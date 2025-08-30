const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

pub const AttackDetector = struct {
    player_1_state: PlayerState = .{},
    player_2_state: PlayerState = .{},

    const Self = @This();
    const PlayerState = struct {
        phase: ?model.AttackPhase = null,
        first_active_frame: ?u32 = null,
        last_active_frame: ?u32 = null,
    };

    pub fn detect(self: *Self, frame: *model.Frame) void {
        detectAttacks(&self.player_1_state, &frame.players[0]);
        detectAttacks(&self.player_2_state, &frame.players[1]);
    }

    fn detectAttacks(state: *PlayerState, player: *model.Player) void {
        const current_frame = player.current_move_frame orelse {
            state.* = .{};
            return;
        };
        const attack_type = player.attack_type orelse {
            state.* = .{};
            return;
        };
        if (current_frame == 1) {
            if (attack_type == .not_attack) {
                state.* = .{ .phase = .not_attack };
            } else {
                state.* = .{ .phase = .start_up };
            }
        }
        const phase = state.phase orelse return;
        switch (phase) {
            .not_attack => {},
            .start_up => if (player.hit_lines.len > 0) {
                state.phase = .active;
                state.first_active_frame = current_frame;
            },
            .active => if (player.hit_lines.len == 0) {
                state.phase = .recovery;
                state.last_active_frame = current_frame -| 1;
            },
            .recovery => {},
        }
        player.attack_phase = state.phase;
        player.current_move_first_active_frame = state.first_active_frame;
        player.current_move_last_active_frame = state.last_active_frame;
    }
};
