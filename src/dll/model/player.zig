const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("root.zig");

pub const PlayerId = enum(u8) {
    player_1 = 0,
    player_2 = 1,

    const Self = @This();
    pub const all = [2]Self{ .player_1, .player_2 };

    pub fn getOther(self: Self) Self {
        switch (self) {
            .player_1 => return .player_2,
            .player_2 => return .player_1,
        }
    }
};

pub const PlayerSide = enum(u8) {
    left = 0,
    right = 1,

    const Self = @This();
    pub const all = [2]Self{ .left, .right };

    pub fn getOther(self: Self) Self {
        switch (self) {
            .left => return .right,
            .right => return .left,
        }
    }
};

pub const PlayerRole = enum(u8) {
    main = 0,
    secondary = 1,

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
    animation_id: ?u32 = null,
    animation_frame: ?u32 = null,
    animation_total_frames: ?u32 = null,
    move_phase: ?model.MovePhase = null,
    move_frame: ?u32 = null,
    first_active_frame: ?u32 = null,
    last_active_frame: ?u32 = null,
    connected_frame: ?u32 = null,
    attack_type: ?model.AttackType = null,
    min_attack_z: ?f32 = null,
    max_attack_z: ?f32 = null,
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
    hurt_cylinders: ?model.HurtCylinders = null,
    collision_spheres: ?model.CollisionSpheres = null,
    hit_lines: model.HitLines = .{},

    const Self = @This();

    pub fn getSkeleton(self: *const Self) ?model.Skeleton {
        const cylinders: *const model.HurtCylinders = if (self.hurt_cylinders) |*c| c else return null;
        const spheres: *const model.CollisionSpheres = if (self.collision_spheres) |*s| s else return null;
        return .init(.{
            .head = cylinders.getPtrConst(.head).cylinder.center,
            .neck = spheres.getPtrConst(.neck).center,
            .upper_torso = cylinders.getPtrConst(.upper_torso).cylinder.center,
            .left_shoulder = cylinders.getPtrConst(.left_shoulder).cylinder.center,
            .right_shoulder = cylinders.getPtrConst(.right_shoulder).cylinder.center,
            .left_elbow = cylinders.getPtrConst(.left_elbow).cylinder.center,
            .right_elbow = cylinders.getPtrConst(.right_elbow).cylinder.center,
            .left_hand = cylinders.getPtrConst(.left_hand).cylinder.center,
            .right_hand = cylinders.getPtrConst(.right_hand).cylinder.center,
            .lower_torso = spheres.getPtrConst(.lower_torso).center,
            .left_pelvis = cylinders.getPtrConst(.left_pelvis).cylinder.center,
            .right_pelvis = cylinders.getPtrConst(.right_pelvis).cylinder.center,
            .left_knee = cylinders.getPtrConst(.left_knee).cylinder.center,
            .right_knee = cylinders.getPtrConst(.right_knee).cylinder.center,
            .left_ankle = cylinders.getPtrConst(.left_ankle).cylinder.center,
            .right_ankle = cylinders.getPtrConst(.right_ankle).cylinder.center,
        });
    }

    pub fn getStartupFrames(self: *const Self) model.U32ActualMinMax {
        return .{
            .actual = self.connected_frame,
            .min = self.first_active_frame,
            .max = self.last_active_frame,
        };
    }

    pub fn getActiveFrames(self: *const Self) model.U32ActualMax {
        const first_active_frame = self.first_active_frame orelse return .{
            .actual = null,
            .max = null,
        };
        const connected_or_whiffed_frame = self.connected_frame orelse self.last_active_frame;
        return .{
            .actual = if (connected_or_whiffed_frame) |frame| 1 + frame -| first_active_frame else null,
            .max = if (self.last_active_frame) |frame| 1 + frame -| first_active_frame else null,
        };
    }

    pub fn getRecoveryFrames(self: *const Self) model.U32ActualMinMax {
        const total = self.getTotalFrames() orelse return .{
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
        const connected_or_whiffed_frame = self.connected_frame orelse self.last_active_frame;
        return .{
            .actual = if (connected_or_whiffed_frame) |frame| total -| frame else null,
            .min = if (self.last_active_frame) |frame| total -| frame else null,
            .max = if (self.first_active_frame) |frame| total -| frame else null,
        };
    }

    pub fn getTotalFrames(self: *const Self) ?u32 {
        const animation_total = self.animation_total_frames orelse return null;
        const animation_frame = self.animation_frame orelse return null;
        const move_frame = self.move_frame orelse return null;
        return animation_total +| move_frame -| animation_frame;
    }

    pub fn getFrameAdvantage(self: *const Self, other: *const Self) model.I32ActualMinMax {
        if (self.move_phase != .recovery or other.move_phase != .recovery) {
            return .{
                .actual = null,
                .min = null,
                .max = null,
            };
        }
        const self_current = self.animation_frame orelse return .{
            .actual = null,
            .min = null,
            .max = null,
        };
        const self_total = self.animation_total_frames orelse return .{
            .actual = null,
            .min = null,
            .max = null,
        };
        const other_current = other.animation_frame orelse return .{
            .actual = null,
            .min = null,
            .max = null,
        };
        const other_total = other.animation_total_frames orelse return .{
            .actual = null,
            .min = null,
            .max = null,
        };
        const self_remaining = self_total -| self_current;
        const other_remaining = other_total -| other_current;
        const actual_advantage = @as(i32, @intCast(other_remaining)) -% @as(i32, @intCast(self_remaining));
        const self_recovery = self.getRecoveryFrames();
        const other_recovery = other.getRecoveryFrames();
        const recovery_advantage = model.I32ActualMinMax{
            .actual = if (other_recovery.actual != null and self_recovery.actual != null) block: {
                break :block @as(i32, @intCast(other_recovery.actual.?)) -% @as(i32, @intCast(self_recovery.actual.?));
            } else null,
            .min = if (other_recovery.min != null and self_recovery.max != null) block: {
                break :block @as(i32, @intCast(other_recovery.min.?)) -% @as(i32, @intCast(self_recovery.max.?));
            } else null,
            .max = if (other_recovery.max != null and self_recovery.min != null) block: {
                break :block @as(i32, @intCast(other_recovery.max.?)) -% @as(i32, @intCast(self_recovery.min.?));
            } else null,
        };
        return .{
            .actual = actual_advantage,
            .min = if (recovery_advantage.min != null and recovery_advantage.actual != null) block: {
                break :block recovery_advantage.min.? -% recovery_advantage.actual.? +% actual_advantage;
            } else null,
            .max = if (recovery_advantage.max != null and recovery_advantage.actual != null) block: {
                break :block recovery_advantage.max.? -% recovery_advantage.actual.? +% actual_advantage;
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
            const center = cylinder.center.swizzle("xy");
            const center_projection = center.subtract(self_position).dot(self_to_other_direction);
            const edge_projection = center_projection + cylinder.radius;
            max_self_projection = @max(max_self_projection, edge_projection);
        }

        var max_other_projection = -std.math.inf(f32);
        for (&other_cylinders.values) |*hurt_cylinder| {
            const cylinder = &hurt_cylinder.cylinder;
            const center = cylinder.center.swizzle("xy");
            const center_projection = center.subtract(other_position).dot(other_to_self_direction);
            const edge_projection = center_projection + cylinder.radius;
            max_other_projection = @max(max_other_projection, edge_projection);
        }

        return other_position.distanceTo(self_position) - max_self_projection - max_other_projection;
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
        return .{ .min = @max(min - floor_height, 0), .max = @max(max - floor_height, 0) };
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
        return .{ .min = @max(min - floor_height, 0), .max = @max(max - floor_height, 0) };
    }

    pub fn getAttackHeight(self: *const Self, floor_z: ?f32) model.F32MinMax {
        const floor_height = floor_z orelse return .{ .min = null, .max = null };
        if (self.move_phase == .active or self.move_phase == .active_recovery) {
            return .{ .min = null, .max = null };
        }
        return .{
            .min = if (self.min_attack_z) |z| @max(z - floor_height, 0) else null,
            .max = if (self.max_attack_z) |z| @max(z - floor_height, 0) else null,
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

test "Player.getSkeleton should return correct value" {
    const cylinder = struct {
        fn call(x: f32, y: f32, z: f32) model.HurtCylinder {
            return .{ .cylinder = .{
                .center = .fromArray(.{ x, y, z }),
                .radius = 0.0,
                .half_height = 0.0,
            } };
        }
    }.call;
    const sphere = struct {
        fn call(x: f32, y: f32, z: f32) model.CollisionSphere {
            return .{
                .center = .fromArray(.{ x, y, z }),
                .radius = 0.0,
            };
        }
    }.call;
    const player = Player{
        .hurt_cylinders = .init(.{
            .left_ankle = cylinder(43, 44, 45),
            .right_ankle = cylinder(46, 47, 48),
            .left_hand = cylinder(22, 23, 24),
            .right_hand = cylinder(25, 26, 27),
            .left_knee = cylinder(37, 38, 39),
            .right_knee = cylinder(40, 41, 42),
            .left_elbow = cylinder(16, 17, 18),
            .right_elbow = cylinder(19, 20, 21),
            .head = cylinder(1, 2, 3),
            .left_shoulder = cylinder(10, 11, 12),
            .right_shoulder = cylinder(13, 14, 15),
            .upper_torso = cylinder(7, 8, 9),
            .left_pelvis = cylinder(31, 32, 33),
            .right_pelvis = cylinder(34, 35, 36),
        }),
        .collision_spheres = .init(.{
            .neck = sphere(4, 5, 6),
            .left_elbow = sphere(16, 17, 18),
            .right_elbow = sphere(19, 20, 21),
            .lower_torso = sphere(28, 29, 30),
            .left_knee = sphere(37, 38, 39),
            .right_knee = sphere(40, 41, 42),
            .left_ankle = sphere(43, 44, 45),
            .right_ankle = sphere(46, 47, 48),
        }),
    };
    try testing.expectEqual(model.Skeleton.init(.{
        .head = .fromArray(.{ 1, 2, 3 }),
        .neck = .fromArray(.{ 4, 5, 6 }),
        .upper_torso = .fromArray(.{ 7, 8, 9 }),
        .left_shoulder = .fromArray(.{ 10, 11, 12 }),
        .right_shoulder = .fromArray(.{ 13, 14, 15 }),
        .left_elbow = .fromArray(.{ 16, 17, 18 }),
        .right_elbow = .fromArray(.{ 19, 20, 21 }),
        .left_hand = .fromArray(.{ 22, 23, 24 }),
        .right_hand = .fromArray(.{ 25, 26, 27 }),
        .lower_torso = .fromArray(.{ 28, 29, 30 }),
        .left_pelvis = .fromArray(.{ 31, 32, 33 }),
        .right_pelvis = .fromArray(.{ 34, 35, 36 }),
        .left_knee = .fromArray(.{ 37, 38, 39 }),
        .right_knee = .fromArray(.{ 40, 41, 42 }),
        .left_ankle = .fromArray(.{ 43, 44, 45 }),
        .right_ankle = .fromArray(.{ 46, 47, 48 }),
    }), player.getSkeleton());
    try testing.expectEqual(null, (Player{}).getSkeleton());
}

test "Player.getStartupFrames should return correct value" {
    try testing.expectEqual(model.U32ActualMinMax{ .actual = 2, .min = 1, .max = 3 }, (Player{
        .first_active_frame = 1,
        .connected_frame = 2,
        .last_active_frame = 3,
    }).getStartupFrames());
    try testing.expectEqual(model.U32ActualMinMax{ .actual = 2, .min = null, .max = 3 }, (Player{
        .first_active_frame = null,
        .connected_frame = 2,
        .last_active_frame = 3,
    }).getStartupFrames());
    try testing.expectEqual(model.U32ActualMinMax{ .actual = null, .min = 1, .max = 3 }, (Player{
        .first_active_frame = 1,
        .connected_frame = null,
        .last_active_frame = 3,
    }).getStartupFrames());
    try testing.expectEqual(model.U32ActualMinMax{ .actual = 2, .min = 1, .max = null }, (Player{
        .first_active_frame = 1,
        .connected_frame = 2,
        .last_active_frame = null,
    }).getStartupFrames());
}

test "Player.getActiveFrames should return correct value" {
    try testing.expectEqual(model.U32ActualMax{ .actual = 2, .max = 3 }, (Player{
        .first_active_frame = 1,
        .connected_frame = 2,
        .last_active_frame = 3,
    }).getActiveFrames());
    try testing.expectEqual(model.U32ActualMax{ .actual = null, .max = null }, (Player{
        .first_active_frame = null,
        .connected_frame = 2,
        .last_active_frame = 3,
    }).getActiveFrames());
    try testing.expectEqual(model.U32ActualMax{ .actual = 3, .max = 3 }, (Player{
        .first_active_frame = 1,
        .connected_frame = null,
        .last_active_frame = 3,
    }).getActiveFrames());
    try testing.expectEqual(model.U32ActualMax{ .actual = 2, .max = null }, (Player{
        .first_active_frame = 1,
        .connected_frame = 2,
        .last_active_frame = null,
    }).getActiveFrames());
}

test "Player.getRecoveryFrames should return correct value" {
    try testing.expectEqual(model.U32ActualMinMax{ .actual = 3, .min = 2, .max = 4 }, (Player{
        .move_phase = .recovery,
        .attack_type = .mid,
        .first_active_frame = 1,
        .connected_frame = 2,
        .last_active_frame = 3,
        .animation_frame = 5,
        .move_frame = 4,
        .animation_total_frames = 6,
    }).getRecoveryFrames());
    try testing.expectEqual(model.U32ActualMinMax{ .actual = 3, .min = 2, .max = null }, (Player{
        .move_phase = .recovery,
        .attack_type = .mid,
        .first_active_frame = null,
        .connected_frame = 2,
        .last_active_frame = 3,
        .animation_frame = 5,
        .move_frame = 4,
        .animation_total_frames = 6,
    }).getRecoveryFrames());
    try testing.expectEqual(model.U32ActualMinMax{ .actual = 2, .min = 2, .max = 4 }, (Player{
        .move_phase = .recovery,
        .attack_type = .mid,
        .first_active_frame = 1,
        .connected_frame = null,
        .last_active_frame = 3,
        .animation_frame = 5,
        .move_frame = 4,
        .animation_total_frames = 6,
    }).getRecoveryFrames());
    try testing.expectEqual(model.U32ActualMinMax{ .actual = 3, .min = null, .max = 4 }, (Player{
        .move_phase = .recovery,
        .attack_type = .mid,
        .first_active_frame = 1,
        .connected_frame = 2,
        .last_active_frame = null,
        .animation_frame = 5,
        .move_frame = 4,
        .animation_total_frames = 6,
    }).getRecoveryFrames());
    try testing.expectEqual(model.U32ActualMinMax{ .actual = null, .min = null, .max = null }, (Player{
        .move_phase = .recovery,
        .attack_type = .mid,
        .first_active_frame = 1,
        .connected_frame = 2,
        .last_active_frame = 3,
        .animation_frame = 5,
        .move_frame = 4,
        .animation_total_frames = null,
    }).getRecoveryFrames());
    try testing.expectEqual(model.U32ActualMinMax{ .actual = 5, .min = 5, .max = 5 }, (Player{
        .move_phase = .recovery,
        .attack_type = .not_attack,
        .first_active_frame = null,
        .connected_frame = null,
        .last_active_frame = null,
        .animation_frame = 5,
        .move_frame = 4,
        .animation_total_frames = 6,
    }).getRecoveryFrames());
}

test "Player.getTotalFrames should return correct value" {
    try testing.expectEqual(4, (Player{
        .animation_frame = 3,
        .move_frame = 2,
        .animation_total_frames = 5,
    }).getTotalFrames());
    try testing.expectEqual(null, (Player{
        .animation_frame = null,
        .move_frame = 2,
        .animation_total_frames = 5,
    }).getTotalFrames());
    try testing.expectEqual(null, (Player{
        .animation_frame = 3,
        .move_frame = null,
        .animation_total_frames = 5,
    }).getTotalFrames());
    try testing.expectEqual(null, (Player{
        .animation_frame = 3,
        .move_frame = 2,
        .animation_total_frames = null,
    }).getTotalFrames());
}

test "Player.getFrameAdvantage should return correct value" {
    const player_1 = Player{
        .move_phase = .recovery,
        .attack_type = .mid,
        .first_active_frame = 1,
        .connected_frame = 2,
        .last_active_frame = 3,
        .animation_frame = 5,
        .move_frame = 4,
        .animation_total_frames = 6,
    };
    const player_2 = Player{
        .move_phase = .recovery,
        .attack_type = .not_attack,
        .first_active_frame = null,
        .connected_frame = null,
        .last_active_frame = null,
        .animation_frame = 3,
        .move_frame = 2,
        .animation_total_frames = 6,
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

test "Player.getDistanceTo should return correct value" {
    const player_1 = Player{
        .position = .fromArray(.{ -5, 0, 0 }),
        .hurt_cylinders = .init(.{
            .left_ankle = .{ .cylinder = .{ .center = .fromArray(.{ -5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .right_ankle = .{ .cylinder = .{ .center = .fromArray(.{ -5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .left_hand = .{ .cylinder = .{ .center = .fromArray(.{ -5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .right_hand = .{ .cylinder = .{ .center = .fromArray(.{ -6, 1, 0 }), .radius = 3, .half_height = 1 } },
            .left_knee = .{ .cylinder = .{ .center = .fromArray(.{ -5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .right_knee = .{ .cylinder = .{ .center = .fromArray(.{ -5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .left_elbow = .{ .cylinder = .{ .center = .fromArray(.{ -5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .right_elbow = .{ .cylinder = .{ .center = .fromArray(.{ -5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .head = .{ .cylinder = .{ .center = .fromArray(.{ -5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .left_shoulder = .{ .cylinder = .{ .center = .fromArray(.{ -5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .right_shoulder = .{ .cylinder = .{ .center = .fromArray(.{ -5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .upper_torso = .{ .cylinder = .{ .center = .fromArray(.{ -5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .left_pelvis = .{ .cylinder = .{ .center = .fromArray(.{ -5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .right_pelvis = .{ .cylinder = .{ .center = .fromArray(.{ -5, 0, 0 }), .radius = 1, .half_height = 1 } },
        }),
    };
    const player_2 = Player{
        .position = .fromArray(.{ 5, 0, 0 }),
        .hurt_cylinders = .init(.{
            .left_ankle = .{ .cylinder = .{ .center = .fromArray(.{ 5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .right_ankle = .{ .cylinder = .{ .center = .fromArray(.{ 5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .left_hand = .{ .cylinder = .{ .center = .fromArray(.{ 6, 1, 0 }), .radius = 3, .half_height = 1 } },
            .right_hand = .{ .cylinder = .{ .center = .fromArray(.{ 5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .left_knee = .{ .cylinder = .{ .center = .fromArray(.{ 5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .right_knee = .{ .cylinder = .{ .center = .fromArray(.{ 5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .left_elbow = .{ .cylinder = .{ .center = .fromArray(.{ 5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .right_elbow = .{ .cylinder = .{ .center = .fromArray(.{ 5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .head = .{ .cylinder = .{ .center = .fromArray(.{ 5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .left_shoulder = .{ .cylinder = .{ .center = .fromArray(.{ 5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .right_shoulder = .{ .cylinder = .{ .center = .fromArray(.{ 5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .upper_torso = .{ .cylinder = .{ .center = .fromArray(.{ 5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .left_pelvis = .{ .cylinder = .{ .center = .fromArray(.{ 5, 0, 0 }), .radius = 1, .half_height = 1 } },
            .right_pelvis = .{ .cylinder = .{ .center = .fromArray(.{ 5, 0, 0 }), .radius = 1, .half_height = 1 } },
        }),
    };
    try testing.expectEqual(6.0, player_1.getDistanceTo(&player_2));
    try testing.expectEqual(6.0, player_2.getDistanceTo(&player_1));
    var player_3 = player_1;
    player_3.position = null;
    var player_4 = player_2;
    player_4.hurt_cylinders = null;
    try testing.expectEqual(null, player_2.getDistanceTo(&player_3));
    try testing.expectEqual(null, player_3.getDistanceTo(&player_2));
    try testing.expectEqual(null, player_1.getDistanceTo(&player_4));
    try testing.expectEqual(null, player_4.getDistanceTo(&player_1));
}

test "Player.getAngleTo should return correct value" {
    const player_1 = Player{ .position = .fromArray(.{ 0, 0, 0 }), .rotation = 0 };
    const player_2 = Player{ .position = .fromArray(.{ 1, 0, 0 }), .rotation = -std.math.pi };
    const player_3 = Player{ .position = .fromArray(.{ 0, 1, 0 }), .rotation = -std.math.pi };
    const player_4 = Player{ .position = .fromArray(.{ 1, 1, 0 }), .rotation = null };

    try testing.expect(player_2.getAngleTo(&player_1) != null);
    try testing.expect(player_3.getAngleTo(&player_1) != null);
    try testing.expect(player_4.getAngleTo(&player_1) != null);
    try testing.expectApproxEqAbs(0.0, player_2.getAngleTo(&player_1).?, 0.000001);
    try testing.expectApproxEqAbs(-0.5 * std.math.pi, player_3.getAngleTo(&player_1).?, 0.000001);
    try testing.expectApproxEqAbs(-0.25 * std.math.pi, player_4.getAngleTo(&player_1).?, 0.000001);

    try testing.expect(player_1.getAngleTo(&player_2) != null);
    try testing.expect(player_3.getAngleTo(&player_2) != null);
    try testing.expect(player_4.getAngleTo(&player_2) != null);
    try testing.expectApproxEqAbs(0.0, player_1.getAngleTo(&player_2).?, 0.000001);
    try testing.expectApproxEqAbs(0.25 * std.math.pi, player_3.getAngleTo(&player_2).?, 0.000001);
    try testing.expectApproxEqAbs(0.5 * std.math.pi, player_4.getAngleTo(&player_2).?, 0.000001);

    try testing.expect(player_1.getAngleTo(&player_3) != null);
    try testing.expect(player_2.getAngleTo(&player_3) != null);
    try testing.expect(player_4.getAngleTo(&player_3) != null);
    try testing.expectApproxEqAbs(-0.5 * std.math.pi, player_1.getAngleTo(&player_3).?, 0.000001);
    try testing.expectApproxEqAbs(-0.75 * std.math.pi, player_2.getAngleTo(&player_3).?, 0.000001);
    try testing.expectApproxEqAbs(-std.math.pi, player_4.getAngleTo(&player_3).?, 0.000001);

    try testing.expectEqual(null, player_1.getAngleTo(&player_4));
    try testing.expectEqual(null, player_2.getAngleTo(&player_4));
    try testing.expectEqual(null, player_3.getAngleTo(&player_4));
}

test "Player.getHurtCylindersHeight should return correct value" {
    const player = Player{
        .hurt_cylinders = .init(.{
            .left_ankle = .{ .cylinder = .{ .center = .fromArray(.{ 1, 14, -7 }), .radius = 1, .half_height = 1 } },
            .right_ankle = .{ .cylinder = .{ .center = .fromArray(.{ 2, 13, -6 }), .radius = 2, .half_height = 3 } },
            .left_hand = .{ .cylinder = .{ .center = .fromArray(.{ 3, 12, -5 }), .radius = 3, .half_height = 1 } },
            .right_hand = .{ .cylinder = .{ .center = .fromArray(.{ 4, 11, -4 }), .radius = 4, .half_height = 1 } },
            .left_knee = .{ .cylinder = .{ .center = .fromArray(.{ 5, 10, -3 }), .radius = 5, .half_height = 1 } },
            .right_knee = .{ .cylinder = .{ .center = .fromArray(.{ 6, 9, -2 }), .radius = 6, .half_height = 1 } },
            .left_elbow = .{ .cylinder = .{ .center = .fromArray(.{ 7, 8, -1 }), .radius = 7, .half_height = 1 } },
            .right_elbow = .{ .cylinder = .{ .center = .fromArray(.{ 8, 7, 0 }), .radius = 8, .half_height = 1 } },
            .head = .{ .cylinder = .{ .center = .fromArray(.{ 9, 6, 1 }), .radius = 9, .half_height = 1 } },
            .left_shoulder = .{ .cylinder = .{ .center = .fromArray(.{ 10, 5, 2 }), .radius = 10, .half_height = 1 } },
            .right_shoulder = .{ .cylinder = .{ .center = .fromArray(.{ 11, 4, 3 }), .radius = 11, .half_height = 1 } },
            .upper_torso = .{ .cylinder = .{ .center = .fromArray(.{ 12, 3, 4 }), .radius = 12, .half_height = 1 } },
            .left_pelvis = .{ .cylinder = .{ .center = .fromArray(.{ 13, 2, 5 }), .radius = 13, .half_height = 3 } },
            .right_pelvis = .{ .cylinder = .{ .center = .fromArray(.{ 14, 1, 6 }), .radius = 14, .half_height = 1 } },
        }),
    };
    try testing.expectEqual(model.F32MinMax{ .min = 0, .max = 8 }, player.getHurtCylindersHeight(0));
    try testing.expectEqual(model.F32MinMax{ .min = 1, .max = 18 }, player.getHurtCylindersHeight(-10));
    try testing.expectEqual(model.F32MinMax{ .min = 0, .max = 0 }, player.getHurtCylindersHeight(10));
    try testing.expectEqual(model.F32MinMax{ .min = null, .max = null }, player.getHurtCylindersHeight(null));
}

test "Player.getHitLinesHeight should return correct value" {
    const player = Player{
        .hit_lines = .{
            .buffer = .{
                .{ .line = .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) } },
                .{ .line = .{ .point_1 = .fromArray(.{ 7, 8, 9 }), .point_2 = .fromArray(.{ 10, 11, 12 }) } },
                .{ .line = .{ .point_1 = .fromArray(.{ 13, 14, 15 }), .point_2 = .fromArray(.{ 16, 17, 18 }) } },
                .{ .line = .{ .point_1 = .fromArray(.{ 19, 20, 21 }), .point_2 = .fromArray(.{ 22, 23, 24 }) } },
                .{ .line = .{ .point_1 = .fromArray(.{ 25, 26, 27 }), .point_2 = .fromArray(.{ 28, 29, 30 }) } },
                .{ .line = .{ .point_1 = .fromArray(.{ 31, 32, 33 }), .point_2 = .fromArray(.{ 34, 35, 36 }) } },
                .{ .line = .{ .point_1 = .fromArray(.{ 37, 38, 39 }), .point_2 = .fromArray(.{ 40, 41, 42 }) } },
                .{ .line = .{ .point_1 = .fromArray(.{ 43, 44, 45 }), .point_2 = .fromArray(.{ 46, 47, 48 }) } },
            },
            .len = 8,
        },
    };
    try testing.expectEqual(model.F32MinMax{ .min = 3, .max = 48 }, player.getHitLinesHeight(0));
    try testing.expectEqual(model.F32MinMax{ .min = 13, .max = 58 }, player.getHitLinesHeight(-10));
    try testing.expectEqual(model.F32MinMax{ .min = 0, .max = 38 }, player.getHitLinesHeight(10));
    try testing.expectEqual(model.F32MinMax{ .min = 0, .max = 0 }, player.getHitLinesHeight(50));
    try testing.expectEqual(model.F32MinMax{ .min = null, .max = null }, player.getHitLinesHeight(null));
    const no_lines_player = Player{ .hit_lines = .{ .buffer = undefined, .len = 0 } };
    try testing.expectEqual(model.F32MinMax{ .min = null, .max = null }, no_lines_player.getHitLinesHeight(0));
}

test "Player.getAttackHeight should return correct value" {
    const player = Player{ .min_attack_z = 1, .max_attack_z = 3 };
    try testing.expectEqual(model.F32MinMax{ .min = 1, .max = 3 }, player.getAttackHeight(0));
    try testing.expectEqual(model.F32MinMax{ .min = 11, .max = 13 }, player.getAttackHeight(-10));
    try testing.expectEqual(model.F32MinMax{ .min = 0, .max = 1 }, player.getAttackHeight(2));
    try testing.expectEqual(model.F32MinMax{ .min = 0, .max = 0 }, player.getAttackHeight(10));
    try testing.expectEqual(model.F32MinMax{ .min = null, .max = null }, player.getAttackHeight(null));
    const no_lines_player = Player{ .min_attack_z = null, .max_attack_z = null };
    try testing.expectEqual(model.F32MinMax{ .min = null, .max = null }, no_lines_player.getAttackHeight(0));
}
