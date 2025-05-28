const std = @import("std");
const misc = @import("../misc/root.zig");
const os = @import("../os/root.zig");

pub fn dereferenceMisaligned(comptime Type: type, address: usize) !Type {
    if (!os.isMemoryReadable(address, @sizeOf(usize))) {
        misc.error_context.new("Memory address 0x{X} is not readable.", .{address});
        return error.NotReadable;
    }
    const pointer: *align(1) Type = @ptrFromInt(address);
    return pointer.*;
}

pub fn resolveRelativeOffset(comptime Offset: type, address: usize) !usize {
    if (Offset != u8 and Offset != u16 and Offset != u32 and Offset != u64) {
        @compileError("Unsupported offset type: " ++ @typeName(Offset));
    }
    if (!os.isMemoryReadable(address, @sizeOf(Offset))) {
        misc.error_context.new("Memory address 0x{X} is not readable.", .{address});
        return error.NotReadable;
    }
    const pointer: *align(1) Offset = @ptrFromInt(address);
    const offset = pointer.*;
    const addition_1 = @addWithOverflow(address, @sizeOf(Offset));
    if (addition_1[1] == 1) {
        misc.error_context.new("Relative offset overflew the address space.", .{});
        return error.Overflow;
    }
    const addition_2 = @addWithOverflow(addition_1[0], offset);
    if (addition_2[1] == 1) {
        misc.error_context.new("Relative offset overflew the address space.", .{});
        return error.Overflow;
    }
    return addition_2[0];
}

const testing = std.testing;

test "dereferenceMisaligned should return correct value when address is aligned and memory is readable" {
    const value: i32 = 123;
    const address = @intFromPtr(&value);
    const dereferenced = dereferenceMisaligned(i32, address);
    try testing.expectEqual(123, dereferenced);
}

test "dereferenceMisaligned should return correct value when address is misaligned and memory is readable" {
    const value: u64 = 0xFF00;
    const address = @intFromPtr(&value) + 1;
    const dereferenced = dereferenceMisaligned(u32, address);
    try testing.expectEqual(0xFF, dereferenced);
}

test "dereferenceMisaligned should return error when memory is not readable" {
    try testing.expectError(error.NotReadable, dereferenceMisaligned(u64, 0));
}

test "resolveRelativeOffset should return correct value when u8 offset" {
    const data = [_]u8{ 3, 1, 2, 3, 4 };
    const offset_address = resolveRelativeOffset(u8, @intFromPtr(&data[0]));
    try testing.expectEqual(@intFromPtr(&data[data.len - 1]), offset_address);
}

test "resolveRelativeOffset should return correct value when u16 offset" {
    const data = [_]u8{ 3, 0, 1, 2, 3, 4 };
    const offset_address = resolveRelativeOffset(u16, @intFromPtr(&data[0]));
    try testing.expectEqual(@intFromPtr(&data[data.len - 1]), offset_address);
}

test "resolveRelativeOffset should return correct value when u32 offset" {
    const data = [_]u8{ 3, 0, 0, 0, 1, 2, 3, 4 };
    const offset_address = resolveRelativeOffset(u32, @intFromPtr(&data[0]));
    try testing.expectEqual(@intFromPtr(&data[data.len - 1]), offset_address);
}

test "resolveRelativeOffset should return correct value when u64 offset" {
    const data = [_]u8{ 3, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4 };
    const offset_address = resolveRelativeOffset(u64, @intFromPtr(&data[0]));
    try testing.expectEqual(@intFromPtr(&data[data.len - 1]), offset_address);
}

test "resolveRelativeOffset should error when offset is not readable" {
    try testing.expectError(error.NotReadable, resolveRelativeOffset(u64, 0));
}

test "resolveRelativeOffset should error when offset overflows the address space" {
    const offset: u64 = std.math.maxInt(u64);
    try testing.expectError(error.Overflow, resolveRelativeOffset(u64, @intFromPtr(&offset)));
}
