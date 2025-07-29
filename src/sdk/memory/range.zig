const std = @import("std");
const os = @import("../os/root.zig");

pub const Range = struct {
    base_address: usize,
    size_in_bytes: usize,

    const Self = @This();

    pub fn fromPointer(pointer: anytype) Self {
        return Self{
            .base_address = @intFromPtr(pointer),
            .size_in_bytes = @sizeOf(@TypeOf(pointer.*)),
        };
    }

    pub fn isReadable(self: *const Self) bool {
        return os.isMemoryReadable(self.base_address, self.size_in_bytes);
    }

    pub fn isWriteable(self: *const Self) bool {
        return os.isMemoryWriteable(self.base_address, self.size_in_bytes);
    }

    pub fn isValid(self: *const Self) bool {
        return os.isMemoryRangeValid(self.base_address, self.size_in_bytes);
    }
};

const testing = std.testing;

test "fromPointer should return correct base address and size" {
    var array = [_]u8{ 0, 1, 2, 3, 4 };
    const memory_range = Range.fromPointer(&array);
    try testing.expectEqual(memory_range.base_address, @intFromPtr(&array));
    try testing.expectEqual(memory_range.size_in_bytes, array.len);
}

test "isReadable should return true when memory is readable and writable" {
    var array = [_]u8{ 0, 1, 2, 3, 4 };
    const memory_range = Range.fromPointer(&array);
    try testing.expectEqual(true, memory_range.isReadable());
}

test "isReadable should return true when memory is only readable" {
    const array = [_]u8{ 0, 1, 2, 3, 4 };
    const memory_range = Range.fromPointer(&array);
    try testing.expectEqual(true, memory_range.isReadable());
}

test "isReadable should return false when memory not readable" {
    const memory_range = Range{
        .base_address = std.math.maxInt(usize) - 5,
        .size_in_bytes = 5,
    };
    try testing.expectEqual(false, memory_range.isReadable());
}

test "isReadable should return false when base address is null" {
    const memory_range = Range{
        .base_address = 0,
        .size_in_bytes = 5,
    };
    try testing.expectEqual(false, memory_range.isReadable());
}

test "isWriteable should return true when memory is readable and writable" {
    var array = [_]u8{ 0, 1, 2, 3, 4 };
    const memory_range = Range.fromPointer(&array);
    try testing.expectEqual(true, memory_range.isWriteable());
}

test "isWriteable should return false when memory is only readable" {
    const array = [_]u8{ 0, 1, 2, 3, 4 };
    const memory_range = Range.fromPointer(&array);
    try testing.expectEqual(false, memory_range.isWriteable());
}

test "isWriteable should return false when memory not readable" {
    const memory_range = Range{
        .base_address = std.math.maxInt(usize) - 5,
        .size_in_bytes = 5,
    };
    try testing.expectEqual(false, memory_range.isWriteable());
}

test "isWriteable should return false when base address is null" {
    const memory_range = Range{
        .base_address = 0,
        .size_in_bytes = 5,
    };
    try testing.expectEqual(false, memory_range.isWriteable());
}

test "isValid should return true when range does not overflow" {
    const memory_range = Range{
        .base_address = 123,
        .size_in_bytes = 456,
    };
    try testing.expectEqual(true, memory_range.isValid());
}

test "isValid should return true when range overflows" {
    const memory_range = Range{
        .base_address = std.math.maxInt(usize) - 5,
        .size_in_bytes = 10,
    };
    try testing.expectEqual(false, memory_range.isValid());
}
