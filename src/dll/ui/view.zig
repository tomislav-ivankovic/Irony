const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("../ui/root.zig");

pub const ViewDirection = enum {
    front,
    side,
    top,
};

pub const View = struct {
    camera: ui.Camera = .{},
    hurt_cylinders: ui.HurtCylinders = .{},
    hit_lines: ui.HitLines = .{},
    measure_tool: ui.MeasureTool = .{},

    const Self = @This();

    pub fn processFrame(self: *Self, settings: *const model.Settings, frame: *const model.Frame) void {
        self.hurt_cylinders.processFrame(&settings.hurt_cylinders, frame);
        self.hit_lines.processFrame(&settings.hit_lines, frame);
    }

    pub fn update(self: *Self, delta_time: f32) void {
        self.hurt_cylinders.update(delta_time);
        self.hit_lines.update(delta_time);
    }

    pub fn draw(
        self: *Self,
        settings: *const model.Settings,
        frame: *const model.Frame,
        direction: ViewDirection,
    ) void {
        self.camera.updateWindowState(direction);
        const matrix = self.camera.calculateMatrix(frame, direction) orelse return;
        const inverse_matrix = matrix.inverse() orelse sdk.math.Mat4.identity;

        self.measure_tool.processInput(&settings.measure_tool, matrix, inverse_matrix);
        self.camera.processInput(direction, inverse_matrix);

        ui.drawIngameCamera(&settings.ingame_camera, frame, direction, matrix);
        ui.drawCollisionSpheres(&settings.collision_spheres, frame, matrix, inverse_matrix);
        self.hurt_cylinders.draw(&settings.hurt_cylinders, frame, direction, matrix, inverse_matrix);
        ui.drawFloor(&settings.floor, frame, direction, matrix);
        ui.drawForwardDirections(&settings.forward_directions, frame, direction, matrix);
        ui.drawSkeletons(&settings.skeletons, frame, matrix);
        self.hit_lines.draw(&settings.hit_lines, frame, matrix);
        self.measure_tool.draw(&settings.measure_tool, matrix);
    }
};
