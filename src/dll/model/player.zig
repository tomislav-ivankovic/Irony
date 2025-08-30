const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("root.zig");

pub const PlayerId = enum {
    player_1,
    player_2,

    const Self = @This();
    pub const all = [2]Self{ .player_1, .player_2 };

    pub fn getOther(self: Self) Self {
        switch (self) {
            .player_1 => return .player_2,
            .player_2 => return .player_1,
        }
    }
};

pub const PlayerSide = enum {
    left,
    right,

    const Self = @This();
    pub const all = [2]Self{ .left, .right };

    pub fn getOther(self: Self) Self {
        switch (self) {
            .left => return .right,
            .right => return .left,
        }
    }
};

pub const PlayerRole = enum {
    main,
    secondary,

    const Self = @This();
    pub const all = [2]Self{ .main, .secondary };

    pub fn getOther(self: Self) Self {
        switch (self) {
            .main => return .secondary,
            .secondary => return .main,
        }
    }
};

pub const Player = struct {
    character_id: ?u32 = null,
    current_move_id: ?u32 = null,
    current_move_frame: ?u32 = null,
    current_move_first_active_frame: ?u32 = null,
    current_move_last_active_frame: ?u32 = null,
    current_move_total_frames: ?u32 = null,
    attack_type: ?model.AttackType = null,
    attack_phase: ?model.AttackPhase = null,
    attack_damage: ?i32 = null,
    hit_outcome: ?model.HitOutcome = null,
    posture: ?model.Posture = null,
    blocking: ?model.Blocking = null,
    crushing: ?model.Crushing = null,
    can_move: ?bool = null,
    input: ?model.Input = null,
    health: ?i32 = null,
    rage: ?model.Rage = null,
    heat: ?model.Heat = null,
    position: ?sdk.math.Vec3 = null,
    rotation: ?f32 = null,
    skeleton: ?model.Skeleton = null,
    hurt_cylinders: ?model.HurtCylinders = null,
    collision_spheres: ?model.CollisionSpheres = null,
    hit_lines: model.HitLines = .{},
};

const testing = std.testing;

test "PlayerId.getOther should return correct value" {
    try testing.expectEqual(PlayerId.player_2, PlayerId.player_1.getOther());
    try testing.expectEqual(PlayerId.player_1, PlayerId.player_2.getOther());
}

test "PlayerSide.getOther should return correct value" {
    try testing.expectEqual(PlayerSide.right, PlayerSide.left.getOther());
    try testing.expectEqual(PlayerSide.left, PlayerSide.right.getOther());
}

test "PlayerRole.getOther should return correct value" {
    try testing.expectEqual(PlayerRole.secondary, PlayerRole.main.getOther());
    try testing.expectEqual(PlayerRole.main, PlayerRole.secondary.getOther());
}
