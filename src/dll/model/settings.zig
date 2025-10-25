const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

pub const Settings = struct {
    hit_lines: PlayerSettings(HitLinesSettings) = .{ .mode = .same, .players = .{ .{}, .{} } },
    hurt_cylinders: PlayerSettings(HurtCylindersSettings) = .{ .mode = .same, .players = .{ .{}, .{} } },
    collision_spheres: PlayerSettings(CollisionSpheresSettings) = .{ .mode = .same, .players = .{ .{}, .{} } },
    skeletons: PlayerSettings(SkeletonSettings) = .{ .mode = .same, .players = .{ .{}, .{} } },
    forward_directions: PlayerSettings(ForwardDirectionSettings) = .{ .mode = .same, .players = .{ .{}, .{} } },
    floor: FloorSettings = .{},
    ingame_camera: IngameCameraSettings = .{},
    misc: MiscSettings = .{},

    const Self = @This();
    const file_name = "settings.json";

    pub fn load(base_dir: *const sdk.fs.BaseDir) !Self {
        var buffer: [sdk.os.max_file_path_length]u8 = undefined;
        const file_path = base_dir.getPath(&buffer, file_name) catch |err| {
            sdk.misc.error_context.append("Failed to construct file path.", .{});
            return err;
        };
        return sdk.fs.loadSettings(Self, file_path);
    }

    pub fn save(self: *const Self, base_dir: *const sdk.fs.BaseDir) !void {
        var buffer: [sdk.os.max_file_path_length]u8 = undefined;
        const file_path = base_dir.getPath(&buffer, file_name) catch |err| {
            sdk.misc.error_context.append("Failed to construct file path.", .{});
            return err;
        };
        return sdk.fs.saveSettings(self, file_path);
    }
};

pub const HitLinesSettings = struct {
    enabled: bool = true,
    normal: FillAndOutline = .{
        .enabled = true,
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
        .enabled = true,
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
        enabled: bool,
        fill: ColorsAndThickness,
        outline: ColorsAndThickness,
    };
    pub const ColorsAndThickness = struct {
        colors: std.EnumArray(model.AttackType, sdk.math.Vec4),
        thickness: f32,

        const Self = @This();
        const JsonValue = struct {
            colors: std.enums.EnumFieldStruct(model.AttackType, sdk.math.Vec4, null),
            thickness: f32,
        };

        pub fn jsonStringify(self: *const Self, jsonWriter: anytype) !void {
            const json_value = JsonValue{
                .colors = sdk.misc.enumArrayToEnumFieldStruct(model.AttackType, sdk.math.Vec4, &self.colors),
                .thickness = self.thickness,
            };
            try jsonWriter.write(json_value);
        }

        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Self {
            const json_value = try std.json.innerParse(JsonValue, allocator, source, options);
            return .{
                .colors = .init(json_value.colors),
                .thickness = json_value.thickness,
            };
        }

        pub fn settingsParse(allocator: std.mem.Allocator, reader: *std.json.Reader, default_value: *const Self) !Self {
            const json_default = JsonValue{
                .colors = sdk.misc.enumArrayToEnumFieldStruct(model.AttackType, sdk.math.Vec4, &default_value.colors),
                .thickness = default_value.thickness,
            };
            const json_value = try sdk.fs.settingsInnerParse(JsonValue, allocator, reader, &json_default);
            return .{
                .colors = .init(json_value.colors),
                .thickness = json_value.thickness,
            };
        }
    };
};

pub const HurtCylindersSettings = struct {
    enabled: bool = true,
    normal: Crushing = .{
        .enabled = true,
        .normal = .{ .color = .fromArray(.{ 0.5, 0.5, 0.5, 0.5 }), .thickness = 1.0 },
        .high_crushing = .{ .color = .fromArray(.{ 0.75, 0.0, 0.0, 0.5 }), .thickness = 1.0 },
        .low_crushing = .{ .color = .fromArray(.{ 0.0, 0.375, 0.75, 0.5 }), .thickness = 1.0 },
        .invincible = .{ .color = .fromArray(.{ 0.75, 0.0, 0.75, 0.5 }), .thickness = 1.0 },
    },
    power_crushing: Crushing = .{
        .enabled = true,
        .normal = .{ .color = .fromArray(.{ 1.0, 1.0, 1.0, 1.0 }), .thickness = 1.0 },
        .high_crushing = .{ .color = .fromArray(.{ 1.0, 0.25, 0.25, 1.0 }), .thickness = 1.0 },
        .low_crushing = .{ .color = .fromArray(.{ 0.0, 0.25, 1.0, 1.0 }), .thickness = 1.0 },
        .invincible = .{ .color = .fromArray(.{ 1.0, 0.0, 1.0, 1.0 }), .thickness = 1.0 },
    },
    connected: ColorThicknessAndDuration = .{
        .enabled = true,
        .color = .fromArray(.{ 1.0, 0.75, 0.25, 0.5 }),
        .thickness = 1.0,
        .duration = 1.0,
    },
    lingering: ColorThicknessAndDuration = .{
        .enabled = true,
        .color = .fromArray(.{ 0.0, 0.75, 0.75, 0.5 }),
        .thickness = 1.0,
        .duration = 1.0,
    },

    pub const Crushing = struct {
        enabled: bool,
        normal: ColorAndThickness,
        high_crushing: ColorAndThickness,
        low_crushing: ColorAndThickness,
        invincible: ColorAndThickness,
    };
    pub const ColorAndThickness = struct {
        color: sdk.math.Vec4,
        thickness: f32,
    };
    pub const ColorThicknessAndDuration = struct {
        enabled: bool,
        color: sdk.math.Vec4,
        thickness: f32,
        duration: f32,
    };
};

pub const CollisionSpheresSettings = struct {
    enabled: bool = false,
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

    const Self = @This();
    const JsonValue = struct {
        enabled: bool,
        colors: std.enums.EnumFieldStruct(model.Blocking, sdk.math.Vec4, null),
        thickness: f32,
        cant_move_alpha: f32,
    };

    pub fn jsonStringify(self: *const Self, jsonWriter: anytype) !void {
        const json_value = JsonValue{
            .enabled = self.enabled,
            .colors = sdk.misc.enumArrayToEnumFieldStruct(model.Blocking, sdk.math.Vec4, &self.colors),
            .thickness = self.thickness,
            .cant_move_alpha = self.cant_move_alpha,
        };
        try jsonWriter.write(json_value);
    }

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Self {
        const json_value = try std.json.innerParse(JsonValue, allocator, source, options);
        return .{
            .enabled = json_value.enabled,
            .colors = .init(json_value.colors),
            .thickness = json_value.thickness,
            .cant_move_alpha = json_value.cant_move_alpha,
        };
    }

    pub fn settingsParse(allocator: std.mem.Allocator, reader: *std.json.Reader, default_value: *const Self) !Self {
        const json_default = JsonValue{
            .enabled = default_value.enabled,
            .colors = sdk.misc.enumArrayToEnumFieldStruct(model.Blocking, sdk.math.Vec4, &default_value.colors),
            .thickness = default_value.thickness,
            .cant_move_alpha = default_value.cant_move_alpha,
        };
        const json_value = try sdk.fs.settingsInnerParse(JsonValue, allocator, reader, &json_default);
        return .{
            .enabled = json_value.enabled,
            .colors = .init(json_value.colors),
            .thickness = json_value.thickness,
            .cant_move_alpha = json_value.cant_move_alpha,
        };
    }
};

pub const ForwardDirectionSettings = struct {
    enabled: bool = true,
    color: sdk.math.Vec4 = .fromArray(.{ 1.0, 0.0, 1.0, 1.0 }),
    length: f32 = 100.0,
    thickness: f32 = 1.0,
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

pub const MiscSettings = struct {
    details_columns: DetailsColumns = .id_based,

    pub const DetailsColumns = enum {
        id_based,
        side_based,
        role_based,
    };
};

pub const PlayerSettingsMode = enum {
    same,
    id_separated,
    side_separated,
    role_separated,
};

pub fn PlayerSettings(comptime Type: type) type {
    return struct {
        mode: PlayerSettingsMode,
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

test "Settings.load should load the same settings that Settings.save saves" {
    const expected_settings = Settings{
        .floor = .{
            .thickness = 123.0,
        },
    };
    const base_dir = try sdk.fs.BaseDir.fromStr("./test_assets");
    try expected_settings.save(&base_dir);
    defer std.fs.cwd().deleteFile("./test_assets/settings.json") catch @panic("Failed to cleanup test file.");
    const actual_settings = try Settings.load(&base_dir);
    try testing.expectEqual(expected_settings, actual_settings);
}

test "PlayerSettings.getById should return correct value" {
    const same = PlayerSettings(u8){ .mode = .same, .players = .{ 1, 2 } };
    try testing.expectEqual(1, same.getById(&.{}, .player_1).*);
    try testing.expectEqual(1, same.getById(&.{}, .player_2).*);

    const id = PlayerSettings(u8){ .mode = .id_separated, .players = .{ 1, 2 } };
    try testing.expectEqual(1, id.getById(&.{}, .player_1).*);
    try testing.expectEqual(2, id.getById(&.{}, .player_2).*);

    const side = PlayerSettings(u8){ .mode = .side_separated, .players = .{ 'L', 'R' } };
    try testing.expectEqual('L', side.getById(&.{ .left_player_id = .player_1 }, .player_1).*);
    try testing.expectEqual('R', side.getById(&.{ .left_player_id = .player_1 }, .player_2).*);
    try testing.expectEqual('R', side.getById(&.{ .left_player_id = .player_2 }, .player_1).*);
    try testing.expectEqual('L', side.getById(&.{ .left_player_id = .player_2 }, .player_2).*);

    const role = PlayerSettings(u8){ .mode = .role_separated, .players = .{ 'M', 'S' } };
    try testing.expectEqual('M', role.getById(&.{ .main_player_id = .player_1 }, .player_1).*);
    try testing.expectEqual('S', role.getById(&.{ .main_player_id = .player_1 }, .player_2).*);
    try testing.expectEqual('S', role.getById(&.{ .main_player_id = .player_2 }, .player_1).*);
    try testing.expectEqual('M', role.getById(&.{ .main_player_id = .player_2 }, .player_2).*);
}

test "PlayerSettings.getBySide should return correct value" {
    const same = PlayerSettings(u8){ .mode = .same, .players = .{ 1, 2 } };
    try testing.expectEqual(1, same.getBySide(&.{}, .left).*);
    try testing.expectEqual(1, same.getBySide(&.{}, .right).*);

    const id = PlayerSettings(u8){ .mode = .id_separated, .players = .{ 1, 2 } };
    try testing.expectEqual(1, id.getBySide(&.{ .left_player_id = .player_1 }, .left).*);
    try testing.expectEqual(2, id.getBySide(&.{ .left_player_id = .player_1 }, .right).*);
    try testing.expectEqual(2, id.getBySide(&.{ .left_player_id = .player_2 }, .left).*);
    try testing.expectEqual(1, id.getBySide(&.{ .left_player_id = .player_2 }, .right).*);

    const side = PlayerSettings(u8){ .mode = .side_separated, .players = .{ 'L', 'R' } };
    try testing.expectEqual('L', side.getBySide(&.{}, .left).*);
    try testing.expectEqual('R', side.getBySide(&.{}, .right).*);

    const role = PlayerSettings(u8){ .mode = .role_separated, .players = .{ 'M', 'S' } };
    try testing.expectEqual('M', role.getBySide(&.{ .left_player_id = .player_1, .main_player_id = .player_1 }, .left).*);
    try testing.expectEqual('S', role.getBySide(&.{ .left_player_id = .player_1, .main_player_id = .player_1 }, .right).*);
    try testing.expectEqual('S', role.getBySide(&.{ .left_player_id = .player_1, .main_player_id = .player_2 }, .left).*);
    try testing.expectEqual('M', role.getBySide(&.{ .left_player_id = .player_1, .main_player_id = .player_2 }, .right).*);
    try testing.expectEqual('S', role.getBySide(&.{ .left_player_id = .player_2, .main_player_id = .player_1 }, .left).*);
    try testing.expectEqual('M', role.getBySide(&.{ .left_player_id = .player_2, .main_player_id = .player_1 }, .right).*);
    try testing.expectEqual('M', role.getBySide(&.{ .left_player_id = .player_2, .main_player_id = .player_2 }, .left).*);
    try testing.expectEqual('S', role.getBySide(&.{ .left_player_id = .player_2, .main_player_id = .player_2 }, .right).*);
}

test "PlayerSettings.getByRole should return correct value" {
    const same = PlayerSettings(u8){ .mode = .same, .players = .{ 1, 2 } };
    try testing.expectEqual(1, same.getByRole(&.{}, .main).*);
    try testing.expectEqual(1, same.getByRole(&.{}, .secondary).*);

    const id = PlayerSettings(u8){ .mode = .id_separated, .players = .{ 1, 2 } };
    try testing.expectEqual(1, id.getByRole(&.{ .main_player_id = .player_1 }, .main).*);
    try testing.expectEqual(2, id.getByRole(&.{ .main_player_id = .player_1 }, .secondary).*);
    try testing.expectEqual(2, id.getByRole(&.{ .main_player_id = .player_2 }, .main).*);
    try testing.expectEqual(1, id.getByRole(&.{ .main_player_id = .player_2 }, .secondary).*);

    const side = PlayerSettings(u8){ .mode = .side_separated, .players = .{ 'L', 'R' } };
    try testing.expectEqual('L', side.getByRole(&.{ .left_player_id = .player_1, .main_player_id = .player_1 }, .main).*);
    try testing.expectEqual('R', side.getByRole(&.{ .left_player_id = .player_1, .main_player_id = .player_1 }, .secondary).*);
    try testing.expectEqual('R', side.getByRole(&.{ .left_player_id = .player_1, .main_player_id = .player_2 }, .main).*);
    try testing.expectEqual('L', side.getByRole(&.{ .left_player_id = .player_1, .main_player_id = .player_2 }, .secondary).*);
    try testing.expectEqual('R', side.getByRole(&.{ .left_player_id = .player_2, .main_player_id = .player_1 }, .main).*);
    try testing.expectEqual('L', side.getByRole(&.{ .left_player_id = .player_2, .main_player_id = .player_1 }, .secondary).*);
    try testing.expectEqual('L', side.getByRole(&.{ .left_player_id = .player_2, .main_player_id = .player_2 }, .main).*);
    try testing.expectEqual('R', side.getByRole(&.{ .left_player_id = .player_2, .main_player_id = .player_2 }, .secondary).*);

    const role = PlayerSettings(u8){ .mode = .role_separated, .players = .{ 'M', 'S' } };
    try testing.expectEqual('M', role.getByRole(&.{}, .main).*);
    try testing.expectEqual('S', role.getByRole(&.{}, .secondary).*);
}
