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
    frame: model.Frame = .{},
    camera: ui.Camera = .{},
    hurt_cylinders: ui.HurtCylinders = .{},
    hit_lines: ui.HitLines = .{},

    const Self = @This();

    const config = .{
        .floor = .{
            .color = sdk.math.Vec4.fromArray(.{ 0.0, 1.0, 0.0, 1.0 }),
            .thickness = 1.0,
        },
        .look_direction = .{
            .color = sdk.math.Vec4.fromArray(.{ 1.0, 0.0, 1.0, 1.0 }),
            .length = 100.0,
            .thickness = 1.0,
        },
    };

    pub fn processFrame(self: *Self, frame: *const model.Frame) void {
        self.hurt_cylinders.processFrame(frame);
        self.hit_lines.processFrame(frame);
        self.frame = frame.*;
    }

    pub fn update(self: *Self, delta_time: f32) void {
        self.hurt_cylinders.update(delta_time);
        self.hit_lines.update(delta_time);
    }

    pub fn draw(self: *Self, direction: ViewDirection) void {
        self.camera.updateWindowState(direction);
        const matrix = self.camera.calculateMatrix(&self.frame, direction) orelse return;
        const inverse_matrix = matrix.inverse() orelse sdk.math.Mat4.identity;
        ui.drawCollisionSpheres(&self.frame, matrix, inverse_matrix);
        self.hurt_cylinders.draw(&self.frame, direction, matrix, inverse_matrix);
        if (self.frame.floor_z) |floor_z| {
            ui.drawFloor(floor_z, config.floor.color, config.floor.thickness, direction, matrix);
        }
        self.drawLookAtLines(direction, matrix);
        ui.drawSkeletons(&self.frame, matrix);
        self.hit_lines.draw(&self.frame, matrix);
    }

    fn drawLookAtLines(self: *const Self, direction: ViewDirection, matrix: sdk.math.Mat4) void {
        if (direction != .top) {
            return;
        }
        for (&self.frame.players) |*player| {
            const position = player.position orelse continue;
            const rotation = player.rotation orelse continue;
            const length = config.look_direction.length;
            const delta = sdk.math.Vec3.plus_x.scale(length).rotateZ(rotation);
            const line = sdk.math.LineSegment3{
                .point_1 = position,
                .point_2 = position.add(delta),
            };
            const color = config.look_direction.color;
            const thickness = config.look_direction.thickness;
            ui.drawLine(line, color, thickness, matrix);
        }
    }
};
