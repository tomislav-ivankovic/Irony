const std = @import("std");
const imgui = @import("imgui");
const math = @import("../math/root.zig");
const game = @import("../game/root.zig");

pub const View = struct {
    window_size: std.EnumArray(Direction, math.Vec2) = .initFill(math.Vec2.zero),

    const Self = @This();
    pub const Direction = enum {
        front,
        side,
        top,
    };
    pub const Player = struct {
        hit_lines_start: game.HitLinePoints,
        hit_lines_end: game.HitLinePoints,
        hurt_cylinders: game.HurtCylinders,
        collision_spheres: game.CollisionSpheres,
    };

    const collision_spheres_color = imgui.ImVec4{ .x = 0.0, .y = 0.0, .z = 1.0, .w = 0.5 };
    const collision_spheres_thickness = 1.0;
    const hurt_cylinders_color = imgui.ImVec4{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 0.5 };
    const hurt_cylinders_thickness = 1.0;
    const stick_figure_color = imgui.ImVec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 };
    const stick_figure_thickness = 2.0;

    pub fn draw(self: *Self, direction: Direction, player_1: *const Player, player_2: *const Player) void {
        self.updateWindowSize(direction);
        const matrix = self.calculateFinalMatrix(direction, player_1, player_2);
        const inverse_matrix = matrix.inverse() orelse math.Mat4.identity;
        drawCollisionSpheres(player_1, matrix, inverse_matrix);
        drawCollisionSpheres(player_2, matrix, inverse_matrix);
        drawHurtCylinders(direction, player_1, matrix, inverse_matrix);
        drawHurtCylinders(direction, player_2, matrix, inverse_matrix);
        drawStickFigure(player_1, matrix);
        drawStickFigure(player_2, matrix);
    }

    fn updateWindowSize(self: *Self, direction: Direction) void {
        var window_size: math.Vec2 = undefined;
        imgui.igGetContentRegionAvail(window_size.asImVecPointer());
        self.window_size.set(direction, window_size);
    }

    fn calculateFinalMatrix(self: *const Self, direction: Direction, player_1: *const Player, player_2: *const Player) math.Mat4 {
        const look_at_matrix = calculateLookAtMatrix(direction, player_1, player_2);
        const orthographic_matrix = self.calculateOrthographicMatrix(direction, player_1, player_2);
        const window_matrix = calculateWindowMatrix();
        return look_at_matrix.multiply(orthographic_matrix).multiply(window_matrix);
    }

    fn calculateLookAtMatrix(direction: Direction, player_1: *const Player, player_2: *const Player) math.Mat4 {
        const p1 = math.Vec3.fromArray(player_1.collision_spheres.get(.lower_torso).getValue().position);
        const p2 = math.Vec3.fromArray(player_2.collision_spheres.get(.lower_torso).getValue().position);
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

    fn calculateOrthographicMatrix(
        self: *const Self,
        direction: Direction,
        player_1: *const Player,
        player_2: *const Player,
    ) math.Mat4 {
        const p1 = math.Vec3.fromArray(player_1.collision_spheres.get(.lower_torso).getValue().position);
        const p2 = math.Vec3.fromArray(player_2.collision_spheres.get(.lower_torso).getValue().position);
        const distance = p2.swizzle("xy").distanceTo(p1.swizzle("xy"));
        const padded_distance = distance + 300;
        const viewport_size = switch (direction) {
            .front, .top => block: {
                const window_size = self.window_size.get(direction);
                const aspect_ratio = window_size.x() / window_size.y();
                break :block math.Vec2.fromArray(.{ padded_distance, padded_distance / aspect_ratio });
            },
            .side => block: {
                const front_window_size = self.window_size.get(.front);
                const front_aspect_ratio = front_window_size.x() / front_window_size.y();
                const side_window_size = self.window_size.get(.side);
                const side_aspect_ratio = side_window_size.x() / side_window_size.y();
                break :block math.Vec2.fromArray(.{
                    padded_distance * side_aspect_ratio / front_aspect_ratio,
                    padded_distance / front_aspect_ratio,
                });
            },
        };
        return math.Mat4.fromOrthographic(
            -0.5 * viewport_size.x(),
            0.5 * viewport_size.x(),
            -0.5 * viewport_size.y(),
            0.5 * viewport_size.y(),
            0,
            1,
        );
    }

    fn calculateWindowMatrix() math.Mat4 {
        var window_pos: math.Vec2 = undefined;
        imgui.igGetCursorScreenPos(window_pos.asImVecPointer());
        var window_size: math.Vec2 = undefined;
        imgui.igGetContentRegionAvail(window_size.asImVecPointer());
        return math.Mat4.identity
            .scale(math.Vec3.fromArray(.{ 0.5 * window_size.x(), -0.5 * window_size.y(), 1 }))
            .translate(window_size.scale(0.5).add(window_pos).extend(0));
    }

    fn drawCollisionSpheres(player: *const Player, matrix: math.Mat4, inverse_matrix: math.Mat4) void {
        const world_right = math.Vec3.plus_x.directionTransform(inverse_matrix).normalize();
        const world_up = math.Vec3.plus_y.directionTransform(inverse_matrix).normalize();

        const color = imgui.igGetColorU32_Vec4(collision_spheres_color);
        const thickness = collision_spheres_thickness;

        const draw_list = imgui.igGetWindowDrawList();
        for (player.collision_spheres.values) |s| {
            const sphere = s.getValue();
            const pos = math.Vec3.fromArray(sphere.position).pointTransform(matrix).swizzle("xy");
            const radius = world_up.add(world_right).scale(sphere.radius).directionTransform(matrix).swizzle("xy");
            imgui.ImDrawList_AddEllipse(draw_list, pos.toImVec(), radius.toImVec(), color, 0, 32, thickness);
        }
    }

    fn drawHurtCylinders(direction: Direction, player: *const Player, matrix: math.Mat4, inverse_matrix: math.Mat4) void {
        const world_right = math.Vec3.plus_x.directionTransform(inverse_matrix).normalize();
        const world_up = math.Vec3.plus_y.directionTransform(inverse_matrix).normalize();

        const color = imgui.igGetColorU32_Vec4(hurt_cylinders_color);
        const thickness = hurt_cylinders_thickness;

        const draw_list = imgui.igGetWindowDrawList();
        for (player.hurt_cylinders.values) |c| {
            const cylinder = c.getValue();
            const pos = math.Vec3.fromArray(cylinder.position).pointTransform(matrix).swizzle("xy");
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

    fn drawStickFigure(player: *const Player, matrix: math.Mat4) void {
        const transform = struct {
            fn call(body_part: anytype, m: math.Mat4) imgui.ImVec2 {
                return math.Vec3.fromArray(body_part.getValue().position).pointTransform(m).swizzle("xy").toImVec();
            }
        }.call;
        const cylinders = &player.hurt_cylinders;
        const spheres = &player.collision_spheres;

        const head = transform(cylinders.get(.head), matrix);
        const neck = transform(spheres.get(.neck), matrix);
        const upper_torso = transform(cylinders.get(.upper_torso), matrix);
        const left_shoulder = transform(cylinders.get(.left_shoulder), matrix);
        const right_shoulder = transform(cylinders.get(.right_shoulder), matrix);
        const left_elbow = transform(cylinders.get(.left_elbow), matrix);
        const right_elbow = transform(cylinders.get(.right_elbow), matrix);
        const left_hand = transform(cylinders.get(.left_hand), matrix);
        const right_hand = transform(cylinders.get(.right_hand), matrix);
        const lower_torso = transform(spheres.get(.lower_torso), matrix);
        const left_pelvis = transform(cylinders.get(.left_pelvis), matrix);
        const right_pelvis = transform(cylinders.get(.right_pelvis), matrix);
        const left_knee = transform(cylinders.get(.left_knee), matrix);
        const right_knee = transform(cylinders.get(.right_knee), matrix);
        const left_ankle = transform(cylinders.get(.left_ankle), matrix);
        const right_ankle = transform(cylinders.get(.right_ankle), matrix);

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
};
