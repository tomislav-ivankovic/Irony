const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const Process = @import("../os/process.zig").Process;
const Module = @import("../os/module.zig").Module;
const RemoteSlice = @import("../os/remote_slice.zig").RemoteSlice;
const RemoteThread = @import("../os/remote_thread.zig").RemoteThread;
const pathToFileName = @import("../os/misc.zig").pathToFileName;

pub const InjectedModule = struct {
    module: Module,
    test_allocation: if (builtin.is_test) *u8 else void,

    const Self = @This();

    pub fn inject(process: Process, module_path: []const u8) !Self {
        var buffer = [_:0]u16{0} ** Module.max_file_path;
        const size = try std.unicode.utf8ToUtf16Le(&buffer, module_path);
        const utf16_module_path = buffer[0..size :0];
        const kernel_module = try Module.getLocal("kernel32.dll");
        const load_library_address = try kernel_module.getProcedureAddress("LoadLibraryW");
        const remote_string = try RemoteSlice(u16, 0).create(process, utf16_module_path);
        defer remote_string.destroy() catch undefined;
        const remote_thread = try RemoteThread.spawn(&process, @ptrFromInt(load_library_address), remote_string.address);
        defer remote_thread.clean() catch undefined;
        const module_handle_part = try remote_thread.join();
        if (module_handle_part == 0) {
            return error.RemoteLoadLibraryWFailed;
        }
        const file_name = pathToFileName(module_path);
        const module = try Module.getRemote(process, file_name);
        const test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else .{};
        return .{ .module = module, .test_allocation = test_allocation };
    }

    pub fn eject(self: *const Self) !void {
        const kernel_module = try Module.getLocal("kernel32.dll");
        const free_library_address = try kernel_module.getProcedureAddress("FreeLibrary");
        const remote_thread = try RemoteThread.spawn(&self.module.process, @ptrFromInt(free_library_address), @intFromPtr(self.module.handle));
        defer remote_thread.clean() catch undefined;
        const return_code = try remote_thread.join();
        if (return_code == 0) {
            return error.RemoteFreeLibraryFailed;
        }
        if (builtin.is_test) {
            std.testing.allocator.destroy(self.test_allocation);
        }
    }
};

const testing = @import("std").testing;

test "inject should load module into address space" {
    const module_path = try std.fs.path.resolve(testing.allocator, &.{ "test_assets", "test_1.dll" });
    defer testing.allocator.free(module_path);
    const injected_module = try InjectedModule.inject(Process.getCurrent(), module_path);
    defer injected_module.eject() catch undefined;
    _ = try Module.getLocal("test_1.dll");
}

test "eject should unload module from address space" {
    const module_path = try std.fs.path.resolve(testing.allocator, &.{ "test_assets", "test_2.dll" });
    defer testing.allocator.free(module_path);
    const injected_module = try InjectedModule.inject(Process.getCurrent(), module_path);
    try injected_module.eject();
    try testing.expectError(error.OsError, Module.getLocal("test_2.dll"));
}

test "inject should error when invalid module path" {
    try testing.expectError(error.RemoteLoadLibraryWFailed, InjectedModule.inject(Process.getCurrent(), "invalid module path"));
}
