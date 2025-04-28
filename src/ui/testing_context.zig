const std = @import("std");
const builtin = @import("builtin");
const imgui = @import("imgui");
const misc = @import("../misc/root.zig");
const ui = @import("root.zig");

threadlocal var instance: ?TestingContext = null;

pub fn getTestingContext() !(*const TestingContext) {
    if (!builtin.is_test) {
        @compileError("TestingContext is only allowed to be used in tests.");
    }
    if (instance == null) {
        instance = TestingContext.init() catch |err| {
            misc.errorContext().append("Failed to initialize UI testing context.");
            return err;
        };
    }
    return &instance.?;
}

pub const TestingContext = struct {
    engine: *imgui.ImGuiTestEngine,
    imgui_context: *imgui.ImGuiContext,

    const Self = @This();
    const Function = fn (ctx: ui.TestContext) anyerror!void;

    pub fn init() !Self {
        const engine = imgui.teCreateContext() orelse {
            misc.errorContext().new("teCreateContext returned null.");
            return error.ImguiError;
        };
        errdefer imgui.teDestroyContext(engine);

        const imgui_context = imgui.igCreateContext(null) orelse {
            misc.errorContext().new("igCreateContext returned null.");
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
            .engine = engine,
            .imgui_context = imgui_context,
        };
    }

    pub fn deinit(self: *Self) void {
        imgui.teStop(self.engine);
        imgui.igDestroyContext(self.imgui_context);
        imgui.teDestroyContext(self.engine);
    }

    pub fn runTest(
        self: *const Self,
        comptime guiFunction: *const Function,
        comptime testFunction: *const Function,
    ) !void {
        const the_test = imgui.teRegisterTest(self.engine, "", "", null, 0);
        defer imgui.teUnregisterTest(self.engine, the_test);

        const GuiFunction = struct {
            threadlocal var returned_error: ?anyerror = null;
            fn call(raw_ctx: [*c]imgui.ImGuiTestContext) callconv(.c) void {
                const ctx = ui.TestContext{ .raw = raw_ctx };
                if (guiFunction(ctx)) {
                    returned_error = null;
                } else |err| {
                    misc.errorContext().append("Failed to execute test's GUI function.");
                    misc.errorContext().logError(err);
                    returned_error = err;
                }
            }
        };
        the_test.*.GuiFunc = GuiFunction.call;

        const TestFunction = struct {
            threadlocal var returned_error: ?anyerror = null;
            fn call(raw_ctx: [*c]imgui.ImGuiTestContext) callconv(.c) void {
                const ctx = ui.TestContext{ .raw = raw_ctx };
                if (testFunction(ctx)) {
                    returned_error = null;
                } else |err| {
                    misc.errorContext().append("Failed to execute test's TEST function.");
                    misc.errorContext().logError(err);
                    returned_error = err;
                }
            }
        };
        the_test.*.TestFunc = TestFunction.call;

        imgui.teQueueTest(self.engine, the_test, 0);
        while (!imgui.teIsTestQueueEmpty(self.engine)) {
            misc.errorContext().clear();

            const imgui_io = imgui.igGetIO();
            imgui_io.*.DisplaySize = .{ .x = 1280, .y = 720 };
            imgui_io.*.DeltaTime = 1.0 / 60.00;

            imgui.igNewFrame();
            imgui.igRender();
            imgui.tePostSwap(self.engine);

            if (GuiFunction.returned_error) |err| {
                return err;
            }
            if (TestFunction.returned_error) |err| {
                return err;
            }
        }

        const status = the_test.*.Output.Status;
        if (status == imgui.ImGuiTestStatus_Success) {
            return;
        }
        if (status != imgui.ImGuiTestStatus_Error) {
            std.debug.print(
                "Expecting the UI test to end with status Success (1) or Error (4) but instead got status: {}",
                .{status},
            );
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
        return error.UiTestFailed;
    }
};

test "hello world imgui test engine 1" {
    const context = try getTestingContext();
    try context.runTest(
        struct {
            var b = false;
            fn call(ctx: ui.TestContext) !void {
                _ = ctx;
                _ = imgui.igBegin("Test Window", null, imgui.ImGuiWindowFlags_NoSavedSettings);
                imgui.igText("Hello, automation world");
                _ = imgui.igButton("Click Me", .{});
                if (imgui.igTreeNode_Str("Node")) {
                    _ = imgui.igCheckbox("Checkbox", &b);
                    imgui.igTreePop();
                }
                imgui.igEnd();
            }
        }.call,
        struct {
            fn call(ctx: ui.TestContext) !void {
                ctx.setRef("Test Window");
                ctx.itemClick("Click Me", 0, 0);
                ctx.itemOpen("Node", 0);
                ctx.itemCheck("Node/Checkbox", 0);
                ctx.itemUncheck("Node/Checkbox", 0);
            }
        }.call,
    );
}

test "hello world imgui test engine 2" {
    const context = try getTestingContext();
    try context.runTest(
        struct {
            var b = false;
            fn call(ctx: ui.TestContext) !void {
                _ = ctx;
                _ = imgui.igBegin("Test Window", null, 0);
                imgui.igText("Hello, automation world");
                _ = imgui.igButton("Click Me", .{});
                if (imgui.igTreeNode_Str("Node")) {
                    _ = imgui.igCheckbox("Checkbox", &b);
                    imgui.igTreePop();
                }
                imgui.igEnd();
            }
        }.call,
        struct {
            fn call(ctx: ui.TestContext) !void {
                ctx.setRef("Test Window");
                ctx.itemClick("Click Me", 0, 0);
                ctx.itemOpen("Node", 0);
                ctx.itemCheck("Node/Checkbox", 0);
                ctx.itemUncheck("Node/Checkbox", 0);
            }
        }.call,
    );
}
