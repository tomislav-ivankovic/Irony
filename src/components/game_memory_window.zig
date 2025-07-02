const std = @import("std");
const imgui = @import("imgui");
const game = @import("../game/root.zig");
const components = @import("root.zig");

pub const GameMemoryWindow = struct {
    is_open: bool = false,

    const Self = @This();
    pub const name = "Game Memory";

    pub fn draw(self: *Self, game_memory: *const game.Memory) void {
        if (!self.is_open) {
            return;
        }
        const render_content = imgui.igBegin(name, &self.is_open, imgui.ImGuiWindowFlags_HorizontalScrollbar);
        defer imgui.igEnd();
        if (!render_content) {
            return;
        }
        components.drawData("game_memory", game_memory);
        // if (game_memory.player_1.findBaseAddress()) |address| {
        //     const array: *const [3000]f32 = @ptrFromInt(address);
        //     components.drawData("player_1_array", array);
        // }
        // if (game_memory.player_2.findBaseAddress()) |address| {
        //     const array: *const [3000]f32 = @ptrFromInt(address);
        //     components.drawData("player_2_array", array);
        // }
    }
};
