const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const Process = @import("process.zig").Process;

pub fn RemoteSlice(comptime Element: type, comptime sentinel: ?Element) type {
    return struct {
        process_handle: w32.HANDLE,
        address: usize,
        len: usize,
        test_allocation: if (builtin.is_test) *u8 else void,

        const Self = @This();

        pub fn create(
            process: *const Process,
            data: if (sentinel) |s| [:s]const Element else []const Element,
        ) !Self {
            const process_handle = process.handle;
            const full_length = if (sentinel != null) data.len + 1 else data.len;
            const size_in_bytes = full_length * @sizeOf(Element);
            const address = w32.VirtualAllocEx(process_handle, null, size_in_bytes, .{
                .COMMIT = 1,
                .RESERVE = 1,
            }, .{ .PAGE_READWRITE = 1 }) orelse return error.OsError;
            errdefer _ = w32.VirtualFreeEx(process_handle, address, 0, .RELEASE);
            const success = w32.WriteProcessMemory(process_handle, address, @ptrCast(data), size_in_bytes, null);
            if (success == 0) {
                return error.OsError;
            }
            return Self{
                .process_handle = process_handle,
                .address = @intFromPtr(address),
                .len = data.len,
                .test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else .{},
            };
        }

        pub fn destroy(self: *const Self) !void {
            const success = w32.VirtualFreeEx(self.process_handle, @ptrFromInt(self.address), 0, .RELEASE);
            if (success == 0) {
                return error.OsError;
            }
            if (builtin.is_test) {
                std.testing.allocator.destroy(self.test_allocation);
            }
        }

        pub fn getSizeInBytes(self: *const Self) usize {
            const full_length = if (sentinel != null) self.len + 1 else self.len;
            return full_length * @sizeOf(Element);
        }
    };
}

const testing = std.testing;
const isMemoryWriteable = @import("memory.zig").isMemoryWriteable;

test "create should allocate memory and copy the data to it" {
    const data = [_]u32{ 1, 2, 3, 4, 5 };
    const remote_slice = try RemoteSlice(u32, null).create(&Process.getCurrent(), &data);
    defer remote_slice.destroy() catch unreachable;
    try testing.expectEqual(true, isMemoryWriteable(remote_slice.address, remote_slice.getSizeInBytes()));
    const pointer: *[data.len]u32 = @ptrFromInt(remote_slice.address);
    try testing.expectEqualSlices(u32, &data, pointer);
}

test "create should copy sentinel value when sentinel value is provided" {
    const data = [_:6]u32{ 1, 2, 3, 4, 5 };
    const remote_slice = try RemoteSlice(u32, 6).create(&Process.getCurrent(), &data);
    defer remote_slice.destroy() catch unreachable;
    try testing.expectEqual(true, isMemoryWriteable(remote_slice.address, remote_slice.getSizeInBytes()));
    const pointer: *[data.len + 1]u32 = @ptrFromInt(remote_slice.address);
    try testing.expectEqualSlices(u32, &[_:0]u32{ 1, 2, 3, 4, 5, 6 }, pointer);
}

test "destroy should free the allocated memory" {
    const data = [_]u32{ 1, 2, 3, 4, 5 };
    const remote_slice = try RemoteSlice(u32, null).create(&Process.getCurrent(), &data);
    try testing.expectEqual(true, isMemoryWriteable(remote_slice.address, remote_slice.getSizeInBytes()));
    try remote_slice.destroy();
    try testing.expectEqual(false, isMemoryWriteable(remote_slice.address, remote_slice.getSizeInBytes()));
}

test "getSizeInBytes should should return the correct value when no sentinel value is provided" {
    const data = [_]u32{ 1, 2, 3, 4, 5 };
    const remote_slice = try RemoteSlice(u32, null).create(&Process.getCurrent(), &data);
    defer remote_slice.destroy() catch unreachable;
    try testing.expectEqual(@sizeOf(@TypeOf(data)), remote_slice.getSizeInBytes());
}

test "getSizeInBytes should should return the correct value when sentinel value is provided" {
    const data = [_:6]u32{ 1, 2, 3, 4, 5 };
    const remote_slice = try RemoteSlice(u32, 6).create(&Process.getCurrent(), &data);
    defer remote_slice.destroy() catch unreachable;
    try testing.expectEqual(@sizeOf(@TypeOf(data)), remote_slice.getSizeInBytes());
}
