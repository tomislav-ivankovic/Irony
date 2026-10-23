const std = @import("std");
const builtin = @import("builtin");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("../ui/root.zig");

pub const MeasureTool = struct {
    state: State = .idle,

    const Self = @This();
    const State = union(enum) {
        idle: void,
        moving: Moving,
        completed: Completed,

        const Moving = struct {
            line: sdk.math.LineSegment3,
            moving_point: PointId,
        };
        const Completed = struct {
            line: sdk.math.LineSegment3,
            hovered_point: ?PointId,
        };
    };
    const PointId = enum {
        point_1,
        point_2,
    };

    pub fn processInput(
        self: *Self,
        settings: *const model.MeasureToolSettings,
        matrix: sdk.math.Mat4,
        inverse_matrix: sdk.math.Mat4,
    ) void {
        if (!imgui.igIsWindowHovered(imgui.ImGuiHoveredFlags_ChildWindows)) {
            return;
        }
        const screen_mouse = sdk.math.Vec2.fromImVec(imgui.igGetIO_Nil().*.MousePos);
        const is_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_MouseLeft, false);
        const is_released = imgui.igIsKeyReleased_Nil(imgui.ImGuiKey_MouseLeft);
        switch (self.state) {
            .idle => {
                if (is_pressed) {
                    const world_mouse = screen_mouse.extend(0.5).pointTransform(inverse_matrix);
                    self.state = .{ .moving = .{
                        .line = .{ .point_1 = world_mouse, .point_2 = world_mouse },
                        .moving_point = .point_2,
                    } };
                }
            },
            .moving => |*state| {
                switch (state.moving_point) {
                    .point_1 => {
                        const screen_z = state.line.point_1.pointTransform(matrix).z();
                        state.line.point_1 = screen_mouse.extend(screen_z).pointTransform(inverse_matrix);
                    },
                    .point_2 => {
                        const screen_z = state.line.point_2.pointTransform(matrix).z();
                        state.line.point_2 = screen_mouse.extend(screen_z).pointTransform(inverse_matrix);
                    },
                }
                if (is_released) {
                    self.state = .{ .completed = .{
                        .line = state.line,
                        .hovered_point = state.moving_point,
                    } };
                }
            },
            .completed => |*state| {
                const screen_point_1 = state.line.point_1.pointTransform(matrix).swizzle("xy");
                const screen_point_2 = state.line.point_2.pointTransform(matrix).swizzle("xy");
                const point_1_distance = screen_point_1.distanceTo(screen_mouse);
                const point_2_distance = screen_point_2.distanceTo(screen_mouse);
                const hover_distance = settings.hover_distance;
                if (point_1_distance <= hover_distance or point_2_distance <= hover_distance) {
                    if (point_1_distance <= point_2_distance) {
                        state.hovered_point = .point_1;
                    } else {
                        state.hovered_point = .point_2;
                    }
                } else {
                    state.hovered_point = null;
                }
                if (is_pressed) {
                    if (state.hovered_point) |point_id| {
                        self.state = .{ .moving = .{
                            .line = state.line,
                            .moving_point = point_id,
                        } };
                    } else {
                        self.state = .idle;
                    }
                }
            },
        }
    }

    pub fn draw(self: *const Self, shapes: *const ui.Shapes, settings: *const model.MeasureToolSettings) void {
        const line, const hovered_point = switch (self.state) {
            .idle => return,
            .moving => |*state| .{ state.line, state.moving_point },
            .completed => |*state| .{ state.line, state.hovered_point },
        };
        const hovered = &settings.hovered_point;
        const normal = &settings.normal_point;
        const point_1_color = if (hovered_point == .point_1) hovered.color else normal.color;
        const point_2_color = if (hovered_point == .point_2) hovered.color else normal.color;
        const point_1_thickness = if (hovered_point == .point_1) hovered.thickness else normal.thickness;
        const point_2_thickness = if (hovered_point == .point_2) hovered.thickness else normal.thickness;
        if (shapes.* == ._2d and hovered_point != null) {
            imgui.igSetMouseCursor(imgui.ImGuiMouseCursor_Hand);
        }
        shapes.drawLine(line, settings.line.color, settings.line.thickness, 0);
        shapes.drawPoint(line.point_1, point_1_color, point_1_thickness);
        shapes.drawPoint(line.point_2, point_2_color, point_2_thickness);
        if (shapes.* == ._2d) {
            drawLineText(line, settings.text_color, shapes._2d.matrix);
        }
    }

    fn drawLineText(line: sdk.math.LineSegment3, color: sdk.math.Vec4, matrix: sdk.math.Mat4) void {
        const point_1 = line.point_1.pointTransform(matrix).swizzle("xy");
        const point_2 = line.point_2.pointTransform(matrix).swizzle("xy");
        var difference = point_2.subtract(point_1);
        if (difference.lengthSquared() < 1.0) {
            return;
        }
        if (difference.y() < 0) {
            difference = difference.negate();
        }

        const distance = line.point_1.distanceTo(line.point_2);
        var buffer: [32]u8 = undefined;
        const text = std.fmt.bufPrintSentinel(&buffer, "{d:.2} cm", .{distance}, 0) catch "error";
        var text_size: sdk.math.Vec2 = undefined;
        imgui.igCalcTextSize(text_size.asImVec(), text, null, false, -1);

        const midpoint = point_1.add(point_2).scale(0.5);
        const away_from_line_spacing = difference.normalize().rotateZ(-0.5 * std.math.pi).scale(0.5 * text_size.y());
        const horizontal_factor = @abs(difference.x()) / (@abs(difference.x()) + @abs(difference.y()));
        const text_offset = sdk.math.Vec2.fromArray(.{
            -0.5 * text_size.x() * horizontal_factor * horizontal_factor * horizontal_factor,
            -0.5 * text_size.y(),
        });
        const position = midpoint.add(away_from_line_spacing).add(text_offset);

        const draw_list = imgui.igGetWindowDrawList();
        const u32_color = imgui.igGetColorU32_Vec4(color.toImVec());
        imgui.ImDrawList_AddText_Vec2(draw_list, position.toImVec(), u32_color, text, null);
        if (builtin.is_test) {
            var rect: imgui.ImRect = undefined;
            imgui.igGetItemRectMin(&rect.Min);
            imgui.igGetItemRectMax(&rect.Max);
            imgui.teItemAdd(imgui.igGetCurrentContext(), imgui.igGetID_Str(text), &rect, null);
        }
    }
};

const testing = std.testing;

test "should draw correct shapes and text as the user inputs what to measure" {
    const Test = struct {
        var measure_tool: MeasureTool = .{};
        const settings = model.MeasureToolSettings{
            .line = .{ .color = .fill(0.1), .thickness = 1 },
            .normal_point = .{ .color = .fill(0.2), .thickness = 2 },
            .hovered_point = .{ .color = .fill(0.3), .thickness = 3 },
            .text_color = .fill(0.4),
            .hover_distance = 0.1,
        };
        var window_pos: sdk.math.Vec2 = undefined;
        var window_size: sdk.math.Vec2 = undefined;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            ui.testing_shapes.clear();
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_NoMove);
            defer imgui.igEnd();
            imgui.igGetCursorScreenPos(window_pos.asImVec());
            imgui.igGetContentRegionAvail(window_size.asImVec());
            const matrix = sdk.math.Mat4.identity
                .lookAt(.fromArray(.{ 5, 0, 2.5 }), .fromArray(.{ 6, 0, 2.5 }), .plus_z)
                .orthographic(-10, 10, -5, 5, -1, 1)
                .scale(.fromArray(.{ 0.5 * window_size.x(), -0.5 * window_size.y(), 1 }))
                .translate(window_pos.add(window_size.scale(0.5)).extend(0));
            const inverse_matrix = matrix.inverse() orelse @panic("Failed to calculate inverse matrix.");
            measure_tool.processInput(&settings, matrix, inverse_matrix);
            const shapes = ui.Shapes{ ._2d = .{
                .direction = .front,
                .matrix = matrix,
                .inverse_matrix = inverse_matrix,
            } };
            measure_tool.draw(&shapes, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const world_1 = sdk.math.Vec3.fromArray(.{ 5, -5, 2.5 });
            const world_2 = sdk.math.Vec3.fromArray(.{ 5, 0, 2.5 });
            const world_3 = sdk.math.Vec3.fromArray(.{ 5, 5, 2.5 });
            const screen_1 = window_pos.add(window_size.multiplyElements(.fromArray(.{ 0.25, 0.5 })));
            const screen_2 = window_pos.add(window_size.multiplyElements(.fromArray(.{ 0.5, 0.5 })));
            const screen_3 = window_pos.add(window_size.multiplyElements(.fromArray(.{ 0.75, 0.5 })));
            ctx.setRef("Window");

            try testing.expectEqual(0, ui.testing_shapes.getAll().len);

            ctx.mouseMoveToPos(screen_1.toImVec());
            ctx.mouseDown(imgui.ImGuiMouseButton_Left);
            ctx.mouseMoveToPos(screen_2.toImVec());

            try testing.expectEqual(3, ui.testing_shapes.getAll().len);
            var line = ui.testing_shapes.findLineWithWorldPoints(world_1, world_2, 0.1);
            var point_1 = ui.testing_shapes.findPointWithWorldPosition(world_1, 0.1);
            var point_2 = ui.testing_shapes.findPointWithWorldPosition(world_2, 0.1);
            try testing.expect(line != null);
            try testing.expect(point_1 != null);
            try testing.expect(point_2 != null);
            try testing.expectEqual(sdk.math.Vec4.fill(0.1), line.?.color);
            try testing.expectEqual(1, line.?.thickness);
            try testing.expectEqual(sdk.math.Vec4.fill(0.2), point_1.?.color);
            try testing.expectEqual(2, point_1.?.thickness);
            try testing.expectEqual(sdk.math.Vec4.fill(0.3), point_2.?.color);
            try testing.expectEqual(3, point_2.?.thickness);
            try ctx.expectItemExists("5.00 cm");

            ctx.mouseMoveToPos(screen_3.toImVec());
            ctx.mouseUp(imgui.ImGuiMouseButton_Left);

            try testing.expectEqual(3, ui.testing_shapes.getAll().len);
            line = ui.testing_shapes.findLineWithWorldPoints(world_1, world_3, 0.1);
            point_1 = ui.testing_shapes.findPointWithWorldPosition(world_1, 0.1);
            point_2 = ui.testing_shapes.findPointWithWorldPosition(world_3, 0.1);
            try testing.expect(line != null);
            try testing.expect(point_1 != null);
            try testing.expect(point_2 != null);
            try testing.expectEqual(sdk.math.Vec4.fill(0.1), line.?.color);
            try testing.expectEqual(1, line.?.thickness);
            try testing.expectEqual(sdk.math.Vec4.fill(0.2), point_1.?.color);
            try testing.expectEqual(2, point_1.?.thickness);
            try testing.expectEqual(sdk.math.Vec4.fill(0.3), point_2.?.color);
            try testing.expectEqual(3, point_2.?.thickness);
            try ctx.expectItemExists("10.00 cm");

            ctx.mouseMoveToPos(screen_2.toImVec());

            try testing.expectEqual(3, ui.testing_shapes.getAll().len);
            line = ui.testing_shapes.findLineWithWorldPoints(world_1, world_3, 0.1);
            point_1 = ui.testing_shapes.findPointWithWorldPosition(world_1, 0.1);
            point_2 = ui.testing_shapes.findPointWithWorldPosition(world_3, 0.1);
            try testing.expect(line != null);
            try testing.expect(point_1 != null);
            try testing.expect(point_2 != null);
            try testing.expectEqual(sdk.math.Vec4.fill(0.1), line.?.color);
            try testing.expectEqual(1, line.?.thickness);
            try testing.expectEqual(sdk.math.Vec4.fill(0.2), point_1.?.color);
            try testing.expectEqual(2, point_1.?.thickness);
            try testing.expectEqual(sdk.math.Vec4.fill(0.2), point_2.?.color);
            try testing.expectEqual(2, point_2.?.thickness);
            try ctx.expectItemExists("10.00 cm");

            ctx.mouseMoveToPos(screen_1.toImVec());

            try testing.expectEqual(3, ui.testing_shapes.getAll().len);
            line = ui.testing_shapes.findLineWithWorldPoints(world_1, world_3, 0.1);
            point_1 = ui.testing_shapes.findPointWithWorldPosition(world_1, 0.1);
            point_2 = ui.testing_shapes.findPointWithWorldPosition(world_3, 0.1);
            try testing.expect(line != null);
            try testing.expect(point_1 != null);
            try testing.expect(point_2 != null);
            try testing.expectEqual(sdk.math.Vec4.fill(0.1), line.?.color);
            try testing.expectEqual(1, line.?.thickness);
            try testing.expectEqual(sdk.math.Vec4.fill(0.3), point_1.?.color);
            try testing.expectEqual(3, point_1.?.thickness);
            try testing.expectEqual(sdk.math.Vec4.fill(0.2), point_2.?.color);
            try testing.expectEqual(2, point_2.?.thickness);
            try ctx.expectItemExists("10.00 cm");

            ctx.mouseDown(imgui.ImGuiMouseButton_Left);
            ctx.mouseMoveToPos(screen_2.toImVec());

            try testing.expectEqual(3, ui.testing_shapes.getAll().len);
            line = ui.testing_shapes.findLineWithWorldPoints(world_2, world_3, 0.1);
            point_1 = ui.testing_shapes.findPointWithWorldPosition(world_2, 0.1);
            point_2 = ui.testing_shapes.findPointWithWorldPosition(world_3, 0.1);
            try testing.expect(line != null);
            try testing.expect(point_1 != null);
            try testing.expect(point_2 != null);
            try testing.expectEqual(sdk.math.Vec4.fill(0.1), line.?.color);
            try testing.expectEqual(1, line.?.thickness);
            try testing.expectEqual(sdk.math.Vec4.fill(0.3), point_1.?.color);
            try testing.expectEqual(3, point_1.?.thickness);
            try testing.expectEqual(sdk.math.Vec4.fill(0.2), point_2.?.color);
            try testing.expectEqual(2, point_2.?.thickness);
            try ctx.expectItemExists("5.00 cm");

            ctx.mouseUp(imgui.ImGuiMouseButton_Left);
            ctx.mouseMoveToPos(screen_1.toImVec());

            try testing.expectEqual(3, ui.testing_shapes.getAll().len);
            line = ui.testing_shapes.findLineWithWorldPoints(world_2, world_3, 0.1);
            point_1 = ui.testing_shapes.findPointWithWorldPosition(world_2, 0.1);
            point_2 = ui.testing_shapes.findPointWithWorldPosition(world_3, 0.1);
            try testing.expect(line != null);
            try testing.expect(point_1 != null);
            try testing.expect(point_2 != null);
            try testing.expectEqual(sdk.math.Vec4.fill(0.1), line.?.color);
            try testing.expectEqual(1, line.?.thickness);
            try testing.expectEqual(sdk.math.Vec4.fill(0.2), point_1.?.color);
            try testing.expectEqual(2, point_1.?.thickness);
            try testing.expectEqual(sdk.math.Vec4.fill(0.2), point_2.?.color);
            try testing.expectEqual(2, point_2.?.thickness);
            try ctx.expectItemExists("5.00 cm");

            ctx.mouseClick(imgui.ImGuiMouseButton_Left);

            try testing.expectEqual(0, ui.testing_shapes.getAll().len);
            try ctx.expectItemNotExists("5.00 cm");
            try ctx.expectItemNotExists("10.00 cm");
        }
    };
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
