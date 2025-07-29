const std = @import("std");

pub const converted_value_tag = opaque {};

pub fn ConvertedValue(
    comptime Raw: type,
    comptime Converted: type,
    comptime rawToConverted: ?*const fn (raw: Raw) Converted,
    comptime convertedToRaw: ?*const fn (value: Converted) Raw,
) type {
    return extern struct {
        raw: Raw,

        const Self = @This();
        pub const tag = converted_value_tag;

        pub fn fromConverted(converted: Converted) Self {
            if (convertedToRaw) |ctr| {
                return .{ .raw = ctr(converted) };
            } else {
                @compileError("Can not setConverted a ConvertedValue when convertedToRaw is not provided.");
            }
        }

        pub fn convert(self: *const Self) Converted {
            if (rawToConverted) |rtc| {
                return rtc(self.raw);
            } else {
                @compileError("Can not convert a ConvertedValue when rawToConverted is not provided.");
            }
        }

        pub fn setConverted(self: *Self, converted: Converted) void {
            if (convertedToRaw) |ctr| {
                self.raw = ctr(converted);
            } else {
                @compileError("Can not setConverted a ConvertedValue when convertedToRaw is not provided.");
            }
        }
    };
}

const testing = std.testing;

test "should have same size as raw value" {
    try testing.expectEqual(@sizeOf(i64), @sizeOf(ConvertedValue(i64, u32, null, null)));
}

test "fromConverted should return correct value" {
    const convertedToRaw = struct {
        fn call(raw: i32) i32 {
            return raw - 5;
        }
    }.call;
    const value = ConvertedValue(i32, i32, null, convertedToRaw).fromConverted(10);
    try testing.expectEqual(5, value.raw);
}

test "convert should return correct value" {
    const rawToConverted = struct {
        fn call(raw: i32) i32 {
            return raw + 5;
        }
    }.call;
    const value = ConvertedValue(i32, i32, rawToConverted, null){ .raw = 5 };
    try testing.expectEqual(10, value.convert());
}

test "setConverted should set correct value" {
    const convertedToRaw = struct {
        fn call(raw: i32) i32 {
            return raw - 5;
        }
    }.call;
    var value = ConvertedValue(i32, i32, null, convertedToRaw){ .raw = 0 };
    value.setConverted(10);
    try testing.expectEqual(5, value.raw);
}
