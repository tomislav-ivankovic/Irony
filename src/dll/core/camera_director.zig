const std = @import("std");
const model = @import("../model/root.zig");

pub const CameraDirector = struct {
    mode: Mode = .live,

    const Self = @This();
    pub const Mode = union(enum) {
        live: void,
        recording: void,
        free_look: model.Camera,
    };

    pub fn startFreeLook(self: *Self, frame_maybe: ?*const model.Frame) void {
        const frame = frame_maybe orelse return;
        const camera = frame.camera orelse return;
        self.mode = .{ .free_look = camera };
    }

    pub fn update(
        self: *Self,
        source_maybe: ?model.Source,
        camera_override: *?model.Camera,
        frame_maybe: ?*const model.Frame,
    ) void {
        if (!isAllowed(source_maybe)) {
            self.mode = .live;
        }
        camera_override.* = switch (self.mode) {
            .live => null,
            .recording => if (frame_maybe) |frame| frame.camera else null,
            .free_look => |camera| camera,
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

test "should switch mode to live and clear camera override when source is live game" {
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
    try testing.expectEqual(CameraDirector.Mode.live, camera_director.mode);
    try testing.expectEqual(null, camera_override);
}

test "should switch mode to live and clear camera override when source is unknown" {
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
    try testing.expectEqual(CameraDirector.Mode.live, camera_director.mode);
    try testing.expectEqual(null, camera_override);
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
    try testing.expectEqual(CameraDirector.Mode.live, camera_director.mode);
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
    try testing.expectEqual(CameraDirector.Mode{ .free_look = camera }, camera_director.mode);
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
    var camera_director = CameraDirector{ .mode = .{ .free_look = camera } };
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

test "should switch mode to live and clear camera override when mode is free look and source is live game" {
    const camera = model.Camera{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 4,
        .yaw = 5,
        .roll = 6,
        .horizontal_fov = 7,
    };
    var camera_director = CameraDirector{ .mode = .{ .free_look = camera } };
    var camera_override: ?model.Camera = camera;
    camera_director.update(.live_game, &camera_override, &.{ .camera = camera });
    try testing.expectEqual(CameraDirector.Mode.live, camera_director.mode);
    try testing.expectEqual(null, camera_override);
}
