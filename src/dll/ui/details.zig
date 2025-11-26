const std = @import("std");
const builtin = @import("builtin");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

pub const Details = struct {
    frames_since_round_start: Row(
        "Since Round Start",
        \\Number of frames that passed since round start.
        \\Does not increase beyond 65535.
    ,
        u32,
        null,
        drawU32,
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
    attack_damage: Row(
        "Attack Damage",
        \\Damage that the current attack inflicts to the opponent on normal hit.
        \\Same value irregardless if the actual attack whiffs, gets blocked, normal-hits or counter-hits the opponent.
    ,
        i32,
        0,
        drawI32,
    ) = .{},
    hit_outcome: Row(
        "Hit Outcome",
        "Outcome of the hit line hurt cylinder interaction.",
        model.HitOutcome,
        .none,
        drawHitOutcome,
    ) = .{},
    posture: Row(
        "Posture",
        \\One of the following:
        \\Standing - Can block mid and high attacks. Gets hit my lows attacks.
        \\Crouching - Can block low attacks. Gets hit my mid attacks. Crushes high attacks.
        \\Downed Face Up - Gets hit by mid and low attacks. Crushes high attacks.
        \\Downed Face Down - Gets hit by mid and low attacks. Crushes high attacks.
        \\Airborne - Getting hit results in getting floated. Does not necessarily crush low attacks.
        \\
        \\IMPORTANT:
        \\The detection of Airborne is currently not working correctly.
        \\Do not rely on this application to show you on what frame the Airborne state of a move starts and stops.
        \\Doing so will give you incorrect information.
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
        \\
        \\IMPORTANT:
        \\The detection of low crushing is currently not working correctly.
        \\Do not rely on this application to show you on what frame the low crushing of a move starts and stops.
        \\Doing so will give you incorrect information.
    ,
        model.Crushing,
        null,
        drawCrushing,
    ) = .{},
    can_move: Row(
        "Can Move",
        "Whether the player is free to move or stuck in a recovery animation.",
        bool,
        null,
        drawYesNo,
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
    health: Row(
        "Health",
        "Remaining health points that the player has.",
        i32,
        null,
        drawI32,
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
        self.frames_since_round_start.processFrame(s, frame.frames_since_round_start, frame.frames_since_round_start);
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
        self.attack_damage.processFrame(s, c1.attack_damage, c2.attack_damage);
        self.hit_outcome.processFrame(s, c1.hit_outcome, c2.hit_outcome);
        self.posture.processFrame(s, c1.posture, c2.posture);
        self.blocking.processFrame(s, c1.blocking, c2.blocking);
        self.crushing.processFrame(s, c1.crushing, c2.crushing);
        self.can_move.processFrame(s, c1.can_move, c2.can_move);
        self.input.processFrame(s, c1.input, c2.input);
        self.health.processFrame(s, c1.health, c2.health);
        self.rage.processFrame(s, c1.rage, c2.rage);
        self.heat.processFrame(s, c1.heat, c2.heat);
        self.distance_to_opponent.processFrame(s, c1.getDistanceTo(c2), c2.getDistanceTo(c1));
        self.angle_to_opponent.processFrame(s, c1.getAngleTo(c2), c2.getAngleTo(c1));
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

fn drawI32(value: i32, alpha: f32) void {
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

fn drawU32ActualMax(value: model.U32ActualMax, alpha: f32) void {
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var stream = std.io.fixedBufferStream(&buffer);
    if (value.actual) |actual| {
        stream.writer().print("{}", .{actual}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    _ = stream.write(" (") catch {};
    if (value.max) |max| {
        stream.writer().print("{}", .{max}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    _ = stream.write(")") catch {};
    if (stream.pos >= buffer.len - 1) {
        drawText(error_string, alpha);
        return;
    }
    drawText(buffer[0..stream.pos :0], alpha);
}

fn drawU32ActualMinMax(value: model.U32ActualMinMax, alpha: f32) void {
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var stream = std.io.fixedBufferStream(&buffer);
    if (value.actual) |actual| {
        stream.writer().print("{}", .{actual}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    _ = stream.write(" (") catch {};
    if (value.min) |min| {
        stream.writer().print("{}", .{min}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    _ = stream.write(" - ") catch {};
    if (value.max) |max| {
        stream.writer().print("{}", .{max}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    _ = stream.write(")") catch {};
    if (stream.pos >= buffer.len - 1) {
        drawText(error_string, alpha);
        return;
    }
    drawText(buffer[0..stream.pos :0], alpha);
}

fn drawI32ActualMinMax(value: model.I32ActualMinMax, alpha: f32) void {
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var stream = std.io.fixedBufferStream(&buffer);
    if (value.actual) |actual| {
        if (actual > 0) {
            _ = stream.write("+") catch {};
        }
        stream.writer().print("{}", .{actual}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    _ = stream.write(" (") catch {};
    if (value.min) |min| {
        if (min > 0) {
            _ = stream.write("+") catch {};
        }
        stream.writer().print("{}", .{min}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    _ = stream.write(", ") catch {};
    if (value.max) |max| {
        if (max > 0) {
            _ = stream.write("+") catch {};
        }
        stream.writer().print("{}", .{max}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    _ = stream.write(")") catch {};
    if (stream.pos >= buffer.len - 1) {
        drawText(error_string, alpha);
        return;
    }
    drawText(buffer[0..stream.pos :0], alpha);
}

fn drawF32MinMax(value: model.F32MinMax, alpha: f32) void {
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var stream = std.io.fixedBufferStream(&buffer);
    if (value.min) |min| {
        stream.writer().print("{d:.2}", .{min}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    _ = stream.write(" - ") catch {};
    if (value.max) |max| {
        stream.writer().print("{d:.2}", .{max}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    if (stream.pos >= buffer.len - 1) {
        drawText(error_string, alpha);
        return;
    }
    drawText(buffer[0..stream.pos :0], alpha);
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

fn drawCrushing(value: model.Crushing, alpha: f32) void {
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var stream = std.io.fixedBufferStream(&buffer);
    var is_first = true;
    if (value.invincibility) {
        if (!is_first) {
            _ = stream.write("+") catch {};
        }
        _ = stream.write("Everything") catch {};
        is_first = false;
    } else {
        if (value.high_crushing) {
            if (!is_first) {
                _ = stream.write(", ") catch {};
            }
            _ = stream.write("Highs") catch {};
            is_first = false;
        }
        if (value.low_crushing) {
            if (!is_first) {
                _ = stream.write(", ") catch {};
            }
            _ = stream.write("Lows") catch {};
            is_first = false;
        }
        if (value.anti_air_only_crushing) {
            if (!is_first) {
                _ = stream.write(", ") catch {};
            }
            _ = stream.write("Anti-Airs") catch {};
            is_first = false;
        }
    }
    if (value.power_crushing) {
        if (!is_first) {
            _ = stream.write(", ") catch {};
        }
        _ = stream.write("Power-Crushing") catch {};
        is_first = false;
    }
    if (stream.pos == 0) {
        drawText(empty_value_string, alpha);
    } else if (stream.pos >= buffer.len - 1) {
        drawText(error_string, alpha);
    } else {
        drawText(buffer[0..stream.pos :0], alpha);
    }
}

fn drawInput(value: model.Input, alpha: f32) void {
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var stream = std.io.fixedBufferStream(&buffer);
    if (value.up and !value.down) {
        _ = stream.write("u") catch {};
    }
    if (value.down and !value.up) {
        _ = stream.write("d") catch {};
    }
    if (value.forward and !value.back) {
        _ = stream.write("f") catch {};
    }
    if (value.back and !value.forward) {
        _ = stream.write("b") catch {};
    }
    var is_first = true;
    if (value.button_1) {
        if (!is_first) {
            _ = stream.write("+") catch {};
        }
        _ = stream.write("1") catch {};
        is_first = false;
    }
    if (value.button_2) {
        if (!is_first) {
            _ = stream.write("+") catch {};
        }
        _ = stream.write("2") catch {};
        is_first = false;
    }
    if (value.button_3) {
        if (!is_first) {
            _ = stream.write("+") catch {};
        }
        _ = stream.write("3") catch {};
        is_first = false;
    }
    if (value.button_4) {
        if (!is_first) {
            _ = stream.write("+") catch {};
        }
        _ = stream.write("4") catch {};
        is_first = false;
    }
    if (value.special_style) {
        if (!is_first) {
            _ = stream.write("+") catch {};
        }
        _ = stream.write("SS") catch {};
        is_first = false;
    }
    if (value.rage) {
        if (!is_first) {
            _ = stream.write("+") catch {};
        }
        _ = stream.write("R") catch {};
        is_first = false;
    }
    if (value.heat) {
        if (!is_first) {
            _ = stream.write("+") catch {};
        }
        _ = stream.write("H") catch {};
        is_first = false;
    }
    if (stream.pos == 0) {
        drawText(empty_value_string, alpha);
    } else if (stream.pos >= buffer.len - 1) {
        drawText(error_string, alpha);
    } else {
        drawText(buffer[0..stream.pos :0], alpha);
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
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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

test "should draw frames since round start correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{};
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

test "should draw character ID correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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

test "should draw move frame correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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

test "should draw frame advantage correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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

test "should draw attack damage correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{};
        var details = Details{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            details.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window/table/Attack Damage");

            details.processFrame(&settings, &.{ .players = .{
                .{ .attack_damage = null },
                .{ .attack_damage = 0 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/0");
            try ctx.expectItemExists("cell_2/0");

            details.processFrame(&settings, &.{ .players = .{
                .{ .attack_damage = 123 },
                .{ .attack_damage = 456 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("cell_1/123");
            try ctx.expectItemExists("cell_2/456");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw hit outcome correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{};
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

test "should draw posture correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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

test "should draw can move correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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

test "should draw health correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{};
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

test "should draw rage correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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

test "should draw distance to opponent correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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

test "should draw hit lines height correctly" {
    const Test = struct {
        var settings = model.DetailsSettings{};
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
        var settings = model.DetailsSettings{};
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
