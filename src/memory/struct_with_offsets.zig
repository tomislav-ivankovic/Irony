const std = @import("std");

pub const StructWithOffsetsMember = struct {
    name: [:0]const u8,
    type: type,
    offset: ?usize = null,
    default_value_ptr: ?*const anyopaque = null,
};

pub fn StructWithOffsets(size: ?usize, comptime members: []const StructWithOffsetsMember) type {
    var sorted_members: [members.len]StructWithOffsetsMember = undefined;
    for (members, 0..) |member, index| {
        var sorted_member = member;
        if (sorted_member.offset == null) {
            sorted_member.offset = if (index == 0) 0 else sorted_members[index - 1].offset.? + @sizeOf(sorted_member.type);
        }
        sorted_members[index] = sorted_member;
    }
    std.mem.sort(StructWithOffsetsMember, &sorted_members, {}, struct {
        fn isLessThen(_: void, lhs: StructWithOffsetsMember, rhs: StructWithOffsetsMember) bool {
            return lhs.offset.? < rhs.offset.?;
        }
    }.isLessThen);

    var fields_buffer: [2 * sorted_members.len + 1]std.builtin.Type.StructField = undefined;
    var fields_size = 0;
    var current_offset: usize = 0;
    var padding_index: usize = 0;
    for (sorted_members) |member| {
        const member_offset = member.offset.?;
        if (member_offset < current_offset) {
            @compileError(std.fmt.comptimePrint(
                "Unable to create struct with offsets. Struct member \"{s}\" overlaps with other members of the struct.",
                .{member.name},
            ));
        }
        if (member_offset > current_offset) {
            const padding_size = member_offset - current_offset;
            fields_buffer[fields_size] = .{
                .name = std.fmt.comptimePrint("_{}", .{padding_index}),
                .type = [padding_size]u8,
                .default_value_ptr = &([_]u8{0} ** padding_size),
                .is_comptime = false,
                .alignment = 1,
            };
            padding_index += 1;
            fields_size += 1;
        }
        fields_buffer[fields_size] = .{
            .name = member.name,
            .type = member.type,
            .default_value_ptr = member.default_value_ptr,
            .is_comptime = false,
            .alignment = if (member_offset % @alignOf(member.type) == 0) @alignOf(member.type) else 1,
        };
        fields_size += 1;
        current_offset = member_offset + @sizeOf(member.type);
    }

    if (size) |struct_size| {
        if (struct_size < current_offset) {
            @compileError(std.fmt.comptimePrint(
                "Unable to create struct with offsets. Member \"{s}\" exceeds the size boundary of the struct.",
                .{sorted_members[sorted_members.len - 1].name},
            ));
        }
        if (struct_size > current_offset) {
            const padding_size = struct_size - current_offset;
            fields_buffer[fields_size] = .{
                .name = std.fmt.comptimePrint("_{}", .{padding_index}),
                .type = [padding_size]u8,
                .default_value_ptr = &([_]u8{0} ** padding_size),
                .is_comptime = false,
                .alignment = 1,
            };
            padding_index += 1;
            fields_size += 1;
        }
    }

    return @Type(.{ .@"struct" = .{
        .layout = .@"extern",
        .backing_integer = null,
        .fields = fields_buffer[0..fields_size],
        .decls = &.{},
        .is_tuple = false,
    } });
}

const testing = std.testing;

test "should have correct offsets and size when specified offsets and specified size" {
    const Struct = StructWithOffsets(20, &.{
        .{ .name = "field_1", .type = i32, .offset = 4 },
        .{ .name = "field_2", .type = f32, .offset = 12 },
    });
    const s = Struct{
        .field_1 = 1,
        .field_2 = 2.0,
    };
    const struct_address = @intFromPtr(&s);
    const field_1_address = @intFromPtr(&s.field_1);
    const field_2_address = @intFromPtr(&s.field_2);
    try testing.expectEqual(20, @sizeOf(Struct));
    try testing.expectEqual(4, field_1_address - struct_address);
    try testing.expectEqual(12, field_2_address - struct_address);
}

test "should have correct offsets and size when specified offsets and unspecified size" {
    const Struct = StructWithOffsets(null, &.{
        .{ .name = "field_1", .type = i32, .offset = 4 },
        .{ .name = "field_2", .type = f32, .offset = 12 },
    });
    const s = Struct{
        .field_1 = 1,
        .field_2 = 2.0,
    };
    const struct_address = @intFromPtr(&s);
    const field_1_address = @intFromPtr(&s.field_1);
    const field_2_address = @intFromPtr(&s.field_2);
    try testing.expectEqual(16, @sizeOf(Struct));
    try testing.expectEqual(4, field_1_address - struct_address);
    try testing.expectEqual(12, field_2_address - struct_address);
}

test "should have correct offsets and size when unspecified offsets and unspecified size" {
    const Struct = StructWithOffsets(null, &.{
        .{ .name = "field_1", .type = i32 },
        .{ .name = "field_2", .type = f32 },
    });
    const s = Struct{
        .field_1 = 1,
        .field_2 = 2.0,
    };
    const struct_address = @intFromPtr(&s);
    const field_1_address = @intFromPtr(&s.field_1);
    const field_2_address = @intFromPtr(&s.field_2);
    try testing.expectEqual(8, @sizeOf(Struct));
    try testing.expectEqual(0, field_1_address - struct_address);
    try testing.expectEqual(4, field_2_address - struct_address);
}

test "should have correct offsets and size when no space for padding" {
    const Struct = StructWithOffsets(null, &.{
        .{ .name = "field_1", .type = i32, .offset = 0 },
        .{ .name = "field_2", .type = f32, .offset = 4 },
    });
    const s = Struct{
        .field_1 = 1,
        .field_2 = 2.0,
    };
    const struct_address = @intFromPtr(&s);
    const field_1_address = @intFromPtr(&s.field_1);
    const field_2_address = @intFromPtr(&s.field_2);
    try testing.expectEqual(8, @sizeOf(Struct));
    try testing.expectEqual(0, field_1_address - struct_address);
    try testing.expectEqual(4, field_2_address - struct_address);
}

test "should create no padding between members with specified and unspecified offsets" {
    const Struct = StructWithOffsets(null, &.{
        .{ .name = "field_1", .type = i32, .offset = 4 },
        .{ .name = "field_2", .type = f32 },
    });
    const s = Struct{
        .field_1 = 1,
        .field_2 = 2.0,
    };
    const struct_address = @intFromPtr(&s);
    const field_1_address = @intFromPtr(&s.field_1);
    const field_2_address = @intFromPtr(&s.field_2);
    try testing.expectEqual(12, @sizeOf(Struct));
    try testing.expectEqual(4, field_1_address - struct_address);
    try testing.expectEqual(8, field_2_address - struct_address);
}

test "should have correct offsets and size when members are not specified in order" {
    const Struct = StructWithOffsets(null, &.{
        .{ .name = "field_1", .type = i32, .offset = 12 },
        .{ .name = "field_2", .type = f32, .offset = 20 },
        .{ .name = "field_3", .type = u32, .offset = 4 },
    });
    const s = Struct{
        .field_1 = 1,
        .field_2 = 2.0,
        .field_3 = 3,
    };
    const struct_address = @intFromPtr(&s);
    const field_1_address = @intFromPtr(&s.field_1);
    const field_2_address = @intFromPtr(&s.field_2);
    const field_3_address = @intFromPtr(&s.field_3);
    try testing.expectEqual(24, @sizeOf(Struct));
    try testing.expectEqual(12, field_1_address - struct_address);
    try testing.expectEqual(20, field_2_address - struct_address);
    try testing.expectEqual(4, field_3_address - struct_address);
}

test "should have correct size when no members and specified size" {
    const Struct = StructWithOffsets(4, &.{});
    try testing.expectEqual(4, @sizeOf(Struct));
}

test "should have size zero when no members and unspecified size" {
    const Struct = StructWithOffsets(null, &.{});
    try testing.expectEqual(0, @sizeOf(Struct));
}

test "should have correctly working default member values" {
    const Struct = StructWithOffsets(20, &.{
        .{ .name = "field_1", .type = i32, .offset = 4, .default_value_ptr = &@as(i32, 123) },
        .{ .name = "field_2", .type = f32, .offset = 12, .default_value_ptr = &@as(f32, 456.789) },
    });
    const s = Struct{};
    try testing.expectEqual(123, s.field_1);
    try testing.expectEqual(456.789, s.field_2);
}
