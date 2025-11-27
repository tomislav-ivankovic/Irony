const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("root.zig");

pub const SettingsWindow = struct {
    is_open: bool,
    navigation_layout: ui.NavigationLayout,
    misc_settings: MiscSettings,
    save_button: SaveButton,

    const Self = @This();
    pub const name = "Settings";
    const default_settings = model.Settings{};

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .is_open = false,
            .navigation_layout = .{},
            .misc_settings = .init(allocator),
            .save_button = .init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.save_button.deinit();
        self.misc_settings.deinit();
    }

    pub fn draw(self: *Self, base_dir: *const sdk.misc.BaseDir, settings: *model.Settings) void {
        if (!self.is_open) {
            return;
        }

        const display_size = imgui.igGetIO_Nil().*.DisplaySize;
        imgui.igSetNextWindowPos(
            .{ .x = 0.5 * display_size.x, .y = 0.5 * display_size.y },
            imgui.ImGuiCond_FirstUseEver,
            .{ .x = 0.5, .y = 0.5 },
        );
        imgui.igSetNextWindowSize(.{ .x = 720, .y = 480 }, imgui.ImGuiCond_FirstUseEver);

        const render_content = imgui.igBegin(name, &self.is_open, imgui.ImGuiWindowFlags_HorizontalScrollbar);
        defer imgui.igEnd();
        if (!render_content) {
            return;
        }

        var content_size: imgui.ImVec2 = undefined;
        imgui.igGetContentRegionAvail(&content_size);

        const navigation_layout_height = content_size.y - self.save_button.height - imgui.igGetStyle().*.ItemSpacing.y;
        if (imgui.igBeginChild_Str("layout", .{ .y = navigation_layout_height }, 0, 0)) {
            self.drawNavigationLayout(base_dir, settings);
        }
        imgui.igEndChild();

        self.save_button.draw(base_dir, settings);
    }

    fn drawNavigationLayout(self: *Self, base_dir: *const sdk.misc.BaseDir, settings: *model.Settings) void {
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
                .name = "Measure Tool",
                .content = struct {
                    fn call(c: *const Context) void {
                        drawMeasureToolSettings(&c.settings.measure_tool, &default_settings.measure_tool);
                    }
                }.call,
            },
            .{
                .name = "Details Table",
                .content = struct {
                    fn call(c: *const Context) void {
                        drawDetailsSettings(&c.settings.details, &default_settings.details);
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
    reload_button: ReloadButton,
    defaults_button: DefaultsButton,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .reload_button = .init(allocator),
            .defaults_button = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.reload_button.deinit();
    }

    pub fn draw(
        self: *Self,
        base_dir: *const sdk.misc.BaseDir,
        settings: *model.Settings,
        default_settings: *const model.Settings,
    ) void {
        self.reload_button.draw(base_dir, settings);
        self.defaults_button.draw(settings, default_settings);
    }
};

const SaveButton = struct {
    allocator: std.mem.Allocator,
    task: Task,
    height: f32,

    const Self = @This();
    const Task = sdk.misc.Task(void);

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .task = .createCompleted({}),
            .height = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self.task.join();
    }

    fn draw(self: *Self, base_dir: *const sdk.misc.BaseDir, settings: *model.Settings) void {
        var content_size: imgui.ImVec2 = undefined;
        imgui.igGetContentRegionAvail(&content_size);

        const is_loading = self.task.peek() == null;
        imgui.igBeginDisabled(is_loading);
        defer imgui.igEndDisabled();
        const label = if (is_loading) "Saving..." else "Save";
        if (imgui.igButton(label, .{ .x = content_size.x })) {
            self.saveSettings(base_dir, settings);
        }
        var size: imgui.ImVec2 = undefined;
        imgui.igGetItemRectSize(&size);
        self.height = size.y;
    }

    fn saveSettings(self: *Self, base_dir: *const sdk.misc.BaseDir, settings: *const model.Settings) void {
        std.log.info("Saving settings...", .{});
        std.log.debug("Spawning settings save thread...", .{});
        _ = self.task.join();
        self.task = Task.spawn(
            self.allocator,
            struct {
                fn call(dir: sdk.misc.BaseDir, settings_to_save: model.Settings) void {
                    std.log.debug("Settings save task started.", .{});
                    if (settings_to_save.save(&dir)) {
                        std.log.info("Settings saved.", .{});
                        sdk.ui.toasts.send(.success, null, "Settings saved successfully.", .{});
                    } else |err| {
                        sdk.misc.error_context.append("Failed to save settings.", .{});
                        sdk.misc.error_context.logError(err);
                    }
                }
            }.call,
            .{ base_dir.*, settings.* },
        ) catch |err| {
            sdk.misc.error_context.new("Failed to spawn settings save task.", .{});
            sdk.misc.error_context.append("Failed to save settings.", .{});
            sdk.misc.error_context.logError(err);
            return;
        };
    }
};

const ReloadButton = struct {
    allocator: std.mem.Allocator,
    task: Task,
    confirm_open: bool,

    const Self = @This();
    const Task = sdk.misc.Task(?model.Settings);

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .task = .createCompleted(null),
            .confirm_open = false,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self.task.join();
    }

    fn draw(self: *Self, base_dir: *const sdk.misc.BaseDir, settings: *model.Settings) void {
        const is_loading = self.task.peek() == null;
        imgui.igBeginDisabled(is_loading);
        defer imgui.igEndDisabled();
        const label = if (is_loading) "Reloading settings..." else "Reload Settings";
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
                self.loadSettings(base_dir);
                imgui.igCloseCurrentPopup();
            }
            imgui.igSameLine(0, -1);
            imgui.igSetItemDefaultFocus();
            if (imgui.igButton("Cancel", .{})) {
                imgui.igCloseCurrentPopup();
            }
        }
        self.checkLoadedSettings(settings);
    }

    fn loadSettings(self: *Self, base_dir: *const sdk.misc.BaseDir) void {
        std.log.info("Loading settings...", .{});
        std.log.debug("Spawning settings load thread...", .{});
        _ = self.task.join();
        self.task = Task.spawn(
            self.allocator,
            struct {
                fn call(dir: sdk.misc.BaseDir) ?model.Settings {
                    std.log.debug("Settings load task started.", .{});
                    if (model.Settings.load(&dir)) |settings| {
                        std.log.debug("Settings loaded into temporary storage.", .{});
                        return settings;
                    } else |err| {
                        sdk.misc.error_context.append("Failed to load settings.", .{});
                        sdk.misc.error_context.logError(err);
                        return null;
                    }
                }
            }.call,
            .{base_dir.*},
        ) catch |err| {
            sdk.misc.error_context.new("Failed to spawn settings load task.", .{});
            sdk.misc.error_context.append("Failed to load settings.", .{});
            sdk.misc.error_context.logError(err);
            return;
        };
    }

    fn checkLoadedSettings(self: *Self, settings: *model.Settings) void {
        const settings_to_load = (self.task.peek() orelse return).* orelse return;
        settings.* = settings_to_load;
        self.task = .createCompleted(null);
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
    if (!imgui.igBeginTable("table", 2, flags, .{}, 0)) {
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

fn drawMeasureToolSettings(value: *model.MeasureToolSettings, default: *const model.MeasureToolSettings) void {
    const drawColorAndThickness = struct {
        fn call(
            label: [:0]const u8,
            v: *model.MeasureToolSettings.ColorAndThickness,
            d: *const model.MeasureToolSettings.ColorAndThickness,
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

    drawColorAndThickness("Line", &value.line, &default.line);
    drawColorAndThickness("Normal Point", &value.normal_point, &default.normal_point);
    drawColorAndThickness("Hovered Point", &value.hovered_point, &default.hovered_point);
    drawColor("Text Color", &value.text_color, &default.text_color);
    drawThickness("Hover Distance", &value.hover_distance, &default.hover_distance);
}

fn drawDetailsSettings(value: *model.DetailsSettings, default: *const model.DetailsSettings) void {
    const drawRowsEnabled = struct {
        fn call(
            label: [:0]const u8,
            v: *model.DetailsSettings.RowsEnabled,
            d: *const model.DetailsSettings.RowsEnabled,
        ) void {
            imgui.igText("%s", label.ptr);
            imgui.igPushID_Str(label);
            defer imgui.igPopID();
            imgui.igIndent(0);
            defer imgui.igUnindent(0);
            inline for (@typeInfo(ui.Details).@"struct".fields) |*field| {
                drawBool(field.type.display_name, &@field(v, field.name), &@field(d, field.name));
            }
            if (imgui.igButton("Enable All", .{})) {
                inline for (@typeInfo(ui.Details).@"struct".fields) |*field| {
                    @field(v, field.name) = true;
                }
            }
            imgui.igSameLine(0, -1);
            if (imgui.igButton("Disable All", .{})) {
                inline for (@typeInfo(ui.Details).@"struct".fields) |*field| {
                    @field(v, field.name) = false;
                }
            }
        }
    }.call;
    const column_names = std.enums.EnumFieldStruct(model.DetailsSettings.Column, [:0]const u8, null){
        .player_1 = "Player 1",
        .player_2 = "Player 2",
        .left_player = "Left Player",
        .right_player = "Right Player",
        .main_player = "Main Player ",
        .secondary_player = "Secondary Player",
    };
    drawEnum(model.DetailsSettings.Column, "Column 1", &column_names, &value.column_1, &default.column_1);
    drawEnum(model.DetailsSettings.Column, "Column 2", &column_names, &value.column_2, &default.column_2);
    drawFloat("Fade Out Duration", &value.fade_out_duration, &default.fade_out_duration, 0.01, 0, 10, "%.2f s", 0);
    drawFloat("Fade Out Alpha", &value.fade_out_alpha, &default.fade_out_alpha, 0.01, 0, 1, "%.2f", 0);
    drawRowsEnabled("Enabled Rows", &value.rows_enabled, &default.rows_enabled);
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

const testing = std.testing;
const testing_base_dir = sdk.misc.BaseDir.fromStr("test_assets") catch unreachable;

test "should not draw anything when window is closed" {
    const Test = struct {
        var settings = model.Settings{};
        var window: SettingsWindow = undefined;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(&testing_base_dir, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try ctx.expectItemNotExists("//" ++ SettingsWindow.name);
        }
    };
    Test.window = .init(testing.allocator);
    defer Test.window.deinit();
    Test.window.is_open = false;
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "reset settings to defaults button should set settings to default value when clicked and confirmed" {
    const Test = struct {
        const default_settings = model.Settings{};
        var settings = default_settings;
        var window: SettingsWindow = undefined;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(&testing_base_dir, &settings);
            sdk.ui.toasts.draw();
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            sdk.ui.toasts.update(100);
            ctx.setRef(SettingsWindow.name);
            ctx.itemClick("**/Miscellaneous", imgui.ImGuiMouseButton_Left, 0);
            ctx.setRef(ctx.windowInfo("layout/content", 0).Window);

            settings.floor.thickness = 123;
            try testing.expect(!std.meta.eql(default_settings, settings));

            ctx.itemClick("Reset Settings To Defaults", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("//$FOCUSED/Cancel", imgui.ImGuiMouseButton_Left, 0);

            try testing.expect(!std.meta.eql(default_settings, settings));
            try ctx.expectItemNotExists("//toast-0");

            ctx.itemClick("Reset Settings To Defaults", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("//$FOCUSED/Reset", imgui.ImGuiMouseButton_Left, 0);

            try ctx.expectItemExists("//toast-0/Settings set to default values.");
            try testing.expectEqual(default_settings, settings);
        }
    };
    Test.window = .init(testing.allocator);
    defer Test.window.deinit();
    Test.window.is_open = true;
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "reload settings button should load the same settings that the save button saved" {
    const Test = struct {
        var settings = model.Settings{};
        var window: SettingsWindow = undefined;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(&testing_base_dir, &settings);
            sdk.ui.toasts.draw();
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            sdk.ui.toasts.update(100);
            settings.floor.thickness = 123;

            ctx.setRef(SettingsWindow.name);
            ctx.itemClick("Save", imgui.ImGuiMouseButton_Left, 0);
            while (ctx.itemExists("Saving...")) {
                ctx.yield(1);
            }
            defer std.fs.cwd().deleteFile("./test_assets/" ++ model.Settings.file_name) catch {
                @panic("Failed to cleanup test file.");
            };
            try ctx.expectItemExists("Save");

            const saved_settings = settings;
            settings.floor.thickness = 456;
            try testing.expect(!std.meta.eql(settings, saved_settings));
            try ctx.expectItemExists("//toast-0/Settings saved successfully.");
            sdk.ui.toasts.update(100);

            ctx.itemClick("**/Miscellaneous", imgui.ImGuiMouseButton_Left, 0);
            ctx.setRef(ctx.windowInfo("layout/content", 0).Window);
            ctx.itemClick("Reload Settings", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("//$FOCUSED/Cancel", imgui.ImGuiMouseButton_Left, 0);

            try testing.expect(!std.meta.eql(settings, saved_settings));
            try ctx.expectItemNotExists("//toast-0");

            ctx.itemClick("Reload Settings", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("//$FOCUSED/Reload", imgui.ImGuiMouseButton_Left, 0);
            while (ctx.itemExists("Reloading settings...")) {
                ctx.yield(1);
            }
            try ctx.expectItemExists("Reload Settings");

            try testing.expectEqual(saved_settings, settings);
            try ctx.expectItemExists("//toast-0/Settings reloaded successfully.");
        }
    };
    Test.window = .init(testing.allocator);
    defer Test.window.deinit();
    Test.window.is_open = true;
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "player settings separation should function correctly" {
    const Test = struct {
        var settings = model.Settings{};
        var window: SettingsWindow = undefined;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(&testing_base_dir, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const current = &settings.skeletons;

            ctx.setRef(SettingsWindow.name);
            ctx.itemClick("**/Skeletons", imgui.ImGuiMouseButton_Left, 0);
            ctx.setRef(ctx.windowInfo("layout/content", 0).Window);

            ctx.itemClick("Player Separation", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("//$FOCUSED/Same Settings", imgui.ImGuiMouseButton_Left, 0);

            try testing.expectEqual(.same, current.mode);
            ctx.itemUncheck("Enabled", 0);
            try testing.expectEqual(false, current.players[0].enabled);
            ctx.itemCheck("Enabled", 0);
            try testing.expectEqual(true, current.players[0].enabled);

            ctx.itemClick("Player Separation", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("//$FOCUSED/Player 1 \\/ Player 2", imgui.ImGuiMouseButton_Left, 0);

            try testing.expectEqual(.id_separated, current.mode);
            ctx.itemUncheck("**/Player 1/Enabled", 0);
            try testing.expectEqual(false, current.players[0].enabled);
            ctx.itemCheck("**/Player 1/Enabled", 0);
            try testing.expectEqual(true, current.players[0].enabled);
            ctx.itemUncheck("**/Player 2/Enabled", 0);
            try testing.expectEqual(false, current.players[1].enabled);
            ctx.itemCheck("**/Player 2/Enabled", 0);
            try testing.expectEqual(true, current.players[1].enabled);

            ctx.itemClick("Player Separation", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("//$FOCUSED/Left Player \\/ Right Player", imgui.ImGuiMouseButton_Left, 0);

            try testing.expectEqual(.side_separated, current.mode);
            ctx.itemUncheck("**/Left Player/Enabled", 0);
            try testing.expectEqual(false, current.players[0].enabled);
            ctx.itemCheck("**/Left Player/Enabled", 0);
            try testing.expectEqual(true, current.players[0].enabled);
            ctx.itemUncheck("**/Right Player/Enabled", 0);
            try testing.expectEqual(false, current.players[1].enabled);
            ctx.itemCheck("**/Right Player/Enabled", 0);
            try testing.expectEqual(true, current.players[1].enabled);

            ctx.itemClick("Player Separation", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("//$FOCUSED/Main Player \\/ Secondary Player", imgui.ImGuiMouseButton_Left, 0);

            try testing.expectEqual(.role_separated, current.mode);
            ctx.itemUncheck("**/Main Player/Enabled", 0);
            try testing.expectEqual(false, current.players[0].enabled);
            ctx.itemCheck("**/Main Player/Enabled", 0);
            try testing.expectEqual(true, current.players[0].enabled);
            ctx.itemUncheck("**/Secondary Player/Enabled", 0);
            try testing.expectEqual(false, current.players[1].enabled);
            ctx.itemCheck("**/Secondary Player/Enabled", 0);
            try testing.expectEqual(true, current.players[1].enabled);
        }
    };
    Test.window = .init(testing.allocator);
    defer Test.window.deinit();
    Test.window.is_open = true;
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "hit line settings should function correctly" {
    const Test = struct {
        const default_settings = model.Settings{};
        var settings = default_settings;
        var window: SettingsWindow = undefined;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(&testing_base_dir, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const current = &settings.hit_lines.players[0];
            const default = &default_settings.hit_lines.players[0];

            ctx.setRef(SettingsWindow.name);
            ctx.itemClick("**/Hit Lines", imgui.ImGuiMouseButton_Left, 0);
            ctx.setRef(ctx.windowInfo("layout/content", 0).Window);
            ctx.itemClick("Player Separation", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("//$FOCUSED/Same Settings", imgui.ImGuiMouseButton_Left, 0);

            ctx.itemUncheck("Enabled", 0);
            try testing.expectEqual(false, current.enabled);
            ctx.itemClick("Enabled/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.enabled, current.enabled);
            ctx.itemCheck("Enabled", 0);
            try testing.expectEqual(true, current.enabled);

            ctx.itemInputValueFloat("Lingering Duration", 123);
            try testing.expectEqual(123, current.duration);
            ctx.itemClick("Lingering Duration/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.duration, current.duration);

            ctx.itemUncheck("Normal Hit Lines/Enabled", 0);
            try testing.expectEqual(false, current.normal.enabled);
            ctx.itemClick("Normal Hit Lines/Enabled/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.normal.enabled, current.normal.enabled);
            ctx.itemCheck("Normal Hit Lines/Enabled", 0);
            try testing.expectEqual(true, current.normal.enabled);

            ctx.itemInputValueFloat("Normal Hit Lines/Fill/Colors/High/##X", 153);
            try testing.expectEqual(0.6, current.normal.fill.colors.get(.high).x());
            ctx.itemClick("Normal Hit Lines/Fill/Colors/High/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.normal.fill.colors.get(.high), current.normal.fill.colors.get(.high));

            ctx.itemInputValueFloat("Normal Hit Lines/Fill/Thickness", 123);
            try testing.expectEqual(123, current.normal.fill.thickness);
            ctx.itemClick("Normal Hit Lines/Fill/Thickness/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.normal.fill.thickness, current.normal.fill.thickness);

            ctx.itemInputValueFloat("Normal Hit Lines/Outline/Colors/Mid/##Y", 153);
            try testing.expectEqual(0.6, current.normal.outline.colors.get(.mid).y());
            ctx.itemClick("Normal Hit Lines/Outline/Colors/Mid/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.normal.outline.colors.get(.mid), current.normal.outline.colors.get(.mid));

            ctx.itemInputValueFloat("Normal Hit Lines/Outline/Thickness", 123);
            try testing.expectEqual(123, current.normal.outline.thickness);
            ctx.itemClick("Normal Hit Lines/Outline/Thickness/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.normal.outline.thickness, current.normal.outline.thickness);

            ctx.itemInputValueFloat("Inactive Or Crushed Hit Lines/Fill/Colors/Low/##Z", 153);
            try testing.expectEqual(0.6, current.inactive_or_crushed.fill.colors.get(.low).z());
            ctx.itemClick("Inactive Or Crushed Hit Lines/Fill/Colors/Low/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(
                default.inactive_or_crushed.fill.colors.get(.low),
                current.inactive_or_crushed.fill.colors.get(.low),
            );

            ctx.itemInputValueFloat("Inactive Or Crushed Hit Lines/Fill/Thickness", 123);
            try testing.expectEqual(123, current.inactive_or_crushed.fill.thickness);
            ctx.itemClick("Inactive Or Crushed Hit Lines/Fill/Thickness/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(
                default.inactive_or_crushed.fill.thickness,
                current.inactive_or_crushed.fill.thickness,
            );

            ctx.itemInputValueFloat("Inactive Or Crushed Hit Lines/Outline/Colors/Special Low/##W", 153);
            try testing.expectEqual(0.6, current.inactive_or_crushed.outline.colors.get(.special_low).w());
            ctx.itemClick(
                "Inactive Or Crushed Hit Lines/Outline/Colors/Special Low/###default",
                imgui.ImGuiMouseButton_Left,
                0,
            );
            try testing.expectEqual(
                default.inactive_or_crushed.outline.colors.get(.special_low),
                current.inactive_or_crushed.outline.colors.get(.special_low),
            );

            ctx.itemInputValueFloat("Inactive Or Crushed Hit Lines/Outline/Thickness", 123);
            try testing.expectEqual(123, current.inactive_or_crushed.outline.thickness);
            ctx.itemClick("Inactive Or Crushed Hit Lines/Outline/Thickness/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(
                default.inactive_or_crushed.outline.thickness,
                current.inactive_or_crushed.outline.thickness,
            );
        }
    };
    Test.window = .init(testing.allocator);
    defer Test.window.deinit();
    Test.window.is_open = true;
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "hurt cylinders settings should function correctly" {
    const Test = struct {
        const default_settings = model.Settings{};
        var settings = default_settings;
        var window: SettingsWindow = undefined;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(&testing_base_dir, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const current = &settings.hurt_cylinders.players[0];
            const default = &default_settings.hurt_cylinders.players[0];

            ctx.setRef(SettingsWindow.name);
            ctx.itemClick("**/Hurt Cylinders", imgui.ImGuiMouseButton_Left, 0);
            ctx.setRef(ctx.windowInfo("layout/content", 0).Window);
            ctx.itemClick("Player Separation", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("//$FOCUSED/Same Settings", imgui.ImGuiMouseButton_Left, 0);

            ctx.itemUncheck("Enabled", 0);
            try testing.expectEqual(false, current.enabled);
            ctx.itemClick("Enabled/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.enabled, current.enabled);
            ctx.itemCheck("Enabled", 0);
            try testing.expectEqual(true, current.enabled);

            ctx.itemUncheck("Normal Hurt Cylinders/Enabled", 0);
            try testing.expectEqual(false, current.normal.enabled);
            ctx.itemClick("Normal Hurt Cylinders/Enabled/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.normal.enabled, current.normal.enabled);
            ctx.itemCheck("Normal Hurt Cylinders/Enabled", 0);
            try testing.expectEqual(true, current.normal.enabled);

            ctx.itemInputValueFloat("Normal Hurt Cylinders/Normal/Color/##X", 153);
            try testing.expectEqual(0.6, current.normal.normal.color.x());
            ctx.itemClick("Normal Hurt Cylinders/Normal/Color/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.normal.normal.color, current.normal.normal.color);

            ctx.itemInputValueFloat("Normal Hurt Cylinders/High Crushing/Thickness", 123);
            try testing.expectEqual(123, current.normal.high_crushing.thickness);
            ctx.itemClick("Normal Hurt Cylinders/High Crushing/Thickness/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.normal.high_crushing.thickness, current.normal.high_crushing.thickness);

            ctx.itemUncheck("Power-Crushing Hurt Cylinders/Enabled", 0);
            try testing.expectEqual(false, current.power_crushing.enabled);
            ctx.itemClick("Power-Crushing Hurt Cylinders/Enabled/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.power_crushing.enabled, current.power_crushing.enabled);
            ctx.itemCheck("Power-Crushing Hurt Cylinders/Enabled", 0);
            try testing.expectEqual(true, current.power_crushing.enabled);

            ctx.itemInputValueFloat("Power-Crushing Hurt Cylinders/Low Crushing/Color/##Y", 153);
            try testing.expectEqual(0.6, current.power_crushing.low_crushing.color.y());
            ctx.itemClick("Power-Crushing Hurt Cylinders/Low Crushing/Color/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(
                default.power_crushing.low_crushing.color,
                current.power_crushing.low_crushing.color,
            );

            ctx.itemInputValueFloat("Power-Crushing Hurt Cylinders/Invincible/Thickness", 123);
            try testing.expectEqual(123, current.power_crushing.invincible.thickness);
            ctx.itemClick("Power-Crushing Hurt Cylinders/Invincible/Thickness/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(
                default.power_crushing.invincible.thickness,
                current.power_crushing.invincible.thickness,
            );

            ctx.itemUncheck("Connected (Hit) Hurt Cylinders/Enabled", 0);
            try testing.expectEqual(false, current.connected.enabled);
            ctx.itemClick("Connected (Hit) Hurt Cylinders/Enabled/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.connected.enabled, current.connected.enabled);
            ctx.itemCheck("Connected (Hit) Hurt Cylinders/Enabled", 0);
            try testing.expectEqual(true, current.connected.enabled);

            ctx.itemInputValueFloat("Connected (Hit) Hurt Cylinders/Color/##Z", 153);
            try testing.expectEqual(0.6, current.connected.color.z());
            ctx.itemClick("Connected (Hit) Hurt Cylinders/Color/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.connected.color, current.connected.color);

            ctx.itemInputValueFloat("Connected (Hit) Hurt Cylinders/Thickness", 123);
            try testing.expectEqual(123, current.connected.thickness);
            ctx.itemClick("Connected (Hit) Hurt Cylinders/Thickness/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.connected.thickness, current.connected.thickness);

            ctx.itemInputValueFloat("Connected (Hit) Hurt Cylinders/Duration", 123);
            try testing.expectEqual(123, current.connected.duration);
            ctx.itemClick("Connected (Hit) Hurt Cylinders/Duration/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.connected.duration, current.connected.duration);

            ctx.itemUncheck("Lingering Hurt Cylinders/Enabled", 0);
            try testing.expectEqual(false, current.lingering.enabled);
            ctx.itemClick("Lingering Hurt Cylinders/Enabled/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.lingering.enabled, current.lingering.enabled);
            ctx.itemCheck("Lingering Hurt Cylinders/Enabled", 0);
            try testing.expectEqual(true, current.lingering.enabled);

            ctx.itemInputValueFloat("Lingering Hurt Cylinders/Color/##W", 153);
            try testing.expectEqual(0.6, current.lingering.color.w());
            ctx.itemClick("Lingering Hurt Cylinders/Color/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.lingering.color, current.lingering.color);

            ctx.itemInputValueFloat("Lingering Hurt Cylinders/Thickness", 123);
            try testing.expectEqual(123, current.lingering.thickness);
            ctx.itemClick("Lingering Hurt Cylinders/Thickness/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.lingering.thickness, current.lingering.thickness);

            ctx.itemInputValueFloat("Lingering Hurt Cylinders/Duration", 123);
            try testing.expectEqual(123, current.lingering.duration);
            ctx.itemClick("Lingering Hurt Cylinders/Duration/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.lingering.duration, current.lingering.duration);
        }
    };
    Test.window = .init(testing.allocator);
    defer Test.window.deinit();
    Test.window.is_open = true;
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "collision spheres settings should function correctly" {
    const Test = struct {
        const default_settings = model.Settings{};
        var settings = default_settings;
        var window: SettingsWindow = undefined;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(&testing_base_dir, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const current = &settings.collision_spheres.players[0];
            const default = &default_settings.collision_spheres.players[0];

            ctx.setRef(SettingsWindow.name);
            ctx.itemClick("**/Collision Spheres", imgui.ImGuiMouseButton_Left, 0);
            ctx.setRef(ctx.windowInfo("layout/content", 0).Window);
            ctx.itemClick("Player Separation", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("//$FOCUSED/Same Settings", imgui.ImGuiMouseButton_Left, 0);

            ctx.itemUncheck("Enabled", 0);
            try testing.expectEqual(false, current.enabled);
            ctx.itemClick("Enabled/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.enabled, current.enabled);
            ctx.itemCheck("Enabled", 0);
            try testing.expectEqual(true, current.enabled);

            ctx.itemInputValueFloat("Color/##X", 153);
            try testing.expectEqual(0.6, current.color.x());
            ctx.itemClick("Color/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.color, current.color);

            ctx.itemInputValueFloat("Thickness", 123);
            try testing.expectEqual(123, current.thickness);
            ctx.itemClick("Thickness/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.thickness, current.thickness);
        }
    };
    Test.window = .init(testing.allocator);
    defer Test.window.deinit();
    Test.window.is_open = true;
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "skeletons settings should function correctly" {
    const Test = struct {
        const default_settings = model.Settings{};
        var settings = default_settings;
        var window: SettingsWindow = undefined;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(&testing_base_dir, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const current = &settings.skeletons.players[0];
            const default = &default_settings.skeletons.players[0];

            ctx.setRef(SettingsWindow.name);
            ctx.itemClick("**/Skeletons", imgui.ImGuiMouseButton_Left, 0);
            ctx.setRef(ctx.windowInfo("layout/content", 0).Window);
            ctx.itemClick("Player Separation", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("//$FOCUSED/Same Settings", imgui.ImGuiMouseButton_Left, 0);

            ctx.itemUncheck("Enabled", 0);
            try testing.expectEqual(false, current.enabled);
            ctx.itemClick("Enabled/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.enabled, current.enabled);
            ctx.itemCheck("Enabled", 0);
            try testing.expectEqual(true, current.enabled);

            ctx.itemInputValueFloat("Colors/Not Blocking/##X", 153);
            try testing.expectEqual(0.6, current.colors.get(.not_blocking).x());
            ctx.itemClick("Colors/Not Blocking/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.colors.get(.not_blocking), current.colors.get(.not_blocking));

            ctx.itemInputValueFloat("Colors/Neutral Blocking Mids/##Y", 153);
            try testing.expectEqual(0.6, current.colors.get(.neutral_blocking_mids).y());
            ctx.itemClick("Colors/Neutral Blocking Mids/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(
                default.colors.get(.neutral_blocking_mids),
                current.colors.get(.neutral_blocking_mids),
            );

            ctx.itemInputValueFloat("Colors/Fully Blocking Mids/##Z", 153);
            try testing.expectEqual(0.6, current.colors.get(.fully_blocking_mids).z());
            ctx.itemClick("Colors/Fully Blocking Mids/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.colors.get(.fully_blocking_mids), current.colors.get(.fully_blocking_mids));

            ctx.itemInputValueFloat("Colors/Neutral Blocking Lows/##W", 153);
            try testing.expectEqual(0.6, current.colors.get(.neutral_blocking_lows).w());
            ctx.itemClick("Colors/Neutral Blocking Lows/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(
                default.colors.get(.neutral_blocking_lows),
                current.colors.get(.neutral_blocking_lows),
            );

            ctx.itemInputValueFloat("Colors/Fully Blocking Lows/##X", 153);
            try testing.expectEqual(0.6, current.colors.get(.fully_blocking_lows).x());
            ctx.itemClick("Colors/Fully Blocking Lows/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.colors.get(.fully_blocking_lows), current.colors.get(.fully_blocking_lows));

            ctx.itemInputValueFloat("Thickness", 123);
            try testing.expectEqual(123, current.thickness);
            ctx.itemClick("Thickness/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.thickness, current.thickness);

            ctx.itemInputValueFloat("Can't Move Alpha", 0.123);
            try testing.expectEqual(0.123, current.cant_move_alpha);
            ctx.itemClick("Can't Move Alpha/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.cant_move_alpha, current.cant_move_alpha);
        }
    };
    Test.window = .init(testing.allocator);
    defer Test.window.deinit();
    Test.window.is_open = true;
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "forward directions settings should function correctly" {
    const Test = struct {
        const default_settings = model.Settings{};
        var settings = default_settings;
        var window: SettingsWindow = undefined;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(&testing_base_dir, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const current = &settings.forward_directions.players[0];
            const default = &default_settings.forward_directions.players[0];

            ctx.setRef(SettingsWindow.name);
            ctx.itemClick("**/Forward Directions", imgui.ImGuiMouseButton_Left, 0);
            ctx.setRef(ctx.windowInfo("layout/content", 0).Window);
            ctx.itemClick("Player Separation", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("//$FOCUSED/Same Settings", imgui.ImGuiMouseButton_Left, 0);

            ctx.itemUncheck("Enabled", 0);
            try testing.expectEqual(false, current.enabled);
            ctx.itemClick("Enabled/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.enabled, current.enabled);
            ctx.itemCheck("Enabled", 0);
            try testing.expectEqual(true, current.enabled);

            ctx.itemInputValueFloat("Color/##X", 153);
            try testing.expectEqual(0.6, current.color.x());
            ctx.itemClick("Color/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.color, current.color);

            ctx.itemInputValueFloat("Length", 123);
            try testing.expectEqual(123, current.length);
            ctx.itemClick("Length/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.length, current.length);

            ctx.itemInputValueFloat("Thickness", 123);
            try testing.expectEqual(123, current.thickness);
            ctx.itemClick("Thickness/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.thickness, current.thickness);
        }
    };
    Test.window = .init(testing.allocator);
    defer Test.window.deinit();
    Test.window.is_open = true;
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "floor settings should function correctly" {
    const Test = struct {
        const default_settings = model.Settings{};
        var settings = default_settings;
        var window: SettingsWindow = undefined;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(&testing_base_dir, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const current = &settings.floor;
            const default = &default_settings.floor;

            ctx.setRef(SettingsWindow.name);
            ctx.itemClick("**/Floor", imgui.ImGuiMouseButton_Left, 0);
            ctx.setRef(ctx.windowInfo("layout/content", 0).Window);

            ctx.itemUncheck("Enabled", 0);
            try testing.expectEqual(false, current.enabled);
            ctx.itemClick("Enabled/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.enabled, current.enabled);
            ctx.itemCheck("Enabled", 0);
            try testing.expectEqual(true, current.enabled);

            ctx.itemInputValueFloat("Color/##X", 153);
            try testing.expectEqual(0.6, current.color.x());
            ctx.itemClick("Color/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.color, current.color);

            ctx.itemInputValueFloat("Thickness", 123);
            try testing.expectEqual(123, current.thickness);
            ctx.itemClick("Thickness/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.thickness, current.thickness);
        }
    };
    Test.window = .init(testing.allocator);
    defer Test.window.deinit();
    Test.window.is_open = true;
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "ingame camera settings should function correctly" {
    const Test = struct {
        const default_settings = model.Settings{};
        var settings = default_settings;
        var window: SettingsWindow = undefined;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(&testing_base_dir, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const current = &settings.ingame_camera;
            const default = &default_settings.ingame_camera;

            ctx.setRef(SettingsWindow.name);
            ctx.itemClick("**/Ingame Camera", imgui.ImGuiMouseButton_Left, 0);
            ctx.setRef(ctx.windowInfo("layout/content", 0).Window);

            ctx.itemUncheck("Enabled", 0);
            try testing.expectEqual(false, current.enabled);
            ctx.itemClick("Enabled/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.enabled, current.enabled);
            ctx.itemCheck("Enabled", 0);
            try testing.expectEqual(true, current.enabled);

            ctx.itemInputValueFloat("Color/##X", 153);
            try testing.expectEqual(0.6, current.color.x());
            ctx.itemClick("Color/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.color, current.color);

            ctx.itemInputValueFloat("Length", 123);
            try testing.expectEqual(123, current.length);
            ctx.itemClick("Length/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.length, current.length);

            ctx.itemInputValueFloat("Thickness", 123);
            try testing.expectEqual(123, current.thickness);
            ctx.itemClick("Thickness/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.thickness, current.thickness);
        }
    };
    Test.window = .init(testing.allocator);
    defer Test.window.deinit();
    Test.window.is_open = true;
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "measure tool settings should function correctly" {
    const Test = struct {
        const default_settings = model.Settings{};
        var settings = default_settings;
        var window: SettingsWindow = undefined;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(&testing_base_dir, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const current = &settings.measure_tool;
            const default = &default_settings.measure_tool;

            ctx.setRef(SettingsWindow.name);
            ctx.itemClick("**/Measure Tool", imgui.ImGuiMouseButton_Left, 0);
            ctx.setRef(ctx.windowInfo("layout/content", 0).Window);

            ctx.itemInputValueFloat("Line/Color/##X", 153);
            try testing.expectEqual(0.6, current.line.color.x());
            ctx.itemClick("Line/Color/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.line.color, current.line.color);

            ctx.itemInputValueFloat("Line/Thickness", 123);
            try testing.expectEqual(123, current.line.thickness);
            ctx.itemClick("Line/Thickness/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.line.thickness, current.line.thickness);

            ctx.itemInputValueFloat("Normal Point/Color/##Y", 153);
            try testing.expectEqual(0.6, current.normal_point.color.y());
            ctx.itemClick("Normal Point/Color/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.normal_point.color, current.normal_point.color);

            ctx.itemInputValueFloat("Normal Point/Thickness", 123);
            try testing.expectEqual(123, current.normal_point.thickness);
            ctx.itemClick("Normal Point/Thickness/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.normal_point.thickness, current.normal_point.thickness);

            ctx.itemInputValueFloat("Hovered Point/Color/##Z", 153);
            try testing.expectEqual(0.6, current.hovered_point.color.z());
            ctx.itemClick("Hovered Point/Color/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.hovered_point.color, current.hovered_point.color);

            ctx.itemInputValueFloat("Hovered Point/Thickness", 123);
            try testing.expectEqual(123, current.hovered_point.thickness);
            ctx.itemClick("Hovered Point/Thickness/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.hovered_point.thickness, current.hovered_point.thickness);

            ctx.itemInputValueFloat("Text Color/##W", 153);
            try testing.expectEqual(0.6, current.text_color.w());
            ctx.itemClick("Text Color/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.text_color, current.text_color);

            ctx.itemInputValueFloat("Hover Distance", 123);
            try testing.expectEqual(123, current.hover_distance);
            ctx.itemClick("Hover Distance/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.hover_distance, current.hover_distance);
        }
    };
    Test.window = .init(testing.allocator);
    defer Test.window.deinit();
    Test.window.is_open = true;
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "details table settings should function correctly" {
    const Test = struct {
        const default_settings = model.Settings{};
        var settings = default_settings;
        var window: SettingsWindow = undefined;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(&testing_base_dir, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const current = &settings.details;
            const default = &default_settings.details;

            ctx.setRef(SettingsWindow.name);
            ctx.itemClick("**/Details Table", imgui.ImGuiMouseButton_Left, 0);
            ctx.setRef(ctx.windowInfo("layout/content", 0).Window);

            ctx.itemClick("Column 1", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("//$FOCUSED/Left Player", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(.left_player, current.column_1);
            ctx.itemClick("Column 1/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.column_1, current.column_1);

            ctx.itemClick("Column 2", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("//$FOCUSED/Right Player", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(.right_player, current.column_2);
            ctx.itemClick("Column 2/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.column_2, current.column_2);

            ctx.itemInputValueFloat("Fade Out Duration", 123);
            try testing.expectEqual(123, current.fade_out_duration);
            ctx.itemClick("Fade Out Duration/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.fade_out_duration, current.fade_out_duration);

            ctx.itemInputValueFloat("Fade Out Alpha", 123);
            try testing.expectEqual(123, current.fade_out_alpha);
            ctx.itemClick("Fade Out Alpha/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.fade_out_alpha, current.fade_out_alpha);

            ctx.itemUncheck("Enabled Rows/Animation Frame", 0);
            try testing.expectEqual(false, current.rows_enabled.animation_frame);
            ctx.itemClick("Enabled Rows/Animation Frame/###default", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(default.rows_enabled.animation_frame, current.rows_enabled.animation_frame);
            ctx.itemCheck("Enabled Rows/Animation Frame", 0);
            try testing.expectEqual(true, current.rows_enabled.animation_frame);

            ctx.itemClick("Enabled Rows/Disable All", imgui.ImGuiMouseButton_Left, 0);
            inline for (@typeInfo(model.DetailsSettings.RowsEnabled).@"struct".fields) |*field| {
                try testing.expectEqual(false, @field(current.rows_enabled, field.name));
            }
            ctx.itemClick("Enabled Rows/Enable All", imgui.ImGuiMouseButton_Left, 0);
            inline for (@typeInfo(model.DetailsSettings.RowsEnabled).@"struct".fields) |*field| {
                try testing.expectEqual(true, @field(current.rows_enabled, field.name));
            }
        }
    };
    Test.window = .init(testing.allocator);
    defer Test.window.deinit();
    Test.window.is_open = true;
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
