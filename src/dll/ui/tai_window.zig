const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const core = @import("../core/root.zig");
const ui = @import("root.zig");

pub const TaiWindow = struct {
    is_open: bool,
    table: ui.TaiTable(.{}),
    controls: ui.TaiControls,
    controls_height: f32 = 0,

    const Self = @This();

    pub const name = "Tool Assisted Input";

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .is_open = false,
            .table = .init(allocator),
            .controls = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.table.deinit();
    }

    pub fn handleKeybinds(tai: *core.ToolAssistedInput) void {
        ui.TaiControls.handleKeybinds(tai);
    }

    pub fn draw(
        self: *Self,
        controller: *core.Controller,
        tai: *core.ToolAssistedInput,
        coordinator: *core.TaiRecordingCoordinator,
    ) void {
        const display_size = imgui.igGetIO_Nil().*.DisplaySize;
        imgui.igSetNextWindowPos(
            .{ .x = 0.5 * display_size.x, .y = 0.5 * display_size.y },
            imgui.ImGuiCond_FirstUseEver,
            .{ .x = 0.5, .y = 0.5 },
        );
        imgui.igSetNextWindowSize(.{ .x = 520, .y = 640 }, imgui.ImGuiCond_FirstUseEver);

        if (!self.is_open) {
            return;
        }
        const render_content = imgui.igBegin(name, &self.is_open, 0);
        defer imgui.igEnd();
        if (!render_content) {
            return;
        }

        var available_size: imgui.ImVec2 = undefined;
        imgui.igGetContentRegionAvail(&available_size);
        const table_height = available_size.y - self.controls_height;

        if (imgui.igBeginChild_Str("table", .{ .y = table_height }, 0, imgui.ImGuiWindowFlags_NoMove)) {
            self.table.draw(tai, controller, &self.controls.enable_player_1, &self.controls.enable_player_2);
        }
        imgui.igEndChild();
        if (imgui.igBeginChild_Str("controls", .{}, 0, 0)) {
            const start_y = imgui.igGetCursorPosY();
            self.controls.draw(tai, coordinator, &self.table.editor.selection);
            self.controls_height = imgui.igGetCursorPosY() - start_y;
        }
        imgui.igEndChild();
    }
};
