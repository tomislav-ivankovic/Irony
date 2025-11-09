const std = @import("std");
const imgui = @import("imgui");
const build_info = @import("build_info");
const sdk = @import("../../sdk/root.zig");
const core = @import("../core/root.zig");
const model = @import("../model/root.zig");
const ui = @import("root.zig");

pub const MainWindow = struct {
    quadrant_layout: ui.QuadrantLayout = .{},
    view: ui.View = .{},
    controls: ui.Controls(.{}) = .{},
    file_menu: ui.FileMenu = .{},
    controls_height: f32 = 0,

    const Self = @This();
    const QuadrantContext = struct {
        self: *Self,
        settings: *const model.Settings,
        frame: ?*const model.Frame,
    };

    pub fn processFrame(self: *Self, settings: *const model.Settings, frame: *const model.Frame) void {
        self.view.processFrame(settings, frame);
    }

    pub fn update(self: *Self, delta_time: f32, controller: *core.Controller) void {
        self.view.update(delta_time);
        self.file_menu.update(controller);
    }

    pub fn handleKeybinds(self: *Self, controller: *core.Controller) void {
        self.controls.handleKeybinds(controller);
    }

    pub fn draw(
        self: *Self,
        ui_instance: *ui.Ui,
        base_dir: *const sdk.misc.BaseDir,
        file_dialog_context: *imgui.ImGuiFileDialog,
        controller: *core.Controller,
        settings: *model.Settings,
    ) void {
        const display_size = imgui.igGetIO_Nil().*.DisplaySize;
        imgui.igSetNextWindowPos(
            .{ .x = 0.5 * display_size.x, .y = 0.5 * display_size.y },
            imgui.ImGuiCond_FirstUseEver,
            .{ .x = 0.5, .y = 0.5 },
        );
        imgui.igSetNextWindowSize(.{ .x = 960, .y = 640 }, imgui.ImGuiCond_FirstUseEver);

        var title_buffer: [260]u8 = undefined;
        const asterisk = if (controller.contains_unsaved_changes) "*" else "";
        const file_name = if (self.file_menu.getFilePath()) |path| sdk.os.pathToFileName(path) else "Untitled";
        const title = std.fmt.bufPrintZ(
            &title_buffer,
            build_info.display_name ++ " - {s}{s}###main_window",
            .{ asterisk, file_name },
        ) catch build_info.display_name ++ "###main_window";

        const render_content = imgui.igBegin(title, &ui_instance.is_open, imgui.ImGuiWindowFlags_MenuBar);
        defer imgui.igEnd();
        if (!render_content) {
            return;
        }

        self.drawMenuBar(ui_instance, base_dir, file_dialog_context, controller);
        if (imgui.igBeginChild_Str("views", .{ .x = 0, .y = -self.controls_height }, 0, 0)) {
            const context = QuadrantContext{
                .self = self,
                .settings = settings,
                .frame = controller.getCurrentFrame(),
            };
            self.quadrant_layout.draw(context, &.{
                .top_left = .{ .id = "front", .content = drawFrontView, .window_flags = imgui.ImGuiWindowFlags_NoMove },
                .top_right = .{ .id = "side", .content = drawSideView, .window_flags = imgui.ImGuiWindowFlags_NoMove },
                .bottom_left = .{ .id = "top", .content = drawTopView, .window_flags = imgui.ImGuiWindowFlags_NoMove },
                .bottom_right = .{ .id = "details", .content = drawDetails },
            });
        }
        imgui.igEndChild();
        if (imgui.igBeginChild_Str("controls", .{ .x = 0, .y = 0 }, 0, 0)) {
            const controls_start_y = imgui.igGetCursorPosY();
            self.controls.draw(controller);
            self.controls_height = imgui.igGetCursorPosY() - controls_start_y;
        }
        imgui.igEndChild();
    }

    fn drawMenuBar(
        self: *Self,
        ui_instance: *ui.Ui,
        base_dir: *const sdk.misc.BaseDir,
        file_dialog_context: *imgui.ImGuiFileDialog,
        controller: *core.Controller,
    ) void {
        if (!imgui.igBeginMenuBar()) {
            return;
        }
        defer imgui.igEndMenuBar();

        self.file_menu.draw(base_dir, file_dialog_context, controller, &ui_instance.is_open);
        self.view.camera.drawMenuBar();

        if (imgui.igMenuItem_Bool(ui.SettingsWindow.name, null, false, true)) {
            ui_instance.settings_window.is_open = !ui_instance.settings_window.is_open;
            if (ui_instance.settings_window.is_open) {
                imgui.igSetWindowFocus_Str(ui.SettingsWindow.name);
            }
        }

        if (imgui.igBeginMenu("Help", true)) {
            defer imgui.igEndMenu();
            if (imgui.igMenuItem_Bool(ui.LogsWindow.name, null, false, true)) {
                ui_instance.logs_window.is_open = true;
                imgui.igSetWindowFocus_Str(ui.LogsWindow.name);
            }
            if (imgui.igMenuItem_Bool(ui.GameMemoryWindow.name, null, false, true)) {
                ui_instance.game_memory_window.is_open = true;
                imgui.igSetWindowFocus_Str(ui.GameMemoryWindow.name);
            }
            if (imgui.igMenuItem_Bool(ui.FrameWindow.name, null, false, true)) {
                ui_instance.frame_window.is_open = true;
                imgui.igSetWindowFocus_Str(ui.FrameWindow.name);
            }
        }
    }

    fn drawFrontView(context: QuadrantContext) void {
        const frame = context.frame orelse return;
        context.self.view.draw(context.settings, frame, .front);
    }

    fn drawSideView(context: QuadrantContext) void {
        const frame = context.frame orelse return;
        context.self.view.draw(context.settings, frame, .side);
    }

    fn drawTopView(context: QuadrantContext) void {
        const frame = context.frame orelse return;
        context.self.view.draw(context.settings, frame, .top);
    }

    fn drawDetails(context: QuadrantContext) void {
        const frame = context.frame orelse return;
        ui.drawDetails(frame, context.settings.misc.details_columns);
    }
};
