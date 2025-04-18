const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const os = @import("root.zig");

pub const RemoteThread = struct {
    handle: w32.HANDLE,
    test_allocation: if (builtin.is_test) *u8 else void,

    const Self = @This();

    pub fn spawn(
        process: *const os.Process,
        start_routine: *const fn (parameter: usize) callconv(.winapi) u32,
        parameter: usize,
    ) !Self {
        const handle = w32.CreateRemoteThread(
            process.handle,
            null,
            0,
            @ptrCast(start_routine),
            @ptrFromInt(parameter),
            0,
            null,
        ) orelse {
            misc.errorContext().newFmt("{}", .{os.Error.getLast()});
            misc.errorContext().append("CreateRemoteThread returned null.");
            return error.OsError;
        };
        const test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {};
        return Self{ .handle = handle, .test_allocation = test_allocation };
    }

    pub fn clean(self: *const Self) !void {
        const success = w32.CloseHandle(self.handle);
        if (success == 0) {
            misc.errorContext().newFmt("{}", .{os.Error.getLast()});
            misc.errorContext().append("CloseHandle returned 0.");
            return error.OsError;
        }
        if (builtin.is_test) {
            std.testing.allocator.destroy(self.test_allocation);
        }
    }

    pub fn join(self: *const Self) !u32 {
        const return_code = w32.WaitForSingleObject(self.handle, w32.INFINITE);
        if (return_code == @intFromEnum(w32.WAIT_FAILED)) {
            misc.errorContext().newFmt("{}", .{os.Error.getLast()});
            misc.errorContext().appendFmt("WaitForSingleObject returned: {}", .{return_code});
            return error.OsError;
        }
        var exit_code: u32 = undefined;
        const success = w32.GetExitCodeThread(self.handle, &exit_code);
        if (success == 0) {
            misc.errorContext().newFmt("{}", .{os.Error.getLast()});
            misc.errorContext().append("GetExitCodeThread returned 0.");
            return error.OsError;
        }
        return exit_code;
    }
};

const testing = std.testing;

test "should run remote thread and return correct exit code" {
    const startRoutine = struct {
        fn call(parameter: usize) callconv(.winapi) u32 {
            return @intCast(parameter + 1);
        }
    }.call;
    const process = os.Process.getCurrent();
    var remote_thread = try RemoteThread.spawn(&process, startRoutine, 123);
    defer remote_thread.clean() catch @panic("Failed to clean remote thread.");
    const exit_code = try remote_thread.join();
    try testing.expectEqual(124, exit_code);
}
