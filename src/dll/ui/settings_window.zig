const std = @import("std");
const imgui = @import("imgui");
const model = @import("../model/root.zig");
const ui = @import("root.zig");

pub const SettingsWindow = struct {
    is_open: bool = false,
    navigation_layout: ui.NavigationLayout = .{},

    const Self = @This();
    pub const name = "Settings";

    pub fn draw(self: *Self, settings: *model.Settings) void {
        if (!self.is_open) {
            return;
        }
        const render_content = imgui.igBegin(name, &self.is_open, imgui.ImGuiWindowFlags_HorizontalScrollbar);
        defer imgui.igEnd();
        if (!render_content) {
            return;
        }
        self.navigation_layout.draw(settings, &.{
            .{
                .name = "Hit Lines",
                .content = struct {
                    fn call(s: *model.Settings) void {
                        drawPlayerSettings(
                            model.HitLinesSettings,
                            &s.hit_lines,
                            drawHitLinesSettings,
                        );
                    }
                }.call,
            },
            .{
                .name = "Hurt Cylinders",
                .content = struct {
                    fn call(s: *model.Settings) void {
                        drawPlayerSettings(
                            model.HurtCylindersSettings,
                            &s.hurt_cylinders,
                            drawHurtCylindersSettings,
                        );
                    }
                }.call,
            },
            .{
                .name = "Collision Spheres",
                .content = struct {
                    fn call(s: *model.Settings) void {
                        drawPlayerSettings(
                            model.CollisionSpheresSettings,
                            &s.collision_spheres,
                            drawCollisionSpheresSettings,
                        );
                    }
                }.call,
            },
            .{
                .name = "Skeletons",
                .content = struct {
                    fn call(s: *model.Settings) void {
                        drawPlayerSettings(
                            model.SkeletonSettings,
                            &s.skeletons,
                            drawSkeletonSettings,
                        );
                    }
                }.call,
            },
            .{
                .name = "Forward Directions",
                .content = struct {
                    fn call(s: *model.Settings) void {
                        drawPlayerSettings(
                            model.ForwardDirectionSettings,
                            &s.forward_directions,
                            drawForwardDirectionsSettings,
                        );
                    }
                }.call,
            },
            .{
                .name = "Floor",
                .content = struct {
                    fn call(s: *model.Settings) void {
                        drawFloorSettings(&s.floor);
                    }
                }.call,
            },
            .{
                .name = "Ingame Camera",
                .content = struct {
                    fn call(s: *model.Settings) void {
                        drawIngameCameraSettings(&s.ingame_camera);
                    }
                }.call,
            },
        });
    }
};

fn drawPlayerSettings(
    comptime Type: type,
    settings: *model.PlayerSettings(Type),
    drawContent: *const fn (settings: *Type) void,
) void {
    const same_name = "Same Settings";
    const id_separated_name = "Player 1 / Player 2";
    const side_separated_name = "Left Player / Right Player";
    const role_separated_name = "Main Player / Secondary Player";
    const preview_value = switch (settings.*) {
        .same => same_name,
        .id_separated => id_separated_name,
        .side_separated => side_separated_name,
        .role_separated => role_separated_name,
    };
    if (imgui.igBeginCombo("Settings Separation", preview_value, 0)) {
        defer imgui.igEndCombo();
        if (imgui.igSelectable_Bool(same_name, settings.* == .same, 0, .{})) {
            settings.* = switch (settings.*) {
                .same => |s| .{ .same = s },
                .id_separated => |s| .{ .same = s.player_1 },
                .side_separated => |s| .{ .same = s.left },
                .role_separated => |s| .{ .same = s.main },
            };
        }
        if (imgui.igSelectable_Bool(id_separated_name, settings.* == .id_separated, 0, .{})) {
            settings.* = switch (settings.*) {
                .same => |s| .{ .id_separated = .{ .player_1 = s, .player_2 = s } },
                .id_separated => |s| .{ .id_separated = .{ .player_1 = s.player_1, .player_2 = s.player_2 } },
                .side_separated => |s| .{ .id_separated = .{ .player_1 = s.left, .player_2 = s.right } },
                .role_separated => |s| .{ .id_separated = .{ .player_1 = s.main, .player_2 = s.secondary } },
            };
        }
        if (imgui.igSelectable_Bool(side_separated_name, settings.* == .side_separated, 0, .{})) {
            settings.* = switch (settings.*) {
                .same => |s| .{ .side_separated = .{ .left = s, .right = s } },
                .id_separated => |s| .{ .side_separated = .{ .left = s.player_1, .right = s.player_2 } },
                .side_separated => |s| .{ .side_separated = .{ .left = s.left, .right = s.right } },
                .role_separated => |s| .{ .side_separated = .{ .left = s.main, .right = s.secondary } },
            };
        }
        if (imgui.igSelectable_Bool(role_separated_name, settings.* == .role_separated, 0, .{})) {
            settings.* = switch (settings.*) {
                .same => |s| .{ .role_separated = .{ .main = s, .secondary = s } },
                .id_separated => |s| .{ .role_separated = .{ .main = s.player_1, .secondary = s.player_2 } },
                .side_separated => |s| .{ .role_separated = .{ .main = s.left, .secondary = s.right } },
                .role_separated => |s| .{ .role_separated = .{ .main = s.main, .secondary = s.secondary } },
            };
        }
    }

    switch (settings.*) {
        .same => |*s| drawContent(s),
        .id_separated => |*s| {
            if (imgui.igBeginTable("players", 2, imgui.ImGuiTableFlags_BordersInner, .{}, 0)) {
                defer imgui.igEndTable();
                if (imgui.igTableNextColumn()) {
                    imgui.igSeparatorText("Player 1");
                    drawContent(&s.player_1);
                }
                if (imgui.igTableNextColumn()) {
                    imgui.igSeparatorText("Player 2");
                    drawContent(&s.player_2);
                }
            }
        },
        .side_separated => |*s| {
            if (imgui.igBeginTable("players", 2, imgui.ImGuiTableFlags_BordersInner, .{}, 0)) {
                defer imgui.igEndTable();
                if (imgui.igTableNextColumn()) {
                    imgui.igSeparatorText("Left Player");
                    drawContent(&s.left);
                }
                if (imgui.igTableNextColumn()) {
                    imgui.igSeparatorText("Right Player");
                    drawContent(&s.right);
                }
            }
        },
        .role_separated => |*s| {
            if (imgui.igBeginTable("players", 2, imgui.ImGuiTableFlags_BordersInner, .{}, 0)) {
                defer imgui.igEndTable();
                if (imgui.igTableNextColumn()) {
                    imgui.igSeparatorText("Main Player");
                    drawContent(&s.main);
                }
                if (imgui.igTableNextColumn()) {
                    imgui.igSeparatorText("Secondary Player");
                    drawContent(&s.secondary);
                }
            }
        },
    }
}

fn drawHitLinesSettings(settings: *model.HitLinesSettings) void {
    _ = settings;
}

fn drawHurtCylindersSettings(settings: *model.HurtCylindersSettings) void {
    _ = settings;
}

fn drawCollisionSpheresSettings(settings: *model.CollisionSpheresSettings) void {
    _ = settings;
}

fn drawSkeletonSettings(settings: *model.SkeletonSettings) void {
    _ = settings;
}

fn drawForwardDirectionsSettings(settings: *model.ForwardDirectionSettings) void {
    _ = settings;
}

fn drawFloorSettings(settings: *model.FloorSettings) void {
    _ = settings;
}

fn drawIngameCameraSettings(settings: *model.IngameCameraSettings) void {
    _ = settings;
}
