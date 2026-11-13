const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const core = @import("../core/root.zig");
const model = @import("../model/root.zig");

pub fn drawCameraMenuBar(camera_director: *core.CameraDirector) void {
    if (!imgui.igBeginMenu("Camera", true)) {
        return;
    }
    defer imgui.igEndMenu();
    if (imgui.igMenuItem_Bool("Live Camera", "Ctrl + 1", camera_director.mode == .live, true)) {
        camera_director.mode = .live;
    }
    if (imgui.igMenuItem_Bool("Recorded Camera", "Ctrl + 2", camera_director.mode == .recording, true)) {
        camera_director.mode = .recording;
    }
    if (imgui.igMenuItem_Bool("Free Camera", "Ctrl + 3", camera_director.mode == .free_look, true)) {
        camera_director.mode = .free_look;
    }
    if (imgui.igIsItemHovered(0)) {
        imgui.igSetTooltip(
            \\Right Mouse Button: Look Around
            \\Right Mouse Button + W, A, S, D: Move
            \\Right Mouse Button + Ctrl, Space: Move Down, Up
            \\Right Mouse Button + Shift: Move Faster
            ,
        );
    }
}

pub fn handleCameraShortcuts(camera_director: *core.CameraDirector) void {
    if (imgui.igGetTopMostPopupModal() != null) {
        return;
    }
    const route = imgui.ImGuiInputFlags_RouteGlobal;
    if (imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_1, route)) {
        camera_director.mode = .live;
    }
    if (imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_2, route)) {
        camera_director.mode = .recording;
    }
    if (imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_3, route)) {
        camera_director.mode = .free_look;
    }
}

pub fn handleFreeLookCameraInput(
    camera_director: *core.CameraDirector,
    delta_time: f32,
    settings: *const model.FreeLookCameraSettings,
) void {
    if (camera_director.mode != .free_look or !camera_director.is_allowed) {
        return;
    }
    const camera = if (camera_director.free_look_camera) |*camera| camera else return;
    const io = imgui.igGetIO_Nil();
    const display_size = io.*.DisplaySize;
    if (display_size.x > 0 and display_size.y > 0) {
        camera.setVerticalFov(settings.vertical_fov, display_size.x / display_size.y);
    }

    const is_looking = imgui.igIsMouseDown_Nil(imgui.ImGuiMouseButton_Right) and
        !io.*.MouseDownOwned[imgui.ImGuiMouseButton_Right];
    if (!is_looking) {
        return;
    }
    imgui.igSetNextFrameWantCaptureMouse(true);
    routeFreeLookMovementKeys();

    camera.rotatePitchYaw(-io.*.MouseDelta.y * settings.look_sensitivity, io.*.MouseDelta.x * settings.look_sensitivity);

    var direction = sdk.math.Vec3.zero;
    if (imgui.igIsKeyDown_Nil(imgui.ImGuiKey_W)) direction = direction.add(.plus_x);
    if (imgui.igIsKeyDown_Nil(imgui.ImGuiKey_S)) direction = direction.add(.minus_x);
    if (imgui.igIsKeyDown_Nil(imgui.ImGuiKey_D)) direction = direction.add(.plus_y);
    if (imgui.igIsKeyDown_Nil(imgui.ImGuiKey_A)) direction = direction.add(.minus_y);
    if (imgui.igIsKeyDown_Nil(imgui.ImGuiKey_Space)) direction = direction.add(.plus_z);
    if (imgui.igIsKeyDown_Nil(imgui.ImGuiKey_LeftCtrl) or imgui.igIsKeyDown_Nil(imgui.ImGuiKey_RightCtrl)) {
        direction = direction.add(.minus_z);
    }
    if (direction.isZero(0)) {
        return;
    }
    const is_fast = imgui.igIsKeyDown_Nil(imgui.ImGuiKey_LeftShift) or imgui.igIsKeyDown_Nil(imgui.ImGuiKey_RightShift);
    const speed = switch (is_fast) {
        false => settings.speed,
        true => settings.speed_multiplier * settings.speed,
    };
    camera.translateLocal(direction.normalize().scale(speed * delta_time));
}

fn routeFreeLookMovementKeys() void {
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

const testing = std.testing;

test "should change camera director mode when a camera is selected by clicking a menu bar button" {
    const Test = struct {
        var camera_director: core.CameraDirector = .{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            drawCameraMenuBar(&camera_director);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(core.CameraDirector.Mode.live, camera_director.mode);
            ctx.menuClick("Camera/Recorded Camera");
            try testing.expectEqual(core.CameraDirector.Mode.recording, camera_director.mode);
            ctx.menuClick("Camera/Free Camera");
            try testing.expectEqual(core.CameraDirector.Mode.free_look, camera_director.mode);
            ctx.menuClick("Camera/Live Camera");
            try testing.expectEqual(core.CameraDirector.Mode.live, camera_director.mode);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should change camera director mode when a camera keyboard shortcut is pressed" {
    const Test = struct {
        var camera_director: core.CameraDirector = .{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            handleCameraShortcuts(&camera_director);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try testing.expectEqual(core.CameraDirector.Mode.live, camera_director.mode);
            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_2, 1);
            try testing.expectEqual(core.CameraDirector.Mode.recording, camera_director.mode);
            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_3, 1);
            try testing.expectEqual(core.CameraDirector.Mode.free_look, camera_director.mode);
            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_1, 1);
            try testing.expectEqual(core.CameraDirector.Mode.live, camera_director.mode);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should rotate free look camera when dragging with right mouse button outside of windows" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .look_sensitivity = 0.005,
        };
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
            handleFreeLookCameraInput(&camera_director, 0.1, &settings);
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

test "should move free look camera forward when holding right mouse button and W outside of windows" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .look_sensitivity = 0.005,
        };
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
            handleFreeLookCameraInput(&camera_director, 0.1, &settings);
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

test "should move free look camera four times faster when also holding shift" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .look_sensitivity = 0.005,
        };
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
            handleFreeLookCameraInput(&camera_director, 0.1, &settings);
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

test "should not move free look camera faster diagonally" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .look_sensitivity = 0.005,
        };
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
            handleFreeLookCameraInput(&camera_director, 0.1, &settings);
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

test "should not move free look camera when W is held without right mouse button" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .look_sensitivity = 0.005,
        };
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
            handleFreeLookCameraInput(&camera_director, 0.1, &settings);
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

test "should not handle free look input when camera override is not allowed" {
    const Test = struct {
        const settings = model.FreeLookCameraSettings{
            .speed = 500,
            .speed_multiplier = 4,
            .look_sensitivity = 0.005,
        };
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
            handleFreeLookCameraInput(&camera_director, 0.1, &settings);
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
            .look_sensitivity = 0.005,
        };
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
            handleFreeLookCameraInput(&camera_director, 0.1, &settings);
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
            .look_sensitivity = 0.005,
        };
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
            handleFreeLookCameraInput(&camera_director, 0.1, &settings);
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
