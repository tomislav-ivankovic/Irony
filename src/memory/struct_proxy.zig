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
        pub const Child = Struct;

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
            const Field = @FieldType(Struct, field_name);
            const address = self.findFieldAddress(field_name) orelse return null;
            if (address % @alignOf(Field) != 0) {
                return null;
            }
            if (!os.isMemoryReadable(address, @sizeOf(Field))) {
                return null;
            }
            return @ptrFromInt(address);
        }

        pub fn findMutableFieldPointer(
            self: *const Self,
            comptime field_name: []const u8,
        ) ?*@FieldType(Struct, field_name) {
            const Field = @FieldType(Struct, field_name);
            const address = self.findFieldAddress(field_name) orelse return null;
            if (address % @alignOf(Field) != 0) {
                return null;
            }
            if (!os.isMemoryWriteable(address, @sizeOf(Field))) {
                return null;
            }
            return @ptrFromInt(address);
        }

        pub fn takeFullCopy(self: *const Self) ?Struct {
            var copy: Struct = undefined;
            inline for (struct_fields) |*field| {
                const value_pointer = self.findConstFieldPointer(field.name) orelse return null;
                @field(copy, field.name) = value_pointer.*;
            }
            return copy;
        }

        pub fn takePartialCopy(self: *const Self, comptime Partial: type) ?Partial {
            const partial_fields = switch (@typeInfo(Partial)) {
                .@"struct" => |info| info.fields,
                else => @compileError(std.fmt.comptimePrint(
                    "Expected Partial to be a struct type but got: {}",
                    .{@typeName(Partial)},
                )),
            };
            var copy: Partial = undefined;
            inline for (partial_fields) |*field| {
                const value_pointer = self.findConstFieldPointer(field.name) orelse return null;
                @field(copy, field.name) = value_pointer.*;
            }
            return copy;
        }

        pub fn findSizeFromMaxOffset(self: *const Self) usize {
            var max: usize = 0;
            inline for (struct_fields) |*field| {
                if (@field(self.field_offsets, field.name)) |offset| {
                    const result = @addWithOverflow(offset, @sizeOf(field.type));
                    if (result[1] == 0 and result[0] > max) {
                        max = result[0];
                    }
                }
            }
            return max;
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
        .field_offsets = .{ .field_1 = 10, .field_2 = 20, .field_3 = 30 },
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

test "findConstFieldPointer should return a pointer when findFieldAddress succeeds, address is aligned and memory is readable" {
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

test "findConstFieldPointer should return null when findFieldAddress fails, address is misaligned or memory is not readable" {
    const Struct = extern struct { field_1: u64, field_2: u64 };
    const offset_1 = @offsetOf(Struct, "field_1");
    const offset_2 = @offsetOf(Struct, "field_2");
    const value = Struct{ .field_1 = 1, .field_2 = 2 };
    const proxy_1 = StructProxy(Struct){
        .base_trail = .fromArray(.{ 0, 100 }),
        .field_offsets = .{ .field_1 = offset_1, .field_2 = offset_2 },
    };
    const proxy_2 = StructProxy(Struct){
        .base_trail = .fromArray(.{@intFromPtr(&value)}),
        .field_offsets = .{ .field_1 = std.math.maxInt(usize), .field_2 = offset_2 },
    };
    const proxy_3 = StructProxy(Struct){
        .base_trail = .fromArray(.{0}),
        .field_offsets = .{ .field_1 = offset_1, .field_2 = offset_2 },
    };
    const proxy_4 = StructProxy(Struct){
        .base_trail = .fromArray(.{@intFromPtr(&value)}),
        .field_offsets = .{ .field_1 = offset_1 + 1, .field_2 = offset_2 },
    };
    try testing.expectEqual(null, proxy_1.findConstFieldPointer("field_1"));
    try testing.expectEqual(null, proxy_2.findConstFieldPointer("field_1"));
    try testing.expectEqual(null, proxy_3.findConstFieldPointer("field_1"));
    try testing.expectEqual(null, proxy_4.findConstFieldPointer("field_1"));
}

test "findMutableFieldPointer should return a pointer when findFieldAddress succeeds, address is aligned and memory is writable" {
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

test "findMutableFieldPointer should return null when findFieldAddress fails, address is misaligned or memory is not writeable" {
    const Struct = extern struct { field_1: u64, field_2: u64 };
    const offset_1 = @offsetOf(Struct, "field_1");
    const offset_2 = @offsetOf(Struct, "field_2");
    const const_value = Struct{ .field_1 = 1, .field_2 = 2 };
    var var_value = Struct{ .field_1 = 1, .field_2 = 2 };
    const proxy_1 = StructProxy(Struct){
        .base_trail = .fromArray(.{ 0, 100 }),
        .field_offsets = .{ .field_1 = offset_1, .field_2 = offset_2 },
    };
    const proxy_2 = StructProxy(Struct){
        .base_trail = .fromArray(.{@intFromPtr(&var_value)}),
        .field_offsets = .{ .field_1 = std.math.maxInt(usize), .field_2 = offset_2 },
    };
    const proxy_3 = StructProxy(Struct){
        .base_trail = .fromArray(.{0}),
        .field_offsets = .{ .field_1 = offset_1, .field_2 = offset_2 },
    };
    const proxy_4 = StructProxy(Struct){
        .base_trail = .fromArray(.{@intFromPtr(&var_value)}),
        .field_offsets = .{ .field_1 = offset_1 + 1, .field_2 = offset_2 },
    };
    const proxy_5 = StructProxy(Struct){
        .base_trail = .fromArray(.{@intFromPtr(&const_value)}),
        .field_offsets = .{ .field_1 = offset_1, .field_2 = offset_2 },
    };
    try testing.expectEqual(null, proxy_1.findMutableFieldPointer("field_1"));
    try testing.expectEqual(null, proxy_2.findMutableFieldPointer("field_1"));
    try testing.expectEqual(null, proxy_3.findMutableFieldPointer("field_1"));
    try testing.expectEqual(null, proxy_4.findMutableFieldPointer("field_1"));
    try testing.expectEqual(null, proxy_5.findMutableFieldPointer("field_1"));
}

test "takeFullCopy should return a value when findConstFieldPointer succeeds for every field of the struct" {
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
    const copy = proxy.takeFullCopy();
    try testing.expect(copy != null);
    try testing.expectEqual(value, copy.?);
}

test "takeFullCopy should return null when getFieldConst fails for at least one field of the struct" {
    const Struct = struct { field_1: u8, field_2: u16, field_3: u32 };
    const value = Struct{ .field_1 = 1, .field_2 = 2, .field_3 = 3 };
    const proxy = StructProxy(Struct){
        .base_trail = .fromArray(.{@intFromPtr(&value)}),
        .field_offsets = .{
            .field_1 = @offsetOf(Struct, "field_1"),
            .field_2 = @offsetOf(Struct, "field_2"),
            .field_3 = std.math.maxInt(usize),
        },
    };
    const copy = proxy.takeFullCopy();
    try testing.expectEqual(null, copy);
}

test "takePartialCopy should return a value when findConstFieldPointer succeeds for every field of the partial struct" {
    const Struct = struct { field_1: u8, field_2: u16, field_3: u32 };
    const Partial = struct { field_1: u8, field_2: u16 };
    const value = Struct{ .field_1 = 1, .field_2 = 2, .field_3 = 3 };
    const proxy = StructProxy(Struct){
        .base_trail = .fromArray(.{@intFromPtr(&value)}),
        .field_offsets = .{
            .field_1 = @offsetOf(Struct, "field_1"),
            .field_2 = @offsetOf(Struct, "field_2"),
            .field_3 = std.math.maxInt(usize),
        },
    };
    const copy = proxy.takePartialCopy(Partial);
    try testing.expect(copy != null);
    try testing.expectEqual(Partial{ .field_1 = 1, .field_2 = 2 }, copy.?);
}

test "takePartialCopy should return null when getFieldConst fails for at least one field of the partial struct" {
    const Struct = struct { field_1: u8, field_2: u16, field_3: u32 };
    const Partial = struct { field_1: u8, field_2: u16 };
    const value = Struct{ .field_1 = 1, .field_2 = 2, .field_3 = 3 };
    const proxy = StructProxy(Struct){
        .base_trail = .fromArray(.{@intFromPtr(&value)}),
        .field_offsets = .{
            .field_1 = @offsetOf(Struct, "field_1"),
            .field_2 = std.math.maxInt(usize),
            .field_3 = @offsetOf(Struct, "field_3"),
        },
    };
    const copy = proxy.takePartialCopy(Partial);
    try testing.expectEqual(null, copy);
}

test "findSizeFromMaxOffset should return correct value" {
    const Struct = struct { field_1: u8, field_2: u16, field_3: u32 };
    const value = Struct{ .field_1 = 1, .field_2 = 2, .field_3 = 3 };
    const proxy = StructProxy(Struct){
        .base_trail = .fromArray(.{@intFromPtr(&value)}),
        .field_offsets = .{ .field_1 = 10, .field_2 = 30, .field_3 = 20 },
    };
    try testing.expectEqual(32, proxy.findSizeFromMaxOffset());
}
