const std = @import("std");
const build_info = @import("build_info");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");

pub const VersionInfoConfig = struct {
    openLink: *const fn (url: [:0]const u8) error{OpenLinkError}!void = openLink,
};

pub const LatestVersion = union(enum) {
    available: sdk.misc.Version,
    loading: void,
    err: void,
};

pub fn drawVersionInfo(latest_version: LatestVersion, comptime config: VersionInfoConfig) void {
    const current = sdk.misc.Version.current;
    var tool_tip_buffer: [512]u8 = undefined;
    const tool_tip, const text_color = switch (latest_version) {
        .available => |latest| switch (sdk.misc.Version.order(current, latest)) {
            .gt => .{
                std.fmt.bufPrintSentinel(
                    &tool_tip_buffer,
                    \\Using a unreleased version: {f}
                    \\Latest released version is: {f}
                    \\Are you a developer?
                ,
                    .{ current, latest },
                    0,
                ) catch "error",
                imgui.ImVec4{ .x = 0.5, .y = 1, .z = 0.5, .w = 1 },
            },
            .eq => .{
                "Using the latest released version.",
                imgui.ImVec4{ .x = 0.5, .y = 1, .z = 0.5, .w = 1 },
            },
            .lt => .{
                std.fmt.bufPrintSentinel(
                    &tool_tip_buffer,
                    \\Using outdated version: {f}
                    \\Latest released version is: {f}
                    \\Right-click to open the download page for the latest version.
                ,
                    .{ current, latest },
                    0,
                ) catch "error",
                imgui.ImVec4{ .x = 1, .y = 0.5, .z = 0.5, .w = 1 },
            },
        },
        .loading => .{
            "Fetching the latest version number...",
            imgui.ImVec4{ .x = 1, .y = 1, .z = 1, .w = 1 },
        },
        .err => .{
            \\Failed to fetch the latest version number.
            \\Right-click to open the download page for the latest version.
            ,
            imgui.ImVec4{ .x = 1, .y = 1, .z = 0, .w = 1 },
        },
    };

    const current_version: [:0]const u8 = build_info.version;
    const text = "v" ++ current_version;
    imgui.igTextColored(text_color, "%s", text);

    var rect: imgui.ImRect = undefined;
    imgui.igGetItemRectMin(&rect.Min);
    imgui.igGetItemRectMax(&rect.Max);
    _ = imgui.igItemAdd(rect, imgui.igGetID_Str(text), null, imgui.ImGuiItemFlags_NoNav);

    if (imgui.igIsItemHovered(0)) {
        imgui.igSetTooltip(tool_tip);
    }

    if (imgui.igIsItemClicked(imgui.ImGuiMouseButton_Left)) {
        imgui.igSetClipboardText(current_version);
        sdk.ui.toasts.send(.info, null, "Copied to clipboard: {s}", .{current_version});
    }

    if (imgui.igIsItemClicked(imgui.ImGuiMouseButton_Right)) {
        const link = build_info.latest_version_download_page;
        if (config.openLink(link)) {
            sdk.ui.toasts.send(
                .info,
                null,
                "The download page for the latest version has been opened in the browser.",
                .{},
            );
        } else |err| {
            sdk.misc.error_context.append("Failed to open link: {s}", .{link});
            sdk.misc.error_context.logError(err);
        }
    }
}

fn openLink(url: [:0]const u8) !void {
    const open = imgui.igGetPlatformIO_Nil().*.Platform_OpenInShellFn orelse {
        sdk.misc.error_context.new("Platform_OpenInShellFn is null.", .{});
        return error.OpenLinkError;
    };
    const success = open(imgui.igGetCurrentContext(), url);
    if (!success) {
        sdk.misc.error_context.new("Platform_OpenInShellFn returned false.", .{});
        return error.OpenLinkError;
    }
}

const testing = std.testing;

test "should draw current version number text" {
    const Test = struct {
        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawVersionInfo(.loading, .{});
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try ctx.expectItemExists("v" ++ build_info.version);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should put current version number into clipboard when left-clicking text" {
    const Test = struct {
        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawVersionInfo(.loading, .{});
            sdk.ui.toasts.draw();
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            sdk.ui.toasts.update(100);
            ctx.itemClick(
                "//Window/v" ++ build_info.version,
                imgui.ImGuiMouseButton_Left,
                imgui.ImGuiTestOpFlags_NoCheckHoveredId,
            );
            try ctx.expectClipboardText(build_info.version);
            try ctx.expectItemExists("//toast-0/Copied to clipboard: " ++ build_info.version);
            sdk.ui.toasts.update(100);
        }
    };
    sdk.ui.toasts.setIo(std.testing.io);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should open latest version download page when right-clicking text" {
    const OpenLink = struct {
        var times_called: usize = 0;
        var last_url: ?[:0]const u8 = null;
        fn call(url: [:0]const u8) error{OpenLinkError}!void {
            times_called += 1;
            last_url = url;
        }
    };
    const Test = struct {
        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawVersionInfo(.loading, .{ .openLink = OpenLink.call });
            sdk.ui.toasts.draw();
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            sdk.ui.toasts.update(100);

            try testing.expectEqual(0, OpenLink.times_called);
            ctx.itemClick(
                "//Window/v" ++ build_info.version,
                imgui.ImGuiMouseButton_Right,
                imgui.ImGuiTestOpFlags_NoCheckHoveredId,
            );
            try testing.expectEqual(1, OpenLink.times_called);
            try testing.expect(OpenLink.last_url != null);
            try testing.expectEqualStrings(build_info.latest_version_download_page, OpenLink.last_url.?);
            try ctx.expectItemExists(
                "//toast-0/The download page for the latest version has been opened in the browser.",
            );
            sdk.ui.toasts.update(100);
        }
    };
    sdk.ui.toasts.setIo(std.testing.io);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
