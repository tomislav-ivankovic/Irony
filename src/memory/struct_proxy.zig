const std = @import("std");
const os = @import("../os/root.zig");
const memory = @import("root.zig");

pub const struct_proxy_tag = opaque {};

pub fn StructProxy(comptime Struct: type) type {
    const struct_fields = switch (@typeInfo(Struct)) {
        .@"struct" => |info| info.fields,
        else => @compileError("StructProxy expects a struct type as argument."),
    };
    return struct {
        base_trail: memory.Proxy(void),
        field_offsets: memory.FieldOffsets(Struct),

        const Self = @This();
        pub const tag = struct_proxy_tag;

        pub fn getBaseAddress(self: *const Self) ?usize {
            return self.base_trail.findMemoryAddress();
        }

        pub fn getFieldAddress(self: *const Self, comptime field_name: []const u8) ?usize {
            const base_address = self.getBaseAddress() orelse return null;
            const field_offset = @field(self.field_offsets, field_name);
            const add_result = @addWithOverflow(base_address, field_offset);
            if (add_result[1] == 1) {
                return null;
            }
            return add_result[0];
        }

        pub fn getFieldConst(self: *const Self, comptime field_name: []const u8) ?*const @FieldType(Struct, field_name) {
            const address = self.getFieldAddress(field_name) orelse return null;
            const size = @sizeOf(@FieldType(Struct, field_name));
            if (!os.isMemoryReadable(address, size)) {
                return null;
            }
            return @ptrFromInt(address);
        }

        pub fn getFieldMut(self: *const Self, comptime field_name: []const u8) ?*@FieldType(Struct, field_name) {
            const address = self.getFieldAddress(field_name) orelse return null;
            const size = @sizeOf(@FieldType(Struct, field_name));
            if (!os.isMemoryWriteable(address, size)) {
                return null;
            }
            return @ptrFromInt(address);
        }

        pub fn takeStaticCopy(self: *const Self) ?Struct {
            var static_copy: Struct = undefined;
            inline for (struct_fields) |*field| {
                const value_pointer = self.getFieldConst(field.name) orelse return null;
                @field(static_copy, field.name) = value_pointer.*;
            }
            return static_copy;
        }
    };
}

const testing = std.testing;

test "getBaseAddress should return a value when base trail memory address is resolvable" {
    const Struct = struct {};
    const proxy = StructProxy(Struct){
        .base_trail = .fromArray(.{12345}),
        .field_offsets = .{},
    };
    try testing.expectEqual(12345, proxy.getBaseAddress());
}

test "getBaseAddress should return null when base trail memory address is not resolvable" {
    const Struct = struct {};
    const proxy = StructProxy(Struct){
        .base_trail = .fromArray(.{ 0, 100 }),
        .field_offsets = .{},
    };
    try testing.expectEqual(null, proxy.getBaseAddress());
}

test "getFieldAddress should return a value when getBaseAddress succeeds and field offset does not overflow" {
    const Struct = struct {
        field_1: u8,
        field_2: u16,
        field_3: u32,
    };
    const proxy = StructProxy(Struct){
        .base_trail = .fromArray(.{100}),
        .field_offsets = .{
            .field_1 = 10,
            .field_2 = 20,
            .field_3 = 30,
        },
    };
    try testing.expectEqual(110, proxy.getFieldAddress("field_1"));
    try testing.expectEqual(120, proxy.getFieldAddress("field_2"));
    try testing.expectEqual(130, proxy.getFieldAddress("field_3"));
}

test "getFieldAddress should return null when getBaseAddress fails or field offset overflows" {
    const Struct = struct { field: u8 };
    const proxy_1 = StructProxy(Struct){
        .base_trail = .fromArray(.{ 0, 100 }),
        .field_offsets = .{ .field = 10 },
    };
    const proxy_2 = StructProxy(Struct){
        .base_trail = .fromArray(.{100}),
        .field_offsets = .{ .field = std.math.maxInt(usize) },
    };
    try testing.expectEqual(null, proxy_1.getFieldAddress("field"));
    try testing.expectEqual(null, proxy_2.getFieldAddress("field"));
}

test "getFieldConst should return a pointer when getFieldAddress succeeds and memory on that address is readable" {
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
    try testing.expectEqual(&value.field_1, proxy.getFieldConst("field_1"));
    try testing.expectEqual(&value.field_2, proxy.getFieldConst("field_2"));
    try testing.expectEqual(&value.field_3, proxy.getFieldConst("field_3"));
}

test "getFieldConst should return null when getFieldAddress fails or memory on that address is not readable" {
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
    try testing.expectEqual(null, proxy_1.getFieldConst("field"));
    try testing.expectEqual(null, proxy_2.getFieldConst("field"));
    try testing.expectEqual(null, proxy_3.getFieldConst("field"));
}

test "getFieldMut should return a pointer when getFieldAddress succeeds and memory on that address is writeable" {
    const Struct = struct {
        field_1: u8,
        field_2: u16,
        field_3: u32,
    };
    var value = Struct{
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
    try testing.expectEqual(&value.field_1, proxy.getFieldMut("field_1"));
    try testing.expectEqual(&value.field_2, proxy.getFieldMut("field_2"));
    try testing.expectEqual(&value.field_3, proxy.getFieldMut("field_3"));
}

test "getFieldMut should return null when getFieldAddress fails or memory on that address is not writeable" {
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
    try testing.expectEqual(null, proxy_1.getFieldMut("field"));
    try testing.expectEqual(null, proxy_2.getFieldMut("field"));
    try testing.expectEqual(null, proxy_3.getFieldMut("field"));
    try testing.expectEqual(null, proxy_4.getFieldMut("field"));
}

test "takeStaticCopy should return a value when getFieldConst succeeds for every field of the struct" {
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
