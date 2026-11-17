const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const core = @import("../core/root.zig");
const model = @import("../model/root.zig");

pub const FreeLookCamera = struct {
    effectively_down_keys: std.EnumSet(MovementKey) = .empty,
    velocity: sdk.math.Vec3 = .zero,

    const Self = @This();
    const MovementKey = enum {
        forward,
        backward,
        left,
        right,
        up,
        down,

        fn toImGuiKey(self: @This()) imgui.ImGuiKey {
            return switch (self) {
                .forward => imgui.ImGuiKey_W,
                .backward => imgui.ImGuiKey_S,
                .left => imgui.ImGuiKey_A,
                .right => imgui.ImGuiKey_D,
                .up => imgui.ImGuiKey_Space,
                .down => imgui.ImGuiKey_LeftCtrl,
            };
        }
    };

    pub fn drawTooltip() void {
        imgui.igSetTooltip(
            \\Right Mouse Button: Look Around
            \\Right Mouse Button + W, A, S, D: Move
            \\Right Mouse Button + Left Ctrl, Space: Move Down, Up
            \\Right Mouse Button + Left Shift: Move Faster
            ,
        );
    }

    pub fn processInput(
        self: *Self,
        camera_director: *core.CameraDirector,
        delta_time: f32,
        settings: *const model.FreeLookCameraSettings,
    ) void {
        if (camera_director.mode != .free_look or !camera_director.is_allowed) {
            self.effectively_down_keys = .empty;
            self.velocity = .zero;
            return;
        }
        const camera = if (camera_director.free_look_camera) |*camera| camera else {
            self.effectively_down_keys = .empty;
            self.velocity = .zero;
            return;
        };
        const io = imgui.igGetIO_Nil();
        const display_size = io.*.DisplaySize;
        if (display_size.x > 0 and display_size.y > 0) {
            camera.setVerticalFov(settings.vertical_fov, display_size.x / display_size.y);
        }

        const is_looking = imgui.igIsMouseDown_Nil(imgui.ImGuiMouseButton_Right) and
            !io.*.MouseDownOwned[imgui.ImGuiMouseButton_Right];
        if (is_looking) {
            imgui.igSetNextFrameWantCaptureMouse(true);
            routeMovementKeys();
            self.updateEffectivelyDownKeys();
            camera.rotatePitchYaw(
                -io.*.MouseDelta.y * settings.look_sensitivity,
                io.*.MouseDelta.x * settings.look_sensitivity,
            );
        } else {
            self.effectively_down_keys = .empty;
        }

        const is_fast = imgui.igIsKeyDown_Nil(imgui.ImGuiKey_LeftShift);
        const multiplier = if (is_fast) settings.speed_multiplier else 1;
        const target_direction = self.getTargetDirection(camera);
        const target_speed = multiplier * settings.speed;
        const acceleration_step = getVelocityStep(target_speed, settings.acceleration_time, delta_time);
        const deceleration_step = getVelocityStep(target_speed, settings.deceleration_time, delta_time);

        const old_velocity = self.velocity;
        var parallel_speed = self.velocity.dot(target_direction);
        const perpendicular_velocity = self.velocity.subtract(target_direction.scale(parallel_speed));
        if (parallel_speed > target_speed) {
            parallel_speed = @max(parallel_speed - deceleration_step, target_speed);
        } else {
            if (parallel_speed < 0) {
                parallel_speed = @min(parallel_speed + deceleration_step, 0);
            }
            parallel_speed = @min(parallel_speed + acceleration_step, target_speed);
        }
        self.velocity = target_direction.scale(parallel_speed).add(decelerate(perpendicular_velocity, deceleration_step));
        const average_velocity = old_velocity.add(self.velocity).scale(0.5);
        camera.position = camera.position.add(average_velocity.scale(delta_time));
    }

    fn getVelocityStep(speed: f32, time: f32, delta_time: f32) f32 {
        if (time <= 0) {
            return std.math.inf(f32);
        }
        return speed / time * delta_time;
    }

    fn decelerate(velocity: sdk.math.Vec3, deceleration_step: f32) sdk.math.Vec3 {
        const speed = velocity.length();
        if (speed <= deceleration_step) {
            return .zero;
        }
        return velocity.scale((speed - deceleration_step) / speed);
    }

    fn getTargetDirection(self: *const Self, camera: *const model.Camera) sdk.math.Vec3 {
        var direction = sdk.math.Vec3.zero;
        const keys = &self.effectively_down_keys;
        if (keys.contains(.forward)) direction = direction.add(.plus_x);
        if (keys.contains(.backward)) direction = direction.add(.minus_x);
        if (keys.contains(.right)) direction = direction.add(.plus_y);
        if (keys.contains(.left)) direction = direction.add(.minus_y);
        if (keys.contains(.up)) direction = direction.add(.plus_z);
        if (keys.contains(.down)) direction = direction.add(.minus_z);
        if (direction.isZero(0)) {
            return .zero;
        }
        return camera.localToWorldTranslation(direction.normalize());
    }

    fn updateEffectivelyDownKeys(self: *Self) void {
        for (std.enums.values(MovementKey)) |key| {
            const imgui_key = key.toImGuiKey();
            if (imgui.igIsKeyPressed_Bool(imgui_key, false)) {
                self.effectively_down_keys.insert(key);
            }
            if (!imgui.igIsKeyDown_Nil(imgui_key)) {
                self.effectively_down_keys.remove(key);
            }
        }
    }

    fn routeMovementKeys() void {
        const owner_id = imgui.igGetID_Str("free_look_camera");
        const flags = imgui.ImGuiInputFlags_RouteGlobal |
            imgui.ImGuiInputFlags_RouteOverFocused |
            imgui.ImGuiInputFlags_RouteOverActive;
        const keys = [_]imgui.ImGuiKeyChord{
            imgui.ImGuiKey_W,
            imgui.ImGuiKey_A,
            imgui.ImGuiKey_S,
            imgui.ImGuiKey_D,
            imgui.ImGuiKey_Space,
        };
        const mods = [_]imgui.ImGuiKeyChord{
            0,
            imgui.ImGuiMod_Ctrl,
            imgui.ImGuiMod_Shift,
            imgui.ImGuiMod_Ctrl | imgui.ImGuiMod_Shift,
        };
        for (keys) |key| {
            for (mods) |mod| {
                _ = imgui.igShortcut_ID(key | mod, flags, owner_id);
            }
        }
    }
};

const testing = std.testing;

test "should rotate when dragging with right mouse button outside of windows" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .acceleration_time = 0,
            .deceleration_time = 0,
            .look_sensitivity = 0.005,
        };
        var free_look_camera: FreeLookCamera = .{};
        var camera_director: core.CameraDirector = .{
            .mode = .free_look,
            .free_look_camera = .{
                .position = .zero,
                .pitch = 0,
                .yaw = 0,
                .roll = 0,
            },
            .is_allowed = true,
        };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            free_look_camera.processInput(&camera_director, 0.1, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.mouseMoveToPos(.{ .x = 400, .y = 400 });
            ctx.mouseDown(imgui.ImGuiMouseButton_Right);
            ctx.mouseMoveToPos(.{ .x = 500, .y = 300 });
            ctx.mouseUp(imgui.ImGuiMouseButton_Right);
            const camera = &camera_director.free_look_camera.?;
            try testing.expectApproxEqAbs(0.5, camera.yaw, 0.0001);
            try testing.expectApproxEqAbs(0.5, camera.pitch, 0.0001);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should move forward when holding right mouse button and W outside of windows" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .acceleration_time = 0,
            .deceleration_time = 0,
            .look_sensitivity = 0.005,
        };
        var free_look_camera: FreeLookCamera = .{};
        var camera_director: core.CameraDirector = .{
            .mode = .free_look,
            .free_look_camera = .{
                .position = .zero,
                .pitch = 0,
                .yaw = 0,
                .roll = 0,
            },
            .is_allowed = true,
        };
        var frames_with_key_down: f32 = 0;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            if (imgui.igIsKeyDown_Nil(imgui.ImGuiKey_W)) {
                frames_with_key_down += 1;
            }
            free_look_camera.processInput(&camera_director, 0.1, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.mouseMoveToPos(.{ .x = 400, .y = 400 });
            ctx.mouseDown(imgui.ImGuiMouseButton_Right);
            ctx.keyDown(imgui.ImGuiKey_W);
            ctx.yield(10);
            ctx.keyUp(imgui.ImGuiKey_W);
            ctx.mouseUp(imgui.ImGuiMouseButton_Right);
            const camera = &camera_director.free_look_camera.?;
            try testing.expect(frames_with_key_down > 0);
            try testing.expectApproxEqAbs(50 * frames_with_key_down, camera.position.x(), 0.01);
            try testing.expectApproxEqAbs(0, camera.position.y(), 0.0001);
            try testing.expectApproxEqAbs(0, camera.position.z(), 0.0001);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should move faster when also holding shift" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .acceleration_time = 0,
            .deceleration_time = 0,
            .look_sensitivity = 0.005,
        };
        var free_look_camera: FreeLookCamera = .{};
        var camera_director: core.CameraDirector = .{
            .mode = .free_look,
            .free_look_camera = .{
                .position = .zero,
                .pitch = 0,
                .yaw = 0,
                .roll = 0,
            },
            .is_allowed = true,
        };
        var frames_with_keys_down: f32 = 0;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            if (imgui.igIsKeyDown_Nil(imgui.ImGuiKey_W) and imgui.igIsKeyDown_Nil(imgui.ImGuiKey_LeftShift)) {
                frames_with_keys_down += 1;
            }
            free_look_camera.processInput(&camera_director, 0.1, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.mouseMoveToPos(.{ .x = 400, .y = 400 });
            ctx.mouseDown(imgui.ImGuiMouseButton_Right);
            ctx.keyDown(imgui.ImGuiKey_LeftShift);
            ctx.keyDown(imgui.ImGuiKey_W);
            ctx.yield(10);
            ctx.keyUp(imgui.ImGuiKey_W);
            ctx.keyUp(imgui.ImGuiKey_LeftShift);
            ctx.mouseUp(imgui.ImGuiMouseButton_Right);
            const camera = &camera_director.free_look_camera.?;
            try testing.expect(frames_with_keys_down > 0);
            try testing.expectApproxEqAbs(200 * frames_with_keys_down, camera.position.x(), 0.01);
            try testing.expectApproxEqAbs(0, camera.position.y(), 0.0001);
            try testing.expectApproxEqAbs(0, camera.position.z(), 0.0001);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should not move faster diagonally" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .acceleration_time = 0,
            .deceleration_time = 0,
            .look_sensitivity = 0.005,
        };
        var free_look_camera: FreeLookCamera = .{};
        var camera_director: core.CameraDirector = .{
            .mode = .free_look,
            .free_look_camera = .{
                .position = .zero,
                .pitch = 0,
                .yaw = 0,
                .roll = 0,
            },
            .is_allowed = true,
        };
        var frames_with_keys_down: f32 = 0;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            if (imgui.igIsKeyDown_Nil(imgui.ImGuiKey_W) and imgui.igIsKeyDown_Nil(imgui.ImGuiKey_D)) {
                frames_with_keys_down += 1;
            }
            free_look_camera.processInput(&camera_director, 0.1, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.mouseMoveToPos(.{ .x = 400, .y = 400 });
            ctx.mouseDown(imgui.ImGuiMouseButton_Right);
            ctx.keyDown(imgui.ImGuiKey_W);
            ctx.keyDown(imgui.ImGuiKey_D);
            const start_position = camera_director.free_look_camera.?.position;
            frames_with_keys_down = 0;
            ctx.yield(10);
            const end_position = camera_director.free_look_camera.?.position;
            ctx.keyUp(imgui.ImGuiKey_D);
            ctx.keyUp(imgui.ImGuiKey_W);
            ctx.mouseUp(imgui.ImGuiMouseButton_Right);
            const distance = end_position.subtract(start_position);
            try testing.expect(frames_with_keys_down > 0);
            try testing.expectApproxEqAbs(50 * frames_with_keys_down / std.math.sqrt2, distance.x(), 0.01);
            try testing.expectApproxEqAbs(50 * frames_with_keys_down / std.math.sqrt2, distance.y(), 0.01);
            try testing.expectApproxEqAbs(0, distance.z(), 0.0001);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should accelerate up to speed with acceleration from settings" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .acceleration_time = 0.5,
            .deceleration_time = 0,
            .look_sensitivity = 0.005,
        };
        var free_look_camera: FreeLookCamera = .{};
        var camera_director: core.CameraDirector = .{
            .mode = .free_look,
            .free_look_camera = .{
                .position = .zero,
                .pitch = 0,
                .yaw = 0,
                .roll = 0,
            },
            .is_allowed = true,
        };
        var frames_with_key_down: f32 = 0;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            if (imgui.igIsKeyDown_Nil(imgui.ImGuiKey_W)) {
                frames_with_key_down += 1;
            }
            free_look_camera.processInput(&camera_director, 0.1, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.mouseMoveToPos(.{ .x = 400, .y = 400 });
            ctx.mouseDown(imgui.ImGuiMouseButton_Right);
            ctx.keyDown(imgui.ImGuiKey_W);
            ctx.yield(10);
            ctx.keyUp(imgui.ImGuiKey_W);
            ctx.mouseUp(imgui.ImGuiMouseButton_Right);
            // Distance per frame: 5, 15, 25, 35, 45, then 50 at full speed, then 25 when decelerating instantly.
            const camera = &camera_director.free_look_camera.?;
            try testing.expect(frames_with_key_down >= 5);
            try testing.expectApproxEqAbs(125 + 50 * (frames_with_key_down - 5) + 25, camera.position.x(), 0.01);
            try testing.expectApproxEqAbs(0, camera.position.y(), 0.0001);
            try testing.expectApproxEqAbs(0, camera.position.z(), 0.0001);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should accelerate faster when also holding shift" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .acceleration_time = 0.5,
            .deceleration_time = 0,
            .look_sensitivity = 0.005,
        };
        var free_look_camera: FreeLookCamera = .{};
        var camera_director: core.CameraDirector = .{
            .mode = .free_look,
            .free_look_camera = .{
                .position = .zero,
                .pitch = 0,
                .yaw = 0,
                .roll = 0,
            },
            .is_allowed = true,
        };
        var frames_with_keys_down: f32 = 0;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            if (imgui.igIsKeyDown_Nil(imgui.ImGuiKey_W) and imgui.igIsKeyDown_Nil(imgui.ImGuiKey_LeftShift)) {
                frames_with_keys_down += 1;
            }
            free_look_camera.processInput(&camera_director, 0.1, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.mouseMoveToPos(.{ .x = 400, .y = 400 });
            ctx.mouseDown(imgui.ImGuiMouseButton_Right);
            ctx.keyDown(imgui.ImGuiKey_LeftShift);
            ctx.keyDown(imgui.ImGuiKey_W);
            ctx.yield(10);
            ctx.keyUp(imgui.ImGuiKey_W);
            ctx.keyUp(imgui.ImGuiKey_LeftShift);
            ctx.mouseUp(imgui.ImGuiMouseButton_Right);
            // Distance per frame: 20, 60, 100, 140, 180, then 200 at full speed, then 100 when decelerating instantly.
            const camera = &camera_director.free_look_camera.?;
            try testing.expect(frames_with_keys_down >= 5);
            try testing.expectApproxEqAbs(500 + 200 * (frames_with_keys_down - 5) + 100, camera.position.x(), 0.01);
            try testing.expectApproxEqAbs(0, camera.position.y(), 0.0001);
            try testing.expectApproxEqAbs(0, camera.position.z(), 0.0001);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should decelerate to a stop with deceleration from settings when W is released" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .acceleration_time = 0,
            .deceleration_time = 0.5,
            .look_sensitivity = 0.005,
        };
        var free_look_camera: FreeLookCamera = .{};
        var camera_director: core.CameraDirector = .{
            .mode = .free_look,
            .free_look_camera = .{
                .position = .zero,
                .pitch = 0,
                .yaw = 0,
                .roll = 0,
            },
            .is_allowed = true,
        };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            free_look_camera.processInput(&camera_director, 0.1, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.mouseMoveToPos(.{ .x = 400, .y = 400 });
            ctx.mouseDown(imgui.ImGuiMouseButton_Right);
            ctx.keyDown(imgui.ImGuiKey_W);
            ctx.yield(2);
            const start_position = camera_director.free_look_camera.?.position;
            ctx.keyUp(imgui.ImGuiKey_W);
            ctx.yield(10);
            const end_position = camera_director.free_look_camera.?.position;
            ctx.mouseUp(imgui.ImGuiMouseButton_Right);
            // Distance per frame after release: 45, 35, 25, 15, 5.
            const distance = end_position.subtract(start_position);
            try testing.expectApproxEqAbs(125, distance.x(), 0.01);
            try testing.expectApproxEqAbs(0, distance.y(), 0.0001);
            try testing.expectApproxEqAbs(0, distance.z(), 0.0001);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should decelerate faster when also holding shift" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .acceleration_time = 0,
            .deceleration_time = 0.5,
            .look_sensitivity = 0.005,
        };
        var free_look_camera: FreeLookCamera = .{};
        var camera_director: core.CameraDirector = .{
            .mode = .free_look,
            .free_look_camera = .{
                .position = .zero,
                .pitch = 0,
                .yaw = 0,
                .roll = 0,
            },
            .is_allowed = true,
        };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            free_look_camera.processInput(&camera_director, 0.1, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.mouseMoveToPos(.{ .x = 400, .y = 400 });
            ctx.mouseDown(imgui.ImGuiMouseButton_Right);
            ctx.keyDown(imgui.ImGuiKey_LeftShift);
            ctx.keyDown(imgui.ImGuiKey_W);
            ctx.yield(2);
            const start_position = camera_director.free_look_camera.?.position;
            ctx.keyUp(imgui.ImGuiKey_W);
            ctx.yield(10);
            const end_position = camera_director.free_look_camera.?.position;
            ctx.keyUp(imgui.ImGuiKey_LeftShift);
            ctx.mouseUp(imgui.ImGuiMouseButton_Right);
            // Distance per frame after release: 180, 140, 100, 60, 20.
            const distance = end_position.subtract(start_position);
            try testing.expectApproxEqAbs(500, distance.x(), 0.01);
            try testing.expectApproxEqAbs(0, distance.y(), 0.0001);
            try testing.expectApproxEqAbs(0, distance.z(), 0.0001);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should decelerate with both acceleration and deceleration when moving in the opposite direction" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .acceleration_time = 0.5,
            .deceleration_time = 0.5,
            .look_sensitivity = 0.005,
        };
        var free_look_camera: FreeLookCamera = .{ .velocity = .fromArray(.{ 5000, 0, 0 }) };
        var camera_director: core.CameraDirector = .{
            .mode = .free_look,
            .free_look_camera = .{
                .position = .zero,
                .pitch = 0,
                .yaw = 0,
                .roll = 0,
            },
            .is_allowed = true,
        };
        var velocities: [2]sdk.math.Vec3 = undefined;
        var velocities_len: usize = 0;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            free_look_camera.processInput(&camera_director, 0.1, &settings);
            if (imgui.igIsKeyDown_Nil(imgui.ImGuiKey_S) and velocities_len < velocities.len) {
                velocities[velocities_len] = free_look_camera.velocity;
                velocities_len += 1;
            }
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.mouseMoveToPos(.{ .x = 400, .y = 400 });
            ctx.mouseDown(imgui.ImGuiMouseButton_Right);
            ctx.keyDown(imgui.ImGuiKey_S);
            ctx.yield(2);
            ctx.keyUp(imgui.ImGuiKey_S);
            ctx.mouseUp(imgui.ImGuiMouseButton_Right);
            // Acceleration and deceleration both act against the forward velocity.
            try testing.expectEqual(2, velocities_len);
            const velocity_change = velocities[1].subtract(velocities[0]);
            try testing.expectApproxEqAbs(-200, velocity_change.x(), 0.01);
            try testing.expectApproxEqAbs(0, velocity_change.y(), 0.01);
            try testing.expectApproxEqAbs(0, velocity_change.z(), 0.0001);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should decelerate sideways velocity while accelerating in the wanted direction" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .acceleration_time = 0.5,
            .deceleration_time = 0.5,
            .look_sensitivity = 0.005,
        };
        var free_look_camera: FreeLookCamera = .{ .velocity = .fromArray(.{ 5000, 0, 0 }) };
        var camera_director: core.CameraDirector = .{
            .mode = .free_look,
            .free_look_camera = .{
                .position = .zero,
                .pitch = 0,
                .yaw = 0,
                .roll = 0,
            },
            .is_allowed = true,
        };
        var velocities: [2]sdk.math.Vec3 = undefined;
        var velocities_len: usize = 0;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            free_look_camera.processInput(&camera_director, 0.1, &settings);
            if (imgui.igIsKeyDown_Nil(imgui.ImGuiKey_D) and velocities_len < velocities.len) {
                velocities[velocities_len] = free_look_camera.velocity;
                velocities_len += 1;
            }
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.mouseMoveToPos(.{ .x = 400, .y = 400 });
            ctx.mouseDown(imgui.ImGuiMouseButton_Right);
            ctx.keyDown(imgui.ImGuiKey_D);
            ctx.yield(2);
            ctx.keyUp(imgui.ImGuiKey_D);
            ctx.mouseUp(imgui.ImGuiMouseButton_Right);
            // Deceleration acts on the forward velocity, acceleration on the right velocity.
            try testing.expectEqual(2, velocities_len);
            const velocity_change = velocities[1].subtract(velocities[0]);
            try testing.expectApproxEqAbs(-100, velocity_change.x(), 0.01);
            try testing.expectApproxEqAbs(100, velocity_change.y(), 0.01);
            try testing.expectApproxEqAbs(0, velocity_change.z(), 0.0001);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should decelerate to a stop with deceleration from settings when right mouse button is released" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .acceleration_time = 0,
            .deceleration_time = 0.5,
            .look_sensitivity = 0.005,
        };
        var free_look_camera: FreeLookCamera = .{};
        var camera_director: core.CameraDirector = .{
            .mode = .free_look,
            .free_look_camera = .{
                .position = .zero,
                .pitch = 0,
                .yaw = 0,
                .roll = 0,
            },
            .is_allowed = true,
        };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            free_look_camera.processInput(&camera_director, 0.1, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.mouseMoveToPos(.{ .x = 400, .y = 400 });
            ctx.mouseDown(imgui.ImGuiMouseButton_Right);
            ctx.keyDown(imgui.ImGuiKey_W);
            ctx.yield(2);
            const start_position = camera_director.free_look_camera.?.position;
            ctx.mouseUp(imgui.ImGuiMouseButton_Right);
            ctx.yield(10);
            const end_position = camera_director.free_look_camera.?.position;
            ctx.keyUp(imgui.ImGuiKey_W);
            // Distance per frame after release: 45, 35, 25, 15, 5.
            const distance = end_position.subtract(start_position);
            try testing.expectApproxEqAbs(125, distance.x(), 0.01);
            try testing.expectApproxEqAbs(0, distance.y(), 0.0001);
            try testing.expectApproxEqAbs(0, distance.z(), 0.0001);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should not move when W is held without right mouse button" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .acceleration_time = 0,
            .deceleration_time = 0,
            .look_sensitivity = 0.005,
        };
        var free_look_camera: FreeLookCamera = .{};
        var camera_director: core.CameraDirector = .{
            .mode = .free_look,
            .free_look_camera = .{
                .position = .zero,
                .pitch = 0,
                .yaw = 0,
                .roll = 0,
            },
            .is_allowed = true,
        };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            free_look_camera.processInput(&camera_director, 0.1, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.keyDown(imgui.ImGuiKey_W);
            ctx.yield(10);
            ctx.keyUp(imgui.ImGuiKey_W);
            try testing.expectEqual(sdk.math.Vec3.zero, camera_director.free_look_camera.?.position);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should not move when W was pressed before right mouse button" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .acceleration_time = 0,
            .deceleration_time = 0,
            .look_sensitivity = 0.005,
        };
        var free_look_camera: FreeLookCamera = .{};
        var camera_director: core.CameraDirector = .{
            .mode = .free_look,
            .free_look_camera = .{
                .position = .zero,
                .pitch = 0,
                .yaw = 0,
                .roll = 0,
            },
            .is_allowed = true,
        };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            free_look_camera.processInput(&camera_director, 0.1, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.mouseMoveToPos(.{ .x = 400, .y = 400 });
            ctx.keyDown(imgui.ImGuiKey_W);
            ctx.yield(2);
            ctx.mouseDown(imgui.ImGuiMouseButton_Right);
            ctx.yield(10);
            ctx.mouseUp(imgui.ImGuiMouseButton_Right);
            ctx.keyUp(imgui.ImGuiKey_W);
            try testing.expectEqual(sdk.math.Vec3.zero, camera_director.free_look_camera.?.position);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should not handle input when camera override is not allowed" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .acceleration_time = 0,
            .deceleration_time = 0,
            .look_sensitivity = 0.005,
        };
        var free_look_camera: FreeLookCamera = .{};
        var camera_director: core.CameraDirector = .{
            .mode = .free_look,
            .free_look_camera = .{
                .position = .zero,
                .pitch = 0,
                .yaw = 0,
                .roll = 0,
            },
            .is_allowed = false,
        };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            free_look_camera.processInput(&camera_director, 0.1, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.mouseMoveToPos(.{ .x = 400, .y = 400 });
            ctx.mouseDown(imgui.ImGuiMouseButton_Right);
            ctx.keyDown(imgui.ImGuiKey_W);
            ctx.yield(2);
            try testing.expectEqual(false, sdk.ui.hasShortcutRoute(imgui.ImGuiKey_W));
            ctx.mouseMoveToPos(.{ .x = 500, .y = 300 });
            ctx.keyUp(imgui.ImGuiKey_W);
            ctx.mouseUp(imgui.ImGuiMouseButton_Right);
            try testing.expectEqual(model.Camera{
                .position = .zero,
                .pitch = 0,
                .yaw = 0,
                .roll = 0,
            }, camera_director.free_look_camera);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should route movement keys only while holding right mouse button outside of windows" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .acceleration_time = 0,
            .deceleration_time = 0,
            .look_sensitivity = 0.005,
        };
        var free_look_camera: FreeLookCamera = .{};
        var camera_director: core.CameraDirector = .{
            .mode = .free_look,
            .free_look_camera = .{
                .position = .zero,
                .pitch = 0,
                .yaw = 0,
                .roll = 0,
            },
            .is_allowed = true,
        };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            free_look_camera.processInput(&camera_director, 0.1, &settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.mouseMoveToPos(.{ .x = 400, .y = 400 });
            ctx.yield(2);
            try testing.expectEqual(false, sdk.ui.hasShortcutRoute(imgui.ImGuiKey_W));

            ctx.mouseDown(imgui.ImGuiMouseButton_Right);
            ctx.yield(2);
            try testing.expectEqual(true, sdk.ui.hasShortcutRoute(imgui.ImGuiKey_W));
            try testing.expectEqual(true, sdk.ui.hasShortcutRoute(imgui.ImGuiKey_Space));
            try testing.expectEqual(true, sdk.ui.hasShortcutRoute(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_S));
            try testing.expectEqual(true, sdk.ui.hasShortcutRoute(imgui.ImGuiMod_Ctrl | imgui.ImGuiMod_Shift | imgui.ImGuiKey_D));
            try testing.expectEqual(false, sdk.ui.hasShortcutRoute(imgui.ImGuiKey_R));

            ctx.mouseUp(imgui.ImGuiMouseButton_Right);
            ctx.yield(2);
            try testing.expectEqual(false, sdk.ui.hasShortcutRoute(imgui.ImGuiKey_W));
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should take control + S away from other global shortcuts while holding right mouse button outside of windows" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .acceleration_time = 0,
            .deceleration_time = 0,
            .look_sensitivity = 0.005,
        };
        var free_look_camera: FreeLookCamera = .{};
        var camera_director: core.CameraDirector = .{
            .mode = .free_look,
            .free_look_camera = .{
                .position = .zero,
                .pitch = 0,
                .yaw = 0,
                .roll = 0,
            },
            .is_allowed = true,
        };
        var times_other_shortcut_triggered: usize = 0;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            free_look_camera.processInput(&camera_director, 0.1, &settings);
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            if (imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_S, imgui.ImGuiInputFlags_RouteGlobal)) {
                times_other_shortcut_triggered += 1;
            }
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.mouseMoveToPos(ctx.getPosOnVoid(imgui.igGetMainViewport()));
            ctx.yield(2);
            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_S, 1);
            try testing.expectEqual(1, times_other_shortcut_triggered);

            ctx.mouseDown(imgui.ImGuiMouseButton_Right);
            ctx.yield(2);
            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_S, 1);
            try testing.expectEqual(1, times_other_shortcut_triggered);
            ctx.mouseUp(imgui.ImGuiMouseButton_Right);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
