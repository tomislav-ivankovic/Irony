const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");

pub const QuadrantLayout = struct {
    division: imgui.ImVec2 = .{ .x = 0.5, .y = 0.5 },

    const Self = @This();
    pub fn Quadrant(comptime Context: type) type {
        return struct {
            id: [:0]const u8,
            content: *const fn (context: Context) void,
            child_flags: imgui.ImGuiChildFlags = 0,
            window_flags: imgui.ImGuiWindowFlags = 0,
        };
    }
    pub fn Quadrants(comptime Context: type) type {
        return struct {
            top_left: Quadrant(Context),
            top_right: Quadrant(Context),
            bottom_left: Quadrant(Context),
            bottom_right: Quadrant(Context),
        };
    }

    pub fn draw(self: *Self, context: anytype, quadrants: *const Quadrants(@TypeOf(context))) void {
        var cursor: imgui.ImVec2 = undefined;
        imgui.igGetCursorPos(&cursor);
        self.drawQuadrants(context, quadrants);
        imgui.igSetCursorPos(cursor);
        self.drawBorders();
    }

    fn drawQuadrants(self: *const Self, context: anytype, quadrants: *const Quadrants(@TypeOf(context))) void {
        var content_size: imgui.ImVec2 = undefined;
        imgui.igGetContentRegionAvail(&content_size);
        const border_size = imgui.igGetStyle().*.ChildBorderSize;

        const available_size = imgui.ImVec2{
            .x = content_size.x - (3.0 * border_size),
            .y = content_size.y - (3.0 * border_size),
        };
        const size_1 = imgui.ImVec2{
            .x = std.math.round(self.division.x * available_size.x),
            .y = std.math.round(self.division.y * available_size.y),
        };
        const size_2 = imgui.ImVec2{
            .x = available_size.x - size_1.x,
            .y = available_size.y - size_1.y,
        };

        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_ItemSpacing, .{ .x = 0, .y = 0 });
        defer imgui.igPopStyleVar(1);

        if (self.division.x > 0.0001 and self.division.y > 0.0001) {
            imgui.igSetCursorPos(.{ .x = border_size, .y = border_size });
            if (imgui.igBeginChild_Str(
                quadrants.top_left.id,
                size_1,
                quadrants.top_left.child_flags,
                quadrants.top_left.window_flags,
            )) {
                quadrants.top_left.content(context);
            }
            imgui.igEndChild();
        }

        if (self.division.x < 0.9999 and self.division.y > 0.0001) {
            imgui.igSetCursorPos(.{ .x = size_1.x + (2.0 * border_size), .y = border_size });
            if (imgui.igBeginChild_Str(
                quadrants.top_right.id,
                .{ .x = size_2.x, .y = size_1.y },
                quadrants.top_right.child_flags,
                quadrants.top_right.window_flags,
            )) {
                quadrants.top_right.content(context);
            }
            imgui.igEndChild();
        }

        if (self.division.x > 0.0001 and self.division.y < 0.9999) {
            imgui.igSetCursorPos(.{ .x = border_size, .y = size_1.y + (2.0 * border_size) });
            if (imgui.igBeginChild_Str(
                quadrants.bottom_left.id,
                .{ .x = size_1.x, .y = size_2.y },
                quadrants.bottom_left.child_flags,
                quadrants.bottom_left.window_flags,
            )) {
                quadrants.bottom_left.content(context);
            }
            imgui.igEndChild();
        }

        if (self.division.x < 0.9999 and self.division.y < 0.9999) {
            imgui.igSetCursorPos(.{ .x = size_1.x + (2.0 * border_size), .y = size_1.y + (2.0 * border_size) });
            if (imgui.igBeginChild_Str(
                quadrants.bottom_right.id,
                size_2,
                quadrants.bottom_right.child_flags,
                quadrants.bottom_right.window_flags,
            )) {
                quadrants.bottom_right.content(context);
            }
            imgui.igEndChild();
        }
    }

    fn drawBorders(self: *Self) void {
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
            .x = std.math.round(cursor.x + border_size + (self.division.x * available_size.x)),
            .y = std.math.round(cursor.y + border_size + (self.division.y * available_size.y)),
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
                self.division.x += imgui.igGetIO_Nil().*.MouseDelta.x / available_size.x;
                self.division.x = std.math.clamp(self.division.x, 0.0, 1.0);
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
                self.division.y += imgui.igGetIO_Nil().*.MouseDelta.y / available_size.y;
                self.division.y = std.math.clamp(self.division.y, 0.0, 1.0);
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
                self.division.x += imgui.igGetIO_Nil().*.MouseDelta.x / available_size.x;
                self.division.y += imgui.igGetIO_Nil().*.MouseDelta.y / available_size.y;
                self.division.x = std.math.clamp(self.division.x, 0.0, 1.0);
                self.division.y = std.math.clamp(self.division.y, 0.0, 1.0);
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

        imgui.igSetCursorScreenPos(.{ .x = cursor.x + content_size.x, .y = cursor.y + content_size.y });
    }
};

const testing = std.testing;

test "should render correct content under correct id" {
    const Test = struct {
        var layout = QuadrantLayout{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            layout.draw({}, &.{
                .top_left = .{ .id = "top-left", .content = drawTopLeft },
                .top_right = .{ .id = "top-right", .content = drawTopRight },
                .bottom_left = .{ .id = "bottom-left", .content = drawBottomLeft },
                .bottom_right = .{ .id = "bottom-right", .content = drawBottomRight },
            });
        }

        fn drawTopLeft(_: void) void {
            _ = imgui.igButton("Top Left", .{});
        }

        fn drawTopRight(_: void) void {
            _ = imgui.igButton("Top Right", .{});
        }

        fn drawBottomLeft(_: void) void {
            _ = imgui.igButton("Bottom Left", .{});
        }

        fn drawBottomRight(_: void) void {
            _ = imgui.igButton("Bottom Right", .{});
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef(ctx.windowInfo("//Window/top-left", 0).ID);
            try ctx.expectItemExists("Top Left");
            ctx.setRef(ctx.windowInfo("//Window/top-right", 0).ID);
            try ctx.expectItemExists("Top Right");
            ctx.setRef(ctx.windowInfo("//Window/bottom-left", 0).ID);
            try ctx.expectItemExists("Bottom Left");
            ctx.setRef(ctx.windowInfo("//Window/bottom-right", 0).ID);
            try ctx.expectItemExists("Bottom Right");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should pass the context to content functions" {
    const Test = struct {
        var layout = QuadrantLayout{};
        var top_left_context: ?i32 = null;
        var top_right_context: ?i32 = null;
        var bottom_left_context: ?i32 = null;
        var bottom_right_context: ?i32 = null;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            const context: i32 = 123;
            layout.draw(context, &.{
                .top_left = .{ .id = "top-left", .content = drawTopLeft },
                .top_right = .{ .id = "top-right", .content = drawTopRight },
                .bottom_left = .{ .id = "bottom-left", .content = drawBottomLeft },
                .bottom_right = .{ .id = "bottom-right", .content = drawBottomRight },
            });
        }

        fn drawTopLeft(context: i32) void {
            top_left_context = context;
        }

        fn drawTopRight(context: i32) void {
            top_right_context = context;
        }

        fn drawBottomLeft(context: i32) void {
            bottom_left_context = context;
        }

        fn drawBottomRight(context: i32) void {
            bottom_right_context = context;
        }

        fn testFunction(_: sdk.ui.TestContext) !void {
            try testing.expectEqual(123, top_left_context);
            try testing.expectEqual(123, top_right_context);
            try testing.expectEqual(123, bottom_left_context);
            try testing.expectEqual(123, bottom_right_context);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should resize child windows correctly when mouse dragging the handles" {
    const Sizes = struct {
        top_left: imgui.ImVec2 = .{},
        top_right: imgui.ImVec2 = .{},
        bottom_left: imgui.ImVec2 = .{},
        bottom_right: imgui.ImVec2 = .{},

        const Self = @This();

        fn subtract(self: *const Self, other: *const Self) Self {
            return .{
                .top_left = .{
                    .x = self.top_left.x - other.top_left.x,
                    .y = self.top_left.y - other.top_left.y,
                },
                .top_right = .{
                    .x = self.top_right.x - other.top_right.x,
                    .y = self.top_right.y - other.top_right.y,
                },
                .bottom_left = .{
                    .x = self.bottom_left.x - other.bottom_left.x,
                    .y = self.bottom_left.y - other.bottom_left.y,
                },
                .bottom_right = .{
                    .x = self.bottom_right.x - other.bottom_right.x,
                    .y = self.bottom_right.y - other.bottom_right.y,
                },
            };
        }
    };

    const Test = struct {
        var layout = QuadrantLayout{
            // Makes clicking on the center of axes handles not click the center handle.
            .division = .{ .x = 0.25, .y = 0.75 },
        };
        var current = Sizes{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            layout.draw({}, &.{
                .top_left = .{ .id = "top-left", .content = drawTopLeft },
                .top_right = .{ .id = "top-right", .content = drawTopRight },
                .bottom_left = .{ .id = "bottom-left", .content = drawBottomLeft },
                .bottom_right = .{ .id = "bottom-right", .content = drawBottomRight },
            });
        }

        fn drawTopLeft(_: void) void {
            imgui.igGetContentRegionAvail(&current.top_left);
        }

        fn drawTopRight(_: void) void {
            imgui.igGetContentRegionAvail(&current.top_right);
        }

        fn drawBottomLeft(_: void) void {
            imgui.igGetContentRegionAvail(&current.bottom_left);
        }

        fn drawBottomRight(_: void) void {
            imgui.igGetContentRegionAvail(&current.bottom_right);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            var last = Sizes{};
            var delta = Sizes{};
            ctx.setRef("Window");

            last = current;
            ctx.itemDragWithDelta("x-handle", .{ .x = 10, .y = 20 });
            delta = current.subtract(&last);

            try testing.expectApproxEqAbs(10, delta.top_left.x, 1);
            try testing.expectApproxEqAbs(0, delta.top_left.y, 1);
            try testing.expectApproxEqAbs(-10, delta.top_right.x, 1);
            try testing.expectApproxEqAbs(0, delta.top_right.y, 1);
            try testing.expectApproxEqAbs(10, delta.bottom_left.x, 1);
            try testing.expectApproxEqAbs(0, delta.bottom_left.y, 1);
            try testing.expectApproxEqAbs(-10, delta.bottom_right.x, 1);
            try testing.expectApproxEqAbs(0, delta.bottom_right.y, 1);

            last = current;
            ctx.itemDragWithDelta("x-handle", .{ .x = -10, .y = -20 });
            delta = current.subtract(&last);

            try testing.expectApproxEqAbs(-10, delta.top_left.x, 1);
            try testing.expectApproxEqAbs(0, delta.top_left.y, 1);
            try testing.expectApproxEqAbs(10, delta.top_right.x, 1);
            try testing.expectApproxEqAbs(0, delta.top_right.y, 1);
            try testing.expectApproxEqAbs(-10, delta.bottom_left.x, 1);
            try testing.expectApproxEqAbs(0, delta.bottom_left.y, 1);
            try testing.expectApproxEqAbs(10, delta.bottom_right.x, 1);
            try testing.expectApproxEqAbs(0, delta.bottom_right.y, 1);

            last = current;
            ctx.itemDragWithDelta("y-handle", .{ .x = 10, .y = 20 });
            delta = current.subtract(&last);

            try testing.expectApproxEqAbs(0, delta.top_left.x, 1);
            try testing.expectApproxEqAbs(20, delta.top_left.y, 1);
            try testing.expectApproxEqAbs(0, delta.top_right.x, 1);
            try testing.expectApproxEqAbs(20, delta.top_right.y, 1);
            try testing.expectApproxEqAbs(0, delta.bottom_left.x, 1);
            try testing.expectApproxEqAbs(-20, delta.bottom_left.y, 1);
            try testing.expectApproxEqAbs(0, delta.bottom_right.x, 1);
            try testing.expectApproxEqAbs(-20, delta.bottom_right.y, 1);

            last = current;
            ctx.itemDragWithDelta("y-handle", .{ .x = -10, .y = -20 });
            delta = current.subtract(&last);

            try testing.expectApproxEqAbs(0, delta.top_left.x, 1);
            try testing.expectApproxEqAbs(-20, delta.top_left.y, 1);
            try testing.expectApproxEqAbs(0, delta.top_right.x, 1);
            try testing.expectApproxEqAbs(-20, delta.top_right.y, 1);
            try testing.expectApproxEqAbs(0, delta.bottom_left.x, 1);
            try testing.expectApproxEqAbs(20, delta.bottom_left.y, 1);
            try testing.expectApproxEqAbs(0, delta.bottom_right.x, 1);
            try testing.expectApproxEqAbs(20, delta.bottom_right.y, 1);

            last = current;
            ctx.itemDragWithDelta("center-handle", .{ .x = 10, .y = 20 });
            delta = current.subtract(&last);

            try testing.expectApproxEqAbs(10, delta.top_left.x, 1);
            try testing.expectApproxEqAbs(20, delta.top_left.y, 1);
            try testing.expectApproxEqAbs(-10, delta.top_right.x, 1);
            try testing.expectApproxEqAbs(20, delta.top_right.y, 1);
            try testing.expectApproxEqAbs(10, delta.bottom_left.x, 1);
            try testing.expectApproxEqAbs(-20, delta.bottom_left.y, 1);
            try testing.expectApproxEqAbs(-10, delta.bottom_right.x, 1);
            try testing.expectApproxEqAbs(-20, delta.bottom_right.y, 1);

            last = current;
            ctx.itemDragWithDelta("center-handle", .{ .x = -10, .y = -20 });
            delta = current.subtract(&last);

            try testing.expectApproxEqAbs(-10, delta.top_left.x, 1);
            try testing.expectApproxEqAbs(-20, delta.top_left.y, 1);
            try testing.expectApproxEqAbs(10, delta.top_right.x, 1);
            try testing.expectApproxEqAbs(-20, delta.top_right.y, 1);
            try testing.expectApproxEqAbs(-10, delta.bottom_left.x, 1);
            try testing.expectApproxEqAbs(20, delta.bottom_left.y, 1);
            try testing.expectApproxEqAbs(10, delta.bottom_right.x, 1);
            try testing.expectApproxEqAbs(20, delta.bottom_right.y, 1);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
