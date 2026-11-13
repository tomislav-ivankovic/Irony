const std = @import("std");
const sdk = @import("../../sdk/root.zig");

pub const Camera = struct {
    position: sdk.math.Vec3,
    pitch: f32,
    yaw: f32,
    roll: f32,
    horizontal_fov: f32 = 65.0,

    const Self = @This();
    const max_pitch = 0.5 * std.math.pi - 0.001;

    // Translation is in camera-local axes: x forward, y right, z up.
    pub fn translateLocal(self: *Self, local_translation: sdk.math.Vec3) void {
        const world_translation = local_translation
            .rotateX(-self.roll)
            .rotateY(self.pitch)
            .rotateZ(self.yaw);
        self.position = self.position.add(world_translation);
    }

    pub fn rotatePitchYaw(self: *Self, pitch_delta: f32, yaw_delta: f32) void {
        self.pitch = std.math.clamp(self.pitch + pitch_delta, -max_pitch, max_pitch);
        self.yaw = self.yaw + yaw_delta;
    }

    pub fn setVerticalFov(self: *Self, vertical_fov: f32, aspect_ratio: f32) void {
        self.horizontal_fov = 2 * std.math.atan(std.math.tan(0.5 * vertical_fov) * aspect_ratio);
    }
};

const testing = std.testing;

test "translateLocal should translate in camera local axes" {
    var camera = Camera{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 0,
        .yaw = 0.5 * std.math.pi,
        .roll = 0,
    };
    camera.translateLocal(.fromArray(.{ 10, 0, 0 }));
    try testing.expectApproxEqAbs(1, camera.position.x(), 0.0001);
    try testing.expectApproxEqAbs(12, camera.position.y(), 0.0001);
    try testing.expectApproxEqAbs(3, camera.position.z(), 0.0001);

    camera.translateLocal(.fromArray(.{ 0, 10, 0 }));
    try testing.expectApproxEqAbs(-9, camera.position.x(), 0.0001);
    try testing.expectApproxEqAbs(12, camera.position.y(), 0.0001);
    try testing.expectApproxEqAbs(3, camera.position.z(), 0.0001);

    camera.translateLocal(.fromArray(.{ 0, 0, 10 }));
    try testing.expectApproxEqAbs(-9, camera.position.x(), 0.0001);
    try testing.expectApproxEqAbs(12, camera.position.y(), 0.0001);
    try testing.expectApproxEqAbs(13, camera.position.z(), 0.0001);
}

test "translateLocal should translate forward in the direction the camera is pitched" {
    var camera = Camera{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 0.5 * std.math.pi,
        .yaw = 0,
        .roll = 0,
    };
    camera.translateLocal(.fromArray(.{ 10, 0, 0 }));
    try testing.expectApproxEqAbs(1, camera.position.x(), 0.0001);
    try testing.expectApproxEqAbs(2, camera.position.y(), 0.0001);
    try testing.expectApproxEqAbs(13, camera.position.z(), 0.0001);
}

test "rotatePitchYaw should add to pitch and yaw and leave roll unchanged" {
    var camera = Camera{
        .position = .zero,
        .pitch = 0.1,
        .yaw = 0.2,
        .roll = 0.3,
    };
    camera.rotatePitchYaw(0.4, 0.5);
    try testing.expectApproxEqAbs(0.5, camera.pitch, 0.0001);
    try testing.expectApproxEqAbs(0.7, camera.yaw, 0.0001);
    try testing.expectApproxEqAbs(0.3, camera.roll, 0.0001);
}

test "rotatePitchYaw should clamp pitch to just short of straight up or down" {
    var camera = Camera{
        .position = .zero,
        .pitch = 0,
        .yaw = 0,
        .roll = 0,
    };
    camera.rotatePitchYaw(10, 0);
    try testing.expect(camera.pitch < 0.5 * std.math.pi);
    try testing.expect(camera.pitch > 0.49 * std.math.pi);

    camera.rotatePitchYaw(-20, 0);
    try testing.expect(camera.pitch > -0.5 * std.math.pi);
    try testing.expect(camera.pitch < -0.49 * std.math.pi);
}

test "setVerticalFov should set horizontal fov from vertical fov and aspect ratio" {
    var camera = Camera{
        .position = .zero,
        .pitch = 0,
        .yaw = 0,
        .roll = 0,
        .horizontal_fov = 1,
    };
    camera.setVerticalFov(0.25 * std.math.pi, 1);
    try testing.expectApproxEqAbs(0.25 * std.math.pi, camera.horizontal_fov, 0.0001);

    camera.setVerticalFov(2 * std.math.atan(@as(f32, 0.5)), 2);
    try testing.expectApproxEqAbs(0.5 * std.math.pi, camera.horizontal_fov, 0.0001);
}
