const std = @import("std");
const builtin = @import("builtin");
const imgui = @import("imgui");
const log = @import("../log/root.zig");
const ui = @import("../ui/root.zig");

pub const LogsWindow = struct {
    is_open: bool = false,
    is_scroll_at_bottom: bool = true,
    scroll_y: f32 = 0.0,

    const Self = @This();
    pub const name = "Logs";

    pub fn draw(self: *Self, comptime buffer_logger: type) void {
        if (!self.is_open) {
            return;
        }

        const render_content = imgui.igBegin(name, &self.is_open, imgui.ImGuiWindowFlags_HorizontalScrollbar);
        defer imgui.igEnd();
        if (!render_content) {
            return;
        }

        {
            const entries = buffer_logger.lockAndGetEntries();
            defer buffer_logger.unlock();
            for (0..entries.len) |index| {
                const entry = entries.get(index) catch unreachable;
                drawColoredText(getLogColor(entry.level), entry.full_message);
            }
        }

        const was_scroll_at_bottom = self.is_scroll_at_bottom;
        const did_scroll_y_change = imgui.igGetScrollY() != self.scroll_y;
        if (was_scroll_at_bottom and !did_scroll_y_change) {
            imgui.igSetScrollHereY(1.0);
        }
        self.is_scroll_at_bottom = imgui.igGetScrollY() >= imgui.igGetScrollMaxY() - 1.0;
        self.scroll_y = imgui.igGetScrollY();
    }

    fn getLogColor(log_level: std.log.Level) imgui.ImVec4 {
        return switch (log_level) {
            .err => .{ .x = 1, .y = 0.5, .z = 0.5, .w = 1 },
            .warn => .{ .x = 1, .y = 1, .z = 0, .w = 1 },
            .info => .{ .x = 0, .y = 1, .z = 1, .w = 1 },
            .debug => .{ .x = 0.7, .y = 0.7, .z = 0.7, .w = 1 },
        };
    }

    fn drawColoredText(color: imgui.ImVec4, text: [:0]const u8) void {
        imgui.igTextColored(color, "%s", text.ptr);
        if (builtin.is_test) {
            var min: imgui.ImVec2 = undefined;
            var max: imgui.ImVec2 = undefined;
            imgui.igGetItemRectMin(&min);
            imgui.igGetItemRectMax(&max);
            const rect = imgui.ImRect{ .Min = min, .Max = max };
            imgui.teItemAdd(imgui.igGetCurrentContext(), imgui.igGetID_Str(text), &rect, null);
        }
    }
};

const testing = std.testing;

test "should render every log message" {
    const nanoTimestamp = struct {
        fn call() i128 {
            return 1577934245123456789;
        }
    }.call;
    const logger = log.BufferLogger(.{
        .level = .debug,
        .time_zone = .utc,
        .buffer_size = 4096,
        .max_entries = 64,
        .nanoTimestamp = nanoTimestamp,
    });

    logger.logFn(.debug, std.log.default_log_scope, "Message: 1", .{});
    logger.logFn(.info, std.log.default_log_scope, "Message: 2", .{});
    logger.logFn(.warn, std.log.default_log_scope, "Message: 3", .{});
    logger.logFn(.err, std.log.default_log_scope, "Message: 4", .{});

    const Test = struct {
        var window = LogsWindow{ .is_open = true };

        fn guiFunction(_: ui.TestContext) !void {
            window.draw(logger);
        }

        fn testFunction(ctx: ui.TestContext) !void {
            ctx.setRef("Logs");
            try ctx.expectItemExists("2020-01-02T03:04:05.123456789 [debug] Message: 1");
            try ctx.expectItemExists("2020-01-02T03:04:05.123456789 [info] Message: 2");
            try ctx.expectItemExists("2020-01-02T03:04:05.123456789 [warning] Message: 3");
            try ctx.expectItemExists("2020-01-02T03:04:05.123456789 [error] Message: 4");
        }
    };
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should scroll to the bottom by default and still be able to scroll up" {
    const nanoTimestamp = struct {
        fn call() i128 {
            return 1577934245123456789;
        }
    }.call;
    const logger = log.BufferLogger(.{
        .level = .info,
        .time_zone = .utc,
        .buffer_size = 4096,
        .max_entries = 64,
        .nanoTimestamp = nanoTimestamp,
    });

    for (0..64) |i| {
        logger.logFn(.info, std.log.default_log_scope, "Message: {}", .{i});
    }

    const Test = struct {
        var window = LogsWindow{ .is_open = true };

        fn guiFunction(_: ui.TestContext) !void {
            window.draw(logger);
        }

        fn testFunction(ctx: ui.TestContext) !void {
            try testing.expectEqual(ctx.getScrollMaxY("Logs"), ctx.getScrollY("Logs"));
            ctx.scrollToTop("Logs");
            ctx.yield(1);
            try testing.expectEqual(0, ctx.getScrollY("Logs"));
        }
    };
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
