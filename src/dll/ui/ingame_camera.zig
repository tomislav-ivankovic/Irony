const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("../ui/root.zig");

pub fn drawIngameCamera(
    shapes: *const ui.Shapes,
    settings: *const model.IngameCameraSettings,
    frame: *const model.Frame,
    display_size: sdk.math.Vec2,
) void {
    if (!settings.enabled) {
        return;
    }
    if (shapes.* == ._2d and shapes._2d.direction == .front) {
        return;
    }
    const camera = if (frame.camera) |*c| c else return;
    const inverse_aspect_ratio = display_size.y() / display_size.x();
    const half_horizontal_fov: f32 = 0.5 * camera.horizontal_fov;
    const half_vertical_fov: f32 = std.math.atan(inverse_aspect_ratio * std.math.tan(half_horizontal_fov));
    const edges = [4]sdk.math.Vec3{
        sdk.math.Vec3.fromArray(.{ 1, std.math.tan(half_horizontal_fov), std.math.tan(half_vertical_fov) }).normalize(),
        sdk.math.Vec3.fromArray(.{ 1, std.math.tan(half_horizontal_fov), -std.math.tan(half_vertical_fov) }).normalize(),
        sdk.math.Vec3.fromArray(.{ 1, -std.math.tan(half_horizontal_fov), std.math.tan(half_vertical_fov) }).normalize(),
        sdk.math.Vec3.fromArray(.{ 1, -std.math.tan(half_horizontal_fov), -std.math.tan(half_vertical_fov) }).normalize(),
    };
    for (edges) |edge| {
        const offset = edge.rotateX(-camera.roll).rotateY(camera.pitch).rotateZ(camera.yaw).scale(settings.length);
        const line = sdk.math.LineSegment3{ .point_1 = camera.position, .point_2 = camera.position.add(offset) };
        shapes.drawLine(line, settings.color, settings.thickness, 0);
    }
}

const testing = std.testing;

test "should draw lines correctly" {
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();

    const shapes = ui.Shapes{ ._void = .{} };
    const settings = model.IngameCameraSettings{
        .enabled = true,
        .color = .fromArray(.{ 0.1, 0.2, 0.3, 0.4 }),
        .length = 5,
        .thickness = 1,
    };
    const frame = model.Frame{ .camera = .{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = -0.25 * std.math.pi,
        .yaw = 0.5 * std.math.pi,
        .roll = 0,
        .horizontal_fov = std.math.degreesToRadians(65.0),
    } };
    drawIngameCamera(&shapes, &settings, &frame, .fromArray(.{ 1280, 720 }));

    try testing.expectEqual(4, ui.testing_shapes.getAll().len);
    const lines = [4]?*const ui.TestingShapes.Line{
        ui.testing_shapes.findLineWithWorldPoints(
            .fromArray(.{ 1, 2, 3 }),
            .fromArray(.{ -1.572, 5.877, 1.169 }),
            0.001,
        ),
        ui.testing_shapes.findLineWithWorldPoints(
            .fromArray(.{ 1, 2, 3 }),
            .fromArray(.{ -1.572, 3.831, -0.8772 }),
            0.001,
        ),
        ui.testing_shapes.findLineWithWorldPoints(
            .fromArray(.{ 1, 2, 3 }),
            .fromArray(.{ -1.572, 3.831, -0.877 }),
            0.001,
        ),
        ui.testing_shapes.findLineWithWorldPoints(
            .fromArray(.{ 1, 2, 3 }),
            .fromArray(.{ 3.572, 3.831, -0.877 }),
            0.001,
        ),
    };
    for (lines) |line| {
        try testing.expect(line != null);
        try testing.expectEqual(.{ 0.1, 0.2, 0.3, 0.4 }, line.?.color.array);
        try testing.expectEqual(1, line.?.thickness);
    }
}

test "should draw nothing when disabled in settings" {
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();

    const shapes = ui.Shapes{ ._void = .{} };
    const settings = model.IngameCameraSettings{ .enabled = false };
    const frame = model.Frame{ .camera = .{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = -0.25 * std.math.pi,
        .yaw = 0.5 * std.math.pi,
        .roll = 0,
        .horizontal_fov = std.math.degreesToRadians(65.0),
    } };
    drawIngameCamera(&shapes, &settings, &frame, .fromArray(.{ 1280, 720 }));

    try testing.expectEqual(0, ui.testing_shapes.getAll().len);
}

test "should draw nothing when shapes are 2D and direction is front" {
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();

    const shapes = ui.Shapes{ ._2d = .{
        .direction = .front,
        .matrix = .identity,
        .inverse_matrix = .identity,
    } };
    const settings = model.IngameCameraSettings{ .enabled = true };
    const frame = model.Frame{ .camera = .{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = -0.25 * std.math.pi,
        .yaw = 0.5 * std.math.pi,
        .roll = 0,
        .horizontal_fov = std.math.degreesToRadians(65.0),
    } };
    drawIngameCamera(&shapes, &settings, &frame, .fromArray(.{ 1280, 720 }));

    try testing.expectEqual(0, ui.testing_shapes.getAll().len);
}
