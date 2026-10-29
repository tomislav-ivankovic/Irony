const std = @import("std");
const builtin = @import("builtin");
const sdk = @import("../sdk/root.zig");

pub const InjectedModule = struct {
    module: sdk.os.Module,
    test_allocation: if (builtin.is_test) *u8 else void,

    const Self = @This();

    pub fn inject(process: sdk.os.Process, module_path: []const u8) !Self {
        const file_name = sdk.os.pathToFileName(module_path);
        if (sdk.os.Module.getRemote(process, file_name) catch null) |module| {
            ejectModule(module) catch |err| {
                sdk.misc.error_context.append("Failed eject already loaded module: {s}", .{file_name});
                return err;
            };
        }
        try injectModule(process, module_path);
        const module = sdk.os.Module.getRemote(process, file_name) catch |err| {
            sdk.misc.error_context.append("Failed get remote module: {s}", .{file_name});
            return err;
        };
        return .{
            .module = module,
            .test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {},
        };
    }

    pub fn eject(self: *const Self) !void {
        try ejectModule(self.module);
        if (builtin.is_test) {
            std.testing.allocator.destroy(self.test_allocation);
        }
    }

    fn injectModule(process: sdk.os.Process, module_path: []const u8) !void {
        var buffer: [sdk.os.max_file_path_length:0]u16 = @splat(0);
        const size = std.unicode.utf8ToUtf16Le(&buffer, module_path) catch |err| {
            sdk.misc.error_context.new("Failed to convert UTF8 string \"{s}\" to UTF16-LE.", .{module_path});
            return err;
        };
        const utf16_module_path = buffer[0..size :0];
        const kernel_module = sdk.os.Module.getLocal("kernel32.dll") catch |err| {
            sdk.misc.error_context.append("Failed to get local kernel module: kernel32.dll", .{});
            return err;
        };
        const load_library_address = kernel_module.getProcedureAddress("LoadLibraryW") catch |err| {
            sdk.misc.error_context.append("Failed to get the address of procedure: LoadLibraryW", .{});
            return err;
        };
        const remote_string = sdk.os.RemoteSlice(u16, 0).create(process, utf16_module_path) catch |err| {
            sdk.misc.error_context.append("Failed to create remote slice containing value: {s}", .{module_path});
            return err;
        };
        defer remote_string.destroy() catch |err| {
            sdk.misc.error_context.append("Failed to create destroy remote slice.", .{});
            sdk.misc.error_context.logError(err);
        };
        const remote_thread = sdk.os.RemoteThread.spawn(
            &process,
            @ptrFromInt(load_library_address),
            remote_string.address,
        ) catch |err| {
            sdk.misc.error_context.append("Failed to spawn remote thread: LoadLibraryW", .{});
            return err;
        };
        defer remote_thread.clean() catch |err| {
            sdk.misc.error_context.append("Failed to clean remote thread: LoadLibraryW", .{});
            sdk.misc.error_context.logError(err);
        };
        const module_handle_part = remote_thread.join() catch |err| {
            sdk.misc.error_context.append("Failed to join remote thread: LoadLibraryW", .{});
            return err;
        };
        if (module_handle_part == 0) {
            sdk.misc.error_context.new("Remote LoadLibraryW returned 0.", .{});
            return error.RemoteLoadLibraryWFailed;
        }
    }

    fn ejectModule(module: sdk.os.Module) !void {
        gracefullyEjectModule(module) catch |err_1| {
            if (!builtin.is_test) {
                sdk.misc.error_context.append("Failed to gracefully eject. Continuing with forceful ejection. ", .{});
                sdk.misc.error_context.logWarning(err_1);
            }
            forcefullyEjectModule(module) catch |err_2| {
                sdk.misc.error_context.append("Failed to forcefully eject module.", .{});
                return err_2;
            };
        };
    }

    fn gracefullyEjectModule(module: sdk.os.Module) !void {
        const shared_value = sdk.os.SharedValue(usize).open(
            module.process.id,
            "irony-shutdown-routine",
            .{ .READ = 1 },
        ) catch |err| {
            sdk.misc.error_context.append("Failed to open shutdown routine shared value.", .{});
            return err;
        };
        defer shared_value.close() catch |err| {
            sdk.misc.error_context.append("Failed to close shutdown routine shared value.", .{});
            sdk.misc.error_context.logError(err);
        };
        const shutdown_routine_address = shared_value.read() catch |err| {
            sdk.misc.error_context.append("Failed to read shutdown routine shared value.", .{});
            return err;
        };
        const remote_thread = sdk.os.RemoteThread.spawn(
            &module.process,
            @ptrFromInt(shutdown_routine_address),
            0,
        ) catch |err| {
            sdk.misc.error_context.append("Failed to spawn shutdown routine remote thread.", .{});
            return err;
        };
        defer remote_thread.clean() catch |err| {
            sdk.misc.error_context.append("Failed to clean shutdown routine remote thread.", .{});
            sdk.misc.error_context.logError(err);
        };
        _ = remote_thread.join() catch |err| {
            sdk.misc.error_context.append("Failed to join shutdown routine remote thread.", .{});
            return err;
        };
    }

    fn forcefullyEjectModule(module: sdk.os.Module) !void {
        const kernel_module = sdk.os.Module.getLocal("kernel32.dll") catch |err| {
            sdk.misc.error_context.append("Failed to get local kernel module: kernel32.dll", .{});
            return err;
        };
        const free_library_address = kernel_module.getProcedureAddress("FreeLibrary") catch |err| {
            sdk.misc.error_context.append("Failed to get the address of procedure: FreeLibrary", .{});
            return err;
        };
        const remote_thread = sdk.os.RemoteThread.spawn(
            &module.process,
            @ptrFromInt(free_library_address),
            @intFromPtr(module.handle),
        ) catch |err| {
            sdk.misc.error_context.append("Failed to spawn remote thread: FreeLibrary", .{});
            return err;
        };
        defer remote_thread.clean() catch |err| {
            sdk.misc.error_context.append("Failed to clean remote thread: FreeLibrary", .{});
            sdk.misc.error_context.logError(err);
        };
        const return_code = remote_thread.join() catch |err| {
            sdk.misc.error_context.append("Failed to join remote thread: FreeLibrary", .{});
            return err;
        };
        if (return_code == 0) {
            sdk.misc.error_context.new("Remote FreeLibrary returned 0.", .{});
            return error.RemoteFreeLibraryFailed;
        }
    }
};

const testing = @import("std").testing;

test "inject should load module into address space" {
    const injected_module = try InjectedModule.inject(sdk.os.Process.getCurrent(), "test.dll");
    defer injected_module.eject() catch @panic("Failed to eject module.");
    _ = try sdk.os.Module.getLocal("test.dll");
}

test "eject should unload module from address space" {
    const injected_module = try InjectedModule.inject(sdk.os.Process.getCurrent(), "test.dll");
    try injected_module.eject();
    try testing.expectError(error.OsError, sdk.os.Module.getLocal("test.dll"));
}

test "inject should error when invalid module path" {
    try testing.expectError(
        error.RemoteLoadLibraryWFailed,
        InjectedModule.inject(sdk.os.Process.getCurrent(), "invalid module path"),
    );
}
