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
    controls_height: f32 = 0,
    grid_divide: imgui.ImVec2 = .{ .x = 0.5, .y = 0.5 },

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
            self.drawViews();
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

    fn drawViews(self: *Self) void {
        var content_size: imgui.ImVec2 = undefined;
        imgui.igGetContentRegionAvail(&content_size);
        const border_size = imgui.igGetStyle().*.ChildBorderSize;

        const available_size = imgui.ImVec2{
            .x = content_size.x - (3.0 * border_size),
            .y = content_size.y - (3.0 * border_size),
        };
        const size_1 = imgui.ImVec2{
            .x = std.math.round(self.grid_divide.x * available_size.x),
            .y = std.math.round(self.grid_divide.y * available_size.y),
        };
        const size_2 = imgui.ImVec2{
            .x = available_size.x - size_1.x,
            .y = available_size.y - size_1.y,
        };

        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_ItemSpacing, .{ .x = 0, .y = 0 });
        defer imgui.igPopStyleVar(1);

        if (self.grid_divide.x > 0.0001 and self.grid_divide.y > 0.0001) {
            imgui.igSetCursorPos(.{ .x = border_size, .y = border_size });
            if (imgui.igBeginChild_Str("front", size_1, 0, 0)) {
                imgui.igText("Front View");
            }
            imgui.igEndChild();
        }

        if (self.grid_divide.x < 0.9999 and self.grid_divide.y > 0.0001) {
            imgui.igSetCursorPos(.{ .x = size_1.x + (2.0 * border_size), .y = border_size });
            if (imgui.igBeginChild_Str("side", .{ .x = size_2.x, .y = size_1.y }, 0, 0)) {
                imgui.igText("Side View");
            }
            imgui.igEndChild();
        }

        if (self.grid_divide.x > 0.0001 and self.grid_divide.y < 0.9999) {
            imgui.igSetCursorPos(.{ .x = border_size, .y = size_1.y + (2.0 * border_size) });
            if (imgui.igBeginChild_Str("top", .{ .x = size_1.x, .y = size_2.y }, 0, 0)) {
                imgui.igText("Top View");
            }
            imgui.igEndChild();
        }

        if (self.grid_divide.x < 0.9999 and self.grid_divide.y < 0.9999) {
            imgui.igSetCursorPos(.{ .x = size_1.x + (2.0 * border_size), .y = size_1.y + (2.0 * border_size) });
            if (imgui.igBeginChild_Str("details", size_2, 0, 0)) {
                imgui.igText("Details");
            }
            imgui.igEndChild();
        }

        imgui.igSetCursorPos(.{ .x = 0, .y = 0 });
        self.drawViewBorders();
    }

    fn drawViewBorders(self: *Self) void {
        const color = imgui.igGetColorU32_Vec4(imgui.igGetStyleColorVec4(imgui.ImGuiCol_Separator).*);
        const hovered_color = imgui.igGetColorU32_Vec4(imgui.igGetStyleColorVec4(imgui.ImGuiCol_SeparatorHovered).*);
        const active_color = imgui.igGetColorU32_Vec4(imgui.igGetStyleColorVec4(imgui.ImGuiCol_SeparatorActive).*);
        const border_size = imgui.igGetStyle().*.ChildBorderSize;
        const extra_padding = 4.0;
        const hit_box_size = border_size + (2.0 * extra_padding);

        var cursor: imgui.ImVec2 = undefined;
        imgui.igGetCursorScreenPos(&cursor);
        var content_size: imgui.ImVec2 = undefined;
        imgui.igGetContentRegionAvail(&content_size);

        const available_size = imgui.ImVec2{
            .x = content_size.x - (2.0 * border_size),
            .y = content_size.y - (2.0 * border_size),
        };
        const start = imgui.ImVec2{
            .x = cursor.x,
            .y = cursor.y,
        };
        const center = imgui.ImVec2{
            .x = std.math.round(cursor.x + border_size + (self.grid_divide.x * available_size.x)),
            .y = std.math.round(cursor.y + border_size + (self.grid_divide.y * available_size.y)),
        };
        const end = imgui.ImVec2{
            .x = cursor.x + content_size.x - border_size,
            .y = cursor.y + content_size.y - border_size,
        };

        var x_color = color;
        imgui.igSetCursorScreenPos(.{ .x = center.x - extra_padding, .y = start.y });
        if (imgui.igBeginChild_Str("x-handle", .{ .x = hit_box_size, .y = content_size.y }, 0, 0)) {
            _ = imgui.igInvisibleButton("button", .{ .x = hit_box_size, .y = content_size.y }, 0);
            if (imgui.igIsItemHovered(0)) {
                x_color = hovered_color;
                imgui.igSetMouseCursor(imgui.ImGuiMouseCursor_ResizeEW);
            }
            if (imgui.igIsItemActive()) {
                x_color = active_color;
                self.grid_divide.x += imgui.igGetIO().*.MouseDelta.x / available_size.x;
                self.grid_divide.x = std.math.clamp(self.grid_divide.x, 0.0, 1.0);
            }
        }
        imgui.igEndChild();

        var y_color = color;
        imgui.igSetCursorScreenPos(.{ .x = start.x, .y = center.y - extra_padding });
        if (imgui.igBeginChild_Str("y-handle", .{ .x = content_size.x, .y = hit_box_size }, 0, 0)) {
            _ = imgui.igInvisibleButton("button", .{ .x = content_size.x, .y = hit_box_size }, 0);
            if (imgui.igIsItemHovered(0)) {
                y_color = hovered_color;
                imgui.igSetMouseCursor(imgui.ImGuiMouseCursor_ResizeNS);
            }
            if (imgui.igIsItemActive()) {
                y_color = active_color;
                self.grid_divide.y += imgui.igGetIO().*.MouseDelta.y / available_size.y;
                self.grid_divide.y = std.math.clamp(self.grid_divide.y, 0.0, 1.0);
            }
        }
        imgui.igEndChild();

        imgui.igSetCursorScreenPos(.{ .x = center.x - extra_padding, .y = center.y - extra_padding });
        if (imgui.igBeginChild_Str("center-handle", .{ .x = hit_box_size, .y = hit_box_size }, 0, 0)) {
            _ = imgui.igInvisibleButton("button", .{ .x = hit_box_size, .y = hit_box_size }, 0);
            if (imgui.igIsItemHovered(0)) {
                x_color = hovered_color;
                y_color = hovered_color;
                imgui.igSetMouseCursor(imgui.ImGuiMouseCursor_ResizeAll);
            }
            if (imgui.igIsItemActive()) {
                x_color = active_color;
                y_color = active_color;
                self.grid_divide.x += imgui.igGetIO().*.MouseDelta.x / available_size.x;
                self.grid_divide.y += imgui.igGetIO().*.MouseDelta.y / available_size.y;
                self.grid_divide.x = std.math.clamp(self.grid_divide.x, 0.0, 1.0);
                self.grid_divide.y = std.math.clamp(self.grid_divide.y, 0.0, 1.0);
            }
        }
        imgui.igEndChild();

        const draw_list = imgui.igGetWindowDrawList();
        imgui.ImDrawList_AddLine(draw_list, .{ .x = center.x, .y = start.y }, .{ .x = center.x, .y = end.y }, x_color, border_size);
        imgui.ImDrawList_AddLine(draw_list, .{ .x = start.x, .y = center.y }, .{ .x = end.x, .y = center.y }, y_color, border_size);
        imgui.ImDrawList_AddLine(draw_list, start, .{ .x = end.x, .y = start.y }, color, border_size);
        imgui.ImDrawList_AddLine(draw_list, start, .{ .x = start.x, .y = end.y }, color, border_size);
        imgui.ImDrawList_AddLine(draw_list, end, .{ .x = end.x, .y = start.y }, color, border_size);
        imgui.ImDrawList_AddLine(draw_list, end, .{ .x = start.x, .y = end.y }, color, border_size);
    }

    fn drawControls(_: *Self) void {
        imgui.igText("Controls");
    }
};
