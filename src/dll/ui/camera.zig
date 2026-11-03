const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("../ui/root.zig");

pub const Camera = struct {
    pending_windows: std.EnumArray(ui.ViewDirection, Window) = .initFill(.{}),
    windows: std.EnumArray(ui.ViewDirection, Window) = .initFill(.{}),
    follow_target: FollowTarget = .ingame_camera,
    transform: Transform = .{},
    rotation_radius: ?f32 = null,

    pub const player_padding = 50;
    pub const stage_padding = 200;
    pub const stage_vertical_offset = 100;
    pub const zoom_speed = 1.2;

    const Self = @This();
    pub const Window = struct {
        position: sdk.math.Vec2 = .zero,
        size: sdk.math.Vec2 = .fill(1_000_000),
    };
    pub const FollowTarget = enum {
        ingame_camera,
        players,
        stage,
    };
    pub const Transform = struct {
        translation: sdk.math.Vec3 = .zero,
        scale: f32 = 1.0,
        rotation: f32 = 0.0,
    };

    pub fn measureWindow(self: *Self, direction: ui.ViewDirection) void {
        var window: Window = undefined;
        imgui.igGetCursorScreenPos(window.position.asImVec());
        imgui.igGetContentRegionAvail(window.size.asImVec());
        self.pending_windows.set(direction, window);
    }

    pub fn flushWindowMeasurements(self: *Self) void {
        self.windows = self.pending_windows;
        self.pending_windows = .initFill(.{});
    }

    pub fn processInput(self: *Self, direction: ui.ViewDirection, inverse_matrix: sdk.math.Mat4) void {
        if (!imgui.igIsWindowHovered(imgui.ImGuiHoveredFlags_ChildWindows)) {
            return;
        }

        const wheel = imgui.igGetIO_Nil().*.MouseWheel;
        if (wheel != 0.0) {
            var window_pos: sdk.math.Vec2 = undefined;
            imgui.igGetCursorScreenPos(window_pos.asImVec());
            var window_size: sdk.math.Vec2 = undefined;
            imgui.igGetContentRegionAvail(window_size.asImVec());

            const screen_camera = window_pos.add(window_size.scale(0.5)).extend(0);
            const world_camera = screen_camera.pointTransform(inverse_matrix);

            const mouse_pos = imgui.igGetIO_Nil().*.MousePos;
            const screen_mouse = sdk.math.Vec2.fromImVec(mouse_pos).extend(0);
            const world_mouse = screen_mouse.pointTransform(inverse_matrix);

            const scale_factor = std.math.pow(f32, zoom_speed, wheel);
            const delta_translation = world_mouse.subtract(world_camera).scale(1.0 / scale_factor - 1.0);
            self.transform.translation = self.transform.translation.add(delta_translation);
            self.transform.scale *= scale_factor;
        }

        const is_right_mouse_down = imgui.igIsKeyDown_Nil(imgui.ImGuiKey_MouseRight);
        const is_modifier_down = imgui.igIsKeyDown_Nil(imgui.ImGuiKey_LeftCtrl) or
            imgui.igIsKeyDown_Nil(imgui.ImGuiKey_LeftShift) or
            imgui.igIsKeyDown_Nil(imgui.ImGuiKey_LeftAlt);
        if (is_right_mouse_down and !is_modifier_down) {
            const delta_mouse = imgui.igGetIO_Nil().*.MouseDelta;
            const delta_screen = sdk.math.Vec2.fromImVec(delta_mouse).extend(0);
            const delta_world = delta_screen.directionTransform(inverse_matrix);
            self.transform.translation = self.transform.translation.add(delta_world);
            imgui.igSetMouseCursor(imgui.ImGuiMouseCursor_ResizeAll);
        }
        if (direction != .top and is_right_mouse_down and is_modifier_down) {
            var window_pos: imgui.ImVec2 = undefined;
            imgui.igGetCursorScreenPos(&window_pos);
            var window_size: imgui.ImVec2 = undefined;
            imgui.igGetContentRegionAvail(&window_size);
            const center = window_pos.x + 0.5 * window_size.x;

            const acosExtended = struct {
                fn call(x: f32) f32 {
                    const periods = @floor(0.5 * x + 0.5);
                    const remainder = std.math.wrap(x, 1);
                    return -std.math.pi * periods + std.math.acos(remainder);
                }
            }.call;

            const previous_mouse = imgui.igGetIO_Nil().*.MousePosPrev.x;
            const current_mouse = imgui.igGetIO_Nil().*.MousePos.x;
            const radius = self.rotation_radius orelse @abs(current_mouse - center);
            self.rotation_radius = radius;
            const previous_offset = previous_mouse - center;
            const current_offset = current_mouse - center;
            const previous_angle = acosExtended(previous_offset / radius);
            const current_angle = acosExtended(current_offset / radius);
            const delta_angle = current_angle - previous_angle;

            self.transform.rotation = std.math.wrap(self.transform.rotation - delta_angle, std.math.pi);
            imgui.igSetMouseCursor(imgui.ImGuiMouseCursor_ResizeEW);
        } else {
            self.rotation_radius = null;
        }
        if (direction == .top and is_right_mouse_down and is_modifier_down) {
            var window_pos: sdk.math.Vec2 = undefined;
            imgui.igGetCursorScreenPos(window_pos.asImVec());
            var window_size: sdk.math.Vec2 = undefined;
            imgui.igGetContentRegionAvail(window_size.asImVec());
            const center = window_pos.add(window_size.scale(0.5));

            const previous_mouse = sdk.math.Vec2.fromImVec(imgui.igGetIO_Nil().*.MousePosPrev);
            const current_mouse = sdk.math.Vec2.fromImVec(imgui.igGetIO_Nil().*.MousePos);
            const previous_offset = previous_mouse.subtract(center);
            const current_offset = current_mouse.subtract(center);
            const previous_angle = std.math.atan2(previous_offset.y(), previous_offset.x());
            const current_angle = std.math.atan2(current_offset.y(), current_offset.x());
            const delta_angle = current_angle - previous_angle;

            self.transform.rotation = std.math.wrap(self.transform.rotation - delta_angle, std.math.pi);
            const factor = comptime (1.0 / std.math.tan(std.math.pi / 8.0));
            if (@abs(current_offset.x()) > factor * @abs(current_offset.y())) {
                imgui.igSetMouseCursor(imgui.ImGuiMouseCursor_ResizeNS);
            } else if (@abs(current_offset.y()) > factor * @abs(current_offset.x())) {
                imgui.igSetMouseCursor(imgui.ImGuiMouseCursor_ResizeEW);
            } else if (std.math.sign(current_offset.x()) == std.math.sign(current_offset.y())) {
                imgui.igSetMouseCursor(imgui.ImGuiMouseCursor_ResizeNESW);
            } else {
                imgui.igSetMouseCursor(imgui.ImGuiMouseCursor_ResizeNWSE);
            }
        }

        const is_middle_mouse_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_MouseMiddle, false);
        if (is_middle_mouse_pressed) {
            self.transform = .{};
        }
    }

    pub fn drawMenuBar(self: *Self) void {
        if (imgui.igGetTopMostPopupModal() == null) {
            const route = imgui.ImGuiInputFlags_RouteGlobal;
            if (imgui.igShortcut_Nil(imgui.ImGuiMod_Shift | imgui.ImGuiKey_1, route)) {
                self.follow_target = .ingame_camera;
            }
            if (imgui.igShortcut_Nil(imgui.ImGuiMod_Shift | imgui.ImGuiKey_2, route)) {
                self.follow_target = .players;
            }
            if (imgui.igShortcut_Nil(imgui.ImGuiMod_Shift | imgui.ImGuiKey_3, route)) {
                self.follow_target = .stage;
            }
        }

        if (!imgui.igBeginMenu("Camera", true)) {
            return;
        }
        defer imgui.igEndMenu();
        if (imgui.igMenuItem_Bool("Follow Ingame Camera", "Shift + 1", self.follow_target == .ingame_camera, true)) {
            self.follow_target = .ingame_camera;
        }
        if (imgui.igMenuItem_Bool("Follow Players", "Shift + 2", self.follow_target == .players, true)) {
            self.follow_target = .players;
        }
        if (imgui.igMenuItem_Bool("Follow Stage Bounds", "Shift + 3", self.follow_target == .stage, true)) {
            self.follow_target = .stage;
        }
        imgui.igSeparator();
        if (imgui.igMenuItem_Bool("Reset View Offset", null, false, !std.meta.eql(self.transform, .{}))) {
            self.transform = .{};
        }
    }

    pub fn calculateMatrix(self: *const Self, frame: *const model.Frame, direction: ui.ViewDirection) ?sdk.math.Mat4 {
        const translation_matrix = sdk.math.Mat4.fromTranslation(self.transform.translation);
        const look_at_matrix = switch (self.follow_target) {
            .ingame_camera => calculateIngameCameraLookAtMatrix(frame, direction) orelse return null,
            .players => calculatePlayersLookAtMatrix(frame, direction) orelse return null,
            .stage => calculateStageLookAtMatrix(frame, direction),
        };
        const rotation_matrix = switch (direction) {
            .front, .side => sdk.math.Mat4.fromYRotation(self.transform.rotation),
            .top => sdk.math.Mat4.fromZRotation(self.transform.rotation),
        };
        const scale_matrix = sdk.math.Mat4.fromScale(sdk.math.Vec3.fill(self.transform.scale));
        const orthographic_matrix = self.calculateOrthographicMatrix(
            frame,
            direction,
            look_at_matrix,
            self.follow_target,
        ) orelse return null;
        const window_matrix = self.calculateWindowMatrix(direction);
        return translation_matrix
            .multiply(look_at_matrix)
            .multiply(rotation_matrix)
            .multiply(scale_matrix)
            .multiply(orthographic_matrix)
            .multiply(window_matrix);
    }

    fn calculateIngameCameraLookAtMatrix(frame: *const model.Frame, direction: ui.ViewDirection) ?sdk.math.Mat4 {
        const left_player = frame.getPlayerBySide(.left).getPosition() orelse return null;
        const right_player = frame.getPlayerBySide(.right).getPosition() orelse return null;
        const camera = frame.camera orelse return null;
        const eye = left_player.add(right_player).scale(0.5);
        const difference_2d = eye.swizzle("xy").subtract(camera.position.swizzle("xy"));
        const camera_dir = if (!difference_2d.isZero(0)) difference_2d.normalize().extend(0) else sdk.math.Vec3.plus_x;
        const look_direction = switch (direction) {
            .front => camera_dir,
            .side => camera_dir.rotateZ(0.5 * std.math.pi),
            .top => sdk.math.Vec3.minus_z,
        };
        const target = eye.add(look_direction);
        const up = switch (direction) {
            .front, .side => sdk.math.Vec3.plus_z,
            .top => camera_dir,
        };
        return sdk.math.Mat4.fromLookAt(eye, target, up);
    }

    fn calculatePlayersLookAtMatrix(frame: *const model.Frame, direction: ui.ViewDirection) ?sdk.math.Mat4 {
        const left_player = frame.getPlayerBySide(.left).getPosition() orelse return null;
        const right_player = frame.getPlayerBySide(.right).getPosition() orelse return null;
        const eye = left_player.add(right_player).scale(0.5);
        const difference_2d = right_player.swizzle("xy").subtract(left_player.swizzle("xy"));
        const player_dir = if (!difference_2d.isZero(0)) difference_2d.normalize().extend(0) else sdk.math.Vec3.plus_x;
        const look_direction = switch (direction) {
            .front => player_dir.cross(sdk.math.Vec3.plus_z),
            .side => player_dir,
            .top => sdk.math.Vec3.minus_z,
        };
        const target = eye.add(look_direction);
        const up = switch (direction) {
            .front, .side => sdk.math.Vec3.plus_z,
            .top => player_dir.cross(sdk.math.Vec3.plus_z),
        };
        return sdk.math.Mat4.fromLookAt(eye, target, up);
    }

    fn calculateStageLookAtMatrix(frame: *const model.Frame, direction: ui.ViewDirection) sdk.math.Mat4 {
        const floor_z = frame.floor_z orelse 0;
        const walls: []const model.Wall = frame.walls.asSlice();
        const midpoint = if (walls.len == 0) sdk.math.Vec2.zero else block: {
            var min = sdk.math.Vec2.fill(std.math.inf(f32));
            var max = sdk.math.Vec2.fill(-std.math.inf(f32));
            for (walls) |*wall| {
                min = sdk.math.Vec2.minElements(min, wall.edge_1);
                max = sdk.math.Vec2.maxElements(max, wall.edge_1);
            }
            break :block min.add(max).scale(0.5);
        };
        const eye = midpoint.extend(floor_z + stage_vertical_offset);
        const target = switch (direction) {
            .front => eye.add(.plus_y),
            .side => eye.add(.minus_x),
            .top => eye.add(.minus_z),
        };
        const up = switch (direction) {
            .front, .side => sdk.math.Vec3.plus_z,
            .top => sdk.math.Vec3.plus_y,
        };
        return sdk.math.Mat4.fromLookAt(eye, target, up);
    }

    fn calculateOrthographicMatrix(
        self: *const Self,
        frame: *const model.Frame,
        direction: ui.ViewDirection,
        look_at_matrix: sdk.math.Mat4,
        follow_target: FollowTarget,
    ) ?sdk.math.Mat4 {
        const world_box = switch (follow_target) {
            .ingame_camera, .players => block: {
                var min = sdk.math.Vec3.fill(std.math.inf(f32));
                var max = sdk.math.Vec3.fill(-std.math.inf(f32));
                for (&frame.players) |*player| {
                    if (player.collision_spheres) |*spheres| {
                        for (&spheres.values) |*sphere| {
                            const pos = sphere.center.pointTransform(look_at_matrix);
                            const half_size = sdk.math.Vec3.fill(sphere.radius);
                            min = sdk.math.Vec3.minElements(min, pos.subtract(half_size));
                            max = sdk.math.Vec3.maxElements(max, pos.add(half_size));
                        }
                    }
                    if (player.hurt_cylinders) |*cylinders| {
                        for (&cylinders.values) |*hurt_cylinder| {
                            const cylinder = &hurt_cylinder.cylinder;
                            const pos = cylinder.center.pointTransform(look_at_matrix);
                            const half_size = switch (direction) {
                                .top => sdk.math.Vec3.fromArray(.{
                                    cylinder.radius,
                                    cylinder.radius,
                                    cylinder.half_height,
                                }),
                                .front, .side => sdk.math.Vec3.fromArray(.{
                                    cylinder.radius,
                                    cylinder.half_height,
                                    cylinder.radius,
                                }),
                            };
                            min = sdk.math.Vec3.minElements(min, pos.subtract(half_size));
                            max = sdk.math.Vec3.maxElements(max, pos.add(half_size));
                        }
                    }
                }
                break :block sdk.math.Vec3.maxElements(min.negate(), max).add(.fill(player_padding)).scale(2);
            },
            .stage => block: {
                const walls: []const model.Wall = frame.walls.asSlice();
                if (walls.len == 0) {
                    break :block sdk.math.Vec3.fill(stage_vertical_offset + stage_padding).scale(2);
                }
                const floor_z = frame.floor_z orelse 0;
                var min = sdk.math.Vec3.fill(std.math.inf(f32));
                var max = sdk.math.Vec3.fill(-std.math.inf(f32));
                for (walls) |*wall| {
                    const pos = wall.edge_1.extend(floor_z).pointTransform(look_at_matrix);
                    min = sdk.math.Vec3.minElements(min, pos);
                    max = sdk.math.Vec3.maxElements(max, pos);
                }
                break :block sdk.math.Vec3.maxElements(min.negate(), max).add(.fill(stage_padding)).scale(2);
            },
        };
        const screen_box = switch (direction) {
            .front => sdk.math.Vec3.fromArray(.{
                @min(self.windows.get(.front).size.x(), self.windows.get(.top).size.x()),
                @min(self.windows.get(.front).size.y(), self.windows.get(.side).size.y()),
                @min(self.windows.get(.top).size.y(), self.windows.get(.side).size.x()),
            }),
            .side => sdk.math.Vec3.fromArray(.{
                @min(self.windows.get(.side).size.x(), self.windows.get(.top).size.y()),
                @min(self.windows.get(.side).size.y(), self.windows.get(.front).size.y()),
                @min(self.windows.get(.front).size.x(), self.windows.get(.top).size.x()),
            }),
            .top => sdk.math.Vec3.fromArray(.{
                @min(self.windows.get(.top).size.x(), self.windows.get(.front).size.x()),
                @min(self.windows.get(.top).size.y(), self.windows.get(.side).size.x()),
                @min(self.windows.get(.front).size.y(), self.windows.get(.side).size.y()),
            }),
        };
        const scale_factors = world_box.divideElements(screen_box);
        const max_factor = @max(scale_factors.x(), scale_factors.y(), scale_factors.z());
        const viewport_size = self.windows.get(direction).size.extend(screen_box.z()).scale(max_factor);
        return sdk.math.Mat4.fromOrthographic(
            -0.5 * viewport_size.x(),
            0.5 * viewport_size.x(),
            -0.5 * viewport_size.y(),
            0.5 * viewport_size.y(),
            -0.5 * viewport_size.z(),
            0.5 * viewport_size.z(),
        );
    }

    fn calculateWindowMatrix(self: *const Self, direction: ui.ViewDirection) sdk.math.Mat4 {
        const window = self.windows.get(direction);
        return sdk.math.Mat4.identity
            .scale(.fromArray(.{ 0.5 * window.size.x(), -0.5 * window.size.y(), 1 }))
            .translate(window.position.add(window.size.scale(0.5)).extend(0));
    }
};

const testing = std.testing;

fn testPoint(x: f32, y: f32, z: f32) sdk.math.Vec3 {
    return .fromArray(.{
        100 + (x * Camera.player_padding),
        200 + (y * Camera.player_padding),
        300 + (z * Camera.player_padding),
    });
}

fn testSphere(x: f32, y: f32, z: f32, radius: f32) model.CollisionSphere {
    return .{
        .center = testPoint(x, y, z),
        .radius = radius * Camera.player_padding,
    };
}

fn testCylinder(x: f32, y: f32, z: f32, radius: f32, half_height: f32) model.HurtCylinder {
    return .{ .cylinder = .{
        .center = testPoint(x, y, z),
        .radius = radius * Camera.player_padding,
        .half_height = half_height * Camera.player_padding,
    } };
}

fn stagePoint(x: f32, y: f32, z: f32) sdk.math.Vec3 {
    return .fromArray(.{
        100 + (x * Camera.stage_padding),
        200 + (y * Camera.stage_padding),
        300 + (z * Camera.stage_padding),
    });
}

fn testWall(x1: f32, y1: f32) model.Wall {
    return .{
        .edge_1 = stagePoint(x1, y1, 0).swizzle("xy"),
        .edge_2_index = 0,
    };
}

test "should project correctly when follow target is players" {
    const Test = struct {
        const frame = model.Frame{ .players = .{
            .{
                .collision_spheres = .init(.{
                    .neck = testSphere(-3, 0, 3, 1),
                    .left_elbow = testSphere(-6, 0, 0, 1),
                    .right_elbow = testSphere(-6, 0, 0, 1),
                    .lower_torso = testSphere(-3, 0, 0, 1),
                    .left_knee = testSphere(-3, 0, 0, 1),
                    .right_knee = testSphere(-3, 0, 0, 1),
                    .left_ankle = testSphere(-3, 0, 0, 1),
                    .right_ankle = testSphere(-3, 0, 0, 1),
                }),
                .hurt_cylinders = .init(.{
                    .left_ankle = testCylinder(-3, 0, -3, 2, 1),
                    .right_ankle = testCylinder(-3, 0, -3, 2, 1),
                    .left_hand = testCylinder(-3, -2, 0, 2, 1),
                    .right_hand = testCylinder(-3, 2, 0, 2, 1),
                    .left_knee = testCylinder(-3, 0, 0, 2, 1),
                    .right_knee = testCylinder(-3, 0, 0, 2, 1),
                    .left_elbow = testCylinder(-3, 0, 0, 2, 1),
                    .right_elbow = testCylinder(-3, 0, 0, 2, 1),
                    .head = testCylinder(-3, 0, 0, 2, 1),
                    .left_shoulder = testCylinder(-3, 0, 0, 2, 1),
                    .right_shoulder = testCylinder(-3, 0, 0, 2, 1),
                    .upper_torso = testCylinder(-3, 0, 0, 2, 1),
                    .left_pelvis = testCylinder(-3, 0, 0, 2, 1),
                    .right_pelvis = testCylinder(-3, 0, 0, 2, 1),
                }),
            },
            .{
                .collision_spheres = .init(.{
                    .neck = testSphere(3, 0, 3, 1),
                    .left_elbow = testSphere(6, 0, 0, 1),
                    .right_elbow = testSphere(6, 0, 0, 1),
                    .lower_torso = testSphere(3, 0, 0, 1),
                    .left_knee = testSphere(3, 0, 0, 1),
                    .right_knee = testSphere(3, 0, 0, 1),
                    .left_ankle = testSphere(3, 0, 0, 1),
                    .right_ankle = testSphere(3, 0, 0, 1),
                }),
                .hurt_cylinders = .init(.{
                    .left_ankle = testCylinder(3, 0, -3, 2, 1),
                    .right_ankle = testCylinder(3, 0, -3, 2, 1),
                    .left_hand = testCylinder(3, -2, 0, 2, 1),
                    .right_hand = testCylinder(3, 2, 0, 2, 1),
                    .left_knee = testCylinder(3, 0, 0, 2, 1),
                    .right_knee = testCylinder(3, 0, 0, 2, 1),
                    .left_elbow = testCylinder(3, 0, 0, 2, 1),
                    .right_elbow = testCylinder(3, 0, 0, 2, 1),
                    .head = testCylinder(3, 0, 0, 2, 1),
                    .left_shoulder = testCylinder(3, 0, 0, 2, 1),
                    .right_shoulder = testCylinder(3, 0, 0, 2, 1),
                    .upper_torso = testCylinder(3, 0, 0, 2, 1),
                    .left_pelvis = testCylinder(3, 0, 0, 2, 1),
                    .right_pelvis = testCylinder(3, 0, 0, 2, 1),
                }),
            },
        } };
        var camera: Camera = .{ .follow_target = .players };
        var matrices: std.EnumArray(ui.ViewDirection, sdk.math.Mat4) = .initFill(.identity);

        fn guiFunction(_: sdk.ui.TestContext) !void {
            const window_flags = imgui.ImGuiWindowFlags_NoMove |
                imgui.ImGuiWindowFlags_NoResize |
                imgui.ImGuiWindowFlags_NoDecoration |
                imgui.ImGuiWindowFlags_NoSavedSettings;
            imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });
            imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{ .x = 0, .y = 0 });
            defer imgui.igPopStyleVar(2);

            imgui.igSetNextWindowPos(.{ .x = 100, .y = 100 }, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            if (imgui.igBegin("Front", null, window_flags)) {
                defer imgui.igEnd();
                camera.measureWindow(.front);
                const matrix = camera.calculateMatrix(&frame, .front) orelse return error.MatrixCalculationFailed;
                matrices.set(.front, matrix);
            } else imgui.igEnd();

            imgui.igSetNextWindowPos(.{ .x = 100, .y = 400 }, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            if (imgui.igBegin("Top", null, window_flags)) {
                defer imgui.igEnd();
                camera.measureWindow(.top);
                const matrix = camera.calculateMatrix(&frame, .top) orelse return error.MatrixCalculationFailed;
                matrices.set(.top, matrix);
            } else imgui.igEnd();

            imgui.igSetNextWindowPos(.{ .x = 600, .y = 100 }, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            if (imgui.igBegin("Side", null, window_flags)) {
                defer imgui.igEnd();
                camera.measureWindow(.side);
                const matrix = camera.calculateMatrix(&frame, .side) orelse return error.MatrixCalculationFailed;
                matrices.set(.side, matrix);
            } else imgui.igEnd();

            camera.flushWindowMeasurements();
        }

        fn testFunction(_: sdk.ui.TestContext) !void {
            try testing.expectApproxEqAbs(160, testPoint(-7, -4, -4).pointTransform(matrices.get(.front)).x(), 0.0001);
            try testing.expectApproxEqAbs(280, testPoint(-7, -4, -4).pointTransform(matrices.get(.front)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.9, testPoint(-7, -4, -4).pointTransform(matrices.get(.front)).z(), 0.0001);
            try testing.expectApproxEqAbs(300, testPoint(0, 0, 0).pointTransform(matrices.get(.front)).x(), 0.0001);
            try testing.expectApproxEqAbs(200, testPoint(0, 0, 0).pointTransform(matrices.get(.front)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.5, testPoint(0, 0, 0).pointTransform(matrices.get(.front)).z(), 0.0001);
            try testing.expectApproxEqAbs(440, testPoint(7, 4, 4).pointTransform(matrices.get(.front)).x(), 0.0001);
            try testing.expectApproxEqAbs(120, testPoint(7, 4, 4).pointTransform(matrices.get(.front)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.1, testPoint(7, 4, 4).pointTransform(matrices.get(.front)).z(), 0.0001);

            try testing.expectApproxEqAbs(160, testPoint(-7, -4, -4).pointTransform(matrices.get(.top)).x(), 0.0001);
            try testing.expectApproxEqAbs(420, testPoint(-7, -4, -4).pointTransform(matrices.get(.top)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.9, testPoint(-7, -4, -4).pointTransform(matrices.get(.top)).z(), 0.0001);
            try testing.expectApproxEqAbs(300, testPoint(0, 0, 0).pointTransform(matrices.get(.top)).x(), 0.0001);
            try testing.expectApproxEqAbs(500, testPoint(0, 0, 0).pointTransform(matrices.get(.top)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.5, testPoint(0, 0, 0).pointTransform(matrices.get(.top)).z(), 0.0001);
            try testing.expectApproxEqAbs(440, testPoint(7, 4, 4).pointTransform(matrices.get(.top)).x(), 0.0001);
            try testing.expectApproxEqAbs(580, testPoint(7, 4, 4).pointTransform(matrices.get(.top)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.1, testPoint(7, 4, 4).pointTransform(matrices.get(.top)).z(), 0.0001);

            try testing.expectApproxEqAbs(720, testPoint(-7, -4, -4).pointTransform(matrices.get(.side)).x(), 0.0001);
            try testing.expectApproxEqAbs(280, testPoint(-7, -4, -4).pointTransform(matrices.get(.side)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.15, testPoint(-7, -4, -4).pointTransform(matrices.get(.side)).z(), 0.0001);
            try testing.expectApproxEqAbs(800, testPoint(0, 0, 0).pointTransform(matrices.get(.side)).x(), 0.0001);
            try testing.expectApproxEqAbs(200, testPoint(0, 0, 0).pointTransform(matrices.get(.side)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.5, testPoint(0, 0, 0).pointTransform(matrices.get(.side)).z(), 0.0001);
            try testing.expectApproxEqAbs(880, testPoint(7, 4, 4).pointTransform(matrices.get(.side)).x(), 0.0001);
            try testing.expectApproxEqAbs(120, testPoint(7, 4, 4).pointTransform(matrices.get(.side)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.85, testPoint(7, 4, 4).pointTransform(matrices.get(.side)).z(), 0.0001);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should project correctly when follow target is ingame camera" {
    const Test = struct {
        const frame = model.Frame{
            .camera = .{
                .position = testPoint(0, -10, 0),
                .pitch = 0,
                .roll = 0,
                .yaw = 0,
                .horizontal_fov = 0,
            },
            .players = .{
                .{
                    .collision_spheres = .init(.{
                        .neck = testSphere(-3, 0, 3, 1),
                        .left_elbow = testSphere(-6, 0, 0, 1),
                        .right_elbow = testSphere(-6, 0, 0, 1),
                        .lower_torso = testSphere(-3, 0, 0, 1),
                        .left_knee = testSphere(-3, 0, 0, 1),
                        .right_knee = testSphere(-3, 0, 0, 1),
                        .left_ankle = testSphere(-3, 0, 0, 1),
                        .right_ankle = testSphere(-3, 0, 0, 1),
                    }),
                    .hurt_cylinders = .init(.{
                        .left_ankle = testCylinder(-3, 0, -3, 2, 1),
                        .right_ankle = testCylinder(-3, 0, -3, 2, 1),
                        .left_hand = testCylinder(-3, -2, 0, 2, 1),
                        .right_hand = testCylinder(-3, 2, 0, 2, 1),
                        .left_knee = testCylinder(-3, 0, 0, 2, 1),
                        .right_knee = testCylinder(-3, 0, 0, 2, 1),
                        .left_elbow = testCylinder(-3, 0, 0, 2, 1),
                        .right_elbow = testCylinder(-3, 0, 0, 2, 1),
                        .head = testCylinder(-3, 0, 0, 2, 1),
                        .left_shoulder = testCylinder(-3, 0, 0, 2, 1),
                        .right_shoulder = testCylinder(-3, 0, 0, 2, 1),
                        .upper_torso = testCylinder(-3, 0, 0, 2, 1),
                        .left_pelvis = testCylinder(-3, 0, 0, 2, 1),
                        .right_pelvis = testCylinder(-3, 0, 0, 2, 1),
                    }),
                },
                .{
                    .collision_spheres = .init(.{
                        .neck = testSphere(3, 0, 3, 1),
                        .left_elbow = testSphere(6, 0, 0, 1),
                        .right_elbow = testSphere(6, 0, 0, 1),
                        .lower_torso = testSphere(3, 0, 0, 1),
                        .left_knee = testSphere(3, 0, 0, 1),
                        .right_knee = testSphere(3, 0, 0, 1),
                        .left_ankle = testSphere(3, 0, 0, 1),
                        .right_ankle = testSphere(3, 0, 0, 1),
                    }),
                    .hurt_cylinders = .init(.{
                        .left_ankle = testCylinder(3, 0, -3, 2, 1),
                        .right_ankle = testCylinder(3, 0, -3, 2, 1),
                        .left_hand = testCylinder(3, -2, 0, 2, 1),
                        .right_hand = testCylinder(3, 2, 0, 2, 1),
                        .left_knee = testCylinder(3, 0, 0, 2, 1),
                        .right_knee = testCylinder(3, 0, 0, 2, 1),
                        .left_elbow = testCylinder(3, 0, 0, 2, 1),
                        .right_elbow = testCylinder(3, 0, 0, 2, 1),
                        .head = testCylinder(3, 0, 0, 2, 1),
                        .left_shoulder = testCylinder(3, 0, 0, 2, 1),
                        .right_shoulder = testCylinder(3, 0, 0, 2, 1),
                        .upper_torso = testCylinder(3, 0, 0, 2, 1),
                        .left_pelvis = testCylinder(3, 0, 0, 2, 1),
                        .right_pelvis = testCylinder(3, 0, 0, 2, 1),
                    }),
                },
            },
        };
        var camera: Camera = .{ .follow_target = .ingame_camera };
        var matrices: std.EnumArray(ui.ViewDirection, sdk.math.Mat4) = .initFill(.identity);

        fn guiFunction(_: sdk.ui.TestContext) !void {
            const window_flags = imgui.ImGuiWindowFlags_NoMove |
                imgui.ImGuiWindowFlags_NoResize |
                imgui.ImGuiWindowFlags_NoDecoration |
                imgui.ImGuiWindowFlags_NoSavedSettings;
            imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });
            imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{ .x = 0, .y = 0 });
            defer imgui.igPopStyleVar(2);

            imgui.igSetNextWindowPos(.{ .x = 100, .y = 100 }, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            if (imgui.igBegin("Front", null, window_flags)) {
                defer imgui.igEnd();
                camera.measureWindow(.front);
                const matrix = camera.calculateMatrix(&frame, .front) orelse return error.MatrixCalculationFailed;
                matrices.set(.front, matrix);
            } else imgui.igEnd();

            imgui.igSetNextWindowPos(.{ .x = 100, .y = 400 }, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            if (imgui.igBegin("Top", null, window_flags)) {
                defer imgui.igEnd();
                camera.measureWindow(.top);
                const matrix = camera.calculateMatrix(&frame, .top) orelse return error.MatrixCalculationFailed;
                matrices.set(.top, matrix);
            } else imgui.igEnd();

            imgui.igSetNextWindowPos(.{ .x = 600, .y = 100 }, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            if (imgui.igBegin("Side", null, window_flags)) {
                defer imgui.igEnd();
                camera.measureWindow(.side);
                const matrix = camera.calculateMatrix(&frame, .side) orelse return error.MatrixCalculationFailed;
                matrices.set(.side, matrix);
            } else imgui.igEnd();

            camera.flushWindowMeasurements();
        }

        fn testFunction(_: sdk.ui.TestContext) !void {
            try testing.expectApproxEqAbs(440, testPoint(-7, -4, -4).pointTransform(matrices.get(.front)).x(), 0.0001);
            try testing.expectApproxEqAbs(280, testPoint(-7, -4, -4).pointTransform(matrices.get(.front)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.1, testPoint(-7, -4, -4).pointTransform(matrices.get(.front)).z(), 0.0001);
            try testing.expectApproxEqAbs(300, testPoint(0, 0, 0).pointTransform(matrices.get(.front)).x(), 0.0001);
            try testing.expectApproxEqAbs(200, testPoint(0, 0, 0).pointTransform(matrices.get(.front)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.5, testPoint(0, 0, 0).pointTransform(matrices.get(.front)).z(), 0.0001);
            try testing.expectApproxEqAbs(160, testPoint(7, 4, 4).pointTransform(matrices.get(.front)).x(), 0.0001);
            try testing.expectApproxEqAbs(120, testPoint(7, 4, 4).pointTransform(matrices.get(.front)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.9, testPoint(7, 4, 4).pointTransform(matrices.get(.front)).z(), 0.0001);

            try testing.expectApproxEqAbs(440, testPoint(-7, -4, -4).pointTransform(matrices.get(.top)).x(), 0.0001);
            try testing.expectApproxEqAbs(580, testPoint(-7, -4, -4).pointTransform(matrices.get(.top)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.9, testPoint(-7, -4, -4).pointTransform(matrices.get(.top)).z(), 0.0001);
            try testing.expectApproxEqAbs(300, testPoint(0, 0, 0).pointTransform(matrices.get(.top)).x(), 0.0001);
            try testing.expectApproxEqAbs(500, testPoint(0, 0, 0).pointTransform(matrices.get(.top)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.5, testPoint(0, 0, 0).pointTransform(matrices.get(.top)).z(), 0.0001);
            try testing.expectApproxEqAbs(160, testPoint(7, 4, 4).pointTransform(matrices.get(.top)).x(), 0.0001);
            try testing.expectApproxEqAbs(420, testPoint(7, 4, 4).pointTransform(matrices.get(.top)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.1, testPoint(7, 4, 4).pointTransform(matrices.get(.top)).z(), 0.0001);

            try testing.expectApproxEqAbs(880, testPoint(-7, -4, -4).pointTransform(matrices.get(.side)).x(), 0.0001);
            try testing.expectApproxEqAbs(280, testPoint(-7, -4, -4).pointTransform(matrices.get(.side)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.85, testPoint(-7, -4, -4).pointTransform(matrices.get(.side)).z(), 0.0001);
            try testing.expectApproxEqAbs(800, testPoint(0, 0, 0).pointTransform(matrices.get(.side)).x(), 0.0001);
            try testing.expectApproxEqAbs(200, testPoint(0, 0, 0).pointTransform(matrices.get(.side)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.5, testPoint(0, 0, 0).pointTransform(matrices.get(.side)).z(), 0.0001);
            try testing.expectApproxEqAbs(720, testPoint(7, 4, 4).pointTransform(matrices.get(.side)).x(), 0.0001);
            try testing.expectApproxEqAbs(120, testPoint(7, 4, 4).pointTransform(matrices.get(.side)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.15, testPoint(7, 4, 4).pointTransform(matrices.get(.side)).z(), 0.0001);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should project correctly when follow target is stage" {
    const Test = struct {
        const frame = model.Frame{
            .floor_z = stagePoint(0, 0, 4 - (@as(f32, Camera.stage_vertical_offset) / Camera.stage_padding)).z(),
            .walls = .{
                .buffer = .{
                    testWall(7, 1),
                    testWall(-5, 3),
                    testWall(-7, -3),
                } ++ @as([model.Walls.max_len - 3]model.Wall, @splat(undefined)),
                .len = 3,
            },
        };
        var camera: Camera = .{ .follow_target = .stage };
        var matrices: std.EnumArray(ui.ViewDirection, sdk.math.Mat4) = .initFill(.identity);

        fn guiFunction(_: sdk.ui.TestContext) !void {
            const window_flags = imgui.ImGuiWindowFlags_NoMove |
                imgui.ImGuiWindowFlags_NoResize |
                imgui.ImGuiWindowFlags_NoDecoration |
                imgui.ImGuiWindowFlags_NoSavedSettings;
            imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });
            imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{ .x = 0, .y = 0 });
            defer imgui.igPopStyleVar(2);

            imgui.igSetNextWindowPos(.{ .x = 100, .y = 100 }, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            if (imgui.igBegin("Front", null, window_flags)) {
                defer imgui.igEnd();
                camera.measureWindow(.front);
                const matrix = camera.calculateMatrix(&frame, .front) orelse return error.MatrixCalculationFailed;
                matrices.set(.front, matrix);
            } else imgui.igEnd();

            imgui.igSetNextWindowPos(.{ .x = 100, .y = 400 }, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            if (imgui.igBegin("Top", null, window_flags)) {
                defer imgui.igEnd();
                camera.measureWindow(.top);
                const matrix = camera.calculateMatrix(&frame, .top) orelse return error.MatrixCalculationFailed;
                matrices.set(.top, matrix);
            } else imgui.igEnd();

            imgui.igSetNextWindowPos(.{ .x = 600, .y = 100 }, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            if (imgui.igBegin("Side", null, window_flags)) {
                defer imgui.igEnd();
                camera.measureWindow(.side);
                const matrix = camera.calculateMatrix(&frame, .side) orelse return error.MatrixCalculationFailed;
                matrices.set(.side, matrix);
            } else imgui.igEnd();

            camera.flushWindowMeasurements();
        }

        fn testFunction(_: sdk.ui.TestContext) !void {
            try testing.expectApproxEqAbs(475, stagePoint(-7, -3, 1).pointTransform(matrices.get(.front)).x(), 0.0001);
            try testing.expectApproxEqAbs(275, stagePoint(-7, -3, 1).pointTransform(matrices.get(.front)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.125, stagePoint(-7, -3, 1).pointTransform(matrices.get(.front)).z(), 0.0001);
            try testing.expectApproxEqAbs(300, stagePoint(0, 0, 4).pointTransform(matrices.get(.front)).x(), 0.0001);
            try testing.expectApproxEqAbs(200, stagePoint(0, 0, 4).pointTransform(matrices.get(.front)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.5, stagePoint(0, 0, 4).pointTransform(matrices.get(.front)).z(), 0.0001);
            try testing.expectApproxEqAbs(125, stagePoint(7, 3, 7).pointTransform(matrices.get(.front)).x(), 0.0001);
            try testing.expectApproxEqAbs(125, stagePoint(7, 3, 7).pointTransform(matrices.get(.front)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.875, stagePoint(7, 3, 7).pointTransform(matrices.get(.front)).z(), 0.0001);

            try testing.expectApproxEqAbs(475, stagePoint(-7, -3, 1).pointTransform(matrices.get(.top)).x(), 0.0001);
            try testing.expectApproxEqAbs(575, stagePoint(-7, -3, 1).pointTransform(matrices.get(.top)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.875, stagePoint(-7, -3, 1).pointTransform(matrices.get(.top)).z(), 0.0001);
            try testing.expectApproxEqAbs(300, stagePoint(0, 0, 4).pointTransform(matrices.get(.top)).x(), 0.0001);
            try testing.expectApproxEqAbs(500, stagePoint(0, 0, 4).pointTransform(matrices.get(.top)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.5, stagePoint(0, 0, 4).pointTransform(matrices.get(.top)).z(), 0.0001);
            try testing.expectApproxEqAbs(125, stagePoint(7, 3, 7).pointTransform(matrices.get(.top)).x(), 0.0001);
            try testing.expectApproxEqAbs(425, stagePoint(7, 3, 7).pointTransform(matrices.get(.top)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.125, stagePoint(7, 3, 7).pointTransform(matrices.get(.top)).z(), 0.0001);

            try testing.expectApproxEqAbs(875, stagePoint(-7, -3, 1).pointTransform(matrices.get(.side)).x(), 0.0001);
            try testing.expectApproxEqAbs(275, stagePoint(-7, -3, 1).pointTransform(matrices.get(.side)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.9375, stagePoint(-7, -3, 1).pointTransform(matrices.get(.side)).z(), 0.0001);
            try testing.expectApproxEqAbs(800, stagePoint(0, 0, 4).pointTransform(matrices.get(.side)).x(), 0.0001);
            try testing.expectApproxEqAbs(200, stagePoint(0, 0, 4).pointTransform(matrices.get(.side)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.5, stagePoint(0, 0, 4).pointTransform(matrices.get(.side)).z(), 0.0001);
            try testing.expectApproxEqAbs(725, stagePoint(7, 3, 7).pointTransform(matrices.get(.side)).x(), 0.0001);
            try testing.expectApproxEqAbs(125, stagePoint(7, 3, 7).pointTransform(matrices.get(.side)).y(), 0.0001);
            try testing.expectApproxEqAbs(0.0625, stagePoint(7, 3, 7).pointTransform(matrices.get(.side)).z(), 0.0001);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should zoom in/out on the point that the mouse pointer is pointing when mouse wheel is scrolled" {
    const Test = struct {
        const frame = model.Frame{ .players = .{
            .{
                .collision_spheres = .init(.{
                    .neck = testSphere(-3, 0, 3, 1),
                    .left_elbow = testSphere(-6, 0, 0, 1),
                    .right_elbow = testSphere(-6, 0, 0, 1),
                    .lower_torso = testSphere(-3, 0, 0, 1),
                    .left_knee = testSphere(-3, 0, 0, 1),
                    .right_knee = testSphere(-3, 0, 0, 1),
                    .left_ankle = testSphere(-3, 0, 0, 1),
                    .right_ankle = testSphere(-3, 0, 0, 1),
                }),
                .hurt_cylinders = .init(.{
                    .left_ankle = testCylinder(-3, 0, -3, 2, 1),
                    .right_ankle = testCylinder(-3, 0, -3, 2, 1),
                    .left_hand = testCylinder(-3, -2, 0, 2, 1),
                    .right_hand = testCylinder(-3, 2, 0, 2, 1),
                    .left_knee = testCylinder(-3, 0, 0, 2, 1),
                    .right_knee = testCylinder(-3, 0, 0, 2, 1),
                    .left_elbow = testCylinder(-3, 0, 0, 2, 1),
                    .right_elbow = testCylinder(-3, 0, 0, 2, 1),
                    .head = testCylinder(-3, 0, 0, 2, 1),
                    .left_shoulder = testCylinder(-3, 0, 0, 2, 1),
                    .right_shoulder = testCylinder(-3, 0, 0, 2, 1),
                    .upper_torso = testCylinder(-3, 0, 0, 2, 1),
                    .left_pelvis = testCylinder(-3, 0, 0, 2, 1),
                    .right_pelvis = testCylinder(-3, 0, 0, 2, 1),
                }),
            },
            .{
                .collision_spheres = .init(.{
                    .neck = testSphere(3, 0, 3, 1),
                    .left_elbow = testSphere(6, 0, 0, 1),
                    .right_elbow = testSphere(6, 0, 0, 1),
                    .lower_torso = testSphere(3, 0, 0, 1),
                    .left_knee = testSphere(3, 0, 0, 1),
                    .right_knee = testSphere(3, 0, 0, 1),
                    .left_ankle = testSphere(3, 0, 0, 1),
                    .right_ankle = testSphere(3, 0, 0, 1),
                }),
                .hurt_cylinders = .init(.{
                    .left_ankle = testCylinder(3, 0, -3, 2, 1),
                    .right_ankle = testCylinder(3, 0, -3, 2, 1),
                    .left_hand = testCylinder(3, -2, 0, 2, 1),
                    .right_hand = testCylinder(3, 2, 0, 2, 1),
                    .left_knee = testCylinder(3, 0, 0, 2, 1),
                    .right_knee = testCylinder(3, 0, 0, 2, 1),
                    .left_elbow = testCylinder(3, 0, 0, 2, 1),
                    .right_elbow = testCylinder(3, 0, 0, 2, 1),
                    .head = testCylinder(3, 0, 0, 2, 1),
                    .left_shoulder = testCylinder(3, 0, 0, 2, 1),
                    .right_shoulder = testCylinder(3, 0, 0, 2, 1),
                    .upper_torso = testCylinder(3, 0, 0, 2, 1),
                    .left_pelvis = testCylinder(3, 0, 0, 2, 1),
                    .right_pelvis = testCylinder(3, 0, 0, 2, 1),
                }),
            },
        } };
        var camera: Camera = .{ .follow_target = .players };
        var matrices: std.EnumArray(ui.ViewDirection, sdk.math.Mat4) = .initFill(.identity);
        var inverse_matrices: std.EnumArray(ui.ViewDirection, sdk.math.Mat4) = .initFill(.identity);

        fn guiFunction(_: sdk.ui.TestContext) !void {
            const window_flags = imgui.ImGuiWindowFlags_NoMove |
                imgui.ImGuiWindowFlags_NoResize |
                imgui.ImGuiWindowFlags_NoDecoration |
                imgui.ImGuiWindowFlags_NoSavedSettings;
            imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });
            imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{ .x = 0, .y = 0 });
            defer imgui.igPopStyleVar(2);

            imgui.igSetNextWindowPos(.{ .x = 100, .y = 100 }, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            if (imgui.igBegin("Front", null, window_flags)) {
                defer imgui.igEnd();
                camera.processInput(.front, inverse_matrices.get(.front));
                camera.measureWindow(.front);
                const matrix = camera.calculateMatrix(&frame, .front) orelse return error.MatrixCalculationFailed;
                const inverse_matrix = matrix.inverse() orelse return error.InverseMatrixCalculationFailed;
                matrices.set(.front, matrix);
                inverse_matrices.set(.front, inverse_matrix);
            } else imgui.igEnd();

            imgui.igSetNextWindowPos(.{ .x = 100, .y = 400 }, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            if (imgui.igBegin("Top", null, window_flags)) {
                defer imgui.igEnd();
                camera.processInput(.top, inverse_matrices.get(.top));
                camera.measureWindow(.top);
                const matrix = camera.calculateMatrix(&frame, .top) orelse return error.MatrixCalculationFailed;
                const inverse_matrix = matrix.inverse() orelse return error.InverseMatrixCalculationFailed;
                matrices.set(.top, matrix);
                inverse_matrices.set(.top, inverse_matrix);
            } else imgui.igEnd();

            imgui.igSetNextWindowPos(.{ .x = 600, .y = 100 }, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            if (imgui.igBegin("Side", null, window_flags)) {
                defer imgui.igEnd();
                camera.processInput(.side, inverse_matrices.get(.side));
                camera.measureWindow(.side);
                const matrix = camera.calculateMatrix(&frame, .side) orelse return error.MatrixCalculationFailed;
                const inverse_matrix = matrix.inverse() orelse return error.InverseMatrixCalculationFailed;
                matrices.set(.side, matrix);
                inverse_matrices.set(.side, inverse_matrix);
            } else imgui.igEnd();

            camera.flushWindowMeasurements();
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const Case = struct {
                screen_point: sdk.math.Vec3,
                direction: ui.ViewDirection,
            };
            const cases = [_]Case{
                .{ .screen_point = .fromArray(.{ 360, 200, 0.5 }), .direction = .front },
                .{ .screen_point = .fromArray(.{ 240, 500, 0.5 }), .direction = .top },
                .{ .screen_point = .fromArray(.{ 800, 140, 0.5 }), .direction = .side },
            };
            for (cases) |case| {
                ctx.mouseMoveToPos(case.screen_point.swizzle("xy").toImVec());
                const world_point_1 = case.screen_point.pointTransform(inverse_matrices.get(case.direction));
                const scale_1 = sdk.math.Vec3.ones.directionTransform(matrices.get(case.direction));
                ctx.mouseWheelY(1);
                const world_point_2 = case.screen_point.pointTransform(inverse_matrices.get(case.direction));
                const scale_2 = sdk.math.Vec3.ones.directionTransform(matrices.get(case.direction));
                try testing.expectApproxEqAbs(world_point_1.x(), world_point_2.x(), 0.0001);
                try testing.expectApproxEqAbs(world_point_1.y(), world_point_2.y(), 0.0001);
                try testing.expectApproxEqAbs(world_point_1.z(), world_point_2.z(), 0.0001);
                try testing.expectApproxEqAbs(Camera.zoom_speed * scale_1.x(), scale_2.x(), 0.0001);
                try testing.expectApproxEqAbs(Camera.zoom_speed * scale_1.y(), scale_2.y(), 0.0001);
                try testing.expectApproxEqAbs(Camera.zoom_speed * scale_1.z(), scale_2.z(), 0.0001);
                ctx.mouseWheelY(-1);
                const world_point_3 = case.screen_point.pointTransform(inverse_matrices.get(case.direction));
                const scale_3 = sdk.math.Vec3.ones.directionTransform(matrices.get(case.direction));
                try testing.expectApproxEqAbs(world_point_1.x(), world_point_3.x(), 0.0001);
                try testing.expectApproxEqAbs(world_point_1.y(), world_point_3.y(), 0.0001);
                try testing.expectApproxEqAbs(world_point_1.z(), world_point_3.z(), 0.0001);
                try testing.expectApproxEqAbs(scale_1.x(), scale_3.x(), 0.0001);
                try testing.expectApproxEqAbs(scale_1.y(), scale_3.y(), 0.0001);
                try testing.expectApproxEqAbs(scale_1.z(), scale_3.z(), 0.0001);
            }
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should translate the view when the view is right mouse button dragged without a modifier key" {
    const Test = struct {
        const frame = model.Frame{ .players = .{
            .{
                .collision_spheres = .init(.{
                    .neck = testSphere(-3, 0, 3, 1),
                    .left_elbow = testSphere(-6, 0, 0, 1),
                    .right_elbow = testSphere(-6, 0, 0, 1),
                    .lower_torso = testSphere(-3, 0, 0, 1),
                    .left_knee = testSphere(-3, 0, 0, 1),
                    .right_knee = testSphere(-3, 0, 0, 1),
                    .left_ankle = testSphere(-3, 0, 0, 1),
                    .right_ankle = testSphere(-3, 0, 0, 1),
                }),
                .hurt_cylinders = .init(.{
                    .left_ankle = testCylinder(-3, 0, -3, 2, 1),
                    .right_ankle = testCylinder(-3, 0, -3, 2, 1),
                    .left_hand = testCylinder(-3, -2, 0, 2, 1),
                    .right_hand = testCylinder(-3, 2, 0, 2, 1),
                    .left_knee = testCylinder(-3, 0, 0, 2, 1),
                    .right_knee = testCylinder(-3, 0, 0, 2, 1),
                    .left_elbow = testCylinder(-3, 0, 0, 2, 1),
                    .right_elbow = testCylinder(-3, 0, 0, 2, 1),
                    .head = testCylinder(-3, 0, 0, 2, 1),
                    .left_shoulder = testCylinder(-3, 0, 0, 2, 1),
                    .right_shoulder = testCylinder(-3, 0, 0, 2, 1),
                    .upper_torso = testCylinder(-3, 0, 0, 2, 1),
                    .left_pelvis = testCylinder(-3, 0, 0, 2, 1),
                    .right_pelvis = testCylinder(-3, 0, 0, 2, 1),
                }),
            },
            .{
                .collision_spheres = .init(.{
                    .neck = testSphere(3, 0, 3, 1),
                    .left_elbow = testSphere(6, 0, 0, 1),
                    .right_elbow = testSphere(6, 0, 0, 1),
                    .lower_torso = testSphere(3, 0, 0, 1),
                    .left_knee = testSphere(3, 0, 0, 1),
                    .right_knee = testSphere(3, 0, 0, 1),
                    .left_ankle = testSphere(3, 0, 0, 1),
                    .right_ankle = testSphere(3, 0, 0, 1),
                }),
                .hurt_cylinders = .init(.{
                    .left_ankle = testCylinder(3, 0, -3, 2, 1),
                    .right_ankle = testCylinder(3, 0, -3, 2, 1),
                    .left_hand = testCylinder(3, -2, 0, 2, 1),
                    .right_hand = testCylinder(3, 2, 0, 2, 1),
                    .left_knee = testCylinder(3, 0, 0, 2, 1),
                    .right_knee = testCylinder(3, 0, 0, 2, 1),
                    .left_elbow = testCylinder(3, 0, 0, 2, 1),
                    .right_elbow = testCylinder(3, 0, 0, 2, 1),
                    .head = testCylinder(3, 0, 0, 2, 1),
                    .left_shoulder = testCylinder(3, 0, 0, 2, 1),
                    .right_shoulder = testCylinder(3, 0, 0, 2, 1),
                    .upper_torso = testCylinder(3, 0, 0, 2, 1),
                    .left_pelvis = testCylinder(3, 0, 0, 2, 1),
                    .right_pelvis = testCylinder(3, 0, 0, 2, 1),
                }),
            },
        } };
        var camera: Camera = .{ .follow_target = .players };
        var inverse_matrices: std.EnumArray(ui.ViewDirection, sdk.math.Mat4) = .initFill(.identity);
        var cursor = imgui.ImGuiMouseCursor_None;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            const window_flags = imgui.ImGuiWindowFlags_NoMove |
                imgui.ImGuiWindowFlags_NoResize |
                imgui.ImGuiWindowFlags_NoDecoration |
                imgui.ImGuiWindowFlags_NoSavedSettings;
            imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });
            imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{ .x = 0, .y = 0 });
            defer imgui.igPopStyleVar(2);

            imgui.igSetNextWindowPos(.{ .x = 100, .y = 100 }, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            if (imgui.igBegin("Front", null, window_flags)) {
                defer imgui.igEnd();
                camera.processInput(.front, inverse_matrices.get(.front));
                camera.measureWindow(.front);
                const matrix = camera.calculateMatrix(&frame, .front) orelse return error.MatrixCalculationFailed;
                const inverse_matrix = matrix.inverse() orelse return error.InverseMatrixCalculationFailed;
                inverse_matrices.set(.front, inverse_matrix);
            } else imgui.igEnd();

            imgui.igSetNextWindowPos(.{ .x = 100, .y = 400 }, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            if (imgui.igBegin("Top", null, window_flags)) {
                defer imgui.igEnd();
                camera.processInput(.top, inverse_matrices.get(.top));
                camera.measureWindow(.top);
                const matrix = camera.calculateMatrix(&frame, .top) orelse return error.MatrixCalculationFailed;
                const inverse_matrix = matrix.inverse() orelse return error.InverseMatrixCalculationFailed;
                inverse_matrices.set(.top, inverse_matrix);
            } else imgui.igEnd();

            imgui.igSetNextWindowPos(.{ .x = 600, .y = 100 }, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            if (imgui.igBegin("Side", null, window_flags)) {
                defer imgui.igEnd();
                camera.processInput(.side, inverse_matrices.get(.side));
                camera.measureWindow(.side);
                const matrix = camera.calculateMatrix(&frame, .side) orelse return error.MatrixCalculationFailed;
                const inverse_matrix = matrix.inverse() orelse return error.InverseMatrixCalculationFailed;
                inverse_matrices.set(.side, inverse_matrix);
            } else imgui.igEnd();

            camera.flushWindowMeasurements();
            cursor = imgui.igGetMouseCursor();
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const Case = struct {
                drag_from: sdk.math.Vec3,
                drag_to: sdk.math.Vec3,
                direction: ui.ViewDirection,
            };
            const cases = [_]Case{
                .{
                    .drag_from = .fromArray(.{ 420, 260, 0.5 }),
                    .drag_to = .fromArray(.{ 180, 140, 0.5 }),
                    .direction = .front,
                },
                .{
                    .drag_from = .fromArray(.{ 420, 560, 0.5 }),
                    .drag_to = .fromArray(.{ 180, 440, 0.5 }),
                    .direction = .top,
                },
                .{
                    .drag_from = .fromArray(.{ 860, 260, 0.5 }),
                    .drag_to = .fromArray(.{ 740, 140, 0.5 }),
                    .direction = .side,
                },
            };
            for (cases) |case| {
                ctx.mouseMoveToPos(case.drag_from.swizzle("xy").toImVec());
                try testing.expectEqual(imgui.ImGuiMouseCursor_Arrow, cursor);
                ctx.mouseDown(imgui.ImGuiMouseButton_Right);
                try testing.expectEqual(imgui.ImGuiMouseCursor_ResizeAll, cursor);
                const world_drag_from = case.drag_from.pointTransform(inverse_matrices.get(case.direction));
                ctx.mouseMoveToPos(case.drag_to.swizzle("xy").toImVec());
                const world_drag_to = case.drag_to.pointTransform(inverse_matrices.get(case.direction));
                try testing.expectEqual(imgui.ImGuiMouseCursor_ResizeAll, cursor);
                ctx.mouseUp(imgui.ImGuiMouseButton_Right);
                try testing.expectEqual(imgui.ImGuiMouseCursor_Arrow, cursor);
                try testing.expectApproxEqAbs(world_drag_from.x(), world_drag_to.x(), 0.001);
                try testing.expectApproxEqAbs(world_drag_from.y(), world_drag_to.y(), 0.001);
                try testing.expectApproxEqAbs(world_drag_from.z(), world_drag_to.z(), 0.001);
            }
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should rotate the view when the view is right mouse button dragged with a modifier key" {
    const Test = struct {
        const frame = model.Frame{ .players = .{
            .{
                .collision_spheres = .init(.{
                    .neck = testSphere(-3, 0, 3, 1),
                    .left_elbow = testSphere(-6, 0, 0, 1),
                    .right_elbow = testSphere(-6, 0, 0, 1),
                    .lower_torso = testSphere(-3, 0, 0, 1),
                    .left_knee = testSphere(-3, 0, 0, 1),
                    .right_knee = testSphere(-3, 0, 0, 1),
                    .left_ankle = testSphere(-3, 0, 0, 1),
                    .right_ankle = testSphere(-3, 0, 0, 1),
                }),
                .hurt_cylinders = .init(.{
                    .left_ankle = testCylinder(-3, 0, -3, 2, 1),
                    .right_ankle = testCylinder(-3, 0, -3, 2, 1),
                    .left_hand = testCylinder(-3, -2, 0, 2, 1),
                    .right_hand = testCylinder(-3, 2, 0, 2, 1),
                    .left_knee = testCylinder(-3, 0, 0, 2, 1),
                    .right_knee = testCylinder(-3, 0, 0, 2, 1),
                    .left_elbow = testCylinder(-3, 0, 0, 2, 1),
                    .right_elbow = testCylinder(-3, 0, 0, 2, 1),
                    .head = testCylinder(-3, 0, 0, 2, 1),
                    .left_shoulder = testCylinder(-3, 0, 0, 2, 1),
                    .right_shoulder = testCylinder(-3, 0, 0, 2, 1),
                    .upper_torso = testCylinder(-3, 0, 0, 2, 1),
                    .left_pelvis = testCylinder(-3, 0, 0, 2, 1),
                    .right_pelvis = testCylinder(-3, 0, 0, 2, 1),
                }),
            },
            .{
                .collision_spheres = .init(.{
                    .neck = testSphere(3, 0, 3, 1),
                    .left_elbow = testSphere(6, 0, 0, 1),
                    .right_elbow = testSphere(6, 0, 0, 1),
                    .lower_torso = testSphere(3, 0, 0, 1),
                    .left_knee = testSphere(3, 0, 0, 1),
                    .right_knee = testSphere(3, 0, 0, 1),
                    .left_ankle = testSphere(3, 0, 0, 1),
                    .right_ankle = testSphere(3, 0, 0, 1),
                }),
                .hurt_cylinders = .init(.{
                    .left_ankle = testCylinder(3, 0, -3, 2, 1),
                    .right_ankle = testCylinder(3, 0, -3, 2, 1),
                    .left_hand = testCylinder(3, -2, 0, 2, 1),
                    .right_hand = testCylinder(3, 2, 0, 2, 1),
                    .left_knee = testCylinder(3, 0, 0, 2, 1),
                    .right_knee = testCylinder(3, 0, 0, 2, 1),
                    .left_elbow = testCylinder(3, 0, 0, 2, 1),
                    .right_elbow = testCylinder(3, 0, 0, 2, 1),
                    .head = testCylinder(3, 0, 0, 2, 1),
                    .left_shoulder = testCylinder(3, 0, 0, 2, 1),
                    .right_shoulder = testCylinder(3, 0, 0, 2, 1),
                    .upper_torso = testCylinder(3, 0, 0, 2, 1),
                    .left_pelvis = testCylinder(3, 0, 0, 2, 1),
                    .right_pelvis = testCylinder(3, 0, 0, 2, 1),
                }),
            },
        } };
        var camera: Camera = .{ .follow_target = .players };
        var matrices: std.EnumArray(ui.ViewDirection, sdk.math.Mat4) = .initFill(.identity);
        var inverse_matrices: std.EnumArray(ui.ViewDirection, sdk.math.Mat4) = .initFill(.identity);
        var cursor = imgui.ImGuiMouseCursor_None;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            const window_flags = imgui.ImGuiWindowFlags_NoMove |
                imgui.ImGuiWindowFlags_NoResize |
                imgui.ImGuiWindowFlags_NoDecoration |
                imgui.ImGuiWindowFlags_NoSavedSettings;
            imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });
            imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{ .x = 0, .y = 0 });
            defer imgui.igPopStyleVar(2);

            imgui.igSetNextWindowPos(.{ .x = 100, .y = 100 }, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            if (imgui.igBegin("Front", null, window_flags)) {
                defer imgui.igEnd();
                camera.processInput(.front, inverse_matrices.get(.front));
                camera.measureWindow(.front);
                const matrix = camera.calculateMatrix(&frame, .front) orelse return error.MatrixCalculationFailed;
                const inverse_matrix = matrix.inverse() orelse return error.InverseMatrixCalculationFailed;
                matrices.set(.front, matrix);
                inverse_matrices.set(.front, inverse_matrix);
            } else imgui.igEnd();

            imgui.igSetNextWindowPos(.{ .x = 100, .y = 400 }, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            if (imgui.igBegin("Top", null, window_flags)) {
                defer imgui.igEnd();
                camera.processInput(.top, inverse_matrices.get(.top));
                camera.measureWindow(.top);
                const matrix = camera.calculateMatrix(&frame, .top) orelse return error.MatrixCalculationFailed;
                const inverse_matrix = matrix.inverse() orelse return error.InverseMatrixCalculationFailed;
                matrices.set(.top, matrix);
                inverse_matrices.set(.top, inverse_matrix);
            } else imgui.igEnd();

            imgui.igSetNextWindowPos(.{ .x = 600, .y = 100 }, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(.{ .x = 400, .y = 200 }, imgui.ImGuiCond_Always);
            if (imgui.igBegin("Side", null, window_flags)) {
                defer imgui.igEnd();
                camera.processInput(.side, inverse_matrices.get(.side));
                camera.measureWindow(.side);
                const matrix = camera.calculateMatrix(&frame, .side) orelse return error.MatrixCalculationFailed;
                const inverse_matrix = matrix.inverse() orelse return error.InverseMatrixCalculationFailed;
                matrices.set(.side, matrix);
                inverse_matrices.set(.side, inverse_matrix);
            } else imgui.igEnd();

            camera.flushWindowMeasurements();
            cursor = imgui.igGetMouseCursor();
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.keyDown(imgui.ImGuiKey_LeftCtrl);
            defer ctx.keyUp(imgui.ImGuiKey_LeftCtrl);

            try testing.expectApproxEqAbs(320, testPoint(1, 0, 0).pointTransform(matrices.get(.top)).x(), 0.0001);
            try testing.expectApproxEqAbs(500, testPoint(1, 0, 0).pointTransform(matrices.get(.top)).y(), 0.0001);

            ctx.mouseMoveToPos(.{ .x = 440, .y = 200 });
            try testing.expectEqual(imgui.ImGuiMouseCursor_Arrow, cursor);
            ctx.mouseDown(imgui.ImGuiMouseButton_Right);
            try testing.expectEqual(imgui.ImGuiMouseCursor_ResizeEW, cursor);
            try testing.expectApproxEqAbs(0, camera.transform.rotation, 0.0001);
            ctx.mouseMoveToPos(.{ .x = 300, .y = 200 });
            try testing.expectEqual(imgui.ImGuiMouseCursor_ResizeEW, cursor);
            try testing.expectApproxEqAbs(-0.5 * std.math.pi, camera.transform.rotation, 0.0001);
            ctx.mouseMoveToPos(.{ .x = 160, .y = 200 });
            try testing.expectEqual(imgui.ImGuiMouseCursor_ResizeEW, cursor);
            try testing.expectApproxEqAbs(-std.math.pi, camera.transform.rotation, 0.0001);
            ctx.mouseUp(imgui.ImGuiMouseButton_Right);
            try testing.expectEqual(imgui.ImGuiMouseCursor_Arrow, cursor);

            try testing.expectApproxEqAbs(280, testPoint(1, 0, 0).pointTransform(matrices.get(.top)).x(), 0.0001);
            try testing.expectApproxEqAbs(500, testPoint(1, 0, 0).pointTransform(matrices.get(.top)).y(), 0.0001);

            ctx.mouseMoveToPos(.{ .x = 720, .y = 200 });
            try testing.expectEqual(imgui.ImGuiMouseCursor_Arrow, cursor);
            ctx.mouseDown(imgui.ImGuiMouseButton_Right);
            try testing.expectEqual(imgui.ImGuiMouseCursor_ResizeEW, cursor);
            try testing.expectApproxEqAbs(-std.math.pi, camera.transform.rotation, 0.0001);
            try testing.expectEqual(imgui.ImGuiMouseCursor_ResizeEW, cursor);
            ctx.mouseMoveToPos(.{ .x = 800, .y = 200 });
            try testing.expectApproxEqAbs(-0.5 * std.math.pi, camera.transform.rotation, 0.0001);
            try testing.expectEqual(imgui.ImGuiMouseCursor_ResizeEW, cursor);
            ctx.mouseMoveToPos(.{ .x = 880, .y = 200 });
            try testing.expectEqual(imgui.ImGuiMouseCursor_ResizeEW, cursor);
            try testing.expectApproxEqAbs(0, camera.transform.rotation, 0.0001);
            ctx.mouseUp(imgui.ImGuiMouseButton_Right);
            try testing.expectEqual(imgui.ImGuiMouseCursor_Arrow, cursor);

            try testing.expectApproxEqAbs(320, testPoint(1, 0, 0).pointTransform(matrices.get(.top)).x(), 0.0001);
            try testing.expectApproxEqAbs(500, testPoint(1, 0, 0).pointTransform(matrices.get(.top)).y(), 0.0001);

            ctx.mouseMoveToPos(.{ .x = 380, .y = 500 });
            try testing.expectEqual(imgui.ImGuiMouseCursor_Arrow, cursor);
            ctx.mouseDown(imgui.ImGuiMouseButton_Right);
            try testing.expectEqual(imgui.ImGuiMouseCursor_ResizeNS, cursor);
            try testing.expectApproxEqAbs(0, camera.transform.rotation, 0.0001);
            ctx.mouseMoveToPos(.{ .x = 380, .y = 420 });
            try testing.expectEqual(imgui.ImGuiMouseCursor_ResizeNWSE, cursor);
            try testing.expectApproxEqAbs(0.25 * std.math.pi, camera.transform.rotation, 0.0001);
            ctx.mouseMoveToPos(.{ .x = 220, .y = 420 });
            try testing.expectEqual(imgui.ImGuiMouseCursor_ResizeNESW, cursor);
            try testing.expectApproxEqAbs(0.75 * std.math.pi, camera.transform.rotation, 0.0001);
            ctx.mouseMoveToPos(.{ .x = 300, .y = 420 });
            try testing.expectEqual(imgui.ImGuiMouseCursor_ResizeEW, cursor);
            try testing.expectApproxEqAbs(0.5 * std.math.pi, camera.transform.rotation, 0.0001);
            ctx.mouseUp(imgui.ImGuiMouseButton_Right);

            try testing.expectApproxEqAbs(300, testPoint(1, 0, 0).pointTransform(matrices.get(.top)).x(), 0.0001);
            try testing.expectApproxEqAbs(480, testPoint(1, 0, 0).pointTransform(matrices.get(.top)).y(), 0.0001);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should change follow target when a target is selected by clicking a menu bar button" {
    const Test = struct {
        var camera: Camera = .{ .follow_target = .players };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            camera.drawMenuBar();
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(.players, camera.follow_target);
            ctx.menuClick("Camera/Follow Ingame Camera");
            try testing.expectEqual(.ingame_camera, camera.follow_target);
            ctx.menuClick("Camera/Follow Players");
            try testing.expectEqual(.players, camera.follow_target);
            ctx.menuClick("Camera/Follow Stage Bounds");
            try testing.expectEqual(.stage, camera.follow_target);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should change follow target when a target a keyboard shortcut is pressed" {
    const Test = struct {
        var camera: Camera = .{ .follow_target = .players };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            camera.drawMenuBar();
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try testing.expectEqual(.players, camera.follow_target);
            ctx.keyPress(imgui.ImGuiMod_Shift | imgui.ImGuiKey_1, 1);
            try testing.expectEqual(.ingame_camera, camera.follow_target);
            ctx.keyPress(imgui.ImGuiMod_Shift | imgui.ImGuiKey_3, 1);
            try testing.expectEqual(.stage, camera.follow_target);
            ctx.keyPress(imgui.ImGuiMod_Shift | imgui.ImGuiKey_2, 1);
            try testing.expectEqual(.players, camera.follow_target);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should set transform to default value when menu bar reset view offset button is clicked" {
    const Test = struct {
        var camera: Camera = .{ .transform = .{
            .translation = .fromArray(.{ 1, 2, 3 }),
            .scale = 4,
            .rotation = 5,
        } };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            camera.drawMenuBar();
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expect(!std.meta.eql(Camera.Transform{}, camera.transform));
            ctx.menuClick("Camera/Reset View Offset");
            try testing.expectEqual(Camera.Transform{}, camera.transform);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
