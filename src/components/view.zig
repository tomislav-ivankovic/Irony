const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../sdk/root.zig");
const core = @import("../core/root.zig");

pub const View = struct {
    window_size: std.EnumArray(Direction, sdk.math.Vec2) = .initFill(sdk.math.Vec2.zero),
    frame: core.Frame = .{},
    hit_hurt_cylinder_life_time: std.EnumArray(core.PlayerId, std.EnumArray(core.HurtCylinderId, f32)) = .initFill(
        .initFill(std.math.inf(f32)),
    ),
    lingering_hurt_cylinders: sdk.misc.CircularBuffer(32, LingeringCylinder) = .{},
    lingering_hit_lines: sdk.misc.CircularBuffer(128, LingeringLine) = .{},

    const Self = @This();
    pub const Direction = enum {
        front,
        side,
        top,
    };
    const LingeringLine = struct {
        line: sdk.math.LineSegment3,
        player_id: core.PlayerId,
        life_time: f32,
    };
    const LingeringCylinder = struct {
        cylinder: sdk.math.Cylinder,
        player_id: core.PlayerId,
        life_time: f32,
    };

    const floor_color = sdk.math.Vec4.fromArray(.{ 0.0, 1.0, 0.0, 1.0 });
    const floor_thickness = 1.0;
    const collision_spheres_color = sdk.math.Vec4.fromArray(.{ 0.0, 0.0, 1.0, 0.5 });
    const collision_spheres_thickness = 1.0;
    const hurt_cylinders_color = sdk.math.Vec4.fromArray(.{ 0.5, 0.5, 0.5, 0.5 });
    const hurt_cylinders_thickness = 1.0;
    const skeleton_color = sdk.math.Vec4.fromArray(.{ 1.0, 1.0, 1.0, 1.0 });
    const skeleton_thickness = 2.0;
    const hit_line_color = sdk.math.Vec4.fromArray(.{ 1.0, 0.0, 0.0, 1.0 });
    const hit_line_thickness = 1.0;
    const hit_line_duration = 3.0;
    const hit_hurt_cylinders_color = sdk.math.Vec4.fromArray(.{ 1.0, 1.0, 0.0, 0.5 });
    const hit_hurt_cylinders_thickness = 1.0;
    const hit_hurt_cylinders_duration = 1.0;
    const lingering_hurt_cylinders_color = sdk.math.Vec4.fromArray(.{ 0.0, 0.75, 0.75, 0.5 });
    const lingering_hurt_cylinders_thickness = 1.0;
    const lingering_hurt_cylinders_duration = 1.0;
    const look_at_color = sdk.math.Vec4.fromArray(.{ 1.0, 0.0, 1.0, 1.0 });
    const look_at_length = 100.0;
    const look_at_thickness = 1.0;

    pub fn processFrame(self: *Self, frame: *const core.Frame) void {
        self.processHurtCylinders(.player_1, frame);
        self.processHurtCylinders(.player_2, frame);
        self.processHitLines(.player_1, frame);
        self.processHitLines(.player_2, frame);
        self.frame = frame.*;
    }

    fn processHurtCylinders(self: *Self, player_id: core.PlayerId, frame: *const core.Frame) void {
        const player = frame.getPlayerById(player_id);
        const cylinders: *const core.HurtCylinders = if (player.hurt_cylinders) |*c| c else return;
        for (&cylinders.values, 0..) |*hurt_cylinder, index| {
            if (!hurt_cylinder.intersects) {
                continue;
            }
            const cylinder_id = core.HurtCylinders.Indexer.keyForIndex(index);
            self.hit_hurt_cylinder_life_time.getPtr(player_id).getPtr(cylinder_id).* = 0;
            _ = self.lingering_hurt_cylinders.addToBack(.{
                .cylinder = hurt_cylinder.cylinder,
                .player_id = player_id,
                .life_time = 0,
            });
        }
    }

    fn processHitLines(self: *Self, player_id: core.PlayerId, frame: *const core.Frame) void {
        const player = frame.getPlayerById(player_id);
        for (player.hit_lines.asConstSlice()) |*hit_line| {
            _ = self.lingering_hit_lines.addToBack(.{
                .line = hit_line.line,
                .player_id = player_id,
                .life_time = 0,
            });
        }
    }

    pub fn update(self: *Self, delta_time: f32) void {
        self.updateHitHurtCylinders(delta_time);
        self.updateLingeringHurtCylinders(delta_time);
        self.updateLingeringHitLines(delta_time);
    }

    fn updateHitHurtCylinders(self: *Self, delta_time: f32) void {
        for (&self.hit_hurt_cylinder_life_time.values) |*player_cylinders| {
            for (&player_cylinders.values) |*life_time| {
                life_time.* += delta_time;
            }
        }
    }

    fn updateLingeringHurtCylinders(self: *Self, delta_time: f32) void {
        for (0..self.lingering_hurt_cylinders.len) |index| {
            const line = self.lingering_hurt_cylinders.getMut(index) catch unreachable;
            line.life_time += delta_time;
        }
        while (self.lingering_hurt_cylinders.getFirst() catch null) |line| {
            if (line.life_time <= hit_line_duration) {
                break;
            }
            _ = self.lingering_hurt_cylinders.removeFirst() catch unreachable;
        }
    }

    fn updateLingeringHitLines(self: *Self, delta_time: f32) void {
        for (0..self.lingering_hit_lines.len) |index| {
            const cylinder = self.lingering_hit_lines.getMut(index) catch unreachable;
            cylinder.life_time += delta_time;
        }
        while (self.lingering_hit_lines.getFirst() catch null) |cylinder| {
            if (cylinder.life_time <= hit_line_duration) {
                break;
            }
            _ = self.lingering_hit_lines.removeFirst() catch unreachable;
        }
    }

    pub fn draw(self: *Self, direction: Direction) void {
        self.updateWindowSize(direction);
        const matrix = self.calculateFinalMatrix(direction) orelse return;
        const inverse_matrix = matrix.inverse() orelse sdk.math.Mat4.identity;
        self.drawCollisionSpheres(matrix, inverse_matrix);
        self.drawLingeringHurtCylinders(direction, matrix, inverse_matrix);
        self.drawHurtCylinders(direction, matrix, inverse_matrix);
        self.drawFloor(direction, matrix);
        self.drawLookAtLines(direction, matrix);
        self.drawSkeletons(matrix);
        self.drawLingeringHitLines(matrix);
        self.drawHitLines(matrix);
    }

    fn updateWindowSize(self: *Self, direction: Direction) void {
        var window_size: sdk.math.Vec2 = undefined;
        imgui.igGetContentRegionAvail(window_size.asImVec());
        self.window_size.set(direction, window_size);
    }

    fn calculateFinalMatrix(self: *const Self, direction: Direction) ?sdk.math.Mat4 {
        const look_at_matrix = self.calculateLookAtMatrix(direction) orelse return null;
        const orthographic_matrix = self.calculateOrthographicMatrix(direction, look_at_matrix) orelse return null;
        const window_matrix = calculateWindowMatrix();
        return look_at_matrix.multiply(orthographic_matrix).multiply(window_matrix);
    }

    fn calculateLookAtMatrix(self: *const Self, direction: Direction) ?sdk.math.Mat4 {
        const left_player = self.frame.getPlayerBySide(.left).position orelse return null;
        const right_player = self.frame.getPlayerBySide(.right).position orelse return null;
        const eye = left_player.add(right_player).scale(0.5);
        const difference_2d = right_player.swizzle("xy").subtract(left_player.swizzle("xy"));
        const player_dir = if (!difference_2d.isZero(0)) difference_2d.normalize().extend(0) else sdk.math.Vec3.plus_x;
        const look_direction = switch (direction) {
            .front => player_dir.cross(sdk.math.Vec3.minus_z),
            .side => player_dir.negate(),
            .top => sdk.math.Vec3.plus_z,
        };
        const target = eye.add(look_direction);
        const up = switch (direction) {
            .front, .side => sdk.math.Vec3.plus_z,
            .top => player_dir.cross(sdk.math.Vec3.plus_z),
        };
        return sdk.math.Mat4.fromLookAt(eye, target, up);
    }

    fn calculateOrthographicMatrix(
        self: *const Self,
        direction: Direction,
        look_at_matrix: sdk.math.Mat4,
    ) ?sdk.math.Mat4 {
        var min = sdk.math.Vec3.fill(std.math.inf(f32));
        var max = sdk.math.Vec3.fill(-std.math.inf(f32));
        for (&self.frame.players) |*player| {
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
        const world_box = sdk.math.Vec3.maxElements(min.negate(), max).add(padding).scale(2);
        const screen_box = switch (direction) {
            .front => sdk.math.Vec3.fromArray(.{
                @min(self.window_size.get(.front).x(), self.window_size.get(.top).x()),
                @min(self.window_size.get(.front).y(), self.window_size.get(.side).y()),
                @min(self.window_size.get(.top).y(), self.window_size.get(.side).x()),
            }),
            .side => sdk.math.Vec3.fromArray(.{
                @min(self.window_size.get(.side).x(), self.window_size.get(.top).y()),
                @min(self.window_size.get(.side).y(), self.window_size.get(.front).y()),
                @min(self.window_size.get(.front).x(), self.window_size.get(.top).x()),
            }),
            .top => sdk.math.Vec3.fromArray(.{
                @min(self.window_size.get(.top).x(), self.window_size.get(.front).x()),
                @min(self.window_size.get(.top).y(), self.window_size.get(.side).x()),
                @min(self.window_size.get(.front).y(), self.window_size.get(.side).y()),
            }),
        };
        const scale_factors = world_box.divideElements(screen_box);
        const max_factor = @max(scale_factors.x(), scale_factors.y(), scale_factors.z());
        const viewport_size = self.window_size.get(direction).extend(screen_box.z()).scale(max_factor);
        return sdk.math.Mat4.fromOrthographic(
            -0.5 * viewport_size.x(),
            0.5 * viewport_size.x(),
            -0.5 * viewport_size.y(),
            0.5 * viewport_size.y(),
            -0.5 * viewport_size.z(),
            0.5 * viewport_size.z(),
        );
    }

    fn calculateWindowMatrix() sdk.math.Mat4 {
        var window_pos: sdk.math.Vec2 = undefined;
        imgui.igGetCursorScreenPos(window_pos.asImVec());
        var window_size: sdk.math.Vec2 = undefined;
        imgui.igGetContentRegionAvail(window_size.asImVec());
        return sdk.math.Mat4.identity
            .scale(sdk.math.Vec3.fromArray(.{ 0.5 * window_size.x(), -0.5 * window_size.y(), 1 }))
            .translate(window_size.scale(0.5).add(window_pos).extend(0));
    }

    fn drawCollisionSpheres(self: *const Self, matrix: sdk.math.Mat4, inverse_matrix: sdk.math.Mat4) void {
        for (&self.frame.players) |*player| {
            const spheres: *const core.CollisionSpheres = if (player.collision_spheres) |*s| s else continue;
            for (spheres.values) |sphere| {
                drawSphere(sphere, collision_spheres_color, collision_spheres_thickness, matrix, inverse_matrix);
            }
        }
    }

    fn drawHurtCylinders(
        self: *const Self,
        direction: Direction,
        matrix: sdk.math.Mat4,
        inverse_matrix: sdk.math.Mat4,
    ) void {
        for (core.PlayerId.all) |player_id| {
            const player = self.frame.getPlayerById(player_id);
            const cylinders: *const core.HurtCylinders = if (player.hurt_cylinders) |*c| c else continue;
            for (cylinders.values, 0..) |hurt_cylinder, index| {
                const cylinder = hurt_cylinder.cylinder;
                const cylinder_id = core.HurtCylinders.Indexer.keyForIndex(index);

                const life_time = self.hit_hurt_cylinder_life_time.getPtrConst(player_id).get(cylinder_id);
                const completion: f32 = if (hurt_cylinder.intersects) 0.0 else block: {
                    break :block std.math.clamp(life_time / hit_hurt_cylinders_duration, 0.0, 1.0);
                };
                const t = completion * completion * completion * completion;
                const color = sdk.math.Vec4.lerpElements(hit_hurt_cylinders_color, hurt_cylinders_color, t);
                const thickness = std.math.lerp(hit_hurt_cylinders_thickness, hurt_cylinders_thickness, t);

                drawCylinder(cylinder, color, thickness, direction, matrix, inverse_matrix);
            }
        }
    }

    fn drawLingeringHurtCylinders(
        self: *const Self,
        direction: Direction,
        matrix: sdk.math.Mat4,
        inverse_matrix: sdk.math.Mat4,
    ) void {
        for (0..self.lingering_hurt_cylinders.len) |index| {
            const hurt_cylinder = self.lingering_hurt_cylinders.get(index) catch unreachable;
            const cylinder = hurt_cylinder.cylinder;

            const completion = hurt_cylinder.life_time / lingering_hurt_cylinders_duration;
            var color = lingering_hurt_cylinders_color;
            color.asColor().a *= 1.0 - (completion * completion * completion * completion);

            drawCylinder(cylinder, color, lingering_hurt_cylinders_thickness, direction, matrix, inverse_matrix);
        }
    }

    fn drawSkeletons(self: *const Self, matrix: sdk.math.Mat4) void {
        const drawBone = struct {
            fn call(
                mat: sdk.math.Mat4,
                skeleton: *const core.Skeleton,
                point_1: core.SkeletonPointId,
                point_2: core.SkeletonPointId,
            ) void {
                const line = sdk.math.LineSegment3{ .point_1 = skeleton.get(point_1), .point_2 = skeleton.get(point_2) };
                drawLine(line, skeleton_color, skeleton_thickness, mat);
            }
        }.call;
        for (&self.frame.players) |*player| {
            const skeleton: *const core.Skeleton = if (player.skeleton) |*s| s else continue;
            drawBone(matrix, skeleton, .head, .neck);
            drawBone(matrix, skeleton, .neck, .upper_torso);
            drawBone(matrix, skeleton, .upper_torso, .left_shoulder);
            drawBone(matrix, skeleton, .upper_torso, .right_shoulder);
            drawBone(matrix, skeleton, .left_shoulder, .left_elbow);
            drawBone(matrix, skeleton, .right_shoulder, .right_elbow);
            drawBone(matrix, skeleton, .left_elbow, .left_hand);
            drawBone(matrix, skeleton, .right_elbow, .right_hand);
            drawBone(matrix, skeleton, .upper_torso, .lower_torso);
            drawBone(matrix, skeleton, .lower_torso, .left_pelvis);
            drawBone(matrix, skeleton, .lower_torso, .right_pelvis);
            drawBone(matrix, skeleton, .left_pelvis, .left_knee);
            drawBone(matrix, skeleton, .right_pelvis, .right_knee);
            drawBone(matrix, skeleton, .left_knee, .left_ankle);
            drawBone(matrix, skeleton, .right_knee, .right_ankle);
        }
    }

    fn drawHitLines(self: *const Self, matrix: sdk.math.Mat4) void {
        for (&self.frame.players) |*player| {
            for (player.hit_lines.asConstSlice()) |hit_line| {
                const line = hit_line.line;
                drawLine(line, hit_line_color, hit_line_thickness, matrix);
            }
        }
    }

    fn drawLingeringHitLines(self: *const Self, matrix: sdk.math.Mat4) void {
        for (0..self.lingering_hit_lines.len) |index| {
            const hit_line = self.lingering_hit_lines.get(index) catch unreachable;
            const line = hit_line.line;

            const completion = hit_line.life_time / hit_line_duration;
            var color = hit_line_color;
            color.asColor().a *= 1.0 - (completion * completion * completion * completion);

            drawLine(line, color, hit_line_thickness, matrix);
        }
    }

    fn drawLookAtLines(self: *const Self, direction: Direction, matrix: sdk.math.Mat4) void {
        if (direction != .top) {
            return;
        }
        for (&self.frame.players) |*player| {
            const position = player.position orelse continue;
            const rotation = player.rotation orelse continue;
            const delta = sdk.math.Vec3.plus_x.scale(look_at_length).rotateZ(rotation);
            const line = sdk.math.LineSegment3{
                .point_1 = position,
                .point_2 = position.add(delta),
            };
            drawLine(line, look_at_color, look_at_thickness, matrix);
        }
    }

    fn drawFloor(self: *const Self, direction: Direction, matrix: sdk.math.Mat4) void {
        if (direction == .top) {
            return;
        }

        var window_pos: sdk.math.Vec2 = undefined;
        imgui.igGetCursorScreenPos(window_pos.asImVec());
        var window_size: sdk.math.Vec2 = undefined;
        imgui.igGetContentRegionAvail(window_size.asImVec());
        const world_z = self.frame.floor_z orelse return;

        const screen_x = window_pos.toCoords().x;
        const screen_w = window_size.toCoords().x;
        const screen_y = sdk.math.Vec3.plus_z.scale(world_z).pointTransform(matrix).toCoords().y;

        const draw_list = imgui.igGetWindowDrawList();
        const point_1 = sdk.math.Vec2.fromArray(.{ screen_x, screen_y }).toImVec();
        const point_2 = sdk.math.Vec2.fromArray(.{ screen_x + screen_w, screen_y }).toImVec();
        const u32_color = imgui.igGetColorU32_Vec4(floor_color.toImVec());

        imgui.ImDrawList_AddLine(draw_list, point_1, point_2, u32_color, floor_thickness);
    }

    fn drawSphere(
        sphere: sdk.math.Sphere,
        color: sdk.math.Vec4,
        thickness: f32,
        matrix: sdk.math.Mat4,
        inverse_matrix: sdk.math.Mat4,
    ) void {
        const world_right = sdk.math.Vec3.plus_x.directionTransform(inverse_matrix).normalize();
        const world_up = sdk.math.Vec3.plus_y.directionTransform(inverse_matrix).normalize();

        const draw_list = imgui.igGetWindowDrawList();
        const center = sphere.center.pointTransform(matrix).swizzle("xy").toImVec();
        const radius = world_up.add(world_right).scale(sphere.radius).directionTransform(matrix).swizzle("xy").toImVec();
        const u32_color = imgui.igGetColorU32_Vec4(color.toImVec());

        imgui.ImDrawList_AddEllipse(draw_list, center, radius, u32_color, 0, 32, thickness);
    }

    fn drawCylinder(
        cylinder: sdk.math.Cylinder,
        color: sdk.math.Vec4,
        thickness: f32,
        direction: Direction,
        matrix: sdk.math.Mat4,
        inverse_matrix: sdk.math.Mat4,
    ) void {
        const world_right = sdk.math.Vec3.plus_x.directionTransform(inverse_matrix).normalize();
        const world_up = sdk.math.Vec3.plus_y.directionTransform(inverse_matrix).normalize();

        const draw_list = imgui.igGetWindowDrawList();
        const center = cylinder.center.pointTransform(matrix).swizzle("xy");
        const u32_color = imgui.igGetColorU32_Vec4(color.toImVec());

        switch (direction) {
            .front, .side => {
                const half_size = world_up.scale(cylinder.half_height)
                    .add(world_right.scale(cylinder.radius))
                    .directionTransform(matrix)
                    .swizzle("xy");
                const min = center.subtract(half_size).toImVec();
                const max = center.add(half_size).toImVec();
                imgui.ImDrawList_AddRect(draw_list, min, max, u32_color, 0, 0, thickness);
            },
            .top => {
                const im_center = center.toImVec();
                const radius = world_up
                    .add(world_right)
                    .scale(cylinder.radius)
                    .directionTransform(matrix)
                    .swizzle("xy")
                    .toImVec();
                imgui.ImDrawList_AddEllipse(draw_list, im_center, radius, u32_color, 0, 32, thickness);
            },
        }
    }

    fn drawLine(
        line: sdk.math.LineSegment3,
        color: sdk.math.Vec4,
        thickness: f32,
        matrix: sdk.math.Mat4,
    ) void {
        const draw_list = imgui.igGetWindowDrawList();
        const point_1 = line.point_1.pointTransform(matrix).swizzle("xy").toImVec();
        const point_2 = line.point_2.pointTransform(matrix).swizzle("xy").toImVec();
        const u32_color = imgui.igGetColorU32_Vec4(color.toImVec());

        imgui.ImDrawList_AddLine(draw_list, point_1, point_2, u32_color, thickness);
    }
};
