const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const rendering = @import("../rendering/root.zig");
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
    control_hints: ui.ControlHints = .{},

    const Self = @This();

    pub fn processFrame(self: *Self, settings: *const model.Settings, frame: *const model.Frame) void {
        self.hurt_cylinders.processFrame(&settings.hurt_cylinders, frame);
        self.hit_lines.processFrame(&settings.hit_lines, frame);
    }

    pub fn update(self: *Self, delta_time: f32) void {
        self.camera.flushWindowMeasurements();
        self.hurt_cylinders.update(delta_time);
        self.hit_lines.update(delta_time);
        self.control_hints.update(delta_time);
    }

    pub fn draw(
        self: *Self,
        settings: *const model.Settings,
        frame: *const model.Frame,
        direction: ViewDirection,
    ) void {
        self.camera.measureWindow(direction);
        const matrix = self.camera.calculateMatrix(frame, direction) orelse return;
        const inverse_matrix = matrix.inverse() orelse sdk.math.Mat4.identity;

        self.measure_tool.processInput(&settings.measure_tool, matrix, inverse_matrix);
        self.camera.processInput(direction, inverse_matrix);

        const shapes_2d = ui.Shapes2D{
            .direction = direction,
            .matrix = matrix,
            .inverse_matrix = inverse_matrix,
            .thickness_scale = settings.general.rendering_2d.thickness_scale,
        };
        const shapes = ui.Shapes{ ._2d = shapes_2d };

        ui.drawIngameCamera(&shapes, &settings.ingame_camera, frame);
        ui.drawCollisionSpheres(&shapes, &settings.collision_spheres, frame);
        self.hurt_cylinders.draw(&shapes, &settings.hurt_cylinders, frame);
        ui.drawStage(&shapes_2d, &settings.stage, frame);
        ui.drawForwardDirections(&shapes, &settings.forward_directions, frame);
        ui.drawSkeletons(&shapes, &settings.skeletons, frame);
        self.hit_lines.draw(&shapes, &settings.hit_lines, frame);
        self.measure_tool.draw(&shapes, &settings.measure_tool);
        self.control_hints.draw(direction);
    }

    pub fn draw3D(
        self: *const Self,
        shape_renderer: *rendering.Shapes,
        settings: *const model.Settings,
        frame: *const model.Frame,
    ) void {
        const shapes = ui.Shapes{ ._3d = .{
            .renderer = shape_renderer,
            .thickness_scale = settings.general.rendering_3d.thickness_scale,
            .fill_alpha = settings.general.rendering_3d.fill_alpha,
        } };
        ui.drawIngameCamera(&shapes, &settings.ingame_camera, frame);
        ui.drawCollisionSpheres(&shapes, &settings.collision_spheres, frame);
        self.hurt_cylinders.draw(&shapes, &settings.hurt_cylinders, frame);
        ui.drawForwardDirections(&shapes, &settings.forward_directions, frame);
        ui.drawSkeletons(&shapes, &settings.skeletons, frame);
        self.hit_lines.draw(&shapes, &settings.hit_lines, frame);
        self.measure_tool.draw(&shapes, &settings.measure_tool);
    }
};
