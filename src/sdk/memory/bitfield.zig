const std = @import("std");

pub fn BitfieldMember(comptime BackingInt: type) type {
    return struct {
        name: [:0]const u8,
        backing_value: BackingInt,
        default_value: bool = false,
    };
}

pub fn Bitfield(comptime BackingInt: type, comptime members: []const BitfieldMember(BackingInt)) type {
    @setEvalBranchQuota(3000);

    const number_of_bits = @bitSizeOf(BackingInt);
    var field_names: [number_of_bits][]const u8 = undefined;
    var field_attributes: [number_of_bits]std.builtin.Type.Struct.FieldAttributes = undefined;
    var next_member_index: usize = 0;
    var padding_field_name_buffer: [8]u8 = undefined;
    padding_field_name_buffer[0] = '_';

    for (&field_names, &field_attributes, 0..) |*field_name, *field_attribute, bit_index| {
        const backing_value = 1 << bit_index;
        const next_member: ?*const BitfieldMember(BackingInt) = switch (next_member_index < members.len) {
            true => &members[next_member_index],
            else => null,
        };
        if (next_member) |member| {
            if (member.backing_value == backing_value) {
                field_name.* = member.name;
                field_attribute.* = .{ .default_value_ptr = if (member.default_value == true) &true else &false };
                next_member_index += 1;
                continue;
            } else if (member.backing_value < backing_value) {
                if (std.math.isPowerOfTwo(next_member.?.backing_value)) {
                    @compileError(std.fmt.comptimePrint(
                        "Failed to create a bitfield type. Member \"{s}\" is out of order.",
                        .{member.name},
                    ));
                } else {
                    @compileError(std.fmt.comptimePrint(
                        "Failed to create a bitfield type. Member \"{s}\" has non power of two backing value: {}",
                        .{ member.name, member.backing_value },
                    ));
                }
            }
        }
        const int_len = std.fmt.printInt(padding_field_name_buffer[1..], bit_index, 10, .lower, .{});
        padding_field_name_buffer[int_len + 1] = 0;
        const name_final = padding_field_name_buffer[0..(int_len + 1) :0].*;
        field_name.* = &name_final;
        field_attribute.* = .{ .default_value_ptr = &false };
    }

    return @Struct(.@"packed", BackingInt, &field_names, &@splat(bool), &field_attributes);
}

const testing = std.testing;

test "should have same size as the backing integer" {
    try testing.expectEqual(@sizeOf(u8), @sizeOf(Bitfield(u8, &.{})));
    try testing.expectEqual(@sizeOf(u16), @sizeOf(Bitfield(u16, &.{})));
    try testing.expectEqual(@sizeOf(u32), @sizeOf(Bitfield(u32, &.{})));
    try testing.expectEqual(@sizeOf(u64), @sizeOf(Bitfield(u64, &.{})));
}

test "should place members at correct bits" {
    const Bits = Bitfield(u16, &.{
        .{ .name = "bit_3", .backing_value = 8 },
        .{ .name = "bit_6", .backing_value = 64 },
        .{ .name = "bit_10", .backing_value = 1024 },
    });
    try testing.expectEqual(8, @backingInt(Bits{ .bit_3 = true }));
    try testing.expectEqual(64, @backingInt(Bits{ .bit_6 = true }));
    try testing.expectEqual(1024, @backingInt(Bits{ .bit_10 = true }));
}

test "should have correctly working default member values" {
    const Bits = Bitfield(u16, &.{
        .{ .name = "bit_3", .backing_value = 8, .default_value = false },
        .{ .name = "bit_6", .backing_value = 64 },
        .{ .name = "bit_10", .backing_value = 1024, .default_value = true },
    });
    try testing.expectEqual(1024, @backingInt(Bits{}));
}
