const std = @import("std");

pub const BooleanConfig = struct {
    BackingInt: type = u8,
    false_value: comptime_int = 0,
    true_value: comptime_int = 1,
};

pub fn Boolean(comptime config: BooleanConfig) type {
    return enum(config.BackingInt) {
        false = config.false_value,
        true = config.true_value,
        _,

        const Self = @This();

        pub fn fromBool(b: bool) Self {
            return switch (b) {
                false => .false,
                true => .true,
            };
        }

        pub fn toBool(self: Self) ?bool {
            return switch (self) {
                .false => false,
                .true => true,
                else => null,
            };
        }

        comptime {
            const false_v = config.false_value;
            const true_v = config.true_value;
            const third_v = if (false_v != 0 and true_v != 0) 0 else if (false_v != 1 and true_v != 1) 1 else 2;
            std.debug.assert(Self.fromBool(false) == .false);
            std.debug.assert(Self.fromBool(true) == .true);
            std.debug.assert(@as(Self, @enumFromInt(false_v)).toBool() == false);
            std.debug.assert(@as(Self, @enumFromInt(true_v)).toBool() == true);
            std.debug.assert(@as(Self, @enumFromInt(third_v)).toBool() == null);
        }
    };
}
