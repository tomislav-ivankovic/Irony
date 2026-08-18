const std = @import("std");
const builtin = @import("builtin");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

pub const Details = struct {
    irony_version: Row(
        "Irony Version",
        \\Version of Irony that data was recorded with.
        \\Can be used to check what version of Irony was used to record old recordings.
        \\If blank, the data was recorded by version of Irony older then 2.4.0.
    ,
        model.IronyVersion,
        null,
        drawIronyVersion,
    ) = .{},
    game: Row(
        "Game",
        \\Game that the data was recorded from.
        \\You can open recordings of T8 inside T7 and recordings of T7 inside T8.
        \\If blank, the data was recorded by version of Irony older then 2.4.0.
    ,
        model.Game,
        null,
        drawGame,
    ) = .{},
    game_version: Row(
        "Game Version",
        \\Version of the game that the data was recorded from.
        \\Can be used to check what the version the game was when an old recording was recorded.
        \\If blank, Irony failed to read the game version or data was recorded by version of Irony older then 2.4.0.
    ,
        model.GameVersion,
        .empty,
        drawGameVersion,
    ) = .{},
    source: Row(
        "Source",
        \\One of the following:
        \\Practice - Data was recorded inside practice mode.
        \\Live Game - Data was recorded while a live match was played.
        \\Replay Loading - Data was recorded during the fast game simulation while a replay was loading.
        \\Replay Playback - Data was recorded from a manual playback of a already loaded replay.
    ,
        model.Source,
        null,
        drawSource,
    ) = .{},
    match_phase: Row(
        "Match Phase",
        \\One of the following:
        \\Not In Match - Not inside a match. Most commonly in practice mode.
        \\Intro - Game is playing the character intro animations. The match is beginning.
        \\Outro - Game is playing the character outro or match draw animation. The match is ending.
        \\Round Start - Starting part of the round where the characters are unable to interact.
        \\Round End - Ending part of the round where the winner of the round is already decided.
        \\Mid Round - Main part of the round where the characters are fighting.
        \\In Between Rounds - Game is playing a stage transformation cinematic in between two rounds.
    ,
        model.MatchPhase,
        null,
        drawMatchPhase,
    ) = .{},
    frames_since_round_start: Row(
        "Since Round Start",
        \\Number of frames that passed since round start.
        \\Does not increase beyond 65535.
    ,
        u32,
        null,
        drawU32,
    ) = .{},
    frames_left_in_round: Row(
        "Frames Left In Round",
        \\Number of frames left before the round clock hits zero.
        \\Can freeze during rage arts.
    ,
        u32,
        null,
        drawU32,
    ) = .{},
    player_name: Row(
        "Player Name",
        \\Name of the player.
    ,
        model.PlayerName,
        .empty,
        drawPlayerName,
    ) = .{},
    rounds_won: Row(
        "Rounds Won",
        \\Number of rounds that the player won in the current match.
    ,
        u32,
        null,
        drawU32,
    ) = .{},
    rounds_needed_to_win: Row(
        "Rounds Needed To Win",
        \\Number of rounds that the player needs to win to win the current match.
    ,
        u32,
        null,
        drawU32,
    ) = .{},
    health: Row(
        "Health",
        "Health points that keep the player in the fight.",
        u32,
        null,
        drawU32,
    ) = .{},
    recoverable_health: Row(
        "Recoverable Health",
        "Health points that the player can recover.",
        u32,
        null,
        drawU32,
    ) = .{},
    health_recover_limit: Row(
        "Health Recover Limit",
        "Limit to health points that the player can reach by recovering all recoverable health.",
        u32,
        null,
        drawU32,
    ) = .{},
    max_health: Row(
        "Max Health",
        "Health points that the player has when the health bar is full.",
        u32,
        null,
        drawU32,
    ) = .{},
    rage: Row(
        "Rage",
        \\One of the following:
        \\Available - Rage not active but can get activated once player's health drops low enough.
        \\Activated - Player's health dropped low enough to activate rage, but player did not use rage art yet.
        \\Used Up - Player previously used rage art and therefor can no longer enter rage in this round.
    ,
        model.Rage,
        null,
        drawRage,
    ) = .{},
    heat: Row(
        "Heat",
        \\One of the following:
        \\Available - Heat not yet activated but can get activated with a heat burst or heat engager.
        \\Activated - Player is currently in heat. The amount of heat bar remaining is displayed as a percentage.
        \\Used Up - Heat already used up and player can no longer enter heat in this round.
    ,
        model.Heat,
        null,
        drawHeat,
    ) = .{},
    character_id: Row(
        "Character ID",
        "ID of the character that the player is currently playing.",
        u32,
        null,
        drawU32,
    ) = .{},
    animation_id: Row(
        "Animation ID",
        "ID of the animation that the character is currently performing.",
        u32,
        null,
        drawU32,
    ) = .{},
    animation_frame: Row(
        "Animation Frame",
        \\Index of the currently playing frame inside the current animation.
        \\Usually, gets set to 1 at the start of a new animation and increases by 1 each frame.
        \\However, there are situations where the game can freeze animations.
        \\This results in this number not increasing during that freeze.
    ,
        u32,
        null,
        drawU32,
    ) = .{},
    animation_total_frames: Row(
        "Animation Total Frames",
        \\For most animations, this number indicates the last frame of the animation.
        \\For some animations, the "Animation Frame" can go above this number.
        \\This happens when the player is in recovery state, but has delayed recovery because of not holding back.
        \\As soon as player does any input from this state, the game will transition to the next animation.
    ,
        u32,
        null,
        drawU32,
    ) = .{},
    move_phase: Row(
        "Move Phase",
        \\One of the following:
        \\Neutral - Moving freely.
        \\Start Up - Attack is winding up. Getting hit results in getting counter-hit.
        \\Active - Game is currently checking hit line hurt cylinder intersections.
        \\Active Recovery - Active frame that got turned into recovery because of the attack already connecting.
        \\Recovery - Move is cooling down. Player is unable to interact until recovery ends.
    ,
        model.MovePhase,
        null,
        drawMovePhase,
    ) = .{},
    move_frame: Row(
        "Move Frame",
        \\In most situations, same as "Animation Frame".
        \\However, in situations where the game freezes ether player's animation, this number stops increasing in value.
        \\This causes the value to diverge from "Animation Frame", but makes the value better for frame data math.
    ,
        u32,
        null,
        drawU32,
    ) = .{},
    startup_frames: Row(
        "Startup Frames",
        \\Number of frames that the current attack is in start up phase.
        \\Frames in which ether player's animation is frozen are not counted in this value.
        \\The value outside brackets indicates the startup frames in the current interaction.
        \\The values inside brackets indicate the minimum and maximum possible startup frames for the current attack.
    ,
        model.U32ActualMinMax,
        .nulls,
        drawU32ActualMinMax,
    ) = .{},
    active_frames: Row(
        "Active Frames",
        \\Number of frames that the current attack is in active phase.
        \\The value outside brackets indicates the active frames in the current interaction.
        \\The values inside brackets indicate the minimum and maximum possible active frames for the current attack.
    ,
        model.U32ActualMax,
        .nulls,
        drawU32ActualMax,
    ) = .{},
    recovery_frames: Row(
        "Recovery Frames",
        \\Number of frames that the current move is in recovery phase.
        \\Frames in which ether player's animation is frozen are not counted in this value.
        \\The value outside brackets indicates the recovery frames in the current interaction.
        \\The values inside brackets indicate the minimum and maximum possible recovery frames for the current move.
    ,
        model.U32ActualMinMax,
        .nulls,
        drawU32ActualMinMax,
    ) = .{},
    total_frames: Row(
        "Total Frames",
        \\For most moves, same as "Total Animation Frame".
        \\However, frames in which ether player's animation is frozen are not counted in this value.
        \\This causes the value to diverge from "Total Animation Frame", but makes the value better for frame data math.
    ,
        u32,
        null,
        drawU32,
    ) = .{},
    frame_advantage: Row(
        "Frame Advantage",
        \\Difference of recovery time in frames between the player and his opponent.
        \\Positive value indicates the player recovering sooner then the opponent.
        \\Negative value indicates the opponent recovering sooner then the player.
        \\Zero indicates simultaneous recovery.
        \\The value outside brackets indicates the frame advantage in the current interaction.
        \\The values inside brackets indicate the minimum and maximum possible frame advantage for the current move.
    ,
        model.I32ActualMinMax,
        .nulls,
        drawI32ActualMinMax,
    ) = .{},
    attack_type: Row(
        "Attack Type",
        \\One of the following:
        \\High - Blocked by standing guard. Crushed by crouching.
        \\Mid - Blocked by standing guard. Hits crouching guard.
        \\Low - Hits standing guard. Blocked by crouching guard. Low-crushable.
        \\Special Low - Blocked by standing guard. Blocked by crouching guard. Low-crushable.
        \\Unblockable High - Hits standing guard. Crushed by crouching.
        \\Unblockable Mid - Hits standing guard. Hits crouching guard.
        \\Unblockable Low - Hits standing guard. Hits crouching guard. Low-crushable.
        \\Throw - Appears during throw animations, after the active frames of the throw.
        \\Projectile - Not sure how this works.
        \\Anti-Air Only - Only hits airborne targets. Everything else crushes it.
    ,
        model.AttackType,
        .not_attack,
        drawAttackType,
    ) = .{},
    attack_range: Row(
        "Attack Range [m]",
        \\Distance between the most exposed point on player's hurt cylinders taken 1 frame before the start of the
        \\attack animation and the furthest reaching point on attack's hit lines.
        \\Everything is first projected to the line that points in the direction the player is looking at at the first
        \\frame of attack animation. The distance is then measured on that projection line.
    ,
        f32,
        null,
        drawF32Div100,
    ) = .{},
    attack_height: Row(
        "Attack Height [cm]",
        "Distances from the floor to the lowest and highest points of attack hit lines in the current move.",
        model.F32MinMax,
        .nulls,
        drawF32MinMax,
    ) = .{},
    recovery_range: Row(
        "Recovery Range [m]",
        \\Distance between the furthest reaching point on attack's hit lines and the most exposed point on player's
        \\hurt cylinders taken at the last recovery frame.
        \\Everything is first projected to the line that points in the direction the player was looking at at the first
        \\frame of attack animation. The distance is then measured on that projection line.
        \\Positive value indicates that the player recovered behind attack's hit lines.
        \\Negative value indicates that the player recovered in front of attack's hit lines.
    ,
        f32,
        null,
        drawF32Div100,
    ) = .{},
    hit_outcome: Row(
        "Hit Outcome",
        "Outcome of the hit line hurt cylinder interaction.",
        model.HitOutcome,
        .none,
        drawHitOutcome,
    ) = .{},
    combo_hits: Row(
        "Combo Hits",
        \\Number of hits landed during the current combo.
    ,
        u32,
        0,
        drawU32,
    ) = .{},
    combo_damage: Row(
        "Combo Damage",
        \\Damage inflicted on the opponent during the current combo.
    ,
        u32,
        0,
        drawU32,
    ) = .{},
    posture: Row(
        "Posture",
        \\One of the following:
        \\Standing - Can block mid and high attacks. Gets hit my lows attacks.
        \\Crouching - Can block low attacks. Gets hit my mid attacks. Crushes high attacks.
        \\Downed Face Up - Gets hit by mid and low attacks. Crushes high attacks.
        \\Downed Face Down - Gets hit by mid and low attacks. Crushes high attacks.
        \\Airborne - Getting hit results in getting floated. Does not necessarily crush low attacks.
    ,
        model.Posture,
        null,
        drawPosture,
    ) = .{},
    blocking: Row(
        "Blocking",
        \\One of the following:
        \\Not - Not blocking a single type of attack.
        \\Neutral Mids - Blocks some high, mid, and special low attacks.
        \\Fully Mids - Blocks all high, mid, and special low attacks.
        \\Neutral Lows - Blocks some low and special low attacks.
        \\Fully Lows - Blocks all low and special low attacks.
    ,
        model.Blocking,
        null,
        drawBlocking,
    ) = .{},
    crushing: Row(
        "Crushing",
        \\Zero, one or more of the following:
        \\Everything - Every attack is guaranteed to whiff. Player is invincible.
        \\Highs - High and unblockable high attacks are guaranteed to whiff.
        \\Lows - Low and unblockable low and special low attacks are guaranteed to whiff.
        \\Anti-Airs - Anti-air attacks are guaranteed to whiff.
        \\Power-Crushing - Absorbs non low and non throw attacks.
    ,
        model.Crushing,
        null,
        drawCrushing,
    ) = .{},
    can_interact: Row(
        "Can Interact",
        "Whether the player is able to influence the game simulation using inputs.",
        bool,
        null,
        drawYesNo,
    ) = .{},
    can_move: Row(
        "Can Move",
        "Whether the player is free to move using normal directional input.",
        bool,
        null,
        drawYesNo,
    ) = .{},
    throw_escape_phase: Row(
        "Throw Escape Phase",
        \\One of the following:
        \\In Escape Window - Player is able input buttons to escape the throw.
        \\Escape Success - Player succeeded in escaping the throw.
        \\Escape Fail - Player failed in escaping the throw.
    ,
        model.ThrowEscapePhase,
        null,
        drawThrowEscapePhase,
    ) = .{},
    correct_throw_escape: Row(
        "Correct Throw Escape",
        \\One of the following:
        \\1 - The current throw can be escaped by inputting only left punch.
        \\2 - The current throw can be escaped by inputting only right punch.
        \\1+2 - The current throw can be escaped by inputting left and right punch simultaneously.
        \\1 or 2 - The current throw can be escaped by inputting ether only left punch or only right punch.
    ,
        model.ThrowEscapeInputs,
        .{},
        drawThrowEscapeInputs,
    ) = .{},
    attempted_throw_escape: Row(
        "Attempted Throw Escape",
        \\One of the following:
        \\1 - Player attempted to escape the throw by inputting only left punch.
        \\2 - Player attempted to escape the throw by inputting only right punch.
        \\1+2 - Player attempted to escape the throw by inputting left and right punch simultaneously.
    ,
        model.ThrowEscapeInput,
        .none,
        drawThrowEscapeInput,
    ) = .{},
    throw_escape_attempt_timing: Row(
        "Throw Escape Attempt Timing",
        \\One of the following:
        \\On Time - Player inputted the escape attempt inside the escape window.
        \\Late - Player inputted the escape attempt after the escape window ended.
    ,
        model.ThrowEscapeTiming,
        null,
        drawThrowEscapeTiming,
    ) = .{},
    input: Row(
        "Input",
        \\Input that is being held down by the player at the current frame.
        \\Combination of following symbols:
        \\u - Up input.
        \\d - Down input.
        \\f - Forward input.
        \\b - Back input.
        \\1 - Left punch input.
        \\2 - Right punch input.
        \\3 - Left kick input.
        \\4 - Right kick input.
        \\SS - Special style input.
        \\H - Heat input.
        \\R - Rage input.
    ,
        model.Input,
        null,
        drawInput,
    ) = .{},
    distance_to_opponent: Row(
        "Distance To Opponent [m]",
        \\Distance between the most exposed points on player's and opponent's hurt cylinders.
        \\Both points are first projected to the line that connects player's and opponent's centroid floor projection.
        \\The distance is then measured on that projection line.
    ,
        f32,
        null,
        drawF32Div100,
    ) = .{},
    angle_to_opponent: Row(
        "Angle To Opponent [°]",
        \\Angle between the line that connects player's and opponent's centroid floor projections and opponent's
        \\look direction.
        \\Negative value indicates player being on the left side of the opponent.
        \\Positive value indicates player being on the right side of the opponent.
    ,
        f32,
        null,
        drawF32Degrees,
    ) = .{},
    distance_to_wall: Row(
        "Distance To Wall [m]",
        \\Distance between the player's centroid and the intersection point of the line that connects player's and
        \\opponent's centroid with the closest wall behind the player.
        \\Broken walls are ignored.
    ,
        f32,
        null,
        drawF32Div100,
    ) = .{},
    angle_to_wall: Row(
        "Angle To Wall [°]",
        \\Angle between the line that connects player's and opponent's centroid and the closest wall behind the player
        \\that intersects with that line.
        \\Negative value indicates wall being on the right side of the player.
        \\Positive value indicates wall being on the left side of the player.
        \\Broken walls are ignored.
    ,
        f32,
        null,
        drawF32Degrees,
    ) = .{},
    hit_lines_height: Row(
        "Hit Lines Height [cm]",
        "Distances from the floor to the lowest and highest points of player's hit lines in the current frame.",
        model.F32MinMax,
        .nulls,
        drawF32MinMax,
    ) = .{},
    hurt_cylinders_height: Row(
        "Hurt Cylinders Height [cm]",
        "Distances from the floor to the lowest and highest points of player's hurt cylinders in the current frame.",
        model.F32MinMax,
        .nulls,
        drawF32MinMax,
    ) = .{},

    const Self = @This();

    pub fn processFrame(self: *Self, settings: *const model.DetailsSettings, frame: *const model.Frame) void {
        const c1 = switch (settings.column_1) {
            .player_1 => frame.getPlayerById(.player_1),
            .player_2 => frame.getPlayerById(.player_2),
            .left_player => frame.getPlayerBySide(.left),
            .right_player => frame.getPlayerBySide(.right),
            .main_player => frame.getPlayerByRole(.main),
            .secondary_player => frame.getPlayerByRole(.secondary),
        };
        const c2 = switch (settings.column_2) {
            .player_1 => frame.getPlayerById(.player_1),
            .player_2 => frame.getPlayerById(.player_2),
            .left_player => frame.getPlayerBySide(.left),
            .right_player => frame.getPlayerBySide(.right),
            .main_player => frame.getPlayerByRole(.main),
            .secondary_player => frame.getPlayerByRole(.secondary),
        };
        const s = settings;
        self.irony_version.processFrame(s, frame.irony_version, frame.irony_version);
        self.game.processFrame(s, frame.game, frame.game);
        self.game_version.processFrame(s, frame.game_version, frame.game_version);
        self.source.processFrame(s, frame.source, frame.source);
        self.match_phase.processFrame(s, frame.match_phase, frame.match_phase);
        self.frames_since_round_start.processFrame(s, frame.frames_since_round_start, frame.frames_since_round_start);
        self.frames_left_in_round.processFrame(s, frame.frames_left_in_round, frame.frames_left_in_round);
        self.player_name.processFrame(s, c1.name, c2.name);
        self.rounds_won.processFrame(s, c1.rounds_won, c2.rounds_won);
        self.rounds_needed_to_win.processFrame(s, frame.rounds_needed_to_win, frame.rounds_needed_to_win);
        self.health.processFrame(s, c1.health, c2.health);
        self.recoverable_health.processFrame(s, c1.getRecoverableHealth(), c2.getRecoverableHealth());
        self.health_recover_limit.processFrame(s, c1.health_recover_limit, c2.health_recover_limit);
        self.max_health.processFrame(s, c1.max_health, c2.max_health);
        self.rage.processFrame(s, c1.rage, c2.rage);
        self.heat.processFrame(s, c1.heat, c2.heat);
        self.character_id.processFrame(s, c1.character_id, c2.character_id);
        self.animation_id.processFrame(s, c1.animation_id, c2.animation_id);
        self.animation_frame.processFrame(s, c1.animation_frame, c2.animation_frame);
        self.animation_total_frames.processFrame(s, c1.animation_total_frames, c2.animation_total_frames);
        self.move_phase.processFrame(s, c1.move_phase, c2.move_phase);
        self.move_frame.processFrame(s, c1.getMoveFrame(), c2.getMoveFrame());
        self.startup_frames.processFrame(s, c1.getStartupFrames(), c2.getStartupFrames());
        self.active_frames.processFrame(s, c1.getActiveFrames(), c2.getActiveFrames());
        self.recovery_frames.processFrame(s, c1.getRecoveryFrames(), c2.getRecoveryFrames());
        self.total_frames.processFrame(s, c1.getTotalFrames(), c2.getTotalFrames());
        self.frame_advantage.processFrame(s, c1.getFrameAdvantage(c2), c2.getFrameAdvantage(c1));
        self.attack_type.processFrame(s, c1.attack_type, c2.attack_type);
        self.attack_range.processFrame(s, c1.attack_range, c2.attack_range);
        self.attack_height.processFrame(s, c1.getAttackHeight(frame.floor_z), c2.getAttackHeight(frame.floor_z));
        self.recovery_range.processFrame(s, c1.recovery_range, c2.recovery_range);
        self.hit_outcome.processFrame(s, c1.hit_outcome, c2.hit_outcome);
        self.combo_hits.processFrame(s, c1.combo_hits, c2.combo_hits);
        self.combo_damage.processFrame(s, c1.combo_damage, c2.combo_damage);
        self.posture.processFrame(s, c1.posture, c2.posture);
        self.blocking.processFrame(s, c1.blocking, c2.blocking);
        self.crushing.processFrame(s, c1.crushing, c2.crushing);
        self.can_interact.processFrame(s, c1.can_interact, c2.can_interact);
        self.can_move.processFrame(s, c1.can_move, c2.can_move);
        self.throw_escape_phase.processFrame(
            s,
            if (c1.throw_escape) |*t| t.phase else null,
            if (c2.throw_escape) |*t| t.phase else null,
        );
        self.correct_throw_escape.processFrame(
            s,
            if (c1.throw_escape) |*t| t.correct_inputs else null,
            if (c2.throw_escape) |*t| t.correct_inputs else null,
        );
        self.attempted_throw_escape.processFrame(
            s,
            if (c1.throw_escape) |*t| t.attempted_input else null,
            if (c2.throw_escape) |*t| t.attempted_input else null,
        );
        self.throw_escape_attempt_timing.processFrame(
            s,
            if (c1.throw_escape) |*t| switch (t.attempted_input) {
                .none => null,
                else => t.attempt_timing,
            } else null,
            if (c2.throw_escape) |*t| switch (t.attempted_input) {
                .none => null,
                else => t.attempt_timing,
            } else null,
        );
        self.input.processFrame(s, c1.input, c2.input);
        self.distance_to_opponent.processFrame(s, c1.getDistanceTo(c2), c2.getDistanceTo(c1));
        self.angle_to_opponent.processFrame(s, c1.getAngleTo(c2), c2.getAngleTo(c1));
        self.distance_to_wall.processFrame(
            s,
            c1.getDistanceToWall(c2, frame.walls.asSlice()),
            c2.getDistanceToWall(c1, frame.walls.asSlice()),
        );
        self.angle_to_wall.processFrame(
            s,
            c1.getAngleToWall(c2, frame.walls.asSlice()),
            c2.getAngleToWall(c1, frame.walls.asSlice()),
        );
        self.hit_lines_height.processFrame(
            s,
            c1.getHitLinesHeight(frame.floor_z),
            c2.getHitLinesHeight(frame.floor_z),
        );
        self.hurt_cylinders_height.processFrame(
            s,
            c1.getHurtCylindersHeight(frame.floor_z),
            c2.getHurtCylindersHeight(frame.floor_z),
        );
    }

    pub fn update(self: *Self, delta_time: f32) void {
        inline for (@typeInfo(Self).@"struct".fields) |*field| {
            @field(self, field.name).update(delta_time);
        }
    }

    pub fn draw(self: Self, settings: *const model.DetailsSettings) void {
        const table_flags = imgui.ImGuiTableFlags_RowBg |
            imgui.ImGuiTableFlags_BordersInner |
            imgui.ImGuiTableFlags_PadOuterX |
            imgui.ImGuiTableFlags_Resizable |
            imgui.ImGuiTableFlags_ScrollY;
        var table_size: imgui.ImVec2 = undefined;
        imgui.igGetContentRegionAvail(&table_size);
        if (table_size.y < 5) {
            return; // Prevents crash from happening when user makes the child window too small.
        }
        const render_content = imgui.igBeginTable("table", 3, table_flags, table_size, 0);
        if (!render_content) return;
        defer imgui.igEndTable();

        imgui.igTableSetupScrollFreeze(0, 1);
        imgui.igTableSetupColumn("Property", 0, 0, 0);
        imgui.igTableSetupColumn(getHeaderName(settings.column_1), 0, 0, 0);
        imgui.igTableSetupColumn(getHeaderName(settings.column_2), 0, 0, 0);
        imgui.igTableHeadersRow();

        inline for (@typeInfo(Self).@"struct".fields) |*field| {
            if (@field(settings.rows_enabled, field.name)) {
                @field(self, field.name).draw(settings);
            }
        }
    }

    fn getHeaderName(column_setting: model.DetailsSettings.Column) [:0]const u8 {
        return switch (column_setting) {
            .player_1 => "Player 1",
            .player_2 => "Player 2",
            .left_player => "Left Player",
            .right_player => "Right Player",
            .main_player => "Main Player",
            .secondary_player => "Secondary Player",
        };
    }
};

fn Row(
    comptime name: [:0]const u8,
    comptime description: [:0]const u8,
    comptime Type: type,
    comptime empty_value: ?Type,
    comptime drawCellContent: *const fn (value: Type, alpha: f32) void,
) type {
    return struct {
        cell_1: Cell(Type, empty_value, drawCellContent) = .{},
        cell_2: Cell(Type, empty_value, drawCellContent) = .{},

        const Self = @This();
        pub const display_name = name;
        pub const display_description = description;

        pub fn processFrame(
            self: *Self,
            settings: *const model.DetailsSettings,
            value_1: ?Type,
            value_2: ?Type,
        ) void {
            self.cell_1.processFrame(settings, value_1);
            self.cell_2.processFrame(settings, value_2);
        }

        pub fn update(self: *Self, delta_time: f32) void {
            self.cell_1.update(delta_time);
            self.cell_2.update(delta_time);
        }

        pub fn draw(self: Self, settings: *const model.DetailsSettings) void {
            if (imgui.igTableNextColumn()) {
                drawText(name, 1.0);
                if (imgui.igIsItemHovered(0)) {
                    imgui.igSetTooltip(description);
                }
            }
            imgui.igPushID_Str(name);
            defer imgui.igPopID();
            if (imgui.igTableNextColumn()) {
                imgui.igPushID_Str("cell_1");
                defer imgui.igPopID();
                self.cell_1.draw(settings);
            }
            if (imgui.igTableNextColumn()) {
                imgui.igPushID_Str("cell_2");
                defer imgui.igPopID();
                self.cell_2.draw(settings);
            }
        }
    };
}

fn Cell(
    comptime Type: type,
    comptime empty_value: ?Type,
    comptime drawCellContent: *const fn (value: Type, alpha: f32) void,
) type {
    return struct {
        is_currently_present: bool = false,
        last_value: Type = undefined,
        remaining_time: f32 = 0.0,

        const Self = @This();

        pub fn processFrame(self: *Self, settings: *const model.DetailsSettings, value_maybe: ?Type) void {
            if (value_maybe) |value| {
                self.is_currently_present = !std.meta.eql(value_maybe, empty_value);
                if (self.is_currently_present) {
                    self.last_value = value;
                    self.remaining_time = settings.fade_out_duration;
                }
            } else {
                self.is_currently_present = false;
            }
        }

        pub fn update(self: *Self, delta_time: f32) void {
            if (!self.is_currently_present) {
                self.remaining_time = @max(0, self.remaining_time - delta_time);
            }
        }

        pub fn draw(self: Self, settings: *const model.DetailsSettings) void {
            if (self.is_currently_present) {
                drawCellContent(self.last_value, 1.0);
                return;
            }
            if (self.remaining_time <= 0.0) {
                if (empty_value) |value| {
                    drawCellContent(value, settings.fade_out_alpha);
                } else {
                    drawText(empty_value_string, settings.fade_out_alpha);
                }
                return;
            }
            const completion = 1.0 - (self.remaining_time / settings.fade_out_duration);
            const alpha = std.math.lerp(1.0, settings.fade_out_alpha, completion * completion * completion * completion);
            drawCellContent(self.last_value, alpha);
        }
    };
}

const string_buffer_size = 128;
const empty_value_string = "---";
const error_string = "error";

fn drawYesNo(value: bool, alpha: f32) void {
    const text = if (value) "Yes" else "No";
    drawText(text, alpha);
}

fn drawU32(value: u32, alpha: f32) void {
    var buffer: [string_buffer_size]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buffer, "{}", .{value}) catch error_string;
    drawText(text, alpha);
}

fn drawF32(value: f32, alpha: f32) void {
    var buffer: [string_buffer_size]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buffer, "{d:.2}", .{value}) catch error_string;
    drawText(text, alpha);
}

fn drawF32Div100(value: f32, alpha: f32) void {
    drawF32(0.01 * value, alpha);
}

fn drawF32Degrees(value: f32, alpha: f32) void {
    drawF32(std.math.radiansToDegrees(value), alpha);
}

fn drawIronyVersion(value: model.IronyVersion, alpha: f32) void {
    var buffer: [string_buffer_size]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buffer, "{f}", .{value}) catch error_string;
    drawText(text, alpha);
}

fn drawGameVersion(value: model.GameVersion, alpha: f32) void {
    if (value.len == 0) {
        drawText(empty_value_string, alpha);
        return;
    }
    drawText(value.asSlice(), alpha);
}

fn drawPlayerName(value: model.PlayerName, alpha: f32) void {
    if (value.len == 0) {
        drawText(empty_value_string, alpha);
        return;
    }
    drawText(value.asSlice(), alpha);
}

fn drawU32ActualMax(value: model.U32ActualMax, alpha: f32) void {
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var writer = std.Io.Writer.fixed(&buffer);
    if (value.actual) |actual| {
        writer.print("{}", .{actual}) catch {};
    } else {
        writer.writeAll(empty_value_string) catch {};
    }
    writer.writeAll(" (") catch {};
    if (value.max) |max| {
        writer.print("{}", .{max}) catch {};
    } else {
        writer.writeAll(empty_value_string) catch {};
    }
    writer.writeByte(')') catch {};
    if (writer.end >= buffer.len - 1) {
        drawText(error_string, alpha);
        return;
    }
    drawText(buffer[0..writer.end :0], alpha);
}

fn drawU32ActualMinMax(value: model.U32ActualMinMax, alpha: f32) void {
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var writer = std.Io.Writer.fixed(&buffer);
    if (value.actual) |actual| {
        writer.print("{}", .{actual}) catch {};
    } else {
        writer.writeAll(empty_value_string) catch {};
    }
    writer.writeAll(" (") catch {};
    if (value.min) |min| {
        writer.print("{}", .{min}) catch {};
    } else {
        writer.writeAll(empty_value_string) catch {};
    }
    writer.writeAll(" - ") catch {};
    if (value.max) |max| {
        writer.print("{}", .{max}) catch {};
    } else {
        writer.writeAll(empty_value_string) catch {};
    }
    writer.writeByte(')') catch {};
    if (writer.end >= buffer.len - 1) {
        drawText(error_string, alpha);
        return;
    }
    drawText(buffer[0..writer.end :0], alpha);
}

fn drawI32ActualMinMax(value: model.I32ActualMinMax, alpha: f32) void {
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var writer = std.Io.Writer.fixed(&buffer);
    if (value.actual) |actual| {
        if (actual > 0) {
            writer.writeByte('+') catch {};
        }
        writer.print("{}", .{actual}) catch {};
    } else {
        writer.writeAll(empty_value_string) catch {};
    }
    writer.writeAll(" (") catch {};
    if (value.min) |min| {
        if (min > 0) {
            writer.writeByte('+') catch {};
        }
        writer.print("{}", .{min}) catch {};
    } else {
        writer.writeAll(empty_value_string) catch {};
    }
    writer.writeAll(", ") catch {};
    if (value.max) |max| {
        if (max > 0) {
            writer.writeByte('+') catch {};
        }
        writer.print("{}", .{max}) catch {};
    } else {
        writer.writeAll(empty_value_string) catch {};
    }
    writer.writeByte(')') catch {};
    if (writer.end >= buffer.len - 1) {
        drawText(error_string, alpha);
        return;
    }
    drawText(buffer[0..writer.end :0], alpha);
}

fn drawF32MinMax(value: model.F32MinMax, alpha: f32) void {
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var writer = std.Io.Writer.fixed(&buffer);
    if (value.min) |min| {
        writer.print("{d:.2}", .{min}) catch {};
    } else {
        writer.writeAll(empty_value_string) catch {};
    }
    writer.writeAll(" - ") catch {};
    if (value.max) |max| {
        writer.print("{d:.2}", .{max}) catch {};
    } else {
        writer.writeAll(empty_value_string) catch {};
    }
    if (writer.end >= buffer.len - 1) {
        drawText(error_string, alpha);
        return;
    }
    drawText(buffer[0..writer.end :0], alpha);
}

fn drawGame(value: model.Game, alpha: f32) void {
    const text = switch (value) {
        .t7 => "T7",
        .t8 => "T8",
    };
    drawText(text, alpha);
}

fn drawSource(value: model.Source, alpha: f32) void {
    const text = switch (value) {
        .practice => "Practice",
        .live_game => "Live Game",
        .replay_loading => "Replay Loading",
        .replay_playback => "Replay Playback",
    };
    drawText(text, alpha);
}

fn drawMatchPhase(value: model.MatchPhase, alpha: f32) void {
    const text = switch (value) {
        .not_in_a_match => "Not In Match",
        .intro => "Intro",
        .outro => "Outro",
        .round_start => "Round Start",
        .round_end => "Round End",
        .mid_round => "Mid Round",
        .in_between_rounds => "In Between Rounds",
    };
    drawText(text, alpha);
}

fn drawMovePhase(value: model.MovePhase, alpha: f32) void {
    const text = switch (value) {
        .neutral => "Neutral",
        .start_up => "Start Up",
        .active => "Active",
        .active_recovery => "Active Recovery",
        .recovery => "Recovery",
    };
    drawText(text, alpha);
}

fn drawAttackType(value: model.AttackType, alpha: f32) void {
    const text = switch (value) {
        .not_attack => empty_value_string,
        .high => "High",
        .mid => "Mid",
        .low => "Low",
        .special_low => "Special Low",
        .unblockable_high => "Unblockable High",
        .unblockable_mid => "Unblockable Mid",
        .unblockable_low => "Unblockable Low",
        .throw => "Throw",
        .projectile => "Projectile",
        .antiair_only => "Anti-Air Only",
    };
    drawText(text, alpha);
}

fn drawHitOutcome(value: model.HitOutcome, alpha: f32) void {
    const text = switch (value) {
        .none => empty_value_string,
        .blocked_standing => "Blocked Standing",
        .blocked_crouching => "Blocked Crouching",
        .juggle => "Juggle",
        .screw => "Screw",
        .grounded_face_down => "Grounded Face Down",
        .grounded_face_up => "Grounded Face Up",
        .counter_hit_standing => "Counter Hit Standing",
        .counter_hit_crouching => "Counter Hit Crouching",
        .normal_hit_standing => "Normal Hit Standing",
        .normal_hit_crouching => "Normal Hit Crouching",
        .normal_hit_standing_left => "Normal Hit Standing Left",
        .normal_hit_crouching_left => "Normal Hit Crouching Left",
        .normal_hit_standing_back => "Normal Hit Standing Back",
        .normal_hit_crouching_back => "Normal Hit Crouching Back",
        .normal_hit_standing_right => "Normal Hit Standing Right",
        .normal_hit_crouching_right => "Normal Hit Crouching Right",
    };
    drawText(text, alpha);
}

fn drawPosture(value: model.Posture, alpha: f32) void {
    const text = switch (value) {
        .standing => "Standing",
        .crouching => "Crouching",
        .downed_face_up => "Downed Face Up",
        .downed_face_down => "Downed Face Down",
        .airborne => "Airborne",
    };
    drawText(text, alpha);
}

fn drawBlocking(value: model.Blocking, alpha: f32) void {
    const text = switch (value) {
        .not_blocking => "Not",
        .neutral_blocking_mids => "Neutral Mids",
        .fully_blocking_mids => "Fully Mids",
        .neutral_blocking_lows => "Neutral Lows",
        .fully_blocking_lows => "Fully Lows",
    };
    drawText(text, alpha);
}

fn drawThrowEscapePhase(value: model.ThrowEscapePhase, alpha: f32) void {
    const text = switch (value) {
        .in_escape_window => "In Escape Window",
        .escape_success => "Escape Success",
        .escape_fail => "Escape Fail",
    };
    drawText(text, alpha);
}

fn drawThrowEscapeInput(value: model.ThrowEscapeInput, alpha: f32) void {
    const text = switch (value) {
        .none => empty_value_string,
        .one => "1",
        .two => "2",
        .one_plus_two => "1+2",
    };
    drawText(text, alpha);
}

fn drawThrowEscapeTiming(value: model.ThrowEscapeTiming, alpha: f32) void {
    const text = switch (value) {
        .on_time => "On Time",
        .late => "Late",
    };
    drawText(text, alpha);
}

fn drawThrowEscapeInputs(value: model.ThrowEscapeInputs, alpha: f32) void {
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var writer = std.Io.Writer.fixed(&buffer);
    var is_first = true;
    if (value.one) {
        if (!is_first) {
            writer.writeAll(" or ") catch {};
        }
        writer.writeByte('1') catch {};
        is_first = false;
    }
    if (value.two) {
        if (!is_first) {
            writer.writeAll(" or ") catch {};
        }
        writer.writeByte('2') catch {};
        is_first = false;
    }
    if (value.one_plus_two) {
        if (!is_first) {
            writer.writeAll(" or ") catch {};
        }
        writer.writeAll("1+2") catch {};
        is_first = false;
    }
    if (writer.end == 0) {
        drawText(empty_value_string, alpha);
    } else if (writer.end >= buffer.len - 1) {
        drawText(error_string, alpha);
    } else {
        drawText(buffer[0..writer.end :0], alpha);
    }
}

fn drawCrushing(value: model.Crushing, alpha: f32) void {
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var writer = std.Io.Writer.fixed(&buffer);
    var is_first = true;
    if (value.invincibility) {
        if (!is_first) {
            writer.writeByte('+') catch {};
        }
        writer.writeAll("Everything") catch {};
        is_first = false;
    } else {
        if (value.high_crushing) {
            if (!is_first) {
                writer.writeAll(", ") catch {};
            }
            writer.writeAll("Highs") catch {};
            is_first = false;
        }
        if (value.low_crushing) {
            if (!is_first) {
                writer.writeAll(", ") catch {};
            }
            writer.writeAll("Lows") catch {};
            is_first = false;
        }
        if (value.anti_air_only_crushing) {
            if (!is_first) {
                writer.writeAll(", ") catch {};
            }
            writer.writeAll("Anti-Airs") catch {};
            is_first = false;
        }
    }
    if (value.power_crushing) {
        if (!is_first) {
            writer.writeAll(", ") catch {};
        }
        writer.writeAll("Power-Crushing") catch {};
        is_first = false;
    }
    if (writer.end == 0) {
        drawText(empty_value_string, alpha);
    } else if (writer.end >= buffer.len - 1) {
        drawText(error_string, alpha);
    } else {
        drawText(buffer[0..writer.end :0], alpha);
    }
}

fn drawInput(value: model.Input, alpha: f32) void {
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var writer = std.Io.Writer.fixed(&buffer);
    if (value.up and !value.down) {
        writer.writeByte('u') catch {};
    }
    if (value.down and !value.up) {
        writer.writeByte('d') catch {};
    }
    if (value.forward and !value.back) {
        writer.writeByte('f') catch {};
    }
    if (value.back and !value.forward) {
        writer.writeByte('b') catch {};
    }
    var is_first = true;
    if (value.button_1) {
        if (!is_first) {
            writer.writeByte('+') catch {};
        }
        writer.writeByte('1') catch {};
        is_first = false;
    }
    if (value.button_2) {
        if (!is_first) {
            writer.writeByte('+') catch {};
        }
        writer.writeByte('2') catch {};
        is_first = false;
    }
    if (value.button_3) {
        if (!is_first) {
            writer.writeByte('+') catch {};
        }
        writer.writeByte('3') catch {};
        is_first = false;
    }
    if (value.button_4) {
        if (!is_first) {
            writer.writeByte('+') catch {};
        }
        writer.writeByte('4') catch {};
        is_first = false;
    }
    if (value.special_style) {
        if (!is_first) {
            writer.writeByte('+') catch {};
        }
        writer.writeAll("SS") catch {};
        is_first = false;
    }
    if (value.rage) {
        if (!is_first) {
            writer.writeByte('+') catch {};
        }
        writer.writeByte('R') catch {};
        is_first = false;
    }
    if (value.heat) {
        if (!is_first) {
            writer.writeByte('+') catch {};
        }
        writer.writeByte('H') catch {};
        is_first = false;
    }
    if (writer.end == 0) {
        drawText(empty_value_string, alpha);
    } else if (writer.end >= buffer.len - 1) {
        drawText(error_string, alpha);
    } else {
        drawText(buffer[0..writer.end :0], alpha);
    }
}

fn drawRage(value: model.Rage, alpha: f32) void {
    const text = switch (value) {
        .available => "Available",
        .activated => "Activated",
        .used_up => "Used Up",
    };
    drawText(text, alpha);
}

fn drawHeat(value: model.Heat, alpha: f32) void {
    const text = switch (value) {
        .available => "Available",
        .activated => |activated| {
            const percent = activated.gauge * 100;
            var buffer: [string_buffer_size]u8 = undefined;
            const text = std.fmt.bufPrintZ(&buffer, "Activated: {d:.1}%", .{percent}) catch error_string;
            drawText(text, alpha);
            return;
        },
        .used_up => "Used Up",
    };
    drawText(text, alpha);
}

fn drawText(text: [:0]const u8, alpha: f32) void {
    const color = imgui.ImVec4{
        .x = 1,
        .y = 1,
        .z = 1,
        .w = alpha,
    };
    imgui.igTextColored(color, "%s", text.ptr);

    var rect: imgui.ImRect = undefined;
    imgui.igGetItemRectMin(&rect.Min);
    imgui.igGetItemRectMax(&rect.Max);
    _ = imgui.igItemAdd(rect, imgui.igGetID_Str(text), null, imgui.ImGuiItemFlags_NoNav);

    if (imgui.igIsItemClicked(imgui.ImGuiMouseButton_Left)) {
        imgui.igSetClipboardText(text);
        sdk.ui.toasts.send(.info, null, "Copied to clipboard: {s}", .{text});
    }

    if (builtin.is_test) {
        imgui.teItemAdd(imgui.igGetCurrentContext(), imgui.igGetID_Str(text), &rect, null);
    }
}

const testing = std.testing;

test "should draw correct table headers based on settings" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table");
            try ctx.expectItemExists("$$0/Property");

            settings.column_1 = .player_1;
            settings.column_2 = .player_2;
            ctx.yield(1);
            try ctx.expectItemExists("$$1/Player 1");
            try ctx.expectItemExists("$$2/Player 2");

            settings.column_1 = .player_2;
            settings.column_2 = .player_1;
            ctx.yield(1);
            try ctx.expectItemExists("$$1/Player 2");
            try ctx.expectItemExists("$$2/Player 1");

            settings.column_1 = .left_player;
            settings.column_2 = .right_player;
            ctx.yield(1);
            try ctx.expectItemExists("$$1/Left Player");
            try ctx.expectItemExists("$$2/Right Player");

            settings.column_1 = .right_player;
            settings.column_2 = .left_player;
            ctx.yield(1);
            try ctx.expectItemExists("$$1/Right Player");
            try ctx.expectItemExists("$$2/Left Player");

            settings.column_1 = .main_player;
            settings.column_2 = .secondary_player;
            ctx.yield(1);
            try ctx.expectItemExists("$$1/Main Player");
            try ctx.expectItemExists("$$2/Secondary Player");

            settings.column_1 = .secondary_player;
            settings.column_2 = .main_player;
            ctx.yield(1);
            try ctx.expectItemExists("$$1/Secondary Player");
            try ctx.expectItemExists("$$2/Main Player");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw data in correct columns based on settings" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const frame = model.Frame{
                .players = .{
                    .{ .animation_frame = 1 },
                    .{ .animation_frame = 2 },
                },
                .left_player_id = .player_2,
                .main_player_id = .player_1,
            };
            ctx.setRef("Window/table/Animation Frame");

            settings.column_1 = .player_1;
            settings.column_2 = .player_2;
            details.processFrame(&settings, &frame);
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/1");
            try ctx.expectItemExists("cell_2/2");

            settings.column_1 = .player_2;
            settings.column_2 = .player_1;
            details.processFrame(&settings, &frame);
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/2");
            try ctx.expectItemExists("cell_2/1");

            settings.column_1 = .left_player;
            settings.column_2 = .right_player;
            details.processFrame(&settings, &frame);
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/2");
            try ctx.expectItemExists("cell_2/1");

            settings.column_1 = .right_player;
            settings.column_2 = .left_player;
            details.processFrame(&settings, &frame);
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/1");
            try ctx.expectItemExists("cell_2/2");

            settings.column_1 = .main_player;
            settings.column_2 = .secondary_player;
            details.processFrame(&settings, &frame);
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/1");
            try ctx.expectItemExists("cell_2/2");

            settings.column_1 = .secondary_player;
            settings.column_2 = .main_player;
            details.processFrame(&settings, &frame);
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/2");
            try ctx.expectItemExists("cell_2/1");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should put text into clipboard when clicking text" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
            sdk.ui.toasts.draw();
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const frame = model.Frame{
                .players = .{
                    .{ .animation_frame = 1 },
                    .{ .animation_frame = 2 },
                },
                .left_player_id = .player_2,
                .main_player_id = .player_1,
            };
            details.processFrame(&settings, &frame);
            sdk.ui.toasts.update(100);
            ctx.setRef("Window/table");

            ctx.itemClick("Animation Frame", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("Animation Frame");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: Animation Frame");
            sdk.ui.toasts.update(100);

            ctx.itemClick(
                "Animation Frame/cell_1/1",
                imgui.ImGuiMouseButton_Left,
                imgui.ImGuiTestOpFlags_NoCheckHoveredId,
            );
            try ctx.expectClipboardText("1");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 1");
            sdk.ui.toasts.update(100);

            ctx.itemClick(
                "Animation Frame/cell_2/2",
                imgui.ImGuiMouseButton_Left,
                imgui.ImGuiTestOpFlags_NoCheckHoveredId,
            );
            try ctx.expectClipboardText("2");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 2");
            sdk.ui.toasts.update(100);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should should slowly fade out from last present value to null or empty value" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Attack Type");

            details.processFrame(&settings, &.{ .players = .{
                .{ .attack_type = .high },
                .{ .attack_type = .mid },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/High");
            try ctx.expectItemExists("cell_2/Mid");

            details.processFrame(&settings, &.{ .players = .{
                .{ .attack_type = null },
                .{ .attack_type = .not_attack },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/High");
            try ctx.expectItemExists("cell_2/Mid");

            details.update(0.9 * settings.fade_out_duration);
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/High");
            try ctx.expectItemExists("cell_2/Mid");

            details.update(0.2 * settings.fade_out_duration);
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should not draw row when row is disabled in settings" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");

            details.processFrame(&settings, &.{ .players = .{
                .{ .attack_type = .high },
                .{ .attack_type = .mid },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("table/Attack Type");
            try ctx.expectItemExists("table/Attack Type/cell_1/High");
            try ctx.expectItemExists("table/Attack Type/cell_2/Mid");

            settings.rows_enabled.attack_type = false;
            ctx.yield(3); // No idea why yield(1) is not enough.
            try ctx.expectItemNotExists("table/Attack Type");
            try ctx.expectItemNotExists("table/Attack Type/cell_1/High");
            try ctx.expectItemNotExists("table/Attack Type/cell_2/Mid");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw irony version correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Irony Version");

            details.processFrame(&settings, &.{ .irony_version = null });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .irony_version = .comptimeParse("1.23.45") });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/1.23.45");
            try ctx.expectItemExists("cell_2/1.23.45");

            details.processFrame(&settings, &.{ .irony_version = .comptimeParse("98.76.54-SNAPSHOT") });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/98.76.54-SNAPSHOT");
            try ctx.expectItemExists("cell_2/98.76.54-SNAPSHOT");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw game correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Game");

            details.processFrame(&settings, &.{ .game = null });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .game = .t7 });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/T7");
            try ctx.expectItemExists("cell_2/T7");

            details.processFrame(&settings, &.{ .game = .t8 });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/T8");
            try ctx.expectItemExists("cell_2/T8");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw game version correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Game Version");

            details.processFrame(&settings, &.{ .game_version = .empty });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .game_version = .fromSliceTrimmed("12.34.56") });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/12.34.56");
            try ctx.expectItemExists("cell_2/12.34.56");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw source correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Source");

            details.processFrame(&settings, &.{ .source = null });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .source = .practice });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Practice");
            try ctx.expectItemExists("cell_2/Practice");

            details.processFrame(&settings, &.{ .source = .live_game });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Live Game");
            try ctx.expectItemExists("cell_2/Live Game");

            details.processFrame(&settings, &.{ .source = .replay_loading });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Replay Loading");
            try ctx.expectItemExists("cell_2/Replay Loading");

            details.processFrame(&settings, &.{ .source = .replay_playback });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Replay Playback");
            try ctx.expectItemExists("cell_2/Replay Playback");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw match phase correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Match Phase");

            details.processFrame(&settings, &.{ .match_phase = null });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .match_phase = .not_in_a_match });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Not In Match");
            try ctx.expectItemExists("cell_2/Not In Match");

            details.processFrame(&settings, &.{ .match_phase = .intro });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Intro");
            try ctx.expectItemExists("cell_2/Intro");

            details.processFrame(&settings, &.{ .match_phase = .outro });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Outro");
            try ctx.expectItemExists("cell_2/Outro");

            details.processFrame(&settings, &.{ .match_phase = .round_start });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Round Start");
            try ctx.expectItemExists("cell_2/Round Start");

            details.processFrame(&settings, &.{ .match_phase = .round_end });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Round End");
            try ctx.expectItemExists("cell_2/Round End");

            details.processFrame(&settings, &.{ .match_phase = .mid_round });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Mid Round");
            try ctx.expectItemExists("cell_2/Mid Round");

            details.processFrame(&settings, &.{ .match_phase = .in_between_rounds });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/In Between Rounds");
            try ctx.expectItemExists("cell_2/In Between Rounds");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw frames since round start correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Since Round Start");

            details.processFrame(&settings, &.{ .frames_since_round_start = null });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .frames_since_round_start = 0 });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/0");
            try ctx.expectItemExists("cell_2/0");

            details.processFrame(&settings, &.{ .frames_since_round_start = 123 });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/123");
            try ctx.expectItemExists("cell_2/123");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw frames left in round correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Frames Left In Round");

            details.processFrame(&settings, &.{ .frames_left_in_round = null });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .frames_left_in_round = 0 });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/0");
            try ctx.expectItemExists("cell_2/0");

            details.processFrame(&settings, &.{ .frames_left_in_round = 123 });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/123");
            try ctx.expectItemExists("cell_2/123");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw player name correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Player Name");

            details.processFrame(&settings, &.{ .players = .{
                .{ .name = .empty },
                .{ .name = .fromArray("Player Name".*) },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/Player Name");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw rounds won correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Rounds Won");

            details.processFrame(&settings, &.{ .players = .{
                .{ .rounds_won = null },
                .{ .rounds_won = 0 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/0");

            details.processFrame(&settings, &.{ .players = .{
                .{ .rounds_won = 123 },
                .{ .rounds_won = 456 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/123");
            try ctx.expectItemExists("cell_2/456");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw rounds needed to win correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Rounds Needed To Win");

            details.processFrame(&settings, &.{ .rounds_needed_to_win = null });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .rounds_needed_to_win = 0 });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/0");
            try ctx.expectItemExists("cell_2/0");

            details.processFrame(&settings, &.{ .rounds_needed_to_win = 123 });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/123");
            try ctx.expectItemExists("cell_2/123");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw health correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Health");

            details.processFrame(&settings, &.{ .players = .{
                .{ .health = null },
                .{ .health = 0 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/0");

            details.processFrame(&settings, &.{ .players = .{
                .{ .health = 123 },
                .{ .health = 456 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/123");
            try ctx.expectItemExists("cell_2/456");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw recoverable health correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Recoverable Health");

            details.processFrame(&settings, &.{ .players = .{
                .{ .health = null, .health_recover_limit = null },
                .{ .health = 100, .health_recover_limit = 100 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/0");

            details.processFrame(&settings, &.{ .players = .{
                .{ .health = 100, .health_recover_limit = 223 },
                .{ .health = 100, .health_recover_limit = 556 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/123");
            try ctx.expectItemExists("cell_2/456");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw health recover limit correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Health Recover Limit");

            details.processFrame(&settings, &.{ .players = .{
                .{ .health_recover_limit = null },
                .{ .health_recover_limit = 0 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/0");

            details.processFrame(&settings, &.{ .players = .{
                .{ .health_recover_limit = 123 },
                .{ .health_recover_limit = 456 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/123");
            try ctx.expectItemExists("cell_2/456");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw max health correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Max Health");

            details.processFrame(&settings, &.{ .players = .{
                .{ .max_health = null },
                .{ .max_health = 0 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/0");

            details.processFrame(&settings, &.{ .players = .{
                .{ .max_health = 123 },
                .{ .max_health = 456 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/123");
            try ctx.expectItemExists("cell_2/456");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw rage correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Rage");

            details.processFrame(&settings, &.{ .players = .{
                .{ .rage = null },
                .{ .rage = .available },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/Available");

            details.processFrame(&settings, &.{ .players = .{
                .{ .rage = .activated },
                .{ .rage = .used_up },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Activated");
            try ctx.expectItemExists("cell_2/Used Up");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw heat correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Heat");

            details.processFrame(&settings, &.{ .players = .{
                .{ .heat = null },
                .{ .heat = .available },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/Available");

            details.processFrame(&settings, &.{ .players = .{
                .{ .heat = .{ .activated = .{ .gauge = 0.1234567 } } },
                .{ .heat = .used_up },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Activated: 12.3%");
            try ctx.expectItemExists("cell_2/Used Up");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw character ID correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Character ID");

            details.processFrame(&settings, &.{ .players = .{
                .{ .character_id = null },
                .{ .character_id = 0 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/0");

            details.processFrame(&settings, &.{ .players = .{
                .{ .character_id = 123 },
                .{ .character_id = 456 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/123");
            try ctx.expectItemExists("cell_2/456");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw animation ID correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Animation ID");

            details.processFrame(&settings, &.{ .players = .{
                .{ .animation_id = null },
                .{ .animation_id = 0 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/0");

            details.processFrame(&settings, &.{ .players = .{
                .{ .animation_id = 123 },
                .{ .animation_id = 456 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/123");
            try ctx.expectItemExists("cell_2/456");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw animation frame correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Animation Frame");

            details.processFrame(&settings, &.{ .players = .{
                .{ .animation_frame = null },
                .{ .animation_frame = 0 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/0");

            details.processFrame(&settings, &.{ .players = .{
                .{ .animation_frame = 123 },
                .{ .animation_frame = 456 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/123");
            try ctx.expectItemExists("cell_2/456");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw animation total frames correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Animation Total Frames");

            details.processFrame(&settings, &.{ .players = .{
                .{ .animation_total_frames = null },
                .{ .animation_total_frames = 0 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/0");

            details.processFrame(&settings, &.{ .players = .{
                .{ .animation_total_frames = 123 },
                .{ .animation_total_frames = 456 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/123");
            try ctx.expectItemExists("cell_2/456");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw move phase correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Move Phase");

            details.processFrame(&settings, &.{ .players = .{
                .{ .move_phase = null },
                .{ .move_phase = .neutral },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/Neutral");

            details.processFrame(&settings, &.{ .players = .{
                .{ .move_phase = .start_up },
                .{ .move_phase = .active },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Start Up");
            try ctx.expectItemExists("cell_2/Active");

            details.processFrame(&settings, &.{ .players = .{
                .{ .move_phase = .active_recovery },
                .{ .move_phase = .recovery },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Active Recovery");
            try ctx.expectItemExists("cell_2/Recovery");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw move frame correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Move Frame");

            details.processFrame(&settings, &.{ .players = .{
                .{ .animation_frame = null, .animation_to_move_delta = null },
                .{ .animation_frame = 0, .animation_to_move_delta = 0 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/0");

            details.processFrame(&settings, &.{ .players = .{
                .{ .animation_frame = 123, .animation_to_move_delta = 0 },
                .{ .animation_frame = 456, .animation_to_move_delta = 0 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/123");
            try ctx.expectItemExists("cell_2/456");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw startup frames correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Startup Frames");

            details.processFrame(&settings, &.{ .players = .{
                .{ .first_active_frame = null, .connected_frame = null, .last_active_frame = null },
                .{ .first_active_frame = 1, .connected_frame = null, .last_active_frame = null },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/--- (--- - ---)");
            try ctx.expectItemExists("cell_2/--- (1 - ---)");

            details.processFrame(&settings, &.{ .players = .{
                .{ .first_active_frame = 1, .connected_frame = 2, .last_active_frame = null },
                .{ .first_active_frame = 1, .connected_frame = 2, .last_active_frame = 3 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/2 (1 - ---)");
            try ctx.expectItemExists("cell_2/2 (1 - 3)");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw active frames correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Active Frames");

            details.processFrame(&settings, &.{ .players = .{
                .{ .first_active_frame = null, .connected_frame = null, .last_active_frame = null },
                .{ .first_active_frame = 1, .connected_frame = null, .last_active_frame = null },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/--- (---)");
            try ctx.expectItemExists("cell_2/--- (---)");

            details.processFrame(&settings, &.{ .players = .{
                .{ .first_active_frame = 1, .connected_frame = 2, .last_active_frame = null },
                .{ .first_active_frame = 1, .connected_frame = 2, .last_active_frame = 3 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/2 (---)");
            try ctx.expectItemExists("cell_2/2 (3)");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw recovery frames correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Recovery Frames");

            details.processFrame(&settings, &.{ .players = .{
                .{
                    .animation_total_frames = 5,
                    .animation_to_move_delta = 0,
                    .first_active_frame = null,
                    .connected_frame = null,
                    .last_active_frame = null,
                },
                .{
                    .animation_total_frames = 5,
                    .animation_to_move_delta = 0,
                    .first_active_frame = 1,
                    .connected_frame = null,
                    .last_active_frame = null,
                },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/--- (--- - ---)");
            try ctx.expectItemExists("cell_2/--- (--- - 4)");

            details.processFrame(&settings, &.{ .players = .{
                .{
                    .animation_total_frames = 5,
                    .animation_to_move_delta = 0,
                    .first_active_frame = 1,
                    .connected_frame = 2,
                    .last_active_frame = null,
                },
                .{
                    .animation_total_frames = 5,
                    .animation_to_move_delta = 0,
                    .first_active_frame = 1,
                    .connected_frame = 2,
                    .last_active_frame = 3,
                },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/3 (--- - 4)");
            try ctx.expectItemExists("cell_2/3 (2 - 4)");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw total frames correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Total Frames");

            details.processFrame(&settings, &.{ .players = .{
                .{
                    .animation_total_frames = null,
                    .animation_to_move_delta = 123,
                },
                .{
                    .animation_total_frames = 123,
                    .animation_to_move_delta = null,
                },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .players = .{
                .{
                    .animation_total_frames = 123,
                    .animation_to_move_delta = 0,
                },
                .{
                    .animation_total_frames = 123,
                    .animation_to_move_delta = 23,
                },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/123");
            try ctx.expectItemExists("cell_2/100");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw frame advantage correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Frame Advantage");

            details.processFrame(&settings, &.{ .players = .{
                .{
                    .move_phase = .recovery,
                    .attack_type = .mid,
                    .first_active_frame = 1,
                    .connected_frame = 2,
                    .last_active_frame = 3,
                    .animation_frame = 5,
                    .animation_to_move_delta = 1,
                    .animation_total_frames = 6,
                },
                .{
                    .move_phase = .recovery,
                    .attack_type = .not_attack,
                    .first_active_frame = null,
                    .connected_frame = null,
                    .last_active_frame = null,
                    .animation_frame = 3,
                    .animation_to_move_delta = 1,
                    .animation_total_frames = 6,
                },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/+2 (+1, +3)");
            try ctx.expectItemExists("cell_2/-2 (-3, -1)");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw attack type correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Attack Type");

            details.processFrame(&settings, &.{ .players = .{
                .{ .attack_type = null },
                .{ .attack_type = .not_attack },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .players = .{
                .{ .attack_type = .high },
                .{ .attack_type = .mid },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/High");
            try ctx.expectItemExists("cell_2/Mid");

            details.processFrame(&settings, &.{ .players = .{
                .{ .attack_type = .low },
                .{ .attack_type = .special_low },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Low");
            try ctx.expectItemExists("cell_2/Special Low");

            details.processFrame(&settings, &.{ .players = .{
                .{ .attack_type = .unblockable_high },
                .{ .attack_type = .unblockable_mid },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Unblockable High");
            try ctx.expectItemExists("cell_2/Unblockable Mid");

            details.processFrame(&settings, &.{ .players = .{
                .{ .attack_type = .unblockable_low },
                .{ .attack_type = .throw },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Unblockable Low");
            try ctx.expectItemExists("cell_2/Throw");

            details.processFrame(&settings, &.{ .players = .{
                .{ .attack_type = .projectile },
                .{ .attack_type = .antiair_only },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Projectile");
            try ctx.expectItemExists("cell_2/Anti-Air Only");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw attack range correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Attack Range [m]");

            details.processFrame(&settings, &.{ .players = .{
                .{ .attack_range = null },
                .{ .attack_range = 0 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/0.00");

            details.processFrame(&settings, &.{ .players = .{
                .{ .attack_range = 123.456 },
                .{ .attack_range = -456.789 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/1.23");
            try ctx.expectItemExists("cell_2/-4.57");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw attack height correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Attack Height [cm]");

            details.processFrame(&settings, &.{
                .floor_z = 0,
                .players = .{
                    .{ .min_attack_z = null, .max_attack_z = null },
                    .{ .min_attack_z = 123.456, .max_attack_z = null },
                },
            });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/--- - ---");
            try ctx.expectItemExists("cell_2/123.46 - ---");

            details.processFrame(&settings, &.{
                .floor_z = 0,
                .players = .{
                    .{ .min_attack_z = null, .max_attack_z = 456.789 },
                    .{ .min_attack_z = 123.456, .max_attack_z = 456.789 },
                },
            });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/--- - 456.79");
            try ctx.expectItemExists("cell_2/123.46 - 456.79");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw recovery range correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Recovery Range [m]");

            details.processFrame(&settings, &.{ .players = .{
                .{ .recovery_range = null },
                .{ .recovery_range = 0 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/0.00");

            details.processFrame(&settings, &.{ .players = .{
                .{ .recovery_range = 123.456 },
                .{ .recovery_range = -456.789 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/1.23");
            try ctx.expectItemExists("cell_2/-4.57");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw hit outcome correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Hit Outcome");

            details.processFrame(&settings, &.{ .players = .{
                .{ .hit_outcome = null },
                .{ .hit_outcome = .none },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .players = .{
                .{ .hit_outcome = .blocked_standing },
                .{ .hit_outcome = .blocked_crouching },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Blocked Standing");
            try ctx.expectItemExists("cell_2/Blocked Crouching");

            details.processFrame(&settings, &.{ .players = .{
                .{ .hit_outcome = .juggle },
                .{ .hit_outcome = .screw },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Juggle");
            try ctx.expectItemExists("cell_2/Screw");

            details.processFrame(&settings, &.{ .players = .{
                .{ .hit_outcome = .grounded_face_down },
                .{ .hit_outcome = .grounded_face_up },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Grounded Face Down");
            try ctx.expectItemExists("cell_2/Grounded Face Up");

            details.processFrame(&settings, &.{ .players = .{
                .{ .hit_outcome = .counter_hit_standing },
                .{ .hit_outcome = .counter_hit_crouching },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Counter Hit Standing");
            try ctx.expectItemExists("cell_2/Counter Hit Crouching");

            details.processFrame(&settings, &.{ .players = .{
                .{ .hit_outcome = .normal_hit_standing },
                .{ .hit_outcome = .normal_hit_crouching },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Normal Hit Standing");
            try ctx.expectItemExists("cell_2/Normal Hit Crouching");

            details.processFrame(&settings, &.{ .players = .{
                .{ .hit_outcome = .normal_hit_standing_left },
                .{ .hit_outcome = .normal_hit_crouching_left },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Normal Hit Standing Left");
            try ctx.expectItemExists("cell_2/Normal Hit Crouching Left");

            details.processFrame(&settings, &.{ .players = .{
                .{ .hit_outcome = .normal_hit_standing_back },
                .{ .hit_outcome = .normal_hit_crouching_back },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Normal Hit Standing Back");
            try ctx.expectItemExists("cell_2/Normal Hit Crouching Back");

            details.processFrame(&settings, &.{ .players = .{
                .{ .hit_outcome = .normal_hit_standing_right },
                .{ .hit_outcome = .normal_hit_crouching_right },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Normal Hit Standing Right");
            try ctx.expectItemExists("cell_2/Normal Hit Crouching Right");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw combo hits correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Combo Hits");

            details.processFrame(&settings, &.{ .players = .{
                .{ .combo_hits = null },
                .{ .combo_hits = 0 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/0");
            try ctx.expectItemExists("cell_2/0");

            details.processFrame(&settings, &.{ .players = .{
                .{ .combo_hits = 123 },
                .{ .combo_hits = 456 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/123");
            try ctx.expectItemExists("cell_2/456");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw combo damage" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Combo Damage");

            details.processFrame(&settings, &.{ .players = .{
                .{ .combo_damage = null },
                .{ .combo_damage = 0 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/0");
            try ctx.expectItemExists("cell_2/0");

            details.processFrame(&settings, &.{ .players = .{
                .{ .combo_damage = 123 },
                .{ .combo_damage = 456 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/123");
            try ctx.expectItemExists("cell_2/456");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw posture correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Posture");

            details.processFrame(&settings, &.{ .players = .{
                .{ .posture = null },
                .{ .posture = .standing },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/Standing");

            details.processFrame(&settings, &.{ .players = .{
                .{ .posture = .crouching },
                .{ .posture = .downed_face_up },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Crouching");
            try ctx.expectItemExists("cell_2/Downed Face Up");

            details.processFrame(&settings, &.{ .players = .{
                .{ .posture = .downed_face_down },
                .{ .posture = .airborne },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Downed Face Down");
            try ctx.expectItemExists("cell_2/Airborne");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw blocking correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Blocking");

            details.processFrame(&settings, &.{ .players = .{
                .{ .blocking = null },
                .{ .blocking = .not_blocking },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/Not");

            details.processFrame(&settings, &.{ .players = .{
                .{ .blocking = .neutral_blocking_mids },
                .{ .blocking = .fully_blocking_mids },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Neutral Mids");
            try ctx.expectItemExists("cell_2/Fully Mids");

            details.processFrame(&settings, &.{ .players = .{
                .{ .blocking = .neutral_blocking_lows },
                .{ .blocking = .fully_blocking_lows },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Neutral Lows");
            try ctx.expectItemExists("cell_2/Fully Lows");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw crushing correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Crushing");

            details.processFrame(&settings, &.{ .players = .{
                .{ .crushing = null },
                .{ .crushing = .{} },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .players = .{
                .{ .crushing = .{ .high_crushing = true } },
                .{ .crushing = .{ .high_crushing = true, .low_crushing = true } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Highs");
            try ctx.expectItemExists("cell_2/Highs, Lows");

            details.processFrame(&settings, &.{ .players = .{
                .{ .crushing = .{ .anti_air_only_crushing = true } },
                .{ .crushing = .{ .high_crushing = true, .low_crushing = true, .invincibility = true } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Anti-Airs");
            try ctx.expectItemExists("cell_2/Everything");

            details.processFrame(&settings, &.{ .players = .{
                .{ .crushing = .{ .power_crushing = true } },
                .{ .crushing = .{ .high_crushing = true, .invincibility = true, .power_crushing = true } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Power-Crushing");
            try ctx.expectItemExists("cell_2/Everything, Power-Crushing");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw can interact correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Can Interact");

            details.processFrame(&settings, &.{ .players = .{
                .{ .can_interact = null },
                .{ .can_interact = false },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/No");

            details.processFrame(&settings, &.{ .players = .{
                .{ .can_interact = true },
                .{ .can_interact = false },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Yes");
            try ctx.expectItemExists("cell_2/No");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw throw escape phase correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Throw Escape Phase");

            details.processFrame(&settings, &.{ .players = .{
                .{ .throw_escape = null },
                .{ .throw_escape = .{ .phase = .in_escape_window } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/In Escape Window");

            details.processFrame(&settings, &.{ .players = .{
                .{ .throw_escape = .{ .phase = .escape_success } },
                .{ .throw_escape = .{ .phase = .escape_fail } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Escape Success");
            try ctx.expectItemExists("cell_2/Escape Fail");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw correct throw escape correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Correct Throw Escape");

            details.processFrame(&settings, &.{ .players = .{
                .{ .throw_escape = null },
                .{ .throw_escape = .{
                    .phase = .in_escape_window,
                    .correct_inputs = .{ .one = false, .two = false, .one_plus_two = false },
                } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .players = .{
                .{ .throw_escape = .{
                    .phase = .in_escape_window,
                    .correct_inputs = .{ .one = true, .two = false, .one_plus_two = false },
                } },
                .{ .throw_escape = .{
                    .phase = .in_escape_window,
                    .correct_inputs = .{ .one = false, .two = true, .one_plus_two = false },
                } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/1");
            try ctx.expectItemExists("cell_2/2");

            details.processFrame(&settings, &.{ .players = .{
                .{ .throw_escape = .{
                    .phase = .in_escape_window,
                    .correct_inputs = .{ .one = false, .two = false, .one_plus_two = true },
                } },
                .{ .throw_escape = .{
                    .phase = .in_escape_window,
                    .correct_inputs = .{ .one = true, .two = true, .one_plus_two = false },
                } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/1+2");
            try ctx.expectItemExists("cell_2/1 or 2");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw attempted throw escape correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Attempted Throw Escape");

            details.processFrame(&settings, &.{ .players = .{
                .{ .throw_escape = null },
                .{ .throw_escape = .{
                    .phase = .in_escape_window,
                    .attempted_input = .none,
                } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .players = .{
                .{ .throw_escape = .{
                    .phase = .in_escape_window,
                    .attempted_input = .one,
                } },
                .{ .throw_escape = .{
                    .phase = .in_escape_window,
                    .attempted_input = .two,
                } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/1");
            try ctx.expectItemExists("cell_2/2");

            details.processFrame(&settings, &.{ .players = .{
                .{ .throw_escape = .{
                    .phase = .in_escape_window,
                    .attempted_input = .one_plus_two,
                } },
                .{ .throw_escape = .{
                    .phase = .in_escape_window,
                    .attempted_input = .one_plus_two,
                } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/1+2");
            try ctx.expectItemExists("cell_2/1+2");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw throw escape attempt timing correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Throw Escape Attempt Timing");

            details.processFrame(&settings, &.{ .players = .{
                .{ .throw_escape = null },
                .{ .throw_escape = .{
                    .phase = .in_escape_window,
                    .attempted_input = .none,
                    .attempt_timing = .on_time,
                } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .players = .{
                .{ .throw_escape = .{
                    .phase = .in_escape_window,
                    .attempted_input = .one,
                    .attempt_timing = .on_time,
                } },
                .{ .throw_escape = .{
                    .phase = .in_escape_window,
                    .attempted_input = .two,
                    .attempt_timing = .late,
                } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/On Time");
            try ctx.expectItemExists("cell_2/Late");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw can move correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Can Move");

            details.processFrame(&settings, &.{ .players = .{
                .{ .can_move = null },
                .{ .can_move = false },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/No");

            details.processFrame(&settings, &.{ .players = .{
                .{ .can_move = true },
                .{ .can_move = false },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/Yes");
            try ctx.expectItemExists("cell_2/No");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw input correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Input");

            details.processFrame(&settings, &.{ .players = .{
                .{ .input = null },
                .{ .input = .{} },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .players = .{
                .{ .input = .{ .up = true, .forward = true } },
                .{ .input = .{ .down = true, .back = true } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/uf");
            try ctx.expectItemExists("cell_2/db");

            details.processFrame(&settings, &.{ .players = .{
                .{ .input = .{ .up = true, .down = true } },
                .{ .input = .{ .forward = true, .back = true } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .players = .{
                .{ .input = .{ .button_1 = true } },
                .{ .input = .{ .button_2 = true, .button_3 = true } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/1");
            try ctx.expectItemExists("cell_2/2+3");

            details.processFrame(&settings, &.{ .players = .{
                .{ .input = .{ .down = true, .forward = true, .button_4 = true } },
                .{ .input = .{
                    .up = true,
                    .back = true,
                    .button_1 = true,
                    .button_2 = true,
                    .button_3 = true,
                    .button_4 = true,
                } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/df4");
            try ctx.expectItemExists("cell_2/ub1+2+3+4");

            details.processFrame(&settings, &.{ .players = .{
                .{ .input = .{ .special_style = true } },
                .{ .input = .{ .special_style = true, .heat = true } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/SS");
            try ctx.expectItemExists("cell_2/SS+H");

            details.processFrame(&settings, &.{ .players = .{
                .{ .input = .{ .back = true, .rage = true } },
                .{ .input = .{
                    .down = true,
                    .back = true,
                    .button_1 = true,
                    .button_2 = true,
                    .button_3 = true,
                    .button_4 = true,
                    .special_style = true,
                    .rage = true,
                    .heat = true,
                } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/bR");
            try ctx.expectItemExists("cell_2/db1+2+3+4+SS+R+H");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw distance to opponent correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Distance To Opponent [m]");

            details.processFrame(&settings, &.{ .players = .{ .{}, .{} } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .players = .{
                .{
                    .collision_spheres = .initFill(.{
                        .center = .fromArray(.{ 0, 0, 0 }),
                        .radius = 0,
                    }),
                    .hurt_cylinders = .initFill(.{ .cylinder = .{
                        .center = .fromArray(.{ 0, 0, 0 }),
                        .radius = 0,
                        .half_height = 0,
                    } }),
                },
                .{
                    .collision_spheres = .initFill(.{
                        .center = .fromArray(.{ 123.456, 0, 0 }),
                        .radius = 0,
                    }),
                    .hurt_cylinders = .initFill(.{ .cylinder = .{
                        .center = .fromArray(.{ 123.456, 0, 0 }),
                        .radius = 0,
                        .half_height = 0,
                    } }),
                },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/1.23");
            try ctx.expectItemExists("cell_2/1.23");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw angle to opponent correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Angle To Opponent [°]");

            details.processFrame(&settings, &.{ .players = .{ .{}, .{} } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(&settings, &.{ .players = .{
                .{
                    .collision_spheres = .initFill(.{
                        .center = .fromArray(.{ -1, 0, 0 }),
                        .radius = 0.0,
                    }),
                    .rotation = 0,
                },
                .{
                    .collision_spheres = .initFill(.{
                        .center = .fromArray(.{ 1, 0, 0 }),
                        .radius = 0.0,
                    }),
                    .rotation = 0.5 * std.math.pi,
                },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/-90.00");
            try ctx.expectItemExists("cell_2/0.00");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw distance to wall correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Distance To Wall [m]");

            details.processFrame(&settings, &.{
                .players = .{ .{}, .{} },
                .walls = .empty,
            });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(
                &settings,
                &.{
                    .players = .{
                        .{ .collision_spheres = .initFill(.{ .center = .fromArray(.{ -100, 0, 0 }), .radius = 0 }) },
                        .{ .collision_spheres = .initFill(.{ .center = .fromArray(.{ 100, 0, 0 }), .radius = 0 }) },
                    },
                    .walls = .{
                        .buffer = .{
                            model.Wall{ .edge_1 = .fromArray(.{ -223, -1 }), .edge_2_index = 1 },
                            model.Wall{ .edge_1 = .fromArray(.{ 556, -1 }), .edge_2_index = 2 },
                            model.Wall{ .edge_1 = .fromArray(.{ 556, 1 }), .edge_2_index = 3 },
                            model.Wall{ .edge_1 = .fromArray(.{ -223, 1 }), .edge_2_index = 0 },
                        } ++ ([1]model.Wall{undefined} ** (model.Walls.max_len - 4)),
                        .len = 4,
                    },
                },
            );
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/1.23");
            try ctx.expectItemExists("cell_2/4.56");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw angle to wall correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Angle To Wall [°]");

            details.processFrame(&settings, &.{
                .players = .{ .{}, .{} },
                .walls = .empty,
            });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/---");
            try ctx.expectItemExists("cell_2/---");

            details.processFrame(
                &settings,
                &.{
                    .players = .{
                        .{ .collision_spheres = .initFill(.{ .center = .fromArray(.{ -1, 0, 0 }), .radius = 0 }) },
                        .{ .collision_spheres = .initFill(.{ .center = .fromArray(.{ 1, 0, 0 }), .radius = 0 }) },
                    },
                    .walls = .{
                        .buffer = .{
                            model.Wall{ .edge_1 = .fromArray(.{ -100, -100 }), .edge_2_index = 1 },
                            model.Wall{ .edge_1 = .fromArray(.{ 300, -100 }), .edge_2_index = 2 },
                            model.Wall{ .edge_1 = .fromArray(.{ -100, 300 }), .edge_2_index = 0 },
                        } ++ ([1]model.Wall{undefined} ** (model.Walls.max_len - 3)),
                        .len = 4,
                    },
                },
            );
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/0.00");
            try ctx.expectItemExists("cell_2/-45.00");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw hit lines height correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Hit Lines Height [cm]");

            details.processFrame(&settings, &.{
                .floor_z = 0,
                .players = .{
                    .{ .hit_lines = .{
                        .buffer = undefined,
                        .len = 0,
                    } },
                    .{ .hit_lines = .{
                        .buffer = .{
                            .{ .line = .{
                                .point_1 = .fromArray(.{ 0, 0, 123.456 }),
                                .point_2 = .fromArray(.{ 0, 0, 456.789 }),
                            } },
                            undefined,
                            undefined,
                            undefined,
                            undefined,
                            undefined,
                            undefined,
                            undefined,
                        },
                        .len = 1,
                    } },
                },
            });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/--- - ---");
            try ctx.expectItemExists("cell_2/123.46 - 456.79");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw hurt cylinders height correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{ .rows_enabled = .{} };
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Hurt Cylinders Height [cm]");

            details.processFrame(&settings, &.{
                .floor_z = 0,
                .players = .{
                    .{ .hurt_cylinders = null },
                    .{ .hurt_cylinders = .initFill(.{ .cylinder = .{
                        .center = .fromArray(.{ 0, 0, 100 }),
                        .radius = 0,
                        .half_height = 25,
                    } }) },
                },
            });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/--- - ---");
            try ctx.expectItemExists("cell_2/75.00 - 125.00");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
