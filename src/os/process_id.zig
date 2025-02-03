const std = @import("std");
const w32 = @import("win32").everything;
const Process = @import("process.zig").Process;
const pathToFileName = @import("misc.zig").pathToFileName;

pub const ProcessId = struct {
    raw: u32,

    const Self = @This();
    const max_processes = 4096;

    pub fn getCurrent() Self {
        return .{ .raw = w32.GetCurrentProcessId() };
    }

    pub fn findAll() !Iterator {
        var buffer: [max_processes]u32 = undefined;
        var number_of_bytes: u32 = undefined;
        const success = w32.K32EnumProcesses(
            &buffer[0],
            @sizeOf(@TypeOf(buffer)),
            &number_of_bytes,
        );
        if (success == 0) {
            return error.OsError;
        }
        const number_of_elements = number_of_bytes / @sizeOf(u32);
        return .{
            .buffer = buffer,
            .number_of_elements = number_of_elements,
        };
    }

    pub const Iterator = struct {
        buffer: [max_processes]u32,
        number_of_elements: u32,
        index: u32 = 0,

        fn next(self: *Iterator) ?ProcessId {
            if (self.index >= self.number_of_elements or self.index >= max_processes) {
                return null;
            }
            const raw = self.buffer[self.index];
            self.index += 1;
            return .{ .raw = raw };
        }
    };

    pub fn findByFileName(file_name: []const u8) !Self {
        var iterator = try Self.findAll();
        while (iterator.next()) |process_id| {
            var process = Process.open(process_id, .{ .QUERY_LIMITED_INFORMATION = 1 }) catch continue;
            defer process.close() catch unreachable;
            var buffer: [Process.max_file_path]u8 = undefined;
            const size = try process.getFilePath(&buffer);
            const path = buffer[0..size];
            const name = pathToFileName(path);
            if (std.mem.eql(u8, name, file_name)) {
                return process_id;
            }
        }
        return error.NotFound;
    }
};

const testing = std.testing;

test "getCurrent should return process id of the current process" {
    const expected = std.os.windows.GetCurrentProcessId();
    const actual = ProcessId.getCurrent().raw;
    try testing.expectEqual(expected, actual);
}

test "findAll should find current process id" {
    const current = ProcessId.getCurrent();
    var has_current = false;
    var iterator = try ProcessId.findAll();
    while (iterator.next()) |process_id| {
        if (std.meta.eql(process_id, current)) {
            has_current = true;
        }
    }
    try testing.expect(has_current);
}

test "findByFileName should return process id when process exists" {
    const expected = ProcessId.getCurrent();
    const actual = try ProcessId.findByFileName("test.exe");
    try testing.expectEqual(expected, actual);
}

test "findByFileName should error when process does not exist" {
    try testing.expectError(error.NotFound, ProcessId.findByFileName("invalid process name"));
}
