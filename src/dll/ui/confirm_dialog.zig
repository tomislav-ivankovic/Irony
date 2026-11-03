const std = @import("std");
const builtin = @import("builtin");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");

pub const ConfirmDialogAction = enum { none, confirm, abort };

pub fn drawConfirmDialog(
    open: *bool,
    title: [:0]const u8,
    description: [:0]const u8,
    confirm_label: [:0]const u8,
    abort_label: [:0]const u8,
) ConfirmDialogAction {
    const was_open = open.*;
    if (open.* and !imgui.igIsPopupOpen_Str(title, 0)) {
        imgui.igOpenPopup_Str(title, 0);
    }
    if (!imgui.igBeginPopupModal(title, open, imgui.ImGuiWindowFlags_AlwaysAutoResize)) {
        if (was_open and !open.*) {
            return .abort; // Closed by the title bar X button.
        } else {
            return .none;
        }
    }
    defer imgui.igEndPopup();

    drawText(description);
    imgui.igSeparator();
    var action = ConfirmDialogAction.none;
    if (imgui.igButton(confirm_label, .{})) {
        action = .confirm;
    }
    imgui.igSameLine(0, -1);
    imgui.igSetItemDefaultFocus();
    if (imgui.igButton(abort_label, .{})) {
        action = .abort;
    }
    switch (action) {
        .none => {},
        .confirm, .abort => {
            imgui.igCloseCurrentPopup();
            open.* = false;
        },
    }
    return action;
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

const testing = std.testing;

test "should not draw content until dialog is open" {
    const Test = struct {
        var open = false;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            _ = drawConfirmDialog(&open, "Title", "Description", "Confirm", "Abort");
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try ctx.expectItemNotExists("//Title/Description");
            try ctx.expectItemNotExists("//Title/Confirm");
            try ctx.expectItemNotExists("//Title/Abort");

            open = true;
            ctx.yield(1);

            try ctx.expectItemExists("//Title/Description");
            try ctx.expectItemExists("//Title/Confirm");
            try ctx.expectItemExists("//Title/Abort");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should return confirm and close when confirm button is clicked" {
    const Test = struct {
        var open = true;
        var confirm_count: usize = 0;
        var abort_count: usize = 0;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            switch (drawConfirmDialog(&open, "Title", "Description", "Confirm", "Abort")) {
                .none => {},
                .confirm => confirm_count += 1,
                .abort => abort_count += 1,
            }
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("//Title");
            ctx.yield(1);

            try testing.expectEqual(true, open);
            try testing.expectEqual(0, confirm_count);
            try testing.expectEqual(0, abort_count);

            ctx.itemClick("Confirm", imgui.ImGuiMouseButton_Left, 0);

            try testing.expectEqual(false, open);
            try testing.expectEqual(1, confirm_count);
            try testing.expectEqual(0, abort_count);

            ctx.yield(1);

            try testing.expectEqual(false, open);
            try testing.expectEqual(1, confirm_count);
            try testing.expectEqual(0, abort_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should return abort and close when abort button is clicked" {
    const Test = struct {
        var open = true;
        var confirm_count: usize = 0;
        var abort_count: usize = 0;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            switch (drawConfirmDialog(&open, "Title", "Description", "Confirm", "Abort")) {
                .none => {},
                .confirm => confirm_count += 1,
                .abort => abort_count += 1,
            }
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("//Title");
            ctx.yield(1);

            try testing.expectEqual(true, open);
            try testing.expectEqual(0, confirm_count);
            try testing.expectEqual(0, abort_count);

            ctx.itemClick("Abort", imgui.ImGuiMouseButton_Left, 0);

            try testing.expectEqual(false, open);
            try testing.expectEqual(0, confirm_count);
            try testing.expectEqual(1, abort_count);

            ctx.yield(1);

            try testing.expectEqual(false, open);
            try testing.expectEqual(0, confirm_count);
            try testing.expectEqual(1, abort_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should return abort once and close when window is closed" {
    const Test = struct {
        var open = true;
        var confirm_count: usize = 0;
        var abort_count: usize = 0;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            switch (drawConfirmDialog(&open, "Title", "Description", "Confirm", "Abort")) {
                .none => {},
                .confirm => confirm_count += 1,
                .abort => abort_count += 1,
            }
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("//Title");
            ctx.yield(1);

            try testing.expectEqual(true, open);
            try testing.expectEqual(0, confirm_count);
            try testing.expectEqual(0, abort_count);

            ctx.windowClose("//Title");

            try testing.expectEqual(false, open);
            try testing.expectEqual(0, confirm_count);
            try testing.expectEqual(1, abort_count);

            ctx.yield(1);

            try testing.expectEqual(false, open);
            try testing.expectEqual(0, confirm_count);
            try testing.expectEqual(1, abort_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should close dialog without returning action when open is set to false externally" {
    const Test = struct {
        var open = true;
        var confirm_count: usize = 0;
        var abort_count: usize = 0;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            switch (drawConfirmDialog(&open, "Title", "Description", "Confirm", "Abort")) {
                .none => {},
                .confirm => confirm_count += 1,
                .abort => abort_count += 1,
            }
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try ctx.expectItemExists("//Title/Description");
            try ctx.expectItemExists("//Title/Confirm");
            try ctx.expectItemExists("//Title/Abort");
            try testing.expectEqual(0, confirm_count);
            try testing.expectEqual(0, abort_count);

            open = false;
            ctx.yield(3); // Test engine caches item lookups for 2 frames.

            try ctx.expectItemNotExists("//Title/Description");
            try ctx.expectItemNotExists("//Title/Confirm");
            try ctx.expectItemNotExists("//Title/Abort");
            try testing.expectEqual(0, confirm_count);
            try testing.expectEqual(0, abort_count);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
