const std = @import("std");
const imgui = @import("imgui");
const math = @import("../math/root.zig");
const game = @import("../game/root.zig");

pub const View = struct {
    window_size: std.EnumArray(Direction, math.Vec2) = .initFill(math.Vec2.zero),
    previous_frame: ?Frame = null,
    current_frame: ?Frame = null,

    const Self = @This();
    pub const Direction = enum {
        front,
        side,
        top,
    };
    pub const Player = struct {
        hit_lines: game.HitLines,
        hurt_cylinders: game.HurtCylinders,
        collision_spheres: game.CollisionSpheres,
    };
    const Frame = [2]Player;

    const collision_spheres_color = imgui.ImVec4{ .x = 0.0, .y = 0.0, .z = 1.0, .w = 0.5 };
    const collision_spheres_thickness = 1.0;
    const hurt_cylinders_color = imgui.ImVec4{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 0.5 };
    const hurt_cylinders_thickness = 1.0;
    const stick_figure_color = imgui.ImVec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 };
    const stick_figure_thickness = 2.0;
    const hit_line_color = imgui.ImVec4{ .x = 1.0, .y = 0.0, .z = 0.0, .w = 1.0 };
    const hit_line_thickness = 1.0;

    pub fn tick(self: *Self, player_1: ?*const Player, player_2: ?*const Player) void {
        self.previous_frame = self.current_frame;
        const p1 = player_1 orelse {
            self.current_frame = null;
            return;
        };
        const p2 = player_2 orelse {
            self.current_frame = null;
            return;
        };
        self.current_frame = .{ p1.*, p2.* };
    }

    pub fn draw(self: *Self, direction: Direction) void {
        self.updateWindowSize(direction);
        const matrix = self.calculateFinalMatrix(direction) orelse return;
        const inverse_matrix = matrix.inverse() orelse math.Mat4.identity;
        self.drawCollisionSpheres(matrix, inverse_matrix);
        self.drawHurtCylinders(direction, matrix, inverse_matrix);
        self.drawStickFigures(matrix);
        self.drawHitLines(matrix);
    }

    fn updateWindowSize(self: *Self, direction: Direction) void {
        var window_size: math.Vec2 = undefined;
        imgui.igGetContentRegionAvail(window_size.asImVec());
        self.window_size.set(direction, window_size);
    }

    fn calculateFinalMatrix(self: *const Self, direction: Direction) ?math.Mat4 {
        const look_at_matrix = self.calculateLookAtMatrix(direction) orelse return null;
        const orthographic_matrix = self.calculateOrthographicMatrix(direction, look_at_matrix) orelse return null;
        const window_matrix = calculateWindowMatrix();
        return look_at_matrix.multiply(orthographic_matrix).multiply(window_matrix);
    }

    fn calculateLookAtMatrix(self: *const Self, direction: Direction) ?math.Mat4 {
        const frame = if (self.current_frame) |*f| f else return null;
        const p1 = frame[0].collision_spheres.lower_torso.position;
        const p2 = frame[1].collision_spheres.lower_torso.position;
        const eye = p1.add(p2).scale(0.5);
        const difference_2d = p2.swizzle("xy").subtract(p1.swizzle("xy"));
        const player_dir = if (!difference_2d.isZero(0)) difference_2d.normalize().extend(0) else math.Vec3.plus_x;
        const look_direction = switch (direction) {
            .front => player_dir.cross(math.Vec3.minus_z),
            .side => player_dir.negate(),
            .top => math.Vec3.plus_z,
        };
        const target = eye.add(look_direction);
        const up = switch (direction) {
            .front, .side => math.Vec3.plus_z,
            .top => player_dir.cross(math.Vec3.plus_z),
        };
        return math.Mat4.fromLookAt(eye, target, up);
    }

    fn calculateOrthographicMatrix(self: *const Self, direction: Direction, look_at_matrix: math.Mat4) ?math.Mat4 {
        const frame = if (self.current_frame) |*f| f else return null;
        var min = math.Vec3.fill(std.math.inf(f32));
        var max = math.Vec3.fill(-std.math.inf(f32));
        for (frame) |player| {
            for (player.collision_spheres.asConstArray()) |*sphere| {
                const pos = sphere.position.pointTransform(look_at_matrix);
                const half_size = math.Vec3.fill(sphere.radius);
                min = math.Vec3.minElements(min, pos.subtract(half_size));
                max = math.Vec3.maxElements(max, pos.add(half_size));
            }
            for (player.hurt_cylinders.asConstArray()) |*cylinder| {
                const pos = cylinder.position.pointTransform(look_at_matrix);
                const half_size = math.Vec3.fromArray(.{
                    cylinder.radius,
                    cylinder.radius,
                    cylinder.half_height,
                });
                min = math.Vec3.minElements(min, pos.subtract(half_size));
                max = math.Vec3.maxElements(max, pos.add(half_size));
            }
        }
        const padding = math.Vec3.fill(50);
        const world_box = math.Vec3.maxElements(min.negate(), max).add(padding).scale(2);
        const screen_box = switch (direction) {
            .front => math.Vec3.fromArray(.{
                @min(self.window_size.get(.front).x(), self.window_size.get(.top).x()),
                @min(self.window_size.get(.front).y(), self.window_size.get(.side).y()),
                @min(self.window_size.get(.top).y(), self.window_size.get(.side).x()),
            }),
            .side => math.Vec3.fromArray(.{
                @min(self.window_size.get(.side).x(), self.window_size.get(.top).y()),
                @min(self.window_size.get(.side).y(), self.window_size.get(.front).y()),
                @min(self.window_size.get(.front).x(), self.window_size.get(.top).x()),
            }),
            .top => math.Vec3.fromArray(.{
                @min(self.window_size.get(.top).x(), self.window_size.get(.front).x()),
                @min(self.window_size.get(.top).y(), self.window_size.get(.side).x()),
                @min(self.window_size.get(.front).y(), self.window_size.get(.side).y()),
            }),
        };
        const scale_factors = world_box.divideElements(screen_box);
        const max_factor = @max(scale_factors.x(), scale_factors.y(), scale_factors.z());
        const viewport_size = self.window_size.get(direction).extend(screen_box.z()).scale(max_factor);
        return math.Mat4.fromOrthographic(
            -0.5 * viewport_size.x(),
            0.5 * viewport_size.x(),
            -0.5 * viewport_size.y(),
            0.5 * viewport_size.y(),
            -0.5 * viewport_size.z(),
            0.5 * viewport_size.z(),
        );
    }

    fn calculateWindowMatrix() math.Mat4 {
        var window_pos: math.Vec2 = undefined;
        imgui.igGetCursorScreenPos(window_pos.asImVec());
        var window_size: math.Vec2 = undefined;
        imgui.igGetContentRegionAvail(window_size.asImVec());
        return math.Mat4.identity
            .scale(math.Vec3.fromArray(.{ 0.5 * window_size.x(), -0.5 * window_size.y(), 1 }))
            .translate(window_size.scale(0.5).add(window_pos).extend(0));
    }

    fn drawCollisionSpheres(self: *const Self, matrix: math.Mat4, inverse_matrix: math.Mat4) void {
        const frame = if (self.current_frame) |*f| f else return;

        const world_right = math.Vec3.plus_x.directionTransform(inverse_matrix).normalize();
        const world_up = math.Vec3.plus_y.directionTransform(inverse_matrix).normalize();

        const color = imgui.igGetColorU32_Vec4(collision_spheres_color);
        const thickness = collision_spheres_thickness;

        const draw_list = imgui.igGetWindowDrawList();
        for (frame) |player| {
            for (player.collision_spheres.asConstArray()) |*sphere| {
                const pos = sphere.position.pointTransform(matrix).swizzle("xy");
                const radius = world_up.add(world_right).scale(sphere.radius).directionTransform(matrix).swizzle("xy");
                imgui.ImDrawList_AddEllipse(draw_list, pos.toImVec(), radius.toImVec(), color, 0, 32, thickness);
            }
        }
    }

    fn drawHurtCylinders(self: *const Self, direction: Direction, matrix: math.Mat4, inverse_matrix: math.Mat4) void {
        const frame = if (self.current_frame) |*f| f else return;

        const world_right = math.Vec3.plus_x.directionTransform(inverse_matrix).normalize();
        const world_up = math.Vec3.plus_y.directionTransform(inverse_matrix).normalize();

        const color = imgui.igGetColorU32_Vec4(hurt_cylinders_color);
        const thickness = hurt_cylinders_thickness;

        const draw_list = imgui.igGetWindowDrawList();
        for (frame) |player| {
            for (player.hurt_cylinders.asConstArray()) |*cylinder| {
                const pos = cylinder.position.pointTransform(matrix).swizzle("xy");
                switch (direction) {
                    .front, .side => {
                        const half_size = world_up.scale(cylinder.half_height)
                            .add(world_right.scale(cylinder.radius))
                            .directionTransform(matrix)
                            .swizzle("xy");
                        const min = pos.subtract(half_size);
                        const max = pos.add(half_size);
                        imgui.ImDrawList_AddRect(draw_list, min.toImVec(), max.toImVec(), color, 0, 0, thickness);
                    },
                    .top => {
                        const radius = world_up
                            .add(world_right)
                            .scale(cylinder.radius)
                            .directionTransform(matrix).swizzle("xy");
                        imgui.ImDrawList_AddEllipse(draw_list, pos.toImVec(), radius.toImVec(), color, 0, 32, thickness);
                    },
                }
            }
        }
    }

    fn drawStickFigures(self: *const Self, matrix: math.Mat4) void {
        const frame = if (self.current_frame) |*f| f else return;
        for (frame) |player| {
            const transform = struct {
                fn call(body_part: anytype, m: math.Mat4) imgui.ImVec2 {
                    return body_part.position.pointTransform(m).swizzle("xy").toImVec();
                }
            }.call;
            const cylinders = &player.hurt_cylinders;
            const spheres = &player.collision_spheres;

            const head = transform(cylinders.head, matrix);
            const neck = transform(spheres.neck, matrix);
            const upper_torso = transform(cylinders.upper_torso, matrix);
            const left_shoulder = transform(cylinders.left_shoulder, matrix);
            const right_shoulder = transform(cylinders.right_shoulder, matrix);
            const left_elbow = transform(cylinders.left_elbow, matrix);
            const right_elbow = transform(cylinders.right_elbow, matrix);
            const left_hand = transform(cylinders.left_hand, matrix);
            const right_hand = transform(cylinders.right_hand, matrix);
            const lower_torso = transform(spheres.lower_torso, matrix);
            const left_pelvis = transform(cylinders.left_pelvis, matrix);
            const right_pelvis = transform(cylinders.right_pelvis, matrix);
            const left_knee = transform(cylinders.left_knee, matrix);
            const right_knee = transform(cylinders.right_knee, matrix);
            const left_ankle = transform(cylinders.left_ankle, matrix);
            const right_ankle = transform(cylinders.right_ankle, matrix);

            const color = imgui.igGetColorU32_Vec4(stick_figure_color);
            const thickness = stick_figure_thickness;

            const draw_list = imgui.igGetWindowDrawList();
            imgui.ImDrawList_AddLine(draw_list, head, neck, color, thickness);
            imgui.ImDrawList_AddLine(draw_list, neck, upper_torso, color, thickness);
            imgui.ImDrawList_AddLine(draw_list, upper_torso, left_shoulder, color, thickness);
            imgui.ImDrawList_AddLine(draw_list, upper_torso, right_shoulder, color, thickness);
            imgui.ImDrawList_AddLine(draw_list, left_shoulder, left_elbow, color, thickness);
            imgui.ImDrawList_AddLine(draw_list, right_shoulder, right_elbow, color, thickness);
            imgui.ImDrawList_AddLine(draw_list, left_elbow, left_hand, color, thickness);
            imgui.ImDrawList_AddLine(draw_list, right_elbow, right_hand, color, thickness);
            imgui.ImDrawList_AddLine(draw_list, upper_torso, lower_torso, color, thickness);
            imgui.ImDrawList_AddLine(draw_list, lower_torso, left_pelvis, color, thickness);
            imgui.ImDrawList_AddLine(draw_list, lower_torso, right_pelvis, color, thickness);
            imgui.ImDrawList_AddLine(draw_list, left_pelvis, left_knee, color, thickness);
            imgui.ImDrawList_AddLine(draw_list, right_pelvis, right_knee, color, thickness);
            imgui.ImDrawList_AddLine(draw_list, left_knee, left_ankle, color, thickness);
            imgui.ImDrawList_AddLine(draw_list, right_knee, right_ankle, color, thickness);
        }
    }

    fn drawHitLines(self: *const Self, matrix: math.Mat4) void {
        const previous_frame = if (self.previous_frame) |*f| f else return;
        const current_frame = if (self.current_frame) |*f| f else return;

        const color = imgui.igGetColorU32_Vec4(hit_line_color);
        const thickness = hit_line_thickness;

        const draw_list = imgui.igGetWindowDrawList();
        for (previous_frame, current_frame) |previous_player, current_player| {
            var last_point: ?math.Vec2 = null;
            for (&previous_player.hit_lines, &current_player.hit_lines) |*previous_set, *current_set| {
                for (&previous_set.points, &current_set.points) |previous_point, current_point| {
                    if (std.meta.eql(previous_point.position, current_point.position)) {
                        continue;
                    }
                    const current = current_point.position.pointTransform(matrix).swizzle("xy");
                    if (last_point) |last| {
                        imgui.ImDrawList_AddLine(draw_list, last.toImVec(), current.toImVec(), color, thickness);
                    }
                    last_point = current;
                }
            }
        }
    }
};
