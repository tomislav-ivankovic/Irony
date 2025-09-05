const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("../ui/root.zig");

const colors = std.EnumArray(model.Blocking, sdk.math.Vec4).init(.{
    .not_blocking = .fromArray(.{ 1.0, 1.0, 1.0, 1.0 }),
    .neutral_blocking_mids = .fromArray(.{ 1.0, 1.0, 0.75, 1.0 }),
    .fully_blocking_mids = .fromArray(.{ 1.0, 1.0, 0.5, 1.0 }),
    .neutral_blocking_lows = .fromArray(.{ 0.75, 0.875, 1.0, 1.0 }),
    .fully_blocking_lows = .fromArray(.{ 0.5, 0.75, 1.0, 1.0 }),
});
const thickness = 2.0;
const cant_move_alpha = 0.5;

pub fn drawSkeletons(frame: *const model.Frame, matrix: sdk.math.Mat4) void {
    for (&frame.players) |*player| {
        const skeleton: *const model.Skeleton = if (player.skeleton) |*s| s else continue;
        const blocking = if (player.blocking) |b| b else .not_blocking;
        const can_move = if (player.can_move) |c| c else true;
        var color = colors.get(blocking);
        if (!can_move) {
            color.asColor().a *= cant_move_alpha;
        }
        drawSkeleton(skeleton, color, matrix);
    }
}

fn drawSkeleton(skeleton: *const model.Skeleton, color: sdk.math.Vec4, matrix: sdk.math.Mat4) void {
    drawBone(matrix, color, skeleton, .head, .neck);
    drawBone(matrix, color, skeleton, .neck, .upper_torso);
    drawBone(matrix, color, skeleton, .upper_torso, .left_shoulder);
    drawBone(matrix, color, skeleton, .upper_torso, .right_shoulder);
    drawBone(matrix, color, skeleton, .left_shoulder, .left_elbow);
    drawBone(matrix, color, skeleton, .right_shoulder, .right_elbow);
    drawBone(matrix, color, skeleton, .left_elbow, .left_hand);
    drawBone(matrix, color, skeleton, .right_elbow, .right_hand);
    drawBone(matrix, color, skeleton, .upper_torso, .lower_torso);
    drawBone(matrix, color, skeleton, .lower_torso, .left_pelvis);
    drawBone(matrix, color, skeleton, .lower_torso, .right_pelvis);
    drawBone(matrix, color, skeleton, .left_pelvis, .left_knee);
    drawBone(matrix, color, skeleton, .right_pelvis, .right_knee);
    drawBone(matrix, color, skeleton, .left_knee, .left_ankle);
    drawBone(matrix, color, skeleton, .right_knee, .right_ankle);
}

fn drawBone(
    matrix: sdk.math.Mat4,
    color: sdk.math.Vec4,
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
