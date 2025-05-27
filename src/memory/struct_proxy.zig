const std = @import("std");
const os = @import("../os/root.zig");
const misc = @import("../misc/root.zig");
const memory = @import("root.zig");

pub const struct_proxy_tag = opaque {};

pub fn StructProxy(comptime Struct: type) type {
    const struct_fields = switch (@typeInfo(Struct)) {
        .@"struct" => |info| info.fields,
        else => @compileError("StructProxy expects a struct type as argument."),
    };
    return struct {
        base_trail: memory.PointerTrail,
        field_offsets: misc.FieldMap(Struct, ?usize),

        const Self = @This();
        pub const tag = struct_proxy_tag;

        pub fn findBaseAddress(self: *const Self) ?usize {
            return self.base_trail.resolve();
        }

        pub fn findFieldAddress(self: *const Self, comptime field_name: []const u8) ?usize {
            const base_address = self.findBaseAddress() orelse return null;
            const field_offset = @field(self.field_offsets, field_name) orelse return null;
            const add_result = @addWithOverflow(base_address, field_offset);
            if (add_result[1] == 1) {
                return null;
            }
            return add_result[0];
        }

        pub fn findConstFieldPointer(
            self: *const Self,
            comptime field_name: []const u8,
        ) ?*const @FieldType(Struct, field_name) {
            const address = self.findFieldAddress(field_name) orelse return null;
            const size = @sizeOf(@FieldType(Struct, field_name));
            if (!os.isMemoryReadable(address, size)) {
                return null;
            }
            return @ptrFromInt(address);
        }

        pub fn findMutableFieldPointer(
            self: *const Self,
            comptime field_name: []const u8,
        ) ?*@FieldType(Struct, field_name) {
            const address = self.findFieldAddress(field_name) orelse return null;
            const size = @sizeOf(@FieldType(Struct, field_name));
            if (!os.isMemoryWriteable(address, size)) {
                return null;
            }
            return @ptrFromInt(address);
        }

        pub fn takeStaticCopy(self: *const Self) ?Struct {
            var static_copy: Struct = undefined;
            inline for (struct_fields) |*field| {
                const value_pointer = self.findConstFieldPointer(field.name) orelse return null;
                @field(static_copy, field.name) = value_pointer.*;
            }
            return static_copy;
        }
    };
}

const testing = std.testing;

test "findBaseAddress should return a value when base trail is resolvable" {
    const Struct = struct {};
    const proxy = StructProxy(Struct){
        .base_trail = .fromArray(.{12345}),
        .field_offsets = .{},
    };
    try testing.expectEqual(12345, proxy.findBaseAddress());
}

test "findBaseAddress should return null when base trail is not resolvable" {
    const Struct = struct {};
    const proxy = StructProxy(Struct){
        .base_trail = .fromArray(.{ 0, 100 }),
        .field_offsets = .{},
    };
    try testing.expectEqual(null, proxy.findBaseAddress());
}

test "findFieldAddress should return a value when findBaseAddress succeeds and field offset exists and does not overflow" {
    const Struct = struct { field_1: u8, field_2: u16, field_3: u32 };
    const proxy = StructProxy(Struct){
        .base_trail = .fromArray(.{100}),
        .field_offsets = .{
            .field_1 = 10,
            .field_2 = 20,
            .field_3 = 30,
        },
    };
    try testing.expectEqual(110, proxy.findFieldAddress("field_1"));
    try testing.expectEqual(120, proxy.findFieldAddress("field_2"));
    try testing.expectEqual(130, proxy.findFieldAddress("field_3"));
}

test "findFieldAddress should return null when findBaseAddress fails or field offset is null or overflows" {
    const Struct = struct { field: u8 };
    const proxy_1 = StructProxy(Struct){
        .base_trail = .fromArray(.{ 0, 100 }),
        .field_offsets = .{ .field = 10 },
    };
    const proxy_2 = StructProxy(Struct){
        .base_trail = .fromArray(.{100}),
        .field_offsets = .{ .field = null },
    };
    const proxy_3 = StructProxy(Struct){
        .base_trail = .fromArray(.{100}),
        .field_offsets = .{ .field = std.math.maxInt(usize) },
    };
    try testing.expectEqual(null, proxy_1.findFieldAddress("field"));
    try testing.expectEqual(null, proxy_2.findFieldAddress("field"));
    try testing.expectEqual(null, proxy_3.findFieldAddress("field"));
}

test "findConstFieldPointer should return a pointer when findFieldAddress succeeds and memory is readable" {
    const Struct = struct { field_1: u8, field_2: u16, field_3: u32 };
    const value = Struct{ .field_1 = 1, .field_2 = 2, .field_3 = 3 };
    const proxy = StructProxy(Struct){
        .base_trail = .fromArray(.{@intFromPtr(&value)}),
        .field_offsets = .{
            .field_1 = @offsetOf(Struct, "field_1"),
            .field_2 = @offsetOf(Struct, "field_2"),
            .field_3 = @offsetOf(Struct, "field_3"),
        },
    };
    try testing.expectEqual(&value.field_1, proxy.findConstFieldPointer("field_1"));
    try testing.expectEqual(&value.field_2, proxy.findConstFieldPointer("field_2"));
    try testing.expectEqual(&value.field_3, proxy.findConstFieldPointer("field_3"));
}

test "findConstFieldPointer should return null when findFieldAddress fails or memory is not readable" {
    const Struct = struct { field: u8 };
    const value = Struct{ .field = 1 };
    const proxy_1 = StructProxy(Struct){
        .base_trail = .fromArray(.{ 0, 100 }),
        .field_offsets = .{ .field = 0 },
    };
    const proxy_2 = StructProxy(Struct){
        .base_trail = .fromArray(.{@intFromPtr(&value)}),
        .field_offsets = .{ .field = std.math.maxInt(usize) },
    };
    const proxy_3 = StructProxy(Struct){
        .base_trail = .fromArray(.{0}),
        .field_offsets = .{ .field = 0 },
    };
    try testing.expectEqual(null, proxy_1.findConstFieldPointer("field"));
    try testing.expectEqual(null, proxy_2.findConstFieldPointer("field"));
    try testing.expectEqual(null, proxy_3.findConstFieldPointer("field"));
}

test "findMutableFieldPointer should return a pointer when findFieldAddress succeeds and memory is writeable" {
    const Struct = struct { field_1: u8, field_2: u16, field_3: u32 };
    var value = Struct{ .field_1 = 1, .field_2 = 2, .field_3 = 3 };
    const proxy = StructProxy(Struct){
        .base_trail = .fromArray(.{@intFromPtr(&value)}),
        .field_offsets = .{
            .field_1 = @offsetOf(Struct, "field_1"),
            .field_2 = @offsetOf(Struct, "field_2"),
            .field_3 = @offsetOf(Struct, "field_3"),
        },
    };
    try testing.expectEqual(&value.field_1, proxy.findMutableFieldPointer("field_1"));
    try testing.expectEqual(&value.field_2, proxy.findMutableFieldPointer("field_2"));
    try testing.expectEqual(&value.field_3, proxy.findMutableFieldPointer("field_3"));
}

test "findMutableFieldPointer should return null when findFieldAddress fails or memory is not writeable" {
    const Struct = struct { field: u8 };
    const const_value = Struct{ .field = 1 };
    var var_value = Struct{ .field = 1 };
    const proxy_1 = StructProxy(Struct){
        .base_trail = .fromArray(.{ 0, 100 }),
        .field_offsets = .{ .field = @offsetOf(Struct, "field") },
    };
    const proxy_2 = StructProxy(Struct){
        .base_trail = .fromArray(.{@intFromPtr(&var_value)}),
        .field_offsets = .{ .field = std.math.maxInt(usize) },
    };
    const proxy_3 = StructProxy(Struct){
        .base_trail = .fromArray(.{0}),
        .field_offsets = .{ .field = @offsetOf(Struct, "field") },
    };
    const proxy_4 = StructProxy(Struct){
        .base_trail = .fromArray(.{@intFromPtr(&const_value)}),
        .field_offsets = .{ .field = @offsetOf(Struct, "field") },
    };
    try testing.expectEqual(null, proxy_1.findMutableFieldPointer("field"));
    try testing.expectEqual(null, proxy_2.findMutableFieldPointer("field"));
    try testing.expectEqual(null, proxy_3.findMutableFieldPointer("field"));
    try testing.expectEqual(null, proxy_4.findMutableFieldPointer("field"));
}

test "takeStaticCopy should return a value when findConstFieldPointer succeeds for every field of the struct" {
    const Struct = struct {
        field_1: u8,
        field_2: u16,
        field_3: u32,
    };
    const value = Struct{
        .field_1 = 1,
        .field_2 = 2,
        .field_3 = 3,
    };
    const proxy = StructProxy(Struct){
        .base_trail = .fromArray(.{@intFromPtr(&value)}),
        .field_offsets = .{
            .field_1 = @offsetOf(Struct, "field_1"),
            .field_2 = @offsetOf(Struct, "field_2"),
            .field_3 = @offsetOf(Struct, "field_3"),
        },
    };
    const copy = proxy.takeStaticCopy();
    try testing.expect(copy != null);
    try testing.expectEqual(value, copy.?);
}

test "takeStaticCopy should return null when getFieldConst fails for at least one field of the struct" {
    const Struct = struct {
        field_1: u8,
        field_2: u16,
        field_3: u32,
    };
    const value = Struct{
        .field_1 = 1,
        .field_2 = 2,
        .field_3 = 3,
    };
    const proxy = StructProxy(Struct){
        .base_trail = .fromArray(.{@intFromPtr(&value)}),
        .field_offsets = .{
            .field_1 = @offsetOf(Struct, "field_1"),
            .field_2 = @offsetOf(Struct, "field_2"),
            .field_3 = std.math.maxInt(usize),
        },
    };
    const copy = proxy.takeStaticCopy();
    try testing.expectEqual(null, copy);
}
