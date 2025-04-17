const std = @import("std");
const os = @import("../os/root.zig");

pub fn MultilevelPointer(comptime Type: type) type {
    return struct {
        buffer: [max_len]?usize,
        len: usize,

        const Self = @This();
        const max_len = 32;

        pub fn fromArray(array: anytype) Self {
            if (@typeInfo(@TypeOf(array)) != .array) {
                const coerced: [array.len]?usize = array;
                return fromArray(coerced);
            }
            if (array.len > max_len) {
                @compileError(std.fmt.comptimePrint(
                    "The provided array with length {} is larger then maximum multilevel pointer length: {}",
                    .{ array.len, max_len },
                ));
            }
            var buffer: [max_len]?usize = undefined;
            for (array, 0..) |element, i| {
                buffer[i] = element;
            }
            return .{ .buffer = buffer, .len = array.len };
        }

        pub fn getOffsets(self: *const Self) []const ?usize {
            return self.buffer[0..self.len];
        }

        pub fn toConstPointer(self: *const Self) ?*const Type {
            const address = self.findMemoryAddressWithoutLastCheck() orelse return null;
            if (!os.isMemoryReadable(address, @sizeOf(Type))) {
                return null;
            }
            return @ptrFromInt(address);
        }

        pub fn toMutablePointer(self: *const Self) ?*Type {
            const address = self.findMemoryAddressWithoutLastCheck() orelse return null;
            if (!os.isMemoryWriteable(address, @sizeOf(Type))) {
                return null;
            }
            return @ptrFromInt(address);
        }

        pub fn findMemoryAddress(self: *const Self) ?usize {
            const address = self.findMemoryAddressWithoutLastCheck() orelse return null;
            if (!os.isMemoryReadable(address, @sizeOf(Type))) {
                return null;
            }
            return address;
        }

        fn findMemoryAddressWithoutLastCheck(self: *const Self) ?usize {
            const offsets = self.getOffsets();
            if (offsets.len == 0) {
                return null;
            }
            var current_address: usize = 0;
            for (offsets, 0..) |optional_offset, i| {
                const offset = optional_offset orelse return null;
                const result = @addWithOverflow(current_address, offset);
                const offset_address = result[0];
                const overflow = result[1];
                if (overflow == 1) {
                    return null;
                }
                current_address = offset_address;
                if (i == offsets.len - 1) {
                    break;
                }
                if (!os.isMemoryReadable(current_address, @sizeOf(usize))) {
                    return null;
                }
                const pointer: *const usize = @ptrFromInt(current_address);
                current_address = pointer.*;
                if (current_address == 0) {
                    return null;
                }
            }
            return current_address;
        }
    };
}

const testing = std.testing;

const Struct = packed struct {
    value_1: i32 = 1,
    value_2: i32 = 2,
};
const value_1_offset = 0;
const value_2_offset = @sizeOf(i32);

test "test" {
    _ = MultilevelPointer(i32).fromArray(.{ 0x1, 0x2, 0x3, 0x4 });
}

test "toConstPointer should return a pointer when the multilevel pointer is valid" {
    const testCase = struct {
        fn call(comptime size: comptime_int, offsets: [size]?usize, expected_pointer: *const i32) !void {
            const multilevel_pointer = MultilevelPointer(i32).fromArray(offsets);
            const actual_pointer = multilevel_pointer.toConstPointer();
            try testing.expectEqual(expected_pointer, actual_pointer);
        }
    }.call;
    const str = Struct{};
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);
    try testCase(1, .{str_address + value_1_offset}, &str.value_1);
    try testCase(1, .{str_address + value_2_offset}, &str.value_2);
    try testCase(2, .{ str_address_address, value_1_offset }, &str.value_1);
    try testCase(2, .{ str_address_address, value_2_offset }, &str.value_2);
}

test "toConstPointer should return null when the multilevel pointer is invalid or incomplete" {
    const testCase = struct {
        fn call(comptime size: comptime_int, offsets: [size]?usize) !void {
            const multilevel_pointer = MultilevelPointer(i32).fromArray(offsets);
            const actual_pointer = multilevel_pointer.toConstPointer();
            try testing.expectEqual(null, actual_pointer);
        }
    }.call;
    const str = Struct{};
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);
    try testCase(0, .{});
    try testCase(1, .{std.math.maxInt(usize)});
    try testCase(2, .{ 0, value_2_offset });
    try testCase(2, .{ str_address_address, std.math.maxInt(usize) });
    try testCase(1, .{null});
    try testCase(2, .{ str_address_address, null });
    try testCase(3, .{ str_address_address, value_1_offset, null });
    try testCase(3, .{ str_address_address, null, value_1_offset });
}

test "toMutablePointer should return a pointer when the multilevel pointer is valid" {
    const testCase = struct {
        fn call(comptime size: comptime_int, offsets: [size]?usize, expected_pointer: *i32) !void {
            const multilevel_pointer = MultilevelPointer(i32).fromArray(offsets);
            const actual_pointer = multilevel_pointer.toMutablePointer();
            try testing.expectEqual(expected_pointer, actual_pointer);
        }
    }.call;
    var str = Struct{};
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);
    try testCase(1, .{str_address + value_1_offset}, &str.value_1);
    try testCase(1, .{str_address + value_2_offset}, &str.value_2);
    try testCase(2, .{ str_address_address, value_1_offset }, &str.value_1);
    try testCase(2, .{ str_address_address, value_2_offset }, &str.value_2);
}

test "toMutablePointer should return null when the multilevel pointer is invalid or incomplete" {
    const testCase = struct {
        fn call(comptime size: comptime_int, offsets: [size]?usize) !void {
            const multilevel_pointer = MultilevelPointer(i32).fromArray(offsets);
            const actual_pointer = multilevel_pointer.toMutablePointer();
            try testing.expectEqual(null, actual_pointer);
        }
    }.call;
    var str = Struct{};
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);
    try testCase(0, .{});
    try testCase(1, .{std.math.maxInt(usize)});
    try testCase(2, .{ 0, value_2_offset });
    try testCase(2, .{ str_address_address, std.math.maxInt(usize) });
    try testCase(1, .{null});
    try testCase(2, .{ str_address_address, null });
    try testCase(3, .{ str_address_address, value_1_offset, null });
    try testCase(3, .{ str_address_address, null, value_1_offset });
}

test "findMemoryAddress should return a value when the multilevel pointer is valid" {
    const testCase = struct {
        fn call(comptime size: comptime_int, offsets: [size]?usize, expected_address: usize) !void {
            const multilevel_pointer = MultilevelPointer(i32).fromArray(offsets);
            const actual_address = multilevel_pointer.findMemoryAddress();
            try testing.expectEqual(expected_address, actual_address);
        }
    }.call;
    const str = Struct{};
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);
    try testCase(1, .{str_address + value_1_offset}, @intFromPtr(&str.value_1));
    try testCase(1, .{str_address + value_2_offset}, @intFromPtr(&str.value_2));
    try testCase(2, .{ str_address_address, value_1_offset }, @intFromPtr(&str.value_1));
    try testCase(2, .{ str_address_address, value_2_offset }, @intFromPtr(&str.value_2));
}

test "findMemoryAddress should return null when the multilevel pointer is invalid or incomplete" {
    const testCase = struct {
        fn call(comptime size: comptime_int, offsets: [size]?usize) !void {
            const multilevel_pointer = MultilevelPointer(i32).fromArray(offsets);
            const actual_address = multilevel_pointer.findMemoryAddress();
            try testing.expectEqual(null, actual_address);
        }
    }.call;
    const str = Struct{};
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);
    try testCase(0, .{});
    try testCase(1, .{std.math.maxInt(usize)});
    try testCase(2, .{ 0, value_2_offset });
    try testCase(2, .{ str_address_address, std.math.maxInt(usize) });
    try testCase(1, .{null});
    try testCase(2, .{ str_address_address, null });
    try testCase(3, .{ str_address_address, value_1_offset, null });
    try testCase(3, .{ str_address_address, null, value_1_offset });
}
