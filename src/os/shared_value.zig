const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const os = @import("root.zig");

pub fn SharedValue(comptime Value: type) type {
    return struct {
        handle: w32.HANDLE,
        test_allocation: if (builtin.is_test) *u8 else void,

        const Self = @This();

        pub fn create(name: []const u8) !Self {
            var buffer = [_:0]u16{0} ** os.max_file_path_length;
            const size = getFullName(&buffer, os.ProcessId.getCurrent(), name) catch |err| {
                misc.error_context.append("Failed to get full name.", .{});
                return err;
            };
            const full_name = buffer[0..size :0];
            const handle = w32.CreateFileMappingW(
                w32.INVALID_HANDLE_VALUE,
                null,
                .{ .PAGE_READWRITE = 1 },
                @intCast(@sizeOf(Value) >> 32),
                @intCast(@sizeOf(Value) & 0xFFFFFFFF),
                full_name,
            ) orelse {
                misc.error_context.new("{}", .{os.Error.getLast()});
                misc.error_context.append("CreateFileMappingW returned null.", .{});
                return error.OsError;
            };
            return .{
                .handle = handle,
                .test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {},
            };
        }

        pub fn destroy(self: *const Self) !void {
            return deinit(self);
        }

        pub fn open(process_id: os.ProcessId, name: []const u8, desired_access: w32.FILE_MAP) !Self {
            var buffer = [_:0]u16{0} ** os.max_file_path_length;
            const size = getFullName(&buffer, process_id, name) catch |err| {
                misc.error_context.append("Failed to get full name.", .{});
                return err;
            };
            const full_name = buffer[0..size :0];
            const handle = w32.OpenFileMappingW(@bitCast(desired_access), 0, full_name) orelse {
                misc.error_context.new("{}", .{os.Error.getLast()});
                misc.error_context.append("OpenFileMappingW returned null.", .{});
                return error.OsError;
            };
            return .{
                .handle = handle,
                .test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {},
            };
        }

        pub fn close(self: *const Self) !void {
            return deinit(self);
        }

        pub fn read(self: *const Self) !Value {
            const pointer = w32.MapViewOfFile(self.handle, w32.FILE_MAP_READ, 0, 0, @sizeOf(Value)) orelse {
                misc.error_context.new("{}", .{os.Error.getLast()});
                misc.error_context.append("MapViewOfFile returned null.", .{});
                return error.OsError;
            };
            defer {
                const success = w32.UnmapViewOfFile(pointer);
                if (success == 0) {
                    misc.error_context.new("{}", .{os.Error.getLast()});
                    misc.error_context.append("UnmapViewOfFile returned 0.", .{});
                    misc.error_context.logError(error.OsError);
                }
            }
            const value_pointer: *align(1) Value = @ptrCast(pointer);
            return value_pointer.*;
        }

        pub fn write(self: *const Self, value: Value) !void {
            const pointer = w32.MapViewOfFile(self.handle, w32.FILE_MAP_WRITE, 0, 0, @sizeOf(Value)) orelse {
                misc.error_context.new("{}", .{os.Error.getLast()});
                misc.error_context.append("MapViewOfFile returned null.", .{});
                return error.OsError;
            };
            defer {
                const success = w32.UnmapViewOfFile(pointer);
                if (success == 0) {
                    misc.error_context.new("{}", .{os.Error.getLast()});
                    misc.error_context.append("UnmapViewOfFile returned 0.", .{});
                    misc.error_context.logError(error.OsError);
                }
            }
            const value_pointer: *align(1) Value = @ptrCast(pointer);
            value_pointer.* = value;
        }

        fn getFullName(buffer: *[os.max_file_path_length]u16, process_id: os.ProcessId, name: []const u8) !usize {
            const pid = process_id.raw;
            var utf8_buffer: [os.max_file_path_length]u8 = undefined;
            const utf8_name = std.fmt.bufPrint(&utf8_buffer, "Global\\{}-{s}", .{ pid, name }) catch |err| {
                misc.error_context.new("Failed to construct full name: \"Global\\{}-{s}\"", .{ pid, name });
                return err;
            };
            return std.unicode.utf8ToUtf16Le(buffer, utf8_name) catch |err| {
                misc.error_context.new("Failed to convert \"{s}\" to UTF-16LE.", .{name});
                return err;
            };
        }

        fn deinit(self: *const Self) !void {
            const success = w32.CloseHandle(self.handle);
            if (success == 0) {
                misc.error_context.new("{}", .{os.Error.getLast()});
                misc.error_context.append("CloseHandle returned 0.", .{});
                return error.OsError;
            }
            if (builtin.is_test) {
                std.testing.allocator.destroy(self.test_allocation);
            }
        }
    };
}

const testing = std.testing;

test "opener should read the same value that the creator wrote" {
    const creator = try SharedValue(u32).create("test");
    defer creator.destroy() catch @panic("Failed to destroy shared value.");
    const opener = try SharedValue(u32).open(os.ProcessId.getCurrent(), "test", .{ .READ = 1 });
    defer opener.close() catch @panic("Failed to close shared value.");
    try creator.write(123);
    try testing.expectEqual(123, opener.read());
}

test "creator should read the same value that the opener wrote" {
    const creator = try SharedValue(u32).create("test");
    defer creator.destroy() catch @panic("Failed to destroy shared value.");
    const opener = try SharedValue(u32).open(os.ProcessId.getCurrent(), "test", .{ .WRITE = 1 });
    defer opener.close() catch @panic("Failed to close shared value.");
    try opener.write(123);
    try testing.expectEqual(123, creator.read());
}

test "read should error when opener has no read access" {
    const creator = try SharedValue(u32).create("test");
    defer creator.destroy() catch @panic("Failed to destroy shared value.");
    const opener = try SharedValue(u32).open(os.ProcessId.getCurrent(), "test", .{ .WRITE = 1 });
    defer opener.close() catch @panic("Failed to close shared value.");
    try testing.expectError(error.OsError, opener.read());
}

test "write should error when opener has no write access" {
    const creator = try SharedValue(u32).create("test");
    defer creator.destroy() catch @panic("Failed to destroy shared value.");
    const opener = try SharedValue(u32).open(os.ProcessId.getCurrent(), "test", .{ .READ = 1 });
    defer opener.close() catch @panic("Failed to close shared value.");
    try testing.expectError(error.OsError, opener.write(123));
}
