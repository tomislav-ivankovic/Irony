const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("root.zig");

pub const SettingsWindow = struct {
    is_open: bool = false,
    navigation_layout: ui.NavigationLayout = .{},
    misc_settings: MiscSettings = .{},
    save_button: SaveButton = .{},

    const Self = @This();
    pub const name = "Settings";

    pub fn draw(self: *Self, base_dir: *const sdk.misc.BaseDir, settings: *model.Settings) void {
        if (!self.is_open) {
            return;
        }
        imgui.igSetNextWindowSizeConstraints(
            .{ .x = 128, .y = 128 },
            .{ .x = std.math.inf(f32), .y = std.math.inf(f32) },
            null,
            null,
        );
        const render_content = imgui.igBegin(name, &self.is_open, imgui.ImGuiWindowFlags_HorizontalScrollbar);
        defer imgui.igEnd();
        if (!render_content) {
            return;
        }

        var content_size: imgui.ImVec2 = undefined;
        imgui.igGetContentRegionAvail(&content_size);

        const navigation_layout_height = content_size.y - self.save_button.height - imgui.igGetStyle().*.ItemSpacing.y;
        if (imgui.igBeginChild_Str("navigation_layout", .{ .y = navigation_layout_height }, 0, 0)) {
            self.drawNavigationLayout(base_dir, settings);
        }
        imgui.igEndChild();

        self.save_button.draw(base_dir, settings);
    }

    pub fn drawNavigationLayout(self: *Self, base_dir: *const sdk.misc.BaseDir, settings: *model.Settings) void {
        const Context = struct {
            self: *Self,
            base_dir: *const sdk.misc.BaseDir,
            settings: *model.Settings,
        };
        const context = Context{
            .self = self,
            .base_dir = base_dir,
            .settings = settings,
        };
        self.navigation_layout.draw(&context, &.{
            .{
                .name = "Hit Lines",
                .content = struct {
                    fn call(c: *const Context) void {
                        drawPlayerSettings(
                            model.HitLinesSettings,
                            &c.settings.hit_lines,
                            drawHitLinesSettings,
                        );
                    }
                }.call,
            },
            .{
                .name = "Hurt Cylinders",
                .content = struct {
                    fn call(c: *const Context) void {
                        drawPlayerSettings(
                            model.HurtCylindersSettings,
                            &c.settings.hurt_cylinders,
                            drawHurtCylindersSettings,
                        );
                    }
                }.call,
            },
            .{
                .name = "Collision Spheres",
                .content = struct {
                    fn call(c: *const Context) void {
                        drawPlayerSettings(
                            model.CollisionSpheresSettings,
                            &c.settings.collision_spheres,
                            drawCollisionSpheresSettings,
                        );
                    }
                }.call,
            },
            .{
                .name = "Skeletons",
                .content = struct {
                    fn call(c: *const Context) void {
                        drawPlayerSettings(
                            model.SkeletonSettings,
                            &c.settings.skeletons,
                            drawSkeletonSettings,
                        );
                    }
                }.call,
            },
            .{
                .name = "Forward Directions",
                .content = struct {
                    fn call(c: *const Context) void {
                        drawPlayerSettings(
                            model.ForwardDirectionSettings,
                            &c.settings.forward_directions,
                            drawForwardDirectionsSettings,
                        );
                    }
                }.call,
            },
            .{
                .name = "Floor",
                .content = struct {
                    fn call(c: *const Context) void {
                        drawFloorSettings(&c.settings.floor);
                    }
                }.call,
            },
            .{
                .name = "Ingame Camera",
                .content = struct {
                    fn call(c: *const Context) void {
                        drawIngameCameraSettings(&c.settings.ingame_camera);
                    }
                }.call,
            },
            .{
                .name = "Miscellaneous",
                .content = struct {
                    fn call(c: *const Context) void {
                        c.self.misc_settings.draw(c.base_dir, c.settings);
                    }
                }.call,
            },
        });
    }
};

const MiscSettings = struct {
    reload_button: ReloadButton = .{},
    defaults_button: DefaultsButton = .{},

    const Self = @This();

    pub fn draw(self: *Self, base_dir: *const sdk.misc.BaseDir, settings: *model.Settings) void {
        self.reload_button.draw(base_dir, settings);
        self.defaults_button.draw(settings);
    }
};

const SaveButton = struct {
    height: f32 = 0,
    is_enabled: std.atomic.Value(bool) = .init(true),

    const Self = @This();

    fn draw(self: *Self, base_dir: *const sdk.misc.BaseDir, settings: *model.Settings) void {
        var content_size: imgui.ImVec2 = undefined;
        imgui.igGetContentRegionAvail(&content_size);

        imgui.igBeginDisabled(!self.is_enabled.load(.seq_cst));
        defer imgui.igEndDisabled();
        if (imgui.igButton("Save", .{ .x = content_size.x })) {
            self.saveSettings(base_dir, settings);
        }
        var size: imgui.ImVec2 = undefined;
        imgui.igGetItemRectSize(&size);
        self.height = size.y;
    }

    fn saveSettings(self: *Self, base_dir: *const sdk.misc.BaseDir, settings: *model.Settings) void {
        self.is_enabled.store(false, .seq_cst);
        std.log.debug("Spawning settings save thread...", .{});
        const thread = std.Thread.spawn(
            .{},
            struct {
                fn call(
                    dir: *const sdk.misc.BaseDir,
                    settings_to_save: model.Settings,
                    enabled: *std.atomic.Value(bool),
                ) void {
                    std.log.info("Settings save thread started.", .{});
                    std.log.info("Saving settings...", .{});
                    if (settings_to_save.save(dir)) {
                        std.log.info("Settings saved.", .{});
                        sdk.ui.toasts.send(.success, null, "Settings saved successfully.", .{});
                    } else |err| {
                        sdk.misc.error_context.append("Failed to save settings.", .{});
                        sdk.misc.error_context.logError(err);
                    }
                    enabled.store(true, .seq_cst);
                }
            }.call,
            .{ base_dir, settings.*, &self.is_enabled },
        ) catch |err| {
            sdk.misc.error_context.new("Failed to spawn settings save thread.", .{});
            sdk.misc.error_context.logError(err);
            self.is_enabled.store(true, .seq_cst);
            return;
        };
        thread.detach();
    }
};

const ReloadButton = struct {
    is_enabled: std.atomic.Value(bool) = .init(true),
    loaded_settings: ?model.Settings = null,
    confirm_open: bool = false,

    const Self = @This();

    fn draw(self: *Self, base_dir: *const sdk.misc.BaseDir, settings: *model.Settings) void {
        imgui.igBeginDisabled(!self.is_enabled.load(.seq_cst));
        defer imgui.igEndDisabled();
        if (imgui.igButton("Reload Settings", .{})) {
            self.confirm_open = true;
            imgui.igOpenPopup_Str("Reload settings?", 0);
        }
        if (imgui.igBeginPopupModal("Reload settings?", &self.confirm_open, imgui.ImGuiWindowFlags_AlwaysAutoResize)) {
            defer imgui.igEndPopup();
            imgui.igText("Are you sure you want to reload settings?");
            imgui.igText("Any settings you did not save will be lost.");
            imgui.igSeparator();
            if (imgui.igButton("Reload", .{})) {
                self.loadSettings(base_dir);
                imgui.igCloseCurrentPopup();
            }
            imgui.igSameLine(0, -1);
            imgui.igSetItemDefaultFocus();
            if (imgui.igButton("Cancel", .{})) {
                imgui.igCloseCurrentPopup();
            }
        }
        if (self.is_enabled.load(.seq_cst)) {
            if (self.loaded_settings) |s| {
                settings.* = s;
                self.loaded_settings = null;
                std.log.info("Settings loaded.", .{});
                sdk.ui.toasts.send(.success, null, "Settings reloaded successfully.", .{});
            }
        }
    }

    fn loadSettings(self: *Self, base_dir: *const sdk.misc.BaseDir) void {
        self.is_enabled.store(false, .seq_cst);
        std.log.debug("Spawning settings load thread...", .{});
        const thread = std.Thread.spawn(
            .{},
            struct {
                fn call(
                    s: *Self,
                    dir: *const sdk.misc.BaseDir,
                    enabled: *std.atomic.Value(bool),
                ) void {
                    std.log.info("Settings load thread started.", .{});
                    std.log.info("Loading settings...", .{});
                    if (model.Settings.load(dir)) |settings| {
                        s.loaded_settings = settings;
                        std.log.info("Settings loaded into temporary storage.", .{});
                    } else |err| {
                        sdk.misc.error_context.append("Failed to load settings.", .{});
                        sdk.misc.error_context.logError(err);
                    }
                    enabled.store(true, .seq_cst);
                }
            }.call,
            .{ self, base_dir, &self.is_enabled },
        ) catch |err| {
            sdk.misc.error_context.new("Failed to spawn settings load thread.", .{});
            sdk.misc.error_context.logError(err);
            self.is_enabled.store(true, .seq_cst);
            return;
        };
        thread.detach();
    }
};

const DefaultsButton = struct {
    confirm_open: bool = false,

    const Self = @This();

    fn draw(self: *Self, settings: *model.Settings) void {
        if (imgui.igButton("Reset Settings To Defaults", .{})) {
            self.confirm_open = true;
            imgui.igOpenPopup_Str("Reset settings to defaults?", 0);
        }
        if (imgui.igBeginPopupModal("Reset settings to defaults?", &self.confirm_open, imgui.ImGuiWindowFlags_AlwaysAutoResize)) {
            defer imgui.igEndPopup();
            imgui.igText("Are you sure you want to reset all settings to default values?");
            imgui.igText("Any settings you did not save will be lost.");
            imgui.igText("You can however reload your saved settings.");
            imgui.igText("(Unless you override them by saving.)");
            imgui.igSeparator();
            if (imgui.igButton("Reset", .{})) {
                settings.* = .{};
                std.log.info("Settings set to default values.", .{});
                sdk.ui.toasts.send(.success, null, "Settings set to default values.", .{});
                imgui.igCloseCurrentPopup();
            }
            imgui.igSameLine(0, -1);
            imgui.igSetItemDefaultFocus();
            if (imgui.igButton("Cancel", .{})) {
                imgui.igCloseCurrentPopup();
            }
        }
    }
};

fn drawPlayerSettings(
    comptime Type: type,
    settings: *model.PlayerSettings(Type),
    drawContent: *const fn (settings: *Type) void,
) void {
    const labels = std.EnumArray(model.PlayerSettingsMode, [:0]const u8).init(.{
        .same = "Same Settings",
        .id_separated = "Player 1 / Player 2",
        .side_separated = "Left Player / Right Player",
        .role_separated = "Main Player / Secondary Player",
    });
    if (imgui.igBeginCombo("Player Separation", labels.get(settings.mode), 0)) {
        defer imgui.igEndCombo();
        inline for (@typeInfo(model.PlayerSettingsMode).@"enum".fields) |*field| {
            const mode: model.PlayerSettingsMode = @enumFromInt(field.value);
            if (imgui.igSelectable_Bool(labels.get(mode), settings.mode == mode, 0, .{})) {
                settings.mode = mode;
            }
        }
    }

    const label_1, const label_2 = switch (settings.mode) {
        .same => {
            imgui.igSeparatorText("Both Players");
            drawContent(&settings.players[0]);
            return;
        },
        .id_separated => .{ "Player 1", "Player 2" },
        .side_separated => .{ "Left Player", "Right Player" },
        .role_separated => .{ "Main Player", "Secondary Player" },
    };
    const flags = imgui.ImGuiTableFlags_Resizable | imgui.ImGuiTableFlags_BordersInner;
    if (!imgui.igBeginTable("players", 2, flags, .{}, 0)) {
        return;
    }
    defer imgui.igEndTable();
    if (imgui.igTableNextColumn()) {
        imgui.igPushID_Str(label_1);
        defer imgui.igPopID();
        imgui.igSeparatorText(label_1);
        drawContent(&settings.players[0]);
    }
    if (imgui.igTableNextColumn()) {
        imgui.igPushID_Str(label_2);
        defer imgui.igPopID();
        imgui.igSeparatorText(label_2);
        drawContent(&settings.players[1]);
    }
}

fn drawHitLinesSettings(settings: *model.HitLinesSettings) void {
    const defaults = model.HitLinesSettings{};

    drawBool("Enabled", &settings.enabled, defaults.enabled);
    imgui.igBeginDisabled(!settings.enabled);
    defer imgui.igEndDisabled();

    const drawColors = struct {
        fn call(
            label: [:0]const u8,
            value: *std.EnumArray(model.AttackType, sdk.math.Vec4),
            default_value: std.EnumArray(model.AttackType, sdk.math.Vec4),
        ) void {
            imgui.igText("%s", label.ptr);
            imgui.igPushID_Str(label);
            defer imgui.igPopID();
            imgui.igIndent(0);
            defer imgui.igUnindent(0);
            inline for (@typeInfo(model.AttackType).@"enum".fields) |*field| {
                const attack_type: model.AttackType = @enumFromInt(field.value);
                const color_label = switch (attack_type) {
                    .not_attack => "Not Attack",
                    .high => "High",
                    .mid => "Mid",
                    .low => "Low",
                    .special_low => "Special Low",
                    .unblockable_high => "Unblockable High",
                    .unblockable_mid => "Unblockable Mid",
                    .unblockable_low => "Unblockable Low",
                    .throw => "Throw",
                    .projectile => "Projectile",
                    .antiair_only => "Anti-Air Only",
                };
                drawColor(color_label, value.getPtr(attack_type), default_value.get(attack_type));
            }
        }
    }.call;
    const drawColorsAndThickness = struct {
        fn call(
            label: [:0]const u8,
            value: *model.HitLinesSettings.ColorsAndThickness,
            default_value: model.HitLinesSettings.ColorsAndThickness,
        ) void {
            imgui.igText("%s", label.ptr);
            imgui.igPushID_Str(label);
            defer imgui.igPopID();
            imgui.igIndent(0);
            defer imgui.igUnindent(0);
            drawColors("Colors", &value.colors, default_value.colors);
            drawThickness("Thickness", &value.thickness, default_value.thickness);
        }
    }.call;
    const drawFillAndOutline = struct {
        fn call(
            label: [:0]const u8,
            value: *model.HitLinesSettings.FillAndOutline,
            default_value: model.HitLinesSettings.FillAndOutline,
        ) void {
            imgui.igText("%s", label.ptr);
            imgui.igPushID_Str(label);
            defer imgui.igPopID();
            imgui.igIndent(0);
            defer imgui.igUnindent(0);

            drawBool("Enabled", &value.enabled, default_value.enabled);
            imgui.igBeginDisabled(!value.enabled);
            defer imgui.igEndDisabled();

            drawColorsAndThickness("Fill", &value.fill, default_value.fill);
            drawColorsAndThickness("Outline", &value.outline, default_value.outline);
        }
    }.call;

    drawDuration("Lingering Duration", &settings.duration, defaults.duration);
    drawFillAndOutline("Normal Hit Lines", &settings.normal, defaults.normal);
    drawFillAndOutline("Inactive Or Crushed Hit Lines", &settings.inactive_or_crushed, defaults.inactive_or_crushed);
}

fn drawHurtCylindersSettings(settings: *model.HurtCylindersSettings) void {
    const defaults = model.HurtCylindersSettings{};

    drawBool("Enabled", &settings.enabled, defaults.enabled);
    imgui.igBeginDisabled(!settings.enabled);
    defer imgui.igEndDisabled();

    const drawColorAndThickness = struct {
        fn call(
            label: [:0]const u8,
            value: *model.HurtCylindersSettings.ColorAndThickness,
            default_value: model.HurtCylindersSettings.ColorAndThickness,
        ) void {
            imgui.igText("%s", label.ptr);
            imgui.igPushID_Str(label);
            defer imgui.igPopID();
            imgui.igIndent(0);
            defer imgui.igUnindent(0);
            drawColor("Color", &value.color, default_value.color);
            drawThickness("Thickness", &value.thickness, default_value.thickness);
        }
    }.call;
    const drawColorThicknessAndDuration = struct {
        fn call(
            label: [:0]const u8,
            value: *model.HurtCylindersSettings.ColorThicknessAndDuration,
            default_value: model.HurtCylindersSettings.ColorThicknessAndDuration,
        ) void {
            imgui.igText("%s", label.ptr);
            imgui.igPushID_Str(label);
            defer imgui.igPopID();
            imgui.igIndent(0);
            defer imgui.igUnindent(0);

            drawBool("Enabled", &value.enabled, default_value.enabled);
            imgui.igBeginDisabled(!value.enabled);
            defer imgui.igEndDisabled();

            drawColor("Color", &value.color, default_value.color);
            drawThickness("Thickness", &value.thickness, default_value.thickness);
            drawDuration("Duration", &value.duration, default_value.duration);
        }
    }.call;
    const drawCrushing = struct {
        fn call(
            label: [:0]const u8,
            value: *model.HurtCylindersSettings.Crushing,
            default_value: model.HurtCylindersSettings.Crushing,
        ) void {
            imgui.igText("%s", label.ptr);
            imgui.igPushID_Str(label);
            defer imgui.igPopID();
            imgui.igIndent(0);
            defer imgui.igUnindent(0);

            drawBool("Enabled", &value.enabled, default_value.enabled);
            imgui.igBeginDisabled(!value.enabled);
            defer imgui.igEndDisabled();

            drawColorAndThickness("Normal", &value.normal, default_value.normal);
            drawColorAndThickness("High Crushing", &value.high_crushing, default_value.high_crushing);
            drawColorAndThickness("Low Crushing", &value.low_crushing, default_value.low_crushing);
            drawColorAndThickness("Invincible", &value.invincible, default_value.invincible);
        }
    }.call;

    drawCrushing("Normal Hurt Cylinders", &settings.normal, defaults.normal);
    drawCrushing("Power-Crushing Hurt Cylinders", &settings.power_crushing, defaults.power_crushing);
    drawColorThicknessAndDuration("Connected (Hit) Hurt Cylinders", &settings.connected, defaults.connected);
    drawColorThicknessAndDuration("Lingering Hurt Cylinders", &settings.lingering, defaults.lingering);
}

fn drawCollisionSpheresSettings(settings: *model.CollisionSpheresSettings) void {
    const defaults = model.CollisionSpheresSettings{};

    drawBool("Enabled", &settings.enabled, defaults.enabled);
    imgui.igBeginDisabled(!settings.enabled);
    defer imgui.igEndDisabled();

    drawColor("Color", &settings.color, defaults.color);
    drawThickness("Thickness", &settings.thickness, defaults.thickness);
}

fn drawSkeletonSettings(settings: *model.SkeletonSettings) void {
    const defaults = model.SkeletonSettings{};

    drawBool("Enabled", &settings.enabled, defaults.enabled);
    imgui.igBeginDisabled(!settings.enabled);
    defer imgui.igEndDisabled();

    const drawColors = struct {
        fn call(
            label: [:0]const u8,
            value: *std.EnumArray(model.Blocking, sdk.math.Vec4),
            default_value: std.EnumArray(model.Blocking, sdk.math.Vec4),
        ) void {
            imgui.igText("%s", label.ptr);
            imgui.igPushID_Str(label);
            defer imgui.igPopID();
            imgui.igIndent(0);
            defer imgui.igUnindent(0);
            inline for (@typeInfo(model.Blocking).@"enum".fields) |*field| {
                const blocking: model.Blocking = @enumFromInt(field.value);
                const color_label = switch (blocking) {
                    .not_blocking => "Not Blocking",
                    .neutral_blocking_mids => "Neutral Blocking Mids",
                    .fully_blocking_mids => "Fully Blocking Mids",
                    .neutral_blocking_lows => "Neutral Blocking Lows",
                    .fully_blocking_lows => "Fully Blocking Lows",
                };
                drawColor(color_label, value.getPtr(blocking), default_value.get(blocking));
            }
        }
    }.call;

    drawColors("Colors", &settings.colors, defaults.colors);
    drawThickness("Thickness", &settings.thickness, defaults.thickness);
    drawFloat("Can't Move Alpha", &settings.cant_move_alpha, defaults.cant_move_alpha, 0.01, 0, 1, "%.2f", 0);
}

fn drawForwardDirectionsSettings(settings: *model.ForwardDirectionSettings) void {
    const defaults = model.ForwardDirectionSettings{};

    drawBool("Enabled", &settings.enabled, defaults.enabled);
    imgui.igBeginDisabled(!settings.enabled);
    defer imgui.igEndDisabled();

    drawColor("Color", &settings.color, defaults.color);
    drawLength("Length", &settings.length, defaults.length);
    drawThickness("Thickness", &settings.thickness, defaults.thickness);
}

fn drawFloorSettings(settings: *model.FloorSettings) void {
    const defaults = model.FloorSettings{};

    drawBool("Enabled", &settings.enabled, defaults.enabled);
    imgui.igBeginDisabled(!settings.enabled);
    defer imgui.igEndDisabled();

    drawColor("Color", &settings.color, defaults.color);
    drawThickness("Thickness", &settings.thickness, defaults.thickness);
}

fn drawIngameCameraSettings(settings: *model.IngameCameraSettings) void {
    const defaults = model.IngameCameraSettings{};

    drawBool("Enabled", &settings.enabled, defaults.enabled);
    imgui.igBeginDisabled(!settings.enabled);
    defer imgui.igEndDisabled();

    drawColor("Color", &settings.color, defaults.color);
    drawLength("Length", &settings.length, defaults.length);
    drawThickness("Thickness", &settings.thickness, defaults.thickness);
}

fn drawBool(label: [:0]const u8, value: *bool, default_value: bool) void {
    imgui.igPushID_Str(label);
    drawDefaultButton(value, default_value);
    imgui.igPopID();
    imgui.igSameLine(0, -1);
    _ = imgui.igCheckbox(label, value);
}

fn drawLength(label: [:0]const u8, value: *f32, default_value: f32) void {
    drawFloat(label, value, default_value, 1, 0, 10000, "%.0f cm", 0);
}

fn drawThickness(label: [:0]const u8, value: *f32, default_value: f32) void {
    drawFloat(label, value, default_value, 0.1, 0, 100, "%.1f px", 0);
}

fn drawDuration(label: [:0]const u8, value: *f32, default_value: f32) void {
    drawFloat(label, value, default_value, 0.1, 0, 100, "%.1f s", 0);
}

fn drawColor(label: [:0]const u8, value: *sdk.math.Vec4, default_value: sdk.math.Vec4) void {
    imgui.igPushID_Str(label);
    drawDefaultButton(value, default_value);
    imgui.igPopID();
    imgui.igSameLine(0, -1);
    _ = imgui.igColorEdit4(label, &value.array, 0);
}

fn drawFloat(
    label: [:0]const u8,
    value: *f32,
    default_value: f32,
    step: f32,
    min: f32,
    max: f32,
    format: [:0]const u8,
    flags: imgui.ImGuiInputTextFlags,
) void {
    imgui.igPushID_Str(label);
    drawDefaultButton(value, default_value);
    imgui.igPopID();
    imgui.igSameLine(0, -1);
    _ = imgui.igDragFloat(label, value, step, min, max, format, flags);
}

fn drawDefaultButton(value_pointer: anytype, default_value: @TypeOf(value_pointer.*)) void {
    imgui.igBeginDisabled(std.meta.eql(value_pointer.*, default_value));
    defer imgui.igEndDisabled();
    if (imgui.igButton(" ↺ ###default", .{})) {
        value_pointer.* = default_value;
    }
    if (imgui.igIsItemHovered(0)) {
        imgui.igSetTooltip("Reset To Default Value");
    }
}
