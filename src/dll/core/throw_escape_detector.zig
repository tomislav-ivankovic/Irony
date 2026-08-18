const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

pub const ThrowEscapeDetectorConfig = struct {
    one_plus_two_mode: enum { strict, forgiving },
};

pub fn ThrowEscapeDetector(comptime config: ThrowEscapeDetectorConfig) type {
    return struct {
        player_1_state: PlayerState = .{},
        player_2_state: PlayerState = .{},

        const Self = @This();
        pub const PlayerState = struct {
            input_state: InputState = .none,
            throw_animation_id: ?u32 = null,
            previous_animation_id: ?u32 = null,
            previous_input: ?model.Input = null,
            previous_escape: ?model.ThrowEscape = null,
        };
        pub const InputState = enum {
            none,
            unconfirmed_1,
            unconfirmed_2,
            unconfirmed_1_plus_2,
            confirmed_1,
            confirmed_2,
            confirmed_1_plus_2,
        };

        pub fn detect(self: *Self, frame: *model.Frame) void {
            detectSide(&self.player_1_state, &frame.players[0]);
            detectSide(&self.player_2_state, &frame.players[1]);
        }

        fn detectSide(state: *PlayerState, player: *model.Player) void {
            prolongEscapeSuccess(state, player);
            prolongCorrectInputs(state, player);
            processInput(state, player);
            setAttemptTiming(state, player);
            updatePreviousState(state, player);
        }

        fn prolongEscapeSuccess(state: *const PlayerState, player: *model.Player) void {
            const previous_escape = if (state.previous_escape) |*e| e else return;
            if (previous_escape.phase != .escape_success) {
                return;
            }
            const animation_id = player.animation_id orelse return;
            const previous_animation_id = state.previous_animation_id orelse return;
            if (animation_id != previous_animation_id and previous_animation_id != state.throw_animation_id) {
                return;
            }
            if (player.throw_escape) |*escape| {
                escape.phase = .escape_success;
            } else {
                player.throw_escape = previous_escape.*;
            }
        }

        fn prolongCorrectInputs(state: *const PlayerState, player: *model.Player) void {
            const escape = if (player.throw_escape) |*e| e else return;
            const previous_escape = if (state.previous_escape) |*e| e else return;
            if (escape.phase == .escape_success or escape.correct_inputs == model.ThrowEscapeInputs{}) {
                escape.correct_inputs = previous_escape.correct_inputs;
            }
        }

        fn processInput(state: *PlayerState, player: *model.Player) void {
            const escape = if (player.throw_escape) |*e| e else {
                state.input_state = .none;
                return;
            };
            const previous_correct_inputs = if (state.previous_escape) |*e| e.correct_inputs else model.ThrowEscapeInputs{};
            if (escape.phase != .escape_success and escape.correct_inputs != previous_correct_inputs) {
                state.input_state = .none;
                escape.attempted_input = .none;
            }
            const input = player.input orelse return;
            const previous_input = state.previous_input orelse return;
            switch (state.input_state) {
                .none => block: {
                    const escape_attempted = switch (escape.input_mode) {
                        .press => (!previous_input.button_1 and input.button_1) or
                            (!previous_input.button_2 and input.button_2),
                        .hold => true,
                    };
                    if (!escape_attempted) {
                        break :block;
                    }
                    if (input.button_1 and input.button_2) {
                        state.input_state = switch (config.one_plus_two_mode) {
                            .strict => .confirmed_1_plus_2,
                            .forgiving => .unconfirmed_1_plus_2,
                        };
                    } else if (input.button_1) {
                        state.input_state = switch (config.one_plus_two_mode) {
                            .strict => .confirmed_1,
                            .forgiving => .unconfirmed_1,
                        };
                    } else if (input.button_2) {
                        state.input_state = switch (config.one_plus_two_mode) {
                            .strict => .confirmed_2,
                            .forgiving => .unconfirmed_2,
                        };
                    }
                },
                .unconfirmed_1 => {
                    state.input_state = switch (input.button_1 and input.button_2) {
                        true => .confirmed_1_plus_2,
                        false => .confirmed_1,
                    };
                },
                .unconfirmed_2 => {
                    state.input_state = switch (input.button_1 and input.button_2) {
                        true => .confirmed_1_plus_2,
                        false => .confirmed_2,
                    };
                },
                .unconfirmed_1_plus_2 => {
                    state.input_state = .confirmed_1_plus_2;
                },
                .confirmed_1, .confirmed_2, .confirmed_1_plus_2 => {},
            }
            escape.attempted_input = switch (state.input_state) {
                .none, .unconfirmed_1, .unconfirmed_2, .unconfirmed_1_plus_2 => .none,
                .confirmed_1 => .one,
                .confirmed_2 => .two,
                .confirmed_1_plus_2 => .one_plus_two,
            };
        }

        fn setAttemptTiming(state: *PlayerState, player: *model.Player) void {
            const escape = if (player.throw_escape) |*e| e else return;
            const previous_escape = if (state.previous_escape) |*e| e else return;
            escape.attempt_timing = switch (previous_escape.attempted_input) {
                .none => switch (escape.phase) {
                    .in_escape_window, .escape_success => .on_time,
                    .escape_fail => .late,
                },
                .one, .two, .one_plus_two => previous_escape.attempt_timing,
            };
        }

        fn updatePreviousState(state: *PlayerState, player: *const model.Player) void {
            if (player.throw_escape) |*escape| {
                const is_in_throw_animation = escape.phase == .in_escape_window or
                    (escape.phase == .escape_success and state.previous_escape == null);
                if (is_in_throw_animation) {
                    state.throw_animation_id = player.animation_id;
                }
            } else {
                state.throw_animation_id = null;
            }
            state.previous_animation_id = player.animation_id;
            state.previous_input = player.input;
            state.previous_escape = player.throw_escape;
        }
    };
}

const testing = std.testing;

test "should prolong escape success into the escape animation" {
    var frame = model.Frame{};
    var detector = ThrowEscapeDetector(.{ .one_plus_two_mode = .strict }){};

    frame = .{ // frame before escape window
        .players = .{ .{
            .animation_id = 1,
            .throw_escape = null,
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[0].throw_escape);

    frame = .{ // first frame of escape window
        .players = .{ .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .in_escape_window },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapePhase.in_escape_window, frame.players[0].throw_escape.?.phase);

    frame = .{ // escape succeeds
        .players = .{ .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .escape_success },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapePhase.escape_success, frame.players[0].throw_escape.?.phase);

    frame = .{ // original animation keeps running
        .players = .{ .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .escape_success },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapePhase.escape_success, frame.players[0].throw_escape.?.phase);

    frame = .{ // switching to escape animation
        .players = .{ .{
            .animation_id = 3,
            .throw_escape = null,
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapePhase.escape_success, frame.players[0].throw_escape.?.phase);

    frame = .{ // still in escape animation
        .players = .{ .{
            .animation_id = 3,
            .throw_escape = null,
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapePhase.escape_success, frame.players[0].throw_escape.?.phase);

    frame = .{ // exiting escape animation
        .players = .{ .{
            .animation_id = 4,
            .throw_escape = null,
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[0].throw_escape);
}

test "should prolong correct inputs until the end of animation when escape fails" {
    var frame = model.Frame{};
    var detector = ThrowEscapeDetector(.{ .one_plus_two_mode = .strict }){};

    frame = .{ // frame before escape window
        .players = .{ .{
            .animation_id = 1,
            .throw_escape = null,
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[0].throw_escape);

    frame = .{ // first frame of escape window
        .players = .{ .{
            .animation_id = 2,
            .throw_escape = .{
                .phase = .in_escape_window,
                .correct_inputs = .{ .one = false, .two = false, .one_plus_two = true },
            },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(
        model.ThrowEscapeInputs{ .one = false, .two = false, .one_plus_two = true },
        frame.players[0].throw_escape.?.correct_inputs,
    );

    frame = .{ // one more frame inside escape window
        .players = .{ .{
            .animation_id = 2,
            .throw_escape = .{
                .phase = .in_escape_window,
                .correct_inputs = .{ .one = false, .two = false, .one_plus_two = true },
            },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(
        model.ThrowEscapeInputs{ .one = false, .two = false, .one_plus_two = true },
        frame.players[0].throw_escape.?.correct_inputs,
    );

    frame = .{ // escape window ends
        .players = .{ .{
            .animation_id = 2,
            .throw_escape = .{
                .phase = .escape_fail,
                .correct_inputs = .{ .one = false, .two = false, .one_plus_two = true },
            },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(
        model.ThrowEscapeInputs{ .one = false, .two = false, .one_plus_two = true },
        frame.players[0].throw_escape.?.correct_inputs,
    );

    frame = .{ // one more frame outside escape window
        .players = .{ .{
            .animation_id = 2,
            .throw_escape = .{
                .phase = .escape_fail,
                .correct_inputs = .{ .one = false, .two = false, .one_plus_two = true },
            },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(
        model.ThrowEscapeInputs{ .one = false, .two = false, .one_plus_two = true },
        frame.players[0].throw_escape.?.correct_inputs,
    );

    frame = .{ // throw animation ends
        .players = .{ .{
            .animation_id = 3,
            .throw_escape = null,
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[0].throw_escape);
}

test "should prolong correct inputs until the end of escape animation when escape succeeds" {
    var frame = model.Frame{};
    var detector = ThrowEscapeDetector(.{ .one_plus_two_mode = .strict }){};

    frame = .{ // initialization of previous frame state
        .players = .{ .{}, .{
            .animation_id = 1,
            .throw_escape = null,
        } },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[1].throw_escape);

    frame = .{ // first frame of escape window
        .players = .{ .{}, .{
            .animation_id = 2,
            .throw_escape = .{
                .phase = .in_escape_window,
                .correct_inputs = .{ .one = true, .two = true, .one_plus_two = false },
            },
        } },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[1].throw_escape != null);
    try testing.expectEqual(
        model.ThrowEscapeInputs{ .one = true, .two = true, .one_plus_two = false },
        frame.players[1].throw_escape.?.correct_inputs,
    );

    frame = .{ // escape succeeds
        .players = .{ .{}, .{
            .animation_id = 2,
            .throw_escape = .{
                .phase = .escape_success,
                .correct_inputs = .{ .one = true, .two = false, .one_plus_two = false },
            },
        } },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[1].throw_escape != null);
    try testing.expectEqual(
        model.ThrowEscapeInputs{ .one = true, .two = true, .one_plus_two = false },
        frame.players[1].throw_escape.?.correct_inputs,
    );

    frame = .{ // first frame of escape animation
        .players = .{ .{}, .{
            .animation_id = 3,
            .throw_escape = null,
        } },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[1].throw_escape != null);
    try testing.expectEqual(
        model.ThrowEscapeInputs{ .one = true, .two = true, .one_plus_two = false },
        frame.players[1].throw_escape.?.correct_inputs,
    );

    frame = .{ // one more frame of escape animation
        .players = .{ .{}, .{
            .animation_id = 3,
            .throw_escape = null,
        } },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[1].throw_escape != null);
    try testing.expectEqual(
        model.ThrowEscapeInputs{ .one = true, .two = true, .one_plus_two = false },
        frame.players[1].throw_escape.?.correct_inputs,
    );

    frame = .{ // escape animation ends
        .players = .{ .{}, .{
            .animation_id = 4,
            .throw_escape = null,
        } },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[1].throw_escape);
}

test "should correctly detect attempted input in strict one plus press two mode" {
    var frame = model.Frame{};
    var detector = ThrowEscapeDetector(.{ .one_plus_two_mode = .strict }){};

    frame = .{ // inputting 1+3 before escape window
        .players = .{ .{
            .animation_id = 1,
            .throw_escape = null,
            .input = .{ .button_1 = true, .button_3 = true },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[0].throw_escape);

    frame = .{ // first frame of escape window
        .players = .{ .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .in_escape_window, .input_mode = .press },
            .input = .{ .button_1 = true, .button_3 = true },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.none, frame.players[0].throw_escape.?.attempted_input);

    frame = .{ // pressing button 4
        .players = .{ .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .in_escape_window, .input_mode = .press },
            .input = .{ .button_1 = true, .button_3 = true, .button_4 = true },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.none, frame.players[0].throw_escape.?.attempted_input);

    frame = .{ // releasing button 1
        .players = .{ .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .in_escape_window, .input_mode = .press },
            .input = .{ .button_3 = true, .button_4 = true },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.none, frame.players[0].throw_escape.?.attempted_input);

    frame = .{ // pressing button 2
        .players = .{ .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .escape_success, .input_mode = .press },
            .input = .{ .button_2 = true, .button_3 = true, .button_4 = true },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.two, frame.players[0].throw_escape.?.attempted_input);

    frame = .{ // pressing button 1
        .players = .{ .{
            .animation_id = 3,
            .throw_escape = null,
            .input = .{ .button_1 = true, .button_2 = true, .button_3 = true, .button_4 = true },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.two, frame.players[0].throw_escape.?.attempted_input);

    frame = .{ // releasing everything
        .players = .{ .{
            .animation_id = 3,
            .throw_escape = null,
            .input = .{},
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.two, frame.players[0].throw_escape.?.attempted_input);

    frame = .{ // switching to escape animation
        .players = .{ .{
            .animation_id = 3,
            .throw_escape = null,
            .input = .{},
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.two, frame.players[0].throw_escape.?.attempted_input);

    frame = .{ // one more frame in escape animation
        .players = .{ .{
            .animation_id = 3,
            .throw_escape = null,
            .input = .{},
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.two, frame.players[0].throw_escape.?.attempted_input);

    frame = .{ // escape animation ends
        .players = .{ .{
            .animation_id = 4,
            .throw_escape = null,
            .input = .{},
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[0].throw_escape);
}

test "should correctly detect attempted input in forgiving one plus two press mode" {
    var frame = model.Frame{};
    var detector = ThrowEscapeDetector(.{ .one_plus_two_mode = .forgiving }){};

    frame = .{ // inputting 1+3 before escape window
        .players = .{ .{}, .{
            .animation_id = 1,
            .throw_escape = null,
            .input = .{ .button_1 = true, .button_3 = true },
        } },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[1].throw_escape);

    frame = .{ // first frame of escape window
        .players = .{ .{}, .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .in_escape_window, .input_mode = .press },
            .input = .{ .button_1 = true, .button_3 = true },
        } },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[1].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.none, frame.players[1].throw_escape.?.attempted_input);

    frame = .{ // pressing button 4
        .players = .{ .{}, .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .in_escape_window, .input_mode = .press },
            .input = .{ .button_1 = true, .button_3 = true, .button_4 = true },
        } },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[1].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.none, frame.players[1].throw_escape.?.attempted_input);

    frame = .{ // releasing button 1
        .players = .{ .{}, .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .in_escape_window, .input_mode = .press },
            .input = .{ .button_3 = true, .button_4 = true },
        } },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[1].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.none, frame.players[1].throw_escape.?.attempted_input);

    frame = .{ // pressing button 2
        .players = .{ .{}, .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .in_escape_window, .input_mode = .press },
            .input = .{ .button_2 = true, .button_3 = true, .button_4 = true },
        } },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[1].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.none, frame.players[1].throw_escape.?.attempted_input);

    frame = .{ // pressing button 1
        .players = .{ .{}, .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .escape_success },
            .input = .{ .button_1 = true, .button_2 = true, .button_3 = true, .button_4 = true },
        } },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[1].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.one_plus_two, frame.players[1].throw_escape.?.attempted_input);

    frame = .{ // and switching to escape animation
        .players = .{ .{}, .{
            .animation_id = 3,
            .throw_escape = null,
            .input = .{ .button_1 = true, .button_2 = true, .button_3 = true, .button_4 = true },
        } },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[1].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.one_plus_two, frame.players[1].throw_escape.?.attempted_input);

    frame = .{ // releasing everything
        .players = .{ .{}, .{
            .animation_id = 3,
            .throw_escape = null,
            .input = .{},
        } },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[1].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.one_plus_two, frame.players[1].throw_escape.?.attempted_input);

    frame = .{ // one more frame in escape animation
        .players = .{ .{}, .{
            .animation_id = 3,
            .throw_escape = null,
            .input = .{},
        } },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[1].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.one_plus_two, frame.players[1].throw_escape.?.attempted_input);

    frame = .{ // escape animation ends
        .players = .{ .{}, .{
            .animation_id = 4,
            .throw_escape = null,
            .input = .{},
        } },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[1].throw_escape);
}

test "should correctly detect attempted input in strict one plus two hold mode" {
    var frame = model.Frame{};
    var detector = ThrowEscapeDetector(.{ .one_plus_two_mode = .strict }){};

    frame = .{ // inputting 1+3 before escape window
        .players = .{ .{
            .animation_id = 1,
            .throw_escape = null,
            .input = .{ .button_1 = true, .button_3 = true },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[0].throw_escape);

    frame = .{ // first frame of escape window
        .players = .{ .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .escape_success, .input_mode = .hold },
            .input = .{ .button_1 = true, .button_3 = true },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.one, frame.players[0].throw_escape.?.attempted_input);

    frame = .{ // pressing button 4
        .players = .{ .{
            .animation_id = 3,
            .throw_escape = null,
            .input = .{ .button_1 = true, .button_2 = true, .button_3 = true },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.one, frame.players[0].throw_escape.?.attempted_input);

    frame = .{ // releasing everything
        .players = .{ .{
            .animation_id = 3,
            .throw_escape = null,
            .input = .{},
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.one, frame.players[0].throw_escape.?.attempted_input);

    frame = .{ // one more frame in escape animation
        .players = .{ .{
            .animation_id = 3,
            .throw_escape = null,
            .input = .{},
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.one, frame.players[0].throw_escape.?.attempted_input);

    frame = .{ // escape animation ends
        .players = .{ .{
            .animation_id = 4,
            .throw_escape = null,
            .input = .{},
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[0].throw_escape);
}

test "should correctly detect attempted input in forgiving one plus two hold mode" {
    var frame = model.Frame{};
    var detector = ThrowEscapeDetector(.{ .one_plus_two_mode = .forgiving }){};

    frame = .{ // inputting 1+3 before escape window
        .players = .{ .{
            .animation_id = 1,
            .throw_escape = null,
            .input = .{ .button_1 = true, .button_3 = true },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[0].throw_escape);

    frame = .{ // first frame of escape window
        .players = .{ .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .in_escape_window, .input_mode = .hold },
            .input = .{ .button_1 = true, .button_3 = true },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.none, frame.players[0].throw_escape.?.attempted_input);

    frame = .{ // pressing button 2
        .players = .{ .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .escape_success, .input_mode = .hold },
            .input = .{ .button_1 = true, .button_2 = true, .button_3 = true },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.one_plus_two, frame.players[0].throw_escape.?.attempted_input);

    frame = .{ // releasing everything
        .players = .{ .{
            .animation_id = 3,
            .throw_escape = null,
            .input = .{},
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.one_plus_two, frame.players[0].throw_escape.?.attempted_input);

    frame = .{ // one more frame in escape animation
        .players = .{ .{
            .animation_id = 3,
            .throw_escape = null,
            .input = .{},
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.one_plus_two, frame.players[0].throw_escape.?.attempted_input);

    frame = .{ // escape animation ends
        .players = .{ .{
            .animation_id = 4,
            .throw_escape = null,
            .input = .{},
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[0].throw_escape);
}

test "should set attempt timing to late when escape is attempted outside escape window" {
    var frame = model.Frame{};
    var detector = ThrowEscapeDetector(.{ .one_plus_two_mode = .strict }){};

    frame = .{ // frame before escape window
        .players = .{ .{
            .animation_id = 1,
            .throw_escape = null,
            .input = .{},
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[0].throw_escape);

    frame = .{ // first frame of escape window
        .players = .{ .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .in_escape_window },
            .input = .{},
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.none, frame.players[0].throw_escape.?.attempted_input);
    try testing.expectEqual(model.ThrowEscapeTiming.on_time, frame.players[0].throw_escape.?.attempt_timing);

    frame = .{ // one more frame in escape window
        .players = .{ .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .in_escape_window },
            .input = .{},
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.none, frame.players[0].throw_escape.?.attempted_input);
    try testing.expectEqual(model.ThrowEscapeTiming.on_time, frame.players[0].throw_escape.?.attempt_timing);

    frame = .{ // escape window over, pressing button 1
        .players = .{ .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .escape_fail },
            .input = .{ .button_1 = true },
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.one, frame.players[0].throw_escape.?.attempted_input);
    try testing.expectEqual(model.ThrowEscapeTiming.late, frame.players[0].throw_escape.?.attempt_timing);

    frame = .{ // one more frame outside escape window
        .players = .{ .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .escape_fail },
            .input = .{},
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[0].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.one, frame.players[0].throw_escape.?.attempted_input);
    try testing.expectEqual(model.ThrowEscapeTiming.late, frame.players[0].throw_escape.?.attempt_timing);

    frame = .{ // escape animation ends
        .players = .{ .{
            .animation_id = 3,
            .throw_escape = null,
            .input = .{},
        }, .{} },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[0].throw_escape);
}

test "should keep attempt timing to be on time when escape is attempted inside escape window" {
    var frame = model.Frame{};
    var detector = ThrowEscapeDetector(.{ .one_plus_two_mode = .strict }){};

    frame = .{ // frame before escape input
        .players = .{ .{}, .{
            .animation_id = 1,
            .throw_escape = null,
            .input = .{},
        } },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[1].throw_escape);

    frame = .{ // first frame of escape window
        .players = .{ .{}, .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .in_escape_window },
            .input = .{},
        } },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[1].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.none, frame.players[1].throw_escape.?.attempted_input);
    try testing.expectEqual(model.ThrowEscapeTiming.on_time, frame.players[1].throw_escape.?.attempt_timing);

    frame = .{ // pressing button 1
        .players = .{ .{}, .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .in_escape_window },
            .input = .{ .button_1 = true },
        } },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[1].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.one, frame.players[1].throw_escape.?.attempted_input);
    try testing.expectEqual(model.ThrowEscapeTiming.on_time, frame.players[1].throw_escape.?.attempt_timing);

    frame = .{ // escape window over, 1 was wrong escape input
        .players = .{ .{}, .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .escape_fail },
            .input = .{},
        } },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[1].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.one, frame.players[1].throw_escape.?.attempted_input);
    try testing.expectEqual(model.ThrowEscapeTiming.on_time, frame.players[1].throw_escape.?.attempt_timing);

    frame = .{ // one more frame outside escape window
        .players = .{ .{}, .{
            .animation_id = 2,
            .throw_escape = .{ .phase = .escape_fail },
            .input = .{},
        } },
    };
    detector.detect(&frame);
    try testing.expect(frame.players[1].throw_escape != null);
    try testing.expectEqual(model.ThrowEscapeInput.one, frame.players[1].throw_escape.?.attempted_input);
    try testing.expectEqual(model.ThrowEscapeTiming.on_time, frame.players[1].throw_escape.?.attempt_timing);

    frame = .{ // escape animation ends
        .players = .{ .{}, .{
            .animation_id = 3,
            .throw_escape = null,
            .input = .{},
        } },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[1].throw_escape);
}
