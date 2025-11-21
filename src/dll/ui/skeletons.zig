const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("../ui/root.zig");

pub fn drawSkeletons(
    settings: *const model.PlayerSettings(model.SkeletonSettings),
    frame: *const model.Frame,
    matrix: sdk.math.Mat4,
) void {
    for (model.PlayerId.all) |player_id| {
        const player_settings = settings.getById(frame, player_id);
        if (!player_settings.enabled) {
            continue;
        }
        const player = frame.getPlayerById(player_id);
        const skeleton = player.getSkeleton() orelse continue;
        const blocking = player.blocking orelse .not_blocking;
        const can_move = player.can_move orelse true;
        var color = player_settings.colors.get(blocking);
        if (!can_move) {
            color.asColor().a *= player_settings.cant_move_alpha;
        }
        drawSkeleton(&skeleton, color, player_settings.thickness, matrix);
    }
}

fn drawSkeleton(
    skeleton: *const model.Skeleton,
    color: sdk.math.Vec4,
    thickness: f32,
    matrix: sdk.math.Mat4,
) void {
    drawBone(matrix, color, thickness, skeleton, .head, .neck);
    drawBone(matrix, color, thickness, skeleton, .neck, .upper_torso);
    drawBone(matrix, color, thickness, skeleton, .upper_torso, .left_shoulder);
    drawBone(matrix, color, thickness, skeleton, .upper_torso, .right_shoulder);
    drawBone(matrix, color, thickness, skeleton, .left_shoulder, .left_elbow);
    drawBone(matrix, color, thickness, skeleton, .right_shoulder, .right_elbow);
    drawBone(matrix, color, thickness, skeleton, .left_elbow, .left_hand);
    drawBone(matrix, color, thickness, skeleton, .right_elbow, .right_hand);
    drawBone(matrix, color, thickness, skeleton, .upper_torso, .lower_torso);
    drawBone(matrix, color, thickness, skeleton, .lower_torso, .left_pelvis);
    drawBone(matrix, color, thickness, skeleton, .lower_torso, .right_pelvis);
    drawBone(matrix, color, thickness, skeleton, .left_pelvis, .left_knee);
    drawBone(matrix, color, thickness, skeleton, .right_pelvis, .right_knee);
    drawBone(matrix, color, thickness, skeleton, .left_knee, .left_ankle);
    drawBone(matrix, color, thickness, skeleton, .right_knee, .right_ankle);
}

fn drawBone(
    matrix: sdk.math.Mat4,
    color: sdk.math.Vec4,
    thickness: f32,
    skeleton: *const model.Skeleton,
    point_1: model.SkeletonPointId,
    point_2: model.SkeletonPointId,
) void {
    const line = sdk.math.LineSegment3{
        .point_1 = skeleton.get(point_1),
        .point_2 = skeleton.get(point_2),
    };
    ui.drawLine(line, color, thickness, matrix);
}

const testing = std.testing;

test "should draw lines correctly" {
    const Test = struct {
        fn guiFunction(_: sdk.ui.TestContext) !void {
            ui.testing_shapes.clear();

            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();

            const settings = model.PlayerSettings(model.SkeletonSettings){
                .mode = .id_separated,
                .players = .{
                    .{
                        .enabled = true,
                        .colors = .initFill(.fromArray(.{ 0.1, 0.2, 0.3, 0.4 })),
                        .thickness = 1,
                        .cant_move_alpha = 1.0,
                    },
                    .{
                        .enabled = true,
                        .colors = .initFill(.fromArray(.{ 0.5, 0.6, 0.7, 0.8 })),
                        .thickness = 2,
                        .cant_move_alpha = 1.0,
                    },
                },
            };
            const frame = model.Frame{ .players = .{
                .{
                    .collision_spheres = .init(.{
                        .neck = .{ .center = .fill(2), .radius = 0 },
                        .left_elbow = .{ .center = .fill(3.12), .radius = 0 },
                        .right_elbow = .{ .center = .fill(3.22), .radius = 0 },
                        .lower_torso = .{ .center = .fill(4), .radius = 0 },
                        .left_knee = .{ .center = .fill(4.12), .radius = 0 },
                        .right_knee = .{ .center = .fill(4.22), .radius = 0 },
                        .left_ankle = .{ .center = .fill(4.13), .radius = 0 },
                        .right_ankle = .{ .center = .fill(4.23), .radius = 0 },
                    }),
                    .hurt_cylinders = .init(.{
                        .left_ankle = .{ .cylinder = .{ .center = .fill(4.13), .radius = 0, .half_height = 0 } },
                        .right_ankle = .{ .cylinder = .{ .center = .fill(4.23), .radius = 0, .half_height = 0 } },
                        .left_hand = .{ .cylinder = .{ .center = .fill(3.13), .radius = 0, .half_height = 0 } },
                        .right_hand = .{ .cylinder = .{ .center = .fill(3.23), .radius = 0, .half_height = 0 } },
                        .left_knee = .{ .cylinder = .{ .center = .fill(4.12), .radius = 0, .half_height = 0 } },
                        .right_knee = .{ .cylinder = .{ .center = .fill(4.22), .radius = 0, .half_height = 0 } },
                        .left_elbow = .{ .cylinder = .{ .center = .fill(3.12), .radius = 0, .half_height = 0 } },
                        .right_elbow = .{ .cylinder = .{ .center = .fill(3.22), .radius = 0, .half_height = 0 } },
                        .head = .{ .cylinder = .{ .center = .fill(1), .radius = 0, .half_height = 0 } },
                        .left_shoulder = .{ .cylinder = .{ .center = .fill(3.11), .radius = 0, .half_height = 0 } },
                        .right_shoulder = .{ .cylinder = .{ .center = .fill(3.21), .radius = 0, .half_height = 0 } },
                        .upper_torso = .{ .cylinder = .{ .center = .fill(3), .radius = 0, .half_height = 0 } },
                        .left_pelvis = .{ .cylinder = .{ .center = .fill(4.11), .radius = 0, .half_height = 0 } },
                        .right_pelvis = .{ .cylinder = .{ .center = .fill(4.21), .radius = 0, .half_height = 0 } },
                    }),
                },
                .{
                    .collision_spheres = .init(.{
                        .neck = .{ .center = .fill(-2), .radius = 0 },
                        .left_elbow = .{ .center = .fill(-3.12), .radius = 0 },
                        .right_elbow = .{ .center = .fill(-3.22), .radius = 0 },
                        .lower_torso = .{ .center = .fill(-4), .radius = 0 },
                        .left_knee = .{ .center = .fill(-4.12), .radius = 0 },
                        .right_knee = .{ .center = .fill(-4.22), .radius = 0 },
                        .left_ankle = .{ .center = .fill(-4.13), .radius = 0 },
                        .right_ankle = .{ .center = .fill(-4.23), .radius = 0 },
                    }),
                    .hurt_cylinders = .init(.{
                        .left_ankle = .{ .cylinder = .{ .center = .fill(-4.13), .radius = 0, .half_height = 0 } },
                        .right_ankle = .{ .cylinder = .{ .center = .fill(-4.23), .radius = 0, .half_height = 0 } },
                        .left_hand = .{ .cylinder = .{ .center = .fill(-3.13), .radius = 0, .half_height = 0 } },
                        .right_hand = .{ .cylinder = .{ .center = .fill(-3.23), .radius = 0, .half_height = 0 } },
                        .left_knee = .{ .cylinder = .{ .center = .fill(-4.12), .radius = 0, .half_height = 0 } },
                        .right_knee = .{ .cylinder = .{ .center = .fill(-4.22), .radius = 0, .half_height = 0 } },
                        .left_elbow = .{ .cylinder = .{ .center = .fill(-3.12), .radius = 0, .half_height = 0 } },
                        .right_elbow = .{ .cylinder = .{ .center = .fill(-3.22), .radius = 0, .half_height = 0 } },
                        .head = .{ .cylinder = .{ .center = .fill(-1), .radius = 0, .half_height = 0 } },
                        .left_shoulder = .{ .cylinder = .{ .center = .fill(-3.11), .radius = 0, .half_height = 0 } },
                        .right_shoulder = .{ .cylinder = .{ .center = .fill(-3.21), .radius = 0, .half_height = 0 } },
                        .upper_torso = .{ .cylinder = .{ .center = .fill(-3), .radius = 0, .half_height = 0 } },
                        .left_pelvis = .{ .cylinder = .{ .center = .fill(-4.11), .radius = 0, .half_height = 0 } },
                        .right_pelvis = .{ .cylinder = .{ .center = .fill(-4.21), .radius = 0, .half_height = 0 } },
                    }),
                },
            } };
            drawSkeletons(&settings, &frame, .identity);
        }

        fn testFunction(_: sdk.ui.TestContext) !void {
            try testing.expectEqual(30, ui.testing_shapes.getAll().len);
            const lines = [30]?*const ui.TestingShapes.Line{
                ui.testing_shapes.findLineWithWorldPoints(.fill(1), .fill(2), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(2), .fill(3), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(3), .fill(3.11), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(3), .fill(3.21), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(3.11), .fill(3.12), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(3.21), .fill(3.22), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(3.12), .fill(3.13), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(3.22), .fill(3.23), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(3), .fill(4), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(4), .fill(4.11), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(4), .fill(4.21), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(4.11), .fill(4.12), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(4.21), .fill(4.22), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(4.12), .fill(4.13), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(4.22), .fill(4.23), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-1), .fill(-2), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-2), .fill(-3), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-3), .fill(-3.11), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-3), .fill(-3.21), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-3.11), .fill(-3.12), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-3.21), .fill(-3.22), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-3.12), .fill(-3.13), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-3.22), .fill(-3.23), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-3), .fill(-4), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-4), .fill(-4.11), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-4), .fill(-4.21), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-4.11), .fill(-4.12), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-4.21), .fill(-4.22), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-4.12), .fill(-4.13), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-4.22), .fill(-4.23), 0.0001),
            };
            for (lines, 0..) |line, index| {
                try testing.expect(line != null);
                if (index < 15) {
                    try testing.expectEqual(.{ 0.1, 0.2, 0.3, 0.4 }, line.?.color.array);
                    try testing.expectEqual(1, line.?.thickness);
                } else {
                    try testing.expectEqual(.{ 0.5, 0.6, 0.7, 0.8 }, line.?.color.array);
                    try testing.expectEqual(2, line.?.thickness);
                }
            }
        }
    };
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should not draw lines for the player disabled in settings" {
    const Test = struct {
        fn guiFunction(_: sdk.ui.TestContext) !void {
            ui.testing_shapes.clear();

            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();

            const settings = model.PlayerSettings(model.SkeletonSettings){
                .mode = .id_separated,
                .players = .{ .{ .enabled = true }, .{ .enabled = false } },
            };
            const frame = model.Frame{ .players = .{
                .{
                    .collision_spheres = .init(.{
                        .neck = .{ .center = .fill(2), .radius = 0 },
                        .left_elbow = .{ .center = .fill(3.12), .radius = 0 },
                        .right_elbow = .{ .center = .fill(3.22), .radius = 0 },
                        .lower_torso = .{ .center = .fill(4), .radius = 0 },
                        .left_knee = .{ .center = .fill(4.12), .radius = 0 },
                        .right_knee = .{ .center = .fill(4.22), .radius = 0 },
                        .left_ankle = .{ .center = .fill(4.13), .radius = 0 },
                        .right_ankle = .{ .center = .fill(4.23), .radius = 0 },
                    }),
                    .hurt_cylinders = .init(.{
                        .left_ankle = .{ .cylinder = .{ .center = .fill(4.13), .radius = 0, .half_height = 0 } },
                        .right_ankle = .{ .cylinder = .{ .center = .fill(4.23), .radius = 0, .half_height = 0 } },
                        .left_hand = .{ .cylinder = .{ .center = .fill(3.13), .radius = 0, .half_height = 0 } },
                        .right_hand = .{ .cylinder = .{ .center = .fill(3.23), .radius = 0, .half_height = 0 } },
                        .left_knee = .{ .cylinder = .{ .center = .fill(4.12), .radius = 0, .half_height = 0 } },
                        .right_knee = .{ .cylinder = .{ .center = .fill(4.22), .radius = 0, .half_height = 0 } },
                        .left_elbow = .{ .cylinder = .{ .center = .fill(3.12), .radius = 0, .half_height = 0 } },
                        .right_elbow = .{ .cylinder = .{ .center = .fill(3.22), .radius = 0, .half_height = 0 } },
                        .head = .{ .cylinder = .{ .center = .fill(1), .radius = 0, .half_height = 0 } },
                        .left_shoulder = .{ .cylinder = .{ .center = .fill(3.11), .radius = 0, .half_height = 0 } },
                        .right_shoulder = .{ .cylinder = .{ .center = .fill(3.21), .radius = 0, .half_height = 0 } },
                        .upper_torso = .{ .cylinder = .{ .center = .fill(3), .radius = 0, .half_height = 0 } },
                        .left_pelvis = .{ .cylinder = .{ .center = .fill(4.11), .radius = 0, .half_height = 0 } },
                        .right_pelvis = .{ .cylinder = .{ .center = .fill(4.21), .radius = 0, .half_height = 0 } },
                    }),
                },
                .{
                    .collision_spheres = .init(.{
                        .neck = .{ .center = .fill(-2), .radius = 0 },
                        .left_elbow = .{ .center = .fill(-3.12), .radius = 0 },
                        .right_elbow = .{ .center = .fill(-3.22), .radius = 0 },
                        .lower_torso = .{ .center = .fill(-4), .radius = 0 },
                        .left_knee = .{ .center = .fill(-4.12), .radius = 0 },
                        .right_knee = .{ .center = .fill(-4.22), .radius = 0 },
                        .left_ankle = .{ .center = .fill(-4.13), .radius = 0 },
                        .right_ankle = .{ .center = .fill(-4.23), .radius = 0 },
                    }),
                    .hurt_cylinders = .init(.{
                        .left_ankle = .{ .cylinder = .{ .center = .fill(-4.13), .radius = 0, .half_height = 0 } },
                        .right_ankle = .{ .cylinder = .{ .center = .fill(-4.23), .radius = 0, .half_height = 0 } },
                        .left_hand = .{ .cylinder = .{ .center = .fill(-3.13), .radius = 0, .half_height = 0 } },
                        .right_hand = .{ .cylinder = .{ .center = .fill(-3.23), .radius = 0, .half_height = 0 } },
                        .left_knee = .{ .cylinder = .{ .center = .fill(-4.12), .radius = 0, .half_height = 0 } },
                        .right_knee = .{ .cylinder = .{ .center = .fill(-4.22), .radius = 0, .half_height = 0 } },
                        .left_elbow = .{ .cylinder = .{ .center = .fill(-3.12), .radius = 0, .half_height = 0 } },
                        .right_elbow = .{ .cylinder = .{ .center = .fill(-3.22), .radius = 0, .half_height = 0 } },
                        .head = .{ .cylinder = .{ .center = .fill(-1), .radius = 0, .half_height = 0 } },
                        .left_shoulder = .{ .cylinder = .{ .center = .fill(-3.11), .radius = 0, .half_height = 0 } },
                        .right_shoulder = .{ .cylinder = .{ .center = .fill(-3.21), .radius = 0, .half_height = 0 } },
                        .upper_torso = .{ .cylinder = .{ .center = .fill(-3), .radius = 0, .half_height = 0 } },
                        .left_pelvis = .{ .cylinder = .{ .center = .fill(-4.11), .radius = 0, .half_height = 0 } },
                        .right_pelvis = .{ .cylinder = .{ .center = .fill(-4.21), .radius = 0, .half_height = 0 } },
                    }),
                },
            } };
            drawSkeletons(&settings, &frame, .identity);
        }

        fn testFunction(_: sdk.ui.TestContext) !void {
            try testing.expectEqual(15, ui.testing_shapes.getAll().len);
            const enabled_lines = [15]?*const ui.TestingShapes.Line{
                ui.testing_shapes.findLineWithWorldPoints(.fill(1), .fill(2), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(2), .fill(3), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(3), .fill(3.11), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(3), .fill(3.21), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(3.11), .fill(3.12), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(3.21), .fill(3.22), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(3.12), .fill(3.13), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(3.22), .fill(3.23), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(3), .fill(4), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(4), .fill(4.11), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(4), .fill(4.21), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(4.11), .fill(4.12), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(4.21), .fill(4.22), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(4.12), .fill(4.13), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(4.22), .fill(4.23), 0.0001),
            };
            const disabled_lines = [15]?*const ui.TestingShapes.Line{
                ui.testing_shapes.findLineWithWorldPoints(.fill(-1), .fill(-2), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-2), .fill(-3), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-3), .fill(-3.11), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-3), .fill(-3.21), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-3.11), .fill(-3.12), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-3.21), .fill(-3.22), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-3.12), .fill(-3.13), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-3.22), .fill(-3.23), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-3), .fill(-4), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-4), .fill(-4.11), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-4), .fill(-4.21), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-4.11), .fill(-4.12), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-4.21), .fill(-4.22), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-4.12), .fill(-4.13), 0.0001),
                ui.testing_shapes.findLineWithWorldPoints(.fill(-4.22), .fill(-4.23), 0.0001),
            };
            for (enabled_lines) |line| {
                try testing.expect(line != null);
            }
            for (disabled_lines) |line| {
                try testing.expectEqual(null, line);
            }
        }
    };
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw with correct color depending on blocking property" {
    const Test = struct {
        var frame = model.Frame{ .players = .{
            .{
                .collision_spheres = .initFill(.{ .center = .fill(1), .radius = 0 }),
                .hurt_cylinders = .initFill(.{ .cylinder = .{ .center = .fill(1), .radius = 0, .half_height = 0 } }),
            },
            .{
                .collision_spheres = .initFill(.{ .center = .fill(-1), .radius = 0 }),
                .hurt_cylinders = .initFill(.{ .cylinder = .{ .center = .fill(-1), .radius = 0, .half_height = 0 } }),
            },
        } };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            ui.testing_shapes.clear();

            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();

            const settings = model.PlayerSettings(model.SkeletonSettings){
                .mode = .id_separated,
                .players = .{
                    .{
                        .enabled = true,
                        .colors = .init(.{
                            .not_blocking = .fill(0.1),
                            .neutral_blocking_mids = .fill(0.2),
                            .fully_blocking_mids = .fill(0.3),
                            .neutral_blocking_lows = .fill(0.4),
                            .fully_blocking_lows = .fill(0.5),
                        }),
                        .cant_move_alpha = 1.0,
                    },
                    .{
                        .enabled = true,
                        .colors = .init(.{
                            .not_blocking = .fill(0.6),
                            .neutral_blocking_mids = .fill(0.7),
                            .fully_blocking_mids = .fill(0.8),
                            .neutral_blocking_lows = .fill(0.9),
                            .fully_blocking_lows = .fill(1.0),
                        }),
                        .cant_move_alpha = 1.0,
                    },
                },
            };
            drawSkeletons(&settings, &frame, .identity);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            frame.players[0].blocking = null;
            frame.players[1].blocking = .not_blocking;
            ctx.yield(1);
            var player_1_line = ui.testing_shapes.findLineWithWorldPoints(.fill(1), .fill(1), 0.0001);
            var player_2_line = ui.testing_shapes.findLineWithWorldPoints(.fill(-1), .fill(-1), 0.0001);
            try testing.expect(player_1_line != null);
            try testing.expect(player_2_line != null);
            try testing.expectEqual(sdk.math.Vec4.fill(0.1), player_1_line.?.color);
            try testing.expectEqual(sdk.math.Vec4.fill(0.6), player_2_line.?.color);

            frame.players[0].blocking = .neutral_blocking_mids;
            frame.players[1].blocking = .fully_blocking_mids;
            ctx.yield(1);
            player_1_line = ui.testing_shapes.findLineWithWorldPoints(.fill(1), .fill(1), 0.0001);
            player_2_line = ui.testing_shapes.findLineWithWorldPoints(.fill(-1), .fill(-1), 0.0001);
            try testing.expect(player_1_line != null);
            try testing.expect(player_2_line != null);
            try testing.expectEqual(sdk.math.Vec4.fill(0.2), player_1_line.?.color);
            try testing.expectEqual(sdk.math.Vec4.fill(0.8), player_2_line.?.color);

            frame.players[0].blocking = .neutral_blocking_lows;
            frame.players[1].blocking = .fully_blocking_lows;
            ctx.yield(1);
            player_1_line = ui.testing_shapes.findLineWithWorldPoints(.fill(1), .fill(1), 0.0001);
            player_2_line = ui.testing_shapes.findLineWithWorldPoints(.fill(-1), .fill(-1), 0.0001);
            try testing.expect(player_1_line != null);
            try testing.expect(player_2_line != null);
            try testing.expectEqual(sdk.math.Vec4.fill(0.4), player_1_line.?.color);
            try testing.expectEqual(sdk.math.Vec4.fill(1.0), player_2_line.?.color);
        }
    };
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw with correct alpha depending on can move property" {
    const Test = struct {
        fn guiFunction(_: sdk.ui.TestContext) !void {
            ui.testing_shapes.clear();

            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();

            const settings = model.PlayerSettings(model.SkeletonSettings){
                .mode = .id_separated,
                .players = .{
                    .{
                        .enabled = true,
                        .colors = .initFill(.fromArray(.{ 0.1, 0.2, 0.3, 0.4 })),
                        .thickness = 1,
                        .cant_move_alpha = 0.1,
                    },
                    .{
                        .enabled = true,
                        .colors = .initFill(.fromArray(.{ 0.5, 0.6, 0.7, 0.8 })),
                        .thickness = 2,
                        .cant_move_alpha = 0.2,
                    },
                },
            };
            const frame = model.Frame{ .players = .{
                .{
                    .collision_spheres = .initFill(.{ .center = .fill(1), .radius = 0 }),
                    .hurt_cylinders = .initFill(.{ .cylinder = .{ .center = .fill(1), .radius = 0, .half_height = 0 } }),
                    .can_move = true,
                },
                .{
                    .collision_spheres = .initFill(.{ .center = .fill(-1), .radius = 0 }),
                    .hurt_cylinders = .initFill(.{ .cylinder = .{ .center = .fill(-1), .radius = 0, .half_height = 0 } }),
                    .can_move = false,
                },
            } };
            drawSkeletons(&settings, &frame, .identity);
        }

        fn testFunction(_: sdk.ui.TestContext) !void {
            const player_1_line = ui.testing_shapes.findLineWithWorldPoints(.fill(1), .fill(1), 0.0001);
            const player_2_line = ui.testing_shapes.findLineWithWorldPoints(.fill(-1), .fill(-1), 0.0001);
            try testing.expect(player_1_line != null);
            try testing.expect(player_2_line != null);
            try testing.expectApproxEqAbs(0.4, player_1_line.?.color.a(), 0.0001);
            try testing.expectApproxEqAbs(0.16, player_2_line.?.color.a(), 0.0001);
        }
    };
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
