const std = @import("std");
const build_info = @import("build_info");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const game = @import("../game/root.zig");
const ui = @import("root.zig");

pub const GameMemoryWindow = struct {
    is_open: bool = false,

    const Self = @This();
    pub const name = "Game Memory";

    pub fn draw(self: *Self, comptime game_id: build_info.Game, game_memory: *const game.Memory(game_id)) void {
        if (!self.is_open) {
            return;
        }

        const display_size = imgui.igGetIO_Nil().*.DisplaySize;
        imgui.igSetNextWindowPos(
            .{ .x = 0.5 * display_size.x, .y = 0.5 * display_size.y },
            imgui.ImGuiCond_FirstUseEver,
            .{ .x = 0.5, .y = 0.5 },
        );
        imgui.igSetNextWindowSize(.{ .x = 600, .y = 600 }, imgui.ImGuiCond_FirstUseEver);

        const render_content = imgui.igBegin(name, &self.is_open, imgui.ImGuiWindowFlags_HorizontalScrollbar);
        defer imgui.igEnd();
        if (!render_content) {
            return;
        }

        inline for (@typeInfo(game.Memory(game_id)).@"struct".fields) |*field| {
            ui.drawData(field.name, &@field(game_memory, field.name));
        }
        // if (game_memory.player_1.findBaseAddress()) |address| {
        //     const array: *const [3000]u32 = @ptrFromInt(address);
        //     ui.drawData("player_1_array", array);
        // }
        // if (game_memory.player_2.findBaseAddress()) |address| {
        //     const array: *const [3000]u32 = @ptrFromInt(address);
        //     ui.drawData("player_2_array", array);
        // }
    }
};

const testing = std.testing;

test "should not draw anything when window is closed" {
    const Test = struct {
        var window: GameMemoryWindow = .{ .is_open = false };
        const memory = std.mem.zeroes(game.Memory(.t8));

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(.t8, &memory);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try ctx.expectItemNotExists("//" ++ GameMemoryWindow.name);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw game memory struct fields when window is opened in T7" {
    const Test = struct {
        var window: GameMemoryWindow = .{ .is_open = true };
        const memory = std.mem.zeroes(game.Memory(.t7));

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(.t7, &memory);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef(GameMemoryWindow.name);
            inline for (@typeInfo(game.Memory(.t7)).@"struct".fields) |*field| {
                try ctx.expectItemExists(field.name);
            }
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw game memory struct fields when window is opened in T8" {
    const Test = struct {
        var window: GameMemoryWindow = .{ .is_open = true };
        const memory = std.mem.zeroes(game.Memory(.t8));

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(.t8, &memory);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef(GameMemoryWindow.name);
            inline for (@typeInfo(game.Memory(.t8)).@"struct".fields) |*field| {
                try ctx.expectItemExists(field.name);
            }
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
