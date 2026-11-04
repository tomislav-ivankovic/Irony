const std = @import("std");

pub fn SelfBasedPointer(comptime SelfPointer: type, comptime Self: type, comptime Type: type) type {
    return switch (SelfPointer) {
        *Self => *Type,
        *const Self => *const Type,
        else => @compileError(
            "Expected self to be of type \"" ++
                @typeName(*const Self) ++
                "\" or \"" ++
                @typeName(*Self) ++
                "\" but got: " ++
                @typeName(SelfPointer),
        ),
    };
}

pub fn SelfBasedSlice(comptime SelfPointer: type, comptime Self: type, comptime Element: type) type {
    return switch (SelfPointer) {
        *Self => []Element,
        *const Self => []const Element,
        else => @compileError(
            "Expected self to be of type \"" ++
                @typeName(*const Self) ++
                "\" or \"" ++
                @typeName(*Self) ++
                "\" but got: " ++
                @typeName(SelfPointer),
        ),
    };
}

pub fn SelfBasedSentinelSlice(
    comptime SelfPointer: type,
    comptime Self: type,
    comptime Element: type,
    comptime sentinel: Element,
) type {
    return switch (SelfPointer) {
        *Self => [:sentinel]Element,
        *const Self => [:sentinel]const Element,
        else => @compileError(
            "Expected self to be of type \"" ++
                @typeName(*const Self) ++
                "\" or \"" ++
                @typeName(*Self) ++
                "\" but got: " ++
                @typeName(SelfPointer),
        ),
    };
}

pub fn Partial(comptime Struct: type) type {
    const info = switch (@typeInfo(Struct)) {
        .@"struct" => |info| info,
        else => @compileError("Partial expects a struct type as argument."),
    };
    var partial_field_types: [info.field_names.len]type = undefined;
    var partial_field_attributes: [info.field_names.len]std.builtin.Type.Struct.FieldAttributes = undefined;
    for (info.field_types, info.field_attrs, 0..) |field_type, attr, index| {
        partial_field_types[index] = ?field_type;
        partial_field_attributes[index] = .{
            .default_value_ptr = &@as(?field_type, null),
            .@"comptime" = attr.@"comptime",
        };
    }
    return @Struct(.auto, null, info.field_names, &partial_field_types, &partial_field_attributes);
}

pub fn FieldMap(
    comptime KeysStruct: type,
    comptime Value: type,
    comptime default_value_ptr: ?*const Value,
) type {
    const info = switch (@typeInfo(KeysStruct)) {
        .@"struct" => |info| info,
        else => @compileError("FieldMap expects a struct type as argument."),
    };
    return @Struct(.auto, null, info.field_names, &@splat(Value), &@splat(.{ .default_value_ptr = default_value_ptr }));
}

pub fn areAllFieldsNull(struct_pointer: anytype) bool {
    const Struct = switch (@typeInfo(@TypeOf(struct_pointer))) {
        .pointer => |pointer| pointer.child,
        else => @compileError(
            "The areAllFieldsNull function expects a pointer to struct but provided value is of type: " ++
                @typeName(@TypeOf(struct_pointer)),
        ),
    };
    const info = switch (@typeInfo(Struct)) {
        .@"struct" => |info| info,
        else => @compileError(
            "The areAllFieldsNull function expects a pointer to struct but provided value is of type: " ++
                @typeName(@TypeOf(struct_pointer)),
        ),
    };
    inline for (info.field_names) |field_name| {
        if (@field(struct_pointer, field_name) != null) {
            return false;
        }
    }
    return true;
}

pub fn enumArrayToEnumFieldStruct(
    comptime Enum: type,
    comptime Value: type,
    array: *const std.EnumArray(Enum, Value),
) std.enums.EnumFieldStruct(Enum, Value, null) {
    const info = switch (@typeInfo(Enum)) {
        .@"enum" => |info| info,
        else => @compileError("Expected Enum to be an enum type but got: " ++ @typeName(Enum)),
    };
    var field_struct: std.enums.EnumFieldStruct(Enum, Value, null) = undefined;
    inline for (info.field_names, info.field_values) |field_name, field_value| {
        @field(field_struct, field_name) = array.get(@fromBackingInt(field_value));
    }
    return field_struct;
}

const testing = std.testing;

test "SelfBasedPointer should return a pointer type with same mutability as SelfPointer" {
    try testing.expect(SelfBasedPointer(*const u64, u64, f32) == *const f32);
    try testing.expect(SelfBasedPointer(*u64, u64, f32) == *f32);
}

test "SelfBasedSlice should return a slice type with same mutability as SelfPointer" {
    try testing.expect(SelfBasedSlice(*const u64, u64, f32) == []const f32);
    try testing.expect(SelfBasedSlice(*u64, u64, f32) == []f32);
}

test "SelfBasedSentinelSlice should return a slice type with same mutability as SelfPointer" {
    try testing.expect(SelfBasedSentinelSlice(*const u64, u64, f32, 0) == [:0]const f32);
    try testing.expect(SelfBasedSentinelSlice(*u64, u64, f32, 0) == [:0]f32);
}

test "FieldMap should make every field typed with the specified type" {
    const Struct = struct {
        field_1: u8,
        field_2: u16,
        field_3: u32,
    };
    const Map = FieldMap(Struct, usize, null);
    try testing.expect(@FieldType(Map, "field_1") == usize);
    try testing.expect(@FieldType(Map, "field_2") == usize);
    try testing.expect(@FieldType(Map, "field_3") == usize);
}

test "FieldMap should have correct default values when provided" {
    const Struct = struct {
        field_1: u8,
        field_2: u16,
        field_3: u32,
    };
    const Map = FieldMap(Struct, usize, &123);
    const map = Map{};
    try testing.expectEqual(123, map.field_1);
    try testing.expectEqual(123, map.field_2);
    try testing.expectEqual(123, map.field_3);
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

test "areAllFieldsNull should return true only if all fields of provided struct are null" {
    const Struct = struct {
        field_1: ?u8,
        field_2: ?u16,
        field_3: ?u32,
    };
    const struct_1 = Struct{
        .field_1 = null,
        .field_2 = null,
        .field_3 = null,
    };
    const struct_2 = Struct{
        .field_1 = null,
        .field_2 = 0,
        .field_3 = null,
    };
    try testing.expectEqual(true, areAllFieldsNull(&struct_1));
    try testing.expectEqual(false, areAllFieldsNull(&struct_2));
}

test "enumArrayToEnumFieldStruct should return correct value" {
    const Enum = enum { a, b, c };
    const expected = std.enums.EnumFieldStruct(Enum, u8, null){
        .a = 1,
        .b = 2,
        .c = 3,
    };
    const array = std.EnumArray(Enum, u8).init(expected);
    const actual = enumArrayToEnumFieldStruct(Enum, u8, &array);
    try testing.expectEqual(expected, actual);
}
