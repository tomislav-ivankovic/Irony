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
    quadrant_layout: components.QuadrantLayout = .{},
    view: components.View = .{},
    controls_height: f32 = 0,

    const Self = @This();

    pub fn draw(self: *Self, game_memory: *const game.Memory) void {
        self.handleFirstDraw();
        self.handleOpenKey();
        if (!self.is_open) {
            return;
        }
        self.drawSecondaryWindows(game_memory);
        const render_content = imgui.igBegin("Irony", &self.is_open, imgui.ImGuiWindowFlags_MenuBar);
        defer imgui.igEnd();
        if (!render_content) {
            return;
        }
        self.drawMenuBar();
        if (imgui.igBeginChild_Str("views", .{ .x = 0, .y = -self.controls_height }, 0, 0)) {
            self.drawQuadrants(game_memory);
        }
        imgui.igEndChild();
        if (imgui.igBeginChild_Str("controls", .{ .x = 0, .y = 0 }, 0, 0)) {
            const controls_start_y = imgui.igGetCursorPosY();
            self.drawControls();
            self.controls_height = imgui.igGetCursorPosY() - controls_start_y;
        }
        imgui.igEndChild();
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

    fn drawSecondaryWindows(self: *Self, game_memory: *const game.Memory) void {
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

    const QuadrantContext = struct {
        self: *Self,
        player_1: ?*const components.View.Player,
        player_2: ?*const components.View.Player,
    };

    fn drawQuadrants(self: *Self, game_memory: *const game.Memory) void {
        const player_1 = if (game_memory.player_1.takePartialCopy(components.View.Player)) |p| &p else null;
        const player_2 = if (game_memory.player_2.takePartialCopy(components.View.Player)) |p| &p else null;
        const context = QuadrantContext{ .self = self, .player_1 = player_1, .player_2 = player_2 };
        self.quadrant_layout.draw(context, &.{
            .top_left = .{ .id = "front", .content = drawFrontView },
            .top_right = .{ .id = "side", .content = drawSideView },
            .bottom_left = .{ .id = "top", .content = drawTopView },
            .bottom_right = .{ .id = "details", .content = drawDetails },
        });
    }

    fn drawFrontView(context: QuadrantContext) void {
        const self = context.self;
        if (context.player_1) |player_1| {
            if (context.player_2) |player_2| {
                self.view.draw(.front, player_1, player_2);
            }
        }
    }

    fn drawSideView(context: QuadrantContext) void {
        const self = context.self;
        if (context.player_1) |player_1| {
            if (context.player_2) |player_2| {
                self.view.draw(.side, player_1, player_2);
            }
        }
    }

    fn drawTopView(context: QuadrantContext) void {
        const self = context.self;
        if (context.player_1) |player_1| {
            if (context.player_2) |player_2| {
                self.view.draw(.top, player_1, player_2);
            }
        }
    }

    fn drawDetails(_: QuadrantContext) void {
        imgui.igText("Details");
    }

    fn drawControls(_: *Self) void {
        imgui.igText("Controls");
    }
};
