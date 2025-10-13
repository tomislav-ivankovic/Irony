const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

pub const Settings = struct {
    hit_lines: PlayerSettings(HitLinesSettings) = .{ .same = .{} },
    hurt_cylinders: PlayerSettings(HurtCylindersSettings) = .{ .same = .{} },
    collision_spheres: PlayerSettings(CollisionSpheresSettings) = .{ .same = .{} },
    skeletons: PlayerSettings(SkeletonSettings) = .{ .same = .{} },
    forward_directions: PlayerSettings(ForwardDirectionSettings) = .{ .same = .{} },
    floor: FloorSettings = .{},
    ingame_camera: IngameCameraSettings = .{},

    const Self = @This();
    const file_name = "settings.json";

    pub fn load(base_dir: *const sdk.misc.BaseDir) !Self {
        var buffer: [sdk.os.max_file_path_length]u8 = undefined;
        const size = base_dir.getPath(&buffer, file_name) catch |err| {
            sdk.misc.error_context.append("Failed to construct file path.", .{});
            return err;
        };
        const file_path = buffer[0..size];
        return sdk.misc.loadSettings(Self, file_path);
    }

    pub fn save(self: *const Self, base_dir: *const sdk.misc.BaseDir) !void {
        var buffer: [sdk.os.max_file_path_length]u8 = undefined;
        const size = base_dir.getPath(&buffer, file_name) catch |err| {
            sdk.misc.error_context.append("Failed to construct file path.", .{});
            return err;
        };
        const file_path = buffer[0..size];
        return sdk.misc.saveSettings(self, file_path);
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
        enabled: ?bool = null,
        colors: ?std.enums.EnumFieldStruct(model.Blocking, sdk.math.Vec4, null) = null,
        thickness: ?f32 = null,
        cant_move_alpha: ?f32 = null,
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
        const default = Self{};
        const json_value = try std.json.innerParse(JsonValue, allocator, source, options);
        return .{
            .enabled = json_value.enabled orelse default.enabled,
            .colors = if (json_value.colors) |c| std.EnumArray(model.Blocking, sdk.math.Vec4).init(c) else default.colors,
            .thickness = json_value.thickness orelse default.thickness,
            .cant_move_alpha = json_value.cant_move_alpha orelse default.cant_move_alpha,
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

pub fn PlayerSettings(comptime Type: type) type {
    return union(enum) {
        same: Type,
        id_separated: IdSeperated,
        side_separated: SideSeperated,
        role_separated: RoleSeparated,

        const Self = @This();
        pub const IdSeperated = struct {
            player_1: Type,
            player_2: Type,
        };
        pub const SideSeperated = struct {
            left: Type,
            right: Type,
        };
        pub const RoleSeparated = struct {
            main: Type,
            secondary: Type,
        };

        pub fn getById(self: *const Self, frame: *const model.Frame, id: model.PlayerId) *const Type {
            return switch (self.*) {
                .same => |*s| s,
                .id_separated => |*s| switch (id) {
                    .player_1 => &s.player_1,
                    .player_2 => &s.player_2,
                },
                .side_separated => |*s| if (frame.left_player_id == id) &s.left else &s.right,
                .role_separated => |*s| if (frame.main_player_id == id) &s.main else &s.secondary,
            };
        }

        pub fn getBySide(self: *const Self, frame: *const model.Frame, side: model.PlayerSide) *const Type {
            return switch (self.*) {
                .same => |*s| s,
                .id_separated => |*s| switch (frame.left_player_id) {
                    .player_1 => switch (side) {
                        .left => &s.player_1,
                        .right => &s.player_2,
                    },
                    .player_2 => switch (side) {
                        .left => &s.player_2,
                        .right => &s.player_1,
                    },
                },
                .side_separated => |*s| switch (side) {
                    .left => &s.left,
                    .right => &s.right,
                },
                .role_separated => |*s| switch (side) {
                    .left => if (frame.left_player_id == frame.main_player_id) &s.main else &s.secondary,
                    .right => if (frame.left_player_id == frame.main_player_id) &s.secondary else &s.main,
                },
            };
        }

        pub fn getByRole(self: *const Self, frame: *const model.Frame, role: model.PlayerRole) *const Type {
            return switch (self.*) {
                .same => |*s| s,
                .id_separated => |*s| switch (frame.main_player_id) {
                    .player_1 => switch (role) {
                        .main => &s.player_1,
                        .secondary => &s.player_2,
                    },
                    .player_2 => switch (role) {
                        .main => &s.player_2,
                        .secondary => &s.player_1,
                    },
                },
                .side_separated => |*s| switch (role) {
                    .main => if (frame.main_player_id == frame.left_player_id) &s.left else &s.right,
                    .secondary => if (frame.main_player_id == frame.left_player_id) &s.right else &s.left,
                },
                .role_separated => |*s| switch (role) {
                    .main => &s.main,
                    .secondary => &s.secondary,
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
    const base_dir = try sdk.misc.BaseDir.fromStr("./test_assets");
    try expected_settings.save(&base_dir);
    defer std.fs.cwd().deleteFile("./test_assets/settings.json") catch @panic("Failed to cleanup test file.");
    const actual_settings = try Settings.load(&base_dir);
    try testing.expectEqual(expected_settings, actual_settings);
}

test "PlayerSettings.getById should return correct value" {
    const same = PlayerSettings(u8){ .same = 'S' };
    try testing.expectEqual('S', same.getById(&.{}, .player_1).*);
    try testing.expectEqual('S', same.getById(&.{}, .player_2).*);

    const id = PlayerSettings(u8){ .id_separated = .{ .player_1 = 1, .player_2 = 2 } };
    try testing.expectEqual(1, id.getById(&.{}, .player_1).*);
    try testing.expectEqual(2, id.getById(&.{}, .player_2).*);

    const side = PlayerSettings(u8){ .side_separated = .{ .left = 'L', .right = 'R' } };
    try testing.expectEqual('L', side.getById(&.{ .left_player_id = .player_1 }, .player_1).*);
    try testing.expectEqual('R', side.getById(&.{ .left_player_id = .player_1 }, .player_2).*);
    try testing.expectEqual('R', side.getById(&.{ .left_player_id = .player_2 }, .player_1).*);
    try testing.expectEqual('L', side.getById(&.{ .left_player_id = .player_2 }, .player_2).*);

    const role = PlayerSettings(u8){ .role_separated = .{ .main = 'M', .secondary = 'S' } };
    try testing.expectEqual('M', role.getById(&.{ .main_player_id = .player_1 }, .player_1).*);
    try testing.expectEqual('S', role.getById(&.{ .main_player_id = .player_1 }, .player_2).*);
    try testing.expectEqual('S', role.getById(&.{ .main_player_id = .player_2 }, .player_1).*);
    try testing.expectEqual('M', role.getById(&.{ .main_player_id = .player_2 }, .player_2).*);
}

test "PlayerSettings.getBySide should return correct value" {
    const same = PlayerSettings(u8){ .same = 'S' };
    try testing.expectEqual('S', same.getBySide(&.{}, .left).*);
    try testing.expectEqual('S', same.getBySide(&.{}, .right).*);

    const id = PlayerSettings(u8){ .id_separated = .{ .player_1 = 1, .player_2 = 2 } };
    try testing.expectEqual(1, id.getBySide(&.{ .left_player_id = .player_1 }, .left).*);
    try testing.expectEqual(2, id.getBySide(&.{ .left_player_id = .player_1 }, .right).*);
    try testing.expectEqual(2, id.getBySide(&.{ .left_player_id = .player_2 }, .left).*);
    try testing.expectEqual(1, id.getBySide(&.{ .left_player_id = .player_2 }, .right).*);

    const side = PlayerSettings(u8){ .side_separated = .{ .left = 'L', .right = 'R' } };
    try testing.expectEqual('L', side.getBySide(&.{}, .left).*);
    try testing.expectEqual('R', side.getBySide(&.{}, .right).*);

    const role = PlayerSettings(u8){ .role_separated = .{ .main = 'M', .secondary = 'S' } };
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
    const same = PlayerSettings(u8){ .same = 'S' };
    try testing.expectEqual('S', same.getByRole(&.{}, .main).*);
    try testing.expectEqual('S', same.getByRole(&.{}, .secondary).*);

    const id = PlayerSettings(u8){ .id_separated = .{ .player_1 = 1, .player_2 = 2 } };
    try testing.expectEqual(1, id.getByRole(&.{ .main_player_id = .player_1 }, .main).*);
    try testing.expectEqual(2, id.getByRole(&.{ .main_player_id = .player_1 }, .secondary).*);
    try testing.expectEqual(2, id.getByRole(&.{ .main_player_id = .player_2 }, .main).*);
    try testing.expectEqual(1, id.getByRole(&.{ .main_player_id = .player_2 }, .secondary).*);

    const side = PlayerSettings(u8){ .side_separated = .{ .left = 'L', .right = 'R' } };
    try testing.expectEqual('L', side.getByRole(&.{ .left_player_id = .player_1, .main_player_id = .player_1 }, .main).*);
    try testing.expectEqual('R', side.getByRole(&.{ .left_player_id = .player_1, .main_player_id = .player_1 }, .secondary).*);
    try testing.expectEqual('R', side.getByRole(&.{ .left_player_id = .player_1, .main_player_id = .player_2 }, .main).*);
    try testing.expectEqual('L', side.getByRole(&.{ .left_player_id = .player_1, .main_player_id = .player_2 }, .secondary).*);
    try testing.expectEqual('R', side.getByRole(&.{ .left_player_id = .player_2, .main_player_id = .player_1 }, .main).*);
    try testing.expectEqual('L', side.getByRole(&.{ .left_player_id = .player_2, .main_player_id = .player_1 }, .secondary).*);
    try testing.expectEqual('L', side.getByRole(&.{ .left_player_id = .player_2, .main_player_id = .player_2 }, .main).*);
    try testing.expectEqual('R', side.getByRole(&.{ .left_player_id = .player_2, .main_player_id = .player_2 }, .secondary).*);

    const role = PlayerSettings(u8){ .role_separated = .{ .main = 'M', .secondary = 'S' } };
    try testing.expectEqual('M', role.getByRole(&.{}, .main).*);
    try testing.expectEqual('S', role.getByRole(&.{}, .secondary).*);
}
