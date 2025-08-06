const std = @import("std");
const imgui = @import("imgui");
const core = @import("../core/root.zig");
const ui = @import("root.zig");
const sdk = @import("../../sdk/root.zig");

pub const Controls = struct {
    total_frames_width: f32 = 0.0,
    speed_button_width: f32 = 0.0,

    const Self = @This();

    pub fn draw(self: *Self, controller: *core.Controller) void {
        imgui.igAlignTextToFramePadding();
        const spacing = imgui.igGetStyle().*.ItemSpacing.x;

        drawCurrentFrame(controller);

        imgui.igSameLine(0, spacing);

        const seekbar_x = imgui.igGetCursorPosX();
        var available_size: imgui.ImVec2 = undefined;
        imgui.igGetContentRegionAvail(&available_size);
        imgui.igPushItemWidth(available_size.x - self.total_frames_width - spacing);
        drawSeekbar(controller);
        imgui.igPopItemWidth();

        imgui.igSameLine(0, -1);

        drawTotalFrames(controller);
        var total_frames_size: imgui.ImVec2 = undefined;
        imgui.igGetItemRectSize(&total_frames_size);
        self.total_frames_width = total_frames_size.x;

        imgui.igGetContentRegionAvail(&available_size);
        const window_width = available_size.x;
        imgui.igSetCursorPosX(seekbar_x);

        drawPlayButton(controller);
        imgui.igSameLine(0, spacing);
        drawPauseButton(controller);
        imgui.igSameLine(0, spacing);
        drawStopButton(controller);
        imgui.igSameLine(0, spacing);
        drawRecordButton(controller);
        imgui.igSameLine(0, 2 * spacing);
        drawFirstFrameButton(controller);
        imgui.igSameLine(0, spacing);
        drawPreviousFrameButton(controller);
        imgui.igSameLine(0, spacing);
        drawNextFrameButton(controller);
        imgui.igSameLine(0, spacing);
        drawLastFrameButton(controller);
        imgui.igSameLine(0, 2 * spacing);
        drawClearButton(controller);

        imgui.igSameLine(0, 2 * spacing);
        const speed_button_x = @max(
            imgui.igGetCursorPosX(),
            window_width - self.total_frames_width - spacing - self.speed_button_width,
        );
        imgui.igSetCursorPosX(speed_button_x);

        drawSpeedButton(controller);

        var speed_button_size: imgui.ImVec2 = undefined;
        imgui.igGetItemRectSize(&speed_button_size);
        self.speed_button_width = speed_button_size.x;
    }

    fn drawCurrentFrame(controller: *core.Controller) void {
        if (controller.getCurrentFrameIndex()) |current| {
            imgui.igText("%05zu", current);
        } else {
            imgui.igText("-----");
        }
    }

    fn drawTotalFrames(controller: *core.Controller) void {
        const total = controller.getTotalFrames();
        if (total != 0) {
            imgui.igText("%05zu", total);
        } else {
            imgui.igText("-----");
        }
    }

    fn drawSeekbar(controller: *core.Controller) void {
        const current = controller.getCurrentFrameIndex() orelse 0;
        var value: i32 = @intCast(current);
        const max: i32 = @intCast(controller.getTotalFrames());
        const changed = imgui.igSliderInt(
            "##seekbar",
            &value,
            0,
            max,
            "",
            imgui.ImGuiSliderFlags_AlwaysClamp,
        );
        if (changed) {
            const new_value: usize = @intCast(value);
            controller.setCurrentFrameIndex(new_value);
        }
    }

    fn drawPlayButton(controller: *core.Controller) void {
        const disabled = controller.mode == .playback or controller.getTotalFrames() == 0;
        if (disabled) imgui.igBeginDisabled(true);
        defer if (disabled) imgui.igEndDisabled();
        if (imgui.igButton(" ▶ ##play", .{})) {
            controller.play();
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Play");
        }
    }

    fn drawPauseButton(controller: *core.Controller) void {
        const disabled = controller.mode == .pause or controller.getTotalFrames() == 0;
        if (disabled) imgui.igBeginDisabled(true);
        defer if (disabled) imgui.igEndDisabled();
        if (imgui.igButton(" ⏸ ##pause", .{})) {
            controller.pause();
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Pause");
        }
    }

    fn drawStopButton(controller: *core.Controller) void {
        const disabled = controller.mode == .live;
        if (disabled) imgui.igBeginDisabled(true);
        defer if (disabled) imgui.igEndDisabled();
        if (imgui.igButton(" ⏹ ##stop", .{})) {
            controller.stop();
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Stop");
        }
    }

    fn drawRecordButton(controller: *core.Controller) void {
        const disabled = controller.mode == .record;
        if (disabled) imgui.igBeginDisabled(true);
        defer if (disabled) imgui.igEndDisabled();
        if (imgui.igButton(" ⏺ ##record", .{})) {
            controller.record();
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Start Recording");
        }
    }

    fn drawFirstFrameButton(controller: *core.Controller) void {
        const total = controller.getTotalFrames();
        const disabled = total == 0;
        if (disabled) imgui.igBeginDisabled(true);
        defer if (disabled) imgui.igEndDisabled();
        if (imgui.igButton(" ⏮ ##first_frame", .{})) {
            controller.setCurrentFrameIndex(0);
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Go To First Frame");
        }
    }

    fn drawLastFrameButton(controller: *core.Controller) void {
        const total = controller.getTotalFrames();
        const disabled = total == 0;
        if (disabled) imgui.igBeginDisabled(true);
        defer if (disabled) imgui.igEndDisabled();
        if (imgui.igButton(" ⏭ ##last_frame", .{})) {
            controller.setCurrentFrameIndex(total - 1);
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Go To Last Frame");
        }
    }

    fn drawPreviousFrameButton(controller: *core.Controller) void {
        const current = controller.getCurrentFrameIndex();
        const disabled = current == null or current == 0;
        if (disabled) imgui.igBeginDisabled(true);
        defer if (disabled) imgui.igEndDisabled();
        imgui.igPushItemFlag(imgui.ImGuiItemFlags_ButtonRepeat, true);
        defer imgui.igPopItemFlag();
        if (imgui.igButton(" ⏪ ##previous_frame", .{})) {
            controller.setCurrentFrameIndex(current.? - 1);
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Go To Previous Frame");
        }
    }

    fn drawNextFrameButton(controller: *core.Controller) void {
        const current = controller.getCurrentFrameIndex();
        const total = controller.getTotalFrames();
        const disabled = total == 0 or current == null or current.? >= total - 1;
        if (disabled) imgui.igBeginDisabled(true);
        defer if (disabled) imgui.igEndDisabled();
        imgui.igPushItemFlag(imgui.ImGuiItemFlags_ButtonRepeat, true);
        defer imgui.igPopItemFlag();
        if (imgui.igButton(" ⏩ ##next_frame", .{})) {
            controller.setCurrentFrameIndex(current.? + 1);
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Go To Next Frame");
        }
    }

    fn drawClearButton(controller: *core.Controller) void {
        const disabled = controller.getTotalFrames() == 0;
        if (disabled) imgui.igBeginDisabled(true);
        defer if (disabled) imgui.igEndDisabled();
        if (imgui.igButton(" 🗑 ##clear", .{})) {
            controller.clear();
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Clear Recording");
        }
    }

    fn drawSpeedButton(controller: *core.Controller) void {
        const speed = &controller.playback_speed;
        var buffer: [32]u8 = undefined;
        const button_text = std.fmt.bufPrintZ(
            &buffer,
            " ⏲ {d:.2}x ##speed",
            .{controller.playback_speed},
        ) catch " ⏲ ##speed";
        if (imgui.igButton(button_text, .{})) {
            imgui.igOpenPopup_Str("speed_popup", 0);
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Playback Speed");
        }
        if (imgui.igBeginPopup("speed_popup", 0)) {
            defer imgui.igEndPopup();
            _ = imgui.igSliderFloat("##speed_slider", speed, -4.0, 4.0, "%.2fx", 0);
            inline for ([_]f32{ 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0 }) |option| {
                const text = std.fmt.comptimePrint("{d:.2}x", .{option});
                if (imgui.igSelectable_Bool(text, speed.* == option, 0, .{})) {
                    speed.* = option;
                }
            }
        }
    }
};
