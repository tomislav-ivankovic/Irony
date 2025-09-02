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
    move_id: ?u32 = null,
    move_frame: ?u32 = null,
    move_first_active_frame: ?u32 = null,
    move_last_active_frame: ?u32 = null,
    move_connected_frame: ?u32 = null,
    move_total_frames: ?u32 = null,
    move_phase: ?model.MovePhase = null,
    attack_type: ?model.AttackType = null,
    min_hit_lines_z: ?f32 = null,
    max_hit_lines_z: ?f32 = null,
    attack_range: ?f32 = null,
    recovery_range: ?f32 = null,
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

    const Self = @This();

    pub fn getStartupFrames(self: *const Self) model.U32ActualMinMax {
        return .{
            .actual = self.move_connected_frame,
            .min = self.move_first_active_frame,
            .max = self.move_last_active_frame,
        };
    }

    pub fn getActiveFrames(self: *const Self) model.U32ActualMax {
        const first_active_frame = self.move_first_active_frame orelse return .{
            .actual = null,
            .max = null,
        };
        const connected_or_whiffed_frame = self.move_connected_frame orelse self.move_last_active_frame;
        return .{
            .actual = if (connected_or_whiffed_frame) |frame| 1 + frame -| first_active_frame else null,
            .max = if (self.move_last_active_frame) |frame| 1 + frame -| first_active_frame else null,
        };
    }

    pub fn getRecoveryFrames(self: *const Self) model.U32ActualMinMax {
        const total = self.move_total_frames orelse return .{
            .actual = null,
            .min = null,
            .max = null,
        };
        if (self.move_phase == .recovery and self.attack_type == .not_attack) {
            return .{
                .actual = total,
                .min = total,
                .max = total,
            };
        }
        const connected_or_whiffed_frame = self.move_connected_frame orelse self.move_last_active_frame;
        return .{
            .actual = if (connected_or_whiffed_frame) |frame| total -| frame else null,
            .min = if (self.move_last_active_frame) |frame| total -| frame else null,
            .max = if (self.move_first_active_frame) |frame| total -| frame else null,
        };
    }

    pub fn getFrameAdvantage(self: *const Self, other: *const Self) model.I32ActualMinMax {
        const self_recovery = self.getRecoveryFrames();
        const other_recovery = other.getRecoveryFrames();
        return .{
            .actual = if (other_recovery.actual != null and self_recovery.actual != null) block: {
                break :block @as(i32, @intCast(other_recovery.actual.?)) -| @as(i32, @intCast(self_recovery.actual.?));
            } else null,
            .min = if (other_recovery.min != null and self_recovery.max != null) block: {
                break :block @as(i32, @intCast(other_recovery.min.?)) -| @as(i32, @intCast(self_recovery.max.?));
            } else null,
            .max = if (other_recovery.max != null and self_recovery.min != null) block: {
                break :block @as(i32, @intCast(other_recovery.max.?)) -| @as(i32, @intCast(self_recovery.min.?));
            } else null,
        };
    }

    pub fn getDistanceTo(self: *const Self, other: *const Self) ?f32 {
        const self_position = if (self.position) |p| p.swizzle("xy") else return null;
        const other_position = if (other.position) |p| p.swizzle("xy") else return null;
        const self_cylinders = self.hurt_cylinders orelse return null;
        const other_cylinders = other.hurt_cylinders orelse return null;

        const position_difference = other_position.subtract(self_position);
        const self_to_other_direction = if (!position_difference.isZero(0.0001)) block: {
            break :block position_difference.normalize();
        } else block: {
            break :block sdk.math.Vec2.plus_x;
        };
        const other_to_self_direction = self_to_other_direction.negate();

        var max_self_projection = -std.math.inf(f32);
        for (&self_cylinders.values) |*hurt_cylinder| {
            const cylinder = &hurt_cylinder.cylinder;
            const center = cylinder.center.swizzle("xy").subtract(self_position);
            const center_projected = center.dot(self_to_other_direction);
            const edge = center_projected + cylinder.radius;
            max_self_projection = @max(max_self_projection, edge);
        }

        var max_other_projection = -std.math.inf(f32);

        for (&other_cylinders.values) |*hurt_cylinder| {
            const cylinder = &hurt_cylinder.cylinder;
            const center = cylinder.center.swizzle("xy").subtract(other_position);
            const center_projected = center.dot(other_to_self_direction);
            const edge = center_projected + cylinder.radius;
            max_other_projection = @max(max_other_projection, edge);
        }

        const distance = other_position.distanceTo(self_position) - max_self_projection - max_other_projection;
        return distance;
    }

    pub fn getAngleTo(self: *const Self, other: *const Self) ?f32 {
        const self_position = self.position orelse return null;
        const other_position = other.position orelse return null;
        const other_rotation = other.rotation orelse return null;
        const difference_2d = self_position.swizzle("xy").subtract(other_position.swizzle("xy"));
        const difference_rotation = std.math.atan2(difference_2d.y(), difference_2d.x());
        return std.math.wrap(other_rotation - difference_rotation, std.math.pi);
    }

    pub fn getHurtCylindersHeight(self: *const Self, floor_z: ?f32) model.F32MinMax {
        const cylinders: *const model.HurtCylinders = if (self.hurt_cylinders) |*c| c else {
            return .{ .min = null, .max = null };
        };
        const floor_height = floor_z orelse return .{ .min = null, .max = null };
        var min = std.math.inf(f32);
        var max = -std.math.inf(f32);
        for (&cylinders.values) |*hurt_cylinder| {
            const cylinder = &hurt_cylinder.cylinder;
            min = @min(min, cylinder.center.z() - cylinder.half_height);
            max = @max(max, cylinder.center.z() + cylinder.half_height);
        }
        return .{ .min = @max(min - floor_height, 0), .max = max - floor_height };
    }

    pub fn getHitLinesHeight(self: *const Self, floor_z: ?f32) model.F32MinMax {
        const lines = self.hit_lines.asConstSlice();
        if (lines.len == 0) {
            return .{ .min = null, .max = null };
        }
        const floor_height = floor_z orelse return .{ .min = null, .max = null };
        var min = std.math.inf(f32);
        var max = -std.math.inf(f32);
        for (lines) |*hit_line| {
            const line = &hit_line.line;
            min = @min(min, line.point_1.z());
            max = @max(max, line.point_1.z());
            min = @min(min, line.point_2.z());
            max = @max(max, line.point_2.z());
        }
        return .{ .min = @max(min - floor_height, 0), .max = max - floor_height };
    }

    pub fn getAttackHeight(self: *const Self, floor_z: ?f32) model.F32MinMax {
        const floor_height = floor_z orelse return .{ .min = null, .max = null };
        if (self.move_phase == .active or self.move_phase == .active_recovery) {
            return .{ .min = null, .max = null };
        }
        return .{
            .min = if (self.min_hit_lines_z) |z| @max(z - floor_height, 0) else null,
            .max = if (self.max_hit_lines_z) |z| @max(z - floor_height, 0) else null,
        };
    }
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

test "Player.getStartupFrames should return correct value" {
    try testing.expectEqual(model.U32ActualMinMax{ .actual = 2, .min = 1, .max = 3 }, (Player{
        .move_first_active_frame = 1,
        .move_connected_frame = 2,
        .move_last_active_frame = 3,
    }).getStartupFrames());
    try testing.expectEqual(model.U32ActualMinMax{ .actual = 2, .min = null, .max = 3 }, (Player{
        .move_first_active_frame = null,
        .move_connected_frame = 2,
        .move_last_active_frame = 3,
    }).getStartupFrames());
    try testing.expectEqual(model.U32ActualMinMax{ .actual = null, .min = 1, .max = 3 }, (Player{
        .move_first_active_frame = 1,
        .move_connected_frame = null,
        .move_last_active_frame = 3,
    }).getStartupFrames());
    try testing.expectEqual(model.U32ActualMinMax{ .actual = 2, .min = 1, .max = null }, (Player{
        .move_first_active_frame = 1,
        .move_connected_frame = 2,
        .move_last_active_frame = null,
    }).getStartupFrames());
}

test "Player.getActiveFrames should return correct value" {
    try testing.expectEqual(model.U32ActualMax{ .actual = 2, .max = 3 }, (Player{
        .move_first_active_frame = 1,
        .move_connected_frame = 2,
        .move_last_active_frame = 3,
    }).getActiveFrames());
    try testing.expectEqual(model.U32ActualMax{ .actual = null, .max = null }, (Player{
        .move_first_active_frame = null,
        .move_connected_frame = 2,
        .move_last_active_frame = 3,
    }).getActiveFrames());
    try testing.expectEqual(model.U32ActualMax{ .actual = 3, .max = 3 }, (Player{
        .move_first_active_frame = 1,
        .move_connected_frame = null,
        .move_last_active_frame = 3,
    }).getActiveFrames());
    try testing.expectEqual(model.U32ActualMax{ .actual = 2, .max = null }, (Player{
        .move_first_active_frame = 1,
        .move_connected_frame = 2,
        .move_last_active_frame = null,
    }).getActiveFrames());
}

test "Player.getRecoveryFrames should return correct value" {
    try testing.expectEqual(model.U32ActualMinMax{ .actual = 3, .min = 2, .max = 4 }, (Player{
        .move_phase = .recovery,
        .attack_type = .mid,
        .move_first_active_frame = 1,
        .move_connected_frame = 2,
        .move_last_active_frame = 3,
        .move_total_frames = 5,
    }).getRecoveryFrames());
    try testing.expectEqual(model.U32ActualMinMax{ .actual = 3, .min = 2, .max = null }, (Player{
        .move_phase = .recovery,
        .attack_type = .mid,
        .move_first_active_frame = null,
        .move_connected_frame = 2,
        .move_last_active_frame = 3,
        .move_total_frames = 5,
    }).getRecoveryFrames());
    try testing.expectEqual(model.U32ActualMinMax{ .actual = 2, .min = 2, .max = 4 }, (Player{
        .move_phase = .recovery,
        .attack_type = .mid,
        .move_first_active_frame = 1,
        .move_connected_frame = null,
        .move_last_active_frame = 3,
        .move_total_frames = 5,
    }).getRecoveryFrames());
    try testing.expectEqual(model.U32ActualMinMax{ .actual = 3, .min = null, .max = 4 }, (Player{
        .move_phase = .recovery,
        .attack_type = .mid,
        .move_first_active_frame = 1,
        .move_connected_frame = 2,
        .move_last_active_frame = null,
        .move_total_frames = 5,
    }).getRecoveryFrames());
    try testing.expectEqual(model.U32ActualMinMax{ .actual = null, .min = null, .max = null }, (Player{
        .move_phase = .recovery,
        .attack_type = .mid,
        .move_first_active_frame = 1,
        .move_connected_frame = 2,
        .move_last_active_frame = 3,
        .move_total_frames = null,
    }).getRecoveryFrames());
    try testing.expectEqual(model.U32ActualMinMax{ .actual = 5, .min = 5, .max = 5 }, (Player{
        .move_phase = .recovery,
        .attack_type = .not_attack,
        .move_first_active_frame = null,
        .move_connected_frame = null,
        .move_last_active_frame = null,
        .move_total_frames = 5,
    }).getRecoveryFrames());
}

test "Player.getFrameAdvantage should return correct value" {
    const player_1 = Player{
        .move_phase = .recovery,
        .attack_type = .mid,
        .move_first_active_frame = 1,
        .move_connected_frame = 2,
        .move_last_active_frame = 3,
        .move_total_frames = 5,
    };
    const player_2 = Player{
        .move_phase = .recovery,
        .attack_type = .not_attack,
        .move_first_active_frame = null,
        .move_connected_frame = null,
        .move_last_active_frame = null,
        .move_total_frames = 5,
    };
    try testing.expectEqual(
        model.I32ActualMinMax{ .actual = 2, .min = 1, .max = 3 },
        player_1.getFrameAdvantage(&player_2),
    );
    try testing.expectEqual(
        model.I32ActualMinMax{ .actual = -2, .min = -3, .max = -1 },
        player_2.getFrameAdvantage(&player_1),
    );
}

// TODO test getDistanceTo, getAngleTo, getHurtCylindersHeight, getHitLinesHeight, getAttackHeight
