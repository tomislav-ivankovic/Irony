const std = @import("std");

pub const StructWithOffsetsMember = struct {
    name: [:0]const u8,
    type: type,
    offset: ?usize = null,
    default_value_ptr: ?*const anyopaque = null,
};

pub fn StructWithOffsets(size: ?usize, comptime members: []const StructWithOffsetsMember) type {
    var field_names: [2 * members.len + 1][]const u8 = undefined;
    var field_types: [2 * members.len + 1]type = undefined;
    var field_attributes: [2 * members.len + 1]std.builtin.Type.Struct.FieldAttributes = undefined;
    var fields_len = 0;
    var current_offset: usize = 0;
    var padding_index: usize = 0;
    var padding_field_name_buffer: [8]u8 = undefined;
    padding_field_name_buffer[0] = '_';

    for (members) |*member| {
        const member_offset = member.offset orelse current_offset;
        if (member_offset < current_offset) {
            @compileError(std.fmt.comptimePrint(
                "Unable to create struct with offsets. " ++
                    "Struct member \"{s}\" is out of order or overlaps with other members of the struct.",
                .{member.name},
            ));
        }
        if (member_offset > current_offset) {
            const int_len = std.fmt.printInt(padding_field_name_buffer[1..], padding_index, 10, .lower, .{});
            padding_field_name_buffer[int_len + 1] = 0;
            const name_final = padding_field_name_buffer[0..(int_len + 1) :0].*;
            const padding_size = member_offset - current_offset;
            field_names[fields_len] = &name_final;
            field_types[fields_len] = [padding_size]u8;
            field_attributes[fields_len] = .{ .default_value_ptr = &@as([padding_size]u8, @splat(0)) };
            padding_index += 1;
            fields_len += 1;
        }
        if (member_offset % @alignOf(member.type) != 0) {
            @compileError(std.fmt.comptimePrint(
                "Unable to create struct with offsets. " ++
                    "Struct member \"{s}\" is misaligned on offset 0x{X} while type alignment is: {}",
                .{ member.name, member_offset, @alignOf(member.type) },
            ));
        }
        field_names[fields_len] = member.name;
        field_types[fields_len] = member.type;
        field_attributes[fields_len] = .{ .default_value_ptr = member.default_value_ptr };
        fields_len += 1;
        current_offset = member_offset + @sizeOf(member.type);
    }

    if (size) |struct_size| {
        if (struct_size < current_offset) {
            @compileError(std.fmt.comptimePrint(
                "Unable to create struct with offsets. Member \"{s}\" exceeds the size boundary of the struct.",
                .{members[members.len - 1].name},
            ));
        }
        if (struct_size > current_offset) {
            const int_len = std.fmt.printInt(padding_field_name_buffer[1..], padding_index, 10, .lower, .{});
            padding_field_name_buffer[int_len + 1] = 0;
            const name_final = padding_field_name_buffer[0..(int_len + 1) :0].*;
            const padding_size = struct_size - current_offset;
            field_names[fields_len] = &name_final;
            field_types[fields_len] = [padding_size]u8;
            field_attributes[fields_len] = .{ .default_value_ptr = &@as([padding_size]u8, @splat(0)) };
            padding_index += 1;
            fields_len += 1;
        }
    }

    return @Struct(
        .@"extern",
        null,
        field_names[0..fields_len],
        field_types[0..fields_len],
        field_attributes[0..fields_len],
    );
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
