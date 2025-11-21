const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("../ui/root.zig");

pub fn drawCollisionSpheres(
    settings: *const model.PlayerSettings(model.CollisionSpheresSettings),
    frame: *const model.Frame,
    matrix: sdk.math.Mat4,
    inverse_matrix: sdk.math.Mat4,
) void {
    for (model.PlayerId.all) |player_id| {
        const player_settings = settings.getById(frame, player_id);
        if (!player_settings.enabled) {
            continue;
        }
        const player = frame.getPlayerById(player_id);
        const spheres: *const model.CollisionSpheres = if (player.collision_spheres) |*s| s else continue;
        for (spheres.values) |sphere| {
            ui.drawSphere(sphere, player_settings.color, player_settings.thickness, matrix, inverse_matrix);
        }
    }
}

const testing = std.testing;

test "should draw spheres correctly" {
    const Test = struct {
        fn guiFunction(_: sdk.ui.TestContext) !void {
            ui.testing_shapes.clear();

            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();

            const settings = model.PlayerSettings(model.CollisionSpheresSettings){
                .mode = .id_separated,
                .players = .{
                    .{ .enabled = true, .color = .fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), .thickness = 1 },
                    .{ .enabled = true, .color = .fromArray(.{ 0.5, 0.6, 0.7, 0.8 }), .thickness = 2 },
                },
            };
            const frame = model.Frame{ .players = .{
                .{ .collision_spheres = .init(.{
                    .neck = .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 1 },
                    .left_elbow = .{ .center = .fromArray(.{ 4, 5, 6 }), .radius = 2 },
                    .right_elbow = .{ .center = .fromArray(.{ 7, 8, 9 }), .radius = 3 },
                    .lower_torso = .{ .center = .fromArray(.{ 10, 11, 12 }), .radius = 4 },
                    .left_knee = .{ .center = .fromArray(.{ 13, 14, 15 }), .radius = 5 },
                    .right_knee = .{ .center = .fromArray(.{ 16, 17, 18 }), .radius = 6 },
                    .left_ankle = .{ .center = .fromArray(.{ 19, 20, 21 }), .radius = 7 },
                    .right_ankle = .{ .center = .fromArray(.{ 22, 23, 24 }), .radius = 8 },
                }) },
                .{ .collision_spheres = .init(.{
                    .neck = .{ .center = .fromArray(.{ -1, -2, -3 }), .radius = 1 },
                    .left_elbow = .{ .center = .fromArray(.{ -4, -5, -6 }), .radius = 2 },
                    .right_elbow = .{ .center = .fromArray(.{ -7, -8, -9 }), .radius = 3 },
                    .lower_torso = .{ .center = .fromArray(.{ -10, -11, -12 }), .radius = 4 },
                    .left_knee = .{ .center = .fromArray(.{ -13, -14, -15 }), .radius = 5 },
                    .right_knee = .{ .center = .fromArray(.{ -16, -17, -18 }), .radius = 6 },
                    .left_ankle = .{ .center = .fromArray(.{ -19, -20, -21 }), .radius = 7 },
                    .right_ankle = .{ .center = .fromArray(.{ -22, -23, -24 }), .radius = 8 },
                }) },
            } };
            drawCollisionSpheres(&settings, &frame, .identity, .identity);
        }

        fn testFunction(_: sdk.ui.TestContext) !void {
            try testing.expectEqual(16, ui.testing_shapes.getAll().len);
            const spheres = [16]?*const ui.TestingShapes.Sphere{
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ 1, 2, 3 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ 4, 5, 6 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ 7, 8, 9 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ 10, 11, 12 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ 13, 14, 15 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ 16, 17, 18 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ 19, 20, 21 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ 22, 23, 24 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ -1, -2, -3 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ -4, -5, -6 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ -7, -8, -9 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ -10, -11, -12 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ -13, -14, -15 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ -16, -17, -18 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ -19, -20, -21 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ -22, -23, -24 }), 0.0001),
            };
            for (spheres, 0..) |sphere, index| {
                try testing.expect(sphere != null);
                if (index < 8) {
                    try testing.expectEqual(.{ 0.1, 0.2, 0.3, 0.4 }, sphere.?.color.array);
                    try testing.expectEqual(1, sphere.?.thickness);
                } else {
                    try testing.expectEqual(.{ 0.5, 0.6, 0.7, 0.8 }, sphere.?.color.array);
                    try testing.expectEqual(2, sphere.?.thickness);
                }
            }
        }
    };
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should not draw spheres for the player disabled in settings" {
    const Test = struct {
        fn guiFunction(_: sdk.ui.TestContext) !void {
            ui.testing_shapes.clear();

            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();

            const settings = model.PlayerSettings(model.CollisionSpheresSettings){
                .mode = .id_separated,
                .players = .{ .{ .enabled = true }, .{ .enabled = false } },
            };
            const frame = model.Frame{ .players = .{
                .{ .collision_spheres = .init(.{
                    .neck = .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 1 },
                    .left_elbow = .{ .center = .fromArray(.{ 4, 5, 6 }), .radius = 2 },
                    .right_elbow = .{ .center = .fromArray(.{ 7, 8, 9 }), .radius = 3 },
                    .lower_torso = .{ .center = .fromArray(.{ 10, 11, 12 }), .radius = 4 },
                    .left_knee = .{ .center = .fromArray(.{ 13, 14, 15 }), .radius = 5 },
                    .right_knee = .{ .center = .fromArray(.{ 16, 17, 18 }), .radius = 6 },
                    .left_ankle = .{ .center = .fromArray(.{ 19, 20, 21 }), .radius = 7 },
                    .right_ankle = .{ .center = .fromArray(.{ 22, 23, 24 }), .radius = 8 },
                }) },
                .{ .collision_spheres = .init(.{
                    .neck = .{ .center = .fromArray(.{ -1, -2, -3 }), .radius = 1 },
                    .left_elbow = .{ .center = .fromArray(.{ -4, -5, -6 }), .radius = 2 },
                    .right_elbow = .{ .center = .fromArray(.{ -7, -8, -9 }), .radius = 3 },
                    .lower_torso = .{ .center = .fromArray(.{ -10, -11, -12 }), .radius = 4 },
                    .left_knee = .{ .center = .fromArray(.{ -13, -14, -15 }), .radius = 5 },
                    .right_knee = .{ .center = .fromArray(.{ -16, -17, -18 }), .radius = 6 },
                    .left_ankle = .{ .center = .fromArray(.{ -19, -20, -21 }), .radius = 7 },
                    .right_ankle = .{ .center = .fromArray(.{ -22, -23, -24 }), .radius = 8 },
                }) },
            } };
            drawCollisionSpheres(&settings, &frame, .identity, .identity);
        }

        fn testFunction(_: sdk.ui.TestContext) !void {
            try testing.expectEqual(8, ui.testing_shapes.getAll().len);
            const enabled_spheres = [8]?*const ui.TestingShapes.Sphere{
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ 1, 2, 3 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ 4, 5, 6 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ 7, 8, 9 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ 10, 11, 12 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ 13, 14, 15 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ 16, 17, 18 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ 19, 20, 21 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ 22, 23, 24 }), 0.0001),
            };
            const disabled_spheres = [8]?*const ui.TestingShapes.Sphere{
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ -1, -2, -3 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ -4, -5, -6 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ -7, -8, -9 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ -10, -11, -12 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ -13, -14, -15 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ -16, -17, -18 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ -19, -20, -21 }), 0.0001),
                ui.testing_shapes.findSphereWithWorldCenter(.fromArray(.{ -22, -23, -24 }), 0.0001),
            };
            for (enabled_spheres) |sphere| {
                try testing.expect(sphere != null);
            }
            for (disabled_spheres) |sphere| {
                try testing.expectEqual(null, sphere);
            }
        }
    };
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
