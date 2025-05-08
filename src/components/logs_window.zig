const std = @import("std");
const builtin = @import("builtin");
const imgui = @import("imgui");
const log = @import("../log/root.zig");
const ui = @import("../ui/root.zig");

pub fn logsWindow(comptime buffer_logger: type, open: ?*bool) void {
    if (imgui.igBegin("Logs", open, imgui.ImGuiWindowFlags_HorizontalScrollbar)) {
        {
            const entries = buffer_logger.lockAndGetEntries();
            defer buffer_logger.unlock();
            for (0..entries.len) |index| {
                const entry = entries.get(index) catch continue;
                textColored(getLogColor(entry.level), entry.full_message);
            }
        }
        const storage = imgui.igGetStateStorage();

        const scroll_at_bottom_id = imgui.igGetID_Str("is_scroll_at_bottom");
        const scroll_y_id = imgui.igGetID_Str("scroll_y");

        const was_scroll_at_bottom = imgui.ImGuiStorage_GetBool(storage, scroll_at_bottom_id, true);
        const previous_scroll_y = imgui.ImGuiStorage_GetFloat(storage, scroll_y_id, imgui.igGetScrollY());
        const scroll_y_changed = imgui.igGetScrollY() != previous_scroll_y;

        if (was_scroll_at_bottom and !scroll_y_changed) {
            imgui.igSetScrollHereY(1.0);
        }

        const is_scroll_at_bottom = imgui.igGetScrollY() >= imgui.igGetScrollMaxY() - 1.0;
        imgui.ImGuiStorage_SetBool(storage, scroll_at_bottom_id, is_scroll_at_bottom);
        imgui.ImGuiStorage_SetFloat(storage, scroll_y_id, imgui.igGetScrollY());
    }
    imgui.igEnd();
}

fn getLogColor(log_level: std.log.Level) imgui.ImVec4 {
    return switch (log_level) {
        .err => .{ .x = 1, .y = 0.5, .z = 0.5, .w = 1 },
        .warn => .{ .x = 1, .y = 1, .z = 0, .w = 1 },
        .info => .{ .x = 0, .y = 1, .z = 1, .w = 1 },
        .debug => .{ .x = 0.7, .y = 0.7, .z = 0.7, .w = 1 },
    };
}

fn textColored(color: imgui.ImVec4, text: [:0]const u8) void {
    if (builtin.is_test) {
        var pos: imgui.ImVec2 = undefined;
        imgui.igGetCursorScreenPos(&pos);
        var size: imgui.ImVec2 = undefined;
        imgui.igCalcTextSize(&size, text, null, false, -1.0);
        const rect = imgui.ImRect{ .Min = pos, .Max = .{ .x = pos.x + size.x, .y = pos.y + size.y } };
        imgui.teItemAdd(imgui.igGetCurrentContext(), imgui.igGetID_Str(text), &rect, null);
    }
    imgui.igTextColored(color, "%s", text.ptr);
}

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

    const context = try ui.getTestingContext();
    try context.runTest(
        .{},
        struct {
            fn call(_: ui.TestContext) !void {
                logsWindow(logger, null);
            }
        }.call,
        struct {
            fn call(ctx: ui.TestContext) !void {
                ctx.setRef("Logs");
                try testing.expect(ctx.itemExists("2020-01-02T03:04:05.123456789 [debug] Message: 1"));
                try testing.expect(ctx.itemExists("2020-01-02T03:04:05.123456789 [info] Message: 2"));
                try testing.expect(ctx.itemExists("2020-01-02T03:04:05.123456789 [warning] Message: 3"));
                try testing.expect(ctx.itemExists("2020-01-02T03:04:05.123456789 [error] Message: 4"));
            }
        }.call,
    );
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

    const context = try ui.getTestingContext();
    try context.runTest(
        .{},
        struct {
            fn call(_: ui.TestContext) !void {
                logsWindow(logger, null);
            }
        }.call,
        struct {
            fn call(ctx: ui.TestContext) !void {
                try testing.expectEqual(ctx.getScrollMaxY("Logs"), ctx.getScrollY("Logs"));
                ctx.scrollToTop("Logs");
                ctx.yield(1);
                try testing.expectEqual(0, ctx.getScrollY("Logs"));
            }
        }.call,
    );
}
