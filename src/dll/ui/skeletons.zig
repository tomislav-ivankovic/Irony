const std = @import("std");
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
