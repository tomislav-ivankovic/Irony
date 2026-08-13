const std = @import("std");
const model = @import("root.zig");

pub const ThrowEscapePhase = enum(u2) {
    not_being_thrown = 0,
    in_escape_window = 1,
    escape_success = 2,
    escape_fail = 3,
};

pub const ThrowEscapeInput = enum(u2) {
    none = 0,
    one = 1,
    two = 2,
    one_plus_two = 3,
};

pub const ThrowEscape = packed struct(u8) {
    phase: ThrowEscapePhase,
    attempted_input: ThrowEscapeInput = .none,
    attempted_in_time: bool = false,
    escapable_with_1: bool = false,
    escapable_with_2: bool = false,
    escapable_with_1_plus_2: bool = false,

    const Self = @This();

    pub fn isAttemptedWithCorrectInput(self: *const Self) bool {
        return switch (self.attempted_input) {
            .none => false,
            .one => self.escapable_with_1,
            .two => self.escapable_with_2,
            .one_plus_two => self.escapable_with_1_plus_2,
        };
    }
};

const testing = std.testing;

test "ThrowEscape.isAttemptedWithCorrectInput should return correct value" {
    try testing.expectEqual(false, (ThrowEscape{
        .phase = .in_escape_window,
        .attempted_input = .none,
        .escapable_with_1 = true,
        .escapable_with_2 = true,
        .escapable_with_1_plus_2 = true,
    }).isAttemptedWithCorrectInput());
    try testing.expectEqual(true, (ThrowEscape{
        .phase = .in_escape_window,
        .attempted_input = .one,
        .escapable_with_1 = true,
        .escapable_with_2 = true,
        .escapable_with_1_plus_2 = false,
    }).isAttemptedWithCorrectInput());
    try testing.expectEqual(true, (ThrowEscape{
        .phase = .in_escape_window,
        .attempted_input = .two,
        .escapable_with_1 = true,
        .escapable_with_2 = true,
        .escapable_with_1_plus_2 = false,
    }).isAttemptedWithCorrectInput());
    try testing.expectEqual(false, (ThrowEscape{
        .phase = .in_escape_window,
        .attempted_input = .one_plus_two,
        .escapable_with_1 = true,
        .escapable_with_2 = true,
        .escapable_with_1_plus_2 = false,
    }).isAttemptedWithCorrectInput());
    try testing.expectEqual(false, (ThrowEscape{
        .phase = .in_escape_window,
        .attempted_input = .one,
        .escapable_with_1 = false,
        .escapable_with_2 = false,
        .escapable_with_1_plus_2 = true,
    }).isAttemptedWithCorrectInput());
    try testing.expectEqual(false, (ThrowEscape{
        .phase = .in_escape_window,
        .attempted_input = .two,
        .escapable_with_1 = false,
        .escapable_with_2 = false,
        .escapable_with_1_plus_2 = true,
    }).isAttemptedWithCorrectInput());
    try testing.expectEqual(true, (ThrowEscape{
        .phase = .in_escape_window,
        .attempted_input = .one_plus_two,
        .escapable_with_1 = false,
        .escapable_with_2 = false,
        .escapable_with_1_plus_2 = true,
    }).isAttemptedWithCorrectInput());
}
