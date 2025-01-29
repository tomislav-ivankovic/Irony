const std = @import("std");
const memory = @import("../os/memory.zig");

pub fn MultilevelPointer(comptime Type: type) type {
    return struct {
        offsets: []const usize,

        const Self = @This();

        pub fn toConstPointer(self: *const Self) ?*const Type {
            const address = self.findMemoryAddressWithoutLastCheck() orelse return null;
            if (!memory.isMemoryReadable(address, @sizeOf(Type))) {
                return null;
            }
            return @ptrFromInt(address);
        }

        pub fn toMutablePointer(self: *const Self) ?*Type {
            const address = self.findMemoryAddressWithoutLastCheck() orelse return null;
            if (!memory.isMemoryWriteable(address, @sizeOf(Type))) {
                return null;
            }
            return @ptrFromInt(address);
        }

        pub fn findMemoryAddress(self: *const Self) ?usize {
            const address = self.findMemoryAddressWithoutLastCheck() orelse return null;
            if (!memory.isMemoryReadable(address, @sizeOf(Type))) {
                return null;
            }
            return address;
        }

        fn findMemoryAddressWithoutLastCheck(self: *const Self) ?usize {
            if (self.offsets.len == 0) {
                return null;
            }
            var current_address: usize = 0;
            for (self.offsets, 0..) |offset, i| {
                const result = @addWithOverflow(current_address, offset);
                const offset_address = result[0];
                const overflow = result[1];
                if (overflow == 1) {
                    return null;
                }
                current_address = offset_address;
                if (i == self.offsets.len - 1) {
                    break;
                }
                if (!memory.isMemoryReadable(current_address, @sizeOf(usize))) {
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

test "toConstPointer should return a pointer when the multilevel pointer is valid" {
    const testCase = struct {
        fn call(offsets: []const usize, expected_pointer: *const i32) !void {
            const multilevel_pointer = MultilevelPointer(i32){
                .offsets = offsets,
            };
            const actual_pointer = multilevel_pointer.toConstPointer();
            try testing.expectEqual(expected_pointer, actual_pointer);
        }
    }.call;
    const str = Struct{};
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);
    try testCase(&[_]usize{str_address + value_1_offset}, &str.value_1);
    try testCase(&[_]usize{str_address + value_2_offset}, &str.value_2);
    try testCase(&[_]usize{ str_address_address, value_1_offset }, &str.value_1);
    try testCase(&[_]usize{ str_address_address, value_2_offset }, &str.value_2);
}

test "toConstPointer should return null when the multilevel pointer is invalid" {
    const testCase = struct {
        fn call(offsets: []const usize) !void {
            const multilevel_pointer = MultilevelPointer(i32){
                .offsets = offsets,
            };
            const actual_pointer = multilevel_pointer.toConstPointer();
            try testing.expectEqual(null, actual_pointer);
        }
    }.call;
    const str = Struct{};
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);
    try testCase(&[_]usize{});
    try testCase(&[_]usize{std.math.maxInt(usize)});
    try testCase(&[_]usize{ 0, value_2_offset });
    try testCase(&[_]usize{ str_address_address, std.math.maxInt(usize) });
}

test "toMutablePointer should return a pointer when the multilevel pointer is valid" {
    const testCase = struct {
        fn call(offsets: []const usize, expected_pointer: *i32) !void {
            const multilevel_pointer = MultilevelPointer(i32){
                .offsets = offsets,
            };
            const actual_pointer = multilevel_pointer.toMutablePointer();
            try testing.expectEqual(expected_pointer, actual_pointer);
        }
    }.call;
    var str = Struct{};
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);
    try testCase(&[_]usize{str_address + value_1_offset}, &str.value_1);
    try testCase(&[_]usize{str_address + value_2_offset}, &str.value_2);
    try testCase(&[_]usize{ str_address_address, value_1_offset }, &str.value_1);
    try testCase(&[_]usize{ str_address_address, value_2_offset }, &str.value_2);
}

test "toMutablePointer should return null when the multilevel pointer is invalid" {
    const testCase = struct {
        fn call(offsets: []const usize) !void {
            const multilevel_pointer = MultilevelPointer(i32){
                .offsets = offsets,
            };
            const actual_pointer = multilevel_pointer.toMutablePointer();
            try testing.expectEqual(null, actual_pointer);
        }
    }.call;
    var str = Struct{};
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);
    try testCase(&[_]usize{});
    try testCase(&[_]usize{std.math.maxInt(usize)});
    try testCase(&[_]usize{ 0, value_2_offset });
    try testCase(&[_]usize{ str_address_address, std.math.maxInt(usize) });
}

test "findMemoryAddress should return a value when the multilevel pointer is valid" {
    const testCase = struct {
        fn call(offsets: []const usize, expected_address: usize) !void {
            const multilevel_pointer = MultilevelPointer(i32){
                .offsets = offsets,
            };
            const actual_address = multilevel_pointer.findMemoryAddress();
            try testing.expectEqual(expected_address, actual_address);
        }
    }.call;
    const str = Struct{};
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);
    try testCase(&[_]usize{str_address + value_1_offset}, @intFromPtr(&str.value_1));
    try testCase(&[_]usize{str_address + value_2_offset}, @intFromPtr(&str.value_2));
    try testCase(&[_]usize{ str_address_address, value_1_offset }, @intFromPtr(&str.value_1));
    try testCase(&[_]usize{ str_address_address, value_2_offset }, @intFromPtr(&str.value_2));
}

test "findMemoryAddress should return null when the multilevel pointer is invalid" {
    const testCase = struct {
        fn call(offsets: []const usize) !void {
            const multilevel_pointer = MultilevelPointer(i32){
                .offsets = offsets,
            };
            const actual_address = multilevel_pointer.findMemoryAddress();
            try testing.expectEqual(null, actual_address);
        }
    }.call;
    const str = Struct{};
    const str_address = @intFromPtr(&str);
    const str_address_address = @intFromPtr(&str_address);
    try testCase(&[_]usize{});
    try testCase(&[_]usize{std.math.maxInt(usize)});
    try testCase(&[_]usize{ 0, value_2_offset });
    try testCase(&[_]usize{ str_address_address, std.math.maxInt(usize) });
}
