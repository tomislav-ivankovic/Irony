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
        pub const PlayerState = struct {
            rage_state: RageState = .{},
            previous_hit_lines: ?game.HitLines(game_id) = null,
        };
        const RageState = struct {
            previous_frames_since_round_start: u32 = 0,
            was_in_rage_this_round: bool = false,
        };
        const GamePlayer = game.Player(game_id);
        const WallRectangle = struct {
            rectangle: sdk.math.Rectangle,
            properties: model.WallProperties,
        };

        pub fn captureFrame(self: *Self, game_memory: *const game.Memory(game_id)) model.Frame {
            const game_version = game_memory.game_version.toConstPointer();
            const player_1 = game_memory.player_1.toConstPointer();
            const player_2 = game_memory.player_2.toConstPointer();
            const main_player_info = game_memory.main_player_info.toConstPointer();
            const secondary_player_info = game_memory.secondary_player_info.toConstPointer();
            const match = game_memory.match.toConstPointer();
            const ruleset = game_memory.ruleset.toConstPointer();
            const cancel_requirements = game_memory.cancel_requirements.toConstPointer();
            const replay_mode = game_memory.replay_mode.toConstPointer();
            const main_player_id = captureMainPlayerId(main_player_info, secondary_player_info);
            const left_player_id = captureLeftPlayerId(player_1, player_2, main_player_id);
            const floor_z = captureFloorZ(player_1, player_2);
            const player_1_info = switch (main_player_id) {
                .player_1 => main_player_info,
                .player_2 => secondary_player_info,
            };
            const player_2_info = switch (main_player_id) {
                .player_1 => secondary_player_info,
                .player_2 => main_player_info,
            };
            const match_player_1 = if (match) |m| &m.players[0] else null;
            const match_player_2 = if (match) |m| &m.players[1] else null;
            const players = [2]model.Player{
                capturePlayer(&self.player_1_state, player_1, player_1_info, match_player_1, cancel_requirements),
                capturePlayer(&self.player_2_state, player_2, player_2_info, match_player_2, cancel_requirements),
            };
            const camera_manager = game_memory.camera_manager.toConstPointer();
            const camera = captureCamera(camera_manager);
            const floor_number = captureFloorNumber(player_1, player_2);
            const set_number = captureStageSetNumber(player_1, player_2);
            const walls = captureWalls(
                floor_number,
                set_number,
                game_memory.walls.asSlice(),
                game_memory.player_starts.asSlice(),
                game_memory.unreal_classes.photo_mode_wall,
            );
            const floor_gimmicks = captureFloorGimmicks(
                floor_number,
                set_number,
                game_memory.floors.asSlice(),
                walls.asSlice(),
            );
            return .{
                .irony_version = .current,
                .game = switch (game_id) {
                    .t7 => .t7,
                    .t8 => .t8,
                },
                .game_version = captureGameVersion(game_version),
                .source = captureSource(match, replay_mode, &game_memory.functions),
                .match_phase = captureMatchPhase(match),
                .rounds_needed_to_win = if (ruleset) |r| r.rounds_needed_to_win else null,
                .frames_since_round_start = captureFramesSinceRoundStart(player_1, player_2),
                .frames_left_in_round = captureFramesLeftInRound(match),
                .floor_z = floor_z,
                .players = players,
                .camera = camera,
                .main_player_id = main_player_id,
                .left_player_id = left_player_id,
                .walls = walls,
                .floor_gimmicks = floor_gimmicks,
            };
        }

        fn captureGameVersion(version_maybe: ?*const game.Version(game_id)) model.GameVersion {
            const buffer = version_maybe orelse return .empty;
            const string = std.mem.sliceTo(buffer, 0);
            const trimmed_front = block: {
                var temp = string;
                while (temp.len > 0 and temp[0] == ' ') {
                    temp = temp[1..];
                }
                break :block temp;
            };
            const fully_trimmed = std.mem.sliceTo(trimmed_front, ' ');
            return .fromSliceTrimmed(fully_trimmed);
        }

        pub fn captureSource(
            match_maybe: ?*const game.Match(game_id),
            replay_mode_maybe: ?*const game.ReplayMode,
            functions: *const game.Memory(game_id).Functions,
        ) ?model.Source {
            if (match_maybe) |match| {
                switch (match.phase) {
                    .practice_mode, .move_showcase => return .practice,
                    else => {},
                }
            }
            switch (game_id) {
                .t7 => {
                    if (replay_mode_maybe) |replay_mode| {
                        switch (replay_mode.*) {
                            .loading => return .replay_loading,
                            .playback => return .replay_playback,
                            else => {},
                        }
                    }
                },
                .t8 => {
                    const isReplay = functions.isReplay orelse return null;
                    var is_replay: bool = undefined;
                    var is_precalculated: bool = undefined;
                    isReplay(&is_replay, &is_precalculated);
                    if (is_replay) {
                        return switch (is_precalculated) {
                            true => .replay_playback,
                            false => .replay_loading,
                        };
                    }
                },
            }
            return switch (match_maybe != null) {
                true => .live_game,
                false => null,
            };
        }

        fn captureMatchPhase(match_maybe: ?*const game.Match(game_id)) ?model.MatchPhase {
            const match = match_maybe orelse return null;
            const match_phase: game.MatchPhase = match.phase;
            return switch (match_phase) {
                .intro_1, .intro_2 => .intro,
                .win_loose_outro, .draw_outro => .outro,
                .round_start => .round_start,
                .round_end => .round_end,
                .mid_round => .mid_round,
                .stage_transformation => .in_between_rounds,
                else => .not_in_a_match,
            };
        }

        fn captureFramesSinceRoundStart(player_1: ?*const GamePlayer, player_2: ?*const GamePlayer) ?u32 {
            if (player_1) |player| {
                return player.frames_since_round_start;
            }
            if (player_2) |player| {
                return player.frames_since_round_start;
            }
            return null;
        }

        fn captureFramesLeftInRound(match_maybe: ?*const game.Match(game_id)) ?u32 {
            const match = match_maybe orelse return null;
            return switch (match.phase) {
                .practice_mode, .move_showcase => null,
                else => match.frames_left_in_round,
            };
        }

        fn captureFloorZ(player_1: ?*const GamePlayer, player_2: ?*const GamePlayer) ?f32 {
            if (player_1) |p1| {
                const z1 = p1.floor_z.convert();
                if (player_2) |p2| {
                    const z2 = p2.floor_z.convert();
                    return 0.5 * (z1 + z2);
                } else {
                    return z1;
                }
            } else if (player_2) |p2| {
                return p2.floor_z.convert();
            } else {
                return null;
            }
        }

        fn captureFloorNumber(player_1: ?*const GamePlayer, player_2: ?*const GamePlayer) ?u32 {
            if (player_1) |p1| {
                return p1.floor_number;
            } else if (player_2) |p2| {
                return p2.floor_number;
            } else {
                return null;
            }
        }

        fn captureStageSetNumber(player_1: ?*const GamePlayer, player_2: ?*const GamePlayer) ?u32 {
            if (game_id != .t8) {
                return null;
            } else if (player_1) |p1| {
                return p1.stage_set_number;
            } else if (player_2) |p2| {
                return p2.stage_set_number;
            } else {
                return null;
            }
        }

        fn captureCamera(camera_manager: ?*const game.CameraManager(game_id)) ?model.Camera {
            const camera = if (camera_manager) |c| c else return null;
            const horizontal_fov = camera.horizontal_fov.convert();
            const position = camera.position.convert();
            const rotation = camera.rotation.convert();
            return .{
                .position = position,
                .pitch = rotation.x(),
                .yaw = rotation.y(),
                .roll = rotation.z(),
                .horizontal_fov = horizontal_fov,
            };
        }

        fn captureMainPlayerId(
            main_info: ?*const game.PlayerInfo(game_id),
            secondary_info: ?*const game.PlayerInfo(game_id),
        ) model.PlayerId {
            if (main_info) |main| {
                switch (main.player_id) {
                    .player_1 => return .player_1,
                    .player_2 => return .player_2,
                    else => {},
                }
            }
            if (secondary_info) |secondary| {
                switch (secondary.player_id) {
                    .player_1 => return .player_2,
                    .player_2 => return .player_1,
                    else => {},
                }
            }
            return .player_1;
        }

        fn captureLeftPlayerId(
            player_1: ?*const GamePlayer,
            player_2: ?*const GamePlayer,
            main_player_id: model.PlayerId,
        ) model.PlayerId {
            const main_player = if (main_player_id == .player_1) player_1 else player_2;
            if (main_player) |mp| {
                return switch (mp.input_side) {
                    .left => main_player_id,
                    .right => main_player_id.getOther(),
                    _ => main_player_id,
                };
            } else {
                return .player_1;
            }
        }

        fn capturePlayer(
            state: *PlayerState,
            player: ?*const GamePlayer,
            info: ?*const game.PlayerInfo(game_id),
            match: ?*const game.MatchPlayer(game_id),
            cancel_requirements: ?*const game.CancelRequirements,
        ) model.Player {
            updateRageState(state, player);
            const captured_player = model.Player{
                .name = capturePlayerName(info),
                .rounds_won = if (match) |m| m.rounds_won else null,
                .character_id = if (player) |p| p.character_id else null,
                .animation_id = if (player) |p| p.animation_id else null,
                .animation_frame = if (player) |p| p.animation_frame else null,
                .animation_total_frames = if (player) |p| p.animation_total_frames else null,
                .attack_type = captureAttackType(player),
                .hit_outcome = captureHitOutcome(player),
                .combo_hits = if (match) |m| m.combo_hits else null,
                .combo_damage = if (match) |m| m.combo_damage else null,
                .posture = capturePosture(player),
                .blocking = captureBlocking(player),
                .crushing = captureCrushing(player),
                .can_interact = captureCanInteract(player),
                .can_move = if (player) |p| p.can_move.toBool() else null,
                .throw_escape = captureThrowEscape(player, cancel_requirements),
                .input = captureInput(player),
                .health = if (player) |p| p.health.convert().value else null,
                .health_recover_limit = if (player) |p| switch (game_id) {
                    .t7 => p.health.convert().value,
                    .t8 => p.health_recover_limit.convert().value,
                } else null,
                .max_health = if (player) |p| switch (game_id) {
                    .t7 => p.max_health.convert(),
                    .t8 => p.max_health.convert().value,
                } else null,
                .rage = captureRage(state, player),
                .heat = captureHeat(player),
                .rotation = if (player) |p| p.rotation.convert() else null,
                .hurt_cylinders = captureHurtCylinders(player),
                .collision_spheres = captureCollisionSpheres(player),
                .hit_lines = captureHitLines(state, player),
            };
            updatePreviousHitLines(state, player);
            return captured_player;
        }

        fn updateRageState(state: *PlayerState, player_maybe: ?*const GamePlayer) void {
            const player = player_maybe orelse return;
            const frames_since_round_start: u32 = player.frames_since_round_start;
            const previous_frames_since_round_start: *u32 = &state.rage_state.previous_frames_since_round_start;
            defer previous_frames_since_round_start.* = frames_since_round_start;
            if (frames_since_round_start < previous_frames_since_round_start.*) {
                state.rage_state.was_in_rage_this_round = false;
            }
            if (player.in_rage.toBool() orelse false) {
                state.rage_state.was_in_rage_this_round = true;
            }
        }

        fn updatePreviousHitLines(state: *PlayerState, player_maybe: ?*const GamePlayer) void {
            state.previous_hit_lines = if (player_maybe) |player| player.hit_lines else null;
        }

        fn capturePlayerName(info_maybe: ?*const game.PlayerInfo(game_id)) model.PlayerName {
            const info = info_maybe orelse return .empty;
            const slice = std.mem.sliceTo(&info.name, 0);
            return model.PlayerName.fromSliceTrimmed(slice);
        }

        fn captureAttackType(player_maybe: ?*const GamePlayer) ?model.AttackType {
            const player = player_maybe orelse return null;
            return switch (player.attack_type) {
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

        fn captureHitOutcome(player_maybe: ?*const GamePlayer) ?model.HitOutcome {
            const player = player_maybe orelse return null;
            return switch (player.hit_outcome) {
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

        fn capturePosture(player_maybe: ?*const GamePlayer) ?model.Posture {
            const player = player_maybe orelse return null;
            const animation = player.animation.toConstPointer() orelse return null;
            const animation_frame: u32 = player.animation_frame;
            const state_flags: game.StateFlags = player.state_flags;
            const simple_state: game.SimpleState = player.simple_state;
            const airborne_start: u32 = animation.airborne_start;
            const airborne_end: u32 = animation.airborne_end;
            const is_airborne = (animation_frame >= airborne_start and animation_frame <= airborne_end) or
                (state_flags.force_airborne_no_low_crushing and simple_state != .invincible);
            if (state_flags.crouching) {
                return .crouching;
            } else if (state_flags.downed) {
                if (state_flags.face_down) {
                    return .downed_face_down;
                } else {
                    return .downed_face_up;
                }
            } else if (is_airborne) {
                return .airborne;
            } else {
                return .standing;
            }
        }

        fn captureBlocking(player_maybe: ?*const GamePlayer) ?model.Blocking {
            const player = player_maybe orelse return null;
            const state_flags: game.StateFlags = player.state_flags;
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

        fn captureCrushing(player_maybe: ?*const GamePlayer) ?model.Crushing {
            const player = player_maybe orelse return null;
            const posture = capturePosture(player) orelse return null;
            const animation = player.animation.toConstPointer() orelse return null;
            const state_flags: game.StateFlags = player.state_flags;
            const simple_state: game.SimpleState = player.simple_state;
            const power_crushing: bool = player.power_crushing.toBool() orelse return null;
            const animation_frame: u32 = player.animation_frame;
            const airborne_start: u32 = animation.airborne_start;
            const airborne_end: u32 = animation.airborne_end;
            return .{
                .high_crushing = posture == .crouching or posture == .downed_face_down or posture == .downed_face_up,
                .low_crushing = posture == .airborne and
                    state_flags.low_crushing_move and
                    !state_flags.force_airborne_no_low_crushing and
                    animation_frame >= airborne_start and
                    animation_frame <= airborne_end -| 3,
                .anti_air_only_crushing = posture != .airborne,
                .power_crushing = power_crushing,
                .invincibility = simple_state == .invincible,
            };
        }

        fn captureCanInteract(player_maybe: ?*const GamePlayer) ?bool {
            const player = player_maybe orelse return null;
            if (player.simple_state == .juggled) {
                return false;
            }
            return player.cancel_flags.can_interact;
        }

        fn captureThrowEscape(
            player_maybe: ?*const GamePlayer,
            cancel_requirements_maybe: ?*const game.CancelRequirements,
        ) ?model.ThrowEscape {
            const player = player_maybe orelse return null;
            const cancel_requirements = if (cancel_requirements_maybe) |c| c.* else return null;
            switch (player.correct_throw_escape_input) {
                .none => return null,
                .press_1, .press_2, .press_1_plus_2, .hold_1, .hold_2, .hold_1_plus_2 => {},
                else => return null,
            }
            const is_inside_escape_window = cancel_requirements.throw_escape_press_1 or
                cancel_requirements.throw_escape_press_2 or
                cancel_requirements.throw_escape_press_1_plus_2 or
                cancel_requirements.throw_escape_hold;
            return .{
                .phase = switch (player.throw_escape_flags.escape_success) {
                    true => .escape_success,
                    false => switch (is_inside_escape_window) {
                        true => .in_escape_window,
                        false => .escape_fail,
                    },
                },
                .input_mode = switch (player.correct_throw_escape_input) {
                    .press_1, .press_2, .press_1_plus_2 => .press,
                    .hold_1, .hold_2, .hold_1_plus_2 => .hold,
                    else => unreachable,
                },
                .correct_inputs = switch (is_inside_escape_window) {
                    true => switch (player.correct_throw_escape_input) {
                        .press_1, .press_2, .press_1_plus_2 => .{
                            .one = cancel_requirements.throw_escape_press_1,
                            .two = cancel_requirements.throw_escape_press_2,
                            .one_plus_two = cancel_requirements.throw_escape_press_1_plus_2,
                        },
                        .hold_1 => .{ .one = true },
                        .hold_2 => .{ .two = true },
                        .hold_1_plus_2 => .{ .one_plus_two = true },
                        else => unreachable,
                    },
                    false => .{},
                },
            };
        }

        fn captureInput(player_maybe: ?*const GamePlayer) ?model.Input {
            const player = player_maybe orelse return null;
            const input_side: game.PlayerSide = player.input_side;
            const input: game.Input(game_id) = player.input;
            const directional_input: game.DirectionalInput.Direction = player.directional_input.down;
            const attack_input: game.AttackInput(game_id).Buttons = player.attack_input.down;
            const input_1 = model.Input{
                .forward = switch (input_side) {
                    .left => input.right,
                    .right => input.left,
                    _ => return null,
                },
                .back = switch (input_side) {
                    .left => input.left,
                    .right => input.right,
                    _ => return null,
                },
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
            const input_2 = model.Input{
                .forward = switch (directional_input) {
                    .down_forward, .forward, .up_forward => true,
                    else => false,
                },
                .back = switch (directional_input) {
                    .down_back, .back, .up_back => true,
                    else => false,
                },
                .up = switch (directional_input) {
                    .up_back, .up, .up_forward => true,
                    else => false,
                },
                .down = switch (directional_input) {
                    .down_back, .down, .down_forward => true,
                    else => false,
                },
                .left = switch (input_side) {
                    .left => switch (directional_input) {
                        .down_back, .back, .up_back => true,
                        else => false,
                    },
                    .right => switch (directional_input) {
                        .down_forward, .forward, .up_forward => true,
                        else => false,
                    },
                    _ => return null,
                },
                .right = switch (input_side) {
                    .right => switch (directional_input) {
                        .down_back, .back, .up_back => true,
                        else => false,
                    },
                    .left => switch (directional_input) {
                        .down_forward, .forward, .up_forward => true,
                        else => false,
                    },
                    _ => return null,
                },
                .button_1 = attack_input.button_1,
                .button_2 = attack_input.button_2,
                .button_3 = attack_input.button_3,
                .button_4 = attack_input.button_4,
                .special_style = switch (game_id) {
                    .t7 => false,
                    .t8 => attack_input.special_style,
                },
                .rage = attack_input.rage,
                .heat = switch (game_id) {
                    .t7 => false,
                    .t8 => attack_input.heat,
                },
            };
            return .{
                .forward = input_1.forward or input_2.forward,
                .back = input_1.back or input_2.back,
                .up = input_1.up or input_2.up,
                .down = input_1.down or input_2.down,
                .left = input_1.left or input_2.left,
                .right = input_1.right or input_2.right,
                .button_1 = input_1.button_1 or input_2.button_1,
                .button_2 = input_1.button_2 or input_2.button_2,
                .button_3 = input_1.button_3 or input_2.button_3,
                .button_4 = input_1.button_4 or input_2.button_4,
                .special_style = input_1.special_style or input_2.special_style,
                .rage = input_1.rage or input_2.rage,
                .heat = input_1.heat or input_2.heat,
            };
        }

        fn captureRage(state: *PlayerState, player_maybe: ?*const GamePlayer) ?model.Rage {
            const player = player_maybe orelse return null;
            const in_rage = player.in_rage.toBool() orelse return null;
            return switch (in_rage) {
                true => .activated,
                false => switch (state.rage_state.was_in_rage_this_round) {
                    true => .used_up,
                    false => .available,
                },
            };
        }

        fn captureHeat(player_maybe: ?*const GamePlayer) ?model.Heat {
            if (game_id != .t8) {
                return .used_up;
            }
            const player = player_maybe orelse return null;
            const in_heat = player.in_heat.toBool() orelse return null;
            const used_heat = player.used_heat.toBool() orelse return null;
            const heat_gauge = player.heat_gauge;
            if (in_heat) {
                return .{ .activated = .{ .gauge = heat_gauge.convert() } };
            } else if (used_heat) {
                return .used_up;
            } else {
                return .available;
            }
        }

        fn captureHurtCylinders(player_maybe: ?*const GamePlayer) ?model.HurtCylinders {
            const player = player_maybe orelse return null;
            const cylinders: *const game.HurtCylinders(game_id) = &player.hurt_cylinders;
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

        fn captureCollisionSpheres(player_maybe: ?*const GamePlayer) ?model.CollisionSpheres {
            const player = player_maybe orelse return null;
            const spheres: *const game.CollisionSpheres = &player.collision_spheres;
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

        fn captureHitLines(state: *const PlayerState, player_maybe: ?*const GamePlayer) model.HitLines {
            const player = player_maybe orelse return .empty;
            const animation = player.animation.toConstPointer() orelse return .empty;
            const is_active_frame = player.animation_frame >= animation.active_start and
                player.animation_frame <= animation.active_end;
            if (!is_active_frame) {
                return .empty;
            }
            return switch (game_id) {
                .t7 => captureT7HitLines(state, player),
                .t8 => captureT8HitLines(state, player),
            };
        }

        fn captureT7HitLines(state: *const PlayerState, player: *const GamePlayer) model.HitLines {
            const previous_lines: *const game.HitLines(.t7) = if (state.previous_hit_lines) |*l| l else return .empty;
            const current_lines: *const game.HitLines(.t7) = &player.hit_lines;
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
            var result = model.HitLines.empty;
            var index: usize = changed_points_len -% 2;
            while (index < changed_points_len) {
                result.append(.{ .line = .{
                    .point_1 = changed_points_buffer[index].position,
                    .point_2 = changed_points_buffer[index + 1].position,
                } }) catch break;
                index -%= 2;
            }
            return result;
        }

        fn captureT8HitLines(state: *const PlayerState, player: *const GamePlayer) model.HitLines {
            const previous_lines: *const game.HitLines(.t8) = if (state.previous_hit_lines) |*l| l else return .empty;
            const current_lines: *const game.HitLines(.t8) = &player.hit_lines;
            var result = model.HitLines.empty;
            for (previous_lines, current_lines) |*raw_previous_line, *raw_current_line| {
                const previous_line = raw_previous_line.convert();
                const current_line = raw_current_line.convert();
                if (std.meta.eql(previous_line.points, current_line.points)) {
                    continue;
                }
                result.append(.{ .line = .{
                    .point_1 = current_line.points[0].position,
                    .point_2 = current_line.points[1].position,
                } }) catch break;
                result.append(.{ .line = .{
                    .point_1 = current_line.points[1].position,
                    .point_2 = current_line.points[2].position,
                } }) catch break;
            }
            return result;
        }

        fn captureWalls(
            floor_number: ?u32,
            stage_set_number: ?u32,
            wall_pointers: []const sdk.memory.Pointer(game.Wall(game_id)),
            start_pointers: []const sdk.memory.Pointer(game.PlayerStart(game_id)),
            photo_mode_wall_class: ?*const game.UnrealClass,
        ) model.Walls {
            const floor_numb = floor_number orelse return .empty;
            const midpoint = captureFloorMidpoint(start_pointers, floor_numb) orelse return .empty;
            var rectangles_buffer: [game.Memory(game_id).max_walls]WallRectangle = undefined;
            const rectangles = captureWallRectangles(
                &rectangles_buffer,
                wall_pointers,
                floor_numb,
                stage_set_number,
                photo_mode_wall_class,
            );
            return computeWallsPolygon(rectangles, midpoint);
        }

        fn captureFloorMidpoint(
            start_pointers: []const sdk.memory.Pointer(game.PlayerStart(game_id)),
            floor_number: u32,
        ) ?sdk.math.Vec2 {
            var min_position: ?sdk.math.Vec2 = null;
            var min_breaks: u8 = std.math.maxInt(u8);
            for (start_pointers) |start_pointer| {
                const start = start_pointer.toConstPointer() orelse continue;
                if (start.floor_number != floor_number or !start.type.isGameStart()) {
                    continue;
                }
                const breaks = switch (game_id) {
                    .t7 => 0,
                    .t8 => @popCount(start.stage_broken_history),
                };
                if (min_breaks < breaks) {
                    continue;
                }
                const root = start.actor.root_component.toConstPointer() orelse continue;
                min_position = root.relative_position.convert().swizzle("xy");
                min_breaks = breaks;
            }
            return min_position;
        }

        fn captureWallRectangles(
            buffer: []WallRectangle,
            wall_pointers: []const sdk.memory.Pointer(game.Wall(game_id)),
            floor_number: u32,
            set_number: ?u32,
            photo_mode_wall_class: ?*const game.UnrealClass,
        ) []WallRectangle {
            const wall_mesh_half_size = switch (game_id) {
                .t7 => 128,
                .t8 => 50,
            };
            var len: usize = 0;
            for (wall_pointers) |wall_pointer| {
                const wall = wall_pointer.toConstPointer() orelse continue;
                if (wall.floor_number != floor_number) {
                    continue;
                }
                if (game_id == .t8) {
                    if (wall.actor.hidden_polaris.value or
                        wall.state == .init or
                        wall.set_number != set_number or
                        wall.actor.class == photo_mode_wall_class)
                    {
                        continue;
                    }
                }
                const root = wall.actor.root_component.toConstPointer() orelse continue;
                if (len >= buffer.len) {
                    break;
                }
                buffer[len] = .{
                    .rectangle = .{
                        .center = root.relative_position.convert().swizzle("xy"),
                        .half_size = root.relative_scale.convert().swizzle("xy").scale(wall_mesh_half_size),
                        .rotation = root.relative_rotation.convert().y(),
                    },
                    .properties = captureWallProperties(wall),
                };
                len += 1;
            }
            return buffer[0..len];
        }

        fn captureWallProperties(wall: *const game.Wall(game_id)) model.WallProperties {
            const attribute: game.WallAttribute = wall.wall_attribute;
            const flags = model.WallFlags{
                .hard = attribute.hard,
                .damaged = switch (game_id) {
                    .t7 => !wall.actor.collision_enabled.value,
                    .t8 => !wall.actor.collision_enabled.value or wall.destruction_level > 0,
                },
                .gimmick_used_up = switch (game_id) {
                    .t7 => !wall.actor.collision_enabled.value,
                    .t8 => !wall.actor.collision_enabled.value or switch (attribute.hard) {
                        false => wall.destruction_level > 0,
                        true => wall.destruction_level > 1,
                    },
                },
                .broken = !wall.actor.collision_enabled.value,
            };
            if (attribute.balcony_break) {
                return .{ .gimmick = .balcony_break, .flags = flags };
            } else if (attribute.wall_bound) {
                return .{ .gimmick = .wall_bound, .flags = flags };
            } else if (attribute.wall_blast) {
                return .{ .gimmick = .wall_blast, .flags = flags };
            } else if (attribute.wall_break) {
                return .{ .gimmick = .wall_break, .flags = flags };
            } else {
                return .{ .gimmick = .none, .flags = flags };
            }
        }

        fn computeWallsPolygon(wall_rectangles: []const WallRectangle, midpoint: sdk.math.Vec2) model.Walls {
            const normal_to_direction = comptime sdk.math.Mat2.fromZRotation(-0.5 * std.math.pi);

            const Turtle = struct {
                position: sdk.math.Vec2,
                direction: sdk.math.Vec2,
                wall_properties: model.WallProperties,
                rectangle_index: usize,
            };
            var turtle: Turtle = block: {
                const ray = sdk.math.Ray2{ .origin = midpoint, .direction = .plus_x };
                var min: ?struct {
                    hit: sdk.math.RaycastRectangleResult.HitPoint,
                    wall_properties: model.WallProperties,
                    rectangle_index: usize,
                } = null;
                for (wall_rectangles, 0..) |*wall, index| {
                    if (wall.properties.gimmick == .wall_break) {
                        continue;
                    }
                    switch (sdk.math.raycastRectangle(ray, wall.rectangle)) {
                        .hit => |hit| {
                            if (hit.entrance.t <= 0) {
                                continue;
                            }
                            if (min == null or hit.entrance.t < min.?.hit.t) {
                                min = .{
                                    .hit = hit.entrance,
                                    .wall_properties = wall.properties,
                                    .rectangle_index = index,
                                };
                            }
                        },
                        .side_scrape, .miss => {},
                    }
                }
                if (min) |result| {
                    break :block .{
                        .position = result.hit.position,
                        .direction = result.hit.normal.multiply(normal_to_direction),
                        .wall_properties = result.wall_properties,
                        .rectangle_index = result.rectangle_index,
                    };
                } else {
                    return .empty;
                }
            };

            const BreakableWall = struct {
                edge_1: ?sdk.math.Vec2 = null,
                edge_2_index: ?u8 = null,
            };
            var breakable_walls = [1]BreakableWall{.{}} ** game.Memory(game_id).max_walls;
            var result = model.Walls.empty;
            var hit_negative_x = false;
            var hit_negative_y = false;
            while (true) {
                const HitType = enum {
                    normal_hit,
                    side_scrape_new_wall_entrance,
                    side_scrape_current_wall_exit,
                    breakable_wall_entrance,
                    breakable_wall_exit,
                };
                const Hit = struct {
                    type: HitType,
                    position: sdk.math.Vec2,
                    normal: sdk.math.Vec2,
                    t: f32,
                    wall_properties: model.WallProperties,
                    rectangle_index: usize,
                };

                const ray = sdk.math.Ray2{ .origin = turtle.position, .direction = turtle.direction };

                var min_hit: ?Hit = null;
                for (wall_rectangles, 0..) |*wall, index| {
                    const hit_point, const hit_type = switch (sdk.math.raycastRectangle(ray, wall.rectangle)) {
                        .hit => |hit| switch (wall.properties.gimmick) {
                            .wall_break => block: {
                                const entrance_distance = hit.entrance.position.distanceSquaredTo(midpoint);
                                const exit_distance = hit.exit.position.distanceSquaredTo(midpoint);
                                if (entrance_distance < exit_distance) {
                                    break :block .{ hit.entrance, HitType.breakable_wall_entrance };
                                } else {
                                    break :block .{ hit.exit, HitType.breakable_wall_exit };
                                }
                            },
                            else => .{ hit.entrance, HitType.normal_hit },
                        },
                        .side_scrape => |scrape| block: {
                            if (wall.properties.gimmick == .wall_break) {
                                continue;
                            }
                            if (index == turtle.rectangle_index) {
                                var exit = scrape.exit;
                                exit.normal = scrape.scraping_side_normal;
                                break :block .{ exit, HitType.side_scrape_current_wall_exit };
                            } else {
                                break :block .{ scrape.entrance, HitType.side_scrape_new_wall_entrance };
                            }
                        },
                        .miss => continue,
                    };
                    if (hit_point.t <= 0) {
                        continue;
                    }
                    if (min_hit == null or hit_point.t < min_hit.?.t) {
                        min_hit = .{
                            .type = hit_type,
                            .position = hit_point.position,
                            .normal = hit_point.normal,
                            .t = hit_point.t,
                            .wall_properties = wall.properties,
                            .rectangle_index = index,
                        };
                    }
                }
                const hit = min_hit orelse break;

                const previous_wall_properties = turtle.wall_properties;
                turtle = switch (hit.type) {
                    .normal_hit => .{
                        .position = hit.position,
                        .direction = hit.normal.multiply(normal_to_direction),
                        .wall_properties = hit.wall_properties,
                        .rectangle_index = hit.rectangle_index,
                    },
                    .side_scrape_new_wall_entrance => switch (turtle.wall_properties.gimmick) {
                        .none => .{
                            .position = hit.position,
                            .direction = turtle.direction,
                            .wall_properties = hit.wall_properties,
                            .rectangle_index = hit.rectangle_index,
                        },
                        else => .{
                            .position = hit.position,
                            .direction = turtle.direction,
                            .wall_properties = turtle.wall_properties,
                            .rectangle_index = turtle.rectangle_index,
                        },
                    },
                    .side_scrape_current_wall_exit => switch (turtle.wall_properties.gimmick) {
                        .none => .{
                            .position = hit.position,
                            .direction = hit.normal.negate(),
                            .wall_properties = hit.wall_properties,
                            .rectangle_index = hit.rectangle_index,
                        },
                        else => .{
                            .position = hit.position,
                            .direction = turtle.direction,
                            .wall_properties = .{},
                            .rectangle_index = 0, // Could lead to bug if there is concavity right after this wall.
                        },
                    },
                    .breakable_wall_entrance, .breakable_wall_exit => .{
                        .position = hit.position,
                        .direction = turtle.direction,
                        .wall_properties = turtle.wall_properties,
                        .rectangle_index = turtle.rectangle_index,
                    },
                };

                const diff = turtle.position.subtract(midpoint);
                if (diff.x() < 0) {
                    hit_negative_x = true;
                }
                if (hit_negative_x and diff.y() < 0) {
                    hit_negative_y = true;
                }
                if (hit_negative_y and diff.y() > 0) {
                    break;
                }

                if (hit.type == .breakable_wall_entrance) {
                    breakable_walls[hit.rectangle_index].edge_1 = turtle.position;
                } else if (hit.type == .breakable_wall_exit) {
                    breakable_walls[hit.rectangle_index].edge_2_index = @intCast(result.len);
                }

                const add_wall = switch (hit.type) {
                    .normal_hit => true,
                    .side_scrape_new_wall_entrance => !std.meta.eql(turtle.wall_properties, previous_wall_properties),
                    .side_scrape_current_wall_exit => true,
                    .breakable_wall_entrance => false,
                    .breakable_wall_exit => true,
                };
                if (add_wall) {
                    result.append(.{
                        .edge_1 = turtle.position,
                        .edge_2_index = @intCast(result.len + 1),
                        .properties = turtle.wall_properties,
                    }) catch break;
                }
            }
            result.buffer[result.len - 1].edge_2_index = 0;

            for (wall_rectangles, 0..) |*wall, index| {
                const breakable_wall = breakable_walls[index];
                if (breakable_wall.edge_1) |edge_1| {
                    if (breakable_wall.edge_2_index) |edge_2_index| {
                        result.append(.{
                            .edge_1 = edge_1,
                            .edge_2_index = edge_2_index,
                            .properties = wall.properties,
                        }) catch break;
                    }
                }
            }

            return result;
        }

        fn captureFloorGimmicks(
            floor_number: ?u32,
            stage_set_number: ?u32,
            floor_pointers: []const sdk.memory.Pointer(game.Floor(game_id)),
            walls: []const model.Wall,
        ) model.FloorGimmicks {
            const current_floor_number = floor_number orelse return .empty;
            const set_number = stage_set_number;
            var result = model.FloorGimmicks.empty;
            for (floor_pointers) |floor_pointer| {
                const floor = floor_pointer.toConstPointer() orelse continue;
                if (floor.floor_number != current_floor_number) {
                    continue;
                }
                const properties = captureFloorGimmickProperties(floor) orelse continue;
                switch (game_id) {
                    .t7 => {
                        var min = sdk.math.Vec2.fill(std.math.inf(f32));
                        var max = sdk.math.Vec2.fill(-std.math.inf(f32));
                        for (walls) |*wall| {
                            min = sdk.math.Vec2.minElements(min, wall.edge_1);
                            max = sdk.math.Vec2.maxElements(max, wall.edge_1);
                        }
                        const center = min.add(max).scale(0.5);
                        const half_size = max.subtract(min).scale(0.5);
                        result.append(.{
                            .rectangle = .{
                                .center = center,
                                .half_size = half_size,
                                .rotation = 0,
                            },
                            .properties = properties,
                        }) catch break;
                    },
                    .t8 => {
                        if (floor.actor.hidden_polaris.value or floor.state == .init or floor.set_number != set_number) {
                            continue;
                        }
                        const root = floor.actor.root_component.toConstPointer() orelse continue;
                        const floor_mesh_half_size = 50;
                        result.append(.{
                            .rectangle = .{
                                .center = root.relative_position.convert().swizzle("xy"),
                                .half_size = root.relative_scale.convert().swizzle("xy").scale(floor_mesh_half_size),
                                .rotation = root.relative_rotation.convert().y(),
                            },
                            .properties = properties,
                        }) catch break;
                    },
                }
            }
            return result;
        }

        fn captureFloorGimmickProperties(floor: *const game.Floor(game_id)) ?model.FloorGimmickProperties {
            return switch (game_id) {
                .t7 => .{
                    .type = block: {
                        if (floor.is_breakable.toBool() orelse false) {
                            break :block .floor_break;
                        } else {
                            return null;
                        }
                    },
                    .flags = .{
                        .hard = false,
                        .damaged = false,
                        .used_up = false,
                    },
                },
                .t8 => .{
                    .type = block: {
                        if (floor.is_floor_blast.toBool() orelse false) {
                            break :block .floor_blast;
                        } else if (floor.is_breakable.toBool() orelse false) {
                            break :block .floor_break;
                        } else {
                            return null;
                        }
                    },
                    .flags = .{
                        .hard = floor.is_hard.toBool() orelse false,
                        .damaged = floor.destruction_level > 0,
                        .used_up = switch (floor.is_hard.toBool() orelse false) {
                            false => floor.destruction_level > 0,
                            else => floor.destruction_level > 1,
                        },
                    },
                },
            };
        }
    };
}

const testing = std.testing;

test "should capture irony version correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    try testing.expectEqual(
        model.IronyVersion.current,
        capturer.captureFrame(&gm(.{})).irony_version,
    );
}

test "should capture game correctly" {
    const gm7 = game.Memory(.t7).testingInit;
    var capturer_7 = Capturer(.t7){};
    try testing.expectEqual(
        model.Game.t7,
        capturer_7.captureFrame(&gm7(.{})).game,
    );
    const gm8 = game.Memory(.t8).testingInit;
    var capturer_8 = Capturer(.t8){};
    try testing.expectEqual(
        model.Game.t8,
        capturer_8.captureFrame(&gm8(.{})).game,
    );
}

test "should capture game version correctly" {
    const makeVersion = struct {
        fn call(comptime str: []const u8) game.Version(.t8) {
            return (str ++ ([1]u8{0} ** (@sizeOf(game.Version(.t8)) - str.len))).*;
        }
    }.call;
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    try testing.expectEqualStrings(
        "",
        capturer.captureFrame(&gm(.{
            .game_version = null,
        })).game_version.asSlice(),
    );
    try testing.expectEqualStrings(
        "",
        capturer.captureFrame(&gm(.{
            .game_version = &makeVersion(""),
        })).game_version.asSlice(),
    );
    try testing.expectEqualStrings(
        "",
        capturer.captureFrame(&gm(.{
            .game_version = &makeVersion("    "),
        })).game_version.asSlice(),
    );
    try testing.expectEqualStrings(
        "12.34.56",
        capturer.captureFrame(&gm(.{
            .game_version = &makeVersion("12.34.56"),
        })).game_version.asSlice(),
    );
    try testing.expectEqualStrings(
        "12.34.56",
        capturer.captureFrame(&gm(.{
            .game_version = &makeVersion("    12.34.56"),
        })).game_version.asSlice(),
    );
    try testing.expectEqualStrings(
        "12.34.56",
        capturer.captureFrame(&gm(.{
            .game_version = &makeVersion("12.34.56 (ignore)"),
        })).game_version.asSlice(),
    );
    try testing.expectEqualStrings(
        "12.34.56",
        capturer.captureFrame(&gm(.{
            .game_version = &makeVersion(" 12.34.56 (ignore)"),
        })).game_version.asSlice(),
    );
}

test "should capture source correctly in T7" {
    const gm = game.Memory(.t7).testingInit;
    var capturer = Capturer(.t7){};
    try testing.expectEqual(
        null,
        capturer.captureFrame(&gm(.{
            .match = null,
            .replay_mode = null,
        })).source,
    );
    try testing.expectEqual(
        .practice,
        capturer.captureFrame(&gm(.{
            .match = &.{ .phase = .practice_mode },
            .replay_mode = null,
        })).source,
    );
    try testing.expectEqual(
        .practice,
        capturer.captureFrame(&gm(.{
            .match = &.{ .phase = .move_showcase },
            .replay_mode = null,
        })).source,
    );
    try testing.expectEqual(
        .practice,
        capturer.captureFrame(&gm(.{
            .match = &.{ .phase = .practice_mode },
            .replay_mode = &.loading,
        })).source,
    );
    try testing.expectEqual(
        .replay_loading,
        capturer.captureFrame(&gm(.{
            .match = null,
            .replay_mode = &.loading,
        })).source,
    );
    try testing.expectEqual(
        .replay_loading,
        capturer.captureFrame(&gm(.{
            .match = &.{ .phase = .mid_round },
            .replay_mode = &.loading,
        })).source,
    );
    try testing.expectEqual(
        .replay_playback,
        capturer.captureFrame(&gm(.{
            .match = null,
            .replay_mode = &.playback,
        })).source,
    );
    try testing.expectEqual(
        .replay_playback,
        capturer.captureFrame(&gm(.{
            .match = &.{ .phase = .mid_round },
            .replay_mode = &.playback,
        })).source,
    );
    try testing.expectEqual(
        .live_game,
        capturer.captureFrame(&gm(.{
            .match = &.{ .phase = .mid_round },
            .replay_mode = null,
        })).source,
    );
}

test "should capture source correctly in T8" {
    const Functions = struct {
        fn notReplay(is_replay: *bool, is_pre_calculated: *bool) callconv(.c) void {
            is_replay.* = false;
            is_pre_calculated.* = false;
        }
        fn replayLoading(is_replay: *bool, is_pre_calculated: *bool) callconv(.c) void {
            is_replay.* = true;
            is_pre_calculated.* = false;
        }
        fn replayPlayback(is_replay: *bool, is_pre_calculated: *bool) callconv(.c) void {
            is_replay.* = true;
            is_pre_calculated.* = true;
        }
    };
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    try testing.expectEqual(
        null,
        capturer.captureFrame(&gm(.{
            .match = null,
            .functions = .{ .isReplay = null },
        })).source,
    );
    try testing.expectEqual(
        null,
        capturer.captureFrame(&gm(.{
            .match = null,
            .functions = .{ .isReplay = Functions.notReplay },
        })).source,
    );
    try testing.expectEqual(
        null,
        capturer.captureFrame(&gm(.{
            .match = &.{ .phase = .mid_round },
            .functions = .{ .isReplay = null },
        })).source,
    );
    try testing.expectEqual(
        .practice,
        capturer.captureFrame(&gm(.{
            .match = &.{ .phase = .practice_mode },
            .functions = .{ .isReplay = null },
        })).source,
    );
    try testing.expectEqual(
        .practice,
        capturer.captureFrame(&gm(.{
            .match = &.{ .phase = .practice_mode },
            .functions = .{ .isReplay = Functions.replayLoading },
        })).source,
    );
    try testing.expectEqual(
        .practice,
        capturer.captureFrame(&gm(.{
            .match = &.{ .phase = .move_showcase },
            .functions = .{ .isReplay = null },
        })).source,
    );
    try testing.expectEqual(
        .practice,
        capturer.captureFrame(&gm(.{
            .match = &.{ .phase = .move_showcase },
            .functions = .{ .isReplay = Functions.replayPlayback },
        })).source,
    );
    try testing.expectEqual(
        .live_game,
        capturer.captureFrame(&gm(.{
            .match = &.{ .phase = .mid_round },
            .functions = .{ .isReplay = Functions.notReplay },
        })).source,
    );
    try testing.expectEqual(
        .replay_loading,
        capturer.captureFrame(&gm(.{
            .match = &.{ .phase = .mid_round },
            .functions = .{ .isReplay = Functions.replayLoading },
        })).source,
    );
    try testing.expectEqual(
        .replay_playback,
        capturer.captureFrame(&gm(.{
            .match = &.{ .phase = .mid_round },
            .functions = .{ .isReplay = Functions.replayPlayback },
        })).source,
    );
}

test "should capture match phase correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    try testing.expectEqual(
        null,
        capturer.captureFrame(&gm(.{ .match = null })).match_phase,
    );
    try testing.expectEqual(
        .intro,
        capturer.captureFrame(&gm(.{ .match = &.{ .phase = .intro_1 } })).match_phase,
    );
    try testing.expectEqual(
        .intro,
        capturer.captureFrame(&gm(.{ .match = &.{ .phase = .intro_2 } })).match_phase,
    );
    try testing.expectEqual(
        .round_start,
        capturer.captureFrame(&gm(.{ .match = &.{ .phase = .round_start } })).match_phase,
    );
    try testing.expectEqual(
        .mid_round,
        capturer.captureFrame(&gm(.{ .match = &.{ .phase = .mid_round } })).match_phase,
    );
    try testing.expectEqual(
        .round_end,
        capturer.captureFrame(&gm(.{ .match = &.{ .phase = .round_end } })).match_phase,
    );
    try testing.expectEqual(
        .outro,
        capturer.captureFrame(&gm(.{ .match = &.{ .phase = .win_loose_outro } })).match_phase,
    );
    try testing.expectEqual(
        .outro,
        capturer.captureFrame(&gm(.{ .match = &.{ .phase = .draw_outro } })).match_phase,
    );
    try testing.expectEqual(
        .in_between_rounds,
        capturer.captureFrame(&gm(.{ .match = &.{ .phase = .stage_transformation } })).match_phase,
    );
    try testing.expectEqual(
        .not_in_a_match,
        capturer.captureFrame(&gm(.{ .match = &.{ .phase = .@"continue" } })).match_phase,
    );
    try testing.expectEqual(
        .not_in_a_match,
        capturer.captureFrame(&gm(.{ .match = &.{ .phase = .practice_mode } })).match_phase,
    );
    try testing.expectEqual(
        .not_in_a_match,
        capturer.captureFrame(&gm(.{ .match = &.{ .phase = .move_showcase } })).match_phase,
    );
    try testing.expectEqual(
        .not_in_a_match,
        capturer.captureFrame(&gm(.{ .match = &.{ .phase = .rematch_menu_1 } })).match_phase,
    );
    try testing.expectEqual(
        .not_in_a_match,
        capturer.captureFrame(&gm(.{ .match = &.{ .phase = .rematch_menu_2 } })).match_phase,
    );
}

test "should capture rounds needed to win correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    try testing.expectEqual(
        123,
        capturer.captureFrame(&gm(.{ .ruleset = &.{ .rounds_needed_to_win = 123 } })).rounds_needed_to_win,
    );
    try testing.expectEqual(
        null,
        capturer.captureFrame(&gm(.{ .ruleset = null })).rounds_needed_to_win,
    );
}

test "should capture frames since round start correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    try testing.expectEqual(
        123,
        capturer.captureFrame(&gm(.{
            .player_1 = &.{ .frames_since_round_start = 123 },
            .player_2 = &.{ .frames_since_round_start = 123 },
        })).frames_since_round_start,
    );
    try testing.expectEqual(
        123,
        capturer.captureFrame(&gm(.{
            .player_1 = &.{ .frames_since_round_start = 123 },
            .player_2 = null,
        })).frames_since_round_start,
    );
    try testing.expectEqual(
        123,
        capturer.captureFrame(&gm(.{
            .player_1 = null,
            .player_2 = &.{ .frames_since_round_start = 123 },
        })).frames_since_round_start,
    );
    try testing.expectEqual(
        null,
        capturer.captureFrame(&gm(.{
            .player_1 = null,
            .player_2 = null,
        })).frames_since_round_start,
    );
}

test "should capture frames left in round correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    try testing.expectEqual(
        123,
        capturer.captureFrame(&gm(.{ .match = &.{
            .phase = .mid_round,
            .frames_left_in_round = 123,
        } })).frames_left_in_round,
    );
    try testing.expectEqual(
        null,
        capturer.captureFrame(&gm(.{ .match = &.{
            .phase = .practice_mode,
            .frames_left_in_round = 123,
        } })).frames_left_in_round,
    );
    try testing.expectEqual(
        null,
        capturer.captureFrame(&gm(.{ .match = &.{
            .phase = .move_showcase,
            .frames_left_in_round = 123,
        } })).frames_left_in_round,
    );
    try testing.expectEqual(
        null,
        capturer.captureFrame(&gm(.{ .match = null })).frames_left_in_round,
    );
}

test "should capture floor Z correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    try testing.expectEqual(
        150.0,
        capturer.captureFrame(&gm(.{
            .player_1 = &.{ .floor_z = .fromConverted(100.0) },
            .player_2 = &.{ .floor_z = .fromConverted(200.0) },
        })).floor_z,
    );
    try testing.expectEqual(
        123.0,
        capturer.captureFrame(&gm(.{
            .player_1 = &.{ .floor_z = .fromConverted(123.0) },
            .player_2 = null,
        })).floor_z,
    );
    try testing.expectEqual(
        123.0,
        capturer.captureFrame(&gm(.{
            .player_1 = null,
            .player_2 = &.{ .floor_z = .fromConverted(123.0) },
        })).floor_z,
    );
    try testing.expectEqual(
        null,
        capturer.captureFrame(&gm(.{
            .player_1 = null,
            .player_2 = null,
        })).floor_z,
    );
}

test "should capture camera correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    try testing.expectEqual(
        null,
        capturer.captureFrame(&gm(.{
            .camera_manager = null,
        })).camera,
    );
    try testing.expectEqual(
        model.Camera{
            .position = .fromArray(.{ 1, 2, 3 }),
            .pitch = 0.25 * std.math.pi,
            .yaw = 0.5 * std.math.pi,
            .roll = 0.75 * std.math.pi,
            .horizontal_fov = 1.0 / 3.0 * std.math.pi,
        },
        capturer.captureFrame(&gm(.{
            .camera_manager = &.{
                .horizontal_fov = .fromConverted(1.0 / 3.0 * std.math.pi),
                .position = .fromConverted(.fromArray(.{ 1, 2, 3 })),
                .rotation = .fromConverted(.fromArray(.{
                    0.25 * std.math.pi,
                    0.5 * std.math.pi,
                    0.75 * std.math.pi,
                })),
            },
        })).camera,
    );
}

test "should capture left player id correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&gm(.{
            .player_1 = &.{ .input_side = @enumFromInt(2) },
            .player_2 = &.{ .input_side = @enumFromInt(2) },
            .main_player_info = &.{ .player_id = .player_1 },
            .secondary_player_info = &.{ .player_id = .player_2 },
        })).left_player_id,
    );
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&gm(.{
            .player_1 = &.{ .input_side = .left },
            .player_2 = &.{ .input_side = @enumFromInt(2) },
            .main_player_info = &.{ .player_id = .player_1 },
            .secondary_player_info = &.{ .player_id = .player_2 },
        })).left_player_id,
    );
    try testing.expectEqual(
        .player_2,
        capturer.captureFrame(&gm(.{
            .player_1 = &.{ .input_side = .right },
            .player_2 = &.{ .input_side = @enumFromInt(2) },
            .main_player_info = &.{ .player_id = .player_1 },
            .secondary_player_info = &.{ .player_id = .player_2 },
        })).left_player_id,
    );
    try testing.expectEqual(
        .player_2,
        capturer.captureFrame(&gm(.{
            .player_1 = &.{ .input_side = @enumFromInt(2) },
            .player_2 = &.{ .input_side = .left },
            .main_player_info = &.{ .player_id = .player_2 },
            .secondary_player_info = &.{ .player_id = .player_1 },
        })).left_player_id,
    );
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&gm(.{
            .player_1 = &.{ .input_side = @enumFromInt(2) },
            .player_2 = &.{ .input_side = .right },
            .main_player_info = &.{ .player_id = .player_2 },
            .secondary_player_info = &.{ .player_id = .player_1 },
        })).left_player_id,
    );
}

test "should capture main player id correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&gm(.{
            .main_player_info = &.{ .player_id = .player_1 },
            .secondary_player_info = &.{ .player_id = .player_2 },
        })).main_player_id,
    );
    try testing.expectEqual(
        .player_2,
        capturer.captureFrame(&gm(.{
            .main_player_info = &.{ .player_id = .player_2 },
            .secondary_player_info = &.{ .player_id = .player_1 },
        })).main_player_id,
    );
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&gm(.{
            .main_player_info = null,
            .secondary_player_info = null,
        })).main_player_id,
    );
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&gm(.{
            .main_player_info = &.{ .player_id = .player_1 },
            .secondary_player_info = null,
        })).main_player_id,
    );
    try testing.expectEqual(
        .player_2,
        capturer.captureFrame(&gm(.{
            .main_player_info = &.{ .player_id = .player_2 },
            .secondary_player_info = null,
        })).main_player_id,
    );
    try testing.expectEqual(
        .player_2,
        capturer.captureFrame(&gm(.{
            .main_player_info = null,
            .secondary_player_info = &.{ .player_id = .player_1 },
        })).main_player_id,
    );
    try testing.expectEqual(
        .player_1,
        capturer.captureFrame(&gm(.{
            .main_player_info = null,
            .secondary_player_info = &.{ .player_id = .player_2 },
        })).main_player_id,
    );
}

test "should capture player name correctly" {
    const makePlayerName = struct {
        fn call(comptime name: []const u8) game.PlayerName {
            return (name ++ ([1]u8{0} ** (@sizeOf(game.PlayerName) - name.len))).*;
        }
    }.call;
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame_1 = capturer.captureFrame(&gm(.{
        .main_player_info = &.{ .player_id = .player_1, .name = makePlayerName("Player 1") },
        .secondary_player_info = &.{ .player_id = .player_2, .name = makePlayerName("Player 2") },
    }));
    const frame_2 = capturer.captureFrame(&gm(.{
        .main_player_info = &.{ .player_id = .player_2, .name = makePlayerName("Player 3") },
        .secondary_player_info = null,
    }));
    try testing.expectEqualStrings("Player 1", frame_1.getPlayerById(.player_1).name.asSlice());
    try testing.expectEqualStrings("Player 2", frame_1.getPlayerById(.player_2).name.asSlice());
    try testing.expectEqualStrings("", frame_2.getPlayerById(.player_1).name.asSlice());
    try testing.expectEqualStrings("Player 3", frame_2.getPlayerById(.player_2).name.asSlice());
}

test "should capture rounds won correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame_1 = capturer.captureFrame(&gm(.{ .match = &.{ .players = .{
        .{ .rounds_won = 123 },
        .{ .rounds_won = 456 },
    } } }));
    const frame_2 = capturer.captureFrame(&gm(.{ .match = null }));
    try testing.expectEqual(123, frame_1.getPlayerById(.player_1).rounds_won);
    try testing.expectEqual(456, frame_1.getPlayerById(.player_2).rounds_won);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_1).rounds_won);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_2).rounds_won);
}

test "should capture character id correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&gm(.{
        .player_1 = &.{ .character_id = 123 },
        .player_2 = null,
    }));
    try testing.expectEqual(123, frame.getPlayerById(.player_1).character_id);
    try testing.expectEqual(null, frame.getPlayerById(.player_2).character_id);
}

test "should capture current animation id correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&gm(.{
        .player_1 = &.{ .animation_id = 123 },
        .player_2 = null,
    }));
    try testing.expectEqual(123, frame.getPlayerById(.player_1).animation_id);
    try testing.expectEqual(null, frame.getPlayerById(.player_2).animation_id);
}

test "should capture current animation frame correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&gm(.{
        .player_1 = &.{ .animation_frame = 123 },
        .player_2 = null,
    }));
    try testing.expectEqual(123, frame.getPlayerById(.player_1).animation_frame);
    try testing.expectEqual(null, frame.getPlayerById(.player_2).animation_frame);
}

test "should capture current animation total frames correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&gm(.{
        .player_1 = &.{ .animation_total_frames = 123 },
        .player_2 = null,
    }));
    try testing.expectEqual(123, frame.getPlayerById(.player_1).animation_total_frames);
    try testing.expectEqual(null, frame.getPlayerById(.player_2).animation_total_frames);
}

test "should capture attack type correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&gm(.{
        .player_1 = &.{ .attack_type = .special_low },
        .player_2 = null,
    }));
    try testing.expectEqual(.special_low, frame.getPlayerById(.player_1).attack_type);
    try testing.expectEqual(null, frame.getPlayerById(.player_2).attack_type);
}

test "should capture hit outcome correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&gm(.{
        .player_1 = &.{ .hit_outcome = .normal_hit_standing },
        .player_2 = null,
    }));
    try testing.expectEqual(.normal_hit_standing, frame.getPlayerById(.player_1).hit_outcome);
    try testing.expectEqual(null, frame.getPlayerById(.player_2).hit_outcome);
}

test "should capture combo hits correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame_1 = capturer.captureFrame(&gm(.{ .match = &.{ .players = .{
        .{ .combo_hits = 123 },
        .{ .combo_hits = 456 },
    } } }));
    const frame_2 = capturer.captureFrame(&gm(.{ .match = null }));
    try testing.expectEqual(123, frame_1.getPlayerById(.player_1).combo_hits);
    try testing.expectEqual(456, frame_1.getPlayerById(.player_2).combo_hits);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_1).combo_hits);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_2).combo_hits);
}

test "should capture combo damage correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame_1 = capturer.captureFrame(&gm(.{ .match = &.{ .players = .{
        .{ .combo_damage = 123 },
        .{ .combo_damage = 456 },
    } } }));
    const frame_2 = capturer.captureFrame(&gm(.{ .match = null }));
    try testing.expectEqual(123, frame_1.getPlayerById(.player_1).combo_damage);
    try testing.expectEqual(456, frame_1.getPlayerById(.player_2).combo_damage);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_1).combo_damage);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_2).combo_damage);
}

test "should capture posture correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame_1 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .animation_frame = 3,
            .state_flags = .{},
            .simple_state = .airborne,
            .animation = .fromPointer(&.{
                .airborne_start = 4,
                .airborne_end = 6,
            }),
        },
        .player_2 = &.{
            .animation_frame = 5,
            .state_flags = .{},
            .simple_state = .airborne,
            .animation = .fromPointer(&.{
                .airborne_start = 4,
                .airborne_end = 6,
            }),
        },
    }));
    const frame_2 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .animation_frame = 1,
            .state_flags = .{ .downed = true, .face_down = false },
            .simple_state = .ground_face_down,
            .animation = .fromPointer(&.{
                .airborne_start = 0,
                .airborne_end = 0,
            }),
        },
        .player_2 = &.{
            .animation_frame = 1,
            .state_flags = .{ .downed = true, .face_down = true },
            .simple_state = .ground_face_up,
            .animation = .fromPointer(&.{
                .airborne_start = 0,
                .airborne_end = 0,
            }),
        },
    }));
    const frame_3 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .animation_frame = 1,
            .state_flags = .{ .crouching = true },
            .simple_state = .crouch,
            .animation = .fromPointer(&.{
                .airborne_start = 0,
                .airborne_end = 0,
            }),
        },
        .player_2 = null,
    }));
    try testing.expectEqual(.standing, frame_1.getPlayerById(.player_1).posture);
    try testing.expectEqual(.airborne, frame_1.getPlayerById(.player_2).posture);
    try testing.expectEqual(.downed_face_up, frame_2.getPlayerById(.player_1).posture);
    try testing.expectEqual(.downed_face_down, frame_2.getPlayerById(.player_2).posture);
    try testing.expectEqual(.crouching, frame_3.getPlayerById(.player_1).posture);
    try testing.expectEqual(null, frame_3.getPlayerById(.player_2).posture);
}

test "should capture blocking correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame_1 = capturer.captureFrame(&gm(.{
        .player_1 = null,
        .player_2 = &.{ .state_flags = .{} },
    }));
    const frame_2 = capturer.captureFrame(&gm(.{
        .player_1 = &.{ .state_flags = .{ .blocking_mids = true, .blocking_lows = false, .neutral_blocking = true } },
        .player_2 = &.{ .state_flags = .{ .blocking_mids = true, .blocking_lows = false, .neutral_blocking = false } },
    }));
    const frame_3 = capturer.captureFrame(&gm(.{
        .player_1 = &.{ .state_flags = .{ .blocking_mids = false, .blocking_lows = true, .neutral_blocking = true } },
        .player_2 = &.{ .state_flags = .{ .blocking_mids = false, .blocking_lows = true, .neutral_blocking = false } },
    }));
    try testing.expectEqual(null, frame_1.getPlayerById(.player_1).blocking);
    try testing.expectEqual(.not_blocking, frame_1.getPlayerById(.player_2).blocking);
    try testing.expectEqual(.neutral_blocking_mids, frame_2.getPlayerById(.player_1).blocking);
    try testing.expectEqual(.fully_blocking_mids, frame_2.getPlayerById(.player_2).blocking);
    try testing.expectEqual(.neutral_blocking_lows, frame_3.getPlayerById(.player_1).blocking);
    try testing.expectEqual(.fully_blocking_lows, frame_3.getPlayerById(.player_2).blocking);
}

test "should capture crushing correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame_1 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .animation_frame = 4,
            .state_flags = .{ .low_crushing_move = true },
            .simple_state = .airborne,
            .power_crushing = .false,
            .animation = .fromPointer(&.{
                .airborne_start = 5,
                .airborne_end = 10,
            }),
        },
        .player_2 = &.{
            .animation_frame = 5,
            .state_flags = .{ .low_crushing_move = true },
            .simple_state = .airborne,
            .power_crushing = .false,
            .animation = .fromPointer(&.{
                .airborne_start = 5,
                .airborne_end = 10,
            }),
        },
    }));
    const frame_2 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .animation_frame = 7,
            .state_flags = .{ .low_crushing_move = true },
            .simple_state = .airborne,
            .power_crushing = .false,
            .animation = .fromPointer(&.{
                .airborne_start = 5,
                .airborne_end = 10,
            }),
        },
        .player_2 = &.{
            .animation_frame = 8,
            .state_flags = .{ .low_crushing_move = true },
            .simple_state = .airborne,
            .power_crushing = .false,
            .animation = .fromPointer(&.{
                .airborne_start = 5,
                .airborne_end = 10,
            }),
        },
    }));
    const frame_3 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .animation_frame = 1,
            .state_flags = .{ .downed = true, .face_down = false },
            .simple_state = .ground_face_up,
            .power_crushing = .false,
            .animation = .fromPointer(&.{
                .airborne_start = 0,
                .airborne_end = 0,
            }),
        },
        .player_2 = &.{
            .animation_frame = 1,
            .state_flags = .{ .downed = true, .face_down = true },
            .simple_state = .ground_face_down,
            .power_crushing = .false,
            .animation = .fromPointer(&.{
                .airborne_start = 0,
                .airborne_end = 0,
            }),
        },
    }));
    const frame_4 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .animation_frame = 1,
            .state_flags = .{ .crouching = true },
            .simple_state = .crouch,
            .power_crushing = .false,
            .animation = .fromPointer(&.{
                .airborne_start = 0,
                .airborne_end = 0,
            }),
        },
    }));
    const frame_5 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .animation_frame = 1,
            .state_flags = .{},
            .simple_state = .standing,
            .power_crushing = .true,
            .animation = .fromPointer(&.{
                .airborne_start = 0,
                .airborne_end = 0,
            }),
        },
        .player_2 = &.{
            .animation_frame = 1,
            .state_flags = .{},
            .simple_state = .invincible,
            .power_crushing = .false,
            .animation = .fromPointer(&.{
                .airborne_start = 0,
                .airborne_end = 0,
            }),
        },
    }));
    try testing.expectEqual(model.Crushing{ .anti_air_only_crushing = true }, frame_1.getPlayerById(.player_1).crushing);
    try testing.expectEqual(model.Crushing{ .low_crushing = true }, frame_1.getPlayerById(.player_2).crushing);
    try testing.expectEqual(model.Crushing{ .low_crushing = true }, frame_2.getPlayerById(.player_1).crushing);
    try testing.expectEqual(model.Crushing{}, frame_2.getPlayerById(.player_2).crushing);
    try testing.expectEqual(
        model.Crushing{ .anti_air_only_crushing = true, .high_crushing = true },
        frame_3.getPlayerById(.player_1).crushing,
    );
    try testing.expectEqual(
        model.Crushing{ .anti_air_only_crushing = true, .high_crushing = true },
        frame_3.getPlayerById(.player_2).crushing,
    );
    try testing.expectEqual(
        model.Crushing{ .anti_air_only_crushing = true, .high_crushing = true },
        frame_4.getPlayerById(.player_1).crushing,
    );
    try testing.expectEqual(null, frame_4.getPlayerById(.player_2).crushing);
    try testing.expectEqual(
        model.Crushing{ .anti_air_only_crushing = true, .power_crushing = true },
        frame_5.getPlayerById(.player_1).crushing,
    );
    try testing.expectEqual(
        model.Crushing{ .anti_air_only_crushing = true, .invincibility = true },
        frame_5.getPlayerById(.player_2).crushing,
    );
}

test "should capture can interact correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame_1 = capturer.captureFrame(&gm(.{
        .player_1 = &.{ .cancel_flags = .{ .can_interact = false }, .simple_state = .standing_forward },
        .player_2 = &.{ .cancel_flags = .{ .can_interact = true }, .simple_state = .standing_forward },
    }));
    const frame_2 = capturer.captureFrame(&gm(.{
        .player_1 = &.{ .cancel_flags = .{ .can_interact = true }, .simple_state = .juggled },
        .player_2 = null,
    }));
    try testing.expectEqual(false, frame_1.getPlayerById(.player_1).can_interact);
    try testing.expectEqual(true, frame_1.getPlayerById(.player_2).can_interact);
    try testing.expectEqual(false, frame_2.getPlayerById(.player_1).can_interact);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_2).can_interact);
}

test "should capture throw escape correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};

    const frame_1 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .correct_throw_escape_input = .none,
            .throw_escape_flags = .{ .escape_success = false },
        },
        .player_2 = &.{
            .correct_throw_escape_input = .press_1_plus_2,
            .throw_escape_flags = .{ .escape_success = false },
        },
        .cancel_requirements = &.{
            .throw_escape_press_1 = false,
            .throw_escape_press_2 = false,
            .throw_escape_press_1_plus_2 = true,
            .throw_escape_hold = false,
        },
    }));
    try testing.expectEqual(null, frame_1.getPlayerById(.player_1).throw_escape);
    try testing.expectEqual(model.ThrowEscape{
        .phase = .in_escape_window,
        .input_mode = .press,
        .correct_inputs = .{ .one = false, .two = false, .one_plus_two = true },
    }, frame_1.getPlayerById(.player_2).throw_escape);

    const frame_2 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .correct_throw_escape_input = .press_1,
            .throw_escape_flags = .{ .escape_success = false },
        },
        .player_2 = &.{
            .correct_throw_escape_input = .press_2,
            .throw_escape_flags = .{ .escape_success = true },
        },
        .cancel_requirements = &.{
            .throw_escape_press_1 = true,
            .throw_escape_press_2 = true,
            .throw_escape_press_1_plus_2 = false,
            .throw_escape_hold = false,
        },
    }));
    try testing.expectEqual(model.ThrowEscape{
        .phase = .in_escape_window,
        .input_mode = .press,
        .correct_inputs = .{ .one = true, .two = true, .one_plus_two = false },
    }, frame_2.getPlayerById(.player_1).throw_escape);
    try testing.expectEqual(model.ThrowEscape{
        .phase = .escape_success,
        .input_mode = .press,
        .correct_inputs = .{ .one = true, .two = true, .one_plus_two = false },
    }, frame_2.getPlayerById(.player_2).throw_escape);

    const frame_3 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .correct_throw_escape_input = .hold_1,
            .throw_escape_flags = .{ .escape_success = false },
        },
        .player_2 = &.{
            .correct_throw_escape_input = .hold_2,
            .throw_escape_flags = .{ .escape_success = false },
        },
        .cancel_requirements = &.{
            .throw_escape_press_1 = false,
            .throw_escape_press_2 = false,
            .throw_escape_press_1_plus_2 = false,
            .throw_escape_hold = true,
        },
    }));
    try testing.expectEqual(model.ThrowEscape{
        .phase = .in_escape_window,
        .input_mode = .hold,
        .correct_inputs = .{ .one = true, .two = false, .one_plus_two = false },
    }, frame_3.getPlayerById(.player_1).throw_escape);
    try testing.expectEqual(model.ThrowEscape{
        .phase = .in_escape_window,
        .input_mode = .hold,
        .correct_inputs = .{ .one = false, .two = true, .one_plus_two = false },
    }, frame_3.getPlayerById(.player_2).throw_escape);

    const frame_4 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .correct_throw_escape_input = .hold_1_plus_2,
            .throw_escape_flags = .{ .escape_success = false },
        },
        .player_2 = &.{
            .correct_throw_escape_input = @enumFromInt(0),
            .throw_escape_flags = .{ .escape_success = false },
        },
        .cancel_requirements = &.{
            .throw_escape_press_1 = false,
            .throw_escape_press_2 = false,
            .throw_escape_press_1_plus_2 = false,
            .throw_escape_hold = false,
        },
    }));
    try testing.expectEqual(model.ThrowEscape{
        .phase = .escape_fail,
        .input_mode = .hold,
        .correct_inputs = .{ .one = false, .two = false, .one_plus_two = false },
    }, frame_4.getPlayerById(.player_1).throw_escape);
    try testing.expectEqual(null, frame_4.getPlayerById(.player_2).throw_escape);
}

test "should capture can move correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame_1 = capturer.captureFrame(&gm(.{
        .player_1 = &.{ .can_move = .false },
        .player_2 = &.{ .can_move = .true },
    }));
    const frame_2 = capturer.captureFrame(&gm(.{
        .player_1 = null,
        .player_2 = &.{ .can_move = @enumFromInt(2) },
    }));
    try testing.expectEqual(false, frame_1.getPlayerById(.player_1).can_move);
    try testing.expectEqual(true, frame_1.getPlayerById(.player_2).can_move);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_1).can_move);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_2).can_move);
}

test "should capture input correctly in T7" {
    const gm = game.Memory(.t7).testingInit;
    var capturer = Capturer(.t7){};
    const frame = capturer.captureFrame(&gm(.{
        .player_1 = &.{
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
            .input_side = .left,
        },
        .player_2 = &.{
            .directional_input = .{ .down = .down_back },
            .attack_input = .{ .down = .{
                .button_1 = true,
                .button_2 = false,
                .button_3 = true,
                .button_4 = false,
                .rage = true,
            } },
            .input_side = .right,
        },
    }));
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
    try testing.expectEqual(model.Input{
        .forward = false,
        .back = true,
        .up = false,
        .down = true,
        .left = false,
        .right = true,
        .button_1 = true,
        .button_2 = false,
        .button_3 = true,
        .button_4 = false,
        .special_style = false,
        .rage = true,
        .heat = false,
    }, frame.getPlayerById(.player_2).input);
}

test "should capture input correctly in T8" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&gm(.{
        .player_1 = &.{
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
            .input_side = .right,
        },
        .player_2 = &.{
            .directional_input = .{ .down = .down_back },
            .attack_input = .{ .down = .{
                .button_1 = true,
                .button_2 = false,
                .button_3 = true,
                .button_4 = false,
                .heat = true,
                .special_style = false,
                .rage = true,
            } },
            .input_side = .left,
        },
    }));
    try testing.expectEqual(model.Input{
        .forward = false,
        .back = true,
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
    try testing.expectEqual(model.Input{
        .forward = false,
        .back = true,
        .up = false,
        .down = true,
        .left = true,
        .right = false,
        .button_1 = true,
        .button_2 = false,
        .button_3 = true,
        .button_4 = false,
        .special_style = false,
        .rage = true,
        .heat = true,
    }, frame.getPlayerById(.player_2).input);
}

test "should capture forward/back correctly depending on the input side" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};

    const frame_1 = capturer.captureFrame(&gm(.{
        .player_1 = &.{ .input = .{ .right = true }, .input_side = .left },
        .player_2 = &.{ .input = .{ .right = true }, .input_side = .right },
    }));
    try testing.expect(frame_1.getPlayerById(.player_1).input != null);
    try testing.expect(frame_1.getPlayerById(.player_2).input != null);
    try testing.expectEqual(true, frame_1.getPlayerById(.player_1).input.?.forward);
    try testing.expectEqual(false, frame_1.getPlayerById(.player_1).input.?.back);
    try testing.expectEqual(false, frame_1.getPlayerById(.player_2).input.?.forward);
    try testing.expectEqual(true, frame_1.getPlayerById(.player_2).input.?.back);

    const frame_2 = capturer.captureFrame(&gm(.{
        .player_1 = &.{ .input = .{ .left = true }, .input_side = .left },
        .player_2 = &.{ .input = .{ .left = true }, .input_side = .right },
    }));
    try testing.expect(frame_2.getPlayerById(.player_1).input != null);
    try testing.expect(frame_2.getPlayerById(.player_2).input != null);
    try testing.expectEqual(false, frame_2.getPlayerById(.player_1).input.?.forward);
    try testing.expectEqual(true, frame_2.getPlayerById(.player_1).input.?.back);
    try testing.expectEqual(true, frame_2.getPlayerById(.player_2).input.?.forward);
    try testing.expectEqual(false, frame_2.getPlayerById(.player_2).input.?.back);

    const frame_3 = capturer.captureFrame(&gm(.{
        .player_1 = &.{ .input = .{ .right = true }, .input_side = .right },
        .player_2 = &.{ .input = .{ .right = true }, .input_side = .left },
    }));
    try testing.expect(frame_3.getPlayerById(.player_1).input != null);
    try testing.expect(frame_3.getPlayerById(.player_2).input != null);
    try testing.expectEqual(false, frame_3.getPlayerById(.player_1).input.?.forward);
    try testing.expectEqual(true, frame_3.getPlayerById(.player_1).input.?.back);
    try testing.expectEqual(true, frame_3.getPlayerById(.player_2).input.?.forward);
    try testing.expectEqual(false, frame_3.getPlayerById(.player_2).input.?.back);

    const frame_4 = capturer.captureFrame(&gm(.{
        .player_1 = &.{ .input = .{ .left = true }, .input_side = .right },
        .player_2 = &.{ .input = .{ .left = true }, .input_side = .left },
    }));
    try testing.expect(frame_4.getPlayerById(.player_1).input != null);
    try testing.expect(frame_4.getPlayerById(.player_2).input != null);
    try testing.expectEqual(true, frame_4.getPlayerById(.player_1).input.?.forward);
    try testing.expectEqual(false, frame_4.getPlayerById(.player_1).input.?.back);
    try testing.expectEqual(false, frame_4.getPlayerById(.player_2).input.?.forward);
    try testing.expectEqual(true, frame_4.getPlayerById(.player_2).input.?.back);
}

test "should capture health correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame_2 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .health = .fromConverted(.{
                .value = 123,
                .encryption_key = 0xBD20A1539B61342F,
            }),
        },
        .player_2 = null,
    }));
    try testing.expectEqual(123, frame_2.getPlayerById(.player_1).health);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_2).health);
}

test "should capture health recover limit correctly in T7" {
    const gm = game.Memory(.t7).testingInit;
    var capturer = Capturer(.t7){};
    const frame_2 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .health = .fromConverted(.{
                .value = 123,
                .encryption_key = 0xBD20A1539B61342F,
            }),
        },
        .player_2 = null,
    }));
    try testing.expectEqual(123, frame_2.getPlayerById(.player_1).health_recover_limit);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_2).health_recover_limit);
}

test "should capture health recover limit correctly in T8" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame_2 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .health_recover_limit = .fromConverted(.{
                .value = 123,
                .encryption_key = 0xBD20A1539B61342F,
            }),
        },
        .player_2 = null,
    }));
    try testing.expectEqual(123, frame_2.getPlayerById(.player_1).health_recover_limit);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_2).health_recover_limit);
}

test "should capture max health correctly in T7" {
    const gm = game.Memory(.t7).testingInit;
    var capturer = Capturer(.t7){};
    const frame_2 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .max_health = .fromConverted(123),
        },
        .player_2 = null,
    }));
    try testing.expectEqual(123, frame_2.getPlayerById(.player_1).max_health);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_2).max_health);
}

test "should capture max health correctly in T8" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame_2 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .max_health = .fromConverted(.{
                .value = 123,
                .encryption_key = 0xBD20A1539B61342F,
            }),
        },
        .player_2 = null,
    }));
    try testing.expectEqual(123, frame_2.getPlayerById(.player_1).max_health);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_2).max_health);
}

test "should capture rage correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};

    const frame_1 = capturer.captureFrame(&gm(.{
        .player_1 = &.{ .in_rage = .false, .frames_since_round_start = 100 },
        .player_2 = &.{ .in_rage = .true, .frames_since_round_start = 100 },
    }));
    try testing.expectEqual(.available, frame_1.getPlayerById(.player_1).rage);
    try testing.expectEqual(.activated, frame_1.getPlayerById(.player_2).rage);

    const frame_2 = capturer.captureFrame(&gm(.{
        .player_1 = &.{ .in_rage = .false, .frames_since_round_start = 101 },
        .player_2 = &.{ .in_rage = .false, .frames_since_round_start = 101 },
    }));
    try testing.expectEqual(.available, frame_2.getPlayerById(.player_1).rage);
    try testing.expectEqual(.used_up, frame_2.getPlayerById(.player_2).rage);

    const frame_3 = capturer.captureFrame(&gm(.{
        .player_1 = &.{ .in_rage = .true, .frames_since_round_start = 100 },
        .player_2 = &.{ .in_rage = .false, .frames_since_round_start = 100 },
    }));
    try testing.expectEqual(.activated, frame_3.getPlayerById(.player_1).rage);
    try testing.expectEqual(.available, frame_3.getPlayerById(.player_2).rage);

    const frame_4 = capturer.captureFrame(&gm(.{
        .player_1 = null,
        .player_2 = null,
    }));
    try testing.expectEqual(null, frame_4.getPlayerById(.player_1).rage);
    try testing.expectEqual(null, frame_4.getPlayerById(.player_2).rage);
}

test "should capture heat correctly in T7" {
    const gm = game.Memory(.t7).testingInit;
    var capturer = Capturer(.t7){};
    const frame = capturer.captureFrame(&gm(.{
        .player_1 = &.{},
        .player_2 = null,
    }));
    try testing.expectEqual(.used_up, frame.getPlayerById(.player_1).heat);
    try testing.expectEqual(.used_up, frame.getPlayerById(.player_2).heat);
}

test "should capture heat correctly in T8" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame_1 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .in_heat = .false,
            .used_heat = .false,
            .heat_gauge = .fromConverted(0.5),
        },
        .player_2 = &.{
            .in_heat = .true,
            .used_heat = .false,
            .heat_gauge = .fromConverted(0.5),
        },
    }));
    const frame_2 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .in_heat = .false,
            .used_heat = .true,
            .heat_gauge = .fromConverted(0.5),
        },
        .player_2 = null,
    }));
    try testing.expectEqual(.available, frame_1.getPlayerById(.player_1).heat);
    try testing.expectEqual(
        model.Heat{ .activated = .{ .gauge = 0.5 } },
        frame_1.getPlayerById(.player_2).heat,
    );
    try testing.expectEqual(.used_up, frame_2.getPlayerById(.player_1).heat);
    try testing.expectEqual(null, frame_2.getPlayerById(.player_2).heat);
}

test "should capture player rotation correctly" {
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .rotation = .fromConverted(0.75 * std.math.pi),
        },
        .player_2 = null,
    }));
    try testing.expect(frame.getPlayerById(.player_1).rotation != null);
    try testing.expectApproxEqAbs(0.75 * std.math.pi, frame.getPlayerById(.player_1).rotation.?, 0.0001);
    try testing.expectEqual(null, frame.getPlayerById(.player_2).rotation);
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
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&gm(.{
        .player_1 = &.{
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
        .player_2 = null,
    }));

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
    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};
    const frame = capturer.captureFrame(&gm(.{
        .player_1 = &.{
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
        .player_2 = null,
    }));

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

    const gm = game.Memory(.t7).testingInit;
    var capturer = Capturer(.t7){};

    const frame_1 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .animation_frame = 1,
            .animation = .fromPointer(&.{
                .active_start = 2,
                .active_end = 3,
            }),
            .hit_lines = .{
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
            },
        },
        .player_2 = &.{
            .animation_frame = 4,
            .animation = .fromPointer(&.{
                .active_start = 2,
                .active_end = 3,
            }),
            .hit_lines = .{
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
            },
        },
    }));
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_1.getPlayerById(.player_1).hit_lines.asSlice());
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_1.getPlayerById(.player_2).hit_lines.asSlice());

    const frame_2 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .animation_frame = 2,
            .animation = .fromPointer(&.{
                .active_start = 2,
                .active_end = 3,
            }),
            .hit_lines = .{
                point(.{ 1, 2, 3 }),
                point(.{ 4, 5, 6 }),
                point(.{ 7, 8, 9 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
            },
        },
        .player_2 = &.{
            .animation_frame = 3,
            .animation = .fromPointer(&.{
                .active_start = 2,
                .active_end = 3,
            }),
            .hit_lines = .{
                point(.{ 10, 11, 12 }),
                point(.{ 13, 14, 15 }),
                point(.{ 16, 17, 18 }),
                point(.{ 19, 20, 21 }),
                point(.{ 0, 0, 0 }),
                point(.{ 0, 0, 0 }),
            },
        },
    }));
    try testing.expectEqualSlices(model.HitLine, &.{
        line(.{ 4, 5, 6 }, .{ 7, 8, 9 }),
    }, frame_2.getPlayerById(.player_1).hit_lines.asSlice());
    try testing.expectEqualSlices(model.HitLine, &.{
        line(.{ 16, 17, 18 }, .{ 19, 20, 21 }),
        line(.{ 10, 11, 12 }, .{ 13, 14, 15 }),
    }, frame_2.getPlayerById(.player_2).hit_lines.asSlice());

    const frame_3 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .animation_frame = 1,
            .animation = .fromPointer(&.{
                .active_start = 2,
                .active_end = 3,
            }),
            .hit_lines = .{
                point(.{ 36, 35, 34 }),
                point(.{ 33, 32, 31 }),
                point(.{ 30, 29, 28 }),
                point(.{ 27, 26, 25 }),
                point(.{ 24, 23, 22 }),
                point(.{ 21, 20, 19 }),
            },
        },
        .player_2 = &.{
            .animation_frame = 2,
            .animation = .fromPointer(&.{
                .active_start = 2,
                .active_end = 3,
            }),
            .hit_lines = .{
                point(.{ 18, 17, 16 }),
                point(.{ 15, 14, 13 }),
                point(.{ 12, 11, 10 }),
                point(.{ 9, 8, 7 }),
                point(.{ 6, 5, 4 }),
                point(.{ 3, 2, 1 }),
            },
        },
    }));
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_3.getPlayerById(.player_1).hit_lines.asSlice());
    try testing.expectEqualSlices(model.HitLine, &.{
        line(.{ 6, 5, 4 }, .{ 3, 2, 1 }),
        line(.{ 12, 11, 10 }, .{ 9, 8, 7 }),
        line(.{ 18, 17, 16 }, .{ 15, 14, 13 }),
    }, frame_3.getPlayerById(.player_2).hit_lines.asSlice());

    const frame_4 = capturer.captureFrame(&gm(.{
        .player_1 = null,
        .player_2 = null,
    }));
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_4.getPlayerById(.player_1).hit_lines.asSlice());
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_4.getPlayerById(.player_2).hit_lines.asSlice());
}

test "should capture hit lines correctly in T8" {
    const hitLine = struct {
        fn call(points: [3][3]f32) @typeInfo(game.HitLines(.t8)).array.child {
            return .fromConverted(.{
                .points = .{
                    .{ .position = .fromArray(points[0]), ._padding = 0 },
                    .{ .position = .fromArray(points[1]), ._padding = 0 },
                    .{ .position = .fromArray(points[2]), ._padding = 0 },
                },
                ._padding_1 = undefined,
                .ignore = undefined,
                ._padding_2 = undefined,
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

    const gm = game.Memory(.t8).testingInit;
    var capturer = Capturer(.t8){};

    const frame_1 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .animation_frame = 1,
            .animation = .fromPointer(&.{
                .active_start = 2,
                .active_end = 3,
            }),
            .hit_lines = .{
                hitLine(.{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } }),
                hitLine(.{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } }),
                hitLine(.{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } }),
                hitLine(.{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } }),
            },
        },
        .player_2 = &.{
            .animation_frame = 1,
            .animation = .fromPointer(&.{
                .active_start = 0,
                .active_end = 0,
            }),
            .hit_lines = .{
                hitLine(.{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } }),
                hitLine(.{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } }),
                hitLine(.{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } }),
                hitLine(.{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } }),
            },
        },
    }));
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_1.getPlayerById(.player_1).hit_lines.asSlice());
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_1.getPlayerById(.player_2).hit_lines.asSlice());

    const frame_2 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .animation_frame = 2,
            .animation = .fromPointer(&.{
                .active_start = 2,
                .active_end = 3,
            }),
            .hit_lines = .{
                hitLine(.{ .{ 1, 2, 3 }, .{ 4, 5, 6 }, .{ 7, 8, 9 } }),
                hitLine(.{ .{ 10, 11, 12 }, .{ 13, 14, 15 }, .{ 16, 17, 18 } }),
                hitLine(.{ .{ 19, 20, 21 }, .{ 22, 23, 24 }, .{ 25, 26, 27 } }),
                hitLine(.{ .{ 28, 29, 30 }, .{ 31, 32, 33 }, .{ 34, 35, 36 } }),
            },
        },
        .player_2 = &.{
            .animation_frame = 1,
            .animation = .fromPointer(&.{
                .active_start = 2,
                .active_end = 3,
            }),
            .hit_lines = .{
                hitLine(.{ .{ 37, 38, 39 }, .{ 40, 41, 42 }, .{ 43, 44, 45 } }),
                hitLine(.{ .{ 46, 47, 48 }, .{ 49, 50, 51 }, .{ 52, 53, 54 } }),
                hitLine(.{ .{ 55, 56, 57 }, .{ 58, 59, 60 }, .{ 61, 62, 63 } }),
                hitLine(.{ .{ 64, 65, 66 }, .{ 67, 68, 69 }, .{ 70, 71, 72 } }),
            },
        },
    }));
    try testing.expectEqualSlices(model.HitLine, &.{
        line(.{ 1, 2, 3 }, .{ 4, 5, 6 }),
        line(.{ 4, 5, 6 }, .{ 7, 8, 9 }),
        line(.{ 10, 11, 12 }, .{ 13, 14, 15 }),
        line(.{ 13, 14, 15 }, .{ 16, 17, 18 }),
        line(.{ 19, 20, 21 }, .{ 22, 23, 24 }),
        line(.{ 22, 23, 24 }, .{ 25, 26, 27 }),
        line(.{ 28, 29, 30 }, .{ 31, 32, 33 }),
        line(.{ 31, 32, 33 }, .{ 34, 35, 36 }),
    }, frame_2.getPlayerById(.player_1).hit_lines.asSlice());
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_2.getPlayerById(.player_2).hit_lines.asSlice());

    const frame_3 = capturer.captureFrame(&gm(.{
        .player_1 = &.{
            .animation_frame = 3,
            .animation = .fromPointer(&.{
                .active_start = 2,
                .active_end = 3,
            }),
            .hit_lines = .{
                hitLine(.{ .{ 1000, 2, 3 }, .{ 4, 5, 6 }, .{ 7, 8, 9 } }),
                hitLine(.{ .{ 10, 11, 12 }, .{ 13, 14, 15 }, .{ 16, 17, 18 } }),
                hitLine(.{ .{ 19, 20, 21 }, .{ 22000, 23, 24 }, .{ 25, 26, 27 } }),
                hitLine(.{ .{ 28, 29, 30 }, .{ 31, 32, 33 }, .{ 34, 35, 36 } }),
            },
        },
        .player_2 = &.{
            .animation_frame = 2,
            .animation = .fromPointer(&.{
                .active_start = 2,
                .active_end = 3,
            }),
            .hit_lines = .{
                hitLine(.{ .{ 37, 38, 39 }, .{ 40, 41, 42 }, .{ 43, 44, 45 } }),
                hitLine(.{ .{ 46, 47, 48 }, .{ 49, 50, 51 }, .{ 52000, 53, 54 } }),
                hitLine(.{ .{ 55, 56, 57 }, .{ 58, 59, 60 }, .{ 61, 62, 63 } }),
                hitLine(.{ .{ 64000, 65, 66 }, .{ 67, 68, 69 }, .{ 70, 71, 72 } }),
            },
        },
    }));
    try testing.expectEqualSlices(model.HitLine, &.{
        line(.{ 1000, 2, 3 }, .{ 4, 5, 6 }),
        line(.{ 4, 5, 6 }, .{ 7, 8, 9 }),
        line(.{ 19, 20, 21 }, .{ 22000, 23, 24 }),
        line(.{ 22000, 23, 24 }, .{ 25, 26, 27 }),
    }, frame_3.getPlayerById(.player_1).hit_lines.asSlice());
    try testing.expectEqualSlices(model.HitLine, &.{
        line(.{ 46, 47, 48 }, .{ 49, 50, 51 }),
        line(.{ 49, 50, 51 }, .{ 52000, 53, 54 }),
        line(.{ 64000, 65, 66 }, .{ 67, 68, 69 }),
        line(.{ 67, 68, 69 }, .{ 70, 71, 72 }),
    }, frame_3.getPlayerById(.player_2).hit_lines.asSlice());

    const frame_4 = capturer.captureFrame(&gm(.{
        .player_1 = null,
        .player_2 = null,
    }));
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_4.getPlayerById(.player_1).hit_lines.asSlice());
    try testing.expectEqualSlices(model.HitLine, &.{}, frame_4.getPlayerById(.player_2).hit_lines.asSlice());
}

test "should capture walls correctly" {
    const pi = std.math.pi;
    const sqrt2 = std.math.sqrt2;
    const expectEqualWall = struct {
        fn call(expected: model.Wall, actual: model.Wall) !void {
            try testing.expectApproxEqAbs(expected.edge_1.x(), actual.edge_1.x(), 0.001);
            try testing.expectApproxEqAbs(expected.edge_1.y(), actual.edge_1.y(), 0.001);
            try testing.expectEqual(expected.edge_2_index, actual.edge_2_index);
            try testing.expectEqual(expected.properties, actual.properties);
        }
    }.call;

    const game_memory = game.Memory(.t8).testingInit(.{
        .unreal_classes = .{
            .photo_mode_wall = @ptrFromInt(0x456),
        },
        .player_1 = &.{ .stage_set_number = 0, .floor_number = 1 },
        .player_2 = &.{ .stage_set_number = 0, .floor_number = 1 },
        .player_starts = &.{
            .{
                .actor = .{ .root_component = .fromPointer(&.{
                    .relative_position = .fromConverted(.fromArray(.{ 300, 500, 0 })),
                }) },
                .stage_broken_history = 0b011,
                .floor_number = 1,
                .type = .game_start,
            },
            .{
                .actor = .{ .root_component = .fromPointer(&.{
                    .relative_position = .fromConverted(.fromArray(.{ 1000, 500, 0 })),
                }) },
                .stage_broken_history = 0b001,
                .floor_number = 1,
                .type = .game_start,
            },
            .{
                .actor = .{ .root_component = .fromPointer(&.{
                    .relative_position = .fromConverted(.fromArray(.{ 1700, 500, 0 })),
                }) },
                .stage_broken_history = 0b101,
                .floor_number = 1,
                .type = .game_start,
            },
            .{
                .actor = .{ .root_component = .fromPointer(&.{
                    .relative_position = .fromConverted(.fromArray(.{ 900, 1200, 0 })),
                }) },
                .stage_broken_history = 0b000,
                .floor_number = 0,
                .type = .game_start,
            },
            .{
                .actor = .{ .root_component = .fromPointer(&.{
                    .relative_position = .fromConverted(.fromArray(.{ 1100, 1200, 0 })),
                }) },
                .stage_broken_history = 0b000,
                .floor_number = 1,
                .type = .drama_start,
            },
        },
        .walls = &.{
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 2000, 500, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 2, 16, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = true },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .destruction_level = 0,
                .wall_attribute = .{
                    .wall_break = true,
                    .balcony_break = true,
                    .wall_blast = true,
                },
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 1900, 900, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, -0.25 * pi, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 7 * sqrt2, sqrt2, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = true },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .destruction_level = 0,
                .wall_attribute = .{},
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 1700, 1000, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 12, 2, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = true },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .destruction_level = 0,
                .wall_attribute = .{},
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 1000, 1000, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 4, 2, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = true },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .destruction_level = 0,
                .wall_attribute = .{
                    .wall_blast = true,
                },
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 300, 1000, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 12, 2, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = true },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .destruction_level = 0,
                .wall_attribute = .{},
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 100, 900, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0.25 * pi, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 7 * sqrt2, sqrt2, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = true },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .destruction_level = 0,
                .wall_attribute = .{},
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 0, 500, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 2, 16, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = true },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .destruction_level = 0,
                .wall_attribute = .{},
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 0, 500, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0.25 * pi, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 2 * sqrt2, 2 * sqrt2, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = true },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .destruction_level = 0,
                .wall_attribute = .{},
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 100, 100, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, -0.25 * pi, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 7 * sqrt2, sqrt2, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = true },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .destruction_level = 0,
                .wall_attribute = .{
                    .wall_bound = true,
                },
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 300, 0, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 12, 2, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = true },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .destruction_level = 0,
                .wall_attribute = .{},
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 1000, 0, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 12, 2, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = true },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .destruction_level = 0,
                .wall_attribute = .{},
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 1700, 0, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 12, 2, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = true },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .destruction_level = 0,
                .wall_attribute = .{},
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 1900, 100, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0.25 * pi, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 7 * sqrt2, sqrt2, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = true },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .destruction_level = 0,
                .wall_attribute = .{},
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 600, 500, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 2, 14, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = true },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .destruction_level = 0,
                .wall_attribute = .{
                    .wall_break = true,
                    .hard = true,
                },
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 1400, 500, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 2, 14, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = false },
                },
                .state = .end,
                .set_number = 0,
                .floor_number = 1,
                .destruction_level = 1,
                .wall_attribute = .{
                    .wall_break = true,
                },
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x456),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 500, 500, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 1, 16, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = false },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .destruction_level = 0,
                .wall_attribute = .{},
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 700, 500, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 1, 16, 0 })),
                    }),
                    .hidden_polaris = .{ .value = true },
                    .collision_enabled = .{ .value = false },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .destruction_level = 0,
                .wall_attribute = .{},
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 900, 500, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 1, 16, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = false },
                },
                .state = .init,
                .set_number = 0,
                .floor_number = 1,
                .destruction_level = 0,
                .wall_attribute = .{},
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 1100, 500, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 1, 16, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = false },
                },
                .state = .main,
                .set_number = 1,
                .floor_number = 1,
                .destruction_level = 0,
                .wall_attribute = .{},
            },
            .{
                .actor = .{
                    .class = @ptrFromInt(0x123),
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 1300, 500, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 1, 16, 0 })),
                    }),
                    .hidden_polaris = .{ .value = false },
                    .collision_enabled = .{ .value = false },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 0,
                .destruction_level = 0,
                .wall_attribute = .{},
            },
        },
    });

    var capturer = Capturer(.t8){};
    const walls = capturer.captureFrame(&game_memory).walls.asSlice();

    try testing.expectEqual(17, walls.len);
    try expectEqualWall(model.Wall{
        .edge_1 = .fromArray(.{ 1900, 800 }),
        .edge_2_index = 1,
        .properties = .{},
    }, walls[0]);
    try expectEqualWall(model.Wall{
        .edge_1 = .fromArray(.{ 1800, 900 }),
        .edge_2_index = 2,
        .properties = .{},
    }, walls[1]);
    try expectEqualWall(model.Wall{
        .edge_1 = .fromArray(.{ 1300, 900 }),
        .edge_2_index = 3,
        .properties = .{},
    }, walls[2]);
    try expectEqualWall(model.Wall{
        .edge_1 = .fromArray(.{ 1200, 900 }),
        .edge_2_index = 4,
        .properties = .{ .gimmick = .wall_blast },
    }, walls[3]);
    try expectEqualWall(model.Wall{
        .edge_1 = .fromArray(.{ 800, 900 }),
        .edge_2_index = 5,
        .properties = .{},
    }, walls[4]);
    try expectEqualWall(model.Wall{
        .edge_1 = .fromArray(.{ 200, 900 }),
        .edge_2_index = 6,
        .properties = .{},
    }, walls[5]);
    try expectEqualWall(model.Wall{
        .edge_1 = .fromArray(.{ 100, 800 }),
        .edge_2_index = 7,
        .properties = .{},
    }, walls[6]);
    try expectEqualWall(model.Wall{
        .edge_1 = .fromArray(.{ 100, 600 }),
        .edge_2_index = 8,
        .properties = .{},
    }, walls[7]);
    try expectEqualWall(model.Wall{
        .edge_1 = .fromArray(.{ 200, 500 }),
        .edge_2_index = 9,
        .properties = .{},
    }, walls[8]);
    try expectEqualWall(model.Wall{
        .edge_1 = .fromArray(.{ 100, 400 }),
        .edge_2_index = 10,
        .properties = .{},
    }, walls[9]);
    try expectEqualWall(model.Wall{
        .edge_1 = .fromArray(.{ 100, 200 }),
        .edge_2_index = 11,
        .properties = .{ .gimmick = .wall_bound },
    }, walls[10]);
    try expectEqualWall(model.Wall{
        .edge_1 = .fromArray(.{ 200, 100 }),
        .edge_2_index = 12,
        .properties = .{},
    }, walls[11]);
    try expectEqualWall(model.Wall{
        .edge_1 = .fromArray(.{ 700, 100 }),
        .edge_2_index = 13,
        .properties = .{},
    }, walls[12]);
    try expectEqualWall(model.Wall{
        .edge_1 = .fromArray(.{ 1800, 100 }),
        .edge_2_index = 14,
        .properties = .{},
    }, walls[13]);
    try expectEqualWall(model.Wall{
        .edge_1 = .fromArray(.{ 1900, 200 }),
        .edge_2_index = 0,
        .properties = .{ .gimmick = .balcony_break },
    }, walls[14]);
    try expectEqualWall(model.Wall{
        .edge_1 = .fromArray(.{ 700, 900 }),
        .edge_2_index = 12,
        .properties = .{
            .gimmick = .wall_break,
            .flags = .{ .hard = true },
        },
    }, walls[15]);
    try expectEqualWall(model.Wall{
        .edge_1 = .fromArray(.{ 1300, 100 }),
        .edge_2_index = 2,
        .properties = .{
            .gimmick = .wall_break,
            .flags = .{
                .damaged = true,
                .gimmick_used_up = true,
                .broken = true,
            },
        },
    }, walls[16]);
}

test "should capture floor gimmicks correctly in T8" {
    const game_memory = game.Memory(.t8).testingInit(.{
        .player_1 = &.{ .stage_set_number = 0, .floor_number = 1 },
        .player_2 = &.{ .stage_set_number = 0, .floor_number = 1 },
        .floors = &.{
            .{
                .actor = .{
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fill(0)),
                        .relative_rotation = .fromConverted(.fill(0)),
                        .relative_scale = .fromConverted(.fill(0)),
                    }),
                    .hidden_polaris = .{ .value = false },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .is_hard = .false,
                .destruction_level = 0,
                .is_breakable = .false,
                .is_floor_blast = .false,
            },
            .{
                .actor = .{
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fill(1)),
                        .relative_rotation = .fromConverted(.fill(1)),
                        .relative_scale = .fromConverted(.fill(1)),
                    }),
                    .hidden_polaris = .{ .value = false },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .is_hard = .false,
                .destruction_level = 0,
                .is_breakable = .true,
                .is_floor_blast = .false,
            },
            .{
                .actor = .{
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fill(2)),
                        .relative_rotation = .fromConverted(.fill(2)),
                        .relative_scale = .fromConverted(.fill(2)),
                    }),
                    .hidden_polaris = .{ .value = false },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .is_hard = .false,
                .destruction_level = 0,
                .is_breakable = .false,
                .is_floor_blast = .true,
            },
            .{
                .actor = .{
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fill(3)),
                        .relative_rotation = .fromConverted(.fill(3)),
                        .relative_scale = .fromConverted(.fill(3)),
                    }),
                    .hidden_polaris = .{ .value = false },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .is_hard = .false,
                .destruction_level = 1,
                .is_breakable = .false,
                .is_floor_blast = .true,
            },
            .{
                .actor = .{
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fill(4)),
                        .relative_rotation = .fromConverted(.fill(4)),
                        .relative_scale = .fromConverted(.fill(4)),
                    }),
                    .hidden_polaris = .{ .value = false },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .is_hard = .true,
                .destruction_level = 1,
                .is_breakable = .false,
                .is_floor_blast = .true,
            },
            .{
                .actor = .{
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fill(5)),
                        .relative_rotation = .fromConverted(.fill(5)),
                        .relative_scale = .fromConverted(.fill(5)),
                    }),
                    .hidden_polaris = .{ .value = false },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .is_hard = .true,
                .destruction_level = 2,
                .is_breakable = .false,
                .is_floor_blast = .true,
            },
            .{
                .actor = .{
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fill(6)),
                        .relative_rotation = .fromConverted(.fill(6)),
                        .relative_scale = .fromConverted(.fill(6)),
                    }),
                    .hidden_polaris = .{ .value = true },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 1,
                .is_hard = .false,
                .destruction_level = 0,
                .is_breakable = .true,
                .is_floor_blast = .false,
            },
            .{
                .actor = .{
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fill(7)),
                        .relative_rotation = .fromConverted(.fill(7)),
                        .relative_scale = .fromConverted(.fill(7)),
                    }),
                    .hidden_polaris = .{ .value = false },
                },
                .state = .init,
                .set_number = 0,
                .floor_number = 1,
                .is_hard = .false,
                .destruction_level = 0,
                .is_breakable = .true,
                .is_floor_blast = .false,
            },
            .{
                .actor = .{
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fill(8)),
                        .relative_rotation = .fromConverted(.fill(8)),
                        .relative_scale = .fromConverted(.fill(8)),
                    }),
                    .hidden_polaris = .{ .value = false },
                },
                .state = .main,
                .set_number = 1,
                .floor_number = 1,
                .is_hard = .false,
                .destruction_level = 0,
                .is_breakable = .true,
                .is_floor_blast = .false,
            },
            .{
                .actor = .{
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fill(9)),
                        .relative_rotation = .fromConverted(.fill(9)),
                        .relative_scale = .fromConverted(.fill(9)),
                    }),
                    .hidden_polaris = .{ .value = false },
                },
                .state = .main,
                .set_number = 0,
                .floor_number = 0,
                .is_hard = .false,
                .destruction_level = 0,
                .is_breakable = .true,
                .is_floor_blast = .false,
            },
        },
    });

    var capturer = Capturer(.t8){};
    const gimmicks = capturer.captureFrame(&game_memory).floor_gimmicks.asSlice();

    try testing.expectEqual(5, gimmicks.len);
    try testing.expectEqual(model.FloorGimmick{
        .rectangle = .{
            .center = .fill(1),
            .half_size = .fill(50),
            .rotation = 1,
        },
        .properties = .{
            .type = .floor_break,
            .flags = .{},
        },
    }, gimmicks[0]);
    try testing.expectEqual(model.FloorGimmick{
        .rectangle = .{
            .center = .fill(2),
            .half_size = .fill(100),
            .rotation = 2,
        },
        .properties = .{
            .type = .floor_blast,
            .flags = .{},
        },
    }, gimmicks[1]);
    try testing.expectEqual(model.FloorGimmick{
        .rectangle = .{
            .center = .fill(3),
            .half_size = .fill(150),
            .rotation = 3,
        },
        .properties = .{
            .type = .floor_blast,
            .flags = .{
                .damaged = true,
                .used_up = true,
            },
        },
    }, gimmicks[2]);
    try testing.expectEqual(model.FloorGimmick{
        .rectangle = .{
            .center = .fill(4),
            .half_size = .fill(200),
            .rotation = 4,
        },
        .properties = .{
            .type = .floor_blast,
            .flags = .{
                .hard = true,
                .damaged = true,
            },
        },
    }, gimmicks[3]);
    try testing.expectEqual(model.FloorGimmick{
        .rectangle = .{
            .center = .fill(5),
            .half_size = .fill(250),
            .rotation = 5,
        },
        .properties = .{
            .type = .floor_blast,
            .flags = .{
                .hard = true,
                .damaged = true,
                .used_up = true,
            },
        },
    }, gimmicks[4]);
}

test "should capture floor gimmicks correctly in T7" {
    const game_memory = game.Memory(.t7).testingInit(.{
        .player_1 = &.{ .floor_number = 1 },
        .player_2 = &.{ .floor_number = 1 },
        .player_starts = &.{
            .{
                .actor = .{ .root_component = .fromPointer(&.{
                    .relative_position = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                }) },
                .floor_number = 1,
                .type = .game_start,
            },
        },
        .walls = &.{
            .{
                .actor = .{
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 228, 0, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 1, 1000, 0 })),
                    }),
                    .collision_enabled = .{ .value = true },
                },
                .floor_number = 1,
            },
            .{
                .actor = .{
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ -228, 0, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 1, 1000, 0 })),
                    }),
                    .collision_enabled = .{ .value = true },
                },
                .floor_number = 1,
            },
            .{
                .actor = .{
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 0, 228, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 1000, 1, 0 })),
                    }),
                    .collision_enabled = .{ .value = true },
                },
                .floor_number = 1,
            },
            .{
                .actor = .{
                    .root_component = .fromPointer(&.{
                        .relative_position = .fromConverted(.fromArray(.{ 0, -228, 0 })),
                        .relative_rotation = .fromConverted(.fromArray(.{ 0, 0, 0 })),
                        .relative_scale = .fromConverted(.fromArray(.{ 1000, 1, 0 })),
                    }),
                    .collision_enabled = .{ .value = true },
                },
                .floor_number = 1,
            },
        },
        .floors = &.{
            .{ .floor_number = 0, .is_breakable = .true },
            .{ .floor_number = 1, .is_breakable = .true },
            .{ .floor_number = 2, .is_breakable = .false },
        },
    });

    var capturer = Capturer(.t7){};
    const gimmicks = capturer.captureFrame(&game_memory).floor_gimmicks.asSlice();

    try testing.expectEqual(gimmicks.len, 1);
    try testing.expectApproxEqAbs(0, gimmicks[0].rectangle.center.x(), 0.0001);
    try testing.expectApproxEqAbs(0, gimmicks[0].rectangle.center.y(), 0.0001);
    try testing.expectApproxEqAbs(100, gimmicks[0].rectangle.half_size.x(), 0.0001);
    try testing.expectApproxEqAbs(100, gimmicks[0].rectangle.half_size.y(), 0.0001);
    try testing.expectApproxEqAbs(0, gimmicks[0].rectangle.rotation, 0.0001);
    try testing.expectEqual(model.FloorGimmickType.floor_break, gimmicks[0].properties.type);
    try testing.expectEqual(model.FloorGimmickFlags{}, gimmicks[0].properties.flags);
}
