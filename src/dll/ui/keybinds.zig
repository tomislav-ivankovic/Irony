const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const core = @import("../core/root.zig");

pub const KeybindsConfig = struct {
    Controller: type = core.Controller,
};

pub fn Keybinds(comptime config: KeybindsConfig) type {
    return struct {
        const Self = @This();

        pub fn handle(self: *Self, is_main_window_open: *bool, controller: *config.Controller) void {
            _ = self;
            handleMainWindowKey(is_main_window_open);
            handlePlayKey(controller);
            handlePauseKey(controller);
            handleStopKey(controller);
            handleRecordKey(controller);
            handleFirstFrameKey(controller);
            handlePreviousFrameKey(controller);
            handleNextFrameKey(controller);
            handleLastFrameKey(controller);
            handleClearKey(controller);
            handleDecreaseSpeedKey(controller);
            handleIncreaseSpeedKey(controller);
        }

        fn handleMainWindowKey(is_main_window_open: *bool) void {
            if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_Tab, false)) {
                is_main_window_open.* = !is_main_window_open.*;
            }
        }

        fn handlePlayKey(controller: *config.Controller) void {
            if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F1, false)) {
                controller.play();
            }
        }

        fn handlePauseKey(controller: *config.Controller) void {
            if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F2, false)) {
                controller.pause();
            }
        }

        fn handleStopKey(controller: *config.Controller) void {
            if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F3, false)) {
                controller.stop();
            }
        }

        fn handleRecordKey(controller: *config.Controller) void {
            if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F4, false)) {
                controller.record();
            }
        }

        fn handleFirstFrameKey(controller: *config.Controller) void {
            if (!imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F5, false)) {
                return;
            }
            const current = controller.getCurrentFrameIndex();
            const total = controller.getTotalFrames();
            if (total == 0 or current == 0) {
                return;
            }
            controller.setCurrentFrameIndex(0);
        }

        fn handleLastFrameKey(controller: *config.Controller) void {
            if (!imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F8, false)) {
                return;
            }
            const current = controller.getCurrentFrameIndex();
            const total = controller.getTotalFrames();
            if (total == 0 or (current != null and current.? >= total - 1)) {
                return;
            }
            controller.setCurrentFrameIndex(total - 1);
        }

        fn handlePreviousFrameKey(controller: *config.Controller) void {
            if (!imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F6, true)) {
                return;
            }
            const current = controller.getCurrentFrameIndex();
            const total = controller.getTotalFrames();
            if (total == 0 or current == 0) {
                return;
            }
            const next = if (current != null and current != 0) current.? - 1 else 0;
            controller.setCurrentFrameIndex(next);
        }

        fn handleNextFrameKey(controller: *config.Controller) void {
            if (!imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F7, true)) {
                return;
            }
            const current = controller.getCurrentFrameIndex();
            const total = controller.getTotalFrames();
            if (total == 0 or (current != null and current.? >= total - 1)) {
                return;
            }
            const next = if (current != null) current.? + 1 else 0;
            controller.setCurrentFrameIndex(next);
        }

        fn handleClearKey(controller: *config.Controller) void {
            if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F9, false)) {
                controller.clear();
            }
        }

        fn handleDecreaseSpeedKey(controller: *config.Controller) void {
            if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F10, true)) {
                controller.playback_speed = @max(controller.playback_speed - 0.1, 0.1);
            }
        }

        fn handleIncreaseSpeedKey(controller: *config.Controller) void {
            if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_F11, true)) {
                controller.playback_speed = @min(controller.playback_speed + 0.1, 4.0);
            }
        }
    };
}

const testing = std.testing;

const MockController = struct {
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

test "should toggle main window opened state when Tab is pressed" {
    const Test = struct {
        var main_window_open = false;
        var controller = MockController{};
        var binds = Keybinds(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            binds.handle(&main_window_open, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(false, main_window_open);
            ctx.keyPress(imgui.ImGuiKey_Tab, 1);
            try testing.expectEqual(true, main_window_open);
            ctx.keyPress(imgui.ImGuiKey_Tab, 1);
            try testing.expectEqual(false, main_window_open);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call play when F1 key is pressed" {
    const Test = struct {
        var main_window_open = false;
        var controller = MockController{};
        var binds = Keybinds(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            binds.handle(&main_window_open, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.play_call_count);
            ctx.keyPress(imgui.ImGuiKey_F1, 1);
            try testing.expectEqual(1, controller.play_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call pause when F2 key is pressed" {
    const Test = struct {
        var main_window_open = false;
        var controller = MockController{};
        var binds = Keybinds(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            binds.handle(&main_window_open, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.pause_call_count);
            ctx.keyPress(imgui.ImGuiKey_F2, 1);
            try testing.expectEqual(1, controller.pause_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call stop when F3 key is pressed" {
    const Test = struct {
        var main_window_open = false;
        var controller = MockController{};
        var binds = Keybinds(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            binds.handle(&main_window_open, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.stop_call_count);
            ctx.keyPress(imgui.ImGuiKey_F3, 1);
            try testing.expectEqual(1, controller.stop_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call record when F4 key is pressed" {
    const Test = struct {
        var main_window_open = false;
        var controller = MockController{};
        var binds = Keybinds(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            binds.handle(&main_window_open, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.record_call_count);
            ctx.keyPress(imgui.ImGuiKey_F4, 1);
            try testing.expectEqual(1, controller.record_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call setCurrentFrameIndex(0) when F5 is pressed" {
    const Test = struct {
        var main_window_open = false;
        var controller = MockController{ .current_frame_index = 50, .total_frames = 100 };
        var binds = Keybinds(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            binds.handle(&main_window_open, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.keyPress(imgui.ImGuiKey_F5, 1);
            try testing.expectEqual(1, controller.set_current_index_call_count);
            try testing.expectEqual(0, controller.set_current_index_argument);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should not call setCurrentFrameIndex when F5 is pressed but already on first frame" {
    const Test = struct {
        var main_window_open = false;
        var controller = MockController{ .current_frame_index = 0, .total_frames = 100 };
        var binds = Keybinds(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            binds.handle(&main_window_open, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.keyPress(imgui.ImGuiKey_F5, 1);
            try testing.expectEqual(0, controller.set_current_index_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call setCurrentFrameIndex(current - 1) when F6 is pressed" {
    const Test = struct {
        var main_window_open = false;
        var controller = MockController{ .current_frame_index = 50, .total_frames = 100 };
        var binds = Keybinds(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            binds.handle(&main_window_open, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.keyPress(imgui.ImGuiKey_F6, 1);
            try testing.expectEqual(1, controller.set_current_index_call_count);
            try testing.expectEqual(49, controller.set_current_index_argument);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should not call setCurrentFrameIndex when F6 is pressed but currently on first frame" {
    const Test = struct {
        var main_window_open = false;
        var controller = MockController{ .current_frame_index = 0, .total_frames = 100 };
        var binds = Keybinds(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            binds.handle(&main_window_open, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.keyPress(imgui.ImGuiKey_F6, 1);
            try testing.expectEqual(0, controller.set_current_index_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call setCurrentFrameIndex(current + 1) when F7 is pressed" {
    const Test = struct {
        var main_window_open = false;
        var controller = MockController{ .current_frame_index = 50, .total_frames = 100 };
        var binds = Keybinds(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            binds.handle(&main_window_open, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.keyPress(imgui.ImGuiKey_F7, 1);
            try testing.expectEqual(1, controller.set_current_index_call_count);
            try testing.expectEqual(51, controller.set_current_index_argument);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should not call setCurrentFrameIndex when F7 is pressed but already on last frame" {
    const Test = struct {
        var main_window_open = false;
        var controller = MockController{ .current_frame_index = 99, .total_frames = 100 };
        var binds = Keybinds(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            binds.handle(&main_window_open, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.keyPress(imgui.ImGuiKey_F7, 1);
            try testing.expectEqual(0, controller.set_current_index_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call setCurrentFrameIndex(total - 1) when F8 is pressed" {
    const Test = struct {
        var main_window_open = false;
        var controller = MockController{ .current_frame_index = 50, .total_frames = 100 };
        var binds = Keybinds(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            binds.handle(&main_window_open, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.keyPress(imgui.ImGuiKey_F8, 1);
            try testing.expectEqual(1, controller.set_current_index_call_count);
            try testing.expectEqual(99, controller.set_current_index_argument);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should not call setCurrentFrameIndex when F8 is pressed but currently on last frame" {
    const Test = struct {
        var main_window_open = false;
        var controller = MockController{ .current_frame_index = 99, .total_frames = 100 };
        var binds = Keybinds(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            binds.handle(&main_window_open, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.keyPress(imgui.ImGuiKey_F8, 1);
            try testing.expectEqual(0, controller.set_current_index_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should not call setCurrentFrameIndex when F5-F8 is pressed but nothing is recorded" {
    const Test = struct {
        var main_window_open = false;
        var controller = MockController{ .current_frame_index = 0, .total_frames = 0 };
        var binds = Keybinds(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            binds.handle(&main_window_open, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.keyPress(imgui.ImGuiKey_F5, 1);
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.keyPress(imgui.ImGuiKey_F6, 1);
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.keyPress(imgui.ImGuiKey_F7, 1);
            try testing.expectEqual(0, controller.set_current_index_call_count);
            ctx.keyPress(imgui.ImGuiKey_F8, 1);
            try testing.expectEqual(0, controller.set_current_index_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call clear when F9 is pressed" {
    const Test = struct {
        var main_window_open = false;
        var controller = MockController{};
        var binds = Keybinds(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            binds.handle(&main_window_open, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(0, controller.clear_call_count);
            ctx.keyPress(imgui.ImGuiKey_F9, 1);
            try testing.expectEqual(1, controller.clear_call_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should decrease playback speed when when F10 is pressed" {
    const Test = struct {
        var main_window_open = false;
        var controller = MockController{ .playback_speed = 1.0 };
        var binds = Keybinds(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            binds.handle(&main_window_open, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectApproxEqAbs(1.0, controller.playback_speed, 0.000001);
            ctx.keyPress(imgui.ImGuiKey_F10, 1);
            try testing.expectApproxEqAbs(0.9, controller.playback_speed, 0.000001);
            ctx.keyPress(imgui.ImGuiKey_F10, 1);
            try testing.expectApproxEqAbs(0.8, controller.playback_speed, 0.000001);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should increase playback speed when when F11 is pressed" {
    const Test = struct {
        var main_window_open = false;
        var controller = MockController{ .playback_speed = 1.0 };
        var binds = Keybinds(.{ .Controller = MockController }){};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            binds.handle(&main_window_open, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectApproxEqAbs(1.0, controller.playback_speed, 0.000001);
            ctx.keyPress(imgui.ImGuiKey_F11, 1);
            try testing.expectApproxEqAbs(1.1, controller.playback_speed, 0.000001);
            ctx.keyPress(imgui.ImGuiKey_F11, 1);
            try testing.expectApproxEqAbs(1.2, controller.playback_speed, 0.000001);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
