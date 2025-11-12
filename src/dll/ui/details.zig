const std = @import("std");
const builtin = @import("builtin");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

pub const Details = struct {
    frames_since_round_start: Row("Since Round Start", u32, null, drawU32) = .{},
    character_id: Row("Character ID", u32, null, drawU32) = .{},
    animation_id: Row("Animation ID", u32, null, drawU32) = .{},
    animation_frame: Row("Animation Frame", u32, null, drawU32) = .{},
    animation_total_frames: Row("Animation Total Frames", u32, null, drawU32) = .{},
    move_phase: Row("Move Phase", model.MovePhase, null, drawMovePhase) = .{},
    move_frame: Row("Move Frame", u32, null, drawU32) = .{},
    startup_frames: Row("Startup Frames", model.U32ActualMinMax, .nulls, drawU32ActualMinMax) = .{},
    active_frames: Row("Active Frames", model.U32ActualMax, .nulls, drawU32ActualMax) = .{},
    recovery_frames: Row("Recovery Frames", model.U32ActualMinMax, .nulls, drawU32ActualMinMax) = .{},
    total_frames: Row("Total Frames", u32, null, drawU32) = .{},
    frame_advantage: Row("Frame Advantage", model.I32ActualMinMax, .nulls, drawI32ActualMinMax) = .{},
    attack_type: Row("Attack Type", model.AttackType, .not_attack, drawAttackType) = .{},
    attack_range: Row("Attack Range [m]", f32, null, drawF32Div100) = .{},
    attack_height: Row("Attack Height [cm]", model.F32MinMax, .nulls, drawF32MinMax) = .{},
    recovery_range: Row("Recovery Range [m]", f32, null, drawF32Div100) = .{},
    attack_damage: Row("Attack Damage", i32, null, drawI32) = .{},
    hit_outcome: Row("Hit Outcome", model.HitOutcome, .none, drawHitOutcome) = .{},
    posture: Row("Posture", model.Posture, null, drawPosture) = .{},
    blocking: Row("Blocking", model.Blocking, null, drawBlocking) = .{},
    crushing: Row("Crushing", model.Crushing, null, drawCrushing) = .{},
    can_move: Row("Can Move", bool, null, drawYesNo) = .{},
    input: Row("Input", model.Input, null, drawInput) = .{},
    health: Row("Health", i32, null, drawI32) = .{},
    rage: Row("Rage", model.Rage, null, drawRage) = .{},
    heat: Row("Heat", model.Heat, null, drawHeat) = .{},
    distance_to_opponent: Row("Distance To Opponent [m]", f32, null, drawF32Div100) = .{},
    angle_to_opponent: Row("Angle To Opponent [°]", f32, null, drawF32) = .{},
    hit_lines_height: Row("Hit Lines Height [cm]", model.F32MinMax, .nulls, drawF32MinMax) = .{},
    hurt_cylinders_height: Row("Hurt Cylinders Height [cm]", model.F32MinMax, .nulls, drawF32MinMax) = .{},

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
        const render_content = imgui.igBeginTable("details_table", 3, table_flags, table_size, 0);
        if (!render_content) return;
        defer imgui.igEndTable();

        imgui.igTableSetupScrollFreeze(0, 1);
        imgui.igTableSetupColumn("Property", 0, 0, 0);
        const column_1_name = switch (settings.column_1) {
            .player_1 => "Player 1",
            .player_2 => "Player 2",
            .left_player => "Left Player",
            .right_player => "Right Player",
            .main_player => "Main Player",
            .secondary_player => "Secondary Player",
        };
        imgui.igTableSetupColumn(column_1_name, 0, 0, 0);
        const column_2_name = switch (settings.column_2) {
            .player_1 => "Player 1",
            .player_2 => "Player 2",
            .left_player => "Left Player",
            .right_player => "Right Player",
            .main_player => "Main Player",
            .secondary_player => "Secondary Player",
        };
        imgui.igTableSetupColumn(column_2_name, 0, 0, 0);
        imgui.igTableHeadersRow();

        inline for (@typeInfo(Self).@"struct".fields) |*field| {
            if (@field(settings.rows_enabled, field.name)) {
                @field(self, field.name).draw(settings);
            }
        }
    }
};

fn Row(
    comptime name: [:0]const u8,
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
            }
            if (imgui.igTableNextColumn()) {
                self.cell_1.draw(settings);
            }
            if (imgui.igTableNextColumn()) {
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
                return;
            }
            const completion = 1.0 - (self.remaining_time / settings.fade_out_duration);
            const alpha = 1.0 - (completion * completion * completion * completion);
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
    if (value.heat) {
        if (!is_first) {
            _ = stream.write("+") catch {};
        }
        _ = stream.write("H") catch {};
        is_first = false;
    }
    if (value.rage) {
        if (!is_first) {
            _ = stream.write("+") catch {};
        }
        _ = stream.write("R") catch {};
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
