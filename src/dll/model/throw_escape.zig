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

pub const ThrowEscapeInputs = packed struct(u3) {
    one: bool = false,
    two: bool = false,
    one_plus_two: bool = false,
};

pub const ThrowEscapeTiming = enum(u1) {
    on_time = 0,
    late = 1,
};

pub const ThrowEscape = packed struct(u8) {
    phase: ThrowEscapePhase,
    attempted_input: ThrowEscapeInput = .none,
    attempt_timing: ThrowEscapeTiming = .on_time,
    correct_inputs: ThrowEscapeInputs = .{},

    const Self = @This();

    pub fn isAttemptedWithCorrectInput(self: *const Self) bool {
        return switch (self.attempted_input) {
            .none => false,
            .one => self.correct_inputs.one,
            .two => self.correct_inputs.two,
            .one_plus_two => self.correct_inputs.one_plus_two,
        };
    }
};

const testing = std.testing;

test "ThrowEscape.isAttemptedWithCorrectInput should return correct value" {
    try testing.expectEqual(false, (ThrowEscape{
        .phase = .in_escape_window,
        .attempted_input = .none,
        .correct_inputs = .{
            .one = true,
            .two = true,
            .one_plus_two = true,
        },
    }).isAttemptedWithCorrectInput());
    try testing.expectEqual(true, (ThrowEscape{
        .phase = .in_escape_window,
        .attempted_input = .one,
        .correct_inputs = .{
            .one = true,
            .two = true,
            .one_plus_two = false,
        },
    }).isAttemptedWithCorrectInput());
    try testing.expectEqual(true, (ThrowEscape{
        .phase = .in_escape_window,
        .attempted_input = .two,
        .correct_inputs = .{
            .one = true,
            .two = true,
            .one_plus_two = false,
        },
    }).isAttemptedWithCorrectInput());
    try testing.expectEqual(false, (ThrowEscape{
        .phase = .in_escape_window,
        .attempted_input = .one_plus_two,
        .correct_inputs = .{
            .one = true,
            .two = true,
            .one_plus_two = false,
        },
    }).isAttemptedWithCorrectInput());
    try testing.expectEqual(false, (ThrowEscape{
        .phase = .in_escape_window,
        .attempted_input = .one,
        .correct_inputs = .{
            .one = false,
            .two = false,
            .one_plus_two = true,
        },
    }).isAttemptedWithCorrectInput());
    try testing.expectEqual(false, (ThrowEscape{
        .phase = .in_escape_window,
        .attempted_input = .two,
        .correct_inputs = .{
            .one = false,
            .two = false,
            .one_plus_two = true,
        },
    }).isAttemptedWithCorrectInput());
    try testing.expectEqual(true, (ThrowEscape{
        .phase = .in_escape_window,
        .attempted_input = .one_plus_two,
        .correct_inputs = .{
            .one = false,
            .two = false,
            .one_plus_two = true,
        },
    }).isAttemptedWithCorrectInput());
}
