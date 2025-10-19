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
    const default_settings = model.Settings{};

    pub fn draw(self: *Self, base_dir: *const sdk.fs.BaseDir, settings: *model.Settings) void {
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

    pub fn drawNavigationLayout(self: *Self, base_dir: *const sdk.fs.BaseDir, settings: *model.Settings) void {
        const Context = struct {
            self: *Self,
            base_dir: *const sdk.fs.BaseDir,
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
                            &default_settings.hit_lines,
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
                            &default_settings.hurt_cylinders,
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
                            &default_settings.collision_spheres,
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
                            &default_settings.skeletons,
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
                            &default_settings.forward_directions,
                            drawForwardDirectionsSettings,
                        );
                    }
                }.call,
            },
            .{
                .name = "Floor",
                .content = struct {
                    fn call(c: *const Context) void {
                        drawFloorSettings(&c.settings.floor, &default_settings.floor);
                    }
                }.call,
            },
            .{
                .name = "Ingame Camera",
                .content = struct {
                    fn call(c: *const Context) void {
                        drawIngameCameraSettings(&c.settings.ingame_camera, &default_settings.ingame_camera);
                    }
                }.call,
            },
            .{
                .name = "Miscellaneous",
                .content = struct {
                    fn call(c: *const Context) void {
                        c.self.misc_settings.draw(c.base_dir, c.settings, &default_settings);
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

    pub fn draw(
        self: *Self,
        base_dir: *const sdk.fs.BaseDir,
        settings: *model.Settings,
        default_settings: *const model.Settings,
    ) void {
        drawMiscSettings(&settings.misc, &default_settings.misc);
        imgui.igSeparator();
        self.reload_button.draw(base_dir, settings);
        self.defaults_button.draw(settings, default_settings);
    }
};

const SaveButton = struct {
    height: f32 = 0,

    // Using a global to avoid the possibility of lifetime problems.
    var is_loading = std.atomic.Value(bool).init(false);

    const Self = @This();

    fn draw(self: *Self, base_dir: *const sdk.fs.BaseDir, settings: *model.Settings) void {
        var content_size: imgui.ImVec2 = undefined;
        imgui.igGetContentRegionAvail(&content_size);

        const loading = is_loading.load(.seq_cst);
        imgui.igBeginDisabled(loading);
        defer imgui.igEndDisabled();
        const label = if (loading) "Saving..." else "Save";
        if (imgui.igButton(label, .{ .x = content_size.x })) {
            saveSettings(base_dir, settings);
        }
        var size: imgui.ImVec2 = undefined;
        imgui.igGetItemRectSize(&size);
        self.height = size.y;
    }

    fn saveSettings(base_dir: *const sdk.fs.BaseDir, settings: *model.Settings) void {
        is_loading.store(true, .seq_cst);
        std.log.info("Saving settings...", .{});
        std.log.debug("Spawning settings save thread...", .{});
        const thread = std.Thread.spawn(
            .{},
            struct {
                fn call(dir: sdk.fs.BaseDir, settings_to_save: model.Settings) void {
                    std.log.debug("Settings save thread started.", .{});
                    if (settings_to_save.save(&dir)) {
                        std.log.info("Settings saved.", .{});
                        sdk.ui.toasts.send(.success, null, "Settings saved successfully.", .{});
                    } else |err| {
                        sdk.misc.error_context.append("Failed to save settings.", .{});
                        sdk.misc.error_context.logError(err);
                    }
                    is_loading.store(false, .seq_cst);
                }
            }.call,
            .{ base_dir.*, settings.* },
        ) catch |err| {
            sdk.misc.error_context.new("Failed to spawn settings save thread.", .{});
            sdk.misc.error_context.append("Failed to save settings.", .{});
            sdk.misc.error_context.logError(err);
            is_loading.store(false, .seq_cst);
            return;
        };
        thread.detach();
    }
};

const ReloadButton = struct {
    confirm_open: bool = false,

    // Using globals to avoid the possibility of lifetime problems.
    var is_loading = std.atomic.Value(bool).init(false);
    var loaded_settings: ?model.Settings = null;

    const Self = @This();

    fn draw(self: *Self, base_dir: *const sdk.fs.BaseDir, settings: *model.Settings) void {
        const loading = is_loading.load(.seq_cst);
        imgui.igBeginDisabled(loading);
        defer imgui.igEndDisabled();
        const label = if (loading) "Reloading settings..." else "Reload Settings";
        if (imgui.igButton(label, .{})) {
            self.confirm_open = true;
            imgui.igOpenPopup_Str("Reload settings?", 0);
        }
        if (imgui.igBeginPopupModal("Reload settings?", &self.confirm_open, imgui.ImGuiWindowFlags_AlwaysAutoResize)) {
            defer imgui.igEndPopup();
            imgui.igText("Are you sure you want to reload settings?");
            imgui.igText("Any settings you did not save will be lost.");
            imgui.igSeparator();
            if (imgui.igButton("Reload", .{})) {
                loadSettings(base_dir);
                imgui.igCloseCurrentPopup();
            }
            imgui.igSameLine(0, -1);
            imgui.igSetItemDefaultFocus();
            if (imgui.igButton("Cancel", .{})) {
                imgui.igCloseCurrentPopup();
            }
        }
        checkLoadedSettings(settings);
    }

    fn loadSettings(base_dir: *const sdk.fs.BaseDir) void {
        is_loading.store(true, .seq_cst);
        std.log.info("Loading settings...", .{});
        std.log.debug("Spawning settings load thread...", .{});
        const thread = std.Thread.spawn(
            .{},
            struct {
                fn call(dir: sdk.fs.BaseDir) void {
                    std.log.debug("Settings load thread started.", .{});
                    if (model.Settings.load(&dir)) |settings| {
                        loaded_settings = settings;
                        std.log.debug("Settings loaded into temporary storage.", .{});
                    } else |err| {
                        sdk.misc.error_context.append("Failed to load settings.", .{});
                        sdk.misc.error_context.logError(err);
                    }
                    is_loading.store(false, .seq_cst);
                }
            }.call,
            .{base_dir.*},
        ) catch |err| {
            sdk.misc.error_context.new("Failed to spawn settings load thread.", .{});
            sdk.misc.error_context.append("Failed to load settings.", .{});
            sdk.misc.error_context.logError(err);
            is_loading.store(false, .seq_cst);
            return;
        };
        thread.detach();
    }

    fn checkLoadedSettings(settings: *model.Settings) void {
        if (is_loading.load(.seq_cst)) {
            return;
        }
        const settings_to_load = loaded_settings orelse return;
        settings.* = settings_to_load;
        loaded_settings = null;
        std.log.info("Settings loaded.", .{});
        sdk.ui.toasts.send(.success, null, "Settings reloaded successfully.", .{});
    }
};

const DefaultsButton = struct {
    confirm_open: bool = false,

    const Self = @This();

    fn draw(self: *Self, settings: *model.Settings, default_settings: *const model.Settings) void {
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
                settings.* = default_settings.*;
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
    value: *model.PlayerSettings(Type),
    default: *const model.PlayerSettings(Type),
    drawContent: *const fn (value: *Type, default: *const Type) void,
) void {
    drawEnum(
        model.PlayerSettingsMode,
        "Player Separation",
        &.{
            .same = "Same Settings",
            .id_separated = "Player 1 / Player 2",
            .side_separated = "Left Player / Right Player",
            .role_separated = "Main Player / Secondary Player",
        },
        &value.mode,
        &default.mode,
    );

    const label_1, const label_2 = switch (value.mode) {
        .same => {
            imgui.igSeparatorText("Both Players");
            drawContent(&value.players[0], &default.players[0]);
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
        drawContent(&value.players[0], &default.players[0]);
    }
    if (imgui.igTableNextColumn()) {
        imgui.igPushID_Str(label_2);
        defer imgui.igPopID();
        imgui.igSeparatorText(label_2);
        drawContent(&value.players[1], &default.players[1]);
    }
}

fn drawHitLinesSettings(value: *model.HitLinesSettings, default: *const model.HitLinesSettings) void {
    drawBool("Enabled", &value.enabled, &default.enabled);
    imgui.igBeginDisabled(!value.enabled);
    defer imgui.igEndDisabled();

    const drawColors = struct {
        fn call(
            label: [:0]const u8,
            v: *std.EnumArray(model.AttackType, sdk.math.Vec4),
            d: *const std.EnumArray(model.AttackType, sdk.math.Vec4),
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
                drawColor(color_label, v.getPtr(attack_type), d.getPtrConst(attack_type));
            }
        }
    }.call;
    const drawColorsAndThickness = struct {
        fn call(
            label: [:0]const u8,
            v: *model.HitLinesSettings.ColorsAndThickness,
            d: *const model.HitLinesSettings.ColorsAndThickness,
        ) void {
            imgui.igText("%s", label.ptr);
            imgui.igPushID_Str(label);
            defer imgui.igPopID();
            imgui.igIndent(0);
            defer imgui.igUnindent(0);
            drawColors("Colors", &v.colors, &d.colors);
            drawThickness("Thickness", &v.thickness, &d.thickness);
        }
    }.call;
    const drawFillAndOutline = struct {
        fn call(
            label: [:0]const u8,
            v: *model.HitLinesSettings.FillAndOutline,
            d: *const model.HitLinesSettings.FillAndOutline,
        ) void {
            imgui.igText("%s", label.ptr);
            imgui.igPushID_Str(label);
            defer imgui.igPopID();
            imgui.igIndent(0);
            defer imgui.igUnindent(0);

            drawBool("Enabled", &v.enabled, &d.enabled);
            imgui.igBeginDisabled(!v.enabled);
            defer imgui.igEndDisabled();

            drawColorsAndThickness("Fill", &v.fill, &d.fill);
            drawColorsAndThickness("Outline", &v.outline, &d.outline);
        }
    }.call;

    drawDuration("Lingering Duration", &value.duration, &default.duration);
    drawFillAndOutline("Normal Hit Lines", &value.normal, &default.normal);
    drawFillAndOutline("Inactive Or Crushed Hit Lines", &value.inactive_or_crushed, &default.inactive_or_crushed);
}

fn drawHurtCylindersSettings(value: *model.HurtCylindersSettings, default: *const model.HurtCylindersSettings) void {
    drawBool("Enabled", &value.enabled, &default.enabled);
    imgui.igBeginDisabled(!value.enabled);
    defer imgui.igEndDisabled();

    const drawColorAndThickness = struct {
        fn call(
            label: [:0]const u8,
            v: *model.HurtCylindersSettings.ColorAndThickness,
            d: *const model.HurtCylindersSettings.ColorAndThickness,
        ) void {
            imgui.igText("%s", label.ptr);
            imgui.igPushID_Str(label);
            defer imgui.igPopID();
            imgui.igIndent(0);
            defer imgui.igUnindent(0);
            drawColor("Color", &v.color, &d.color);
            drawThickness("Thickness", &v.thickness, &d.thickness);
        }
    }.call;
    const drawColorThicknessAndDuration = struct {
        fn call(
            label: [:0]const u8,
            v: *model.HurtCylindersSettings.ColorThicknessAndDuration,
            d: *const model.HurtCylindersSettings.ColorThicknessAndDuration,
        ) void {
            imgui.igText("%s", label.ptr);
            imgui.igPushID_Str(label);
            defer imgui.igPopID();
            imgui.igIndent(0);
            defer imgui.igUnindent(0);

            drawBool("Enabled", &v.enabled, &d.enabled);
            imgui.igBeginDisabled(!v.enabled);
            defer imgui.igEndDisabled();

            drawColor("Color", &v.color, &d.color);
            drawThickness("Thickness", &v.thickness, &d.thickness);
            drawDuration("Duration", &v.duration, &d.duration);
        }
    }.call;
    const drawCrushing = struct {
        fn call(
            label: [:0]const u8,
            v: *model.HurtCylindersSettings.Crushing,
            d: *const model.HurtCylindersSettings.Crushing,
        ) void {
            imgui.igText("%s", label.ptr);
            imgui.igPushID_Str(label);
            defer imgui.igPopID();
            imgui.igIndent(0);
            defer imgui.igUnindent(0);

            drawBool("Enabled", &v.enabled, &d.enabled);
            imgui.igBeginDisabled(!v.enabled);
            defer imgui.igEndDisabled();

            drawColorAndThickness("Normal", &v.normal, &d.normal);
            drawColorAndThickness("High Crushing", &v.high_crushing, &d.high_crushing);
            drawColorAndThickness("Low Crushing", &v.low_crushing, &d.low_crushing);
            drawColorAndThickness("Invincible", &v.invincible, &d.invincible);
        }
    }.call;

    drawCrushing("Normal Hurt Cylinders", &value.normal, &default.normal);
    drawCrushing("Power-Crushing Hurt Cylinders", &value.power_crushing, &default.power_crushing);
    drawColorThicknessAndDuration("Connected (Hit) Hurt Cylinders", &value.connected, &default.connected);
    drawColorThicknessAndDuration("Lingering Hurt Cylinders", &value.lingering, &default.lingering);
}

fn drawCollisionSpheresSettings(value: *model.CollisionSpheresSettings, default: *const model.CollisionSpheresSettings) void {
    drawBool("Enabled", &value.enabled, &default.enabled);
    imgui.igBeginDisabled(!value.enabled);
    defer imgui.igEndDisabled();

    drawColor("Color", &value.color, &default.color);
    drawThickness("Thickness", &value.thickness, &default.thickness);
}

fn drawSkeletonSettings(value: *model.SkeletonSettings, default: *const model.SkeletonSettings) void {
    drawBool("Enabled", &value.enabled, &default.enabled);
    imgui.igBeginDisabled(!value.enabled);
    defer imgui.igEndDisabled();

    const drawColors = struct {
        fn call(
            label: [:0]const u8,
            v: *std.EnumArray(model.Blocking, sdk.math.Vec4),
            d: *const std.EnumArray(model.Blocking, sdk.math.Vec4),
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
                drawColor(color_label, v.getPtr(blocking), d.getPtrConst(blocking));
            }
        }
    }.call;

    drawColors("Colors", &value.colors, &default.colors);
    drawThickness("Thickness", &value.thickness, &default.thickness);
    drawFloat("Can't Move Alpha", &value.cant_move_alpha, &default.cant_move_alpha, 0.01, 0, 1, "%.2f", 0);
}

fn drawForwardDirectionsSettings(
    value: *model.ForwardDirectionSettings,
    default: *const model.ForwardDirectionSettings,
) void {
    drawBool("Enabled", &value.enabled, &default.enabled);
    imgui.igBeginDisabled(!value.enabled);
    defer imgui.igEndDisabled();

    drawColor("Color", &value.color, &default.color);
    drawLength("Length", &value.length, &default.length);
    drawThickness("Thickness", &value.thickness, &default.thickness);
}

fn drawFloorSettings(value: *model.FloorSettings, default: *const model.FloorSettings) void {
    drawBool("Enabled", &value.enabled, &default.enabled);
    imgui.igBeginDisabled(!value.enabled);
    defer imgui.igEndDisabled();

    drawColor("Color", &value.color, &default.color);
    drawThickness("Thickness", &value.thickness, &default.thickness);
}

fn drawIngameCameraSettings(value: *model.IngameCameraSettings, default: *const model.IngameCameraSettings) void {
    drawBool("Enabled", &value.enabled, &default.enabled);
    imgui.igBeginDisabled(!value.enabled);
    defer imgui.igEndDisabled();

    drawColor("Color", &value.color, &default.color);
    drawLength("Length", &value.length, &default.length);
    drawThickness("Thickness", &value.thickness, &default.thickness);
}

fn drawMiscSettings(value: *model.MiscSettings, default: *const model.MiscSettings) void {
    drawEnum(
        model.MiscSettings.DetailsColumns,
        "Details Table Columns",
        &.{
            .id_based = "Player 1 / Player 2",
            .side_based = "Left Player / Right Player",
            .role_based = "Main Player / Secondary Player",
        },
        &value.details_columns,
        &default.details_columns,
    );
}

fn drawBool(label: [:0]const u8, value: *bool, default: *const bool) void {
    imgui.igPushID_Str(label);
    drawDefaultButton(value, default);
    imgui.igPopID();
    imgui.igSameLine(0, -1);
    _ = imgui.igCheckbox(label, value);
}

fn drawLength(label: [:0]const u8, value: *f32, default: *const f32) void {
    drawFloat(label, value, default, 1, 0, 10000, "%.0f cm", 0);
}

fn drawThickness(label: [:0]const u8, value: *f32, default: *const f32) void {
    drawFloat(label, value, default, 0.1, 0, 100, "%.1f px", 0);
}

fn drawDuration(label: [:0]const u8, value: *f32, default: *const f32) void {
    drawFloat(label, value, default, 0.1, 0, 100, "%.1f s", 0);
}

fn drawColor(label: [:0]const u8, value: *sdk.math.Vec4, default: *const sdk.math.Vec4) void {
    imgui.igPushID_Str(label);
    drawDefaultButton(value, default);
    imgui.igPopID();
    imgui.igSameLine(0, -1);
    _ = imgui.igColorEdit4(label, &value.array, 0);
}

fn drawFloat(
    label: [:0]const u8,
    value: *f32,
    default: *const f32,
    step: f32,
    min: f32,
    max: f32,
    format: [:0]const u8,
    flags: imgui.ImGuiInputTextFlags,
) void {
    imgui.igPushID_Str(label);
    drawDefaultButton(value, default);
    imgui.igPopID();
    imgui.igSameLine(0, -1);
    _ = imgui.igDragFloat(label, value, step, min, max, format, flags);
}

fn drawEnum(
    comptime Type: type,
    label: [:0]const u8,
    names: *const std.enums.EnumFieldStruct(Type, [:0]const u8, null),
    value: *Type,
    default: *const Type,
) void {
    const fields = switch (@typeInfo(Type)) {
        .@"enum" => |info| info.fields,
        else => @compileError("Expected Type to be a enum type but got: " ++ @typeName(Type)),
    };
    imgui.igPushID_Str(label);
    drawDefaultButton(value, default);
    imgui.igPopID();
    imgui.igSameLine(0, -1);
    const array = std.EnumArray(Type, [:0]const u8).init(names.*);
    if (imgui.igBeginCombo(label, array.get(value.*), 0)) {
        defer imgui.igEndCombo();
        inline for (fields) |*field| {
            const current_value: Type = @enumFromInt(field.value);
            if (imgui.igSelectable_Bool(array.get(current_value), value.* == current_value, 0, .{})) {
                value.* = current_value;
            }
        }
    }
}

fn drawDefaultButton(value: anytype, default: *const @TypeOf(value.*)) void {
    imgui.igBeginDisabled(std.meta.eql(value.*, default.*));
    defer imgui.igEndDisabled();
    if (imgui.igButton(" ↺ ###default", .{})) {
        value.* = default.*;
    }
    if (imgui.igIsItemHovered(0)) {
        imgui.igSetTooltip("Reset To Default Value");
    }
}
