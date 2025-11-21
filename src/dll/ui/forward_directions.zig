const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("../ui/root.zig");

pub fn drawForwardDirections(
    settings: *const model.PlayerSettings(model.ForwardDirectionSettings),
    frame: *const model.Frame,
    direction: ui.ViewDirection,
    matrix: sdk.math.Mat4,
) void {
    if (direction != .top) {
        return;
    }
    for (model.PlayerId.all) |player_id| {
        const player_settings = settings.getById(frame, player_id);
        if (!player_settings.enabled) {
            continue;
        }
        const player = frame.getPlayerById(player_id);
        const position = player.getPosition() orelse continue;
        const rotation = player.rotation orelse continue;
        const delta = sdk.math.Vec3.plus_x.scale(player_settings.length).rotateZ(rotation);
        const line = sdk.math.LineSegment3{
            .point_1 = position,
            .point_2 = position.add(delta),
        };
        ui.drawLine(line, player_settings.color, player_settings.thickness, matrix);
    }
}

const testing = std.testing;

test "should draw lines correctly when direction is top" {
    const Test = struct {
        fn guiFunction(_: sdk.ui.TestContext) !void {
            ui.testing_shapes.clear();

            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();

            const settings = model.PlayerSettings(model.ForwardDirectionSettings){
                .mode = .id_separated,
                .players = .{
                    .{ .enabled = true, .color = .fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), .length = 1, .thickness = 2 },
                    .{ .enabled = true, .color = .fromArray(.{ 0.5, 0.6, 0.7, 0.8 }), .length = 3, .thickness = 4 },
                },
            };
            const frame = model.Frame{ .players = .{
                .{
                    .collision_spheres = .initFill(.{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 0 }),
                    .rotation = 0,
                },
                .{
                    .collision_spheres = .initFill(.{ .center = .fromArray(.{ 4, 5, 6 }), .radius = 0 }),
                    .rotation = 0.5 * std.math.pi,
                },
            } };
            drawForwardDirections(&settings, &frame, .top, .identity);
        }

        fn testFunction(_: sdk.ui.TestContext) !void {
            try testing.expectEqual(2, ui.testing_shapes.getAll().len);
            const line_1 = ui.testing_shapes.findLineWithWorldPoints(
                .fromArray(.{ 1, 2, 3 }),
                .fromArray(.{ 2, 2, 3 }),
                0.0001,
            );
            const line_2 = ui.testing_shapes.findLineWithWorldPoints(
                .fromArray(.{ 4, 5, 6 }),
                .fromArray(.{ 4, 8, 6 }),
                0.0001,
            );
            try testing.expect(line_1 != null);
            try testing.expect(line_2 != null);
            try testing.expectEqual(.{ 0.1, 0.2, 0.3, 0.4 }, line_1.?.color.array);
            try testing.expectEqual(.{ 0.5, 0.6, 0.7, 0.8 }, line_2.?.color.array);
            try testing.expectEqual(2, line_1.?.thickness);
            try testing.expectEqual(4, line_2.?.thickness);
        }
    };
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should not draw anything when direction is not top" {
    const Test = struct {
        fn guiFunction(_: sdk.ui.TestContext) !void {
            ui.testing_shapes.clear();

            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();

            const settings = model.PlayerSettings(model.ForwardDirectionSettings){
                .mode = .id_separated,
                .players = .{ .{}, .{} },
            };
            const frame = model.Frame{ .players = .{
                .{
                    .collision_spheres = .initFill(.{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 0 }),
                    .rotation = 0,
                },
                .{
                    .collision_spheres = .initFill(.{ .center = .fromArray(.{ 4, 5, 6 }), .radius = 0 }),
                    .rotation = 0,
                },
            } };
            drawForwardDirections(&settings, &frame, .front, .identity);
            drawForwardDirections(&settings, &frame, .side, .identity);
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

test "should not draw the line for the player disabled in settings" {
    const Test = struct {
        fn guiFunction(_: sdk.ui.TestContext) !void {
            ui.testing_shapes.clear();

            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();

            const settings = model.PlayerSettings(model.ForwardDirectionSettings){
                .mode = .id_separated,
                .players = .{ .{ .enabled = true, .length = 1 }, .{ .enabled = false, .length = 1 } },
            };
            const frame = model.Frame{ .players = .{
                .{
                    .collision_spheres = .initFill(.{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 0 }),
                    .rotation = 0,
                },
                .{
                    .collision_spheres = .initFill(.{ .center = .fromArray(.{ 4, 5, 6 }), .radius = 0 }),
                    .rotation = 0,
                },
            } };
            drawForwardDirections(&settings, &frame, .top, .identity);
        }

        fn testFunction(_: sdk.ui.TestContext) !void {
            try testing.expectEqual(1, ui.testing_shapes.getAll().len);
            const line_1 = ui.testing_shapes.findLineWithWorldPoints(
                .fromArray(.{ 1, 2, 3 }),
                .fromArray(.{ 2, 2, 3 }),
                0.0001,
            );
            const line_2 = ui.testing_shapes.findLineWithWorldPoints(
                .fromArray(.{ 4, 5, 6 }),
                .fromArray(.{ 5, 5, 6 }),
                0.0001,
            );
            try testing.expect(line_1 != null);
            try testing.expectEqual(null, line_2);
        }
    };
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
