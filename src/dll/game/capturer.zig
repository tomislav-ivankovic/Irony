const std = @import("std");
const build_info = @import("build_info");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const game = @import("root.zig");

pub fn Capturer(comptime game_id: build_info.Game) type {
    return struct {
        player_1_state: PlayerState = .{},
        player_2_state: PlayerState = .{},

        const Self = @This();
        const PartialPlayer = sdk.misc.Partial(game.Player(game_id));
        pub const GameMemory = struct {
            player_1: PartialPlayer,
            player_2: PartialPlayer,
            camera: ?game.Camera(game_id) = null,
        };
        pub const PlayerState = struct {
            airborne_state: AirborneState = .{},
            rage_state: RageState = .{},
            previous_hit_lines: ?game.HitLines(game_id) = null,
        };
        const AirborneState = packed struct {
            airborne_started: bool = false,
            airborne_ended: bool = false,
            low_crushing_started: bool = false,
            low_crushing_ended: bool = false,
        };
        const RageState = switch (game_id) {
            .t7 => struct {
                previous_frames_since_round_start: u32 = 0,
                was_in_rage_this_round: bool = false,
            },
            .t8 => struct {},
        };

        pub fn captureFrame(self: *Self, game_memory: *const GameMemory) model.Frame {
            const frames_since_round_start = captureFramesSinceRoundStart(game_memory);
            const floor_z = captureFloorZ(game_memory);
            const player_1 = capturePlayer(&self.player_1_state, &game_memory.player_1, .player_1);
            const player_2 = capturePlayer(&self.player_2_state, &game_memory.player_2, .player_2);
            const camera = captureCamera(game_memory);
            const main_player_id = captureMainPlayerId(game_memory);
            const left_player_id = captureLeftPlayerId(game_memory, main_player_id);
            return .{
                .frames_since_round_start = frames_since_round_start,
                .floor_z = floor_z,
                .players = .{ player_1, player_2 },
                .camera = camera,
                .left_player_id = left_player_id,
                .main_player_id = main_player_id,
            };
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

        fn captureCamera(game_memory: *const GameMemory) ?model.Camera {
            const camera = if (game_memory.camera) |c| c.convert() else return null;
            return .{
                .position = camera.position,
                .pitch = camera.pitch,
                .yaw = camera.yaw,
                .roll = camera.roll,
            };
        }

        fn captureMainPlayerId(game_memory: *const GameMemory) model.PlayerId {
            if (game_memory.player_1.is_picked_by_main_player) |boolean| {
                if (boolean.toBool()) |is_main| {
                    return if (is_main) .player_1 else .player_2;
                }
            }
            if (game_memory.player_2.is_picked_by_main_player) |boolean| {
                if (boolean.toBool()) |is_main| {
                    return if (is_main) .player_2 else .player_1;
                }
            }
            return .player_1;
        }

        fn captureLeftPlayerId(game_memory: *const GameMemory, main_player_id: model.PlayerId) model.PlayerId {
            const main_player = if (main_player_id == .player_1) &game_memory.player_1 else &game_memory.player_2;
            if (main_player.input_side) |side| {
                return if (side == .left) main_player_id else main_player_id.getOther();
            } else {
                return .player_1;
            }
        }

        fn capturePlayer(
            state: *PlayerState,
            player: *const PartialPlayer,
            player_id: model.PlayerId,
        ) model.Player {
            updateAirborneState(state, player);
            updateRageState(state, player);
            const captured_player = model.Player{
                .character_id = player.character_id,
                .animation_id = player.animation_id,
                .animation_frame = player.animation_frame,
                .animation_total_frames = player.animation_total_frames,
                .attack_type = captureAttackType(player),
                .attack_damage = player.attack_damage,
                .hit_outcome = captureHitOutcome(player),
                .posture = capturePosture(state, player),
                .blocking = captureBlocking(player),
                .crushing = captureCrushing(state, player),
                .can_move = if (player.can_move) |can_move| can_move.toBool() else null,
                .input = captureInput(player, player_id),
                .health = switch (game_id) {
                    .t7 => if (player.health) |*health| @intCast(health.convert().value) else null,
                    .t8 => if (player.health) |*health| health.convert() else null,
                },
                .rage = captureRage(state, player),
                .heat = captureHeat(player),
                .rotation = capturePlayerRotation(player),
                .hurt_cylinders = captureHurtCylinders(player),
                .collision_spheres = captureCollisionSpheres(player),
                .hit_lines = captureHitLines(state, player),
            };
            updatePreviousHitLines(state, player);
            return captured_player;
        }

        fn updateAirborneState(state: *PlayerState, player: *const PartialPlayer) void {
            const animation_frame: u32 = player.animation_frame orelse return;
            const state_flags: game.StateFlags = player.state_flags orelse return;
            const airborne_flags: game.AirborneFlags = player.airborne_flags orelse return;
            if (animation_frame == 1) {
                state.airborne_state = .{};
            }
            if (!state_flags.airborne_move_or_downed or !state_flags.airborne_move_and_not_juggled) {
                return;
            }
            if (airborne_flags.probably_airborne or !airborne_flags.not_airborne_and_not_downed) {
                state.airborne_state.airborne_started = true;
            }
            if (airborne_flags.low_crushing_start) {
                state.airborne_state.airborne_started = true;
                state.airborne_state.low_crushing_started = true;
            }
            if (airborne_flags.low_crushing_end) {
                state.airborne_state.low_crushing_ended = true;
            }
            if (airborne_flags.airborne_end) {
                state.airborne_state.low_crushing_ended = true;
                state.airborne_state.airborne_ended = true;
            }
        }

        fn updateRageState(state: *PlayerState, player: *const PartialPlayer) void {
            if (game_id != .t7) {
                return;
            }
            const frames_since_round_start: u32 = player.frames_since_round_start orelse return;
            const previous_frames_since_round_start: *u32 = &state.rage_state.previous_frames_since_round_start;
            defer previous_frames_since_round_start.* = frames_since_round_start;
            if (frames_since_round_start < previous_frames_since_round_start.*) {
                state.rage_state.was_in_rage_this_round = false;
            }
            const in_rage: bool = (if (player.in_rage) |b| b.toBool() else null) orelse return;
            if (in_rage) {
                state.rage_state.was_in_rage_this_round = true;
            }
        }

        fn updatePreviousHitLines(state: *PlayerState, player: *const PartialPlayer) void {
            state.previous_hit_lines = player.hit_lines;
        }

        fn captureAttackType(player: *const PartialPlayer) ?model.AttackType {
            const attack_type: game.AttackType = player.attack_type orelse return null;
            return switch (attack_type) {
                .not_attack => .not_attack,
                .high => .high,
                .mid => .mid,
                .low => .low,
                .special_low => .special_low,
                .unblockable_high => .unblockable_high,
                .unblockable_mid => .unblockable_mid,
                .unblockable_low => .unblockable_low,
                .throw => .throw,
                .projectile => .projectile,
                .antiair_only => .antiair_only,
                else => null,
            };
        }

        fn captureHitOutcome(player: *const PartialPlayer) ?model.HitOutcome {
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

        fn capturePosture(state: *const PlayerState, player: *const PartialPlayer) ?model.Posture {
            const state_flags: game.StateFlags = player.state_flags orelse return null;
            const airborne_state = state.airborne_state;
            if (state_flags.crouching) {
                return .crouching;
            } else if (state_flags.downed) {
                if (state_flags.face_down) {
                    return .downed_face_down;
                } else {
                    return .downed_face_up;
                }
            } else if (state_flags.being_juggled or
                (airborne_state.airborne_started and !airborne_state.airborne_ended))
            {
                return .airborne;
            } else {
                return .standing;
            }
        }

        fn captureBlocking(player: *const PartialPlayer) ?model.Blocking {
            const state_flags: game.StateFlags = player.state_flags orelse return null;
            if (state_flags.blocking_mids) {
                if (state_flags.neutral_blocking) {
                    return .neutral_blocking_mids;
                } else {
                    return .fully_blocking_mids;
                }
            } else if (state_flags.blocking_lows) {
                if (state_flags.neutral_blocking) {
                    return .neutral_blocking_lows;
                } else {
                    return .fully_blocking_lows;
                }
            } else {
                return .not_blocking;
            }
        }

        fn captureCrushing(state: *PlayerState, player: *const PartialPlayer) ?model.Crushing {
            const posture = capturePosture(state, player) orelse return null;
            const state_flags: game.StateFlags = player.state_flags orelse return null;
            const simple_state: game.SimpleState = player.simple_state orelse return null;
            const airborne_state = state.airborne_state;
            const power_crushing: sdk.memory.Boolean(.{}) = player.power_crushing orelse return null;
            return .{
                .high_crushing = posture == .crouching or posture == .downed_face_down or posture == .downed_face_up,
                .low_crushing = posture == .airborne and
                    airborne_state.airborne_started and
                    !airborne_state.low_crushing_ended and
                    !state_flags.being_juggled,
                .anti_air_only_crushing = posture != .airborne,
                .power_crushing = power_crushing.toBool() orelse return null,
                .invincibility = simple_state == .invincible,
            };
        }

        fn captureInput(player: *const PartialPlayer, player_id: model.PlayerId) ?model.Input {
            const input: game.Input(game_id) = player.input orelse return null;
            const input_side: game.PlayerSide = player.input_side orelse (if (player_id == .player_1) .left else .right);
            return .{
                .forward = if (input_side == .left) input.right else input.left,
                .back = if (input_side == .left) input.left else input.right,
                .up = input.up,
                .down = input.down,
                .left = input.left,
                .right = input.right,
                .button_1 = input.button_1,
                .button_2 = input.button_2,
                .button_3 = input.button_3,
                .button_4 = input.button_4,
                .special_style = input.special_style,
                .rage = input.rage,
                .heat = switch (game_id) {
                    .t7 => false,
                    .t8 => input.heat,
                },
            };
        }

        fn captureRage(state: *PlayerState, player: *const PartialPlayer) ?model.Rage {
            const in_rage = (if (player.in_rage) |b| b.toBool() else null) orelse return null;
            switch (in_rage) {
                true => return .activated,
                false => switch (game_id) {
                    .t7 => switch (state.rage_state.was_in_rage_this_round) {
                        true => return .used_up,
                        false => return .available,
                    },
                    .t8 => {
                        const used_rage = (if (player.used_rage) |b| b.toBool() else null) orelse return null;
                        return switch (used_rage) {
                            true => return .used_up,
                            false => return .available,
                        };
                    },
                },
            }
        }

        fn captureHeat(player: *const PartialPlayer) ?model.Heat {
            if (game_id != .t8) {
                return .used_up;
            }
            const in_heat = (if (player.in_heat) |b| b.toBool() else null) orelse return null;
            const used_heat = (if (player.used_heat) |b| b.toBool() else null) orelse return null;
            const heat_gauge = player.heat_gauge orelse return null;
            if (in_heat) {
                return .{ .activated = .{ .gauge = heat_gauge.convert() } };
            } else if (used_heat) {
                return .used_up;
            } else {
                return .available;
            }
        }

        fn capturePlayerRotation(player: *const PartialPlayer) ?f32 {
            if (player.rotation) |rotation| {
                return rotation.convert();
            }
            const raw_matrix = player.transform_matrix orelse return null;
            const matrix: sdk.math.Mat4 = raw_matrix.convert();
            const transformed = sdk.math.Vec3.plus_x.directionTransform(matrix);
            var angle = std.math.atan2(transformed.y(), transformed.x());
            angle += 0.5 * std.math.pi; // Since model's forward direction is +Y the look at direction differs for 90 deg.
            if (angle >= std.math.pi) {
                angle -= 2.0 * std.math.pi;
            }
            return angle;
        }

        fn captureHurtCylinders(player: *const PartialPlayer) ?model.HurtCylinders {
            const cylinders: *const game.HurtCylinders(game_id) = if (player.hurt_cylinders) |*c| c else return null;
            const convert = struct {
                fn call(input: *const game.HurtCylinders(game_id).Element) model.HurtCylinder {
                    const converted = input.convert();
                    const cylinder = sdk.math.Cylinder{
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

        fn captureCollisionSpheres(player: *const PartialPlayer) ?model.CollisionSpheres {
            const spheres: *const game.CollisionSpheres = if (player.collision_spheres) |*s| s else return null;
            const convert = struct {
                fn call(input: *const game.CollisionSpheres.Element) model.CollisionSphere {
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

        fn captureHitLines(state: *const PlayerState, player: *const PartialPlayer) model.HitLines {
            return switch (game_id) {
                .t7 => captureT7HitLines(state, player),
                .t8 => captureT8HitLines(state, player),
            };
        }

        fn captureT7HitLines(state: *const PlayerState, player: *const PartialPlayer) model.HitLines {
            const flags: game.PhaseFlags = player.phase_flags orelse return .{};
            if (!flags.is_active) {
                return .{};
            }
            const previous_lines: *const game.HitLines(.t7) = if (state.previous_hit_lines) |*l| l else return .{};
            const current_lines: *const game.HitLines(.t7) = if (player.hit_lines) |*l| l else return .{};
            var changed_points_buffer: [current_lines.len]game.HitLinePoint = undefined;
            var changed_points_len: usize = 0;
            for (previous_lines, current_lines) |*raw_previous_point, *raw_current_point| {
                const previous_point = raw_previous_point.convert();
                const current_point = raw_current_point.convert();
                if (std.meta.eql(previous_point, current_point)) {
                    continue;
                }
                changed_points_buffer[changed_points_len] = current_point;
                changed_points_len += 1;
            }
            var result: model.HitLines = .{};
            var index: usize = changed_points_len -% 2;
            while (index < changed_points_len) {
                const line = sdk.math.LineSegment3{
                    .point_1 = changed_points_buffer[index].position,
                    .point_2 = changed_points_buffer[index + 1].position,
                };
                result.buffer[result.len] = .{ .line = line };
                result.len += 1;
                index -%= 2;
            }
            return result;
        }

        fn captureT8HitLines(state: *const PlayerState, player: *const PartialPlayer) model.HitLines {
            const previous_lines: *const game.HitLines(.t8) = if (state.previous_hit_lines) |*l| l else return .{};
            const current_lines: *const game.HitLines(.t8) = if (player.hit_lines) |*l| l else return .{};
            var result: model.HitLines = .{};
            for (previous_lines, current_lines) |*raw_previous_line, *raw_current_line| {
                const previous_line = raw_previous_line.convert();
                const current_line = raw_current_line.convert();
                if (current_line.ignore != .false) {
                    continue;
                }
                if (std.meta.eql(previous_line.points, current_line.points)) {
                    continue;
                }
                const line_1 = sdk.math.LineSegment3{
                    .point_1 = current_line.points[0].position,
                    .point_2 = current_line.points[1].position,
                };
                const line_2 = sdk.math.LineSegment3{
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
}

const testing = std.testing;

test "should capture frames since round start correctly" {
    var capturer = Capturer(.t8){};
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
    var capturer = Capturer(.t8){};
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

test "should capture camera correctly" {
    var capturer = Capturer(.t8){};
    try testing.expectEqual(
        null,
        capturer.captureFrame(&.{
            .player_1 = .{},
            .player_2 = .{},
            .camera = null,
        }).camera,
    );
    try testing.expectEqual(
        model.Camera{
            .position = .fromArray(.{ 1, 2, 3 }),
            .pitch = 0.25 * std.math.pi,
            .roll = 0.5 * std.math.pi,
            .yaw = 0.75 * std.math.pi,
        },
        capturer.captureFrame(&.{
            .player_1 = .{},
            .player_2 = .{},
            .camera = .fromConverted(.{
                .position = .fromArray(.{ 1, 2, 3 }),
                .pitch = 0.25 * std.math.pi,
                .roll = 0.5 * std.math.pi,
                .yaw = 0.75 * std.math.pi,
            }),
        }).camera,
    );
}

test "should capture left player id correctly" {
    var capturer = Capturer(.t8){};
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = .true, .input_side = null },
            .player_2 = .{ .is_picked_by_main_player = .false, .input_side = null },
        }).left_player_id,
    );
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = .true, .input_side = .left },
            .player_2 = .{ .is_picked_by_main_player = .false, .input_side = null },
        }).left_player_id,
    );
    try testing.expectEqual(
        .player_2,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = .true, .input_side = .right },
            .player_2 = .{ .is_picked_by_main_player = .false, .input_side = null },
        }).left_player_id,
    );
    try testing.expectEqual(
        .player_2,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = .false, .input_side = null },
            .player_2 = .{ .is_picked_by_main_player = .true, .input_side = .left },
        }).left_player_id,
    );
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = .false, .input_side = null },
            .player_2 = .{ .is_picked_by_main_player = .true, .input_side = .right },
        }).left_player_id,
    );
}

test "should capture main player id correctly" {
    var capturer = Capturer(.t8){};
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = .true },
            .player_2 = .{ .is_picked_by_main_player = .false },
        }).main_player_id,
    );
    try testing.expectEqual(
        .player_2,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = .false },
            .player_2 = .{ .is_picked_by_main_player = .true },
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
            .player_1 = .{ .is_picked_by_main_player = .true },
            .player_2 = .{ .is_picked_by_main_player = null },
        }).main_player_id,
    );
    try testing.expectEqual(
        .player_2,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = .false },
            .player_2 = .{ .is_picked_by_main_player = null },
        }).main_player_id,
    );
    try testing.expectEqual(
        .player_2,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = null },
            .player_2 = .{ .is_picked_by_main_player = .true },
        }).main_player_id,
    );
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&.{
            .player_1 = .{ .is_picked_by_main_player = null },
            .player_2 = .{ .is_picked_by_main_player = .false },
        }).main_player_id,
    );
}

test "should capture character id correctly" {
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&.{
        .player_1 = .{ .character_id = 123 },
        .player_2 = .{ .character_id = null },
    });
    try testing.expectEqual(123, frame.getPlayerById(.player_1).character_id);
    try testing.expectEqual(null, frame.getPlayerById(.player_2).character_id);
}

test "should capture current animation id correctly" {
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&.{
        .player_1 = .{ .animation_id = 123 },
        .player_2 = .{ .animation_id = null },
    });
    try testing.expectEqual(123, frame.getPlayerById(.player_1).animation_id);
    try testing.expectEqual(null, frame.getPlayerById(.player_2).animation_id);
}

test "should capture current animation frame correctly" {
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&.{
        .player_1 = .{ .animation_frame = 123 },
        .player_2 = .{ .animation_frame = null },
    });
    try testing.expectEqual(123, frame.getPlayerById(.player_1).animation_frame);
    try testing.expectEqual(null, frame.getPlayerById(.player_2).animation_frame);
}

test "should capture current animation total frames correctly" {
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&.{
        .player_1 = .{ .animation_total_frames = 123 },
        .player_2 = .{ .animation_total_frames = null },
    });
    try testing.expectEqual(123, frame.getPlayerById(.player_1).animation_total_frames);
    try testing.expectEqual(null, frame.getPlayerById(.player_2).animation_total_frames);
}

test "should capture attack type correctly" {
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&.{
        .player_1 = .{ .attack_type = .special_low },
        .player_2 = .{ .attack_type = null },
    });
    try testing.expectEqual(.special_low, frame.getPlayerById(.player_1).attack_type);
    try testing.expectEqual(null, frame.getPlayerById(.player_2).attack_type);
}

test "should capture hit outcome correctly" {
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&.{
        .player_1 = .{ .hit_outcome = .normal_hit_standing },
        .player_2 = .{ .hit_outcome = null },
    });
    try testing.expectEqual(.normal_hit_standing, frame.getPlayerById(.player_1).hit_outcome);
    try testing.expectEqual(null, frame.getPlayerById(.player_2).hit_outcome);
}

// TODO test posture

test "should capture blocking correctly" {
    var capturer = Capturer(.t8){};
    const frame_1 = capturer.captureFrame(&.{
        .player_1 = .{ .state_flags = null },
        .player_2 = .{ .state_flags = .{} },
    });
    const frame_2 = capturer.captureFrame(&.{
        .player_1 = .{ .state_flags = .{ .blocking_mids = true, .blocking_lows = false, .neutral_blocking = true } },
        .player_2 = .{ .state_flags = .{ .blocking_mids = true, .blocking_lows = false, .neutral_blocking = false } },
    });
    const frame_3 = capturer.captureFrame(&.{
        .player_1 = .{ .state_flags = .{ .blocking_mids = false, .blocking_lows = true, .neutral_blocking = true } },
        .player_2 = .{ .state_flags = .{ .blocking_mids = false, .blocking_lows = true, .neutral_blocking = false } },
    });
    try testing.expectEqual(null, frame_1.getPlayerById(.player_1).blocking);
    try testing.expectEqual(.not_blocking, frame_1.getPlayerById(.player_2).blocking);
    try testing.expectEqual(.neutral_blocking_mids, frame_2.getPlayerById(.player_1).blocking);
    try testing.expectEqual(.fully_blocking_mids, frame_2.getPlayerById(.player_2).blocking);
    try testing.expectEqual(.neutral_blocking_lows, frame_3.getPlayerById(.player_1).blocking);
    try testing.expectEqual(.fully_blocking_lows, frame_3.getPlayerById(.player_2).blocking);
}

// TODO test crushing

test "should capture can move correctly" {
    var capturer = Capturer(.t8){};
    const frame_1 = capturer.captureFrame(&.{
        .player_1 = .{ .can_move = .false },
        .player_2 = .{ .can_move = .true },
    });
    const frame_2 = capturer.captureFrame(&.{
        .player_1 = .{ .can_move = null },
        .player_2 = .{ .can_move = @enumFromInt(2) },
    });
    try testing.expectEqual(false, frame_1.getPlayerById(.player_1).can_move);
    try testing.expectEqual(true, frame_1.getPlayerById(.player_2).can_move);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_1).can_move);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_2).can_move);
}

test "should capture input correctly in T7" {
    var capturer = Capturer(.t7){};
    const frame = capturer.captureFrame(&.{
        .player_1 = .{
            .input = .{
                .up = false,
                .down = true,
                .left = false,
                .right = true,
                .button_1 = false,
                .button_2 = true,
                .button_3 = false,
                .button_4 = true,
                .special_style = false,
                .rage = true,
            },
            .input_side = null,
        },
        .player_2 = .{
            .input = null,
            .input_side = null,
        },
    });
    try testing.expectEqual(model.Input{
        .forward = true,
        .back = false,
        .up = false,
        .down = true,
        .left = false,
        .right = true,
        .button_1 = false,
        .button_2 = true,
        .button_3 = false,
        .button_4 = true,
        .special_style = false,
        .rage = true,
        .heat = false,
    }, frame.getPlayerById(.player_1).input);
    try testing.expectEqual(null, frame.getPlayerById(.player_2).input);
}

test "should capture input correctly in T8" {
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&.{
        .player_1 = .{
            .input = .{
                .up = false,
                .down = true,
                .left = false,
                .right = true,
                .button_1 = false,
                .button_2 = true,
                .button_3 = false,
                .button_4 = true,
                .special_style = false,
                .rage = true,
                .heat = false,
            },
            .input_side = null,
        },
        .player_2 = .{
            .input = null,
            .input_side = null,
        },
    });
    try testing.expectEqual(model.Input{
        .forward = true,
        .back = false,
        .up = false,
        .down = true,
        .left = false,
        .right = true,
        .button_1 = false,
        .button_2 = true,
        .button_3 = false,
        .button_4 = true,
        .special_style = false,
        .rage = true,
        .heat = false,
    }, frame.getPlayerById(.player_1).input);
    try testing.expectEqual(null, frame.getPlayerById(.player_2).input);
}

test "should capture forward/back correctly depending on the input side" {
    var capturer = Capturer(.t8){};

    const frame_1 = capturer.captureFrame(&.{
        .player_1 = .{ .input = .{ .right = true }, .input_side = .left },
        .player_2 = .{ .input = .{ .right = true }, .input_side = .right },
    });
    try testing.expect(frame_1.getPlayerById(.player_1).input != null);
    try testing.expect(frame_1.getPlayerById(.player_2).input != null);
    try testing.expectEqual(true, frame_1.getPlayerById(.player_1).input.?.forward);
    try testing.expectEqual(false, frame_1.getPlayerById(.player_1).input.?.back);
    try testing.expectEqual(false, frame_1.getPlayerById(.player_2).input.?.forward);
    try testing.expectEqual(true, frame_1.getPlayerById(.player_2).input.?.back);

    const frame_2 = capturer.captureFrame(&.{
        .player_1 = .{ .input = .{ .left = true }, .input_side = .left },
        .player_2 = .{ .input = .{ .left = true }, .input_side = .right },
    });
    try testing.expect(frame_2.getPlayerById(.player_1).input != null);
    try testing.expect(frame_2.getPlayerById(.player_2).input != null);
    try testing.expectEqual(false, frame_2.getPlayerById(.player_1).input.?.forward);
    try testing.expectEqual(true, frame_2.getPlayerById(.player_1).input.?.back);
    try testing.expectEqual(true, frame_2.getPlayerById(.player_2).input.?.forward);
    try testing.expectEqual(false, frame_2.getPlayerById(.player_2).input.?.back);

    const frame_3 = capturer.captureFrame(&.{
        .player_1 = .{ .input = .{ .right = true }, .input_side = .right },
        .player_2 = .{ .input = .{ .right = true }, .input_side = .left },
    });
    try testing.expect(frame_3.getPlayerById(.player_1).input != null);
    try testing.expect(frame_3.getPlayerById(.player_2).input != null);
    try testing.expectEqual(false, frame_3.getPlayerById(.player_1).input.?.forward);
    try testing.expectEqual(true, frame_3.getPlayerById(.player_1).input.?.back);
    try testing.expectEqual(true, frame_3.getPlayerById(.player_2).input.?.forward);
    try testing.expectEqual(false, frame_3.getPlayerById(.player_2).input.?.back);

    const frame_4 = capturer.captureFrame(&.{
        .player_1 = .{ .input = .{ .left = true }, .input_side = .right },
        .player_2 = .{ .input = .{ .left = true }, .input_side = .left },
    });
    try testing.expect(frame_4.getPlayerById(.player_1).input != null);
    try testing.expect(frame_4.getPlayerById(.player_2).input != null);
    try testing.expectEqual(true, frame_4.getPlayerById(.player_1).input.?.forward);
    try testing.expectEqual(false, frame_4.getPlayerById(.player_1).input.?.back);
    try testing.expectEqual(false, frame_4.getPlayerById(.player_2).input.?.forward);
    try testing.expectEqual(true, frame_4.getPlayerById(.player_2).input.?.back);
}

test "should capture health correctly in T7" {
    var capturer = Capturer(.t7){};
    const frame_2 = capturer.captureFrame(&.{
        .player_1 = .{ .health = .fromConverted(.{
            .value = 123,
            .encryption_key = 0xBD20A1539B61342F,
        }) },
        .player_2 = .{ .health = null },
    });
    try testing.expectEqual(123, frame_2.getPlayerById(.player_1).health);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_2).health);
}

test "should capture health correctly in T8" {
    const DecryptHealth = struct {
        var argument: ?game.Health(.t8) = null;
        fn call(encrypted_health: *const game.Health(.t8)) callconv(.c) i64 {
            argument = encrypted_health.*;
            return 123 << 16;
        }
    };
    const oldDecryptT8Health = game.conversion_globals.decryptT8Health;
    defer game.conversion_globals.decryptT8Health = oldDecryptT8Health;

    var capturer = Capturer(.t8){};
    const encrypted = game.Health(.t8){ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };

    game.conversion_globals.decryptT8Health = null;
    const frame_1 = capturer.captureFrame(&.{
        .player_1 = .{ .health = .{ .raw = encrypted } },
        .player_2 = .{ .health = null },
    });
    try testing.expectEqual(null, frame_1.getPlayerById(.player_1).health);
    try testing.expectEqual(null, frame_1.getPlayerById(.player_2).health);
    try testing.expectEqual(null, DecryptHealth.argument);

    game.conversion_globals.decryptT8Health = DecryptHealth.call;
    const frame_2 = capturer.captureFrame(&.{
        .player_1 = .{ .health = .{ .raw = encrypted } },
        .player_2 = .{ .health = null },
    });
    try testing.expectEqual(123, frame_2.getPlayerById(.player_1).health);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_2).health);
    try testing.expectEqual(encrypted, DecryptHealth.argument);
}

test "should capture rage correctly in T7" {
    var capturer = Capturer(.t7){};

    const frame_1 = capturer.captureFrame(&.{
        .player_1 = .{ .in_rage = .false, .frames_since_round_start = 100 },
        .player_2 = .{ .in_rage = .true, .frames_since_round_start = 100 },
    });
    try testing.expectEqual(.available, frame_1.getPlayerById(.player_1).rage);
    try testing.expectEqual(.activated, frame_1.getPlayerById(.player_2).rage);

    const frame_2 = capturer.captureFrame(&.{
        .player_1 = .{ .in_rage = .false, .frames_since_round_start = 101 },
        .player_2 = .{ .in_rage = .false, .frames_since_round_start = 101 },
    });
    try testing.expectEqual(.available, frame_2.getPlayerById(.player_1).rage);
    try testing.expectEqual(.used_up, frame_2.getPlayerById(.player_2).rage);

    const frame_3 = capturer.captureFrame(&.{
        .player_1 = .{ .in_rage = .true, .frames_since_round_start = 100 },
        .player_2 = .{ .in_rage = .false, .frames_since_round_start = 100 },
    });
    try testing.expectEqual(.activated, frame_3.getPlayerById(.player_1).rage);
    try testing.expectEqual(.available, frame_3.getPlayerById(.player_2).rage);

    const frame_4 = capturer.captureFrame(&.{
        .player_1 = .{ .in_rage = null, .frames_since_round_start = 101 },
        .player_2 = .{ .in_rage = .false, .frames_since_round_start = null },
    });
    try testing.expectEqual(null, frame_4.getPlayerById(.player_1).rage);
    try testing.expectEqual(.available, frame_4.getPlayerById(.player_2).rage);
}

test "should capture rage correctly in T8" {
    var capturer = Capturer(.t8){};
    const frame_1 = capturer.captureFrame(&.{
        .player_1 = .{ .in_rage = .false, .used_rage = .false },
        .player_2 = .{ .in_rage = .true, .used_rage = .false },
    });
    const frame_2 = capturer.captureFrame(&.{
        .player_1 = .{ .in_rage = .false, .used_rage = .true },
        .player_2 = .{ .in_rage = null, .used_rage = null },
    });
    try testing.expectEqual(.available, frame_1.getPlayerById(.player_1).rage);
    try testing.expectEqual(.activated, frame_1.getPlayerById(.player_2).rage);
    try testing.expectEqual(.used_up, frame_2.getPlayerById(.player_1).rage);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_2).rage);
}

test "should capture heat correctly in T7" {
    var capturer = Capturer(.t7){};
    const frame = capturer.captureFrame(&.{ .player_1 = .{}, .player_2 = .{} });
    try testing.expectEqual(.used_up, frame.getPlayerById(.player_2).heat);
}

test "should capture heat correctly in T8" {
    var capturer = Capturer(.t8){};
    const frame_1 = capturer.captureFrame(&.{
        .player_1 = .{
            .in_heat = .false,
            .used_heat = .false,
            .heat_gauge = .fromConverted(0.5),
        },
        .player_2 = .{
            .in_heat = .true,
            .used_heat = .false,
            .heat_gauge = .fromConverted(0.5),
        },
    });
    const frame_2 = capturer.captureFrame(&.{
        .player_1 = .{
            .in_heat = .false,
            .used_heat = .true,
            .heat_gauge = .fromConverted(0.5),
        },
        .player_2 = .{
            .in_heat = null,
            .used_heat = null,
            .heat_gauge = null,
        },
    });
    try testing.expectEqual(.available, frame_1.getPlayerById(.player_1).heat);
    try testing.expectEqual(
        model.Heat{ .activated = .{ .gauge = 0.5 } },
        frame_1.getPlayerById(.player_2).heat,
    );
    try testing.expectEqual(.used_up, frame_2.getPlayerById(.player_1).heat);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_2).heat);
}

test "should capture player rotation correctly" {
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&.{
        .player_1 = .{
            .rotation = .fromConverted(0.75 * std.math.pi),
            .transform_matrix = .fromConverted(sdk.math.Mat4.fromZRotation(std.math.pi)),
        },
        .player_2 = .{
            .rotation = null,
            .transform_matrix = .fromConverted(sdk.math.Mat4.fromZRotation(std.math.pi)),
        },
    });
    try testing.expect(frame.getPlayerById(.player_1).rotation != null);
    try testing.expect(frame.getPlayerById(.player_2).rotation != null);
    try testing.expectApproxEqAbs(0.75 * std.math.pi, frame.getPlayerById(.player_1).rotation.?, 0.0001);
    try testing.expectApproxEqAbs(-0.5 * std.math.pi, frame.getPlayerById(.player_2).rotation.?, 0.0001);
}

test "should capture hurt cylinders correctly" {
    const hurtCylinder = struct {
        fn call(x: f32, y: f32, z: f32, r: f32, h: f32) game.HurtCylinders(.t8).Element {
            return .fromConverted(.{
                .center = .fromArray(.{ x, y, z }),
                .multiplier = 1.0,
                .half_height = h,
                .radius = r,
                .squared_radius = r * r,
                ._padding = undefined,
            });
        }
    }.call;
    const cylinder = struct {
        fn call(x: f32, y: f32, z: f32, r: f32, h: f32) sdk.math.Cylinder {
            return .{
                .center = .fromArray(.{ x, y, z }),
                .radius = r,
                .half_height = h,
            };
        }
    }.call;
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&.{
        .player_1 = .{
            .hurt_cylinders = .{
                .left_ankle = hurtCylinder(1, 2, 3, 4, 5),
                .right_ankle = hurtCylinder(6, 7, 8, 9, 10),
                .left_hand = hurtCylinder(11, 12, 13, 14, 15),
                .right_hand = hurtCylinder(16, 17, 18, 19, 20),
                .left_knee = hurtCylinder(21, 22, 23, 24, 25),
                .right_knee = hurtCylinder(26, 27, 28, 29, 30),
                .left_elbow = hurtCylinder(31, 32, 33, 34, 35),
                .right_elbow = hurtCylinder(36, 37, 38, 39, 40),
                .head = hurtCylinder(41, 42, 43, 44, 45),
                .left_shoulder = hurtCylinder(46, 47, 48, 49, 50),
                .right_shoulder = hurtCylinder(51, 52, 53, 54, 55),
                .upper_torso = hurtCylinder(56, 57, 58, 59, 60),
                .left_pelvis = hurtCylinder(61, 62, 63, 64, 65),
                .right_pelvis = hurtCylinder(66, 67, 68, 69, 70),
            },
        },
        .player_2 = .{ .hurt_cylinders = null },
    });

    try testing.expect(frame.getPlayerById(.player_1).hurt_cylinders != null);
    try testing.expectEqual(null, frame.getPlayerById(.player_2).hurt_cylinders);
    const cylinders = &frame.getPlayerById(.player_1).hurt_cylinders.?;

    try testing.expectEqual(cylinder(1, 2, 3, 4, 5), cylinders.get(.left_ankle).cylinder);
    try testing.expectEqual(cylinder(6, 7, 8, 9, 10), cylinders.get(.right_ankle).cylinder);
    try testing.expectEqual(cylinder(11, 12, 13, 14, 15), cylinders.get(.left_hand).cylinder);
    try testing.expectEqual(cylinder(16, 17, 18, 19, 20), cylinders.get(.right_hand).cylinder);
    try testing.expectEqual(cylinder(21, 22, 23, 24, 25), cylinders.get(.left_knee).cylinder);
    try testing.expectEqual(cylinder(26, 27, 28, 29, 30), cylinders.get(.right_knee).cylinder);
    try testing.expectEqual(cylinder(31, 32, 33, 34, 35), cylinders.get(.left_elbow).cylinder);
    try testing.expectEqual(cylinder(36, 37, 38, 39, 40), cylinders.get(.right_elbow).cylinder);
    try testing.expectEqual(cylinder(41, 42, 43, 44, 45), cylinders.get(.head).cylinder);
    try testing.expectEqual(cylinder(46, 47, 48, 49, 50), cylinders.get(.left_shoulder).cylinder);
    try testing.expectEqual(cylinder(51, 52, 53, 54, 55), cylinders.get(.right_shoulder).cylinder);
    try testing.expectEqual(cylinder(56, 57, 58, 59, 60), cylinders.get(.upper_torso).cylinder);
    try testing.expectEqual(cylinder(61, 62, 63, 64, 65), cylinders.get(.left_pelvis).cylinder);
    try testing.expectEqual(cylinder(66, 67, 68, 69, 70), cylinders.get(.right_pelvis).cylinder);
}

test "should capture collision spheres correctly" {
    const collisionSphere = struct {
        fn call(x: f32, y: f32, z: f32, r: f32) game.CollisionSpheres.Element {
            return .fromConverted(.{
                .center = .fromArray(.{ x, y, z }),
                .multiplier = 1.0,
                .radius = r,
                ._padding = undefined,
            });
        }
    }.call;
    const sphere = struct {
        fn call(x: f32, y: f32, z: f32, r: f32) sdk.math.Sphere {
            return .{
                .center = .fromArray(.{ x, y, z }),
                .radius = r,
            };
        }
    }.call;
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&.{
        .player_1 = .{
            .collision_spheres = .{
                .neck = collisionSphere(1, 2, 3, 4),
                .left_elbow = collisionSphere(5, 6, 7, 8),
                .right_elbow = collisionSphere(9, 10, 11, 12),
                .lower_torso = collisionSphere(13, 14, 15, 16),
                .left_knee = collisionSphere(17, 18, 19, 20),
                .right_knee = collisionSphere(21, 22, 23, 24),
                .left_ankle = collisionSphere(25, 26, 27, 28),
                .right_ankle = collisionSphere(29, 30, 31, 32),
            },
        },
        .player_2 = .{ .collision_spheres = null },
    });

    try testing.expect(frame.getPlayerById(.player_1).collision_spheres != null);
    try testing.expectEqual(null, frame.getPlayerById(.player_2).collision_spheres);
    const spheres = &frame.getPlayerById(.player_1).collision_spheres.?;

    try testing.expectEqual(sphere(1, 2, 3, 4), spheres.get(.neck));
    try testing.expectEqual(sphere(5, 6, 7, 8), spheres.get(.left_elbow));
    try testing.expectEqual(sphere(9, 10, 11, 12), spheres.get(.right_elbow));
    try testing.expectEqual(sphere(13, 14, 15, 16), spheres.get(.lower_torso));
    try testing.expectEqual(sphere(17, 18, 19, 20), spheres.get(.left_knee));
    try testing.expectEqual(sphere(21, 22, 23, 24), spheres.get(.right_knee));
    try testing.expectEqual(sphere(25, 26, 27, 28), spheres.get(.left_ankle));
    try testing.expectEqual(sphere(29, 30, 31, 32), spheres.get(.right_ankle));
}

test "should capture hit lines correctly in T7" {
    const point = struct {
        fn call(points: [3]f32) @typeInfo(game.HitLines(.t7)).array.child {
            return .fromConverted(.{
                .position = .fromArray(points),
                ._padding = 0,
            });
        }
    }.call;
    const line = struct {
        fn call(point_1: [3]f32, point_2: [3]f32) model.HitLine {
            return .{
                .line = .{
                    .point_1 = .fromArray(point_1),
                    .point_2 = .fromArray(point_2),
                },
            };
        }
    }.call;

    var capturer = Capturer(.t7){};

    const frame_1 = capturer.captureFrame(&.{
        .player_1 = .{
            .hit_lines = .{
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
            },
            .phase_flags = .{ .is_active = false },
        },
        .player_2 = .{
            .hit_lines = .{
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
            },
            .phase_flags = .{ .is_active = false },
        },
    });
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_1.getPlayerById(.player_1).hit_lines.asConstSlice());
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_1.getPlayerById(.player_2).hit_lines.asConstSlice());

    const frame_2 = capturer.captureFrame(&.{
        .player_1 = .{
            .hit_lines = .{
                point(.{ 1, 2, 3 }),
                point(.{ 4, 5, 6 }),
                point(.{ 7, 8, 9 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
            },
            .phase_flags = .{ .is_active = true },
        },
        .player_2 = .{
            .hit_lines = .{
                point(.{ 10, 11, 12 }),
                point(.{ 13, 14, 15 }),
                point(.{ 16, 17, 18 }),
                point(.{ 19, 20, 21 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
            },
            .phase_flags = .{ .is_active = true },
        },
    });
    try testing.expectEqualSlices(model.HitLine, &.{
        line(.{ 4, 5, 6 }, .{ 7, 8, 9 }),
    }, frame_2.getPlayerById(.player_1).hit_lines.asConstSlice());
    try testing.expectEqualSlices(model.HitLine, &.{
        line(.{ 16, 17, 18 }, .{ 19, 20, 21 }),
        line(.{ 10, 11, 12 }, .{ 13, 14, 15 }),
    }, frame_2.getPlayerById(.player_2).hit_lines.asConstSlice());

    const frame_3 = capturer.captureFrame(&.{
        .player_1 = .{
            .hit_lines = .{
                point(.{ 36, 35, 34 }),
                point(.{ 33, 32, 31 }),
                point(.{ 30, 29, 28 }),
                point(.{ 27, 26, 25 }),
                point(.{ 24, 23, 22 }),
                point(.{ 21, 20, 19 }),
            },
            .phase_flags = .{ .is_active = false },
        },
        .player_2 = .{
            .hit_lines = .{
                point(.{ 18, 17, 16 }),
                point(.{ 15, 14, 13 }),
                point(.{ 12, 11, 10 }),
                point(.{ 9, 8, 7 }),
                point(.{ 6, 5, 4 }),
                point(.{ 3, 2, 1 }),
            },
            .phase_flags = .{ .is_active = true },
        },
    });
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_3.getPlayerById(.player_1).hit_lines.asConstSlice());
    try testing.expectEqualSlices(model.HitLine, &.{
        line(.{ 6, 5, 4 }, .{ 3, 2, 1 }),
        line(.{ 12, 11, 10 }, .{ 9, 8, 7 }),
        line(.{ 18, 17, 16 }, .{ 15, 14, 13 }),
    }, frame_3.getPlayerById(.player_2).hit_lines.asConstSlice());

    const frame_4 = capturer.captureFrame(&.{
        .player_1 = .{
            .hit_lines = .{
                point(.{ 1, 2, 3 }),
                point(.{ 4, 5, 6 }),
                point(.{ 7, 8, 9 }),
                point(.{ 10, 11, 12 }),
                point(.{ 13, 14, 15 }),
                point(.{ 16, 17, 18 }),
            },
            .phase_flags = null,
        },
        .player_2 = .{
            .hit_lines = null,
            .phase_flags = .{ .is_active = true },
        },
    });
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_4.getPlayerById(.player_1).hit_lines.asConstSlice());
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_4.getPlayerById(.player_2).hit_lines.asConstSlice());
}

test "should capture hit lines correctly in T8" {
    const hitLine = struct {
        fn call(points: [3][3]f32, ignore: bool) @typeInfo(game.HitLines(.t8)).array.child {
            return .fromConverted(.{
                .points = .{
                    .{ .position = .fromArray(points[0]), ._padding = 0 },
                    .{ .position = .fromArray(points[1]), ._padding = 0 },
                    .{ .position = .fromArray(points[2]), ._padding = 0 },
                },
                ._padding_1 = [1]u8{0} ** 8,
                .ignore = .fromBool(ignore),
                ._padding_2 = [1]u8{0} ** 7,
            });
        }
    }.call;
    const line = struct {
        fn call(point_1: [3]f32, point_2: [3]f32) model.HitLine {
            return .{
                .line = .{
                    .point_1 = .fromArray(point_1),
                    .point_2 = .fromArray(point_2),
                },
            };
        }
    }.call;

    var capturer = Capturer(.t8){};

    const frame_1 = capturer.captureFrame(&.{
        .player_1 = .{ .hit_lines = .{
            hitLine(.{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } }, true),
            hitLine(.{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } }, true),
            hitLine(.{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } }, true),
            hitLine(.{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } }, true),
        } },
        .player_2 = .{ .hit_lines = .{
            hitLine(.{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } }, true),
            hitLine(.{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } }, true),
            hitLine(.{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } }, true),
            hitLine(.{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } }, true),
        } },
    });
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_1.getPlayerById(.player_1).hit_lines.asConstSlice());
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_1.getPlayerById(.player_2).hit_lines.asConstSlice());

    const frame_2 = capturer.captureFrame(&.{
        .player_1 = .{ .hit_lines = .{
            hitLine(.{ .{ 1, 2, 3 }, .{ 4, 5, 6 }, .{ 7, 8, 9 } }, true),
            hitLine(.{ .{ 10, 11, 12 }, .{ 13, 14, 15 }, .{ 16, 17, 18 } }, false),
            hitLine(.{ .{ 19, 20, 21 }, .{ 22, 23, 24 }, .{ 25, 26, 27 } }, true),
            hitLine(.{ .{ 28, 29, 30 }, .{ 31, 32, 33 }, .{ 34, 35, 36 } }, false),
        } },
        .player_2 = .{ .hit_lines = .{
            hitLine(.{ .{ 37, 38, 39 }, .{ 40, 41, 42 }, .{ 43, 44, 45 } }, false),
            hitLine(.{ .{ 46, 47, 48 }, .{ 49, 50, 51 }, .{ 52, 53, 54 } }, true),
            hitLine(.{ .{ 55, 56, 57 }, .{ 58, 59, 60 }, .{ 61, 62, 63 } }, false),
            hitLine(.{ .{ 64, 65, 66 }, .{ 67, 68, 69 }, .{ 70, 71, 72 } }, true),
        } },
    });
    try testing.expectEqualSlices(model.HitLine, &.{
        line(.{ 10, 11, 12 }, .{ 13, 14, 15 }),
        line(.{ 13, 14, 15 }, .{ 16, 17, 18 }),
        line(.{ 28, 29, 30 }, .{ 31, 32, 33 }),
        line(.{ 31, 32, 33 }, .{ 34, 35, 36 }),
    }, frame_2.getPlayerById(.player_1).hit_lines.asConstSlice());
    try testing.expectEqualSlices(model.HitLine, &.{
        line(.{ 37, 38, 39 }, .{ 40, 41, 42 }),
        line(.{ 40, 41, 42 }, .{ 43, 44, 45 }),
        line(.{ 55, 56, 57 }, .{ 58, 59, 60 }),
        line(.{ 58, 59, 60 }, .{ 61, 62, 63 }),
    }, frame_2.getPlayerById(.player_2).hit_lines.asConstSlice());

    const frame_3 = capturer.captureFrame(&.{
        .player_1 = .{ .hit_lines = .{
            hitLine(.{ .{ 1, 2, 3 }, .{ 4, 5, 6 }, .{ 7, 8, 9 } }, false),
            hitLine(.{ .{ 1000, 11, 12 }, .{ 13, 14, 15 }, .{ 16, 17, 18 } }, true),
            hitLine(.{ .{ 19, 20, 21 }, .{ 22, 1000, 24 }, .{ 25, 26, 27 } }, true),
            hitLine(.{ .{ 28, 29, 30 }, .{ 31, 32, 33 }, .{ 34, 35, 1000 } }, true),
        } },
        .player_2 = .{ .hit_lines = .{
            hitLine(.{ .{ 1000, 38, 39 }, .{ 40, 41, 42 }, .{ 43, 44, 45 } }, false),
            hitLine(.{ .{ 46, 1000, 48 }, .{ 49, 50, 51 }, .{ 52, 53, 54 } }, false),
            hitLine(.{ .{ 55, 56, 57 }, .{ 1000, 59, 60 }, .{ 61, 62, 63 } }, false),
            hitLine(.{ .{ 64, 65, 66 }, .{ 67, 68, 69 }, .{ 70, 71, 1000 } }, false),
        } },
    });
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_3.getPlayerById(.player_1).hit_lines.asConstSlice());
    try testing.expectEqualSlices(model.HitLine, &.{
        line(.{ 1000, 38, 39 }, .{ 40, 41, 42 }),
        line(.{ 40, 41, 42 }, .{ 43, 44, 45 }),
        line(.{ 46, 1000, 48 }, .{ 49, 50, 51 }),
        line(.{ 49, 50, 51 }, .{ 52, 53, 54 }),
        line(.{ 55, 56, 57 }, .{ 1000, 59, 60 }),
        line(.{ 1000, 59, 60 }, .{ 61, 62, 63 }),
        line(.{ 64, 65, 66 }, .{ 67, 68, 69 }),
        line(.{ 67, 68, 69 }, .{ 70, 71, 1000 }),
    }, frame_3.getPlayerById(.player_2).hit_lines.asConstSlice());

    const frame_4 = capturer.captureFrame(&.{
        .player_1 = .{ .hit_lines = null },
        .player_2 = .{ .hit_lines = null },
    });
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_4.getPlayerById(.player_1).hit_lines.asConstSlice());
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_4.getPlayerById(.player_2).hit_lines.asConstSlice());
}
