const std = @import("std");
const os = @import("../os/root.zig");

pub const PointerTrail = struct {
    buffer: [max_len]?usize,
    len: usize,

    const Self = @This();
    const max_len = 32;

    pub fn fromArray(array: anytype) Self {
        if (@typeInfo(@TypeOf(array)) != .array) {
            const coerced: [array.len]?usize = array;
            return fromArray(coerced);
        }
        if (array.len > max_len) {
            @compileError(std.fmt.comptimePrint(
                "The provided array with length {} is larger then maximum pointer trail length: {}",
                .{ array.len, max_len },
            ));
        }
        var buffer: [max_len]?usize = undefined;
        for (array, 0..) |element, i| {
            buffer[i] = element;
        }
        return .{ .buffer = buffer, .len = array.len };
    }

    pub fn getOffsets(self: *const Self) []const ?usize {
        return self.buffer[0..self.len];
    }

    pub fn resolve(self: *const Self) ?usize {
        const offsets = self.getOffsets();
        if (offsets.len == 0) {
            return null;
        }
        var current_address: usize = 0;
        for (offsets, 0..) |optional_offset, i| {
            const offset = optional_offset orelse return null;
            const result = @addWithOverflow(current_address, offset);
            const offset_address = result[0];
            const overflow = result[1];
            if (overflow == 1) {
                return null;
            }
            current_address = offset_address;
            if (i == offsets.len - 1) {
                break;
            }
            if (!os.isMemoryReadable(current_address, @sizeOf(usize))) {
                return null;
            }
            const pointer: *align(1) const usize = @ptrFromInt(current_address);
            current_address = pointer.*;
            if (current_address == 0) {
                return null;
            }
        }
        return current_address;
    }
};

const testing = std.testing;

test "resolve should return the memory address that the pointer trail resolves to when the trail is resolvable" {
    const Struct = packed struct { field_1: i32, field_2: i32 };
    const field_1_offset = @offsetOf(Struct, "field_1");
    const field_2_offset = @offsetOf(Struct, "field_2");

    const str = Struct{ .field_1 = 1, .field_2 = 2 };
    const field_1_address = @intFromPtr(&str.field_1);
    const field_2_address = @intFromPtr(&str.field_2);
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);
    const str_address_address_address = @intFromPtr(&str_address_address);

    const trail = PointerTrail.fromArray;
    try testing.expectEqual(0, trail(.{0}).resolve());
    try testing.expectEqual(std.math.maxInt(usize), trail(.{std.math.maxInt(usize)}).resolve());
    try testing.expectEqual(field_1_address, trail(.{str_address + field_1_offset}).resolve());
    try testing.expectEqual(field_2_address, trail(.{str_address + field_2_offset}).resolve());
    try testing.expectEqual(field_1_address, trail(.{ str_address_address, field_1_offset }).resolve());
    try testing.expectEqual(field_2_address, trail(.{ str_address_address, field_2_offset }).resolve());
    try testing.expectEqual(field_1_address, trail(.{ str_address_address_address, 0, field_1_offset }).resolve());
    try testing.expectEqual(field_2_address, trail(.{ str_address_address_address, 0, field_2_offset }).resolve());
}

test "resolve should return null when the pointer trail is incomplete or not resolvable" {
    const Struct = packed struct { field_1: i32, field_2: i32 };
    const field_1_offset = @offsetOf(Struct, "field_1");
    const field_2_offset = @offsetOf(Struct, "field_2");

    const str = Struct{ .field_1 = 1, .field_2 = 2 };
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);

    const trail = PointerTrail.fromArray;
    try testing.expectEqual(null, trail(.{}).resolve());
    try testing.expectEqual(null, trail(.{ 0, field_2_offset }).resolve());
    try testing.expectEqual(null, trail(.{ str_address_address, std.math.maxInt(usize) }).resolve());
    try testing.expectEqual(null, trail(.{null}).resolve());
    try testing.expectEqual(null, trail(.{ str_address_address, null }).resolve());
    try testing.expectEqual(null, trail(.{ str_address_address, field_1_offset, null }).resolve());
    try testing.expectEqual(null, trail(.{ str_address_address, null, field_1_offset }).resolve());
}
