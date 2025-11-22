const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("../ui/root.zig");

const half_horizontal_fov: f32 = 0.5 * std.math.degreesToRadians(62.0);
const half_vertical_fov: f32 = std.math.atan((9.0 / 16.0) * std.math.tan(half_horizontal_fov));

pub fn drawIngameCamera(
    settings: *const model.IngameCameraSettings,
    frame: *const model.Frame,
    direction: ui.ViewDirection,
    matrix: sdk.math.Mat4,
) void {
    if (!settings.enabled or direction == .front) {
        return;
    }
    const camera = if (frame.camera) |*c| c else return;
    const edges = [4]sdk.math.Vec3{
        sdk.math.Vec3.fromArray(.{ 1, std.math.tan(half_horizontal_fov), std.math.tan(half_vertical_fov) }).normalize(),
        sdk.math.Vec3.fromArray(.{ 1, std.math.tan(half_horizontal_fov), -std.math.tan(half_vertical_fov) }).normalize(),
        sdk.math.Vec3.fromArray(.{ 1, -std.math.tan(half_horizontal_fov), std.math.tan(half_vertical_fov) }).normalize(),
        sdk.math.Vec3.fromArray(.{ 1, -std.math.tan(half_horizontal_fov), -std.math.tan(half_vertical_fov) }).normalize(),
    };
    for (edges) |edge| {
        const offset = edge.rotateZ(camera.yaw).rotateY(camera.pitch).rotateZ(camera.roll).scale(settings.length);
        const line = sdk.math.LineSegment3{ .point_1 = camera.position, .point_2 = camera.position.add(offset) };
        ui.drawLine(line, settings.color, settings.thickness, matrix);
    }
}

const testing = std.testing;

test "should draw lines correctly when direction is not front" {
    const Test = struct {
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
        } };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            ui.testing_shapes.clear();
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawIngameCamera(&settings, &frame, .top, .identity);
        }

        fn testFunction(_: sdk.ui.TestContext) !void {
            try testing.expectEqual(4, ui.testing_shapes.getAll().len);
            const lines = [4]?*const ui.TestingShapes.Line{
                ui.testing_shapes.findLineWithWorldPoints(
                    .fromArray(.{ 1, 2, 3 }),
                    .fromArray(.{ 0.235, 6.117, 5.733 }),
                    0.001,
                ),
                ui.testing_shapes.findLineWithWorldPoints(
                    .fromArray(.{ 1, 2, 3 }),
                    .fromArray(.{ -1.733, 6.117, 3.765 }),
                    0.001,
                ),
                ui.testing_shapes.findLineWithWorldPoints(
                    .fromArray(.{ 1, 2, 3 }),
                    .fromArray(.{ 3.733, 6.117, 2.235 }),
                    0.001,
                ),
                ui.testing_shapes.findLineWithWorldPoints(
                    .fromArray(.{ 1, 2, 3 }),
                    .fromArray(.{ 1.765, 6.117, 0.267 }),
                    0.001,
                ),
            };
            for (lines) |line| {
                try testing.expect(line != null);
                try testing.expectEqual(.{ 0.1, 0.2, 0.3, 0.4 }, line.?.color.array);
                try testing.expectEqual(1, line.?.thickness);
            }
        }
    };
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw nothing when direction is front" {
    const Test = struct {
        const settings = model.IngameCameraSettings{ .enabled = true };
        const frame = model.Frame{ .camera = .{
            .position = .fromArray(.{ 1, 2, 3 }),
            .pitch = -0.25 * std.math.pi,
            .yaw = 0.5 * std.math.pi,
            .roll = 0,
        } };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            ui.testing_shapes.clear();
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawIngameCamera(&settings, &frame, .front, .identity);
        }

        fn testFunction(_: sdk.ui.TestContext) !void {
            try testing.expectEqual(0, ui.testing_shapes.getAll().len);
        }
    };
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw nothing when disabled in settings" {
    const Test = struct {
        const settings = model.IngameCameraSettings{ .enabled = false };
        const frame = model.Frame{ .camera = .{
            .position = .fromArray(.{ 1, 2, 3 }),
            .pitch = -0.25 * std.math.pi,
            .yaw = 0.5 * std.math.pi,
            .roll = 0,
        } };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            ui.testing_shapes.clear();
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawIngameCamera(&settings, &frame, .top, .identity);
        }

        fn testFunction(_: sdk.ui.TestContext) !void {
            try testing.expectEqual(0, ui.testing_shapes.getAll().len);
        }
    };
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
