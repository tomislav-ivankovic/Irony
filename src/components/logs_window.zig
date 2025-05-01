const std = @import("std");
const imgui = @import("imgui");

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
