const std = @import("std");
const os = @import("../os/root.zig");

pub const pointer_tag = opaque {};

pub fn Pointer(comptime Type: type) type {
    return extern struct {
        address: usize,

        const Self = @This();
        pub const tag = pointer_tag;

        pub fn toConstPointer(self: *const Self) ?*const Type {
            const is_valid = os.isMemoryReadable(self.address, @sizeOf(Type));
            if (is_valid) {
                return @ptrFromInt(self.address);
            } else {
                return null;
            }
        }

        pub fn toMutablePointer(self: *const Self) ?*Type {
            const is_valid = os.isMemoryWriteable(self.address, @sizeOf(Type));
            if (is_valid) {
                return @ptrFromInt(self.address);
            } else {
                return null;
            }
        }
    };
}

const testing = std.testing;

test "should have same size as a normal pointer" {
    try testing.expectEqual(@sizeOf(*u8), @sizeOf(Pointer(u8)));
}

test "toConstPointer should return a pointer when memory is readable and writeable" {
    var memory_value: i32 = 123;
    const pointer = Pointer(i32){ .address = @intFromPtr(&memory_value) };
    try testing.expectEqual(&memory_value, pointer.toConstPointer());
}

test "toConstPointer should return a pointer when memory is only readable" {
    const memory_value: i32 = 123;
    const pointer = Pointer(i32){ .address = @intFromPtr(&memory_value) };
    try testing.expectEqual(&memory_value, pointer.toConstPointer());
}

test "toConstPointer should return null when memory is not readable" {
    const pointer = Pointer(i32){ .address = std.math.maxInt(usize) - @sizeOf(i32) };
    try testing.expectEqual(null, pointer.toConstPointer());
}

test "toConstPointer should return null when address is null" {
    const pointer = Pointer(i32){ .address = 0 };
    try testing.expectEqual(null, pointer.toConstPointer());
}

test "toMutablePointer should return a pointer when memory is readable and writeable" {
    var memory_value: i32 = 123;
    const pointer = Pointer(i32){ .address = @intFromPtr(&memory_value) };
    try testing.expectEqual(&memory_value, pointer.toMutablePointer());
}

test "toMutablePointer should return null when memory is only readable" {
    const memory_value: i32 = 123;
    const pointer = Pointer(i32){ .address = @intFromPtr(&memory_value) };
    try testing.expectEqual(null, pointer.toMutablePointer());
}

test "toMutablePointer should return null when memory is not readable" {
    const pointer = Pointer(i32){ .address = std.math.maxInt(usize) - @sizeOf(i32) };
    try testing.expectEqual(null, pointer.toMutablePointer());
}

test "toMutablePointer should return null when address is null" {
    const pointer = Pointer(i32){ .address = 0 };
    try testing.expectEqual(null, pointer.toMutablePointer());
}
