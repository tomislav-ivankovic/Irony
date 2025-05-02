const std = @import("std");
const imgui = @import("imgui");
const log = @import("../log/root.zig");
const ui = @import("../ui/root.zig");

pub fn logsWindow(comptime buffer_logger: type, open: ?*bool) void {
    if (imgui.igBegin("Logs", open, imgui.ImGuiWindowFlags_HorizontalScrollbar)) {
        const storage = imgui.igGetStateStorage();
        const is_scroll_at_bottom_id = imgui.igGetID_Str("is_scroll_at_bottom");
        const is_scroll_at_bottom = imgui.ImGuiStorage_GetBool(storage, is_scroll_at_bottom_id, true);
        {
            const entries = buffer_logger.lockAndGetEntries();
            defer buffer_logger.unlock();
            for (0..entries.len) |index| {
                const entry = entries.get(index) catch continue;
                const color = getLogColor(entry.level);
                imgui.igTextColored(color, "%s", entry.full_message.ptr);
            }
        }
        if (is_scroll_at_bottom) {
            imgui.igSetScrollHereY(1.0);
        }
        imgui.ImGuiStorage_SetBool(
            storage,
            is_scroll_at_bottom_id,
            imgui.igGetScrollY() >= imgui.igGetScrollMaxY() - 1.0,
        );
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

const testing = std.testing;

test "should render every log message in correct color" {
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
                // TODO finnish the test.
                // ctx.itemCheck("2020-01-02T03:04:05.123456789 [debug] Message: 1", 0);
                // assert that text color is getLogColor(.debug)
                // ctx.itemCheck("2020-01-02T03:04:05.123456789 [info] Message: 2", 0);
                // assert that text color is getLogColor(.info)
                // ctx.itemCheck("2020-01-02T03:04:05.123456789 [warning] Message: 3", 0);
                // assert that text color is getLogColor(.warn)
                // ctx.itemCheck("2020-01-02T03:04:05.123456789 [error] Message: 4", 0);
                // assert that text color is getLogColor(.err)
            }
        }.call,
    );
}
