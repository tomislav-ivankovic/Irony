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

        drawPlayButton(controller);
        imgui.igSameLine(0, -1);
        drawPauseButton(controller);
        imgui.igSameLine(0, -1);
        drawStopButton(controller);
        imgui.igSameLine(0, -1);
        drawRecordButton(controller);
        imgui.igSameLine(0, -1);
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
        const total = controller.recording.items.len;
        if (total != 0) {
            imgui.igText("%05zu", total);
        } else {
            imgui.igText("-----");
        }
    }

    fn drawSeekbar(controller: *core.Controller) void {
        const current = controller.getCurrentFrameIndex() orelse 0;
        var value: i32 = @intCast(current);
        const max: i32 = @intCast(controller.recording.items.len);
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
        const disabled = controller.mode == .playback or controller.recording.items.len == 0;
        if (disabled) imgui.igBeginDisabled(true);
        defer if (disabled) imgui.igEndDisabled();
        if (imgui.igButton("Play", .{})) {
            controller.play();
        }
    }

    fn drawPauseButton(controller: *core.Controller) void {
        const disabled = controller.mode == .pause or controller.recording.items.len == 0;
        if (disabled) imgui.igBeginDisabled(true);
        defer if (disabled) imgui.igEndDisabled();
        if (imgui.igButton("Pause", .{})) {
            controller.pause();
        }
    }

    fn drawStopButton(controller: *core.Controller) void {
        const disabled = controller.mode == .live;
        if (disabled) imgui.igBeginDisabled(true);
        defer if (disabled) imgui.igEndDisabled();
        if (imgui.igButton("Stop", .{})) {
            controller.stop();
        }
    }

    fn drawRecordButton(controller: *core.Controller) void {
        const disabled = controller.mode == .record;
        if (disabled) imgui.igBeginDisabled(true);
        defer if (disabled) imgui.igEndDisabled();
        if (imgui.igButton("Record", .{})) {
            controller.record();
        }
    }

    fn drawClearButton(controller: *core.Controller) void {
        const disabled = controller.recording.items.len == 0;
        if (disabled) imgui.igBeginDisabled(true);
        defer if (disabled) imgui.igEndDisabled();
        if (imgui.igButton("Clear", .{})) {
            controller.clear();
        }
    }
};
