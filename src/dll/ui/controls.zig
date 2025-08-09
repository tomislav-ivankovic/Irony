const std = @import("std");
const builtin = @import("builtin");
const imgui = @import("imgui");
const core = @import("../core/root.zig");
const ui = @import("root.zig");
const sdk = @import("../../sdk/root.zig");

pub const ControlsConfig = struct {
    Controller: type = core.Controller,
};

pub fn Controls(comptime config: ControlsConfig) type {
    return struct {
        total_frames_width: f32 = 0.0,
        speed_button_width: f32 = 0.0,

        const Self = @This();

        pub fn draw(self: *Self, controller: *config.Controller) void {
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

        fn drawCurrentFrame(controller: *config.Controller) void {
            if (controller.getCurrentFrameIndex()) |current| {
                drawText("current_frame", "{d:0>5}", .{current});
            } else {
                drawText("current_frame", "‒‒‒‒‒", .{});
            }
        }

        fn drawTotalFrames(controller: *config.Controller) void {
            const total = controller.getTotalFrames();
            if (total != 0) {
                drawText("total_frames", "{d:0>5}", .{total});
            } else {
                drawText("total_frames", "‒‒‒‒‒", .{});
            }
        }

        fn drawText(test_id: [:0]const u8, comptime fmt: []const u8, args: anytype) void {
            var buffer: [32]u8 = undefined;
            const text = std.fmt.bufPrintZ(&buffer, fmt, args) catch "error";
            imgui.igText("%s", text.ptr);

            if (builtin.is_test) {
                var rect: imgui.ImRect = undefined;
                imgui.igGetItemRectMin(&rect.Min);
                imgui.igGetItemRectMax(&rect.Max);
                const full_test_id = std.fmt.bufPrintZ(&buffer, "{s}: " ++ fmt, .{test_id} ++ args) catch "error";
                imgui.teItemAdd(imgui.igGetCurrentContext(), imgui.igGetID_Str(test_id), &rect, null);
                imgui.teItemAdd(imgui.igGetCurrentContext(), imgui.igGetID_Str(full_test_id), &rect, null);
            }
        }

        fn drawSeekbar(controller: *config.Controller) void {
            const current = controller.getCurrentFrameIndex() orelse 0;
            var value: i32 = @intCast(current);
            const total: i32 = @intCast(controller.getTotalFrames());
            const changed = imgui.igSliderInt(
                "###seekbar",
                &value,
                0,
                if (total > 0) total - 1 else 0,
                "",
                imgui.ImGuiSliderFlags_AlwaysClamp,
            );
            if (changed) {
                const new_value: usize = @intCast(value);
                controller.setCurrentFrameIndex(new_value);
            }
        }

        fn drawPlayButton(controller: *config.Controller) void {
            const disabled = controller.mode == .playback or controller.getTotalFrames() == 0;
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();
            if (imgui.igButton(" ▶ ###play", .{})) {
                controller.play();
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Play [F1]");
            }
        }

        fn drawPauseButton(controller: *config.Controller) void {
            const disabled = controller.mode == .pause or controller.getTotalFrames() == 0;
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();
            if (imgui.igButton(" ⏸ ###pause", .{})) {
                controller.pause();
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Pause [F2]");
            }
        }

        fn drawStopButton(controller: *config.Controller) void {
            const disabled = controller.mode == .live;
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();
            if (imgui.igButton(" ⏹ ###stop", .{})) {
                controller.stop();
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Stop [F3]");
            }
        }

        fn drawRecordButton(controller: *config.Controller) void {
            const disabled = controller.mode == .record;
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();
            if (imgui.igButton(" ⏺ ###record", .{})) {
                controller.record();
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Start Recording [F4]");
            }
        }

        fn drawFirstFrameButton(controller: *config.Controller) void {
            const current = controller.getCurrentFrameIndex();
            const total = controller.getTotalFrames();
            const disabled = total == 0 or current == 0;
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();
            if (imgui.igButton(" ⏮ ###first_frame", .{})) {
                controller.setCurrentFrameIndex(0);
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Go To First Frame [F5]");
            }
        }

        fn drawLastFrameButton(controller: *config.Controller) void {
            const current = controller.getCurrentFrameIndex();
            const total = controller.getTotalFrames();
            const disabled = total == 0 or (current != null and current.? >= total - 1);
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();
            if (imgui.igButton(" ⏭ ###last_frame", .{})) {
                controller.setCurrentFrameIndex(total - 1);
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Go To Last Frame [F7]");
            }
        }

        fn drawPreviousFrameButton(controller: *config.Controller) void {
            const current = controller.getCurrentFrameIndex();
            const total = controller.getTotalFrames();
            const disabled = total == 0 or current == 0;
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();
            imgui.igPushItemFlag(imgui.ImGuiItemFlags_ButtonRepeat, true);
            defer imgui.igPopItemFlag();
            if (imgui.igButton(" ⏪ ###previous_frame", .{})) {
                const next = if (current != null and current != 0) current.? - 1 else 0;
                controller.setCurrentFrameIndex(next);
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Go To Previous Frame [F6]");
            }
        }

        fn drawNextFrameButton(controller: *config.Controller) void {
            const current = controller.getCurrentFrameIndex();
            const total = controller.getTotalFrames();
            const disabled = total == 0 or (current != null and current.? >= total - 1);
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();
            imgui.igPushItemFlag(imgui.ImGuiItemFlags_ButtonRepeat, true);
            defer imgui.igPopItemFlag();
            if (imgui.igButton(" ⏩ ###next_frame", .{})) {
                const next = if (current != null) current.? + 1 else 0;
                controller.setCurrentFrameIndex(next);
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Go To Next Frame [F7]");
            }
        }

        fn drawClearButton(controller: *config.Controller) void {
            const disabled = controller.getTotalFrames() == 0;
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();
            if (imgui.igButton(" 🗑 ###clear", .{})) {
                controller.clear();
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Clear Recording [F9]");
            }
        }

        fn drawSpeedButton(controller: *config.Controller) void {
            const speed = &controller.playback_speed;
            var buffer: [32]u8 = undefined;
            const button_text = std.fmt.bufPrintZ(
                &buffer,
                " ⏲ {d:.2}x ###speed",
                .{controller.playback_speed},
            ) catch " ⏲ ###speed";
            if (imgui.igButton(button_text, .{})) {
                imgui.igOpenPopup_Str("speed_popup", 0);
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Playback Speed [F10 and F11]");
            }
            if (imgui.igBeginPopup("speed_popup", 0)) {
                defer imgui.igEndPopup();
                _ = imgui.igSliderFloat("###speed_slider", speed, 0.1, 4.0, "%.2fx", 0);
                inline for ([_]f32{ 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0 }) |option| {
                    const text = std.fmt.comptimePrint("{d:.2}x", .{option});
                    if (imgui.igSelectable_Bool(text, speed.* == option, 0, .{})) {
                        speed.* = option;
                    }
                }
            }
        }
    };
}

const testing = std.testing;

const MockController = struct {
    mode: Mode,
    playback_speed: f32 = 1.0,
    total_frames: usize = 100,
    current_frame_index: ?usize = null,
    play_call_count: usize = 0,
    pause_call_count: usize = 0,
    stop_call_count: usize = 0,
    record_call_count: usize = 0,
    clear_call_count: usize = 0,
    set_current_index_call_count: usize = 0,
    set_current_index_argument: ?usize = null,

    const Self = @This();
    pub const Mode = enum {
        live,
        record,
        pause,
        playback,
    };

    pub fn play(self: *Self) void {
        self.play_call_count += 1;
    }

    pub fn pause(self: *Self) void {
        self.pause_call_count += 1;
    }

    pub fn stop(self: *Self) void {
        self.stop_call_count += 1;
    }

    pub fn record(self: *Self) void {
        self.record_call_count += 1;
    }

    pub fn clear(self: *Self) void {
        self.clear_call_count += 1;
    }

    pub fn getTotalFrames(self: *const Self) usize {
        return self.total_frames;
    }

    pub fn setCurrentFrameIndex(self: *Self, index: usize) void {
        self.set_current_index_call_count += 1;
        self.set_current_index_argument = index;
    }

    pub fn getCurrentFrameIndex(self: *const Self) ?usize {
        return self.current_frame_index;
    }
};

test "should display current frame index correctly when not null" {
    const Test = struct {
        var controller = MockController{ .mode = .playback, .current_frame_index = 123 };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try ctx.expectItemExists("current_frame: 00123");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should display current frame index correctly when null" {
    const Test = struct {
        var controller = MockController{ .mode = .live, .current_frame_index = null };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try ctx.expectItemExists("current_frame: ‒‒‒‒‒");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should display total frames correctly when not zero" {
    const Test = struct {
        var controller = MockController{ .mode = .playback, .total_frames = 123 };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try ctx.expectItemExists("total_frames: 00123");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should display total frames correctly when zero" {
    const Test = struct {
        var controller = MockController{ .mode = .live, .total_frames = 0 };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try ctx.expectItemExists("total_frames: ‒‒‒‒‒");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call setCurrentFrameIndex with correct value when seekbar is used" {
    const Test = struct {
        var controller = MockController{
            .mode = .record,
            .current_frame_index = 50,
            .total_frames = 100,
        };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");

            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemInputValueInt("###seekbar", 55);
            try testing.expect(controller.set_current_index_call_count > 0);
            try testing.expectEqual(55, controller.set_current_index_argument);

            ctx.itemInputValueInt("###seekbar", -10);
            try testing.expectEqual(0, controller.set_current_index_argument);

            ctx.itemInputValueInt("###seekbar", 123);
            try testing.expectEqual(99, controller.set_current_index_argument);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call play when play button is clicked" {
    const Test = struct {
        var controller = MockController{ .mode = .live };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.play_call_count);
            ctx.itemClick("###play", 0, 0);
            try testing.expectEqual(1, controller.play_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should disable play button when already in playback mode" {
    const Test = struct {
        var controller = MockController{ .mode = .playback };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.play_call_count);
            ctx.itemClick("###play", 0, 0);
            try testing.expectEqual(0, controller.play_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call pause when already playing" {
    const Test = struct {
        var controller = MockController{ .mode = .live };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.pause_call_count);
            ctx.itemClick("###pause", 0, 0);
            try testing.expectEqual(1, controller.pause_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should disable pause button when already paused" {
    const Test = struct {
        var controller = MockController{ .mode = .pause };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.pause_call_count);
            ctx.itemClick("###pause", 0, 0);
            try testing.expectEqual(0, controller.pause_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call stop when stop button is clicked" {
    const Test = struct {
        var controller = MockController{ .mode = .playback };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.stop_call_count);
            ctx.itemClick("###stop", 0, 0);
            try testing.expectEqual(1, controller.stop_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should disable stop button when already stopped" {
    const Test = struct {
        var controller = MockController{ .mode = .live };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.stop_call_count);
            ctx.itemClick("###stop", 0, 0);
            try testing.expectEqual(0, controller.stop_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call record when record button is clicked" {
    const Test = struct {
        var controller = MockController{ .mode = .live };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.record_call_count);
            ctx.itemClick("###record", 0, 0);
            try testing.expectEqual(1, controller.record_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should disable record button when already recording" {
    const Test = struct {
        var controller = MockController{ .mode = .record };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.record_call_count);
            ctx.itemClick("###record", 0, 0);
            try testing.expectEqual(0, controller.record_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call setCurrentFrameIndex(0) when first frame button is clicked" {
    const Test = struct {
        var controller = MockController{
            .mode = .record,
            .current_frame_index = 50,
            .total_frames = 100,
        };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemClick("###first_frame", 0, 0);
            try testing.expectEqual(1, controller.set_current_index_call_count);
            try testing.expectEqual(0, controller.set_current_index_argument);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should disable first frame button when already on first frame" {
    const Test = struct {
        var controller = MockController{
            .mode = .record,
            .current_frame_index = 0,
            .total_frames = 100,
        };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemClick("###first_frame", 0, 0);
            try testing.expectEqual(0, controller.set_current_index_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call setCurrentFrameIndex(total - 1) when last frame button is clicked" {
    const Test = struct {
        var controller = MockController{
            .mode = .record,
            .current_frame_index = 50,
            .total_frames = 100,
        };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemClick("###last_frame", 0, 0);
            try testing.expectEqual(1, controller.set_current_index_call_count);
            try testing.expectEqual(99, controller.set_current_index_argument);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should disable last frame button when already on last frame" {
    const Test = struct {
        var controller = MockController{
            .mode = .record,
            .current_frame_index = 99,
            .total_frames = 100,
        };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemClick("###last_frame", 0, 0);
            try testing.expectEqual(0, controller.set_current_index_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call setCurrentFrameIndex(current - 1) when previous frame button is clicked" {
    const Test = struct {
        var controller = MockController{
            .mode = .record,
            .current_frame_index = 50,
            .total_frames = 100,
        };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemClick("###previous_frame", 0, 0);
            try testing.expectEqual(1, controller.set_current_index_call_count);
            try testing.expectEqual(49, controller.set_current_index_argument);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should disable previous frame button when currently on first frame" {
    const Test = struct {
        var controller = MockController{
            .mode = .record,
            .current_frame_index = 0,
            .total_frames = 100,
        };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemClick("###previous_frame", 0, 0);
            try testing.expectEqual(0, controller.set_current_index_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call setCurrentFrameIndex(current + 1) when next frame button is clicked" {
    const Test = struct {
        var controller = MockController{
            .mode = .record,
            .current_frame_index = 50,
            .total_frames = 100,
        };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemClick("###next_frame", 0, 0);
            try testing.expectEqual(1, controller.set_current_index_call_count);
            try testing.expectEqual(51, controller.set_current_index_argument);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should disable next frame button when currently on last frame" {
    const Test = struct {
        var controller = MockController{
            .mode = .record,
            .current_frame_index = 99,
            .total_frames = 100,
        };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemClick("###next_frame", 0, 0);
            try testing.expectEqual(0, controller.set_current_index_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call clear when clear button is clicked" {
    const Test = struct {
        var controller = MockController{ .mode = .live };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.clear_call_count);
            ctx.itemClick("###clear", 0, 0);
            try testing.expectEqual(1, controller.clear_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should disable all buttons except record when nothing is recorded" {
    const Test = struct {
        var controller = MockController{
            .mode = .live,
            .total_frames = 0,
            .current_frame_index = 0,
        };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");

            try testing.expectEqual(0, controller.play_call_count);
            ctx.itemClick("###play", 0, 0);
            try testing.expectEqual(0, controller.play_call_count);

            try testing.expectEqual(0, controller.pause_call_count);
            ctx.itemClick("###pause", 0, 0);
            try testing.expectEqual(0, controller.pause_call_count);

            try testing.expectEqual(0, controller.stop_call_count);
            ctx.itemClick("###stop", 0, 0);
            try testing.expectEqual(0, controller.stop_call_count);

            try testing.expectEqual(0, controller.record_call_count);
            ctx.itemClick("###record", 0, 0);
            try testing.expectEqual(1, controller.record_call_count);

            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemClick("###first_frame", 0, 0);
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemClick("###last_frame", 0, 0);
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemClick("###previous_frame", 0, 0);
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemClick("###next_frame", 0, 0);
            try testing.expectEqual(0, controller.set_current_index_call_count);

            try testing.expectEqual(0, controller.clear_call_count);
            ctx.itemClick("###clear", 0, 0);
            try testing.expectEqual(0, controller.clear_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should change playback speed when speed UI is used" {
    const Test = struct {
        var controller = MockController{ .mode = .playback };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            ctx.itemClick("###speed", 0, 0);

            ctx.setRef("//$FOCUSED");
            ctx.itemClick("0.50x", 0, 0);
            try testing.expectEqual(0.5, controller.playback_speed);

            ctx.setRef("Window");
            ctx.itemClick("###speed", 0, 0);

            ctx.setRef("//$FOCUSED");
            ctx.itemClick("2.00x", 0, 0);
            try testing.expectEqual(2.0, controller.playback_speed);

            ctx.setRef("Window");
            ctx.itemClick("###speed", 0, 0);

            ctx.setRef("//$FOCUSED");
            ctx.itemInputValueFloat("###speed_slider", 1.23);
            try testing.expectEqual(1.23, controller.playback_speed);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
