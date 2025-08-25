const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

pub const View = struct {
    window_size: std.EnumArray(Direction, sdk.math.Vec2) = .initFill(sdk.math.Vec2.zero),
    frame: model.Frame = .{},
    hit_hurt_cylinder_life_time: std.EnumArray(model.PlayerId, std.EnumArray(model.HurtCylinderId, f32)) = .initFill(
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
        player_id: model.PlayerId,
        life_time: f32,
        attack_type: ?model.AttackType,
    };
    const LingeringCylinder = struct {
        cylinder: sdk.math.Cylinder,
        player_id: model.PlayerId,
        life_time: f32,
    };

    const config = .{
        .floor = .{
            .color = sdk.math.Vec4.fromArray(.{ 0.0, 1.0, 0.0, 1.0 }),
            .thickness = 1.0,
        },
        .collision_spheres = .{
            .color = sdk.math.Vec4.fromArray(.{ 0.0, 0.0, 1.0, 0.5 }),
            .thickness = 1.0,
        },
        .skeleton = .{
            .colors = std.EnumArray(model.Blocking, sdk.math.Vec4).init(.{
                .not_blocking = .fromArray(.{ 1.0, 1.0, 1.0, 1.0 }),
                .neutral_blocking_mids = .fromArray(.{ 1.0, 1.0, 0.75, 1.0 }),
                .fully_blocking_mids = .fromArray(.{ 1.0, 1.0, 0.5, 1.0 }),
                .neutral_blocking_lows = .fromArray(.{ 0.75, 0.875, 1.0, 1.0 }),
                .fully_blocking_lows = .fromArray(.{ 0.5, 0.75, 1.0, 1.0 }),
            }),
            .thickness = 2.0,
            .cant_move_alpha = 0.5,
        },
        .hit_lines = .{
            .fill = .{
                .colors = std.EnumArray(model.AttackType, sdk.math.Vec4).init(.{
                    .not_attack = .fromArray(.{ 0.5, 0.5, 0.5, 1.0 }),
                    .high = .fromArray(.{ 1.0, 0.0, 0.0, 1.0 }),
                    .mid = .fromArray(.{ 1.0, 1.0, 0.0, 1.0 }),
                    .low = .fromArray(.{ 0.0, 0.5, 1.0, 1.0 }),
                    .special_low = .fromArray(.{ 0.0, 1.0, 1.0, 1.0 }),
                    .high_unblockable = .fromArray(.{ 1.0, 0.0, 0.0, 1.0 }),
                    .mid_unblockable = .fromArray(.{ 1.0, 1.0, 0.0, 1.0 }),
                    .low_unblockable = .fromArray(.{ 0.0, 0.5, 1.0, 1.0 }),
                    .throw = .fromArray(.{ 1.0, 1.0, 1.0, 1.0 }),
                    .projectile = .fromArray(.{ 0.5, 1.0, 0.5, 1.0 }),
                    .antiair_only = .fromArray(.{ 1.0, 0.5, 0.0, 1.0 }),
                }),
                .thickness = 1.0,
            },
            .outline = .{
                .colors = std.EnumArray(model.AttackType, sdk.math.Vec4).init(.{
                    .not_attack = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                    .high = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                    .mid = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                    .low = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                    .special_low = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                    .high_unblockable = .fromArray(.{ 0.75, 0.0, 0.75, 1.0 }),
                    .mid_unblockable = .fromArray(.{ 0.75, 0.0, 0.75, 1.0 }),
                    .low_unblockable = .fromArray(.{ 0.75, 0.0, 0.75, 1.0 }),
                    .throw = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                    .projectile = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                    .antiair_only = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                }),
                .thickness = 1.0,
            },
            .duration = 1.0,
        },
        .hurt_cylinders = .{
            .normal = .{
                .color = sdk.math.Vec4.fromArray(.{ 0.5, 0.5, 0.5, 0.5 }),
                .thickness = 1.0,
            },
            .high_crushing = .{
                .color = sdk.math.Vec4.fromArray(.{ 0.75, 0.0, 0.0, 0.5 }),
                .thickness = 1.0,
            },
            .low_crushing = .{
                .color = sdk.math.Vec4.fromArray(.{ 0.0, 0.375, 0.75, 0.5 }),
                .thickness = 1.0,
            },
            .invincible = .{
                .color = sdk.math.Vec4.fromArray(.{ 0.75, 0.0, 0.75, 0.5 }),
                .thickness = 1.0,
            },
            .power_crushing = .{
                .normal = .{
                    .color = sdk.math.Vec4.fromArray(.{ 1.0, 1.0, 1.0, 1.0 }),
                    .thickness = 1.0,
                },
                .high_crushing = .{
                    .color = sdk.math.Vec4.fromArray(.{ 1.0, 0.25, 0.25, 1.0 }),
                    .thickness = 1.0,
                },
                .low_crushing = .{
                    .color = sdk.math.Vec4.fromArray(.{ 0.0, 0.25, 1.0, 1.0 }),
                    .thickness = 1.0,
                },
                .invincible = .{
                    .color = sdk.math.Vec4.fromArray(.{ 1.0, 0.0, 1.0, 1.0 }),
                    .thickness = 1.0,
                },
            },
            .hit = .{
                .color = sdk.math.Vec4.fromArray(.{ 1.0, 0.75, 0.25, 0.5 }),
                .thickness = 1.0,
                .duration = 1.0,
            },
            .lingering = .{
                .color = sdk.math.Vec4.fromArray(.{ 0.0, 0.75, 0.75, 0.5 }),
                .thickness = 1.0,
                .duration = 1.0,
            },
        },
        .look_direction = .{
            .color = sdk.math.Vec4.fromArray(.{ 1.0, 0.0, 1.0, 1.0 }),
            .length = 100.0,
            .thickness = 1.0,
        },
    };

    pub fn processFrame(self: *Self, frame: *const model.Frame) void {
        self.processHurtCylinders(.player_1, frame);
        self.processHurtCylinders(.player_2, frame);
        self.processHitLines(.player_1, frame);
        self.processHitLines(.player_2, frame);
        self.frame = frame.*;
    }

    fn processHurtCylinders(self: *Self, player_id: model.PlayerId, frame: *const model.Frame) void {
        const player = frame.getPlayerById(player_id);
        const cylinders: *const model.HurtCylinders = if (player.hurt_cylinders) |*c| c else return;
        for (&cylinders.values, 0..) |*hurt_cylinder, index| {
            if (!hurt_cylinder.intersects) {
                continue;
            }
            const cylinder_id = model.HurtCylinders.Indexer.keyForIndex(index);
            self.hit_hurt_cylinder_life_time.getPtr(player_id).getPtr(cylinder_id).* = 0;
            _ = self.lingering_hurt_cylinders.addToBack(.{
                .cylinder = hurt_cylinder.cylinder,
                .player_id = player_id,
                .life_time = 0,
            });
        }
    }

    fn processHitLines(self: *Self, player_id: model.PlayerId, frame: *const model.Frame) void {
        const player = frame.getPlayerById(player_id);
        for (player.hit_lines.asConstSlice()) |*hit_line| {
            _ = self.lingering_hit_lines.addToBack(.{
                .line = hit_line.line,
                .player_id = player_id,
                .life_time = 0,
                .attack_type = player.attack_type,
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
            if (line.life_time <= config.hurt_cylinders.lingering.duration) {
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
            if (cylinder.life_time <= config.hit_lines.duration) {
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
            const spheres: *const model.CollisionSpheres = if (player.collision_spheres) |*s| s else continue;
            for (spheres.values) |sphere| {
                const color = config.collision_spheres.color;
                const thickness = config.collision_spheres.thickness;
                drawSphere(sphere, color, thickness, matrix, inverse_matrix);
            }
        }
    }

    fn drawHurtCylinders(
        self: *const Self,
        direction: Direction,
        matrix: sdk.math.Mat4,
        inverse_matrix: sdk.math.Mat4,
    ) void {
        for (model.PlayerId.all) |player_id| {
            const player = self.frame.getPlayerById(player_id);

            const crushing = player.crushing orelse model.Crushing{};
            const base_color: sdk.math.Vec4, const base_thickness: f32 = if (crushing.power_crushing) block: {
                if (crushing.invincibility) {
                    break :block .{
                        config.hurt_cylinders.power_crushing.invincible.color,
                        config.hurt_cylinders.power_crushing.invincible.thickness,
                    };
                } else if (crushing.high_crushing) {
                    break :block .{
                        config.hurt_cylinders.power_crushing.high_crushing.color,
                        config.hurt_cylinders.power_crushing.high_crushing.thickness,
                    };
                } else if (crushing.low_crushing) {
                    break :block .{
                        config.hurt_cylinders.power_crushing.low_crushing.color,
                        config.hurt_cylinders.power_crushing.low_crushing.thickness,
                    };
                } else {
                    break :block .{
                        config.hurt_cylinders.power_crushing.normal.color,
                        config.hurt_cylinders.power_crushing.normal.thickness,
                    };
                }
            } else block: {
                if (crushing.invincibility) {
                    break :block .{
                        config.hurt_cylinders.invincible.color,
                        config.hurt_cylinders.invincible.thickness,
                    };
                } else if (crushing.high_crushing) {
                    break :block .{
                        config.hurt_cylinders.high_crushing.color,
                        config.hurt_cylinders.high_crushing.thickness,
                    };
                } else if (crushing.low_crushing) {
                    break :block .{
                        config.hurt_cylinders.low_crushing.color,
                        config.hurt_cylinders.low_crushing.thickness,
                    };
                } else {
                    break :block .{
                        config.hurt_cylinders.normal.color,
                        config.hurt_cylinders.normal.thickness,
                    };
                }
            };

            const cylinders: *const model.HurtCylinders = if (player.hurt_cylinders) |*c| c else continue;
            for (cylinders.values, 0..) |hurt_cylinder, index| {
                const cylinder = hurt_cylinder.cylinder;
                const cylinder_id = model.HurtCylinders.Indexer.keyForIndex(index);

                const life_time = self.hit_hurt_cylinder_life_time.getPtrConst(player_id).get(cylinder_id);
                const duration = config.hurt_cylinders.hit.duration;
                const completion: f32 = if (hurt_cylinder.intersects) 0.0 else block: {
                    break :block std.math.clamp(life_time / duration, 0.0, 1.0);
                };
                const t = completion * completion * completion * completion;
                const hit_color = config.hurt_cylinders.hit.color;
                const color = sdk.math.Vec4.lerpElements(hit_color, base_color, t);
                const hit_thickness = config.hurt_cylinders.hit.thickness;
                const thickness = std.math.lerp(hit_thickness, base_thickness, t);

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

            const duration = config.hurt_cylinders.lingering.duration;
            const completion = hurt_cylinder.life_time / duration;
            var color = config.hurt_cylinders.lingering.color;
            color.asColor().a *= 1.0 - (completion * completion * completion * completion);
            const thickness = config.hurt_cylinders.lingering.thickness;

            drawCylinder(cylinder, color, thickness, direction, matrix, inverse_matrix);
        }
    }

    fn drawSkeletons(self: *const Self, matrix: sdk.math.Mat4) void {
        const drawBone = struct {
            fn call(
                mat: sdk.math.Mat4,
                skeleton: *const model.Skeleton,
                blocking: model.Blocking,
                can_move: bool,
                point_1: model.SkeletonPointId,
                point_2: model.SkeletonPointId,
            ) void {
                const line = sdk.math.LineSegment3{
                    .point_1 = skeleton.get(point_1),
                    .point_2 = skeleton.get(point_2),
                };
                var color = config.skeleton.colors.get(blocking);
                if (!can_move) {
                    color.asColor().a *= config.skeleton.cant_move_alpha;
                }
                const thickness = config.skeleton.thickness;
                drawLine(line, color, thickness, mat);
            }
        }.call;
        for (&self.frame.players) |*player| {
            const skeleton: *const model.Skeleton = if (player.skeleton) |*s| s else continue;
            const blocking = if (player.blocking) |b| b else .not_blocking;
            const can_move = if (player.can_move) |c| c else true;
            drawBone(matrix, skeleton, blocking, can_move, .head, .neck);
            drawBone(matrix, skeleton, blocking, can_move, .neck, .upper_torso);
            drawBone(matrix, skeleton, blocking, can_move, .upper_torso, .left_shoulder);
            drawBone(matrix, skeleton, blocking, can_move, .upper_torso, .right_shoulder);
            drawBone(matrix, skeleton, blocking, can_move, .left_shoulder, .left_elbow);
            drawBone(matrix, skeleton, blocking, can_move, .right_shoulder, .right_elbow);
            drawBone(matrix, skeleton, blocking, can_move, .left_elbow, .left_hand);
            drawBone(matrix, skeleton, blocking, can_move, .right_elbow, .right_hand);
            drawBone(matrix, skeleton, blocking, can_move, .upper_torso, .lower_torso);
            drawBone(matrix, skeleton, blocking, can_move, .lower_torso, .left_pelvis);
            drawBone(matrix, skeleton, blocking, can_move, .lower_torso, .right_pelvis);
            drawBone(matrix, skeleton, blocking, can_move, .left_pelvis, .left_knee);
            drawBone(matrix, skeleton, blocking, can_move, .right_pelvis, .right_knee);
            drawBone(matrix, skeleton, blocking, can_move, .left_knee, .left_ankle);
            drawBone(matrix, skeleton, blocking, can_move, .right_knee, .right_ankle);
        }
    }

    fn drawHitLines(self: *const Self, matrix: sdk.math.Mat4) void {
        for (&self.frame.players) |*player| {
            const color = config.hit_lines.outline.colors.get(player.attack_type orelse .not_attack);
            for (player.hit_lines.asConstSlice()) |hit_line| {
                const line = hit_line.line;
                const thickness = config.hit_lines.fill.thickness + 2.0 * config.hit_lines.outline.thickness;
                drawLine(line, color, thickness, matrix);
            }
        }
        for (&self.frame.players) |*player| {
            const color = config.hit_lines.fill.colors.get(player.attack_type orelse .not_attack);
            for (player.hit_lines.asConstSlice()) |hit_line| {
                const line = hit_line.line;
                const thickness = config.hit_lines.fill.thickness;
                drawLine(line, color, thickness, matrix);
            }
        }
    }

    fn drawLingeringHitLines(self: *const Self, matrix: sdk.math.Mat4) void {
        for (0..self.lingering_hit_lines.len) |index| {
            const hit_line = self.lingering_hit_lines.get(index) catch unreachable;
            const line = hit_line.line;

            const duration = config.hit_lines.duration;
            const completion = hit_line.life_time / duration;
            var color = config.hit_lines.outline.colors.get(hit_line.attack_type orelse .not_attack);
            color.asColor().a *= 1.0 - (completion * completion * completion * completion);
            const thickness = config.hit_lines.fill.thickness + 2.0 * config.hit_lines.outline.thickness;

            drawLine(line, color, thickness, matrix);
        }
        for (0..self.lingering_hit_lines.len) |index| {
            const hit_line = self.lingering_hit_lines.get(index) catch unreachable;
            const line = hit_line.line;

            const duration = config.hit_lines.duration;
            const completion = hit_line.life_time / duration;
            var color = config.hit_lines.fill.colors.get(hit_line.attack_type orelse .not_attack);
            color.asColor().a *= 1.0 - (completion * completion * completion * completion);
            const thickness = config.hit_lines.fill.thickness;

            drawLine(line, color, thickness, matrix);
        }
    }

    fn drawLookAtLines(self: *const Self, direction: Direction, matrix: sdk.math.Mat4) void {
        if (direction != .top) {
            return;
        }
        for (&self.frame.players) |*player| {
            const position = player.position orelse continue;
            const rotation = player.rotation orelse continue;
            const length = config.look_direction.length;
            const delta = sdk.math.Vec3.plus_x.scale(length).rotateZ(rotation);
            const line = sdk.math.LineSegment3{
                .point_1 = position,
                .point_2 = position.add(delta),
            };
            const color = config.look_direction.color;
            const thickness = config.look_direction.thickness;
            drawLine(line, color, thickness, matrix);
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
        const color = config.floor.color;
        const u32_color = imgui.igGetColorU32_Vec4(color.toImVec());
        const thickness = config.floor.thickness;

        imgui.ImDrawList_AddLine(draw_list, point_1, point_2, u32_color, thickness);
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
