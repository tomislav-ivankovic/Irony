const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

pub const MoveDetector = struct {
    player_1_state: PlayerState = .{},
    player_2_state: PlayerState = .{},

    const Self = @This();
    pub const PlayerState = struct {
        previous_animation_id: ?u32 = null,
        previous_animation_frame: ?u32 = null,
        other_previous_animation_id: ?u32 = null,
        other_previous_animation_frame: ?u32 = null,
        phase: ?model.MovePhase = null,
        move_frame: ?u32 = null,
        first_active_frame: ?u32 = null,
        last_active_frame: ?u32 = null,
        connected_frame: ?u32 = null,
    };

    pub fn detect(self: *Self, frame: *model.Frame) void {
        detectSide(&self.player_1_state, &frame.players[0], &frame.players[1]);
        detectSide(&self.player_2_state, &frame.players[1], &frame.players[0]);
    }

    fn detectSide(state: *PlayerState, player: *model.Player, other_player: *model.Player) void {
        defer {
            state.previous_animation_id = player.animation_id;
            state.previous_animation_frame = player.animation_frame;
            state.other_previous_animation_id = other_player.animation_id;
            state.other_previous_animation_frame = other_player.animation_frame;
        }
        const animation_id = player.animation_id orelse {
            state.* = .{};
            return;
        };
        const previous_animation_id = state.previous_animation_id orelse {
            state.* = .{};
            return;
        };
        const other_animation_id = other_player.animation_id orelse {
            state.* = .{};
            return;
        };
        const other_previous_animation_id = state.other_previous_animation_id orelse {
            state.* = .{};
            return;
        };
        const animation_frame = player.animation_frame orelse {
            state.* = .{};
            return;
        };
        const previous_animation_frame = state.previous_animation_frame orelse {
            state.* = .{};
            return;
        };
        const other_animation_frame = other_player.animation_frame orelse {
            state.* = .{};
            return;
        };
        const other_previous_animation_frame = state.other_previous_animation_frame orelse {
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
        if (animation_frame == 1) {
            if (attack_type == .not_attack) {
                if (can_move) {
                    state.* = .{ .phase = .neutral, .move_frame = 0 };
                } else {
                    state.* = .{ .phase = .recovery, .move_frame = 0 };
                }
            } else {
                state.* = .{ .phase = .start_up, .move_frame = 0 };
            }
        }
        const did_player_animation_progress = (animation_frame != previous_animation_frame) or
            (animation_id != previous_animation_id);
        const did_other_player_animation_progress = (other_animation_frame != other_previous_animation_frame) or
            (other_animation_id != other_previous_animation_id);
        const did_move_progress = did_player_animation_progress and did_other_player_animation_progress;
        if (did_move_progress) {
            if (state.move_frame) |*frame| {
                frame.* += 1;
            }
        }
        const move_frame = state.move_frame orelse {
            state.* = .{};
            return;
        };
        if (state.phase) |phase| {
            switch (phase) {
                .neutral => if (!can_move) {
                    state.phase = .recovery;
                },
                .start_up => if (player.hit_lines.len > 0) {
                    state.phase = .active;
                    state.first_active_frame = move_frame;
                },
                .active => if (player.hit_lines.len == 0) {
                    state.phase = .recovery;
                    state.last_active_frame = move_frame -| 1;
                } else if (state.connected_frame != null) {
                    state.phase = .active_recovery;
                },
                .active_recovery => if (player.hit_lines.len == 0) {
                    state.phase = .recovery;
                    state.last_active_frame = move_frame -| 1;
                },
                .recovery => if (can_move) {
                    state.phase = .neutral;
                },
            }
        }
        if (state.phase == .active and other_player.hit_outcome != null and other_player.hit_outcome != .none) {
            state.connected_frame = move_frame;
        }
        player.move_phase = state.phase;
        player.animation_to_move_delta = animation_frame -| move_frame;
        player.first_active_frame = state.first_active_frame;
        player.last_active_frame = state.last_active_frame;
        player.connected_frame = state.connected_frame;
    }
};

const testing = std.testing;

test "should set move_phase, animation_to_move_delta, first_active_frame, last_active_frame, connected_frame to correct value at correct frame" {
    var frame = model.Frame{};
    var detector = MoveDetector{};

    frame = .{ // initialization of previous frame state
        .players = .{
            .{
                .animation_id = 10,
                .animation_frame = 1,
                .attack_type = .not_attack,
                .hit_outcome = .none,
                .can_move = true,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
            .{
                .animation_id = 20,
                .animation_frame = 1,
                .attack_type = .not_attack,
                .hit_outcome = .none,
                .can_move = true,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
        },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[0].move_phase);
    try testing.expectEqual(null, frame.players[0].animation_to_move_delta);
    try testing.expectEqual(null, frame.players[0].first_active_frame);
    try testing.expectEqual(null, frame.players[0].connected_frame);
    try testing.expectEqual(null, frame.players[0].last_active_frame);
    try testing.expectEqual(null, frame.players[1].move_phase);
    try testing.expectEqual(null, frame.players[1].animation_to_move_delta);
    try testing.expectEqual(null, frame.players[1].first_active_frame);
    try testing.expectEqual(null, frame.players[1].connected_frame);
    try testing.expectEqual(null, frame.players[1].last_active_frame);

    frame = .{ // defender's neutral animation starts
        .players = .{
            .{
                .animation_id = 10,
                .animation_frame = 2,
                .attack_type = .not_attack,
                .hit_outcome = .none,
                .can_move = true,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
            .{
                .animation_id = 21,
                .animation_frame = 1,
                .attack_type = .not_attack,
                .hit_outcome = .none,
                .can_move = true,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
        },
    };
    detector.detect(&frame);
    try testing.expectEqual(null, frame.players[0].move_phase);
    try testing.expectEqual(null, frame.players[0].animation_to_move_delta);
    try testing.expectEqual(null, frame.players[0].first_active_frame);
    try testing.expectEqual(null, frame.players[0].connected_frame);
    try testing.expectEqual(null, frame.players[0].last_active_frame);
    try testing.expectEqual(.neutral, frame.players[1].move_phase);
    try testing.expectEqual(0, frame.players[1].animation_to_move_delta);
    try testing.expectEqual(null, frame.players[1].first_active_frame);
    try testing.expectEqual(null, frame.players[1].connected_frame);
    try testing.expectEqual(null, frame.players[1].last_active_frame);

    frame = .{ // attack animation starts
        .players = .{
            .{
                .animation_id = 11,
                .animation_frame = 1,
                .attack_type = .mid,
                .hit_outcome = .none,
                .can_move = false,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
            .{
                .animation_id = 21,
                .animation_frame = 2,
                .attack_type = .not_attack,
                .hit_outcome = .none,
                .can_move = true,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
        },
    };
    detector.detect(&frame);
    try testing.expectEqual(.start_up, frame.players[0].move_phase);
    try testing.expectEqual(0, frame.players[0].animation_to_move_delta);
    try testing.expectEqual(null, frame.players[0].first_active_frame);
    try testing.expectEqual(null, frame.players[0].connected_frame);
    try testing.expectEqual(null, frame.players[0].last_active_frame);
    try testing.expectEqual(.neutral, frame.players[1].move_phase);
    try testing.expectEqual(0, frame.players[1].animation_to_move_delta);
    try testing.expectEqual(null, frame.players[1].first_active_frame);
    try testing.expectEqual(null, frame.players[1].connected_frame);
    try testing.expectEqual(null, frame.players[1].last_active_frame);

    frame = .{ // normal startup frame
        .players = .{
            .{
                .animation_id = 11,
                .animation_frame = 2,
                .attack_type = .mid,
                .hit_outcome = .none,
                .can_move = false,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
            .{
                .animation_id = 21,
                .animation_frame = 3,
                .attack_type = .not_attack,
                .hit_outcome = .none,
                .can_move = true,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
        },
    };
    detector.detect(&frame);
    try testing.expectEqual(.start_up, frame.players[0].move_phase);
    try testing.expectEqual(0, frame.players[0].animation_to_move_delta);
    try testing.expectEqual(null, frame.players[0].first_active_frame);
    try testing.expectEqual(null, frame.players[0].connected_frame);
    try testing.expectEqual(null, frame.players[0].last_active_frame);
    try testing.expectEqual(.neutral, frame.players[1].move_phase);
    try testing.expectEqual(0, frame.players[1].animation_to_move_delta);
    try testing.expectEqual(null, frame.players[1].first_active_frame);
    try testing.expectEqual(null, frame.players[1].connected_frame);
    try testing.expectEqual(null, frame.players[1].last_active_frame);

    frame = .{ // frame where defender is frozen in time while attacker's animation advances
        .players = .{
            .{
                .animation_id = 11,
                .animation_frame = 3,
                .attack_type = .mid,
                .hit_outcome = .none,
                .can_move = false,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
            .{
                .animation_id = 21,
                .animation_frame = 3,
                .attack_type = .not_attack,
                .hit_outcome = .none,
                .can_move = true,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
        },
    };
    detector.detect(&frame);
    try testing.expectEqual(.start_up, frame.players[0].move_phase);
    try testing.expectEqual(1, frame.players[0].animation_to_move_delta);
    try testing.expectEqual(null, frame.players[0].first_active_frame);
    try testing.expectEqual(null, frame.players[0].connected_frame);
    try testing.expectEqual(null, frame.players[0].last_active_frame);
    try testing.expectEqual(.neutral, frame.players[1].move_phase);
    try testing.expectEqual(0, frame.players[1].animation_to_move_delta);
    try testing.expectEqual(null, frame.players[1].first_active_frame);
    try testing.expectEqual(null, frame.players[1].connected_frame);
    try testing.expectEqual(null, frame.players[1].last_active_frame);

    frame = .{ // first active frame
        .players = .{
            .{
                .animation_id = 11,
                .animation_frame = 4,
                .attack_type = .mid,
                .hit_outcome = .none,
                .can_move = false,
                .hit_lines = .{ .buffer = undefined, .len = 1 },
            },
            .{
                .animation_id = 21,
                .animation_frame = 4,
                .attack_type = .not_attack,
                .hit_outcome = .none,
                .can_move = true,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
        },
    };
    detector.detect(&frame);
    try testing.expectEqual(.active, frame.players[0].move_phase);
    try testing.expectEqual(1, frame.players[0].animation_to_move_delta);
    try testing.expectEqual(3, frame.players[0].first_active_frame);
    try testing.expectEqual(null, frame.players[0].connected_frame);
    try testing.expectEqual(null, frame.players[0].last_active_frame);
    try testing.expectEqual(.neutral, frame.players[1].move_phase);
    try testing.expectEqual(0, frame.players[1].animation_to_move_delta);
    try testing.expectEqual(null, frame.players[1].first_active_frame);
    try testing.expectEqual(null, frame.players[1].connected_frame);
    try testing.expectEqual(null, frame.players[1].last_active_frame);

    frame = .{ // attack gets blocked
        .players = .{
            .{
                .animation_id = 11,
                .animation_frame = 5,
                .attack_type = .mid,
                .hit_outcome = .none,
                .can_move = false,
                .hit_lines = .{ .buffer = undefined, .len = 2 },
            },
            .{
                .animation_id = 21,
                .animation_frame = 5,
                .attack_type = .not_attack,
                .hit_outcome = .blocked_standing,
                .can_move = true,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
        },
    };
    detector.detect(&frame);
    try testing.expectEqual(.active, frame.players[0].move_phase);
    try testing.expectEqual(1, frame.players[0].animation_to_move_delta);
    try testing.expectEqual(3, frame.players[0].first_active_frame);
    try testing.expectEqual(4, frame.players[0].connected_frame);
    try testing.expectEqual(null, frame.players[0].last_active_frame);
    try testing.expectEqual(.neutral, frame.players[1].move_phase);
    try testing.expectEqual(0, frame.players[1].animation_to_move_delta);
    try testing.expectEqual(null, frame.players[1].first_active_frame);
    try testing.expectEqual(null, frame.players[1].connected_frame);
    try testing.expectEqual(null, frame.players[1].last_active_frame);

    frame = .{ // last active frame (active-recovery)
        .players = .{
            .{
                .animation_id = 11,
                .animation_frame = 6,
                .attack_type = .mid,
                .hit_outcome = .none,
                .can_move = false,
                .hit_lines = .{ .buffer = undefined, .len = 3 },
            },
            .{
                .animation_id = 22,
                .animation_frame = 1,
                .attack_type = .not_attack,
                .hit_outcome = .blocked_standing,
                .can_move = false,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
        },
    };
    detector.detect(&frame);
    try testing.expectEqual(.active_recovery, frame.players[0].move_phase);
    try testing.expectEqual(1, frame.players[0].animation_to_move_delta);
    try testing.expectEqual(3, frame.players[0].first_active_frame);
    try testing.expectEqual(4, frame.players[0].connected_frame);
    try testing.expectEqual(null, frame.players[0].last_active_frame);
    try testing.expectEqual(.recovery, frame.players[1].move_phase);
    try testing.expectEqual(0, frame.players[1].animation_to_move_delta);
    try testing.expectEqual(null, frame.players[1].first_active_frame);
    try testing.expectEqual(null, frame.players[1].connected_frame);
    try testing.expectEqual(null, frame.players[1].last_active_frame);

    frame = .{ // attack starts recovering
        .players = .{
            .{
                .animation_id = 11,
                .animation_frame = 7,
                .attack_type = .mid,
                .hit_outcome = .none,
                .can_move = false,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
            .{
                .animation_id = 22,
                .animation_frame = 2,
                .attack_type = .not_attack,
                .hit_outcome = .blocked_standing,
                .can_move = false,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
        },
    };
    detector.detect(&frame);
    try testing.expectEqual(.recovery, frame.players[0].move_phase);
    try testing.expectEqual(1, frame.players[0].animation_to_move_delta);
    try testing.expectEqual(3, frame.players[0].first_active_frame);
    try testing.expectEqual(4, frame.players[0].connected_frame);
    try testing.expectEqual(5, frame.players[0].last_active_frame);
    try testing.expectEqual(.recovery, frame.players[1].move_phase);
    try testing.expectEqual(0, frame.players[1].animation_to_move_delta);
    try testing.expectEqual(null, frame.players[1].first_active_frame);
    try testing.expectEqual(null, frame.players[1].connected_frame);
    try testing.expectEqual(null, frame.players[1].last_active_frame);

    frame = .{ // frame where attacker is frozen in time while defenders's animation advances
        .players = .{
            .{
                .animation_id = 11,
                .animation_frame = 7,
                .attack_type = .mid,
                .hit_outcome = .none,
                .can_move = false,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
            .{
                .animation_id = 22,
                .animation_frame = 3,
                .attack_type = .not_attack,
                .hit_outcome = .blocked_standing,
                .can_move = false,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
        },
    };
    detector.detect(&frame);
    try testing.expectEqual(.recovery, frame.players[0].move_phase);
    try testing.expectEqual(1, frame.players[0].animation_to_move_delta);
    try testing.expectEqual(3, frame.players[0].first_active_frame);
    try testing.expectEqual(4, frame.players[0].connected_frame);
    try testing.expectEqual(5, frame.players[0].last_active_frame);
    try testing.expectEqual(.recovery, frame.players[1].move_phase);
    try testing.expectEqual(1, frame.players[1].animation_to_move_delta);
    try testing.expectEqual(null, frame.players[1].first_active_frame);
    try testing.expectEqual(null, frame.players[1].connected_frame);
    try testing.expectEqual(null, frame.players[1].last_active_frame);

    frame = .{ // defender recovered
        .players = .{
            .{
                .animation_id = 11,
                .animation_frame = 8,
                .attack_type = .mid,
                .hit_outcome = .none,
                .can_move = false,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
            .{
                .animation_id = 23,
                .animation_frame = 1,
                .attack_type = .not_attack,
                .hit_outcome = .none,
                .can_move = true,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
        },
    };
    detector.detect(&frame);
    try testing.expectEqual(.recovery, frame.players[0].move_phase);
    try testing.expectEqual(1, frame.players[0].animation_to_move_delta);
    try testing.expectEqual(3, frame.players[0].first_active_frame);
    try testing.expectEqual(4, frame.players[0].connected_frame);
    try testing.expectEqual(5, frame.players[0].last_active_frame);
    try testing.expectEqual(.neutral, frame.players[1].move_phase);
    try testing.expectEqual(0, frame.players[1].animation_to_move_delta);
    try testing.expectEqual(null, frame.players[1].first_active_frame);
    try testing.expectEqual(null, frame.players[1].connected_frame);
    try testing.expectEqual(null, frame.players[1].last_active_frame);

    frame = .{ // attacker recovered
        .players = .{
            .{
                .animation_id = 12,
                .animation_frame = 1,
                .attack_type = .not_attack,
                .hit_outcome = .none,
                .can_move = true,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
            .{
                .animation_id = 23,
                .animation_frame = 2,
                .attack_type = .not_attack,
                .hit_outcome = .none,
                .can_move = true,
                .hit_lines = .{ .buffer = undefined, .len = 0 },
            },
        },
    };
    detector.detect(&frame);
    try testing.expectEqual(.neutral, frame.players[0].move_phase);
    try testing.expectEqual(0, frame.players[0].animation_to_move_delta);
    try testing.expectEqual(null, frame.players[0].first_active_frame);
    try testing.expectEqual(null, frame.players[0].connected_frame);
    try testing.expectEqual(null, frame.players[0].last_active_frame);
    try testing.expectEqual(.neutral, frame.players[1].move_phase);
    try testing.expectEqual(0, frame.players[1].animation_to_move_delta);
    try testing.expectEqual(null, frame.players[1].first_active_frame);
    try testing.expectEqual(null, frame.players[1].connected_frame);
    try testing.expectEqual(null, frame.players[1].last_active_frame);
}
