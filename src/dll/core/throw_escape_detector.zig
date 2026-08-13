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
            prolongEscapableWith(state, player);
            processInput(state, player);
            updatePreviousState(state, player);
        }

        fn prolongEscapeSuccess(state: *const PlayerState, player: *model.Player) void {
            const previous_escape = state.previous_escape orelse return;
            if (previous_escape.phase != .escape_success) {
                return;
            }
            const escape = if (player.throw_escape) |*e| e else return;
            const animation_id = player.animation_id orelse return;
            const previous_animation_id = state.previous_animation_id orelse return;
            if (animation_id != previous_animation_id and previous_animation_id != state.throw_animation_id) {
                escape.phase = .not_being_thrown;
            } else {
                escape.phase = .escape_success;
            }
        }

        fn prolongEscapableWith(state: *const PlayerState, player: *model.Player) void {
            const escape = if (player.throw_escape) |*e| e else return;
            const previous_escape = state.previous_escape orelse return;
            switch (escape.phase) {
                .not_being_thrown => {
                    escape.escapable_with_1 = false;
                    escape.escapable_with_2 = false;
                    escape.escapable_with_1_plus_2 = false;
                },
                .in_escape_window, .escape_success, .escape_fail => {
                    escape.escapable_with_1 = escape.escapable_with_1 or previous_escape.escapable_with_1;
                    escape.escapable_with_2 = escape.escapable_with_2 or previous_escape.escapable_with_2;
                    escape.escapable_with_1_plus_2 = escape.escapable_with_1_plus_2 or
                        previous_escape.escapable_with_1_plus_2;
                },
            }
        }

        fn processInput(state: *PlayerState, player: *model.Player) void {
            const input = player.input orelse return;
            const escape = if (player.throw_escape) |*e| e else return;
            const previous_input = state.previous_input orelse return;
            const previous_escape = state.previous_escape orelse return;
            if (escape.phase == .not_being_thrown) {
                state.input_state = .none;
                escape.attempted_input = .none;
                escape.attempted_in_time = false;
                return;
            }
            switch (state.input_state) {
                .none => block: {
                    const escape_attempted = (!previous_input.button_1 and input.button_1) or
                        (!previous_input.button_2 and input.button_2);
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
                    } else {
                        unreachable;
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
            if (previous_escape.attempted_input == .none and escape.attempted_input != .none) {
                escape.attempted_in_time = switch (escape.phase) {
                    .not_being_thrown => unreachable,
                    .in_escape_window, .escape_success => true,
                    .escape_fail => false,
                };
            } else {
                escape.attempted_in_time = previous_escape.attempted_in_time;
            }
        }

        fn updatePreviousState(state: *PlayerState, player: *const model.Player) void {
            if (player.throw_escape) |escape| {
                if (escape.phase == .not_being_thrown) {
                    state.throw_animation_id = null;
                } else if (state.previous_escape) |previous_escape| {
                    if (previous_escape.phase == .not_being_thrown) {
                        state.throw_animation_id = player.animation_id;
                    }
                }
            }
            state.previous_animation_id = player.animation_id;
            state.previous_input = player.input;
            state.previous_escape = player.throw_escape;
        }
    };
}
