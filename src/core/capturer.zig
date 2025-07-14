const std = @import("std");
const misc = @import("../misc/root.zig");
const math = @import("../math/root.zig");
const game = @import("../game/root.zig");
const memory = @import("../memory/root.zig");
const core = @import("root.zig");

pub const Capturer = struct {
    previous_player_1_hit_lines: ?game.HitLines = null,
    previous_player_2_hit_lines: ?game.HitLines = null,

    const Self = @This();
    pub const GameMemory = struct {
        player_1: misc.Partial(game.Player),
        player_2: misc.Partial(game.Player),
    };

    pub fn captureFrame(self: *Self, game_memory: *const GameMemory) core.Frame {
        var player_1 = self.capturePlayer(&game_memory.player_1, .player_1);
        var player_2 = self.capturePlayer(&game_memory.player_2, .player_2);
        detectIntersections(&player_1.hurt_cylinders, &player_2.hit_lines);
        detectIntersections(&player_2.hurt_cylinders, &player_1.hit_lines);
        const main_player_id = captureMainPlayerId(game_memory);
        const left_player_id = captureLeftPlayerId(game_memory, main_player_id);
        self.updatePreviousHitLines(game_memory);
        return .{
            .players = .{ player_1, player_2 },
            .left_player_id = left_player_id,
            .main_player_id = main_player_id,
        };
    }

    fn updatePreviousHitLines(self: *Self, game_memory: *const GameMemory) void {
        self.previous_player_1_hit_lines = game_memory.player_1.hit_lines;
        self.previous_player_2_hit_lines = game_memory.player_2.hit_lines;
    }

    fn captureMainPlayerId(game_memory: *const GameMemory) core.PlayerId {
        if (game_memory.player_1.is_picked_by_main_player) |is_main| {
            return if (is_main) .player_1 else .player_2;
        }
        if (game_memory.player_2.is_picked_by_main_player) |is_main| {
            return if (is_main) .player_2 else .player_1;
        }
        return .player_1;
    }

    fn captureLeftPlayerId(game_memory: *const GameMemory, main_player_id: core.PlayerId) core.PlayerId {
        const main_player = if (main_player_id == .player_1) &game_memory.player_1 else &game_memory.player_2;
        if (main_player.input_side) |side| {
            return if (side == .left) main_player_id else main_player_id.getOther();
        } else {
            return .player_1;
        }
    }

    fn capturePlayer(self: *Self, player: *const misc.Partial(game.Player), player_id: core.PlayerId) core.Player {
        return .{
            .position = capturePlayerPosition(player),
            .skeleton = captureSkeleton(player),
            .hurt_cylinders = captureHurtCylinders(player),
            .collision_spheres = captureCollisionSpheres(player),
            .hit_lines = self.captureHitLines(player, player_id),
        };
    }

    fn capturePlayerPosition(player: *const misc.Partial(game.Player)) ?math.Vec3 {
        if (player.collision_spheres) |*spheres| {
            return spheres.lower_torso.convert().center;
        }
        if (player.hurt_cylinders) |*cylinders| {
            return cylinders.upper_torso.convert().center;
        }
        return null;
    }

    fn captureSkeleton(player: *const misc.Partial(game.Player)) ?core.Skeleton {
        const cylinders: *const game.HurtCylinders = if (player.hurt_cylinders) |*c| c else return null;
        const spheres: *const game.CollisionSpheres = if (player.collision_spheres) |*s| s else return null;
        return .init(.{
            .head = cylinders.head.convert().center,
            .neck = spheres.neck.convert().center,
            .upper_torso = cylinders.upper_torso.convert().center,
            .left_shoulder = cylinders.left_shoulder.convert().center,
            .right_shoulder = cylinders.right_shoulder.convert().center,
            .left_elbow = cylinders.left_elbow.convert().center,
            .right_elbow = cylinders.right_elbow.convert().center,
            .left_hand = cylinders.left_hand.convert().center,
            .right_hand = cylinders.right_hand.convert().center,
            .lower_torso = spheres.lower_torso.convert().center,
            .left_pelvis = cylinders.left_pelvis.convert().center,
            .right_pelvis = cylinders.right_pelvis.convert().center,
            .left_knee = cylinders.left_knee.convert().center,
            .right_knee = cylinders.right_knee.convert().center,
            .left_ankle = cylinders.left_ankle.convert().center,
            .right_ankle = cylinders.right_ankle.convert().center,
        });
    }

    fn captureHurtCylinders(player: *const misc.Partial(game.Player)) ?core.HurtCylinders {
        const cylinders: *const game.HurtCylinders = if (player.hurt_cylinders) |*c| c else return null;
        const convert = struct {
            fn call(input: *const game.HurtCylinders.Element) core.HurtCylinder {
                const converted = input.convert();
                const cylinder = math.Cylinder{
                    .center = converted.center,
                    .radius = converted.radius,
                    .half_height = converted.half_height,
                };
                return .{ .cylinder = cylinder, .intersects = false };
            }
        }.call;
        return .init(.{
            .left_ankle = convert(&cylinders.left_ankle),
            .right_ankle = convert(&cylinders.right_ankle),
            .left_hand = convert(&cylinders.left_hand),
            .right_hand = convert(&cylinders.right_hand),
            .left_knee = convert(&cylinders.left_knee),
            .right_knee = convert(&cylinders.right_knee),
            .left_elbow = convert(&cylinders.left_elbow),
            .right_elbow = convert(&cylinders.right_elbow),
            .head = convert(&cylinders.head),
            .left_shoulder = convert(&cylinders.left_shoulder),
            .right_shoulder = convert(&cylinders.right_shoulder),
            .upper_torso = convert(&cylinders.upper_torso),
            .left_pelvis = convert(&cylinders.left_pelvis),
            .right_pelvis = convert(&cylinders.right_pelvis),
        });
    }

    fn captureCollisionSpheres(player: *const misc.Partial(game.Player)) ?core.CollisionSpheres {
        const spheres: *const game.CollisionSpheres = if (player.collision_spheres) |*s| s else return null;
        const convert = struct {
            fn call(input: *const game.CollisionSpheres.Element) core.CollisionSphere {
                const converted = input.convert();
                return .{ .center = converted.center, .radius = converted.radius };
            }
        }.call;
        return .init(.{
            .neck = convert(&spheres.neck),
            .left_elbow = convert(&spheres.left_elbow),
            .right_elbow = convert(&spheres.right_elbow),
            .lower_torso = convert(&spheres.lower_torso),
            .left_knee = convert(&spheres.left_knee),
            .right_knee = convert(&spheres.right_knee),
            .left_ankle = convert(&spheres.left_ankle),
            .right_ankle = convert(&spheres.right_ankle),
        });
    }

    fn captureHitLines(
        self: *const Self,
        player: *const misc.Partial(game.Player),
        player_id: core.PlayerId,
    ) core.HitLines {
        var result: core.HitLines = .{};
        const previous_lines: *const game.HitLines = switch (player_id) {
            .player_1 => &(self.previous_player_1_hit_lines orelse return result),
            .player_2 => &(self.previous_player_2_hit_lines orelse return result),
        };
        const current_lines: *const game.HitLines = if (player.hit_lines) |*l| l else return result;
        for (previous_lines, current_lines) |*raw_previous_line, *raw_current_line| {
            const previous_line = raw_previous_line.convert();
            const current_line = raw_current_line.convert();
            if (current_line.ignore) {
                continue;
            }
            if (std.meta.eql(previous_line.points, current_line.points)) {
                continue;
            }
            const line_1 = math.LineSegment3{
                .point_1 = current_line.points[0].position,
                .point_2 = current_line.points[1].position,
            };
            const line_2 = math.LineSegment3{
                .point_1 = current_line.points[1].position,
                .point_2 = current_line.points[2].position,
            };
            result.buffer[result.len] = .{ .line = line_1, .intersects = false };
            result.buffer[result.len + 1] = .{ .line = line_2, .intersects = false };
            result.len += 2;
        }
        return result;
    }

    fn detectIntersections(hurt_cylinders: *?core.HurtCylinders, hit_lines: *core.HitLines) void {
        const cylinders: *core.HurtCylinders = if (hurt_cylinders.*) |*c| c else return;
        for (&cylinders.values) |*cylinder| {
            for (hit_lines.asMutableSlice()) |*line| {
                const intersects = math.checkCylinderLineSegmentIntersection(cylinder.cylinder, line.line);
                cylinder.intersects = intersects;
                line.intersects = intersects;
            }
        }
    }
};
