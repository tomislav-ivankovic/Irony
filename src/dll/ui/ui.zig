const std = @import("std");
const imgui = @import("imgui");
const build_info = @import("build_info");
const dll = @import("../../dll.zig");
const sdk = @import("../../sdk/root.zig");
const core = @import("../core/root.zig");
const game = @import("../game/root.zig");
const model = @import("../model/root.zig");
const rendering = @import("../rendering/root.zig");
const ui = @import("root.zig");

pub const Ui = struct {
    is_first_draw: bool,
    is_open: bool,
    main_window: ui.MainWindow,
    tai_window: ui.TaiWindow,
    settings_window: ui.SettingsWindow,
    logs_window: ui.LogsWindow,
    game_memory_window: ui.GameMemoryWindow,
    frame_window: ui.FrameWindow,
    about_window: ui.AboutWindow(.{}),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .is_first_draw = true,
            .is_open = false,
            .main_window = .{},
            .tai_window = .init(allocator),
            .settings_window = .init(allocator),
            .logs_window = .{},
            .game_memory_window = .{},
            .frame_window = .{},
            .about_window = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.settings_window.deinit();
        self.tai_window.deinit();
    }

    pub fn processFrame(self: *Self, settings: *const model.Settings, frame: *const model.Frame) void {
        self.main_window.processFrame(settings, frame);
    }

    pub fn update(self: *Self, io: std.Io, delta_time: f32, controller: *core.Controller) void {
        sdk.ui.toasts.update(delta_time);
        self.main_window.update(io, delta_time, controller);
    }

    pub fn draw(
        self: *Self,
        io: std.Io,
        file_dialog_context: *imgui.ImGuiFileDialog,
        settings_maybe: ?*model.Settings,
        game_memory_maybe: ?*const game.Memory(build_info.game),
        controller: *core.Controller,
        tai: *core.ToolAssistedInput,
        tai_coordinator: *core.TaiRecordingCoordinator,
        latest_version: ui.LatestVersion,
        memory_usage: usize,
    ) void {
        const defaults = (model.Settings{}).general.ui;

        const font_size = if (settings_maybe) |s| s.general.ui.font_size else defaults.font_size;
        imgui.igPushFont(null, font_size);
        defer imgui.igPopFont();

        const background_color = if (settings_maybe) |s| s.general.ui.background_color else defaults.background_color;
        imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_WindowBg, background_color.toImVec());
        defer imgui.igPopStyleColor(1);

        sdk.ui.toasts.draw();

        const game_memory = game_memory_maybe orelse {
            ui.drawMessageWindow("Loading", "Searching for memory addresses and offsets...", .center, true);
            return;
        };
        const settings = settings_maybe orelse {
            ui.drawMessageWindow("Loading", "Loading settings...", .center, true);
            return;
        };
        if (controller.mode == .record) {
            ui.drawMessageWindow("Recording", "⏺ Recording...", .top, false);
        }
        if (controller.mode == .save) {
            ui.drawMessageWindow("Saving", "Saving the recording...", .top, true);
        }
        if (controller.mode == .load) {
            ui.drawMessageWindow("Loading", "Loading the recording...", .top, true);
        }

        self.handleFirstDraw();
        self.handleOpenKey();
        self.main_window.handleKeybinds(controller);
        ui.TaiWindow.handleKeybinds(tai);

        if (!self.is_open) {
            return;
        }
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_WindowMinSize, .{ .x = 240, .y = 200 });
        defer imgui.igPopStyleVar(1);

        self.main_window.draw(
            self,
            io,
            file_dialog_context,
            controller,
            settings,
            latest_version,
            memory_usage,
        );
        self.tai_window.draw(controller, tai, tai_coordinator);
        self.settings_window.draw(io, settings);
        self.logs_window.draw(dll.buffer_logger);
        self.game_memory_window.draw(build_info.game, game_memory);
        self.frame_window.draw(controller.getCurrentFrame());
        self.about_window.draw(io);
    }

    pub fn draw3D(
        self: *const Self,
        shape_renderer: *rendering.Shapes,
        settings: *const model.Settings,
        controller: *const core.Controller,
    ) void {
        if (!settings.general.rendering_3d.enabled) {
            return;
        }
        self.main_window.draw3D(shape_renderer, settings, controller);
    }

    fn handleFirstDraw(self: *Self) void {
        if (!self.is_first_draw) {
            return;
        }
        sdk.ui.toasts.send(.success, null, "{s} initialized. Press [Tab] to open the UI.", .{build_info.display_name});
        self.is_first_draw = false;
    }

    fn handleOpenKey(self: *Self) void {
        _ = imgui.igShortcut_Nil(imgui.ImGuiKey_Tab, imgui.ImGuiInputFlags_RouteGlobal);
        _ = imgui.igShortcut_Nil(imgui.ImGuiMod_Shift | imgui.ImGuiKey_Tab, imgui.ImGuiInputFlags_RouteGlobal);
        const tab_pressed = imgui.igShortcut_Nil(imgui.ImGuiKey_Tab, imgui.ImGuiInputFlags_RouteAlways);
        const shift_tab_pressed = imgui.igShortcut_Nil(
            imgui.ImGuiMod_Shift | imgui.ImGuiKey_Tab,
            imgui.ImGuiInputFlags_RouteAlways,
        );
        if (!tab_pressed and !shift_tab_pressed) {
            return;
        }
        self.is_open = !self.is_open;
    }
};
