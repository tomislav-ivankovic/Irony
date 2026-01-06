const std = @import("std");
const ui = @import("root.zig");
const imgui = @import("imgui");

pub const ControlHints = struct {
    state: std.EnumArray(ui.ViewDirection, AnimationState) = .initFill(.{}),

    const Self = @This();
    const AnimationState = struct {
        current: f32 = 0.0,
        target: f32 = 0.0,
        speed: f32 = std.math.ln2,
    };

    pub fn update(self: *Self, delta_time: f32) void {
        for (&self.state.values) |*state| {
            const exp = std.math.exp(-delta_time * state.speed);
            state.current = state.target + ((state.current - state.target) * exp);
        }
    }

    pub fn draw(self: *Self, direction: ui.ViewDirection) void {
        const state = self.state.getPtr(direction);
        const window_hovered = imgui.igIsWindowHovered(imgui.ImGuiHoveredFlags_ChildWindows);
        state.target = if (window_hovered) 0.5 else 0.0;
        state.speed = if (window_hovered) 3 * std.math.ln2 else 9 * std.math.ln2;
        var available_size: imgui.ImVec2 = undefined;
        imgui.igGetContentRegionAvail(&available_size);
        if (available_size.y < imgui.igGetFontSize()) {
            return; // Prevents crash from happening when user makes the child window too small.
        }
        const color = imgui.ImVec4{
            .x = 1,
            .y = 1,
            .z = 1,
            .w = state.current,
        };
        imgui.igTextColored(color, "⬅, ");
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Left Mouse Button: Measure Distance");
        }
        imgui.igSameLine(0, -1);
        imgui.igTextColored(color, "➡, ");
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Right Mouse Button: Translate View");
        }
        imgui.igSameLine(0, -1);
        imgui.igTextColored(color, "🆑 + ➡, ");
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Control + Right Mouse Button: Rotate View");
        }
        imgui.igSameLine(0, -1);
        imgui.igTextColored(color, "↕ ");
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Scroll: Zoom\nMiddle Mouse Button: Reset View Offset");
        }
    }
};
