const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

pub const Settings = struct {
    hit_lines: PlayerSettings(HitLinesSettings) = .{ .players = .{ .{}, .{} } },
    hurt_cylinders: PlayerSettings(HurtCylindersSettings) = .{ .players = .{ .{}, .{} } },
    collision_spheres: PlayerSettings(CollisionSpheresSettings) = .{ .players = .{ .{}, .{} } },
    skeletons: PlayerSettings(SkeletonSettings) = .{ .players = .{ .{}, .{} } },
    forward_directions: PlayerSettings(ForwardDirectionSettings) = .{ .players = .{ .{}, .{} } },
    floor: FloorSettings = .{},
    ingame_camera: IngameCameraSettings = .{},
};

pub const HitLinesSettings = struct {
    enabled: bool = true,
    normal: FillAndOutline = .{
        .fill = .{
            .colors = .init(.{
                .not_attack = .fromArray(.{ 0.5, 0.5, 0.5, 1.0 }),
                .high = .fromArray(.{ 1.0, 0.0, 0.0, 1.0 }),
                .mid = .fromArray(.{ 1.0, 1.0, 0.0, 1.0 }),
                .low = .fromArray(.{ 0.0, 0.5, 1.0, 1.0 }),
                .special_low = .fromArray(.{ 0.0, 1.0, 1.0, 1.0 }),
                .unblockable_high = .fromArray(.{ 1.0, 0.0, 0.0, 1.0 }),
                .unblockable_mid = .fromArray(.{ 1.0, 1.0, 0.0, 1.0 }),
                .unblockable_low = .fromArray(.{ 0.0, 0.5, 1.0, 1.0 }),
                .throw = .fromArray(.{ 1.0, 1.0, 1.0, 1.0 }),
                .projectile = .fromArray(.{ 0.5, 1.0, 0.5, 1.0 }),
                .antiair_only = .fromArray(.{ 1.0, 0.5, 0.0, 1.0 }),
            }),
            .thickness = 1.0,
        },
        .outline = .{
            .colors = .init(.{
                .not_attack = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                .high = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                .mid = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                .low = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                .special_low = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                .unblockable_high = .fromArray(.{ 0.75, 0.0, 0.75, 1.0 }),
                .unblockable_mid = .fromArray(.{ 0.75, 0.0, 0.75, 1.0 }),
                .unblockable_low = .fromArray(.{ 0.75, 0.0, 0.75, 1.0 }),
                .throw = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                .projectile = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                .antiair_only = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
            }),
            .thickness = 1.0,
        },
    },
    inactive_or_crushed: FillAndOutline = .{
        .fill = .{
            .colors = .init(.{
                .not_attack = .fromArray(.{ 0.5, 0.5, 0.5, 1.0 }),
                .high = .fromArray(.{ 0.5, 0.3, 0.3, 1.0 }),
                .mid = .fromArray(.{ 0.5, 0.5, 0.3, 1.0 }),
                .low = .fromArray(.{ 0.3, 0.35, 0.5, 1.0 }),
                .special_low = .fromArray(.{ 0.3, 0.5, 0.5, 1.0 }),
                .unblockable_high = .fromArray(.{ 0.5, 0.3, 0.3, 1.0 }),
                .unblockable_mid = .fromArray(.{ 0.5, 0.5, 0.3, 1.0 }),
                .unblockable_low = .fromArray(.{ 0.3, 0.35, 0.5, 1.0 }),
                .throw = .fromArray(.{ 0.5, 0.5, 0.5, 1.0 }),
                .projectile = .fromArray(.{ 0.35, 0.5, 0.35, 1.0 }),
                .antiair_only = .fromArray(.{ 0.5, 0.35, 0.3, 1.0 }),
            }),
            .thickness = 1.0,
        },
        .outline = .{
            .colors = .init(.{
                .not_attack = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                .high = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                .mid = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                .low = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                .special_low = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                .unblockable_high = .fromArray(.{ 0.4, 0.3, 0.4, 1.0 }),
                .unblockable_mid = .fromArray(.{ 0.4, 0.3, 0.4, 1.0 }),
                .unblockable_low = .fromArray(.{ 0.4, 0.3, 0.4, 1.0 }),
                .throw = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                .projectile = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                .antiair_only = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
            }),
            .thickness = 1.0,
        },
    },
    duration: f32 = 1.0,

    pub const FillAndOutline = struct {
        fill: ColorsAndThickness,
        outline: ColorsAndThickness,
    };
    pub const ColorsAndThickness = struct {
        colors: std.EnumArray(model.AttackType, sdk.math.Vec4),
        thickness: f32,
    };
};

pub const HurtCylindersSettings = struct {
    enabled: bool = true,
    normal: Crushing = .{
        .normal = .{ .color = .fromArray(.{ 0.5, 0.5, 0.5, 0.5 }), .thickness = 1.0 },
        .high_crushing = .{ .color = .fromArray(.{ 0.75, 0.0, 0.0, 0.5 }), .thickness = 1.0 },
        .low_crushing = .{ .color = .fromArray(.{ 0.0, 0.375, 0.75, 0.5 }), .thickness = 1.0 },
        .invincible = .{ .color = .fromArray(.{ 0.75, 0.0, 0.75, 0.5 }), .thickness = 1.0 },
    },
    power_crushing: Crushing = .{
        .normal = .{ .color = .fromArray(.{ 1.0, 1.0, 1.0, 1.0 }), .thickness = 1.0 },
        .high_crushing = .{ .color = .fromArray(.{ 1.0, 0.25, 0.25, 1.0 }), .thickness = 1.0 },
        .low_crushing = .{ .color = .fromArray(.{ 0.0, 0.25, 1.0, 1.0 }), .thickness = 1.0 },
        .invincible = .{ .color = .fromArray(.{ 1.0, 0.0, 1.0, 1.0 }), .thickness = 1.0 },
    },
    connected: ColorThicknessAndDuration = .{
        .color = .fromArray(.{ 1.0, 0.75, 0.25, 0.5 }),
        .thickness = 1.0,
        .duration = 1.0,
    },
    lingering: ColorThicknessAndDuration = .{
        .color = .fromArray(.{ 0.0, 0.75, 0.75, 0.5 }),
        .thickness = 1.0,
        .duration = 1.0,
    },

    pub const Crushing = struct {
        normal: ColorAndThickness,
        high_crushing: ColorAndThickness,
        low_crushing: ColorAndThickness,
        invincible: ColorAndThickness,
    };
    pub const ColorAndThickness = struct {
        color: sdk.math.Vec4,
        thickness: f32,
    };
    const ColorThicknessAndDuration = struct {
        color: sdk.math.Vec4,
        thickness: f32,
        duration: f32,
    };
};

pub const CollisionSpheresSettings = struct {
    enabled: bool = true,
    color: sdk.math.Vec4 = .fromArray(.{ 0.0, 0.0, 1.0, 0.5 }),
    thickness: f32 = 1.0,
};

pub const SkeletonSettings = struct {
    enabled: bool = true,
    colors: std.EnumArray(model.Blocking, sdk.math.Vec4) = .init(.{
        .not_blocking = .fromArray(.{ 1.0, 1.0, 1.0, 1.0 }),
        .neutral_blocking_mids = .fromArray(.{ 1.0, 1.0, 0.75, 1.0 }),
        .fully_blocking_mids = .fromArray(.{ 1.0, 1.0, 0.5, 1.0 }),
        .neutral_blocking_lows = .fromArray(.{ 0.75, 0.875, 1.0, 1.0 }),
        .fully_blocking_lows = .fromArray(.{ 0.5, 0.75, 1.0, 1.0 }),
    }),
    thickness: f32 = 2.0,
    cant_move_alpha: f32 = 0.5,
};

pub const ForwardDirectionSettings = struct {
    enabled: bool = true,
    color: sdk.math.Vec4 = .fromArray(.{ 1.0, 0.0, 1.0, 1.0 }),
    thickness: f32 = 1.0,
    length: f32 = 100.0,
};

pub const FloorSettings = struct {
    enabled: bool = true,
    color: sdk.math.Vec4 = .fromArray(.{ 0.0, 1.0, 0.0, 1.0 }),
    thickness: f32 = 1.0,
};

pub const IngameCameraSettings = struct {
    enabled: bool = false,
    color: sdk.math.Vec4 = .fromArray(.{ 1.0, 1.0, 1.0, 0.05 }),
    length: f32 = 800.0,
    thickness: f32 = 1.0,
};

pub const PlayerSettingsMode = enum {
    same,
    id_separated,
    side_separated,
    role_separated,
};

pub fn PlayerSettings(comptime Type: type) type {
    return struct {
        mode: PlayerSettingsMode = .same,
        players: [2]Type,

        const Self = @This();

        pub fn getById(self: *const Self, frame: *const model.Frame, id: model.PlayerId) *const Type {
            return switch (self.mode) {
                .same => &self.players[0],
                .id_separated => switch (id) {
                    .player_1 => &self.players[0],
                    .player_2 => &self.players[1],
                },
                .side_separated => if (frame.left_player_id == id) &self.players[0] else &self.players[1],
                .role_separated => if (frame.main_player_id == id) &self.players[0] else &self.players[1],
            };
        }

        pub fn getBySide(self: *const Self, frame: *const model.Frame, side: model.PlayerSide) *const Type {
            return switch (self.mode) {
                .same => &self.players[0],
                .id_separated => switch (frame.left_player_id) {
                    .player_1 => switch (side) {
                        .left => &self.players[0],
                        .right => &self.players[1],
                    },
                    .player_2 => switch (side) {
                        .left => &self.players[1],
                        .right => &self.players[0],
                    },
                },
                .side_separated => switch (side) {
                    .left => &self.players[0],
                    .right => &self.players[1],
                },
                .role_separated => switch (side) {
                    .left => if (frame.left_player_id == frame.main_player_id) &self.players[0] else &self.players[1],
                    .right => if (frame.left_player_id == frame.main_player_id) &self.players[1] else &self.players[0],
                },
            };
        }

        pub fn getByRole(self: *const Self, frame: *const model.Frame, role: model.PlayerRole) *const Type {
            return switch (self.mode) {
                .same => &self.players[0],
                .id_separated => switch (frame.main_player_id) {
                    .player_1 => switch (role) {
                        .main => &self.players[0],
                        .secondary => &self.players[1],
                    },
                    .player_2 => switch (role) {
                        .main => &self.players[1],
                        .secondary => &self.players[0],
                    },
                },
                .side_separated => switch (role) {
                    .main => if (frame.main_player_id == frame.left_player_id) &self.players[0] else &self.players[1],
                    .secondary => if (frame.main_player_id == frame.left_player_id) &self.players[1] else &self.players[0],
                },
                .role_separated => switch (role) {
                    .main => &self.players[0],
                    .secondary => &self.players[1],
                },
            };
        }
    };
}

const testing = std.testing;

test "PlayerSettings.getById should return correct value" {
    const same = PlayerSettings(u8){ .mode = .same, .players = .{ 1, 2 } };
    try testing.expectEqual(&same.players[0], same.getById(&.{}, .player_1));
    try testing.expectEqual(&same.players[0], same.getById(&.{}, .player_2));

    const id = PlayerSettings(u8){ .mode = .id_separated, .players = .{ 1, 2 } };
    try testing.expectEqual(&id.players[0], id.getById(&.{}, .player_1));
    try testing.expectEqual(&id.players[1], id.getById(&.{}, .player_2));

    const side = PlayerSettings(u8){ .mode = .side_separated, .players = .{ 1, 2 } };
    try testing.expectEqual(&side.players[0], side.getById(&.{ .left_player_id = .player_1 }, .player_1));
    try testing.expectEqual(&side.players[1], side.getById(&.{ .left_player_id = .player_1 }, .player_2));
    try testing.expectEqual(&side.players[1], side.getById(&.{ .left_player_id = .player_2 }, .player_1));
    try testing.expectEqual(&side.players[0], side.getById(&.{ .left_player_id = .player_2 }, .player_2));

    const role = PlayerSettings(u8){ .mode = .role_separated, .players = .{ 1, 2 } };
    try testing.expectEqual(&role.players[0], role.getById(&.{ .main_player_id = .player_1 }, .player_1));
    try testing.expectEqual(&role.players[1], role.getById(&.{ .main_player_id = .player_1 }, .player_2));
    try testing.expectEqual(&role.players[1], role.getById(&.{ .main_player_id = .player_2 }, .player_1));
    try testing.expectEqual(&role.players[0], role.getById(&.{ .main_player_id = .player_2 }, .player_2));
}

test "PlayerSettings.getBySide should return correct value" {
    const same = PlayerSettings(u8){ .mode = .same, .players = .{ 1, 2 } };
    try testing.expectEqual(&same.players[0], same.getBySide(&.{}, .left));
    try testing.expectEqual(&same.players[0], same.getBySide(&.{}, .right));

    const id = PlayerSettings(u8){ .mode = .id_separated, .players = .{ 1, 2 } };
    try testing.expectEqual(&id.players[0], id.getBySide(&.{ .left_player_id = .player_1 }, .left));
    try testing.expectEqual(&id.players[1], id.getBySide(&.{ .left_player_id = .player_1 }, .right));
    try testing.expectEqual(&id.players[1], id.getBySide(&.{ .left_player_id = .player_2 }, .left));
    try testing.expectEqual(&id.players[0], id.getBySide(&.{ .left_player_id = .player_2 }, .right));

    const side = PlayerSettings(u8){ .mode = .side_separated, .players = .{ 1, 2 } };
    try testing.expectEqual(&side.players[0], side.getBySide(&.{}, .left));
    try testing.expectEqual(&side.players[1], side.getBySide(&.{}, .right));

    const role = PlayerSettings(u8){ .mode = .role_separated, .players = .{ 1, 2 } };
    try testing.expectEqual(&role.players[0], role.getBySide(&.{ .left_player_id = .player_1, .main_player_id = .player_1 }, .left));
    try testing.expectEqual(&role.players[1], role.getBySide(&.{ .left_player_id = .player_1, .main_player_id = .player_1 }, .right));
    try testing.expectEqual(&role.players[1], role.getBySide(&.{ .left_player_id = .player_1, .main_player_id = .player_2 }, .left));
    try testing.expectEqual(&role.players[0], role.getBySide(&.{ .left_player_id = .player_1, .main_player_id = .player_2 }, .right));
    try testing.expectEqual(&role.players[1], role.getBySide(&.{ .left_player_id = .player_2, .main_player_id = .player_1 }, .left));
    try testing.expectEqual(&role.players[0], role.getBySide(&.{ .left_player_id = .player_2, .main_player_id = .player_1 }, .right));
    try testing.expectEqual(&role.players[0], role.getBySide(&.{ .left_player_id = .player_2, .main_player_id = .player_2 }, .left));
    try testing.expectEqual(&role.players[1], role.getBySide(&.{ .left_player_id = .player_2, .main_player_id = .player_2 }, .right));
}

test "PlayerSettings.getByRole should return correct value" {
    const same = PlayerSettings(u8){ .mode = .same, .players = .{ 1, 2 } };
    try testing.expectEqual(&same.players[0], same.getByRole(&.{}, .main));
    try testing.expectEqual(&same.players[0], same.getByRole(&.{}, .secondary));

    const id = PlayerSettings(u8){ .mode = .id_separated, .players = .{ 1, 2 } };
    try testing.expectEqual(&id.players[0], id.getByRole(&.{ .main_player_id = .player_1 }, .main));
    try testing.expectEqual(&id.players[1], id.getByRole(&.{ .main_player_id = .player_1 }, .secondary));
    try testing.expectEqual(&id.players[1], id.getByRole(&.{ .main_player_id = .player_2 }, .main));
    try testing.expectEqual(&id.players[0], id.getByRole(&.{ .main_player_id = .player_2 }, .secondary));

    const side = PlayerSettings(u8){ .mode = .side_separated, .players = .{ 1, 2 } };
    try testing.expectEqual(&side.players[0], side.getByRole(&.{ .left_player_id = .player_1, .main_player_id = .player_1 }, .main));
    try testing.expectEqual(&side.players[1], side.getByRole(&.{ .left_player_id = .player_1, .main_player_id = .player_1 }, .secondary));
    try testing.expectEqual(&side.players[1], side.getByRole(&.{ .left_player_id = .player_1, .main_player_id = .player_2 }, .main));
    try testing.expectEqual(&side.players[0], side.getByRole(&.{ .left_player_id = .player_1, .main_player_id = .player_2 }, .secondary));
    try testing.expectEqual(&side.players[1], side.getByRole(&.{ .left_player_id = .player_2, .main_player_id = .player_1 }, .main));
    try testing.expectEqual(&side.players[0], side.getByRole(&.{ .left_player_id = .player_2, .main_player_id = .player_1 }, .secondary));
    try testing.expectEqual(&side.players[0], side.getByRole(&.{ .left_player_id = .player_2, .main_player_id = .player_2 }, .main));
    try testing.expectEqual(&side.players[1], side.getByRole(&.{ .left_player_id = .player_2, .main_player_id = .player_2 }, .secondary));

    const role = PlayerSettings(u8){ .mode = .role_separated, .players = .{ 1, 2 } };
    try testing.expectEqual(&role.players[0], role.getByRole(&.{}, .main));
    try testing.expectEqual(&role.players[1], role.getByRole(&.{}, .secondary));
}
