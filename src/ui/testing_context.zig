const std = @import("std");
const builtin = @import("builtin");
const misc = @import("../misc/root.zig");
const imgui = @import("imgui");

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
    const TestFunction = fn (ctx: *imgui.ImGuiTestContext) anyerror!void;

    pub fn init() !Self {
        if (!builtin.is_test) {
            @compileError("TestingContext is only allowed to be used in tests.");
        }
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
        comptime guiFunction: *const TestFunction,
        comptime testFunction: *const TestFunction,
    ) !void {
        const the_test = imgui.teRegisterTest(self.engine, "category", "test", null, 0);
        defer imgui.teUnregisterTest(self.engine, the_test);

        the_test.*.GuiFunc = struct {
            fn call(ctx: [*c]imgui.ImGuiTestContext) callconv(.c) void {
                return guiFunction(ctx) catch |err| {
                    misc.errorContext().append("Failed to execute test's GUI function.");
                    misc.errorContext().logError(err);
                };
            }
        }.call;
        the_test.*.TestFunc = struct {
            fn call(ctx: [*c]imgui.ImGuiTestContext) callconv(.c) void {
                return testFunction(ctx) catch |err| {
                    misc.errorContext().append("Failed to execute test's TEST function.");
                    misc.errorContext().logError(err);
                };
            }
        }.call;

        imgui.teQueueTest(self.engine, the_test, 0);
        while (!imgui.teIsTestQueueEmpty(self.engine)) {
            const imgui_io = imgui.igGetIO();
            imgui_io.*.DisplaySize = .{ .x = 1280, .y = 720 };
            imgui_io.*.DeltaTime = 1.0 / 60.00;

            imgui.igNewFrame();
            imgui.igRender();
            imgui.tePostSwap(self.engine);
        }

        try std.testing.expectEqual(imgui.ImGuiTestStatus_Success, the_test.*.Output.Status);
    }
};

const testing = std.testing;

test "hello world imgui test engine 1" {
    const context = try getTestingContext();
    try context.runTest(
        struct {
            var b = false;
            fn guiFunction(ctx: *imgui.ImGuiTestContext) !void {
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
        }.guiFunction,
        struct {
            fn testFunction(ctx: *imgui.ImGuiTestContext) !void {
                imgui.ImGuiTestContext_SetRef1(ctx, path("Test Window"));
                imgui.ImGuiTestContext_ItemClick(ctx, path("Click Me"), 0, 0);
                imgui.ImGuiTestContext_ItemOpen(ctx, path("Node"), 0);
                imgui.ImGuiTestContext_ItemCheck(ctx, path("Node/Checkbox"), 0);
                imgui.ImGuiTestContext_ItemUncheck(ctx, path("Node/Checkbox"), 0);
            }
            fn path(p: [:0]const u8) imgui.ImGuiTestRef {
                return .{ .ID = 0, .Path = p };
            }
        }.testFunction,
    );
}

test "hello world imgui test engine 2" {
    const context = try getTestingContext();
    try context.runTest(
        struct {
            var b = false;
            fn guiFunction(ctx: *imgui.ImGuiTestContext) !void {
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
        }.guiFunction,
        struct {
            fn testFunction(ctx: *imgui.ImGuiTestContext) !void {
                imgui.ImGuiTestContext_SetRef1(ctx, path("Test Window"));
                imgui.ImGuiTestContext_ItemClick(ctx, path("Click Me"), 0, 0);
                imgui.ImGuiTestContext_ItemOpen(ctx, path("Node"), 0);
                imgui.ImGuiTestContext_ItemCheck(ctx, path("Node/Checkbox"), 0);
                imgui.ImGuiTestContext_ItemUncheck(ctx, path("Node/Checkbox"), 0);
            }
            fn path(p: [:0]const u8) imgui.ImGuiTestRef {
                return .{ .ID = 0, .Path = p };
            }
        }.testFunction,
    );
}
