const std = @import("std");
const log = @import("root.zig");

pub const LogFunction = *const fn (message: *const log.Message) void;

pub fn CompositeLogger(comptime log_functions: []const LogFunction) type {
    return struct {
        pub fn logFn(
            comptime level: std.log.Level,
            comptime scope: @EnumLiteral(),
            comptime format: []const u8,
            args: anytype,
        ) void {
            logMessage(&.fromParams(level, scope, format, &args));
        }

        pub fn logMessage(message: *const log.Message) void {
            inline for (log_functions) |function| {
                function(message);
            }
        }
    };
}

const testing = std.testing;

test "should call every individual log function and pass the message" {
    const LogFunction1 = struct {
        var times_called: usize = 0;
        var last_level: ?std.log.Level = null;
        var last_scope: ?[]const u8 = null;
        var last_text_buffer: [64]u8 = undefined;
        var last_text: ?[]const u8 = null;
        pub fn logMessage(message: *const log.Message) void {
            times_called += 1;
            last_level = message.level;
            last_scope = message.scope;
            last_text = std.fmt.bufPrint(&last_text_buffer, "{f}", .{message}) catch @panic("Buffer too small.");
        }
    };
    const LogFunction2 = struct {
        var times_called: usize = 0;
        var last_level: ?std.log.Level = null;
        var last_scope: ?[]const u8 = null;
        var last_text_buffer: [64]u8 = undefined;
        var last_text: ?[]const u8 = null;
        pub fn logMessage(message: *const log.Message) void {
            times_called += 1;
            last_level = message.level;
            last_scope = message.scope;
            last_text = std.fmt.bufPrint(&last_text_buffer, "{f}", .{message}) catch @panic("Buffer too small.");
        }
    };
    const logger = CompositeLogger(&.{ LogFunction1.logMessage, LogFunction2.logMessage });
    try testing.expectEqual(0, LogFunction1.times_called);
    try testing.expectEqual(0, LogFunction2.times_called);
    logger.logFn(.info, .scope_1, "Message: {}", .{123});
    try testing.expectEqual(1, LogFunction1.times_called);
    try testing.expectEqual(1, LogFunction2.times_called);
    try testing.expectEqual(.info, LogFunction1.last_level);
    try testing.expectEqual(.info, LogFunction2.last_level);
    try testing.expectEqualStrings("scope_1", LogFunction1.last_scope orelse return error.ScopeIsNull);
    try testing.expectEqualStrings("scope_1", LogFunction2.last_scope orelse return error.ScopeIsNull);
    try testing.expectEqualStrings("Message: 123", LogFunction1.last_text orelse return error.TextIsNull);
    try testing.expectEqualStrings("Message: 123", LogFunction2.last_text orelse return error.TextIsNull);
}
