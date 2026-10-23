const std = @import("std");
const builtin = @import("builtin");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

pub const MatchBar = struct {
    frames_left_in_round: ?u32 = null,
    rounds_needed_to_win: u32 = 3,
    player_states: std.EnumArray(model.PlayerId, PlayerState) = .initFill(.{}),

    const Self = @This();
    const PlayerState = struct {
        health_bar: HealthBarState = .{},
        name: model.PlayerName = .empty,
        heat: model.Heat = .used_up,
        rounds_won: AnimatedValue = .{},
    };
    const HealthBarState = struct {
        max_health: u32 = 0,
        health: u32 = 0,
        recoverable_health: u32 = 0,
        damage: AnimatedValue = .{},
        rage: model.Rage = .used_up,
    };
    const AnimatedValue = struct {
        current_value: u32 = 0,
        starting_value: u32 = 0,
        remaining_time: f32 = 0,
    };
    const Side = enum { left, right };

    pub fn processFrame(self: *Self, settings: *const model.MatchBarSettings, frame: *const model.Frame) void {
        self.frames_left_in_round = frame.frames_left_in_round;
        self.rounds_needed_to_win = frame.rounds_needed_to_win orelse 3;
        for (model.PlayerId.all) |player_id| {
            const state = self.player_states.getPtr(player_id);
            const player: *const model.Player = frame.getPlayerById(player_id);
            const other_player: *const model.Player = frame.getPlayerById(player_id.getOther());

            const max_health = player.max_health orelse 0;
            const health = @min(player.health orelse 0, max_health);
            const recoverable_health = @min(player.getRecoverableHealth() orelse 0, max_health - health);
            const combo_damage = @min(other_player.combo_damage orelse 0, max_health - health);
            state.health_bar.max_health = max_health;
            state.health_bar.health = health;
            state.health_bar.recoverable_health = recoverable_health;
            if (health > 0 and combo_damage > 0) {
                state.health_bar.damage.current_value = combo_damage;
                state.health_bar.damage.starting_value = combo_damage;
                state.health_bar.damage.remaining_time = settings.health_bar.damage_animation_duration;
            } else {
                state.health_bar.damage.current_value = 0;
            }
            if (state.health_bar.damage.starting_value > max_health - health) {
                state.health_bar.damage.starting_value = max_health - health;
            }

            state.health_bar.rage = player.rage orelse .used_up;
            state.name = player.name;
            state.heat = player.heat orelse .used_up;

            const rounds_won = @min(player.rounds_won orelse 0, self.rounds_needed_to_win);
            if (rounds_won != state.rounds_won.current_value) {
                state.rounds_won.starting_value = state.rounds_won.current_value;
                state.rounds_won.current_value = rounds_won;
                state.rounds_won.remaining_time = settings.round_count.animation_duration;
            }
        }
    }

    pub fn update(self: *Self, delta_time: f32) void {
        for (&self.player_states.values) |*state| {
            state.health_bar.damage.remaining_time -= delta_time;
            if (state.health_bar.damage.remaining_time < 0) {
                state.health_bar.damage.remaining_time = 0;
            }
            state.rounds_won.remaining_time -= delta_time;
            if (state.rounds_won.remaining_time < 0) {
                state.rounds_won.remaining_time = 0;
            }
        }
    }

    pub fn draw(self: Self, settings: *const model.MatchBarSettings) void {
        if (!settings.enabled) {
            return;
        }
        var available_size: imgui.ImVec2 = undefined;
        imgui.igGetContentRegionAvail(&available_size);
        const spacing = imgui.igGetStyle().*.ItemSpacing.x;
        const inner_spacing = imgui.igGetStyle().*.ItemInnerSpacing.x;

        imgui.igPushStyleVarY(imgui.ImGuiStyleVar_FramePadding, 0);
        defer imgui.igPopStyleVar(1);

        const timer_width = block: {
            imgui.igPushFont(null, 2 * imgui.igGetFontSize());
            defer imgui.igPopFont();
            var size: imgui.ImVec2 = undefined;
            imgui.igCalcTextSize(&size, "88", null, false, -1);
            break :block size.x;
        };
        const health_bar_width = 0.5 * (available_size.x - timer_width - (2 * spacing));
        const rounds_needed_to_win_float: f32 = @floatFromInt(self.rounds_needed_to_win);
        const round_count_width = (rounds_needed_to_win_float * imgui.igGetFrameHeight()) +
            ((rounds_needed_to_win_float - 1) * inner_spacing);
        const heat_bar_width = @min(
            0.5 * health_bar_width,
            0.5 * (available_size.x - (2 * round_count_width) - timer_width - (4 * spacing)),
        );
        const player_name_width = switch (self.rounds_needed_to_win) {
            0 => 0.5 * (available_size.x - (2 * heat_bar_width) - timer_width - (4 * spacing)),
            else => 0.5 *
                (available_size.x - (2 * round_count_width) - (2 * heat_bar_width) - timer_width - (6 * spacing)),
        };

        {
            imgui.igPushID_Str("left");
            defer imgui.igPopID();
            imgui.igBeginGroup();
            defer imgui.igEndGroup();

            const p = self.player_states.getPtrConst(.player_1);
            drawHealthBar("health_bar", &settings.health_bar, &p.health_bar, health_bar_width, .left);
            drawPlayerName("player_name", &p.name, player_name_width, .left);
            imgui.igSameLine(0, -1);
            drawHeatBar("heat_bar", &settings.heat_bar, p.heat, heat_bar_width, .left);
            if (self.rounds_needed_to_win > 0) {
                imgui.igSameLine(0, -1);
                drawRoundCount(
                    "round_count",
                    &settings.round_count,
                    &p.rounds_won,
                    self.rounds_needed_to_win,
                    round_count_width,
                    .left,
                );
            }
        }
        imgui.igSameLine(0, -1);
        {
            imgui.igPushFont(null, 2 * imgui.igGetFontSize());
            defer imgui.igPopFont();

            drawRoundTimer("round_timer", self.frames_left_in_round, timer_width);
        }
        imgui.igSameLine(0, -1);
        {
            imgui.igPushID_Str("right");
            defer imgui.igPopID();
            imgui.igBeginGroup();
            defer imgui.igEndGroup();

            const p = self.player_states.getPtrConst(.player_2);
            drawHealthBar("health_bar", &settings.health_bar, &p.health_bar, health_bar_width, .right);
            if (self.rounds_needed_to_win > 0) {
                drawRoundCount(
                    "round_count",
                    &settings.round_count,
                    &p.rounds_won,
                    self.rounds_needed_to_win,
                    round_count_width,
                    .right,
                );
                imgui.igSameLine(0, -1);
            }
            drawHeatBar("heat_bar", &settings.heat_bar, p.heat, heat_bar_width, .right);
            imgui.igSameLine(0, -1);
            drawPlayerName("player_name", &p.name, player_name_width, .right);
        }
    }

    fn drawRoundTimer(id_string: [:0]const u8, frames_left_in_round: ?u32, width: f32) void {
        const style = imgui.igGetStyle();
        const size = imgui.ImVec2{ .x = width, .y = imgui.igGetFrameHeight() };
        var rect: imgui.ImRect = undefined;
        imgui.igGetCursorScreenPos(&rect.Min);
        rect.Max = .{ .x = rect.Min.x + size.x, .y = rect.Min.y + size.y };

        const id = imgui.igGetID_Str(id_string);
        imgui.igItemSize_Vec2(size, -1.0);
        if (!imgui.igItemAdd(rect, id, null, 0)) {
            return;
        }
        if (builtin.is_test) {
            imgui.teItemAdd(imgui.igGetCurrentContext(), id, &rect, null);
        }

        var buffer: [16]u8 = undefined;
        const text = if (frames_left_in_round) |frames| block: {
            const seconds = switch (frames % 60) {
                0 => @divExact(frames, 60),
                else => @divFloor(frames, 60) + 1,
            };
            break :block std.fmt.bufPrintSentinel(&buffer, "{}", .{seconds}, 0) catch "---";
        } else "∞";
        if (imgui.igButtonBehavior(rect, id, null, null, 0)) {
            imgui.igSetClipboardText(text);
            sdk.ui.toasts.send(.info, null, "Copied to clipboard: {s}", .{text});
        }
        if (builtin.is_test) {
            var test_buffer: [buffer.len + 32]u8 = undefined;
            const test_text = std.fmt.bufPrintSentinel(&test_buffer, "{s}: {s}", .{ id_string, text }, 0) catch "error";
            imgui.teItemAdd(imgui.igGetCurrentContext(), imgui.igGetID_Str(test_text), &rect, null);
        }

        var text_size: imgui.ImVec2 = undefined;
        imgui.igCalcTextSize(&text_size, text, null, false, -1);
        const text_pos = imgui.ImVec2{
            .x = rect.Min.x + (0.5 * size.x) - (0.5 * text_size.x),
            .y = rect.Min.y + (0.5 * size.y) - (0.5 * text_size.y),
        };
        const colors: []const imgui.ImVec4 = style.*.Colors[0..style.*.Colors.len];
        const color = imgui.igGetColorU32_Vec4(colors[imgui.ImGuiCol_Text]);

        const draw_list = imgui.igGetWindowDrawList();
        imgui.ImDrawList_AddText_Vec2(draw_list, text_pos, color, text, null);
    }

    fn drawPlayerName(
        id_string: [:0]const u8,
        name: *const model.PlayerName,
        width: f32,
        side: Side,
    ) void {
        const size = imgui.ImVec2{ .x = width, .y = imgui.igGetFrameHeight() };
        var rect: imgui.ImRect = undefined;
        imgui.igGetCursorScreenPos(&rect.Min);
        rect.Max = .{ .x = rect.Min.x + size.x, .y = rect.Min.y + size.y };

        const id = imgui.igGetID_Str(id_string);
        imgui.igItemSize_Vec2(size, -1.0);
        if (!imgui.igItemAdd(rect, id, null, 0)) {
            return;
        }
        if (builtin.is_test) {
            imgui.teItemAdd(imgui.igGetCurrentContext(), id, &rect, null);
        }

        const text = name.asSlice();
        if (imgui.igButtonBehavior(rect, id, null, null, 0)) {
            imgui.igSetClipboardText(text);
            sdk.ui.toasts.send(.info, null, "Copied to clipboard: {s}", .{text});
        }
        if (builtin.is_test) {
            var test_buffer: [model.PlayerName.buffer_len + 32]u8 = undefined;
            const test_text = std.fmt.bufPrintSentinel(&test_buffer, "{s}: {s}", .{ id_string, text }, 0) catch "error";
            imgui.teItemAdd(imgui.igGetCurrentContext(), imgui.igGetID_Str(test_text), &rect, null);
        }

        var text_size: imgui.ImVec2 = undefined;
        imgui.igCalcTextSize(&text_size, text, null, false, -1);
        const text_rect = imgui.ImRect{
            .Min = .{
                .x = switch (side) {
                    .left => rect.Min.x,
                    .right => @max(rect.Max.x - text_size.x, rect.Min.x),
                },
                .y = rect.Min.y + (0.5 * size.y) - (0.5 * text_size.y),
            },
            .Max = .{
                .x = switch (side) {
                    .left => @min(rect.Min.x + text_size.x, rect.Max.x),
                    .right => rect.Max.x,
                },
                .y = rect.Min.y + (0.5 * size.y) + (0.5 * text_size.y),
            },
        };

        const draw_list = imgui.igGetWindowDrawList();
        imgui.igRenderTextEllipsis(draw_list, text_rect.Min, text_rect.Max, text_rect.Max.x, text, null, null);
    }

    fn drawRoundCount(
        id_string: [:0]const u8,
        settings: *const model.MatchBarSettings.RoundCount,
        rounds_won: *const AnimatedValue,
        rounds_needed_to_win: u32,
        width: f32,
        side: Side,
    ) void {
        const size = imgui.ImVec2{ .x = width, .y = imgui.igGetFrameHeight() };
        var rect: imgui.ImRect = undefined;
        imgui.igGetCursorScreenPos(&rect.Min);
        rect.Max = .{ .x = rect.Min.x + size.x, .y = rect.Min.y + size.y };

        const id = imgui.igGetID_Str(id_string);
        imgui.igItemSize_Vec2(size, -1.0);
        if (!imgui.igItemAdd(rect, id, null, 0)) {
            return;
        }
        if (builtin.is_test) {
            imgui.teItemAdd(imgui.igGetCurrentContext(), id, &rect, null);
        }

        var buffer: [16]u8 = undefined;
        const text = std.fmt.bufPrintSentinel(
            &buffer,
            "{}/{}",
            .{ rounds_won.current_value, rounds_needed_to_win },
            0,
        ) catch "error";
        if (imgui.igButtonBehavior(rect, id, null, null, 0)) {
            imgui.igSetClipboardText(text);
            sdk.ui.toasts.send(.info, null, "Copied to clipboard: {s}", .{text});
        }
        if (builtin.is_test) {
            var test_buffer: [buffer.len + 32]u8 = undefined;
            const test_text = std.fmt.bufPrintSentinel(&test_buffer, "{s}: {s}", .{ id_string, text }, 0) catch "error";
            imgui.teItemAdd(imgui.igGetCurrentContext(), imgui.igGetID_Str(test_text), &rect, null);
        }

        const radius = 0.5 * size.y;
        const start_x = rect.Min.x + radius;
        const center_y = rect.Min.y + radius;
        const rounds_needed_to_win_float: f32 = @floatFromInt(rounds_needed_to_win);
        const spacing = (size.x - (2 * radius)) / (rounds_needed_to_win_float - 1.0);
        const rounds_won_min = @min(rounds_won.starting_value, rounds_won.current_value);
        const rounds_won_max = @max(rounds_won.starting_value, rounds_won.current_value);

        const empty_color = imgui.igGetColorU32_Vec4(settings.empty_circle_color.toImVec());
        const filled_color = imgui.igGetColorU32_Vec4(settings.filled_circle_color.toImVec());
        const transition_color = block: {
            const completion = switch (settings.animation_duration > 0) {
                true => 1.0 - (rounds_won.remaining_time / settings.animation_duration),
                false => 1.0,
            };
            const t = completion * completion * completion * completion;
            const color = switch (rounds_won.current_value > rounds_won.starting_value) {
                true => sdk.math.Vec4.lerpElements(settings.empty_circle_color, settings.filled_circle_color, t),
                false => sdk.math.Vec4.lerpElements(settings.filled_circle_color, settings.empty_circle_color, t),
            };
            break :block imgui.igGetColorU32_Vec4(color.toImVec());
        };

        const draw_list = imgui.igGetWindowDrawList();
        for (0..rounds_needed_to_win) |index| {
            const round_index = switch (side) {
                .left => rounds_needed_to_win - index - 1,
                .right => index,
            };
            const color = if (round_index < rounds_won_min) block: {
                break :block filled_color;
            } else if (round_index < rounds_won_max) block: {
                break :block transition_color;
            } else block: {
                break :block empty_color;
            };
            const float_index: f32 = @floatFromInt(index);
            const center = imgui.ImVec2{ .x = start_x + (float_index * spacing), .y = center_y };
            imgui.ImDrawList_AddCircleFilled(draw_list, center, radius, color, 16);
        }
    }

    fn drawHeatBar(
        id_string: [:0]const u8,
        settings: *const model.MatchBarSettings.HeatBar,
        heat: model.Heat,
        width: f32,
        side: Side,
    ) void {
        const style = imgui.igGetStyle();
        const size = imgui.ImVec2{ .x = width, .y = imgui.igGetFrameHeight() };
        var rect: imgui.ImRect = undefined;
        imgui.igGetCursorScreenPos(&rect.Min);
        rect.Max = .{ .x = rect.Min.x + size.x, .y = rect.Min.y + size.y };

        const id = imgui.igGetID_Str(id_string);
        imgui.igItemSize_Vec2(size, -1.0);
        if (!imgui.igItemAdd(rect, id, null, 0)) {
            return;
        }
        if (builtin.is_test) {
            imgui.teItemAdd(imgui.igGetCurrentContext(), id, &rect, null);
        }

        const heat_value: f32 = switch (heat) {
            .available => 1.0,
            .activated => |activated| activated.gauge,
            .used_up => 0.0,
        };
        var buffer: [8]u8 = undefined;
        const text = std.fmt.bufPrintSentinel(&buffer, "{d:.1}%", .{heat_value * 100}, 0) catch "error";
        if (imgui.igButtonBehavior(rect, id, null, null, 0)) {
            imgui.igSetClipboardText(text);
            sdk.ui.toasts.send(.info, null, "Copied to clipboard: {s}", .{text});
        }
        if (builtin.is_test) {
            var test_buffer: [buffer.len + 32]u8 = undefined;
            const test_text = std.fmt.bufPrintSentinel(&test_buffer, "{s}: {s}", .{ id_string, text }, 0) catch "error";
            imgui.teItemAdd(imgui.igGetCurrentContext(), imgui.igGetID_Str(test_text), &rect, null);
        }

        var text_size: imgui.ImVec2 = undefined;
        imgui.igCalcTextSize(&text_size, text, null, false, -1);
        const text_pos = imgui.ImVec2{
            .x = switch (side) {
                .left => rect.Max.x - text_size.x - style.*.FramePadding.x,
                .right => rect.Min.x + style.*.FramePadding.x,
            },
            .y = rect.Min.y + style.*.FramePadding.y,
        };

        const heat_width = size.x * heat_value;

        const background_color = imgui.igGetColorU32_Vec4(settings.background_color.toImVec());
        const fill_color = imgui.igGetColorU32_Vec4(settings.fill_color.toImVec());
        const activated_color = imgui.igGetColorU32_Vec4(settings.activated_color.toImVec());
        const text_color = imgui.igGetColorU32_Vec4(settings.text_color.toImVec());

        const draw_list = imgui.igGetWindowDrawList();
        imgui.ImDrawList_AddRectFilled(draw_list, rect.Min, rect.Max, background_color, style.*.FrameRounding, 0);
        switch (side) {
            .left => imgui.ImDrawList_AddRectFilled(
                draw_list,
                .{ .x = rect.Max.x - heat_width, .y = rect.Min.y },
                rect.Max,
                fill_color,
                style.*.FrameRounding,
                0,
            ),
            .right => imgui.ImDrawList_AddRectFilled(
                draw_list,
                rect.Min,
                .{ .x = rect.Min.x + heat_width, .y = rect.Max.y },
                fill_color,
                style.*.FrameRounding,
                0,
            ),
        }
        if (heat == .activated) {
            imgui.ImDrawList_AddRect(
                draw_list,
                rect.Min,
                rect.Max,
                activated_color,
                style.*.FrameRounding,
                0,
                settings.activated_thickness,
            );
        }
        if (text_size.x + (2 * style.*.FramePadding.x) <= size.x) {
            imgui.ImDrawList_AddText_Vec2(draw_list, text_pos, text_color, text, null);
        }
    }

    fn drawHealthBar(
        id_string: [:0]const u8,
        settings: *const model.MatchBarSettings.HealthBar,
        state: *const HealthBarState,
        width: f32,
        side: Side,
    ) void {
        const style = imgui.igGetStyle();
        const size = imgui.ImVec2{ .x = width, .y = imgui.igGetFrameHeight() };
        var rect: imgui.ImRect = undefined;
        imgui.igGetCursorScreenPos(&rect.Min);
        rect.Max = .{ .x = rect.Min.x + size.x, .y = rect.Min.y + size.y };

        const id = imgui.igGetID_Str(id_string);
        imgui.igItemSize_Vec2(size, -1.0);
        if (!imgui.igItemAdd(rect, id, null, 0)) {
            return;
        }
        if (builtin.is_test) {
            imgui.teItemAdd(imgui.igGetCurrentContext(), id, &rect, null);
        }

        var buffer: [16]u8 = undefined;
        const text = switch (side) {
            .left => std.fmt.bufPrintSentinel(&buffer, "({}) {}", .{ state.recoverable_health, state.health }, 0),
            .right => std.fmt.bufPrintSentinel(&buffer, "{} ({})", .{ state.health, state.recoverable_health }, 0),
        } catch "error";
        if (imgui.igButtonBehavior(rect, id, null, null, 0)) {
            imgui.igSetClipboardText(text);
            sdk.ui.toasts.send(.info, null, "Copied to clipboard: {s}", .{text});
        }
        if (builtin.is_test) {
            var test_buffer: [buffer.len + 32]u8 = undefined;
            const test_text = std.fmt.bufPrintSentinel(&test_buffer, "{s}: {s}", .{ id_string, text }, 0) catch "error";
            imgui.teItemAdd(imgui.igGetCurrentContext(), imgui.igGetID_Str(test_text), &rect, null);
        }

        var text_size: imgui.ImVec2 = undefined;
        imgui.igCalcTextSize(&text_size, text, null, false, -1);
        const text_pos = imgui.ImVec2{
            .x = switch (side) {
                .left => rect.Max.x - text_size.x - style.*.FramePadding.x,
                .right => rect.Min.x + style.*.FramePadding.x,
            },
            .y = rect.Min.y + style.*.FramePadding.y,
        };

        const max_health: f32 = @floatFromInt(state.max_health);
        const health: f32 = @floatFromInt(state.health);
        const recoverable_health: f32 = @floatFromInt(state.recoverable_health);
        const damage: f32 = if (settings.damage_animation_duration > 0) block: {
            const start: f32 = @floatFromInt(state.damage.starting_value);
            const current: f32 = @floatFromInt(state.damage.current_value);
            const t = 1.0 - (state.damage.remaining_time / settings.damage_animation_duration);
            break :block std.math.lerp(start, current, t);
        } else @floatFromInt(state.damage.current_value);

        const health_width = size.x * health / max_health;
        const recoverable_health_width = size.x * recoverable_health / max_health;
        const damage_width = size.x * damage / max_health;

        const background_color = imgui.igGetColorU32_Vec4(settings.background_color.toImVec());
        const health_color = imgui.igGetColorU32_Vec4(settings.health_color.toImVec());
        const recoverable_health_color = imgui.igGetColorU32_Vec4(settings.recoverable_health_color.toImVec());
        const damage_color = imgui.igGetColorU32_Vec4(settings.damage_color.toImVec());
        const rage_color = imgui.igGetColorU32_Vec4(settings.rage_color.toImVec());
        const text_color = imgui.igGetColorU32_Vec4(settings.text_color.toImVec());

        const draw_list = imgui.igGetWindowDrawList();
        imgui.ImDrawList_AddRectFilled(draw_list, rect.Min, rect.Max, background_color, style.*.FrameRounding, 0);
        switch (side) {
            .left => {
                imgui.ImDrawList_AddRectFilled(
                    draw_list,
                    .{ .x = rect.Max.x - health_width, .y = rect.Min.y },
                    rect.Max,
                    health_color,
                    style.*.FrameRounding,
                    0,
                );
                imgui.ImDrawList_AddRectFilled(
                    draw_list,
                    .{ .x = rect.Max.x - health_width - damage_width, .y = rect.Min.y },
                    .{ .x = rect.Max.x - health_width, .y = rect.Max.y },
                    damage_color,
                    style.*.FrameRounding,
                    0,
                );
                imgui.ImDrawList_AddRectFilled(
                    draw_list,
                    .{ .x = rect.Max.x - health_width - recoverable_health_width, .y = rect.Min.y },
                    .{ .x = rect.Max.x - health_width, .y = rect.Max.y },
                    recoverable_health_color,
                    style.*.FrameRounding,
                    0,
                );
            },
            .right => {
                imgui.ImDrawList_AddRectFilled(
                    draw_list,
                    rect.Min,
                    .{ .x = rect.Min.x + health_width, .y = rect.Max.y },
                    health_color,
                    style.*.FrameRounding,
                    0,
                );
                imgui.ImDrawList_AddRectFilled(
                    draw_list,
                    .{ .x = rect.Min.x + health_width, .y = rect.Min.y },
                    .{ .x = rect.Min.x + health_width + damage_width, .y = rect.Max.y },
                    damage_color,
                    style.*.FrameRounding,
                    0,
                );
                imgui.ImDrawList_AddRectFilled(
                    draw_list,
                    .{ .x = rect.Min.x + health_width, .y = rect.Min.y },
                    .{ .x = rect.Min.x + health_width + recoverable_health_width, .y = rect.Max.y },
                    recoverable_health_color,
                    style.*.FrameRounding,
                    0,
                );
            },
        }
        if (state.rage == .activated) {
            imgui.ImDrawList_AddRect(
                draw_list,
                rect.Min,
                rect.Max,
                rage_color,
                style.*.FrameRounding,
                0,
                settings.rage_thickness,
            );
        }
        if (text_size.x + (2 * style.*.FramePadding.x) <= size.x) {
            imgui.ImDrawList_AddText_Vec2(draw_list, text_pos, text_color, text, null);
        }
    }
};

const testing = std.testing;

test "should draw all items when enabled in settings" {
    const Test = struct {
        const settings = model.MatchBarSettings{ .enabled = true };
        var bar = MatchBar{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            imgui.igSetNextWindowSize(.{ .x = 720, .y = 720 }, imgui.ImGuiCond_Always);
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            bar.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try ctx.expectItemExists("round_timer");
            try ctx.expectItemExists("left/player_name");
            try ctx.expectItemExists("left/round_count");
            try ctx.expectItemExists("left/health_bar");
            try ctx.expectItemExists("left/heat_bar");
            try ctx.expectItemExists("right/player_name");
            try ctx.expectItemExists("right/round_count");
            try ctx.expectItemExists("right/health_bar");
            try ctx.expectItemExists("right/heat_bar");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw nothing when disabled in settings" {
    const Test = struct {
        const settings = model.MatchBarSettings{ .enabled = false };
        var bar = MatchBar{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            imgui.igSetNextWindowSize(.{ .x = 720, .y = 720 }, imgui.ImGuiCond_Always);
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            bar.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try ctx.expectItemNotExists("round_timer");
            try ctx.expectItemNotExists("left/player_name");
            try ctx.expectItemNotExists("left/round_count");
            try ctx.expectItemNotExists("left/health_bar");
            try ctx.expectItemNotExists("left/heat_bar");
            try ctx.expectItemNotExists("right/player_name");
            try ctx.expectItemNotExists("right/round_count");
            try ctx.expectItemNotExists("right/health_bar");
            try ctx.expectItemNotExists("right/heat_bar");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw correct value inside round timer" {
    const Test = struct {
        const settings = model.MatchBarSettings{ .enabled = true };
        var bar = MatchBar{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            imgui.igSetNextWindowSize(.{ .x = 720, .y = 720 }, imgui.ImGuiCond_Always);
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            bar.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");

            bar.processFrame(&settings, &.{ .frames_left_in_round = 121 });
            ctx.yield(1);
            try ctx.expectItemExists("round_timer: 3");

            bar.processFrame(&settings, &.{ .frames_left_in_round = 120 });
            ctx.yield(1);
            try ctx.expectItemExists("round_timer: 2");

            bar.processFrame(&settings, &.{ .frames_left_in_round = 1 });
            ctx.yield(1);
            try ctx.expectItemExists("round_timer: 1");

            bar.processFrame(&settings, &.{ .frames_left_in_round = 0 });
            ctx.yield(1);
            try ctx.expectItemExists("round_timer: 0");

            bar.processFrame(&settings, &.{ .frames_left_in_round = null });
            ctx.yield(1);
            try ctx.expectItemExists("round_timer: ∞");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw correct value inside correct player name" {
    const Test = struct {
        const settings = model.MatchBarSettings{ .enabled = true };
        var bar = MatchBar{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            imgui.igSetNextWindowSize(.{ .x = 720, .y = 720 }, imgui.ImGuiCond_Always);
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            bar.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");

            bar.processFrame(&settings, &.{ .players = .{
                .{ .name = .fromArray("Test".*) },
                .{ .name = .empty },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("left/player_name: Test");
            try ctx.expectItemExists("right/player_name: ");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw correct value inside correct round count" {
    const Test = struct {
        const settings = model.MatchBarSettings{ .enabled = true };
        var bar = MatchBar{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            imgui.igSetNextWindowSize(.{ .x = 720, .y = 720 }, imgui.ImGuiCond_Always);
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            bar.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");

            bar.processFrame(&settings, &.{
                .rounds_needed_to_win = 4,
                .players = .{
                    .{ .rounds_won = 1 },
                    .{ .rounds_won = null },
                },
            });
            ctx.yield(1);
            try ctx.expectItemExists("left/round_count: 1\\/4");
            try ctx.expectItemExists("right/round_count: 0\\/4");

            bar.processFrame(&settings, &.{
                .rounds_needed_to_win = null,
                .players = .{
                    .{ .rounds_won = 2 },
                    .{ .rounds_won = null },
                },
            });
            ctx.yield(1);
            try ctx.expectItemExists("left/round_count: 2\\/3");
            try ctx.expectItemExists("right/round_count: 0\\/3");

            bar.processFrame(&settings, &.{
                .rounds_needed_to_win = 0,
                .players = .{
                    .{ .rounds_won = 3 },
                    .{ .rounds_won = null },
                },
            });
            ctx.yield(1);
            try ctx.expectItemNotExists("left/round_count");
            try ctx.expectItemNotExists("right/round_count");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw correct value inside correct health bar" {
    const Test = struct {
        const settings = model.MatchBarSettings{ .enabled = true };
        var bar = MatchBar{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            imgui.igSetNextWindowSize(.{ .x = 720, .y = 720 }, imgui.ImGuiCond_Always);
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            bar.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");

            bar.processFrame(&settings, &.{ .players = .{
                .{ .max_health = 200, .health_recover_limit = 123, .health = 100 },
                .{ .max_health = 200, .health_recover_limit = 123, .health = 23 },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("left/health_bar: (23) 100");
            try ctx.expectItemExists("right/health_bar: 23 (100)");

            bar.processFrame(&settings, &.{ .players = .{
                .{ .max_health = 200, .health_recover_limit = 0, .health = 0 },
                .{ .max_health = 200, .health_recover_limit = null, .health = null },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("left/health_bar: (0) 0");
            try ctx.expectItemExists("right/health_bar: 0 (0)");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw correct value inside correct heat bar" {
    const Test = struct {
        const settings = model.MatchBarSettings{ .enabled = true };
        var bar = MatchBar{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            imgui.igSetNextWindowSize(.{ .x = 720, .y = 720 }, imgui.ImGuiCond_Always);
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            bar.draw(&settings);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");

            bar.processFrame(&settings, &.{ .players = .{
                .{ .heat = .available },
                .{ .heat = .{ .activated = .{ .gauge = 0.1234 } } },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("left/heat_bar: 100.0%");
            try ctx.expectItemExists("right/heat_bar: 12.3%");

            bar.processFrame(&settings, &.{ .players = .{
                .{ .heat = .used_up },
                .{ .heat = null },
            } });
            ctx.yield(1);
            try ctx.expectItemExists("left/heat_bar: 0.0%");
            try ctx.expectItemExists("right/heat_bar: 0.0%");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should copy correct text to clipboard when clicking on items" {
    const Test = struct {
        const settings = model.MatchBarSettings{ .enabled = true };
        var bar = MatchBar{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            imgui.igSetNextWindowSize(.{ .x = 720, .y = 720 }, imgui.ImGuiCond_Always);
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            bar.draw(&settings);
            sdk.ui.toasts.draw();
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            bar.processFrame(&settings, &.{
                .frames_left_in_round = 3600,
                .rounds_needed_to_win = 4,
                .players = .{
                    .{
                        .name = .fromArray("Player 1".*),
                        .rounds_won = 1,
                        .max_health = 200,
                        .health_recover_limit = 21,
                        .health = 10,
                        .heat = .{ .activated = .{ .gauge = 0.1 } },
                    },
                    .{
                        .name = .fromArray("Player 2".*),
                        .rounds_won = 2,
                        .max_health = 200,
                        .health_recover_limit = 42,
                        .health = 20,
                        .heat = .{ .activated = .{ .gauge = 0.2 } },
                    },
                },
            });
            sdk.ui.toasts.update(100);
            ctx.yield(1);
            ctx.setRef("Window");

            ctx.itemClick("round_timer", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("60");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 60");
            sdk.ui.toasts.update(100);

            ctx.itemClick("left/player_name", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("Player 1");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: Player 1");
            sdk.ui.toasts.update(100);

            ctx.itemClick("right/player_name", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("Player 2");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: Player 2");
            sdk.ui.toasts.update(100);

            ctx.itemClick("left/round_count", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("1/4");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 1\\/4");
            sdk.ui.toasts.update(100);

            ctx.itemClick("right/round_count", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("2/4");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 2\\/4");
            sdk.ui.toasts.update(100);

            ctx.itemClick("left/health_bar", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("(11) 10");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: (11) 10");
            sdk.ui.toasts.update(100);

            ctx.itemClick("right/health_bar", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("20 (22)");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 20 (22)");
            sdk.ui.toasts.update(100);

            ctx.itemClick("left/heat_bar", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("10.0%");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 10.0%");
            sdk.ui.toasts.update(100);

            ctx.itemClick("right/heat_bar", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("20.0%");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 20.0%");
            sdk.ui.toasts.update(100);
        }
    };
    sdk.ui.toasts.setIo(testing.io);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
