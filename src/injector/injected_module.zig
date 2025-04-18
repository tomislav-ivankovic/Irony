const std = @import("std");
const builtin = @import("builtin");
const os = @import("../os/root.zig");
const misc = @import("../misc/root.zig");

pub const InjectedModule = struct {
    module: os.Module,
    test_allocation: if (builtin.is_test) *u8 else void,

    const Self = @This();

    pub fn inject(process: os.Process, module_path: []const u8) !Self {
        const file_name = os.pathToFileName(module_path);
        if (os.Module.getRemote(process, file_name) catch null) |module| {
            ejectModule(module) catch |err| {
                misc.errorContext().appendFmt("Failed eject already loaded module: {s}", .{file_name});
                return err;
            };
        }
        try injectModule(process, module_path);
        const module = os.Module.getRemote(process, file_name) catch |err| {
            misc.errorContext().appendFmt("Failed get remote module: {s}", .{file_name});
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

    fn injectModule(process: os.Process, module_path: []const u8) !void {
        var buffer = [_:0]u16{0} ** os.max_file_path_length;
        const size = std.unicode.utf8ToUtf16Le(&buffer, module_path) catch |err| {
            misc.errorContext().newFmt("Failed to convert UTF8 string \"{s}\" to UTF16-LE.", .{module_path});
            return err;
        };
        const utf16_module_path = buffer[0..size :0];
        const kernel_module = os.Module.getLocal("kernel32.dll") catch |err| {
            misc.errorContext().append("Failed to get local kernel module: kernel32.dll");
            return err;
        };
        const load_library_address = kernel_module.getProcedureAddress("LoadLibraryW") catch |err| {
            misc.errorContext().append("Failed to get the address of procedure: LoadLibraryW");
            return err;
        };
        const remote_string = os.RemoteSlice(u16, 0).create(process, utf16_module_path) catch |err| {
            misc.errorContext().appendFmt("Failed to create remote slice containing value: {s}", .{module_path});
            return err;
        };
        defer remote_string.destroy() catch |err| {
            misc.errorContext().append("Failed to create destroy remote slice.");
            misc.errorContext().logError(err);
        };
        const remote_thread = os.RemoteThread.spawn(
            &process,
            @ptrFromInt(load_library_address),
            remote_string.address,
        ) catch |err| {
            misc.errorContext().append("Failed to spawn remote thread: LoadLibraryW");
            return err;
        };
        defer remote_thread.clean() catch |err| {
            misc.errorContext().append("Failed to clean remote thread: LoadLibraryW");
            misc.errorContext().logError(err);
        };
        const module_handle_part = remote_thread.join() catch |err| {
            misc.errorContext().append("Failed to join remote thread: LoadLibraryW");
            return err;
        };
        if (module_handle_part == 0) {
            misc.errorContext().new("Remote LoadLibraryW returned 0.");
            return error.RemoteLoadLibraryWFailed;
        }
    }

    fn ejectModule(module: os.Module) !void {
        const kernel_module = os.Module.getLocal("kernel32.dll") catch |err| {
            misc.errorContext().append("Failed to get local kernel module: kernel32.dll");
            return err;
        };
        const free_library_address = kernel_module.getProcedureAddress("FreeLibrary") catch |err| {
            misc.errorContext().append("Failed to get the address of procedure: FreeLibrary");
            return err;
        };
        const remote_thread = os.RemoteThread.spawn(
            &module.process,
            @ptrFromInt(free_library_address),
            @intFromPtr(module.handle),
        ) catch |err| {
            misc.errorContext().append("Failed to spawn remote thread: FreeLibrary");
            return err;
        };
        defer remote_thread.clean() catch |err| {
            misc.errorContext().append("Failed to clean remote thread: FreeLibrary");
            misc.errorContext().logError(err);
        };
        const return_code = remote_thread.join() catch |err| {
            misc.errorContext().append("Failed to join remote thread: FreeLibrary");
            return err;
        };
        if (return_code == 0) {
            misc.errorContext().new("Remote FreeLibrary returned 0.");
            return error.RemoteFreeLibraryFailed;
        }
    }
};

const testing = @import("std").testing;

test "inject should load module into address space" {
    const module_path = try std.fs.path.resolve(testing.allocator, &.{ "test_assets", "test.dll" });
    defer testing.allocator.free(module_path);
    const injected_module = try InjectedModule.inject(os.Process.getCurrent(), module_path);
    defer injected_module.eject() catch @panic("Failed to eject module.");
    _ = try os.Module.getLocal("test.dll");
}

test "eject should unload module from address space" {
    const module_path = try std.fs.path.resolve(testing.allocator, &.{ "test_assets", "test.dll" });
    defer testing.allocator.free(module_path);
    const injected_module = try InjectedModule.inject(os.Process.getCurrent(), module_path);
    try injected_module.eject();
    try testing.expectError(error.OsError, os.Module.getLocal("test.dll"));
}

test "inject should error when invalid module path" {
    try testing.expectError(
        error.RemoteLoadLibraryWFailed,
        InjectedModule.inject(os.Process.getCurrent(), "invalid module path"),
    );
}
