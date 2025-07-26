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
        const frames_since_round_start = captureFramesSinceRoundStart(game_memory);
        const floor_z = captureFloorZ(game_memory);
        const player_1 = self.capturePlayer(&game_memory.player_1, .player_1);
        const player_2 = self.capturePlayer(&game_memory.player_2, .player_2);
        const main_player_id = captureMainPlayerId(game_memory);
        const left_player_id = captureLeftPlayerId(game_memory, main_player_id);
        self.updatePreviousHitLines(game_memory);
        return .{
            .frames_since_round_start = frames_since_round_start,
            .floor_z = floor_z,
            .players = .{ player_1, player_2 },
            .left_player_id = left_player_id,
            .main_player_id = main_player_id,
        };
    }

    fn updatePreviousHitLines(self: *Self, game_memory: *const GameMemory) void {
        self.previous_player_1_hit_lines = game_memory.player_1.hit_lines;
        self.previous_player_2_hit_lines = game_memory.player_2.hit_lines;
    }

    fn captureFramesSinceRoundStart(game_memory: *const GameMemory) ?u32 {
        if (game_memory.player_1.frames_since_round_start) |frames| {
            return frames;
        }
        if (game_memory.player_2.frames_since_round_start) |frames| {
            return frames;
        }
        return null;
    }

    fn captureFloorZ(game_memory: *const GameMemory) ?f32 {
        if (game_memory.player_1.floor_z) |raw_z1| {
            const z1 = raw_z1.convert();
            if (game_memory.player_2.floor_z) |raw_z2| {
                const z2 = raw_z2.convert();
                return 0.5 * (z1 + z2);
            } else {
                return z1;
            }
        } else if (game_memory.player_2.floor_z) |raw_z2| {
            const z2 = raw_z2.convert();
            return z2;
        } else {
            return null;
        }
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
            .character_id = player.character_id,
            .current_move_id = player.current_move_id,
            .current_move_frame = player.current_move_frame,
            .current_move_total_frames = player.current_move_total_frames,
            .attack_type = captureAttackType(player),
            .attack_damage = player.attack_damage,
            .hit_outcome = captureHitOutcome(player),
            .input = captureInput(player),
            // .health = player.health, // TODO make it work after decrypting health
            .rage = captureRage(player),
            .heat = captureHeat(player),
            .position = capturePlayerPosition(player),
            .rotation = capturePlayerRotation(player),
            .skeleton = captureSkeleton(player),
            .hurt_cylinders = captureHurtCylinders(player),
            .collision_spheres = captureCollisionSpheres(player),
            .hit_lines = self.captureHitLines(player, player_id),
        };
    }

    fn captureAttackType(player: *const misc.Partial(game.Player)) ?core.AttackType {
        const attack_type: game.AttackType = player.attack_type orelse return null;
        return switch (attack_type) {
            .not_attack => .not_attack,
            .high => .high,
            .mid => .mid,
            .low => .low,
            .special_mid => .special_mid,
            .high_unblockable => .high_unblockable,
            .mid_unblockable => .mid_unblockable,
            .low_unblockable => .low_unblockable,
            .throw => .throw,
            .projectile => .projectile,
            .antiair_only => .antiair_only,
            else => null,
        };
    }

    fn captureHitOutcome(player: *const misc.Partial(game.Player)) ?core.HitOutcome {
        const hit_outcome: game.HitOutcome = player.hit_outcome orelse return null;
        return switch (hit_outcome) {
            .none => .none,
            .blocked_standing => .blocked_standing,
            .blocked_crouching => .blocked_crouching,
            .juggle => .juggle,
            .screw => .screw,
            .grounded_face_down => .grounded_face_down,
            .grounded_face_up => .grounded_face_up,
            .counter_hit_standing => .counter_hit_standing,
            .counter_hit_crouching => .counter_hit_crouching,
            .normal_hit_standing => .normal_hit_standing,
            .normal_hit_crouching => .normal_hit_crouching,
            .normal_hit_standing_left => .normal_hit_standing_left,
            .normal_hit_crouching_left => .normal_hit_crouching_left,
            .normal_hit_standing_back => .normal_hit_standing_back,
            .normal_hit_crouching_back => .normal_hit_crouching_back,
            .normal_hit_standing_right => .normal_hit_standing_right,
            .normal_hit_crouching_right => .normal_hit_crouching_right,
            else => null,
        };
    }

    fn captureInput(player: *const misc.Partial(game.Player)) ?core.Input {
        const input: game.Input = player.input orelse return null;
        return .{
            .up = input.up,
            .down = input.down,
            .left = input.left,
            .right = input.right,
            .special_style = input.special_style,
            .heat = input.heat,
            .rage = input.rage,
            .button_1 = input.button_1,
            .button_2 = input.button_2,
            .button_3 = input.button_3,
            .button_4 = input.button_4,
        };
    }

    fn captureRage(player: *const misc.Partial(game.Player)) ?core.Rage {
        const in_rage = player.in_heat orelse return null;
        const used_rage = player.used_heat orelse return null;
        if (in_rage) {
            return .activated;
        } else if (used_rage) {
            return .used_up;
        } else {
            return .available;
        }
    }

    fn captureHeat(player: *const misc.Partial(game.Player)) ?core.Heat {
        const in_heat = player.in_heat orelse return null;
        const used_heat = player.used_heat orelse return null;
        const heat_gauge = player.heat_gauge orelse return null;
        if (in_heat) {
            return .{ .activated = .{ .gauge = heat_gauge.convert() } };
        } else if (used_heat) {
            return .used_up;
        } else {
            return .available;
        }
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

    fn capturePlayerRotation(player: *const misc.Partial(game.Player)) ?f32 {
        const raw_matrix = player.transform_matrix orelse {
            const raw_rotation = player.rotation orelse return null;
            return raw_rotation.convert();
        };
        const matrix: math.Mat4 = raw_matrix.convert();
        const transformed = math.Vec3.plus_x.directionTransform(matrix);
        var angle = std.math.atan2(transformed.y(), transformed.x());
        angle += 0.5 * std.math.pi; // Since model's forward direction is +Y the look at direction differs for 90 deg.
        if (angle >= std.math.pi) {
            angle -= 2.0 * std.math.pi;
        }
        return angle;
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
                return .{ .cylinder = cylinder };
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
            result.buffer[result.len] = .{ .line = line_1 };
            result.buffer[result.len + 1] = .{ .line = line_2 };
            result.len += 2;
        }
        return result;
    }
};

const testing = std.testing;

test "should capture frames since round start correctly" {
    var capturer = Capturer{};
    try testing.expectEqual(
        123,
        capturer.captureFrame(&.{
            .player_1 = .{ .frames_since_round_start = 123 },
            .player_2 = .{ .frames_since_round_start = 123 },
        }).frames_since_round_start,
    );
    try testing.expectEqual(
        123,
        capturer.captureFrame(&.{
            .player_1 = .{ .frames_since_round_start = 123 },
            .player_2 = .{ .frames_since_round_start = null },
        }).frames_since_round_start,
    );
    try testing.expectEqual(
        123,
        capturer.captureFrame(&.{
            .player_1 = .{ .frames_since_round_start = null },
            .player_2 = .{ .frames_since_round_start = 123 },
        }).frames_since_round_start,
    );
    try testing.expectEqual(
        null,
        capturer.captureFrame(&.{
            .player_1 = .{ .frames_since_round_start = null },
            .player_2 = .{ .frames_since_round_start = null },
        }).frames_since_round_start,
    );
}

test "should capture floor Z correctly" {
    var capturer = Capturer{};
    try testing.expectEqual(
        150.0,
        capturer.captureFrame(&.{
            .player_1 = .{ .floor_z = .fromConverted(100.0) },
            .player_2 = .{ .floor_z = .fromConverted(200.0) },
        }).floor_z,
    );
    try testing.expectEqual(
        123.0,
        capturer.captureFrame(&.{
            .player_1 = .{ .floor_z = .fromConverted(123.0) },
            .player_2 = .{ .floor_z = null },
        }).floor_z,
    );
    try testing.expectEqual(
        123.0,
        capturer.captureFrame(&.{
            .player_1 = .{ .floor_z = null },
            .player_2 = .{ .floor_z = .fromConverted(123.0) },
        }).floor_z,
    );
    try testing.expectEqual(
        null,
        capturer.captureFrame(&.{
            .player_1 = .{ .floor_z = null },
            .player_2 = .{ .floor_z = null },
        }).floor_z,
    );
}

test "should capture left player id correctly" {
    var capturer = Capturer{};
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = true, .input_side = null },
            .player_2 = .{ .is_picked_by_main_player = false, .input_side = null },
        }).left_player_id,
    );
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = true, .input_side = .left },
            .player_2 = .{ .is_picked_by_main_player = false, .input_side = null },
        }).left_player_id,
    );
    try testing.expectEqual(
        .player_2,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = true, .input_side = .right },
            .player_2 = .{ .is_picked_by_main_player = false, .input_side = null },
        }).left_player_id,
    );
    try testing.expectEqual(
        .player_2,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = false, .input_side = null },
            .player_2 = .{ .is_picked_by_main_player = true, .input_side = .left },
        }).left_player_id,
    );
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = false, .input_side = null },
            .player_2 = .{ .is_picked_by_main_player = true, .input_side = .right },
        }).left_player_id,
    );
}

test "should capture main player id correctly" {
    var capturer = Capturer{};
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = true },
            .player_2 = .{ .is_picked_by_main_player = false },
        }).main_player_id,
    );
    try testing.expectEqual(
        .player_2,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = false },
            .player_2 = .{ .is_picked_by_main_player = true },
        }).main_player_id,
    );
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = null },
            .player_2 = .{ .is_picked_by_main_player = null },
        }).main_player_id,
    );
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = true },
            .player_2 = .{ .is_picked_by_main_player = null },
        }).main_player_id,
    );
    try testing.expectEqual(
        .player_2,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = false },
            .player_2 = .{ .is_picked_by_main_player = null },
        }).main_player_id,
    );
    try testing.expectEqual(
        .player_2,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = null },
            .player_2 = .{ .is_picked_by_main_player = true },
        }).main_player_id,
    );
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = null },
            .player_2 = .{ .is_picked_by_main_player = false },
        }).main_player_id,
    );
}

// TODO rest of the tests
