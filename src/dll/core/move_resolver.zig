const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

pub const MoveResolver = struct {
    player_1_state: PlayerState = .{},
    player_2_state: PlayerState = .{},

    const Self = @This();
    pub const PlayerState = struct {
        phase: ?model.MovePhase = null,
        first_active_frame: ?u32 = null,
        last_active_frame: ?u32 = null,
        connected_frame: ?u32 = null,
    };

    pub fn resolve(self: *Self, frame: *model.Frame) void {
        resolveSide(&self.player_1_state, &frame.players[0], &frame.players[1]);
        resolveSide(&self.player_2_state, &frame.players[1], &frame.players[0]);
    }

    fn resolveSide(state: *PlayerState, player: *model.Player, other_player: *model.Player) void {
        const current_frame = player.move_frame orelse {
            state.* = .{};
            return;
        };
        const attack_type = player.attack_type orelse {
            state.* = .{};
            return;
        };
        const can_move = player.can_move orelse {
            state.* = .{};
            return;
        };
        if (current_frame == 1) {
            if (attack_type == .not_attack) {
                if (can_move) {
                    state.* = .{ .phase = .neutral };
                } else {
                    state.* = .{ .phase = .recovery };
                }
            } else {
                state.* = .{ .phase = .start_up };
            }
        }
        if (state.phase) |phase| {
            switch (phase) {
                .neutral => if (!can_move) {
                    state.phase = .recovery;
                },
                .start_up => if (player.hit_lines.len > 0) {
                    state.phase = .active;
                    state.first_active_frame = current_frame;
                },
                .active => if (player.hit_lines.len == 0) {
                    state.phase = .recovery;
                    state.last_active_frame = current_frame -| 1;
                } else if (state.connected_frame != null) {
                    state.phase = .active_recovery;
                },
                .active_recovery => if (player.hit_lines.len == 0) {
                    state.phase = .recovery;
                    state.last_active_frame = current_frame -| 1;
                },
                .recovery => if (can_move) {
                    state.phase = .neutral;
                },
            }
        }
        if (state.phase == .active and other_player.hit_outcome != null and other_player.hit_outcome != .none) {
            state.connected_frame = current_frame;
        }
        player.move_phase = state.phase;
        player.move_first_active_frame = state.first_active_frame;
        player.move_last_active_frame = state.last_active_frame;
        player.move_connected_frame = state.connected_frame;
    }
};
