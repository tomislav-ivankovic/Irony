const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");

pub fn drawMemoryUsage(bytes: usize) void {
    var buffer: [64]u8 = undefined;
    const text = switch (bytes) {
        0...999 => std.fmt.bufPrintSentinel(&buffer, "{} B", .{bytes}, 0),
        1_000...999_999 => std.fmt.bufPrintSentinel(
            &buffer,
            "{}.{d:0>2} kB",
            .{ bytes / 1_000, bytes % 1_000 / 10 },
            0,
        ),
        1_000_000...999_999_999 => std.fmt.bufPrintSentinel(
            &buffer,
            "{}.{d:0>2} MB",
            .{ bytes / 1_000_000, bytes % 1_000_000 / 10_000 },
            0,
        ),
        else => std.fmt.bufPrintSentinel(
            &buffer,
            "{}.{d:0>2} GB",
            .{ bytes / 1_000_000_000, bytes % 1_000_000_000 / 10_000_000 },
            0,
        ),
    } catch "error";

    imgui.igText("%s", text.ptr);

    var rect: imgui.ImRect = undefined;
    imgui.igGetItemRectMin(&rect.Min);
    imgui.igGetItemRectMax(&rect.Max);
    _ = imgui.igItemAdd(rect, imgui.igGetID_Str(text), null, imgui.ImGuiItemFlags_NoNav);

    if (imgui.igIsItemHovered(0)) {
        var tooltip_buffer: [64]u8 = undefined;
        const tooltip_text = std.fmt.bufPrintSentinel(&tooltip_buffer, "RAM usage:\n{} bytes", .{bytes}, 0) catch "error";
        imgui.igSetTooltip(tooltip_text);
    }

    if (imgui.igIsItemClicked(imgui.ImGuiMouseButton_Left)) {
        var clipboard_buffer: [64]u8 = undefined;
        const clipboard_text = std.fmt.bufPrintSentinel(&clipboard_buffer, "{}", .{bytes}, 0) catch "error";
        imgui.igSetClipboardText(clipboard_text);
        sdk.ui.toasts.send(.info, null, "Copied to clipboard: {s}", .{clipboard_text});
    }
}

const testing = std.testing;

test "should draw the correct memory usage text" {
    const Test = struct {
        var bytes: usize = 0;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawMemoryUsage(bytes);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");

            bytes = 0;
            ctx.yield(1);
            try ctx.expectItemExists("0 B");

            bytes = 999;
            ctx.yield(1);
            try ctx.expectItemExists("999 B");

            bytes = 1_011;
            ctx.yield(1);
            try ctx.expectItemExists("1.01 kB");

            bytes = 999_991;
            ctx.yield(1);
            try ctx.expectItemExists("999.99 kB");

            bytes = 1_011_111;
            ctx.yield(1);
            try ctx.expectItemExists("1.01 MB");

            bytes = 999_999_991;
            ctx.yield(1);
            try ctx.expectItemExists("999.99 MB");

            bytes = 1_011_111_111;
            ctx.yield(1);
            try ctx.expectItemExists("1.01 GB");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should put bytes value into clipboard when clicking text" {
    const Test = struct {
        var bytes: usize = 0;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawMemoryUsage(bytes);
            sdk.ui.toasts.draw();
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            bytes = 1011;
            ctx.yield(1);
            sdk.ui.toasts.update(100);

            ctx.itemClick("//Window/1.01 kB", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("1011");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 1011");
            sdk.ui.toasts.update(100);
        }
    };
    sdk.ui.toasts.setIo(testing.io);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
