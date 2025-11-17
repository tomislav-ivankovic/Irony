const std = @import("std");
const builtin = @import("builtin");
const build_info = @import("build_info");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");

pub const AboutWindow = struct {
    is_open: bool = false,

    const Self = @This();
    pub const name = "About";

    pub fn draw(self: *Self) void {
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
        _ = imgui.igTextLinkOpenURL(build_info.home_page, build_info.home_page);
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
        inline for (build_info.contributors) |contributor| {
            imgui.igBullet();
            drawText(contributor);
        }
        imgui.igUnindent(0);
        imgui.igPopID();

        imgui.igBullet();
        if (sdk.misc.Timestamp.fromNano(std.time.nanoTimestamp(), .local) catch null) |timestamp| {
            var buffer: [16]u8 = undefined;
            if (std.fmt.bufPrintZ(&buffer, "©2025-{}", .{timestamp.year}) catch null) |str| {
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

const testing = std.testing;

test "should not draw anything when window is closed" {
    const Test = struct {
        var window: AboutWindow = .{ .is_open = false };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw();
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try ctx.expectItemNotExists("//" ++ AboutWindow.name);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw everything when window is open" {
    const Test = struct {
        var window: AboutWindow = .{ .is_open = true };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            window.draw();
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef(AboutWindow.name);
            try ctx.expectItemExists(build_info.display_name);
            try ctx.expectItemExists("Version:");
            try ctx.expectItemExists("Version:/" ++ build_info.version);
            try ctx.expectItemExists("Compatible with game version:");
            try ctx.expectItemExists("Compatible with game version:/" ++ build_info.game_version);
            try ctx.expectItemExists("Home page:");
            {
                const size = comptime std.mem.replacementSize(u8, build_info.home_page, "/", "\\/");
                var home_page: [size]u8 = undefined;
                _ = std.mem.replace(u8, build_info.home_page, "/", "\\/", &home_page);
                try ctx.expectItemExistsFmt("Home page:/{s}", .{home_page});
            }
            try ctx.expectItemExists("Author:");
            try ctx.expectItemExists("Author:/" ++ build_info.author);
            try ctx.expectItemExists("Contributors:");
            inline for (build_info.contributors) |contributor| {
                try ctx.expectItemExists("Contributors:/" ++ contributor);
            }
            const timestamp = try sdk.misc.Timestamp.fromNano(std.time.nanoTimestamp(), .local);
            try ctx.expectItemExistsFmt("©2025-{}", .{timestamp.year});
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
