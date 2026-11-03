const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");

pub fn beginDialog(open: *bool, title: [:0]const u8) bool {
    if (open.* and !imgui.igIsPopupOpen_Str(title, 0)) {
        imgui.igOpenPopup_Str(title, 0);
    }
    return imgui.igBeginPopupModal(title, open, imgui.ImGuiWindowFlags_AlwaysAutoResize);
}

pub fn endDialog() void {
    imgui.igEndPopup();
}

const testing = std.testing;

test "should not draw content until dialog is open" {
    const Test = struct {
        var open = false;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            if (beginDialog(&open, "Title")) {
                defer endDialog();
                _ = imgui.igButton("Content", .{});
            }
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try ctx.expectItemNotExists("//Title/Content");

            open = true;
            ctx.yield(1);

            try testing.expectEqual(true, open);
            try ctx.expectItemExists("//Title/Content");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should close dialog when open is set to false from inside the dialog" {
    const Test = struct {
        var open = true;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            if (beginDialog(&open, "Title")) {
                defer endDialog();
                if (imgui.igButton("Close", .{})) {
                    open = false;
                }
            }
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("//Title");
            try ctx.expectItemExists("Close");

            ctx.itemClick("Close", imgui.ImGuiMouseButton_Left, 0);
            ctx.yield(3); // Test engine caches item lookups for 2 frames.

            try testing.expectEqual(false, open);
            try ctx.expectItemNotExists("//Title/Close");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should close dialog when open is set to false from outside the dialog" {
    const Test = struct {
        var open = true;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            if (beginDialog(&open, "Title")) {
                defer endDialog();
                _ = imgui.igButton("Content", .{});
            }
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try ctx.expectItemExists("//Title/Content");

            open = false;
            ctx.yield(3); // Test engine caches item lookups for 2 frames.

            try testing.expectEqual(false, open);
            try ctx.expectItemNotExists("//Title/Content");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should set open to false when dialog is closed with the title bar button" {
    const Test = struct {
        var open = true;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            if (beginDialog(&open, "Title")) {
                defer endDialog();
                _ = imgui.igButton("Content", .{});
            }
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.yield(1);
            try testing.expectEqual(true, open);

            ctx.windowClose("//Title");
            ctx.yield(3); // Test engine caches item lookups for 2 frames.

            try testing.expectEqual(false, open);
            try ctx.expectItemNotExists("//Title/Content");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should reopen dialog after it was closed" {
    const Test = struct {
        var open = true;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            if (beginDialog(&open, "Title")) {
                defer endDialog();
                if (imgui.igButton("Close", .{})) {
                    open = false;
                }
            }
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("//Title");
            ctx.itemClick("Close", imgui.ImGuiMouseButton_Left, 0);
            ctx.yield(3); // Test engine caches item lookups for 2 frames.
            try ctx.expectItemNotExists("//Title/Close");

            open = true;
            ctx.yield(1);

            try testing.expectEqual(true, open);
            try ctx.expectItemExists("//Title/Close");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
