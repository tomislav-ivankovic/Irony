const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const errorContext = @import("../error_context.zig").errorContext;
const os = @import("root.zig");

pub const Process = struct {
    id: os.ProcessId,
    handle: w32.HANDLE,
    test_allocation: if (builtin.is_test) ?*u8 else void,

    const Self = @This();
    pub const AccessRights = w32.PROCESS_ACCESS_RIGHTS;
    pub const max_file_path = 260;

    pub fn getCurrent() Self {
        return .{
            .id = os.ProcessId.getCurrent(),
            .handle = w32.GetCurrentProcess() orelse unreachable,
            .test_allocation = if (builtin.is_test) null else .{},
        };
    }

    pub fn open(id: os.ProcessId, access_rights: AccessRights) !Self {
        const handle = w32.OpenProcess(
            access_rights,
            0,
            id.raw,
        ) orelse {
            errorContext().newFmt(null, "{}", os.OsError.getLast());
            errorContext().append(error.OsError, "OpenProcess returned null.");
            return error.OsError;
        };
        return .{
            .id = id,
            .handle = handle,
            .test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else .{},
        };
    }

    pub fn close(self: *const Self) !void {
        const success = w32.CloseHandle(self.handle);
        if (success == 0) {
            errorContext().newFmt(null, "{}", os.OsError.getLast());
            errorContext().append(error.OsError, "CloseHandle returned 0.");
            return error.OsError;
        }
        if (builtin.is_test) {
            if (self.test_allocation) |allocation| {
                std.testing.allocator.destroy(allocation);
            } else {
                @panic("Close was called on a process constructed with getCurrent. " ++
                    "Close should be called only on processes constructed with the open function.");
            }
        }
    }

    pub fn isStillRunning(self: *const Self) !bool {
        var exit_code: u32 = undefined;
        const success = w32.GetExitCodeProcess(self.handle, &exit_code);
        if (success == 0) {
            errorContext().newFmt(null, "{}", os.OsError.getLast());
            errorContext().append(error.OsError, "GetExitCodeProcess returned 0.");
            return error.OsError;
        }
        return exit_code == w32.STILL_ACTIVE;
    }

    pub fn getFilePath(self: *const Self, path_buffer: *[max_file_path]u8) !usize {
        var buffer: [max_file_path:0]u16 = undefined;
        const size = w32.K32GetProcessImageFileNameW(self.handle, &buffer, buffer.len);
        if (size == 0) {
            errorContext().newFmt(null, "{}", os.OsError.getLast());
            errorContext().append(error.OsError, "K32GetProcessImageFileNameW returned 0.");
            return error.OsError;
        }
        return std.unicode.utf16LeToUtf8(path_buffer, buffer[0..size]) catch |err| {
            errorContext().new(err, "Failed to convert UTF-16LE string to UTF8.");
            return err;
        };
    }
};

const testing = std.testing;

test "getCurrent should return the current process object" {
    const process = Process.getCurrent();
    try testing.expectEqual(std.os.windows.GetCurrentProcessId(), process.id.raw);
    try testing.expectEqual(std.os.windows.GetCurrentProcess(), process.handle);
}

test "open should succeed when valid process id" {
    const process_id = os.ProcessId.getCurrent();
    const access_rights = Process.AccessRights{
        .QUERY_INFORMATION = 1,
    };
    var process = try Process.open(process_id, access_rights);
    defer process.close() catch unreachable;
    try testing.expectEqual(process_id.raw, process.id.raw);
}

test "open should error when invalid process id" {
    const process_id = os.ProcessId{ .raw = std.math.maxInt(u32) };
    const access_rights = Process.AccessRights{
        .QUERY_INFORMATION = 1,
    };
    try testing.expectError(error.OsError, Process.open(process_id, access_rights));
}

test "is still running should return true when process is running" {
    const process_id = os.ProcessId.getCurrent();
    const access_rights = Process.AccessRights{
        .QUERY_INFORMATION = 1,
    };
    var process = try Process.open(process_id, access_rights);
    defer process.close() catch unreachable;
    const is_still_running = try process.isStillRunning();
    try testing.expectEqual(true, is_still_running);
}

test "getFilePath should return correct value" {
    const process_id = os.ProcessId.getCurrent();
    const access_rights = Process.AccessRights{
        .QUERY_INFORMATION = 1,
    };
    var process = try Process.open(process_id, access_rights);
    defer process.close() catch unreachable;
    var buffer: [Process.max_file_path]u8 = undefined;
    const size = try process.getFilePath(&buffer);
    const path = buffer[0..size];
    try testing.expectStringEndsWith(path, "test.exe");
}
