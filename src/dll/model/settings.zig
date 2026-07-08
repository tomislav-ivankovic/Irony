const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("../ui/root.zig");

pub const Settings = struct {
    general: GeneralSettings = .{},
    automation: AutomationSettings = .{},
    hit_lines: PlayerSettings(HitLinesSettings) = .{ .mode = .same, .players = .{ .{}, .{} } },
    hurt_cylinders: PlayerSettings(HurtCylindersSettings) = .{ .mode = .same, .players = .{ .{}, .{} } },
    collision_spheres: PlayerSettings(CollisionSpheresSettings) = .{ .mode = .same, .players = .{ .{}, .{} } },
    skeletons: PlayerSettings(SkeletonSettings) = .{ .mode = .same, .players = .{ .{}, .{} } },
    forward_directions: PlayerSettings(ForwardDirectionSettings) = .{ .mode = .same, .players = .{ .{}, .{} } },
    stage: StageSettings = .{},
    ingame_camera: IngameCameraSettings = .{},
    measure_tool: MeasureToolSettings = .{},
    match_bar: MatchBarSettings = .{},
    details: DetailsSettings = .{},

    const Self = @This();
    pub const file_name = "settings.json";

    pub fn save(self: *const Self, base_dir: *const sdk.misc.BaseDir) !void {
        var path_buffer: [sdk.os.max_file_path_length]u8 = undefined;
        const file_path = base_dir.getPath(&path_buffer, file_name) catch |err| {
            sdk.misc.error_context.append("Failed to construct file path.", .{});
            return err;
        };
        const file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
            sdk.misc.error_context.new("Failed to create or open file: {s}", .{file_path});
            return err;
        };
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        sdk.io.writeJsonValue(Self, self, &writer.interface, &.{ .new_line = .{} }) catch |err| {
            sdk.misc.error_context.append("Failed to write JSON file content.", .{});
            return err;
        };
        writer.end() catch |err| {
            sdk.misc.error_context.new("Failed to end file writing.", .{});
            return err;
        };
    }

    pub fn load(base_dir: *const sdk.misc.BaseDir) !Self {
        var path_buffer: [sdk.os.max_file_path_length]u8 = undefined;
        const file_path = base_dir.getPath(&path_buffer, file_name) catch |err| {
            sdk.misc.error_context.append("Failed to construct file path.", .{});
            return err;
        };
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
            sdk.misc.error_context.new("Failed to open file: {s}", .{file_path});
            return err;
        };
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var reader = file.reader(&buffer);
        return sdk.io.readJsonValue(Self, &reader.interface, &.{}) catch |err| {
            sdk.misc.error_context.append("Failed to parse JSON file content.", .{});
            return err;
        };
    }
};

pub const GeneralSettings = struct {
    ui: Ui = .{},
    rendering_2d: Rendering2D = .{},
    rendering_3d: Rendering3D = .{},

    pub const Ui = struct {
        font_size: f32 = sdk.ui.default_font_size,
        background_color: sdk.math.Vec4 = .fromArray(.{ 0.06, 0.06, 0.06, 0.94 }),
        show_memory_usage: bool = true,
        show_version_info: bool = true,
    };
    pub const Rendering2D = struct {
        thickness_scale: f32 = 1,
    };
    pub const Rendering3D = struct {
        enabled: bool = true,
        enable_depth: bool = true,
        thickness_scale: f32 = 2,
        occluded_alpha: f32 = 0.1,
        anti_aliasing: f32 = 1.8,
    };
};

pub const AutomationSettings = struct {
    enabled: bool = true,
    live_games: Mode = .only_record,
    replays: Mode = .only_record,
    save_format: model.RecordingFormat = .irony,

    pub const Mode = enum {
        do_not_record,
        only_record,
        record_and_save,
    };
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
                .not_attack = .fromArray(.{ 0.0, 0.0, 0.0, 1.0 }),
                .high = .fromArray(.{ 0.0, 0.0, 0.0, 1.0 }),
                .mid = .fromArray(.{ 0.0, 0.0, 0.0, 1.0 }),
                .low = .fromArray(.{ 0.0, 0.0, 0.0, 1.0 }),
                .special_low = .fromArray(.{ 0.0, 0.0, 0.0, 1.0 }),
                .unblockable_high = .fromArray(.{ 0.75, 0.0, 0.75, 1.0 }),
                .unblockable_mid = .fromArray(.{ 0.75, 0.0, 0.75, 1.0 }),
                .unblockable_low = .fromArray(.{ 0.75, 0.0, 0.75, 1.0 }),
                .throw = .fromArray(.{ 0.0, 0.0, 0.0, 1.0 }),
                .projectile = .fromArray(.{ 0.0, 0.0, 0.0, 1.0 }),
                .antiair_only = .fromArray(.{ 0.0, 0.0, 0.0, 1.0 }),
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
                .not_attack = .fromArray(.{ 0.0, 0.0, 0.0, 1.0 }),
                .high = .fromArray(.{ 0.0, 0.0, 0.0, 1.0 }),
                .mid = .fromArray(.{ 0.0, 0.0, 0.0, 1.0 }),
                .low = .fromArray(.{ 0.0, 0.0, 0.0, 1.0 }),
                .special_low = .fromArray(.{ 0.0, 0.0, 0.0, 1.0 }),
                .unblockable_high = .fromArray(.{ 0.4, 0.3, 0.4, 1.0 }),
                .unblockable_mid = .fromArray(.{ 0.4, 0.3, 0.4, 1.0 }),
                .unblockable_low = .fromArray(.{ 0.4, 0.3, 0.4, 1.0 }),
                .throw = .fromArray(.{ 0.0, 0.0, 0.0, 1.0 }),
                .projectile = .fromArray(.{ 0.0, 0.0, 0.0, 1.0 }),
                .antiair_only = .fromArray(.{ 0.0, 0.0, 0.0, 1.0 }),
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
    };
};

pub const HurtCylindersSettings = struct {
    enabled: bool = true,
    normal: Crushing = .{
        .enabled = true,
        .normal = .{ .color = .fromArray(.{ 0.25, 0.25, 0.25, 1.0 }), .thickness = 1.0 },
        .high_crushing = .{ .color = .fromArray(.{ 0.375, 0.0, 0.0, 1.0 }), .thickness = 1.0 },
        .low_crushing = .{ .color = .fromArray(.{ 0.0, 0.188, 0.375, 1.0 }), .thickness = 1.0 },
        .invincible = .{ .color = .fromArray(.{ 0.375, 0.0, 0.375, 1.0 }), .thickness = 1.0 },
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
        .color = .fromArray(.{ 0.5, 0.375, 0.125, 1.0 }),
        .thickness = 1.0,
        .duration = 1.0,
    },
    lingering: ColorThicknessAndDuration = .{
        .enabled = true,
        .color = .fromArray(.{ 0.0, 0.375, 0.375, 1.0 }),
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
    color: sdk.math.Vec4 = .fromArray(.{ 0.0, 0.0, 0.5, 1.0 }),
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
    cant_interact_alpha: f32 = 0.5,
};

pub const ForwardDirectionSettings = struct {
    enabled: bool = true,
    color: sdk.math.Vec4 = .fromArray(.{ 1.0, 0.0, 1.0, 1.0 }),
    length: f32 = 100.0,
    thickness: f32 = 1.0,
    height: f32 = 5.0,
};

pub const StageSettings = struct {
    enabled: bool = true,
    foreground: ColorAndThickness = .{
        .color = .fromArray(.{ 0.0, 1.0, 0.0, 1.0 }),
        .thickness = 1.0,
    },
    background: ColorAndThickness = .{
        .color = .fromArray(.{ 0.0, 0.3, 0.0, 1.0 }),
        .thickness = 1.0,
    },
    broken: ColorAndThickness = .{
        .color = .fromArray(.{ 0.25, 0.25, 0.25, 1.0 }),
        .thickness = 1.0,
    },
    wall_gimmicks: std.EnumArray(model.WallGimmick, ColorAndThickness) = .init(.{
        .none = .{
            .color = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
            .thickness = 10.0,
        },
        .wall_break = .{
            .color = .fromArray(.{ 0.25, 0.25, 0.25, 1.0 }),
            .thickness = 10.0,
        },
        .balcony_break = .{
            .color = .fromArray(.{ 0.0, 0.3, 0.3, 1.0 }),
            .thickness = 10.0,
        },
        .wall_blast = .{
            .color = .fromArray(.{ 0.3, 0.3, 0.0, 1.0 }),
            .thickness = 10.0,
        },
        .wall_bound = .{
            .color = .fromArray(.{ 0.3, 0.15, 0.0, 1.0 }),
            .thickness = 10.0,
        },
    }),
    floor_gimmicks: std.EnumArray(model.FloorGimmickType, FloorGimmick) = .init(.{
        .floor_break = .{
            .side_color = .fromArray(.{ 0.0, 0.3, 0.3, 1.0 }),
            .side_thickness = 10.0,
            .top_color = .fromArray(.{ 0.0, 1.0, 1.0, 0.02 }),
            .top_hard_color = .fromArray(.{ 0.0, 1.0, 1.0, 0.01 }),
        },
        .floor_blast = .{
            .side_color = .fromArray(.{ 0.3, 0.15, 0.0, 1.0 }),
            .side_thickness = 10.0,
            .top_color = .fromArray(.{ 1.0, 0.5, 0.0, 0.02 }),
            .top_hard_color = .fromArray(.{ 1.0, 0.5, 0.0, 0.01 }),
        },
    }),

    pub const ColorAndThickness = struct {
        color: sdk.math.Vec4,
        thickness: f32,
    };

    pub const FloorGimmick = struct {
        side_color: sdk.math.Vec4,
        side_thickness: f32,
        top_color: sdk.math.Vec4,
        top_hard_color: sdk.math.Vec4,
    };
};

pub const IngameCameraSettings = struct {
    enabled: bool = false,
    color: sdk.math.Vec4 = .fromArray(.{ 0.15, 0.15, 0.15, 1.0 }),
    length: f32 = 800.0,
    thickness: f32 = 1.0,
};

pub const MeasureToolSettings = struct {
    line: ColorAndThickness = .{
        .color = .fromArray(.{ 1.0, 0.5, 0.0, 1.0 }),
        .thickness = 2,
    },
    normal_point: ColorAndThickness = .{
        .color = .fromArray(.{ 1.0, 0.5, 0.0, 1.0 }),
        .thickness = 8,
    },
    hovered_point: ColorAndThickness = .{
        .color = .fromArray(.{ 1, 1, 1, 1 }),
        .thickness = 8,
    },
    text_color: sdk.math.Vec4 = .fromArray(.{ 1.0, 0.5, 0.0, 1.0 }),
    hover_distance: f32 = 8,

    pub const ColorAndThickness = struct {
        color: sdk.math.Vec4,
        thickness: f32,
    };
};

pub const MatchBarSettings = struct {
    enabled: bool = true,
    health_bar: HealthBar = .{},
    heat_bar: HeatBar = .{},
    round_count: RoundCount = .{},

    pub const HealthBar = struct {
        text_color: sdk.math.Vec4 = .fromArray(.{ 1.0, 1.0, 1.0, 1.0 }),
        background_color: sdk.math.Vec4 = .fromArray(.{ 1.0, 1.0, 1.0, 0.06 }),
        health_color: sdk.math.Vec4 = .fromArray(.{ 0.0, 1.0, 0.0, 0.5 }),
        recoverable_health_color: sdk.math.Vec4 = .fromArray(.{ 0.5, 0.5, 0.5, 0.5 }),
        damage_color: sdk.math.Vec4 = .fromArray(.{ 1.0, 0.0, 0.0, 0.5 }),
        damage_animation_duration: f32 = 0.5,
        rage_color: sdk.math.Vec4 = .fromArray(.{ 1.0, 0.0, 0.0, 0.5 }),
        rage_thickness: f32 = 2,
    };
    pub const HeatBar = struct {
        text_color: sdk.math.Vec4 = .fromArray(.{ 1.0, 1.0, 1.0, 1.0 }),
        background_color: sdk.math.Vec4 = .fromArray(.{ 1.0, 1.0, 1.0, 0.06 }),
        fill_color: sdk.math.Vec4 = .fromArray(.{ 0.0, 0.0, 1.0, 0.5 }),
        activated_color: sdk.math.Vec4 = .fromArray(.{ 1.0, 1.0, 1.0, 0.5 }),
        activated_thickness: f32 = 2,
    };
    pub const RoundCount = struct {
        empty_circle_color: sdk.math.Vec4 = .fromArray(.{ 1.0, 1.0, 1.0, 0.06 }),
        filled_circle_color: sdk.math.Vec4 = .fromArray(.{ 1.0, 1.0, 0.0, 0.75 }),
        animation_duration: f32 = 0.2,
    };
};

pub const DetailsSettings = struct {
    column_1: Column = .player_1,
    column_2: Column = .player_2,
    fade_out_duration: f32 = 0.2,
    fade_out_alpha: f32 = 0.25,
    rows_enabled: RowsEnabled = block: {
        var map: sdk.misc.FieldMap(ui.Details, bool, &true) = .{};
        map.source = false;
        map.match_phase = false;
        map.player_name = false;
        map.rounds_won = false;
        map.rounds_needed_to_win = false;
        map.health = false;
        map.recoverable_health = false;
        map.health_recover_limit = false;
        map.max_health = false;
        map.rage = false;
        map.heat = false;
        break :block map;
    },

    pub const Column = enum {
        player_1,
        player_2,
        left_player,
        right_player,
        main_player,
        secondary_player,
    };
    pub const RowsEnabled = sdk.misc.FieldMap(ui.Details, bool, &true);
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

        pub fn getById(
            self: anytype,
            frame: *const model.Frame,
            id: model.PlayerId,
        ) sdk.misc.SelfBasedPointer(@TypeOf(self), Self, Type) {
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

        pub fn getBySide(
            self: anytype,
            frame: *const model.Frame,
            side: model.PlayerSide,
        ) sdk.misc.SelfBasedPointer(@TypeOf(self), Self, Type) {
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

        pub fn getByRole(
            self: anytype,
            frame: *const model.Frame,
            role: model.PlayerRole,
        ) sdk.misc.SelfBasedPointer(@TypeOf(self), Self, Type) {
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
        .ingame_camera = .{
            .thickness = 123.0,
        },
    };
    const base_dir = try sdk.misc.BaseDir.fromStr("./test_assets");
    try expected_settings.save(&base_dir);
    defer std.fs.cwd().deleteFile("./test_assets/" ++ Settings.file_name) catch @panic("Failed to cleanup test file.");
    const actual_settings = try Settings.load(&base_dir);
    try testing.expectEqual(expected_settings, actual_settings);
}

test "Settings.load should overwrite the settings file if it already exists" {
    const default_settings = Settings{};
    const expected_settings = Settings{
        .ingame_camera = .{
            .thickness = 123.0,
        },
    };
    const base_dir = try sdk.misc.BaseDir.fromStr("./test_assets");
    try default_settings.save(&base_dir);
    defer std.fs.cwd().deleteFile("./test_assets/" ++ Settings.file_name) catch @panic("Failed to cleanup test file.");
    try expected_settings.save(&base_dir);
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
