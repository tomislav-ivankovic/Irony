const std = @import("std");
const builtin = @import("builtin");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

const string_buffer_size = 128;
const empty_value_string = "---";
const error_string = "error";

pub fn drawDetails(frame: *const model.Frame, columns: model.MiscSettings.DetailsColumns) void {
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
    switch (columns) {
        .id_based => {
            imgui.igTableSetupColumn("Player 1", 0, 0, 0);
            imgui.igTableSetupColumn("Player 2", 0, 0, 0);
        },
        .side_based => {
            imgui.igTableSetupColumn("Left Player", 0, 0, 0);
            imgui.igTableSetupColumn("Right Player", 0, 0, 0);
        },
        .role_based => {
            imgui.igTableSetupColumn("Main Player", 0, 0, 0);
            imgui.igTableSetupColumn("Secondary Player", 0, 0, 0);
        },
    }

    imgui.igTableHeadersRow();

    const left, const right = switch (columns) {
        .id_based => .{
            frame.getPlayerById(.player_1),
            frame.getPlayerById(.player_2),
        },
        .side_based => .{
            frame.getPlayerBySide(.left),
            frame.getPlayerBySide(.right),
        },
        .role_based => .{
            frame.getPlayerByRole(.main),
            frame.getPlayerByRole(.secondary),
        },
    };
    drawProperty("Since Round Start", &frame.frames_since_round_start, &frame.frames_since_round_start);
    drawProperty("Character ID", &left.character_id, &right.character_id);
    drawProperty("Animation ID", &left.animation_id, &right.animation_id);
    drawProperty("Animation Frame", &left.animation_frame, &right.animation_frame);
    drawProperty("Animation Total Frames", &left.animation_total_frames, &right.animation_total_frames);
    drawProperty("Move Phase", &left.move_phase, &right.move_phase);
    drawProperty("Move Frame", &left.move_frame, &right.move_frame);
    drawProperty("Startup Frames", &left.getStartupFrames(), &right.getStartupFrames());
    drawProperty("Active Frames", &left.getActiveFrames(), &right.getActiveFrames());
    drawProperty("Recovery Frames", &left.getRecoveryFrames(), &right.getRecoveryFrames());
    drawProperty("Total Frames", &left.getTotalFrames(), &right.getTotalFrames());
    drawProperty("Frame Advantage", &left.getFrameAdvantage(right), &right.getFrameAdvantage(left));
    drawProperty("Attack Type", &left.attack_type, &right.attack_type);
    drawProperty(
        "Attack Range [m]",
        &(if (left.attack_range) |range| @as(?f32, 0.01 * range) else @as(?f32, null)),
        &(if (right.attack_range) |range| @as(?f32, 0.01 * range) else @as(?f32, null)),
    );
    drawProperty("Attack Height [cm]", &left.getAttackHeight(frame.floor_z), &right.getAttackHeight(frame.floor_z));
    drawProperty(
        "Recovery Range [m]",
        &(if (left.recovery_range) |range| @as(?f32, 0.01 * range) else @as(?f32, null)),
        &(if (right.recovery_range) |range| @as(?f32, 0.01 * range) else @as(?f32, null)),
    );
    drawProperty("Attack Damage", &left.attack_damage, &right.attack_damage);
    drawProperty("Hit Outcome", &left.hit_outcome, &right.hit_outcome);
    drawProperty("Posture", &left.posture, &right.posture);
    drawProperty("Blocking", &left.blocking, &right.blocking);
    drawProperty("Crushing", &left.crushing, &right.crushing);
    drawProperty("Can Move", &left.can_move, &right.can_move);
    drawProperty("Input", &left.input, &right.input);
    drawProperty("Health", &left.health, &right.health);
    drawProperty("Rage", &left.rage, &right.rage);
    drawProperty("Heat", &left.heat, &right.heat);
    drawProperty(
        "Distance To Opponent [m]",
        &(if (left.getDistanceTo(right)) |distance| @as(?f32, 0.01 * distance) else @as(?f32, null)),
        &(if (right.getDistanceTo(left)) |distance| @as(?f32, 0.01 * distance) else @as(?f32, null)),
    );
    drawProperty(
        "Angle To Opponent [°]",
        &(if (left.getAngleTo(right)) |angle| @as(?f32, std.math.radiansToDegrees(angle)) else @as(?f32, null)),
        &(if (right.getAngleTo(left)) |angle| @as(?f32, std.math.radiansToDegrees(angle)) else @as(?f32, null)),
    );
    drawProperty(
        "Hit Lines Height [cm]",
        &left.getHitLinesHeight(frame.floor_z),
        &right.getHitLinesHeight(frame.floor_z),
    );
    drawProperty(
        "Hurt Cylinders Height [cm]",
        &left.getHurtCylindersHeight(frame.floor_z),
        &right.getHurtCylindersHeight(frame.floor_z),
    );
}

fn drawProperty(name: [:0]const u8, left_pointer: anytype, right_pointer: anytype) void {
    if (imgui.igTableNextColumn()) {
        drawText(name);
    }
    if (imgui.igTableNextColumn()) {
        drawValue(left_pointer);
    }
    if (imgui.igTableNextColumn()) {
        drawValue(right_pointer);
    }
}

fn drawValue(pointer: anytype) void {
    const Pointer = @TypeOf(pointer);
    const Value = switch (@typeInfo(Pointer)) {
        .pointer => |*p| p.child,
        else => @compileError(
            "The drawValue function expects a pointer but provided value is of type: " ++ @typeName(Pointer),
        ),
    };
    if (Value == model.U32ActualMax) {
        drawU32ActualMax(pointer);
    } else if (Value == model.U32ActualMinMax) {
        drawU32ActualMinMax(pointer);
    } else if (Value == model.I32ActualMinMax) {
        drawI32ActualMinMax(pointer);
    } else if (Value == model.F32MinMax) {
        drawF32MinMax(pointer);
    } else if (Value == model.MovePhase) {
        drawMovePhase(pointer);
    } else if (Value == model.AttackType) {
        drawAttackType(pointer);
    } else if (Value == model.HitOutcome) {
        drawHitOutcome(pointer);
    } else if (Value == model.Posture) {
        drawPosture(pointer);
    } else if (Value == model.Blocking) {
        drawBlocking(pointer);
    } else if (Value == model.Crushing) {
        drawCrushing(pointer);
    } else if (Value == model.Input) {
        drawInput(pointer);
    } else if (Value == model.Rage) {
        drawRage(pointer);
    } else if (Value == model.Heat) {
        drawHeat(pointer);
    } else switch (@typeInfo(Value)) {
        .bool => drawBool(pointer),
        .int => drawInt(pointer),
        .float => drawFloat(pointer),
        .optional => drawOptional(pointer),
        else => @compileError("Unsupported type " ++ @typeName(Value) ++ " provided to the drawValue function."),
    }
}

fn drawBool(pointer: *const bool) void {
    const text = if (pointer.*) "Yes" else "No";
    drawText(text);
}

fn drawInt(pointer: anytype) void {
    var buffer: [string_buffer_size]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buffer, "{}", .{pointer.*}) catch error_string;
    drawText(text);
}

fn drawFloat(pointer: anytype) void {
    var buffer: [string_buffer_size]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buffer, "{d:.2}", .{pointer.*}) catch error_string;
    drawText(text);
}

fn drawOptional(pointer: anytype) void {
    if (pointer.*) |*child| {
        drawValue(child);
    } else {
        drawText(empty_value_string);
    }
}

fn drawU32ActualMax(pointer: *const model.U32ActualMax) void {
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var stream = std.io.fixedBufferStream(&buffer);
    if (pointer.actual) |actual| {
        stream.writer().print("{}", .{actual}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    _ = stream.write(" (") catch {};
    if (pointer.max) |max| {
        stream.writer().print("{}", .{max}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    _ = stream.write(")") catch {};
    if (stream.pos >= buffer.len - 1) {
        drawText(error_string);
        return;
    }
    drawText(buffer[0..stream.pos :0]);
}

fn drawU32ActualMinMax(pointer: *const model.U32ActualMinMax) void {
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var stream = std.io.fixedBufferStream(&buffer);
    if (pointer.actual) |actual| {
        stream.writer().print("{}", .{actual}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    _ = stream.write(" (") catch {};
    if (pointer.min) |min| {
        stream.writer().print("{}", .{min}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    _ = stream.write(" - ") catch {};
    if (pointer.max) |max| {
        stream.writer().print("{}", .{max}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    _ = stream.write(")") catch {};
    if (stream.pos >= buffer.len - 1) {
        drawText(error_string);
        return;
    }
    drawText(buffer[0..stream.pos :0]);
}

fn drawI32ActualMinMax(pointer: *const model.I32ActualMinMax) void {
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var stream = std.io.fixedBufferStream(&buffer);
    if (pointer.actual) |actual| {
        if (actual > 0) {
            _ = stream.write("+") catch {};
        }
        stream.writer().print("{}", .{actual}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    _ = stream.write(" (") catch {};
    if (pointer.min) |min| {
        if (min > 0) {
            _ = stream.write("+") catch {};
        }
        stream.writer().print("{}", .{min}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    _ = stream.write(", ") catch {};
    if (pointer.max) |max| {
        if (max > 0) {
            _ = stream.write("+") catch {};
        }
        stream.writer().print("{}", .{max}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    _ = stream.write(")") catch {};
    if (stream.pos >= buffer.len - 1) {
        drawText(error_string);
        return;
    }
    drawText(buffer[0..stream.pos :0]);
}

fn drawF32MinMax(pointer: *const model.F32MinMax) void {
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var stream = std.io.fixedBufferStream(&buffer);
    if (pointer.min) |min| {
        stream.writer().print("{d:.2}", .{min}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    _ = stream.write(" - ") catch {};
    if (pointer.max) |max| {
        stream.writer().print("{d:.2}", .{max}) catch {};
    } else {
        _ = stream.write(empty_value_string) catch {};
    }
    if (stream.pos >= buffer.len - 1) {
        drawText(error_string);
        return;
    }
    drawText(buffer[0..stream.pos :0]);
}

fn drawMovePhase(pointer: *const model.MovePhase) void {
    const text = switch (pointer.*) {
        .neutral => "Neutral",
        .start_up => "Start Up",
        .active => "Active",
        .active_recovery => "Active Recovery",
        .recovery => "Recovery",
    };
    drawText(text);
}

fn drawAttackType(pointer: *const model.AttackType) void {
    const text = switch (pointer.*) {
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
    drawText(text);
}

fn drawHitOutcome(pointer: *const model.HitOutcome) void {
    const text = switch (pointer.*) {
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
    drawText(text);
}

fn drawPosture(pointer: *const model.Posture) void {
    const text = switch (pointer.*) {
        .standing => "Standing",
        .crouching => "Crouching",
        .downed_face_up => "Downed Face Up",
        .downed_face_down => "Downed Face Down",
        .airborne => "Airborne",
    };
    drawText(text);
}

fn drawBlocking(pointer: *const model.Blocking) void {
    const text = switch (pointer.*) {
        .not_blocking => "Not",
        .neutral_blocking_mids => "Neutral Mids",
        .fully_blocking_mids => "Fully Mids",
        .neutral_blocking_lows => "Neutral Lows",
        .fully_blocking_lows => "Fully Lows",
    };
    drawText(text);
}

fn drawCrushing(pointer: *const model.Crushing) void {
    const crushing = pointer.*;
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var stream = std.io.fixedBufferStream(&buffer);
    var is_first = true;
    if (crushing.invincibility) {
        if (!is_first) {
            _ = stream.write("+") catch {};
        }
        _ = stream.write("Everything") catch {};
        is_first = false;
    } else {
        if (crushing.high_crushing) {
            if (!is_first) {
                _ = stream.write(", ") catch {};
            }
            _ = stream.write("Highs") catch {};
            is_first = false;
        }
        if (crushing.low_crushing) {
            if (!is_first) {
                _ = stream.write(", ") catch {};
            }
            _ = stream.write("Lows") catch {};
            is_first = false;
        }
        if (crushing.anti_air_only_crushing) {
            if (!is_first) {
                _ = stream.write(", ") catch {};
            }
            _ = stream.write("Anti-Airs") catch {};
            is_first = false;
        }
    }
    if (crushing.power_crushing) {
        if (!is_first) {
            _ = stream.write(", ") catch {};
        }
        _ = stream.write("Power-Crushing") catch {};
        is_first = false;
    }
    if (stream.pos == 0) {
        drawText(empty_value_string);
    } else if (stream.pos >= buffer.len - 1) {
        drawText(error_string);
    } else {
        drawText(buffer[0..stream.pos :0]);
    }
}

fn drawInput(pointer: *const model.Input) void {
    const input = pointer.*;
    var buffer: [string_buffer_size]u8 = [1]u8{0} ** string_buffer_size;
    var stream = std.io.fixedBufferStream(&buffer);
    if (input.up and !input.down) {
        _ = stream.write("u") catch {};
    }
    if (input.down and !input.up) {
        _ = stream.write("d") catch {};
    }
    if (input.forward and !input.back) {
        _ = stream.write("f") catch {};
    }
    if (input.back and !input.forward) {
        _ = stream.write("b") catch {};
    }
    var is_first = true;
    if (input.button_1) {
        if (!is_first) {
            _ = stream.write("+") catch {};
        }
        _ = stream.write("1") catch {};
        is_first = false;
    }
    if (input.button_2) {
        if (!is_first) {
            _ = stream.write("+") catch {};
        }
        _ = stream.write("2") catch {};
        is_first = false;
    }
    if (input.button_3) {
        if (!is_first) {
            _ = stream.write("+") catch {};
        }
        _ = stream.write("3") catch {};
        is_first = false;
    }
    if (input.button_4) {
        if (!is_first) {
            _ = stream.write("+") catch {};
        }
        _ = stream.write("4") catch {};
        is_first = false;
    }
    if (input.special_style) {
        if (!is_first) {
            _ = stream.write("+") catch {};
        }
        _ = stream.write("SS") catch {};
        is_first = false;
    }
    if (input.heat) {
        if (!is_first) {
            _ = stream.write("+") catch {};
        }
        _ = stream.write("H") catch {};
        is_first = false;
    }
    if (input.rage) {
        if (!is_first) {
            _ = stream.write("+") catch {};
        }
        _ = stream.write("R") catch {};
        is_first = false;
    }
    if (stream.pos == 0) {
        drawText(empty_value_string);
    } else if (stream.pos >= buffer.len - 1) {
        drawText(error_string);
    } else {
        drawText(buffer[0..stream.pos :0]);
    }
}

fn drawRage(pointer: *const model.Rage) void {
    const text = switch (pointer.*) {
        .available => "Available",
        .activated => "Activated",
        .used_up => "Used Up",
    };
    drawText(text);
}

fn drawHeat(pointer: *const model.Heat) void {
    const text = switch (pointer.*) {
        .available => "Available",
        .activated => |activated| {
            const percent = activated.gauge * 100;
            var buffer: [string_buffer_size]u8 = undefined;
            const text = std.fmt.bufPrintZ(&buffer, "Activated: {d:.1}%", .{percent}) catch error_string;
            drawText(text);
            return;
        },
        .used_up => "Used Up",
    };
    drawText(text);
}

fn drawText(text: [:0]const u8) void {
    imgui.igText("%s", text.ptr);

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
