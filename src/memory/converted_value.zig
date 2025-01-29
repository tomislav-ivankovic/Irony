const std = @import("std");

pub fn ConvertedValue(
    comptime Raw: type,
    comptime Value: type,
    comptime rawToValue: ?*const fn (raw: Raw) Value,
    comptime valueToRaw: ?*const fn (value: Value) Raw,
) type {
    return packed struct {
        raw: Raw,

        const Self = @This();

        pub fn getValue(self: *const Self) Value {
            if (rawToValue) |convert| {
                return convert(self.raw);
            } else {
                @compileError("Can not getValue of a ConvertedValue when rawToValue is not provided.");
            }
        }

        pub fn setValue(self: *Self, value: Value) void {
            if (valueToRaw) |convert| {
                self.raw = convert(value);
            } else {
                @compileError("Can not setValue of a ConvertedValue when valueToRaw is not provided.");
            }
        }
    };
}

const testing = std.testing;

test "should have same size as raw value" {
    try testing.expectEqual(@sizeOf(i64), @sizeOf(ConvertedValue(i64, u32, null, null)));
}

test "getValue should return correct value" {
    const rawToValue = struct {
        fn call(raw: i32) i32 {
            return raw + 5;
        }
    }.call;
    const value = ConvertedValue(i32, i32, rawToValue, null){ .raw = 5 };
    try testing.expectEqual(10, value.getValue());
}

test "setValue should set correct value" {
    const valueToRaw = struct {
        fn call(raw: i32) i32 {
            return raw - 5;
        }
    }.call;
    var value = ConvertedValue(i32, i32, null, valueToRaw){ .raw = 0 };
    value.setValue(10);
    try testing.expectEqual(5, value.raw);
}
