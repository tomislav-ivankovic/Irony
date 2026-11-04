const std = @import("std");
const os = @import("../os/root.zig");
const memory = @import("root.zig");

pub const proxy_tag = opaque {};

pub fn Proxy(comptime Type: type) type {
    return struct {
        trail: memory.PointerTrail,

        const Self = @This();
        pub const tag = proxy_tag;
        pub const Child = Type;

        pub fn fromArray(array: anytype) Self {
            return .{ .trail = .fromArray(array) };
        }

        pub fn fromPointer(pointer: ?*const Type) Self {
            if (pointer) |p| {
                return .{ .trail = .fromArray(.{@intFromPtr(p)}) };
            } else {
                return .{ .trail = .fromArray(.{0}) };
            }
        }

        pub fn findAddress(self: *const Self) ?usize {
            return self.trail.resolve();
        }

        pub fn toConstPointer(self: *const Self) ?*const Type {
            const address = self.findAddress() orelse return null;
            if (address % @alignOf(Type) != 0) {
                return null;
            }
            if (!os.isMemoryReadable(address, @sizeOf(Type))) {
                return null;
            }
            return @ptrFromInt(address);
        }

        pub fn toMutablePointer(self: *const Self) ?*Type {
            const address = self.findAddress() orelse return null;
            if (address % @alignOf(Type) != 0) {
                return null;
            }
            if (!os.isMemoryWriteable(address, @sizeOf(Type))) {
                return null;
            }
            return @ptrFromInt(address);
        }

        pub fn takeCopy(self: *const Self) ?Type {
            if (self.toConstPointer()) |pointer| {
                return pointer.*;
            } else {
                return null;
            }
        }
    };
}

const testing = std.testing;

test "fromPointer should return a proxy with trail that points to pointer's address when pointer is provided" {
    const Struct = struct {};
    const str = Struct{};
    const proxy = Proxy(Struct).fromPointer(&str);
    try testing.expectEqualSlices(?usize, &.{@intFromPtr(&str)}, proxy.trail.getOffsets());
}

test "fromPointer should return a proxy with trail that points to 0 address when null is provided" {
    const Struct = struct {};
    const proxy = Proxy(Struct).fromPointer(null);
    try testing.expectEqualSlices(?usize, &.{0}, proxy.trail.getOffsets());
}

test "findAddress should return a value when trail is resolvable" {
    const Struct = struct {};
    const proxy = Proxy(Struct).fromArray(.{12345});
    try testing.expectEqual(12345, proxy.findAddress());
}

test "findAddress should return null when trail is not resolvable" {
    const Struct = struct {};
    const proxy = Proxy(Struct).fromArray(.{ 0, 100 });
    try testing.expectEqual(null, proxy.findAddress());
}

test "toConstPointer should return a pointer when trail is resolvable, address is aligned and memory is readable" {
    const Struct = extern struct { field_1: i32, field_2: i32 };
    const field_1_offset = @offsetOf(Struct, "field_1");
    const field_2_offset = @offsetOf(Struct, "field_2");

    const str = Struct{ .field_1 = 1, .field_2 = 2 };
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);
    const str_address_address_address = @intFromPtr(&str_address_address);

    const proxy = Proxy(i32).fromArray;
    try testing.expectEqual(&str.field_1, proxy(.{str_address + field_1_offset}).toConstPointer());
    try testing.expectEqual(&str.field_2, proxy(.{str_address + field_2_offset}).toConstPointer());
    try testing.expectEqual(&str.field_1, proxy(.{ str_address_address, field_1_offset }).toConstPointer());
    try testing.expectEqual(&str.field_2, proxy(.{ str_address_address, field_2_offset }).toConstPointer());
    try testing.expectEqual(&str.field_1, proxy(.{ str_address_address_address, 0, field_1_offset }).toConstPointer());
    try testing.expectEqual(&str.field_2, proxy(.{ str_address_address_address, 0, field_2_offset }).toConstPointer());
}

test "toConstPointer should return null when trail is not resolvable, address is misaligned or memory is not readable" {
    const Struct = extern struct { field_1: i32, field_2: i32 };
    const field_1_offset = @offsetOf(Struct, "field_1");
    const field_2_offset = @offsetOf(Struct, "field_2");

    const str = Struct{ .field_1 = 1, .field_2 = 2 };
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);

    const proxy = Proxy(i32).fromArray;
    try testing.expectEqual(null, proxy(.{}).toConstPointer());
    try testing.expectEqual(null, proxy(.{0}).toConstPointer());
    try testing.expectEqual(null, proxy(.{std.math.maxInt(usize)}).toConstPointer());
    try testing.expectEqual(null, proxy(.{ 0, field_2_offset }).toConstPointer());
    try testing.expectEqual(null, proxy(.{ str_address_address, std.math.maxInt(usize) }).toConstPointer());
    try testing.expectEqual(null, proxy(.{null}).toConstPointer());
    try testing.expectEqual(null, proxy(.{ str_address_address, null }).toConstPointer());
    try testing.expectEqual(null, proxy(.{ str_address_address, field_1_offset, null }).toConstPointer());
    try testing.expectEqual(null, proxy(.{ str_address_address, null, field_1_offset }).toConstPointer());
    try testing.expectEqual(null, proxy(.{ str_address_address, field_1_offset + 1 }).toConstPointer());
}

test "toMutablePointer should return a pointer when trail is resolvable, address is aligned and memory is writeable" {
    const Struct = extern struct { field_1: i32, field_2: i32 };
    const field_1_offset = @offsetOf(Struct, "field_1");
    const field_2_offset = @offsetOf(Struct, "field_2");

    var str = Struct{ .field_1 = 1, .field_2 = 2 };
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);
    const str_address_address_address = @intFromPtr(&str_address_address);

    const proxy = Proxy(i32).fromArray;
    try testing.expectEqual(&str.field_1, proxy(.{str_address + field_1_offset}).toMutablePointer());
    try testing.expectEqual(&str.field_2, proxy(.{str_address + field_2_offset}).toMutablePointer());
    try testing.expectEqual(&str.field_1, proxy(.{ str_address_address, field_1_offset }).toMutablePointer());
    try testing.expectEqual(&str.field_2, proxy(.{ str_address_address, field_2_offset }).toMutablePointer());
    try testing.expectEqual(&str.field_1, proxy(.{ str_address_address_address, 0, field_1_offset }).toMutablePointer());
    try testing.expectEqual(&str.field_2, proxy(.{ str_address_address_address, 0, field_2_offset }).toMutablePointer());
}

test "toMutablePointer should return null when trail is not resolvable, address is misaligned or memory is not writeable" {
    const Struct = extern struct { field_1: i32, field_2: i32 };
    const field_1_offset = @offsetOf(Struct, "field_1");
    const field_2_offset = @offsetOf(Struct, "field_2");

    var str = Struct{ .field_1 = 1, .field_2 = 2 };
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);

    const proxy = Proxy(i32).fromArray;
    try testing.expectEqual(null, proxy(.{}).toMutablePointer());
    try testing.expectEqual(null, proxy(.{0}).toMutablePointer());
    try testing.expectEqual(null, proxy(.{std.math.maxInt(usize)}).toMutablePointer());
    try testing.expectEqual(null, proxy(.{ 0, field_2_offset }).toMutablePointer());
    try testing.expectEqual(null, proxy(.{ str_address_address, std.math.maxInt(usize) }).toMutablePointer());
    try testing.expectEqual(null, proxy(.{null}).toMutablePointer());
    try testing.expectEqual(null, proxy(.{ str_address_address, null }).toMutablePointer());
    try testing.expectEqual(null, proxy(.{ str_address_address, field_1_offset, null }).toMutablePointer());
    try testing.expectEqual(null, proxy(.{ str_address_address, null, field_1_offset }).toMutablePointer());
    try testing.expectEqual(null, proxy(.{ str_address_address, field_1_offset + 1 }).toMutablePointer());
}

test "takeCopy should return a copy when trail is resolvable, address is aligned and memory is readable" {
    const Struct = extern struct { field_1: i32, field_2: i32 };
    const field_1_offset = @offsetOf(Struct, "field_1");
    const field_2_offset = @offsetOf(Struct, "field_2");

    const str = Struct{ .field_1 = 1, .field_2 = 2 };
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);
    const str_address_address_address = @intFromPtr(&str_address_address);

    const proxy = Proxy(i32).fromArray;
    try testing.expectEqual(str.field_1, proxy(.{str_address + field_1_offset}).takeCopy());
    try testing.expectEqual(str.field_2, proxy(.{str_address + field_2_offset}).takeCopy());
    try testing.expectEqual(str.field_1, proxy(.{ str_address_address, field_1_offset }).takeCopy());
    try testing.expectEqual(str.field_2, proxy(.{ str_address_address, field_2_offset }).takeCopy());
    try testing.expectEqual(str.field_1, proxy(.{ str_address_address_address, 0, field_1_offset }).takeCopy());
    try testing.expectEqual(str.field_2, proxy(.{ str_address_address_address, 0, field_2_offset }).takeCopy());
}

test "takeCopy should return null when trail is not resolvable, address is misaligned or memory is not readable" {
    const Struct = extern struct { field_1: i32, field_2: i32 };
    const field_1_offset = @offsetOf(Struct, "field_1");
    const field_2_offset = @offsetOf(Struct, "field_2");

    const str = Struct{ .field_1 = 1, .field_2 = 2 };
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);

    const proxy = Proxy(i32).fromArray;
    try testing.expectEqual(null, proxy(.{}).takeCopy());
    try testing.expectEqual(null, proxy(.{0}).takeCopy());
    try testing.expectEqual(null, proxy(.{std.math.maxInt(usize)}).takeCopy());
    try testing.expectEqual(null, proxy(.{ 0, field_2_offset }).takeCopy());
    try testing.expectEqual(null, proxy(.{ str_address_address, std.math.maxInt(usize) }).takeCopy());
    try testing.expectEqual(null, proxy(.{null}).takeCopy());
    try testing.expectEqual(null, proxy(.{ str_address_address, null }).takeCopy());
    try testing.expectEqual(null, proxy(.{ str_address_address, field_1_offset, null }).takeCopy());
    try testing.expectEqual(null, proxy(.{ str_address_address, null, field_1_offset }).takeCopy());
    try testing.expectEqual(null, proxy(.{ str_address_address, field_1_offset + 1 }).takeCopy());
}
