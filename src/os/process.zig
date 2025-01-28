const std = @import("std");
const w32 = @import("win32").everything;
const ProcessId = @import("process_id.zig").ProcessId;

pub const ProcessAccessRights = w32.PROCESS_ACCESS_RIGHTS;

pub const Process = struct {
    id: ProcessId,
    handle: w32.HANDLE,
    is_pseudo_handle: bool,
    is_open: bool,

    const Self = @This();

    pub fn getCurrent() Self {
        return .{
            .id = ProcessId.getCurrent(),
            .handle = w32.GetCurrentProcess() orelse unreachable,
            .is_pseudo_handle = true,
            .is_open = false,
        };
    }

    pub fn open(id: ProcessId, access_rights: ProcessAccessRights) !Self {
        const handle = w32.OpenProcess(
            access_rights,
            0,
            id.raw,
        ) orelse return error.OsError;
        return .{
            .id = id,
            .handle = handle,
            .is_pseudo_handle = false,
            .is_open = true,
        };
    }

    pub fn close(self: *Self) !void {
        if (self.is_pseudo_handle) {
            return error.PseudoHandle;
        }
        if (!self.is_open) {
            return error.AlreadyClosed;
        }
        const success = w32.CloseHandle(self.handle);
        if (success == 0) {
            return error.OsError;
        }
        self.is_open = false;
    }

    pub fn isStillRunning(self: *const Self) !bool {
        var exit_code: u32 = undefined;
        const success = w32.GetExitCodeProcess(self.handle, &exit_code);
        if (success == 0) {
            return error.OsError;
        }
        return exit_code == w32.STILL_ACTIVE;
    }

    pub fn getImageFilePath(self: *const Self, comptime path_buffer_len: comptime_int, path_buffer: *[path_buffer_len]u8) !usize {
        var buffer: [path_buffer_len:0]u16 = undefined;
        const size = w32.K32GetProcessImageFileNameW(self.handle, &buffer, buffer.len);
        if (size == 0) {
            return error.OsError;
        }
        return std.unicode.utf16LeToUtf8(path_buffer, buffer[0..size]);
    }
};

const testing = std.testing;

test "getCurrent should return the current process object" {
    const process = Process.getCurrent();
    try testing.expectEqual(std.os.windows.GetCurrentProcessId(), process.id.raw);
    try testing.expectEqual(std.os.windows.GetCurrentProcess(), process.handle);
    try testing.expectEqual(true, process.is_pseudo_handle);
    try testing.expectEqual(false, process.is_open);
}

test "open should succeed when valid process id" {
    const process_id = ProcessId.getCurrent();
    const access_rights = ProcessAccessRights{
        .QUERY_INFORMATION = 1,
    };
    var process = try Process.open(process_id, access_rights);
    defer process.close() catch unreachable;
    try testing.expectEqual(process_id.raw, process.id.raw);
    try testing.expectEqual(false, process.is_pseudo_handle);
    try testing.expectEqual(true, process.is_open);
}

test "open should error when invalid process id" {
    const process_id = ProcessId{ .raw = std.math.maxInt(u32) };
    const access_rights = ProcessAccessRights{
        .QUERY_INFORMATION = 1,
    };
    try testing.expectError(error.OsError, Process.open(process_id, access_rights));
}

test "close should succeed when process is opened and does not have pseudo handle" {
    const process_id = ProcessId.getCurrent();
    const access_rights = ProcessAccessRights{
        .QUERY_INFORMATION = 1,
    };
    var process = try Process.open(process_id, access_rights);
    try testing.expectEqual(process.id.raw, w32.GetProcessId(process.handle));
    try process.close();
    try testing.expectEqual(0, w32.GetProcessId(process.handle));
}

test "close should error when process is already closed" {
    const process_id = ProcessId.getCurrent();
    const access_rights = ProcessAccessRights{
        .QUERY_INFORMATION = 1,
    };
    var process = try Process.open(process_id, access_rights);
    try process.close();
    try testing.expectError(error.AlreadyClosed, process.close());
}

test "close should error when process has pseudo handle" {
    var process = Process.getCurrent();
    try testing.expectError(error.PseudoHandle, process.close());
}

test "is still running should return true when process is running" {
    const process_id = ProcessId.getCurrent();
    const access_rights = ProcessAccessRights{
        .QUERY_INFORMATION = 1,
    };
    var process = try Process.open(process_id, access_rights);
    defer process.close() catch unreachable;
    const is_still_running = try process.isStillRunning();
    try testing.expectEqual(true, is_still_running);
}

test "get_image_file_path_should_return_correct_value" {
    const process_id = ProcessId.getCurrent();
    const access_rights = ProcessAccessRights{
        .QUERY_INFORMATION = 1,
    };
    var process = try Process.open(process_id, access_rights);
    defer process.close() catch unreachable;
    var buffer: [260:0]u8 = undefined;
    const size = try process.getImageFilePath(buffer.len, &buffer);
    const path = buffer[0..size];
    try testing.expectStringEndsWith(path, "test.exe");
}
