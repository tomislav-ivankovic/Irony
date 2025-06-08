const std = @import("std");
const imgui = @import("imgui");
const dll = @import("../dll.zig");
const components = @import("root.zig");
const ui = @import("../ui/root.zig");
const game = @import("../game/root.zig");

pub const MainWindow = struct {
    is_first_draw: bool = true,
    is_open: bool = false,
    logs_window: components.LogsWindow = .{},
    game_memory_window: components.GameMemoryWindow = .{},

    const Self = @This();

    pub fn draw(self: *Self, game_memory: *const game.Memory) void {
        self.handleFirstDraw();
        self.handleOpenKey();
        if (!self.is_open) {
            return;
        }
        self.drawChildWindows(game_memory);
        const render_content = imgui.igBegin("Irony", &self.is_open, imgui.ImGuiWindowFlags_MenuBar);
        defer imgui.igEnd();
        if (!render_content) {
            return;
        }
        self.drawMenuBar();
    }

    fn handleFirstDraw(self: *Self) void {
        if (!self.is_first_draw) {
            return;
        }
        ui.toasts.send(.success, null, "Irony initialized. Press F2 to open the Irony window.", .{});
        self.is_first_draw = false;
    }

    fn handleOpenKey(self: *Self) void {
        if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F2, false)) {
            self.is_open = !self.is_open;
        }
    }

    fn drawChildWindows(self: *Self, game_memory: *const game.Memory) void {
        self.logs_window.draw(dll.buffer_logger);
        self.game_memory_window.draw(game_memory);
    }

    fn drawMenuBar(self: *Self) void {
        if (!imgui.igBeginMenuBar()) {
            return;
        }
        defer imgui.igEndMenuBar();

        if (imgui.igBeginMenu("Help", true)) {
            defer imgui.igEndMenu();
            if (imgui.igMenuItem_Bool("Logs", null, false, true)) {
                self.logs_window.is_open = true;
                imgui.igSetWindowFocus_Str(components.LogsWindow.name);
            }
            if (imgui.igMenuItem_Bool("Game Memory", null, false, true)) {
                self.game_memory_window.is_open = true;
                imgui.igSetWindowFocus_Str(components.GameMemoryWindow.name);
            }
        }
    }
};
