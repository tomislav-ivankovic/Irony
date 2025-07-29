const std = @import("std");

const LogFunction = *const fn (
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void;

pub fn CompositeLogger(comptime log_functions: []const LogFunction) type {
    return struct {
        pub fn logFn(
            comptime level: std.log.Level,
            comptime scope: @Type(.enum_literal),
            comptime format: []const u8,
            args: anytype,
        ) void {
            inline for (log_functions) |function| {
                function(level, scope, format, args);
            }
        }
    };
}

const testing = std.testing;

test "should call every individual log function and pass all arguments" {
    const LogFunction1 = struct {
        var times_called: usize = 0;
        var last_level: ?std.log.Level = null;
        var last_format: ?[]const u8 = null;
        pub fn logFn(
            comptime level: std.log.Level,
            comptime scope: @Type(.enum_literal),
            comptime format: []const u8,
            args: anytype,
        ) void {
            times_called += 1;
            last_level = level;
            _ = scope;
            last_format = format;
            _ = args;
        }
    };
    const LogFunction2 = struct {
        var times_called: usize = 0;
        var last_level: ?std.log.Level = null;
        var last_format: ?[]const u8 = null;
        pub fn logFn(
            comptime level: std.log.Level,
            comptime scope: @Type(.enum_literal),
            comptime format: []const u8,
            args: anytype,
        ) void {
            times_called += 1;
            last_level = level;
            _ = scope;
            last_format = format;
            _ = args;
        }
    };
    const logger = CompositeLogger(&.{ LogFunction1.logFn, LogFunction2.logFn });
    try testing.expectEqual(0, LogFunction1.times_called);
    try testing.expectEqual(0, LogFunction2.times_called);
    logger.logFn(.info, .scope_1, "Message.", .{});
    try testing.expectEqual(1, LogFunction1.times_called);
    try testing.expectEqual(1, LogFunction2.times_called);
    try testing.expectEqual(.info, LogFunction1.last_level);
    try testing.expectEqual(.info, LogFunction2.last_level);
    try testing.expectEqualStrings("Message.", LogFunction1.last_format.?);
    try testing.expectEqualStrings("Message.", LogFunction2.last_format.?);
}
