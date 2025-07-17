const std = @import("std");
const math = @import("../math/root.zig");
const game = @import("../game/root.zig");

pub const Frame = struct {
    frames_since_round_start: ?u32 = null,
    floor_z: ?f32 = null,
    players: [2]Player = .{ .{}, .{} },
    left_player_id: PlayerId = .player_1,
    main_player_id: PlayerId = .player_1,

    const Self = @This();

    pub fn getPlayerById(self: *const Self, id: PlayerId) *const Player {
        switch (id) {
            .player_1 => return &self.players[0],
            .player_2 => return &self.players[1],
        }
    }

    pub fn getPlayerBySide(self: *const Self, side: PlayerSide) *const Player {
        return switch (side) {
            .left => return self.getPlayerById(self.left_player_id),
            .right => return self.getPlayerById(self.left_player_id.getOther()),
        };
    }

    pub fn getPlayerByRole(self: *const Self, role: PlayerRole) *const Player {
        return switch (role) {
            .main => return self.getPlayerById(self.main_player_id),
            .secondary => return self.getPlayerById(self.main_player_id.getOther()),
        };
    }
};

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
    current_move_frame: ?u32 = null,
    position: ?math.Vec3 = null,
    rotation: ?f32 = null,
    skeleton: ?Skeleton = null,
    hurt_cylinders: ?HurtCylinders = null,
    collision_spheres: ?CollisionSpheres = null,
    hit_lines: HitLines = .{},
};

pub const SkeletonPointId = enum {
    head,
    neck,
    upper_torso,
    left_shoulder,
    right_shoulder,
    left_elbow,
    right_elbow,
    left_hand,
    right_hand,
    lower_torso,
    left_pelvis,
    right_pelvis,
    left_knee,
    right_knee,
    left_ankle,
    right_ankle,
};

pub const SkeletonPoint = math.Vec3;

pub const Skeleton = std.EnumArray(SkeletonPointId, SkeletonPoint);

pub const HurtCylinderId = enum {
    left_ankle,
    right_ankle,
    left_hand,
    right_hand,
    left_knee,
    right_knee,
    left_elbow,
    right_elbow,
    head,
    left_shoulder,
    right_shoulder,
    upper_torso,
    left_pelvis,
    right_pelvis,
};

pub const HurtCylinder = struct {
    cylinder: math.Cylinder,
    intersects: bool,
};

pub const HurtCylinders = std.EnumArray(HurtCylinderId, HurtCylinder);

pub const CollisionSphereId = enum {
    neck,
    left_elbow,
    right_elbow,
    lower_torso,
    left_knee,
    right_knee,
    left_ankle,
    right_ankle,
};

pub const CollisionSphere = math.Sphere;

pub const CollisionSpheres = std.EnumArray(CollisionSphereId, CollisionSphere);

pub const HitLine = struct {
    line: math.LineSegment3,
    intersects: bool,
};

pub const HitLines = struct {
    buffer: [max_len]HitLine = undefined,
    len: usize = 0,

    const Self = @This();

    pub const max_len = @typeInfo(game.HitLines).array.len * 2;

    pub fn asConstSlice(self: *const Self) []const HitLine {
        return self.buffer[0..self.len];
    }

    pub fn asMutableSlice(self: *Self) []HitLine {
        return self.buffer[0..self.len];
    }
};

const testing = std.testing;

test "Frame.getPlayerById should return correct player" {
    const frame = Frame{};
    try testing.expectEqual(&frame.players[0], frame.getPlayerById(.player_1));
    try testing.expectEqual(&frame.players[1], frame.getPlayerById(.player_2));
}

test "Frame.getPlayerBySide should return correct player" {
    const frame_1 = Frame{ .left_player_id = .player_1 };
    const frame_2 = Frame{ .left_player_id = .player_2 };
    try testing.expectEqual(&frame_1.players[0], frame_1.getPlayerBySide(.left));
    try testing.expectEqual(&frame_1.players[1], frame_1.getPlayerBySide(.right));
    try testing.expectEqual(&frame_2.players[1], frame_2.getPlayerBySide(.left));
    try testing.expectEqual(&frame_2.players[0], frame_2.getPlayerBySide(.right));
}

test "Frame.getPlayerByRole should return correct player" {
    const frame_1 = Frame{ .main_player_id = .player_1 };
    const frame_2 = Frame{ .main_player_id = .player_2 };
    try testing.expectEqual(&frame_1.players[0], frame_1.getPlayerByRole(.main));
    try testing.expectEqual(&frame_1.players[1], frame_1.getPlayerByRole(.secondary));
    try testing.expectEqual(&frame_2.players[1], frame_2.getPlayerByRole(.main));
    try testing.expectEqual(&frame_2.players[0], frame_2.getPlayerByRole(.secondary));
}

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

test "HitLines.asConstSlice,asMutableSlice should return correct value" {
    const line_1 = HitLine{
        .line = .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
        .intersects = false,
    };
    const line_2 = HitLine{
        .line = .{ .point_1 = .fromArray(.{ 7, 8, 9 }), .point_2 = .fromArray(.{ 10, 11, 12 }) },
        .intersects = true,
    };
    var lines = HitLines{};
    lines.buffer[0] = line_1;
    lines.buffer[1] = line_2;
    lines.len = 2;
    try testing.expectEqualSlices(HitLine, &.{ line_1, line_2 }, lines.asConstSlice());
    try testing.expectEqualSlices(HitLine, &.{ line_1, line_2 }, lines.asMutableSlice());
}
