const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

pub const ThrowEscapeDetector = struct {
    player_1_state: PlayerState = .{},
    player_2_state: PlayerState = .{},

    const Self = @This();
    pub const PlayerState = struct {
        throw_animation_id: ?u32 = null,
        previous_animation_id: ?u32 = null,
        previous_input: ?model.Input = null,
        previous_escape: ?model.ThrowEscape = null,
    };

    pub fn detect(self: *Self, frame: *model.Frame) void {
        detectSide(&self.player_1_state, &frame.players[0]);
        detectSide(&self.player_2_state, &frame.players[1]);
    }

    fn detectSide(state: *PlayerState, player: *model.Player) void {
        defer {
            if (player.throw_escape) |throw_escape| {
                if (throw_escape.phase == .not_being_thrown) {
                    state.throw_animation_id = null;
                }
            }
            state.previous_animation_id = player.animation_id;
            state.previous_input = player.input;
            state.previous_escape = player.throw_escape;
        }

        const animation_id = player.animation_id orelse return;
        const input = player.input orelse return;
        const escape = if (player.throw_escape) |*e| e else return;
        const previous_animation_id = state.previous_animation_id orelse return;
        const previous_input = state.previous_input orelse return;
        const previous_escape = state.previous_escape orelse return;

        const is_attempting_escape = (!previous_input.button_1 and input.button_1) or
            (!previous_input.button_2 and input.button_2);
        const is_escape_input_correct = if (input.button_1 and input.button_2) block: {
            break :block escape.escapable_with_1_plus_2;
        } else if (input.button_1) block: {
            break :block escape.escapable_with_1;
        } else if (input.button_2) block: {
            break :block escape.escapable_with_2;
        } else block: {
            break :block false;
        };

        switch (previous_escape.phase) {
            .not_being_thrown => {
                if (escape.phase != .not_being_thrown) {
                    state.throw_animation_id = player.animation_id;
                }
            },
            .in_escape_window => {
                if (escape.phase == .in_escape_window and is_attempting_escape) {
                    escape.phase = switch (is_escape_input_correct) {
                        true => .escape_success,
                        false => .wrong_escape_input,
                    };
                }
            },
            .escape_success => {
                if (animation_id != previous_animation_id and previous_animation_id != state.throw_animation_id) {
                    escape.phase = .not_being_thrown;
                } else {
                    escape.phase = .escape_success;
                }
            },
            .escape_window_over => {
                if (escape.phase != .not_being_thrown) {
                    escape.phase = .escape_window_over;
                }
            },
            .wrong_escape_input => {
                if (escape.phase != .not_being_thrown) {
                    escape.phase = .wrong_escape_input;
                }
            },
        }

        switch (escape.phase) {
            .not_being_thrown => {
                escape.escapable_with_1 = false;
                escape.escapable_with_2 = false;
                escape.escapable_with_1_plus_2 = false;
            },
            .in_escape_window, .escape_success, .escape_window_over, .wrong_escape_input => {
                escape.escapable_with_1 = escape.escapable_with_1 or previous_escape.escapable_with_1;
                escape.escapable_with_2 = escape.escapable_with_2 or previous_escape.escapable_with_2;
                escape.escapable_with_1_plus_2 = escape.escapable_with_1_plus_2 or
                    previous_escape.escapable_with_1_plus_2;
            },
        }
    }
};
