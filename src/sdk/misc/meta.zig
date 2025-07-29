const std = @import("std");

pub fn Partial(comptime Struct: type) type {
    const fields: []const std.builtin.Type.StructField = switch (@typeInfo(Struct)) {
        .@"struct" => |info| info.fields,
        else => @compileError("Partial expects a struct type as argument."),
    };
    var partial_fields: [fields.len]std.builtin.Type.StructField = undefined;
    for (fields, 0..) |*field, index| {
        const optional = std.builtin.Type.Optional{ .child = field.type };
        const OptionalType = @Type(.{ .optional = optional });
        partial_fields[index] = .{
            .name = field.name,
            .type = OptionalType,
            .default_value_ptr = &@as(OptionalType, null),
            .is_comptime = field.is_comptime,
            .alignment = @alignOf(OptionalType),
        };
    }
    const partial_struct = std.builtin.Type.Struct{
        .layout = .auto,
        .backing_integer = null,
        .fields = &partial_fields,
        .decls = &.{},
        .is_tuple = false,
    };
    return @Type(.{ .@"struct" = partial_struct });
}

pub fn FieldMap(comptime KeysStruct: type, comptime Value: type) type {
    const key_fields: []const std.builtin.Type.StructField = switch (@typeInfo(KeysStruct)) {
        .@"struct" => |info| info.fields,
        else => @compileError("FieldMap expects a struct type as argument."),
    };
    var map_fields: [key_fields.len]std.builtin.Type.StructField = undefined;
    for (key_fields, 0..) |*field, index| {
        map_fields[index] = .{
            .name = field.name,
            .type = Value,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(Value),
        };
    }
    const map_struct = std.builtin.Type.Struct{
        .layout = .auto,
        .backing_integer = null,
        .fields = &map_fields,
        .decls = &.{},
        .is_tuple = false,
    };
    return @Type(.{ .@"struct" = map_struct });
}

const testing = std.testing;

test "FieldMap should make every field typed with the specified type" {
    const Struct = struct {
        field_1: u8,
        field_2: u16,
        field_3: u32,
    };
    const Map = FieldMap(Struct, usize);
    try testing.expect(@FieldType(Map, "field_1") == usize);
    try testing.expect(@FieldType(Map, "field_2") == usize);
    try testing.expect(@FieldType(Map, "field_3") == usize);
}

test "Partial should make every field optional" {
    const Struct = struct {
        field_1: u8,
        field_2: u16,
        field_3: u32,
    };
    const PartialStruct = Partial(Struct);
    try testing.expect(@FieldType(PartialStruct, "field_1") == ?u8);
    try testing.expect(@FieldType(PartialStruct, "field_2") == ?u16);
    try testing.expect(@FieldType(PartialStruct, "field_3") == ?u32);
}

test "Partial should make every field's default value null" {
    const Struct = struct {
        field_1: u8,
        field_2: u16,
        field_3: u32,
    };
    const partial: Partial(Struct) = .{};
    try testing.expectEqual(null, partial.field_1);
    try testing.expectEqual(null, partial.field_2);
    try testing.expectEqual(null, partial.field_3);
}
