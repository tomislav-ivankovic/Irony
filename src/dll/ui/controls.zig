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
        was_playing_before_scrubbing: bool = false,
        total_frames_width: f32 = 0.0,
        speed_button_width: f32 = 0.0,

        const Self = @This();

        pub fn handleKeybinds(self: *Self, controller: *config.Controller) void {
            handlePlayKey(controller);
            handlePauseKey(controller);
            handleStopKey(controller);
            handleRecordKey(controller);
            self.handleRewindKey(controller);
            handlePreviousFrameKey(controller);
            handleNextFrameKey(controller);
            self.handleFastForwardKey(controller);
            handleClearKey(controller);
            handleDecreaseSpeedKey(controller);
            handleIncreaseSpeedKey(controller);
        }

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

            self.drawRewindButton(controller);
            imgui.igSameLine(0, spacing);
            drawPreviousFrameButton(controller);
            imgui.igSameLine(0, spacing);
            drawNextFrameButton(controller);
            imgui.igSameLine(0, spacing);
            self.drawFastForwardButton(controller);

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
            const disabled = isSeekbarDisabled(controller);
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();

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

        fn isSeekbarDisabled(controller: *const config.Controller) bool {
            return controller.mode == .save or
                controller.mode == .load or
                controller.getTotalFrames() == 0;
        }

        fn drawPlayButton(controller: *config.Controller) void {
            const disabled = isPlayDisabled(controller);
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();
            if (imgui.igButton(" ▶ ###play", .{})) {
                controller.play();
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Play [F1]");
            }
        }

        fn handlePlayKey(controller: *config.Controller) void {
            if (isPlayDisabled(controller)) {
                return;
            }
            if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F1, false)) {
                controller.play();
            }
        }

        fn isPlayDisabled(controller: *const config.Controller) bool {
            return controller.mode == .scrub or
                controller.mode == .playback or
                controller.mode == .save or
                controller.mode == .load or
                controller.getTotalFrames() == 0;
        }

        fn drawPauseButton(controller: *config.Controller) void {
            const disabled = isPauseDisabled(controller);
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();
            if (imgui.igButton(" ⏸ ###pause", .{})) {
                controller.pause();
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Pause [F2]");
            }
        }

        fn handlePauseKey(controller: *config.Controller) void {
            if (isPauseDisabled(controller)) {
                return;
            }
            if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F2, false)) {
                controller.pause();
            }
        }

        fn isPauseDisabled(controller: *const config.Controller) bool {
            return controller.mode == .scrub or
                controller.mode == .pause or
                controller.mode == .save or
                controller.mode == .load or
                controller.getTotalFrames() == 0;
        }

        fn drawStopButton(controller: *config.Controller) void {
            const disabled = isStopDisabled(controller);
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();
            if (imgui.igButton(" ⏹ ###stop", .{})) {
                controller.stop();
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Stop [F3]");
            }
        }

        fn handleStopKey(controller: *config.Controller) void {
            if (isStopDisabled(controller)) {
                return;
            }
            if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F3, false)) {
                controller.stop();
            }
        }

        fn isStopDisabled(controller: *const config.Controller) bool {
            return controller.mode == .scrub or
                controller.mode == .live or
                controller.mode == .save or
                controller.mode == .load;
        }

        fn drawRecordButton(controller: *config.Controller) void {
            const disabled = isRecordDisabled(controller);
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();
            if (imgui.igButton(" ⏺ ###record", .{})) {
                controller.record();
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Start Recording [F4]");
            }
        }

        fn handleRecordKey(controller: *config.Controller) void {
            if (isRecordDisabled(controller)) {
                return;
            }
            if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F4, false)) {
                controller.record();
            }
        }

        fn isRecordDisabled(controller: *const config.Controller) bool {
            return controller.mode == .scrub or
                controller.mode == .record or
                controller.mode == .save or
                controller.mode == .load;
        }

        fn drawRewindButton(self: *Self, controller: *config.Controller) void {
            const disabled = isRewindDisabled(controller);
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();
            _ = imgui.igButton(" ⏪ ###rewind", .{});
            if (imgui.igIsItemActivated()) {
                self.startRewind(controller);
            }
            if (imgui.igIsItemDeactivated()) {
                self.stopRewind(controller);
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Rewind [F5]");
            }
        }

        fn handleRewindKey(self: *Self, controller: *config.Controller) void {
            if (isRewindDisabled(controller)) {
                return;
            }
            if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F5, false)) {
                self.startRewind(controller);
            }
            if (imgui.igIsKeyReleased_Nil(imgui.ImGuiKey_F5)) {
                self.stopRewind(controller);
            }
        }

        fn isRewindDisabled(controller: *const config.Controller) bool {
            return controller.mode == .save or
                controller.mode == .load or
                controller.getTotalFrames() == 0;
        }

        fn startRewind(self: *Self, controller: *config.Controller) void {
            const direction = controller.getScrubDirection();
            if (direction == null) {
                self.was_playing_before_scrubbing = controller.mode == .playback;
                controller.scrub(.backward);
            } else if (direction == .forward) {
                controller.scrub(.neutral);
            }
        }

        fn stopRewind(self: *Self, controller: *config.Controller) void {
            const direction = controller.getScrubDirection() orelse return;
            switch (direction) {
                .backward => if (self.was_playing_before_scrubbing) controller.play() else controller.pause(),
                .neutral => controller.scrub(.forward),
                else => {},
            }
        }

        fn drawFastForwardButton(self: *Self, controller: *config.Controller) void {
            const disabled = isFastForwardDisabled(controller);
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();
            _ = imgui.igButton(" ⏩ ###fast_forward", .{});
            if (imgui.igIsItemActivated()) {
                self.startFastForward(controller);
            }
            if (imgui.igIsItemDeactivated()) {
                self.stopFastForward(controller);
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Fast Forward [F8]");
            }
        }

        fn handleFastForwardKey(self: *Self, controller: *config.Controller) void {
            if (isFastForwardDisabled(controller)) {
                return;
            }
            if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F8, false)) {
                self.startFastForward(controller);
            }
            if (imgui.igIsKeyReleased_Nil(imgui.ImGuiKey_F8)) {
                self.stopFastForward(controller);
            }
        }

        fn isFastForwardDisabled(controller: *const config.Controller) bool {
            return controller.mode == .save or
                controller.mode == .load or
                controller.getTotalFrames() == 0;
        }

        fn startFastForward(self: *Self, controller: *config.Controller) void {
            const direction = controller.getScrubDirection();
            if (direction == null) {
                self.was_playing_before_scrubbing = controller.mode == .playback;
                controller.scrub(.forward);
            } else if (direction == .backward) {
                controller.scrub(.neutral);
            }
        }

        fn stopFastForward(self: *Self, controller: *config.Controller) void {
            const direction = controller.getScrubDirection() orelse return;
            switch (direction) {
                .forward => if (self.was_playing_before_scrubbing) controller.play() else controller.pause(),
                .neutral => controller.scrub(.backward),
                else => {},
            }
        }

        fn drawPreviousFrameButton(controller: *config.Controller) void {
            const disabled = isPreviousFrameDisabled(controller);
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();
            imgui.igPushItemFlag(imgui.ImGuiItemFlags_ButtonRepeat, true);
            defer imgui.igPopItemFlag();
            if (imgui.igButton(" ⏴ ###previous_frame", .{})) {
                goToPreviousFrame(controller);
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Go To Previous Frame [F6]");
            }
        }

        fn handlePreviousFrameKey(controller: *config.Controller) void {
            if (isPreviousFrameDisabled(controller)) {
                return;
            }
            if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F6, true)) {
                goToPreviousFrame(controller);
            }
        }

        fn isPreviousFrameDisabled(controller: *const config.Controller) bool {
            if (controller.mode == .scrub or controller.mode == .save or controller.mode == .load) {
                return true;
            }
            const current = controller.getCurrentFrameIndex();
            const total = controller.getTotalFrames();
            return total == 0 or current == 0;
        }

        fn goToPreviousFrame(controller: *config.Controller) void {
            const current = controller.getCurrentFrameIndex();
            const next = if (current != null and current != 0) current.? - 1 else 0;
            controller.setCurrentFrameIndex(next);
            if (controller.mode != .pause) {
                controller.pause();
            }
        }

        fn drawNextFrameButton(controller: *config.Controller) void {
            const disabled = isNextFrameDisabled(controller);
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();
            imgui.igPushItemFlag(imgui.ImGuiItemFlags_ButtonRepeat, true);
            defer imgui.igPopItemFlag();
            if (imgui.igButton(" ⏵ ###next_frame", .{})) {
                goToNextFrame(controller);
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Go To Next Frame [F7]");
            }
        }

        fn handleNextFrameKey(controller: *config.Controller) void {
            if (isNextFrameDisabled(controller)) {
                return;
            }
            if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F7, true)) {
                goToNextFrame(controller);
            }
        }

        fn isNextFrameDisabled(controller: *const config.Controller) bool {
            if (controller.mode == .scrub or controller.mode == .save or controller.mode == .load) {
                return true;
            }
            const current = controller.getCurrentFrameIndex();
            const total = controller.getTotalFrames();
            return total == 0 or (current != null and current.? >= total - 1);
        }

        fn goToNextFrame(controller: *config.Controller) void {
            const current = controller.getCurrentFrameIndex();
            const next = if (current != null) current.? + 1 else 0;
            controller.setCurrentFrameIndex(next);
            if (controller.mode != .pause) {
                controller.pause();
            }
        }

        fn drawClearButton(controller: *config.Controller) void {
            const disabled = isClearDisabled(controller);
            if (disabled) imgui.igBeginDisabled(true);
            defer if (disabled) imgui.igEndDisabled();
            if (imgui.igButton(" 🗑 ###clear", .{})) {
                controller.clear();
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Clear Recording [F9]");
            }
        }

        fn handleClearKey(controller: *config.Controller) void {
            if (isClearDisabled(controller)) {
                return;
            }
            if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F9, false)) {
                controller.clear();
            }
        }

        fn isClearDisabled(controller: *const config.Controller) bool {
            return controller.mode == .scrub or
                controller.mode == .save or
                controller.mode == .load or
                controller.getTotalFrames() == 0;
        }

        fn drawSpeedButton(controller: *config.Controller) void {
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
                _ = imgui.igSliderFloat("###speed_slider", &controller.playback_speed, 0.1, 4.0, "%.2fx", 0);
                inline for ([_]f32{ 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0 }) |option| {
                    const text = std.fmt.comptimePrint("{d:.2}x", .{option});
                    if (imgui.igSelectable_Bool(text, controller.playback_speed == option, 0, .{})) {
                        controller.playback_speed = option;
                    }
                }
            }
        }

        fn handleDecreaseSpeedKey(controller: *config.Controller) void {
            if (!imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F10, true)) {
                return;
            }
            controller.playback_speed = @max(controller.playback_speed - 0.1, 0.1);
        }

        fn handleIncreaseSpeedKey(controller: *config.Controller) void {
            if (!imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F11, true)) {
                return;
            }
            controller.playback_speed = @min(controller.playback_speed + 0.1, 4.0);
        }
    };
}

const testing = std.testing;

const MockController = struct {
    mode: Mode,
    playback_speed: f32 = 1.0,
    total_frames: usize = 100,
    current_frame_index: ?usize = null,
    scrub_direction: ?ScrubDirection = null,
    play_call_count: usize = 0,
    pause_call_count: usize = 0,
    stop_call_count: usize = 0,
    record_call_count: usize = 0,
    scrub_call_count: usize = 0,
    last_scrub_direction: ?ScrubDirection = null,
    clear_call_count: usize = 0,
    set_current_index_call_count: usize = 0,
    set_current_index_argument: ?usize = null,

    const Self = @This();
    pub const Mode = enum {
        live,
        record,
        pause,
        playback,
        scrub,
        load,
        save,
    };
    pub const ScrubDirection = enum {
        forward,
        backward,
        neutral,
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

    pub fn scrub(self: *Self, direction: ScrubDirection) void {
        self.scrub_call_count += 1;
        self.last_scrub_direction = direction;
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

    pub fn getScrubDirection(self: *const Self) ?ScrubDirection {
        return self.scrub_direction;
    }
};

test "should display current frame index correctly when not null" {
    const Test = struct {
        var controller = MockController{ .mode = .playback, .current_frame_index = 123 };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.handleKeybinds(&controller);
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
            controls.handleKeybinds(&controller);
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
            controls.handleKeybinds(&controller);
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
            controls.handleKeybinds(&controller);
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
            controls.handleKeybinds(&controller);
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

test "should call play when play button is clicked or F1 key is pressed" {
    const Test = struct {
        var controller = MockController{ .mode = .live };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.play_call_count);
            ctx.itemClick("###play", 0, 0);
            try testing.expectEqual(1, controller.play_call_count);
            ctx.keyPress(imgui.ImGuiKey_F1, 1);
            try testing.expectEqual(2, controller.play_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should disable play when already in playback mode" {
    const Test = struct {
        var controller = MockController{ .mode = .playback };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.play_call_count);
            ctx.itemClick("###play", 0, 0);
            try testing.expectEqual(0, controller.play_call_count);
            ctx.keyPress(imgui.ImGuiKey_F1, 1);
            try testing.expectEqual(0, controller.play_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call pause when pause button is clicked or F2 key is pressed" {
    const Test = struct {
        var controller = MockController{ .mode = .live };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.pause_call_count);
            ctx.itemClick("###pause", 0, 0);
            try testing.expectEqual(1, controller.pause_call_count);
            ctx.keyPress(imgui.ImGuiKey_F2, 1);
            try testing.expectEqual(2, controller.pause_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should disable pause when already paused" {
    const Test = struct {
        var controller = MockController{ .mode = .pause };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.pause_call_count);
            ctx.itemClick("###pause", 0, 0);
            try testing.expectEqual(0, controller.pause_call_count);
            ctx.keyPress(imgui.ImGuiKey_F2, 1);
            try testing.expectEqual(0, controller.pause_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call stop when stop button is clicked or F3 key is pressed" {
    const Test = struct {
        var controller = MockController{ .mode = .playback };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.stop_call_count);
            ctx.itemClick("###stop", 0, 0);
            try testing.expectEqual(1, controller.stop_call_count);
            ctx.keyPress(imgui.ImGuiKey_F3, 1);
            try testing.expectEqual(2, controller.stop_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should disable stop when already stopped" {
    const Test = struct {
        var controller = MockController{ .mode = .live };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.stop_call_count);
            ctx.itemClick("###stop", 0, 0);
            try testing.expectEqual(0, controller.stop_call_count);
            ctx.keyPress(imgui.ImGuiKey_F3, 1);
            try testing.expectEqual(0, controller.stop_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call record when record button is clicked or F4 key is pressed" {
    const Test = struct {
        var controller = MockController{ .mode = .live };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.record_call_count);
            ctx.itemClick("###record", 0, 0);
            try testing.expectEqual(1, controller.record_call_count);
            ctx.keyPress(imgui.ImGuiKey_F4, 1);
            try testing.expectEqual(2, controller.record_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should disable record when already recording" {
    const Test = struct {
        var controller = MockController{ .mode = .record };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.record_call_count);
            ctx.itemClick("###record", 0, 0);
            try testing.expectEqual(0, controller.record_call_count);
            ctx.keyPress(imgui.ImGuiKey_F4, 1);
            try testing.expectEqual(0, controller.record_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call scrub(.backward) and pause when rewind button is clicked or F5 key is pressed and controller is not in playback" {
    const Test = struct {
        var controller = MockController{ .mode = .record };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            ctx.itemAction(imgui.ImGuiTestAction_Hover, "###rewind", 0, null);

            try testing.expectEqual(0, controller.scrub_call_count);
            try testing.expectEqual(0, controller.pause_call_count);

            ctx.mouseDown(imgui.ImGuiMouseButton_Left);

            try testing.expectEqual(1, controller.scrub_call_count);
            try testing.expectEqual(.backward, controller.last_scrub_direction);
            try testing.expectEqual(0, controller.pause_call_count);
            controller.mode = .scrub;
            controller.scrub_direction = .backward;

            ctx.mouseUp(imgui.ImGuiMouseButton_Left);

            try testing.expectEqual(1, controller.scrub_call_count);
            try testing.expectEqual(1, controller.pause_call_count);
            controller.mode = .pause;
            controller.scrub_direction = null;

            ctx.keyDown(imgui.ImGuiKey_F5);

            try testing.expectEqual(2, controller.scrub_call_count);
            try testing.expectEqual(.backward, controller.last_scrub_direction);
            try testing.expectEqual(1, controller.pause_call_count);
            controller.mode = .scrub;
            controller.scrub_direction = .backward;

            ctx.keyUp(imgui.ImGuiKey_F5);

            try testing.expectEqual(2, controller.scrub_call_count);
            try testing.expectEqual(2, controller.pause_call_count);
            controller.mode = .pause;
            controller.scrub_direction = null;
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call scrub(.backward) and play when rewind button is clicked or F5 key is pressed and controller is in playback" {
    const Test = struct {
        var controller = MockController{ .mode = .playback };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            ctx.itemAction(imgui.ImGuiTestAction_Hover, "###rewind", 0, null);

            try testing.expectEqual(0, controller.scrub_call_count);
            try testing.expectEqual(0, controller.play_call_count);

            ctx.mouseDown(imgui.ImGuiMouseButton_Left);

            try testing.expectEqual(1, controller.scrub_call_count);
            try testing.expectEqual(.backward, controller.last_scrub_direction);
            try testing.expectEqual(0, controller.play_call_count);
            controller.mode = .scrub;
            controller.scrub_direction = .backward;

            ctx.mouseUp(imgui.ImGuiMouseButton_Left);

            try testing.expectEqual(1, controller.scrub_call_count);
            try testing.expectEqual(1, controller.play_call_count);
            controller.mode = .playback;
            controller.scrub_direction = null;

            ctx.keyDown(imgui.ImGuiKey_F5);

            try testing.expectEqual(2, controller.scrub_call_count);
            try testing.expectEqual(.backward, controller.last_scrub_direction);
            try testing.expectEqual(1, controller.play_call_count);
            controller.mode = .scrub;
            controller.scrub_direction = .backward;

            ctx.keyUp(imgui.ImGuiKey_F5);

            try testing.expectEqual(2, controller.scrub_call_count);
            try testing.expectEqual(2, controller.play_call_count);
            controller.mode = .playback;
            controller.scrub_direction = null;
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call scrub(.neutral) and scrub(.forward) when rewind button is clicked or F5 key is pressed and controller scrubbing forward" {
    const Test = struct {
        var controller = MockController{ .mode = .scrub, .scrub_direction = .forward };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            ctx.itemAction(imgui.ImGuiTestAction_Hover, "###rewind", 0, null);

            try testing.expectEqual(0, controller.scrub_call_count);

            ctx.mouseDown(imgui.ImGuiMouseButton_Left);

            try testing.expectEqual(1, controller.scrub_call_count);
            try testing.expectEqual(.neutral, controller.last_scrub_direction);
            controller.scrub_direction = .neutral;

            ctx.mouseUp(imgui.ImGuiMouseButton_Left);

            try testing.expectEqual(2, controller.scrub_call_count);
            try testing.expectEqual(.forward, controller.last_scrub_direction);
            controller.scrub_direction = .forward;

            ctx.keyDown(imgui.ImGuiKey_F5);

            try testing.expectEqual(3, controller.scrub_call_count);
            try testing.expectEqual(.neutral, controller.last_scrub_direction);
            controller.scrub_direction = .neutral;

            ctx.keyUp(imgui.ImGuiKey_F5);

            try testing.expectEqual(4, controller.scrub_call_count);
            try testing.expectEqual(.forward, controller.last_scrub_direction);
            controller.scrub_direction = .forward;
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call scrub(.forward) and pause when fast forward button is clicked or F8 key is pressed and controller is not in playback" {
    const Test = struct {
        var controller = MockController{ .mode = .record };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            ctx.itemAction(imgui.ImGuiTestAction_Hover, "###fast_forward", 0, null);

            try testing.expectEqual(0, controller.scrub_call_count);
            try testing.expectEqual(0, controller.pause_call_count);

            ctx.mouseDown(imgui.ImGuiMouseButton_Left);

            try testing.expectEqual(1, controller.scrub_call_count);
            try testing.expectEqual(.forward, controller.last_scrub_direction);
            try testing.expectEqual(0, controller.pause_call_count);
            controller.mode = .scrub;
            controller.scrub_direction = .forward;

            ctx.mouseUp(imgui.ImGuiMouseButton_Left);

            try testing.expectEqual(1, controller.scrub_call_count);
            try testing.expectEqual(1, controller.pause_call_count);
            controller.mode = .pause;
            controller.scrub_direction = null;

            ctx.keyDown(imgui.ImGuiKey_F8);

            try testing.expectEqual(2, controller.scrub_call_count);
            try testing.expectEqual(.forward, controller.last_scrub_direction);
            try testing.expectEqual(1, controller.pause_call_count);
            controller.mode = .scrub;
            controller.scrub_direction = .forward;

            ctx.keyUp(imgui.ImGuiKey_F8);

            try testing.expectEqual(2, controller.scrub_call_count);
            try testing.expectEqual(2, controller.pause_call_count);
            controller.mode = .pause;
            controller.scrub_direction = null;
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call scrub(.forward) and play when fast forward button is clicked or F8 key is pressed and controller is in playback" {
    const Test = struct {
        var controller = MockController{
            .mode = .playback,
            .current_frame_index = 50,
            .total_frames = 100,
        };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            ctx.itemAction(imgui.ImGuiTestAction_Hover, "###fast_forward", 0, null);

            try testing.expectEqual(0, controller.scrub_call_count);
            try testing.expectEqual(0, controller.play_call_count);

            ctx.mouseDown(imgui.ImGuiMouseButton_Left);

            try testing.expectEqual(1, controller.scrub_call_count);
            try testing.expectEqual(.forward, controller.last_scrub_direction);
            try testing.expectEqual(0, controller.play_call_count);
            controller.mode = .scrub;
            controller.scrub_direction = .forward;

            ctx.mouseUp(imgui.ImGuiMouseButton_Left);

            try testing.expectEqual(1, controller.scrub_call_count);
            try testing.expectEqual(1, controller.play_call_count);
            controller.mode = .playback;
            controller.scrub_direction = null;

            ctx.keyDown(imgui.ImGuiKey_F8);

            try testing.expectEqual(2, controller.scrub_call_count);
            try testing.expectEqual(.forward, controller.last_scrub_direction);
            try testing.expectEqual(1, controller.play_call_count);
            controller.mode = .scrub;
            controller.scrub_direction = .forward;

            ctx.keyUp(imgui.ImGuiKey_F8);

            try testing.expectEqual(2, controller.scrub_call_count);
            try testing.expectEqual(2, controller.play_call_count);
            controller.mode = .playback;
            controller.scrub_direction = null;
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call scrub(.neutral) and scrub(.backward) when fast forward button is clicked or F8 key is pressed and controller scrubbing backward" {
    const Test = struct {
        var controller = MockController{ .mode = .scrub, .scrub_direction = .backward };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            ctx.itemAction(imgui.ImGuiTestAction_Hover, "###fast_forward", 0, null);

            try testing.expectEqual(0, controller.scrub_call_count);

            ctx.mouseDown(imgui.ImGuiMouseButton_Left);

            try testing.expectEqual(1, controller.scrub_call_count);
            try testing.expectEqual(.neutral, controller.last_scrub_direction);
            controller.scrub_direction = .neutral;

            ctx.mouseUp(imgui.ImGuiMouseButton_Left);

            try testing.expectEqual(2, controller.scrub_call_count);
            try testing.expectEqual(.backward, controller.last_scrub_direction);
            controller.scrub_direction = .backward;

            ctx.keyDown(imgui.ImGuiKey_F8);

            try testing.expectEqual(3, controller.scrub_call_count);
            try testing.expectEqual(.neutral, controller.last_scrub_direction);
            controller.scrub_direction = .neutral;

            ctx.keyUp(imgui.ImGuiKey_F8);

            try testing.expectEqual(4, controller.scrub_call_count);
            try testing.expectEqual(.backward, controller.last_scrub_direction);
            controller.scrub_direction = .backward;
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call setCurrentFrameIndex(current - 1) and pause when previous frame button is clicked or F6 key is pressed" {
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
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            try testing.expectEqual(0, controller.pause_call_count);
            ctx.itemClick("###previous_frame", 0, 0);
            try testing.expectEqual(1, controller.set_current_index_call_count);
            try testing.expectEqual(49, controller.set_current_index_argument);
            try testing.expectEqual(1, controller.pause_call_count);
            ctx.keyPress(imgui.ImGuiKey_F6, 1);
            try testing.expectEqual(2, controller.set_current_index_call_count);
            try testing.expectEqual(49, controller.set_current_index_argument);
            try testing.expectEqual(2, controller.pause_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should disable previous frame when already on first frame" {
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
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemClick("###previous_frame", 0, 0);
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.keyPress(imgui.ImGuiKey_F6, 1);
            try testing.expectEqual(0, controller.set_current_index_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call setCurrentFrameIndex(current + 1) and pause when next frame button is clicked or F7 key is pressed" {
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
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            try testing.expectEqual(0, controller.pause_call_count);
            ctx.itemClick("###next_frame", 0, 0);
            try testing.expectEqual(1, controller.set_current_index_call_count);
            try testing.expectEqual(51, controller.set_current_index_argument);
            try testing.expectEqual(1, controller.pause_call_count);
            ctx.keyPress(imgui.ImGuiKey_F7, 1);
            try testing.expectEqual(2, controller.set_current_index_call_count);
            try testing.expectEqual(51, controller.set_current_index_argument);
            try testing.expectEqual(2, controller.pause_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should disable next frame when already on last frame" {
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
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemClick("###next_frame", 0, 0);
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.keyPress(imgui.ImGuiKey_F7, 1);
            try testing.expectEqual(0, controller.set_current_index_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call clear when clear button is clicked or F9 button is pressed" {
    const Test = struct {
        var controller = MockController{ .mode = .live };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.clear_call_count);
            ctx.itemClick("###clear", 0, 0);
            try testing.expectEqual(1, controller.clear_call_count);
            ctx.keyPress(imgui.ImGuiKey_F9, 1);
            try testing.expectEqual(2, controller.clear_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should disable all buttons/keys except record when nothing is recorded" {
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
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");

            try testing.expectEqual(0, controller.play_call_count);
            ctx.itemClick("###play", 0, 0);
            try testing.expectEqual(0, controller.play_call_count);
            ctx.keyPress(imgui.ImGuiKey_F1, 1);
            try testing.expectEqual(0, controller.play_call_count);

            try testing.expectEqual(0, controller.pause_call_count);
            ctx.itemClick("###pause", 0, 0);
            try testing.expectEqual(0, controller.pause_call_count);
            ctx.keyPress(imgui.ImGuiKey_F2, 1);
            try testing.expectEqual(0, controller.pause_call_count);

            try testing.expectEqual(0, controller.stop_call_count);
            ctx.itemClick("###stop", 0, 0);
            try testing.expectEqual(0, controller.stop_call_count);
            ctx.keyPress(imgui.ImGuiKey_F3, 1);
            try testing.expectEqual(0, controller.stop_call_count);

            try testing.expectEqual(0, controller.record_call_count);
            ctx.itemClick("###record", 0, 0);
            try testing.expectEqual(1, controller.record_call_count);
            ctx.keyPress(imgui.ImGuiKey_F4, 1);
            try testing.expectEqual(2, controller.record_call_count);

            try testing.expectEqual(0, controller.play_call_count);
            ctx.itemClick("###rewind", 0, 0);
            try testing.expectEqual(0, controller.play_call_count);
            ctx.keyPress(imgui.ImGuiKey_F5, 1);
            try testing.expectEqual(0, controller.play_call_count);
            ctx.itemClick("###fast_forward", 0, 0);
            try testing.expectEqual(0, controller.play_call_count);
            ctx.keyPress(imgui.ImGuiKey_F8, 1);
            try testing.expectEqual(0, controller.play_call_count);

            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemClick("###previous_frame", 0, 0);
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.keyPress(imgui.ImGuiKey_F6, 1);
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemClick("###next_frame", 0, 0);
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.keyPress(imgui.ImGuiKey_F7, 1);
            try testing.expectEqual(0, controller.set_current_index_call_count);

            try testing.expectEqual(0, controller.clear_call_count);
            ctx.itemClick("###clear", 0, 0);
            try testing.expectEqual(0, controller.clear_call_count);
            ctx.keyPress(imgui.ImGuiKey_F9, 1);
            try testing.expectEqual(0, controller.clear_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should disable all buttons/keys except rewind and fast forward while scrubbing" {
    const Test = struct {
        var controller = MockController{ .mode = .scrub };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.handleKeybinds(&controller);
            controls.draw(&controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");

            try testing.expectEqual(0, controller.play_call_count);
            ctx.itemClick("###play", 0, 0);
            try testing.expectEqual(0, controller.play_call_count);
            ctx.keyPress(imgui.ImGuiKey_F1, 1);
            try testing.expectEqual(0, controller.play_call_count);

            try testing.expectEqual(0, controller.pause_call_count);
            ctx.itemClick("###pause", 0, 0);
            try testing.expectEqual(0, controller.pause_call_count);
            ctx.keyPress(imgui.ImGuiKey_F2, 1);
            try testing.expectEqual(0, controller.pause_call_count);

            try testing.expectEqual(0, controller.stop_call_count);
            ctx.itemClick("###stop", 0, 0);
            try testing.expectEqual(0, controller.stop_call_count);
            ctx.keyPress(imgui.ImGuiKey_F3, 1);
            try testing.expectEqual(0, controller.stop_call_count);

            try testing.expectEqual(0, controller.record_call_count);
            ctx.itemClick("###record", 0, 0);
            try testing.expectEqual(0, controller.record_call_count);
            ctx.keyPress(imgui.ImGuiKey_F4, 1);
            try testing.expectEqual(0, controller.record_call_count);

            try testing.expectEqual(0, controller.scrub_call_count);
            ctx.itemClick("###rewind", 0, 0);
            try testing.expectEqual(1, controller.scrub_call_count);
            ctx.keyPress(imgui.ImGuiKey_F5, 1);
            try testing.expectEqual(2, controller.scrub_call_count);
            ctx.itemClick("###fast_forward", 0, 0);
            try testing.expectEqual(3, controller.scrub_call_count);
            ctx.keyPress(imgui.ImGuiKey_F8, 1);
            try testing.expectEqual(4, controller.scrub_call_count);

            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemClick("###previous_frame", 0, 0);
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.keyPress(imgui.ImGuiKey_F6, 1);
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.itemClick("###next_frame", 0, 0);
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.keyPress(imgui.ImGuiKey_F7, 1);
            try testing.expectEqual(0, controller.set_current_index_call_count);

            try testing.expectEqual(0, controller.clear_call_count);
            ctx.itemClick("###clear", 0, 0);
            try testing.expectEqual(0, controller.clear_call_count);
            ctx.keyPress(imgui.ImGuiKey_F9, 1);
            try testing.expectEqual(0, controller.clear_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should change playback speed when speed UI and F10,F11 keys are used" {
    const Test = struct {
        var controller = MockController{ .mode = .playback };
        var controls = Controls(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            controls.handleKeybinds(&controller);
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

            ctx.keyPress(imgui.ImGuiKey_F10, 1);
            try testing.expectEqual(1.13, controller.playback_speed);

            ctx.keyPress(imgui.ImGuiKey_F11, 1);
            try testing.expectEqual(1.23, controller.playback_speed);

            ctx.keyPress(imgui.ImGuiKey_F10, 100);
            try testing.expectEqual(0.1, controller.playback_speed);

            ctx.keyPress(imgui.ImGuiKey_F11, 100);
            try testing.expectEqual(4.0, controller.playback_speed);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

// TODO test with save/load controller mode.
