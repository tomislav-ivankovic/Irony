const std = @import("std");
const builtin = @import("builtin");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("root.zig");

pub const FrameWindow = struct {
    is_open: bool = false,

    const Self = @This();
    pub const name = "Captured Frame";

    pub fn draw(self: *Self, frame: ?*const model.Frame) void {
        if (!self.is_open) {
            return;
        }
        const render_content = imgui.igBegin(name, &self.is_open, imgui.ImGuiWindowFlags_HorizontalScrollbar);
        defer imgui.igEnd();
        if (!render_content) {
            return;
        }
        if (frame) |f| {
            inline for (@typeInfo(model.Frame).@"struct".fields) |*field| {
                ui.drawData(field.name, &@field(f, field.name));
            }
        } else {
            imgui.igText("No frame captured.");
            if (builtin.is_test) {
                var rect: imgui.ImRect = undefined;
                imgui.igGetItemRectMin(&rect.Min);
                imgui.igGetItemRectMax(&rect.Max);
                imgui.teItemAdd(imgui.igGetCurrentContext(), imgui.igGetID_Str("No frame captured."), &rect, null);
            }
        }
    }
};

const testing = std.testing;

test "should not draw anything when window is closed" {
    const Test = struct {
        var window: FrameWindow = .{ .is_open = false };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(&.{});
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try ctx.expectItemNotExists("//" ++ FrameWindow.name);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw no frame captured when window is opened and frame is null" {
    const Test = struct {
        var window: FrameWindow = .{ .is_open = true };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(null);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef(FrameWindow.name);
            try ctx.expectItemExists("No frame captured.");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw frame struct fields when window is opened and frame is not null" {
    const Test = struct {
        var window: FrameWindow = .{ .is_open = true };
        const frame = model.Frame{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(&frame);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef(FrameWindow.name);
            inline for (@typeInfo(model.Frame).@"struct".fields) |*field| {
                try ctx.expectItemExists(field.name);
            }
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
