const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("../ui/root.zig");

pub const Camera = struct {
    windows: std.EnumArray(ui.ViewDirection, Window) = .initFill(.{}),
    follow_target: FollowTarget = .ingame_camera,
    transform: Transform = .{},
    rotation_radius: ?f32 = null,

    const Self = @This();
    pub const Window = struct {
        position: sdk.math.Vec2 = .zero,
        size: sdk.math.Vec2 = .zero,
    };
    pub const FollowTarget = enum {
        ingame_camera,
        players,
        origin,
    };
    pub const Transform = struct {
        translation: sdk.math.Vec3 = .zero,
        scale: f32 = 1.0,
        rotation: f32 = 0.0,
    };

    pub fn updateWindowState(self: *Self, direction: ui.ViewDirection) void {
        var window: Window = undefined;
        imgui.igGetCursorScreenPos(window.position.asImVec());
        imgui.igGetContentRegionAvail(window.size.asImVec());
        self.windows.set(direction, window);
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

            const scale_factor = std.math.pow(f32, 1.2, wheel);
            const delta_translation = world_mouse.subtract(world_camera).scale(1.0 / scale_factor - 1.0);
            self.transform.translation = self.transform.translation.add(delta_translation);
            self.transform.scale *= scale_factor;
        }
        if (imgui.igIsKeyDown_Nil(imgui.ImGuiKey_MouseLeft)) {
            const delta_mouse = imgui.igGetIO_Nil().*.MouseDelta;
            const delta_screen = sdk.math.Vec2.fromImVec(delta_mouse).extend(0);
            const delta_world = delta_screen.directionTransform(inverse_matrix);
            self.transform.translation = self.transform.translation.add(delta_world);
            imgui.igSetMouseCursor(imgui.ImGuiMouseCursor_ResizeAll);
        }
        if (direction != .top and imgui.igIsKeyDown_Nil(imgui.ImGuiKey_MouseRight)) {
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

            self.transform.rotation = std.math.wrap(self.transform.rotation + delta_angle, std.math.pi);
            imgui.igSetMouseCursor(imgui.ImGuiMouseCursor_ResizeEW);
        } else {
            self.rotation_radius = null;
        }
        if (direction == .top and imgui.igIsKeyDown_Nil(imgui.ImGuiKey_MouseRight)) {
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
        if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_MouseMiddle, false)) {
            self.transform = .{};
        }
    }

    pub fn drawMenuBar(self: *Self) void {
        if (imgui.igMenuItem_Bool("Follow Ingame Camera", null, self.follow_target == .ingame_camera, true)) {
            self.follow_target = .ingame_camera;
        }
        if (imgui.igMenuItem_Bool("Follow Players", null, self.follow_target == .players, true)) {
            self.follow_target = .players;
        }
        if (imgui.igMenuItem_Bool("Stay At Origin", null, self.follow_target == .origin, true)) {
            self.follow_target = .origin;
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
            .origin => calculateOriginLookAtMatrix(frame, direction),
        };
        const rotation_matrix = switch (direction) {
            .front, .side => sdk.math.Mat4.fromYRotation(self.transform.rotation),
            .top => sdk.math.Mat4.fromZRotation(-self.transform.rotation),
        };
        const scale_matrix = sdk.math.Mat4.fromScale(sdk.math.Vec3.fill(self.transform.scale));
        const orthographic_matrix = self.calculateOrthographicMatrix(
            frame,
            direction,
            look_at_matrix,
            self.follow_target == .origin,
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
        const left_player = frame.getPlayerBySide(.left).position orelse return null;
        const right_player = frame.getPlayerBySide(.right).position orelse return null;
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
        const left_player = frame.getPlayerBySide(.left).position orelse return null;
        const right_player = frame.getPlayerBySide(.right).position orelse return null;
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

    fn calculateOriginLookAtMatrix(frame: *const model.Frame, direction: ui.ViewDirection) sdk.math.Mat4 {
        const floor_z = frame.floor_z orelse 0.0;
        const eye = sdk.math.Vec3.fromArray(.{ 0.0, 0.0, floor_z + 90.0 });
        const target = switch (direction) {
            .front => eye.add(sdk.math.Vec3.plus_y),
            .side => eye.add(sdk.math.Vec3.minus_x),
            .top => eye.add(sdk.math.Vec3.minus_z),
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
        use_static_scale: bool,
    ) ?sdk.math.Mat4 {
        const world_box = if (use_static_scale) sdk.math.Vec3.fill(280) else block: {
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
                        const half_size = sdk.math.Vec3.fromArray(.{
                            cylinder.radius,
                            cylinder.radius,
                            cylinder.half_height,
                        });
                        min = sdk.math.Vec3.minElements(min, pos.subtract(half_size));
                        max = sdk.math.Vec3.maxElements(max, pos.add(half_size));
                    }
                }
            }
            const padding = sdk.math.Vec3.fill(50);
            break :block sdk.math.Vec3.maxElements(min.negate(), max).add(padding).scale(2);
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
            .scale(sdk.math.Vec3.fromArray(.{ -0.5 * window.size.x(), -0.5 * window.size.y(), 1 }))
            .translate(window.size.scale(0.5).add(window.position).extend(0));
    }
};
