const std = @import("std");
const builtin = @import("builtin");
const imgui = @import("imgui");
const misc = @import("../misc/root.zig");
const ui = @import("root.zig");

threadlocal var allocator_instance = std.heap.GeneralPurposeAllocator(.{}){};
threadlocal var instance: ?TestingContext = null;
threadlocal var times_initialized: usize = 0;

pub fn getTestingContext() !(*const TestingContext) {
    if (!builtin.is_test) {
        @compileError("TestingContext is only allowed to be used in tests.");
    }
    if (instance == null) {
        instance = TestingContext.init(allocator_instance.allocator()) catch |err| {
            misc.error_context.append("Failed to initialize UI testing context.", .{});
            return err;
        };
        times_initialized += 1;
        if (times_initialized > 1) {
            std.log.err(
                "UI testing context initialized {} times." ++
                    "This could be because the de-initialization happened in-between UI tests and not after all UI tests.",
                .{times_initialized},
            );
        }
    }
    return &instance.?;
}

pub fn deinitTestingContextAndDetectLeaks() void {
    if (!builtin.is_test) {
        @compileError("TestingContext is only allowed to be used in tests.");
    }
    if (instance) |*context| {
        context.deinit();
        instance = null;
    }
    if (allocator_instance.detectLeaks()) {
        std.log.err("UI testing context detected a memory leak.", .{});
    }
}

pub const TestingContext = struct {
    allocator: std.mem.Allocator,
    old_allocator: ?std.mem.Allocator,
    engine: *imgui.ImGuiTestEngine,
    imgui_context: *imgui.ImGuiContext,

    const Self = @This();
    pub const Function = fn (ctx: ui.TestContext) anyerror!void;
    pub const Config = struct {
        run_flags: imgui.ImGuiTestRunFlags = imgui.ImGuiTestRunFlags_None,
        disable_printing: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator) !Self {
        const old_allocator = ui.getAllocator();
        ui.setAllocator(allocator);
        errdefer ui.setAllocator(old_allocator);

        const engine = imgui.teCreateContext() orelse {
            misc.error_context.new("teCreateContext returned null.", .{});
            return error.ImguiError;
        };
        errdefer imgui.teDestroyContext(engine);

        const imgui_context = imgui.igCreateContext(null) orelse {
            misc.error_context.new("igCreateContext returned null.", .{});
            return error.ImguiError;
        };
        errdefer imgui.igDestroyContext(imgui_context);

        const test_io = imgui.teGetIO(engine);
        test_io.*.ConfigVerboseLevel = imgui.ImGuiTestVerboseLevel_Info;
        test_io.*.ConfigVerboseLevelOnError = imgui.ImGuiTestVerboseLevel_Debug;

        const imgui_io = imgui.igGetIO();
        imgui_io.*.IniFilename = null;
        var pixels: [*c]u8 = undefined;
        var width: c_int = undefined;
        var height: c_int = undefined;
        var bytes_per_pixel: c_int = undefined;
        _ = imgui.ImFontAtlas_GetTexDataAsRGBA32(imgui_io.*.Fonts, &pixels, &width, &height, &bytes_per_pixel);

        imgui.teStart(engine, imgui_context);
        errdefer imgui.teStop(engine);

        return .{
            .allocator = allocator,
            .old_allocator = old_allocator,
            .engine = engine,
            .imgui_context = imgui_context,
        };
    }

    pub fn deinit(self: *Self) void {
        imgui.teStop(self.engine);
        imgui.igDestroyContext(self.imgui_context);
        imgui.teDestroyContext(self.engine);
        ui.setAllocator(self.old_allocator);
    }

    pub fn runTest(
        self: *const Self,
        comptime config: Config,
        comptime guiFunction: *const Function,
        comptime testFunction: *const Function,
    ) !void {
        const the_test = imgui.teRegisterTest(self.engine, "", "", null, 0);
        defer imgui.teUnregisterTest(self.engine, the_test);

        const GuiFunction = struct {
            var returned_error: ?anyerror = null;
            fn call(raw_ctx: [*c]imgui.ImGuiTestContext) callconv(.c) void {
                if (returned_error != null) {
                    return;
                }
                const ctx = ui.TestContext{ .raw = raw_ctx };
                guiFunction(ctx) catch |err| {
                    if (!config.disable_printing) {
                        misc.error_context.append("Failed to execute test's GUI function.", .{});
                        misc.error_context.logError(err);
                    }
                    returned_error = err;
                };
            }
        };
        GuiFunction.returned_error = null;
        the_test.*.GuiFunc = GuiFunction.call;

        const TestFunction = struct {
            var returned_error: ?anyerror = null;
            fn call(raw_ctx: [*c]imgui.ImGuiTestContext) callconv(.c) void {
                if (returned_error != null) {
                    return;
                }
                const ctx = ui.TestContext{ .raw = raw_ctx };
                testFunction(ctx) catch |err| {
                    if (!config.disable_printing) {
                        misc.error_context.append("Failed to execute test's TEST function.", .{});
                        misc.error_context.logError(err);
                    }
                    returned_error = err;
                };
            }
        };
        TestFunction.returned_error = null;
        the_test.*.TestFunc = TestFunction.call;

        imgui.teClearUiState();
        imgui.igSetClipboardText("");
        imgui.teQueueTest(self.engine, the_test, config.run_flags);
        while (!imgui.teIsTestQueueEmpty(self.engine)) {
            misc.error_context.clear();

            const imgui_io = imgui.igGetIO();
            imgui_io.*.DisplaySize = .{ .x = 1280, .y = 720 };
            imgui_io.*.DeltaTime = 1.0 / 60.00;

            imgui.igNewFrame();
            imgui.igRender();
            imgui.tePostSwap(self.engine);
        }

        if (GuiFunction.returned_error) |err| {
            printTestFailedLog(config, the_test);
            return err;
        }
        if (TestFunction.returned_error) |err| {
            printTestFailedLog(config, the_test);
            return err;
        }
        const status = the_test.*.Output.Status;
        switch (status) {
            imgui.ImGuiTestStatus_Success => {},
            imgui.ImGuiTestStatus_Error => {
                printTestFailedLog(config, the_test);
                return error.UiTestFailed;
            },
            else => if (!config.disable_printing) {
                std.debug.print(
                    "Expecting the UI test to end with status Success (1) or Error (4) but instead got status: {}",
                    .{status},
                );
                return error.UnexpectedTestStatus;
            },
        }
    }

    fn printTestFailedLog(comptime config: Config, the_test: *imgui.ImGuiTest) void {
        if (config.disable_printing) {
            return;
        }
        const buffer = imgui.ImGuiTextBuffer_ImGuiTextBuffer();
        defer imgui.ImGuiTextBuffer_destroy(buffer);
        const count = imgui.ImGuiTestLog_ExtractLinesForVerboseLevels(
            &the_test.*.Output.Log,
            imgui.ImGuiTestVerboseLevel_Error,
            imgui.ImGuiTestVerboseLevel_Warning,
            buffer,
        );
        if (count > 0) {
            const str = imgui.ImGuiTextBuffer_c_str(buffer);
            std.debug.print("UI test failed with the following log:\n{s}", .{str});
        } else {
            std.debug.print("UI test failed but no logs recorded.", .{});
        }
    }
};

const testing = std.testing;

test "should pass a successful test" {
    const Test = struct {
        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
        }

        fn testFunction(ctx: ui.TestContext) !void {
            try ctx.expectItemExists("Window");
        }
    };
    const context = try getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should fail the test when testing engine detects a fail" {
    const Test = struct {
        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
        }

        fn testFunction(ctx: ui.TestContext) !void {
            ctx.itemClick("Window/Button", imgui.ImGuiMouseButton_Left, 0);
        }
    };
    const context = try getTestingContext();
    const test_result = context.runTest(.{ .disable_printing = true }, Test.guiFunction, Test.testFunction);
    try testing.expectError(error.UiTestFailed, test_result);
}

test "should fail the test when gui function returns error" {
    const Test = struct {
        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            return error.TestError;
        }

        fn testFunction(ctx: ui.TestContext) !void {
            ctx.setRef("Window");
        }
    };
    const context = try getTestingContext();
    const test_result = context.runTest(.{ .disable_printing = true }, Test.guiFunction, Test.testFunction);
    try testing.expectError(error.TestError, test_result);
}

test "should fail the test when test function returns error" {
    const Test = struct {
        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
        }

        fn testFunction(ctx: ui.TestContext) !void {
            ctx.setRef("Window");
            return error.TestError;
        }
    };
    const context = try getTestingContext();
    const test_result = context.runTest(.{ .disable_printing = true }, Test.guiFunction, Test.testFunction);
    try testing.expectError(error.TestError, test_result);
}

test "should have a working clipboard" {
    const Test = struct {
        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            if (imgui.igButton("Button", .{})) {
                imgui.igSetClipboardText("clipboard text");
            }
        }

        fn testFunction(ctx: ui.TestContext) !void {
            try ctx.expectClipboardText("");
            ctx.setRef("Window");
            ctx.itemClick("Button", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectClipboardText("clipboard text");
        }
    };
    const context = try getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
