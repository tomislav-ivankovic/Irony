const std = @import("std");
const builtin = @import("builtin");
const build_info = @import("build_info");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");

pub const AboutWindowConfig = struct {
    openLink: *const fn (url: [:0]const u8) error{OpenLinkError}!void = openLink,
};

pub fn AboutWindow(comptime config: AboutWindowConfig) type {
    return struct {
        is_open: bool = false,

        const Self = @This();
        pub const name = "About";

        pub fn draw(self: *Self, io: std.Io) void {
            if (!self.is_open) {
                return;
            }

            const display_size = imgui.igGetIO_Nil().*.DisplaySize;
            imgui.igSetNextWindowPos(
                .{ .x = 0.5 * display_size.x, .y = 0.5 * display_size.y },
                imgui.ImGuiCond_FirstUseEver,
                .{ .x = 0.5, .y = 0.5 },
            );
            imgui.igSetNextWindowSize(.{ .x = 420, .y = 360 }, imgui.ImGuiCond_FirstUseEver);

            const render_content = imgui.igBegin(name, &self.is_open, imgui.ImGuiWindowFlags_HorizontalScrollbar);
            defer imgui.igEnd();
            if (!render_content) {
                return;
            }

            drawText(build_info.display_name);

            imgui.igBullet();
            drawText("Version:");
            imgui.igPushID_Str("Version:");
            imgui.igSameLine(0, -1);
            drawText(build_info.version);
            imgui.igPopID();

            imgui.igBullet();
            drawText("Compatible with game version:");
            imgui.igPushID_Str("Compatible with game version:");
            imgui.igSameLine(0, -1);
            drawText(build_info.game_version);
            imgui.igPopID();

            imgui.igBullet();
            drawText("Home page:");
            imgui.igPushID_Str("Home page:");
            imgui.igSameLine(0, -1);
            if (imgui.igTextLink(build_info.home_page)) {
                const link = build_info.home_page;
                if (config.openLink(link)) {
                    sdk.ui.toasts.send(.info, null, "The home page has been opened in the browser.", .{});
                } else |err| {
                    sdk.misc.error_context.append("Failed to open link: {s}", .{link});
                    sdk.misc.error_context.logError(err);
                }
            }
            imgui.igPopID();

            imgui.igBullet();
            drawText("Author:");
            imgui.igPushID_Str("Author:");
            imgui.igIndent(0);
            imgui.igBullet();
            drawText(build_info.author);
            imgui.igUnindent(0);
            imgui.igPopID();

            imgui.igBullet();
            drawText("Contributors:");
            imgui.igPushID_Str("Contributors:");
            imgui.igIndent(0);
            for (build_info.contributors) |contributor| {
                imgui.igBullet();
                drawText(contributor);
            }
            imgui.igUnindent(0);
            imgui.igPopID();

            imgui.igBullet();
            drawText("Donate:");
            imgui.igPushID_Str("Donate:");
            imgui.igIndent(0);
            imgui.igBullet();
            if (imgui.igTextLink("One Time Donation")) {
                const link = build_info.donation_links.one_time;
                if (config.openLink(link)) {
                    sdk.ui.toasts.send(.info, null, "The donation page has been opened in the browser.", .{});
                } else |err| {
                    sdk.misc.error_context.append("Failed to open link: {s}", .{link});
                    sdk.misc.error_context.logError(err);
                }
            }
            imgui.igBullet();
            if (imgui.igTextLink("Recurring Donation")) {
                const link = build_info.donation_links.recurring;
                if (config.openLink(link)) {
                    sdk.ui.toasts.send(.info, null, "The donation page has been opened in the browser.", .{});
                } else |err| {
                    sdk.misc.error_context.append("Failed to open link: {s}", .{link});
                    sdk.misc.error_context.logError(err);
                }
            }
            imgui.igUnindent(0);
            imgui.igPopID();

            imgui.igBullet();
            const nano_time = std.Io.Clock.real.now(io).nanoseconds;
            if (sdk.misc.Timestamp.fromNano(nano_time, .local) catch null) |timestamp| {
                var buffer: [16]u8 = undefined;
                if (std.fmt.bufPrintSentinel(&buffer, "©2025-{}", .{timestamp.year}, 0) catch null) |str| {
                    drawText(str);
                } else {
                    drawText("©2025");
                }
            } else {
                drawText("©2025");
            }
        }

        fn drawText(text: [:0]const u8) void {
            imgui.igText("%s", text.ptr);
            if (builtin.is_test) {
                var rect: imgui.ImRect = undefined;
                imgui.igGetItemRectMin(&rect.Min);
                imgui.igGetItemRectMax(&rect.Max);
                imgui.teItemAdd(imgui.igGetCurrentContext(), imgui.igGetID_Str(text), &rect, null);
            }
        }
    };
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

test "should not draw anything when window is closed" {
    const Test = struct {
        const Window = AboutWindow(.{});
        var window: Window = .{ .is_open = false };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(testing.io);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try ctx.expectItemNotExists("//" ++ Window.name);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw everything when window is open" {
    const Test = struct {
        const Window = AboutWindow(.{});
        var window: Window = .{ .is_open = true };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(testing.io);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef(Window.name);
            try ctx.expectItemExists(build_info.display_name);
            try ctx.expectItemExists("Version:");
            try ctx.expectItemExists("Version:/" ++ build_info.version);
            try ctx.expectItemExists("Compatible with game version:");
            try ctx.expectItemExists("Compatible with game version:/" ++ build_info.game_version);
            try ctx.expectItemExists("Home page:");
            const home_page_id = comptime block: {
                const size = std.mem.replacementSize(u8, build_info.home_page, "/", "\\/");
                var buffer: [size]u8 = undefined;
                _ = std.mem.replace(u8, build_info.home_page, "/", "\\/", &buffer);
                break :block buffer;
            };
            try ctx.expectItemExists("Home page:/" ++ home_page_id);
            try ctx.expectItemExists("Author:");
            try ctx.expectItemExists("Author:/" ++ build_info.author);
            try ctx.expectItemExists("Contributors:");
            for (build_info.contributors) |contributor| {
                try ctx.expectItemExistsFmt("Contributors:/{s}", .{contributor});
            }
            try ctx.expectItemExists("Donate:");
            try ctx.expectItemExists("Donate:/One Time Donation");
            try ctx.expectItemExists("Donate:/Recurring Donation");
            const nano_time = std.Io.Clock.real.now(testing.io).nanoseconds;
            const timestamp = try sdk.misc.Timestamp.fromNano(nano_time, .local);
            try ctx.expectItemExistsFmt("©2025-{}", .{timestamp.year});
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should open correct links when they are clicked" {
    const OpenLink = struct {
        var times_called: usize = 0;
        var last_url: ?[:0]const u8 = null;
        fn call(url: [:0]const u8) error{OpenLinkError}!void {
            times_called += 1;
            last_url = url;
        }
    };
    const Test = struct {
        const Window = AboutWindow(.{ .openLink = OpenLink.call });
        var window: Window = .{ .is_open = true };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw(testing.io);
            sdk.ui.toasts.draw();
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef(Window.name);
            sdk.ui.toasts.update(100);
            try testing.expectEqual(0, OpenLink.times_called);

            const home_page_id = comptime block: {
                const size = std.mem.replacementSize(u8, build_info.home_page, "/", "\\/");
                var buffer: [size]u8 = undefined;
                _ = std.mem.replace(u8, build_info.home_page, "/", "\\/", &buffer);
                break :block buffer;
            };
            ctx.itemClick("Home page:/" ++ home_page_id, imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(1, OpenLink.times_called);
            try testing.expect(OpenLink.last_url != null);
            try testing.expectEqualStrings(build_info.home_page, OpenLink.last_url.?);
            try ctx.expectItemExists("//toast-0/The home page has been opened in the browser.");
            sdk.ui.toasts.update(100);

            ctx.itemClick("Donate:/One Time Donation", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(2, OpenLink.times_called);
            try testing.expect(OpenLink.last_url != null);
            try testing.expectEqualStrings(build_info.donation_links.one_time, OpenLink.last_url.?);
            try ctx.expectItemExists("//toast-0/The donation page has been opened in the browser.");
            sdk.ui.toasts.update(100);

            ctx.itemClick("Donate:/Recurring Donation", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(3, OpenLink.times_called);
            try testing.expect(OpenLink.last_url != null);
            try testing.expectEqualStrings(build_info.donation_links.recurring, OpenLink.last_url.?);
            try ctx.expectItemExists("//toast-0/The donation page has been opened in the browser.");
        }
    };
    sdk.ui.toasts.setIo(testing.io);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
