const std = @import("std");
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

    pub fn draw(self: *Self, settings: *const model.MeasureToolSettings, matrix: sdk.math.Mat4) void {
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
        if (hovered_point != null) {
            imgui.igSetMouseCursor(imgui.ImGuiMouseCursor_Hand);
        }
        ui.drawLine(line, settings.line.color, settings.line.thickness, matrix);
        ui.drawPoint(line.point_1, point_1_color, point_1_thickness, matrix);
        ui.drawPoint(line.point_2, point_2_color, point_2_thickness, matrix);
        drawLineText(line, settings.text_color, matrix);
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
        const text = std.fmt.bufPrintZ(&buffer, "{d:.2} cm", .{distance}) catch "error";
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
    }
};
