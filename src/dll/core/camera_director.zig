const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

pub const CameraDirector = struct {
    mode: Mode = .game,

    const Self = @This();
    pub const Mode = union(enum) {
        game: void,
        recording: void,
        free_look: FreeLook,
    };
    pub const FreeLook = struct {
        camera: model.Camera,

        const max_pitch = 0.5 * std.math.pi - 0.001;

        // Translation is in camera-local axes: x forward, y right, z up.
        pub fn move(self: *FreeLook, local_translation: sdk.math.Vec3) void {
            const world_translation = local_translation
                .rotateX(-self.camera.roll)
                .rotateY(self.camera.pitch)
                .rotateZ(self.camera.yaw);
            self.camera.position = self.camera.position.add(world_translation);
        }

        pub fn rotate(self: *FreeLook, pitch_delta: f32, yaw_delta: f32) void {
            self.camera.pitch = std.math.clamp(self.camera.pitch + pitch_delta, -max_pitch, max_pitch);
            self.camera.yaw = self.camera.yaw + yaw_delta;
        }

        pub fn setVerticalFov(self: *FreeLook, vertical_fov: f32, aspect_ratio: f32) void {
            self.camera.horizontal_fov = 2 * std.math.atan(std.math.tan(0.5 * vertical_fov) * aspect_ratio);
        }
    };

    pub fn startFreeLook(self: *Self, frame_maybe: ?*const model.Frame) void {
        const frame = frame_maybe orelse return;
        const camera = frame.camera orelse return;
        self.mode = .{ .free_look = .{ .camera = camera } };
    }

    pub fn update(
        self: *Self,
        source_maybe: ?model.Source,
        camera_override: *?model.Camera,
        frame_maybe: ?*const model.Frame,
    ) void {
        if (!isAllowed(source_maybe)) {
            self.mode = .game;
        }
        camera_override.* = switch (self.mode) {
            .game => null,
            .recording => if (frame_maybe) |frame| frame.camera else null,
            .free_look => |*free_look| free_look.camera,
        };
    }

    fn isAllowed(source_maybe: ?model.Source) bool {
        const source = source_maybe orelse return false;
        return switch (source) {
            .practice, .replay_loading, .replay_playback => true,
            .live_game => false,
        };
    }
};

const testing = std.testing;

test "should set camera override to frame camera when mode is recording and source is practice or replay" {
    const camera = model.Camera{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 4,
        .yaw = 5,
        .roll = 6,
        .horizontal_fov = 7,
    };
    var camera_director = CameraDirector{ .mode = .recording };
    var camera_override: ?model.Camera = null;
    const frame = model.Frame{ .camera = camera };

    camera_director.update(.practice, &camera_override, &frame);
    try testing.expectEqual(CameraDirector.Mode.recording, camera_director.mode);
    try testing.expectEqual(camera, camera_override);

    camera_override = null;
    camera_director.update(.replay_loading, &camera_override, &frame);
    try testing.expectEqual(CameraDirector.Mode.recording, camera_director.mode);
    try testing.expectEqual(camera, camera_override);

    camera_override = null;
    camera_director.update(.replay_playback, &camera_override, &frame);
    try testing.expectEqual(CameraDirector.Mode.recording, camera_director.mode);
    try testing.expectEqual(camera, camera_override);
}

test "should switch mode to game and clear camera override when source is live game" {
    const camera = model.Camera{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 4,
        .yaw = 5,
        .roll = 6,
        .horizontal_fov = 7,
    };
    var camera_director = CameraDirector{ .mode = .recording };
    var camera_override: ?model.Camera = camera;
    camera_director.update(.live_game, &camera_override, &.{ .camera = camera });
    try testing.expectEqual(CameraDirector.Mode.game, camera_director.mode);
    try testing.expectEqual(null, camera_override);
}

test "should switch mode to game and clear camera override when source is unknown" {
    const camera = model.Camera{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 4,
        .yaw = 5,
        .roll = 6,
        .horizontal_fov = 7,
    };
    var camera_director = CameraDirector{ .mode = .recording };
    var camera_override: ?model.Camera = camera;
    camera_director.update(null, &camera_override, &.{ .camera = camera });
    try testing.expectEqual(CameraDirector.Mode.game, camera_director.mode);
    try testing.expectEqual(null, camera_override);
}

test "should clear camera override when mode is game" {
    const camera = model.Camera{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 4,
        .yaw = 5,
        .roll = 6,
        .horizontal_fov = 7,
    };
    var camera_director = CameraDirector{ .mode = .game };
    var camera_override: ?model.Camera = camera;
    camera_director.update(.practice, &camera_override, &.{ .camera = camera });
    try testing.expectEqual(CameraDirector.Mode.game, camera_director.mode);
    try testing.expectEqual(null, camera_override);
}

test "should clear camera override when mode is recording but there is no frame or frame camera" {
    const camera = model.Camera{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 4,
        .yaw = 5,
        .roll = 6,
        .horizontal_fov = 7,
    };
    var camera_director = CameraDirector{ .mode = .recording };
    var camera_override: ?model.Camera = camera;
    camera_director.update(.practice, &camera_override, null);
    try testing.expectEqual(null, camera_override);

    camera_override = camera;
    camera_director.update(.practice, &camera_override, &.{ .camera = null });
    try testing.expectEqual(null, camera_override);
}

test "should start free look from frame camera" {
    const camera = model.Camera{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 4,
        .yaw = 5,
        .roll = 6,
        .horizontal_fov = 7,
    };
    var camera_director = CameraDirector{ .mode = .recording };
    camera_director.startFreeLook(&.{ .camera = camera });
    try testing.expectEqual(CameraDirector.Mode{ .free_look = .{ .camera = camera } }, camera_director.mode);
}

test "should not start free look when there is no frame or frame camera" {
    var camera_director = CameraDirector{ .mode = .recording };
    camera_director.startFreeLook(null);
    try testing.expectEqual(CameraDirector.Mode.recording, camera_director.mode);
    camera_director.startFreeLook(&.{ .camera = null });
    try testing.expectEqual(CameraDirector.Mode.recording, camera_director.mode);
}

test "should set camera override to free look camera when mode is free look and source is practice or replay" {
    const camera = model.Camera{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 4,
        .yaw = 5,
        .roll = 6,
        .horizontal_fov = 7,
    };
    const frame_camera = model.Camera{
        .position = .fromArray(.{ 8, 9, 10 }),
        .pitch = 11,
        .yaw = 12,
        .roll = 13,
        .horizontal_fov = 14,
    };
    var camera_director = CameraDirector{ .mode = .{ .free_look = .{ .camera = camera } } };
    var camera_override: ?model.Camera = null;
    const frame = model.Frame{ .camera = frame_camera };

    camera_director.update(.practice, &camera_override, &frame);
    try testing.expectEqual(camera, camera_override);

    camera_override = null;
    camera_director.update(.replay_loading, &camera_override, &frame);
    try testing.expectEqual(camera, camera_override);

    camera_override = null;
    camera_director.update(.replay_playback, &camera_override, &frame);
    try testing.expectEqual(camera, camera_override);
}

test "should switch mode to game and clear camera override when mode is free look and source is live game" {
    const camera = model.Camera{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 4,
        .yaw = 5,
        .roll = 6,
        .horizontal_fov = 7,
    };
    var camera_director = CameraDirector{ .mode = .{ .free_look = .{ .camera = camera } } };
    var camera_override: ?model.Camera = camera;
    camera_director.update(.live_game, &camera_override, &.{ .camera = camera });
    try testing.expectEqual(CameraDirector.Mode.game, camera_director.mode);
    try testing.expectEqual(null, camera_override);
}

test "should move free look camera in camera local axes" {
    var free_look = CameraDirector.FreeLook{ .camera = .{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 0,
        .yaw = 0.5 * std.math.pi,
        .roll = 0,
    } };
    free_look.move(.fromArray(.{ 10, 0, 0 }));
    try testing.expectApproxEqAbs(1, free_look.camera.position.x(), 0.0001);
    try testing.expectApproxEqAbs(12, free_look.camera.position.y(), 0.0001);
    try testing.expectApproxEqAbs(3, free_look.camera.position.z(), 0.0001);

    free_look.move(.fromArray(.{ 0, 10, 0 }));
    try testing.expectApproxEqAbs(-9, free_look.camera.position.x(), 0.0001);
    try testing.expectApproxEqAbs(12, free_look.camera.position.y(), 0.0001);
    try testing.expectApproxEqAbs(3, free_look.camera.position.z(), 0.0001);

    free_look.move(.fromArray(.{ 0, 0, 10 }));
    try testing.expectApproxEqAbs(-9, free_look.camera.position.x(), 0.0001);
    try testing.expectApproxEqAbs(12, free_look.camera.position.y(), 0.0001);
    try testing.expectApproxEqAbs(13, free_look.camera.position.z(), 0.0001);
}

test "should move free look camera forward in the direction the camera is pitched" {
    var free_look = CameraDirector.FreeLook{ .camera = .{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 0.5 * std.math.pi,
        .yaw = 0,
        .roll = 0,
    } };
    free_look.move(.fromArray(.{ 10, 0, 0 }));
    try testing.expectApproxEqAbs(1, free_look.camera.position.x(), 0.0001);
    try testing.expectApproxEqAbs(2, free_look.camera.position.y(), 0.0001);
    try testing.expectApproxEqAbs(13, free_look.camera.position.z(), 0.0001);
}

test "should rotate free look camera pitch and yaw" {
    var free_look = CameraDirector.FreeLook{ .camera = .{
        .position = .zero,
        .pitch = 0.1,
        .yaw = 0.2,
        .roll = 0.3,
    } };
    free_look.rotate(0.4, 0.5);
    try testing.expectApproxEqAbs(0.5, free_look.camera.pitch, 0.0001);
    try testing.expectApproxEqAbs(0.7, free_look.camera.yaw, 0.0001);
    try testing.expectApproxEqAbs(0.3, free_look.camera.roll, 0.0001);
}

test "should clamp free look camera pitch to just short of straight up or down" {
    var free_look = CameraDirector.FreeLook{ .camera = .{
        .position = .zero,
        .pitch = 0,
        .yaw = 0,
        .roll = 0,
    } };
    free_look.rotate(10, 0);
    try testing.expect(free_look.camera.pitch < 0.5 * std.math.pi);
    try testing.expect(free_look.camera.pitch > 0.49 * std.math.pi);

    free_look.rotate(-20, 0);
    try testing.expect(free_look.camera.pitch > -0.5 * std.math.pi);
    try testing.expect(free_look.camera.pitch < -0.49 * std.math.pi);
}

test "should set free look camera horizontal fov from vertical fov and aspect ratio" {
    var free_look = CameraDirector.FreeLook{ .camera = .{
        .position = .zero,
        .pitch = 0,
        .yaw = 0,
        .roll = 0,
        .horizontal_fov = 1,
    } };
    free_look.setVerticalFov(0.25 * std.math.pi, 1);
    try testing.expectApproxEqAbs(0.25 * std.math.pi, free_look.camera.horizontal_fov, 0.0001);

    free_look.setVerticalFov(2 * std.math.atan(@as(f32, 0.5)), 2);
    try testing.expectApproxEqAbs(0.5 * std.math.pi, free_look.camera.horizontal_fov, 0.0001);
}
