const std = @import("std");
const w32 = @import("win32").everything;
const Process = @import("process.zig").Process;

pub const RemoteThread = struct {
    handle: w32.HANDLE,
    is_handle_open: bool,

    const Self = @This();

    pub fn spawn(
        process: *const Process,
        start_routine: *const fn (parameter: usize) u32,
        parameter: usize,
    ) !Self {
        const handle = w32.CreateRemoteThread(process.handle, null, 0, @ptrCast(start_routine), @ptrFromInt(parameter), 0, null) orelse return error.OsError;
        return Self{ .handle = handle, .is_handle_open = true };
    }

    pub fn clean(self: *Self) !void {
        if (!self.is_handle_open) {
            return error.AlreadyCleaned;
        }
        const success = w32.CloseHandle(self.handle);
        if (success == 0) {
            return error.OsError;
        }
        self.is_handle_open = false;
    }

    pub fn join(self: *const Self) !u32 {
        const return_code = w32.WaitForSingleObject(self.handle, w32.INFINITE);
        if (return_code == @intFromEnum(w32.WAIT_FAILED)) {
            return error.OsError;
        }
        var exit_code: u32 = undefined;
        const success = w32.GetExitCodeThread(self.handle, &exit_code);
        if (success == 0) {
            return error.OsError;
        }
        return exit_code;
    }
};

const testing = std.testing;

test "should run remote thread and return correct exit code" {
    const startRoutine = struct {
        fn call(parameter: usize) u32 {
            return @intCast(parameter + 1);
        }
    }.call;
    const process = Process.getCurrent();
    var remote_thread = try RemoteThread.spawn(&process, startRoutine, 123);
    defer remote_thread.clean() catch unreachable;
    const exit_code = try remote_thread.join();
    try testing.expectEqual(124, exit_code);
}
