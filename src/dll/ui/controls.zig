const std = @import("std");
const imgui = @import("imgui");
const core = @import("../core/root.zig");
const ui = @import("root.zig");
const sdk = @import("../../sdk/root.zig");

pub const Controls = struct {
    total_frames_width: f32 = 0.0,

    const Self = @This();

    pub fn draw(self: *Self, controller: *core.Controller) void {
        imgui.igAlignTextToFramePadding();

        drawCurrentFrame(controller);

        imgui.igSameLine(0, -1);

        var content_size: imgui.ImVec2 = undefined;
        imgui.igGetContentRegionAvail(&content_size);
        const padding = imgui.igGetStyle().*.ItemSpacing.x;
        imgui.igPushItemWidth(content_size.x - self.total_frames_width - padding);
        drawSeekbar(controller);
        imgui.igPopItemWidth();

        imgui.igSameLine(0, -1);

        drawTotalFrames(controller);
        var total_frames_size: imgui.ImVec2 = undefined;
        imgui.igGetItemRectSize(&total_frames_size);
        self.total_frames_width = total_frames_size.x;

        const spacing = imgui.igGetStyle().*.ItemSpacing.x;
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
            imgui.igSetTooltip("Record");
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
            imgui.igSetTooltip("First Frame");
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
            imgui.igSetTooltip("Last Frame");
        }
    }

    fn drawPreviousFrameButton(controller: *core.Controller) void {
        const current = controller.getCurrentFrameIndex();
        const disabled = current == null or current == 0;
        if (disabled) imgui.igBeginDisabled(true);
        defer if (disabled) imgui.igEndDisabled();
        if (imgui.igButton(" ⏪ ##previous_frame", .{})) {
            controller.setCurrentFrameIndex(current.? - 1);
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Previous Frame");
        }
    }

    fn drawNextFrameButton(controller: *core.Controller) void {
        const current = controller.getCurrentFrameIndex();
        const total = controller.getTotalFrames();
        const disabled = total == 0 or current == null or current.? >= total - 1;
        if (disabled) imgui.igBeginDisabled(true);
        defer if (disabled) imgui.igEndDisabled();
        if (imgui.igButton(" ⏩ ##next_frame", .{})) {
            controller.setCurrentFrameIndex(current.? + 1);
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Next Frame");
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
};
