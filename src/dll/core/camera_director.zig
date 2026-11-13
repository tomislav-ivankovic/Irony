const std = @import("std");
const model = @import("../model/root.zig");

pub const CameraDirector = struct {
    mode: Mode = .live,
    free_look_camera: ?model.Camera = null,
    is_allowed: bool = false,

    const Self = @This();
    pub const Mode = enum {
        live,
        recording,
        free_look,
    };

    pub fn update(
        self: *Self,
        source_maybe: ?model.Source,
        camera_override: *?model.Camera,
        frame_maybe: ?*const model.Frame,
    ) void {
        self.is_allowed = isAllowed(source_maybe);
        if (!self.is_allowed) {
            camera_override.* = null;
            return;
        }
        const frame_camera = if (frame_maybe) |frame| frame.camera else null;
        if (self.mode != .free_look or self.free_look_camera == null) {
            self.free_look_camera = frame_camera;
        }
        camera_override.* = switch (self.mode) {
            .live => null,
            .recording => frame_camera,
            .free_look => self.free_look_camera,
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
    try testing.expectEqual(camera, camera_override);

    camera_override = null;
    camera_director.update(.replay_loading, &camera_override, &frame);
    try testing.expectEqual(camera, camera_override);

    camera_override = null;
    camera_director.update(.replay_playback, &camera_override, &frame);
    try testing.expectEqual(camera, camera_override);
}

test "should clear camera override and keep mode and free look camera when source is live game or unknown" {
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
    var camera_director = CameraDirector{ .mode = .free_look, .free_look_camera = camera };
    var camera_override: ?model.Camera = camera;

    camera_director.update(.live_game, &camera_override, &.{ .camera = frame_camera });
    try testing.expectEqual(null, camera_override);
    try testing.expectEqual(CameraDirector.Mode.free_look, camera_director.mode);
    try testing.expectEqual(camera, camera_director.free_look_camera);

    camera_override = camera;
    camera_director.update(null, &camera_override, &.{ .camera = frame_camera });
    try testing.expectEqual(null, camera_override);
    try testing.expectEqual(CameraDirector.Mode.free_look, camera_director.mode);
    try testing.expectEqual(camera, camera_director.free_look_camera);
}

test "should set is allowed only when source is practice or replay" {
    var camera_director = CameraDirector{};
    var camera_override: ?model.Camera = null;

    camera_director.update(.practice, &camera_override, null);
    try testing.expectEqual(true, camera_director.is_allowed);
    camera_director.update(.live_game, &camera_override, null);
    try testing.expectEqual(false, camera_director.is_allowed);
    camera_director.update(.replay_loading, &camera_override, null);
    try testing.expectEqual(true, camera_director.is_allowed);
    camera_director.update(null, &camera_override, null);
    try testing.expectEqual(false, camera_director.is_allowed);
    camera_director.update(.replay_playback, &camera_override, null);
    try testing.expectEqual(true, camera_director.is_allowed);
}

test "should clear camera override when mode is live" {
    const camera = model.Camera{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 4,
        .yaw = 5,
        .roll = 6,
        .horizontal_fov = 7,
    };
    var camera_director = CameraDirector{ .mode = .live };
    var camera_override: ?model.Camera = camera;
    camera_director.update(.practice, &camera_override, &.{ .camera = camera });
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

test "should keep setting free look camera to frame camera while mode is not free look" {
    const camera_1 = model.Camera{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 4,
        .yaw = 5,
        .roll = 6,
        .horizontal_fov = 7,
    };
    const camera_2 = model.Camera{
        .position = .fromArray(.{ 8, 9, 10 }),
        .pitch = 11,
        .yaw = 12,
        .roll = 13,
        .horizontal_fov = 14,
    };
    var camera_director = CameraDirector{ .mode = .live };
    var camera_override: ?model.Camera = null;

    camera_director.update(.practice, &camera_override, &.{ .camera = camera_1 });
    try testing.expectEqual(camera_1, camera_director.free_look_camera);

    camera_director.mode = .recording;
    camera_director.update(.practice, &camera_override, &.{ .camera = camera_2 });
    try testing.expectEqual(camera_2, camera_director.free_look_camera);

    camera_director.update(.practice, &camera_override, &.{ .camera = null });
    try testing.expectEqual(null, camera_director.free_look_camera);
}

test "should set camera override to free look camera and not reset it when mode is free look" {
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
    var camera_director = CameraDirector{ .mode = .free_look, .free_look_camera = camera };
    var camera_override: ?model.Camera = null;
    const frame = model.Frame{ .camera = frame_camera };

    camera_director.update(.practice, &camera_override, &frame);
    try testing.expectEqual(camera, camera_override);
    try testing.expectEqual(camera, camera_director.free_look_camera);

    camera_override = null;
    camera_director.update(.replay_loading, &camera_override, &frame);
    try testing.expectEqual(camera, camera_override);

    camera_override = null;
    camera_director.update(.replay_playback, &camera_override, &frame);
    try testing.expectEqual(camera, camera_override);
}

test "should set free look camera to frame camera when mode is free look but there is no free look camera yet" {
    const camera = model.Camera{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 4,
        .yaw = 5,
        .roll = 6,
        .horizontal_fov = 7,
    };
    var camera_director = CameraDirector{ .mode = .free_look, .free_look_camera = null };
    var camera_override: ?model.Camera = null;

    camera_director.update(.practice, &camera_override, &.{ .camera = null });
    try testing.expectEqual(null, camera_director.free_look_camera);
    try testing.expectEqual(null, camera_override);

    camera_director.update(.practice, &camera_override, &.{ .camera = camera });
    try testing.expectEqual(camera, camera_director.free_look_camera);
    try testing.expectEqual(camera, camera_override);
}
