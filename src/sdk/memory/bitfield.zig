const std = @import("std");

pub const BitfieldMember = struct {
    name: [:0]const u8,
    position: usize,
    default_value: bool = false,
};

pub fn Bitfield(comptime backing_integer: type, comptime members: []const BitfieldMember) type {
    const number_of_bits = @bitSizeOf(backing_integer);

    for (members) |*member| {
        if (member.position >= number_of_bits) {
            @compileError(std.fmt.comptimePrint(
                "Failed to create bitfield. Member \"{s}\" on position {} exceeds the backing type size: {}",
                .{ member.name, member.position, number_of_bits },
            ));
        }
    }

    var fields: [number_of_bits]std.builtin.Type.StructField = undefined;
    for (0..number_of_bits) |bit| {
        var member_at_bit: ?*const BitfieldMember = null;
        for (members) |*member| {
            if (member.position != bit) {
                continue;
            }
            if (member_at_bit != null) {
                @compileError(std.fmt.comptimePrint(
                    "Failed to create bitfield. Bit at position {} has multiple members.",
                    .{bit},
                ));
            }
            member_at_bit = member;
        }
        fields[bit] = if (member_at_bit) |member| .{
            .name = member.name,
            .type = bool,
            .default_value_ptr = if (member.default_value == true) &true else &false,
            .is_comptime = false,
            .alignment = 0,
        } else .{
            .name = std.fmt.comptimePrint("_{}", .{bit}),
            .type = bool,
            .default_value_ptr = &false,
            .is_comptime = false,
            .alignment = 0,
        };
    }

    return @Type(.{ .@"struct" = .{
        .layout = .@"packed",
        .backing_integer = backing_integer,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

const testing = std.testing;

test "should have same size as the backing integer" {
    try testing.expectEqual(@sizeOf(u8), @sizeOf(Bitfield(u8, &.{})));
    try testing.expectEqual(@sizeOf(u16), @sizeOf(Bitfield(u16, &.{})));
    try testing.expectEqual(@sizeOf(u32), @sizeOf(Bitfield(u32, &.{})));
    try testing.expectEqual(@sizeOf(u64), @sizeOf(Bitfield(u64, &.{})));
    try testing.expectEqual(@sizeOf(u128), @sizeOf(Bitfield(u128, &.{})));
}

test "should place members at correct bits" {
    const Bits = Bitfield(u16, &.{
        .{ .name = "bit_3", .position = 3 },
        .{ .name = "bit_10", .position = 10 },
        .{ .name = "bit_6", .position = 6 },
    });
    const bit_3: u16 = @bitCast(Bits{ .bit_3 = true });
    const bit_10: u16 = @bitCast(Bits{ .bit_10 = true });
    const bit_6: u16 = @bitCast(Bits{ .bit_6 = true });
    try testing.expectEqual(8, bit_3);
    try testing.expectEqual(1024, bit_10);
    try testing.expectEqual(64, bit_6);
}

test "should have correctly working default member values" {
    const Bits = Bitfield(u16, &.{
        .{ .name = "bit_3", .position = 3, .default_value = false },
        .{ .name = "bit_10", .position = 10, .default_value = true },
        .{ .name = "bit_6", .position = 6 },
    });
    const default_value: u16 = @bitCast(Bits{});
    try testing.expectEqual(1024, default_value);
}
