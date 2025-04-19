const std = @import("std");
const misc = @import("../misc/root.zig");

pub const BufferLoggerConfig = struct {
    level: std.log.Level = .debug,
    time_zone: misc.TimeZone = .local,
    buffer_size: usize = 4096,
    max_entries: usize = 64,
    nanoTimestamp: *const fn () i128 = std.time.nanoTimestamp,
};

pub const LogEntry = struct {
    timestamp: i128,
    timestamp_str: []const u8,
    level: std.log.Level,
    scope: ?[]const u8,
    message: [:0]const u8,
    full_message: [:0]const u8,
    buffer_region: []const u8,
};

pub fn BufferLogger(comptime config: BufferLoggerConfig) type {
    return struct {
        var buffer: [config.buffer_size]u8 = undefined;
        var entries = misc.CircularBuffer(config.max_entries, LogEntry){};

        pub fn getEntry(index: usize) !LogEntry {
            return try entries.get(index);
        }

        pub fn getLen() usize {
            return entries.len;
        }

        pub fn logFn(
            comptime level: std.log.Level,
            comptime scope: @Type(.enum_literal),
            comptime format: []const u8,
            args: anytype,
        ) void {
            if (@intFromEnum(level) > @intFromEnum(config.level)) {
                return;
            }
            const last_entry = entries.getLast() catch {
                log(&buffer, level, scope, format, args) catch return;
                return;
            };
            const last_buffer_region = last_entry.buffer_region;
            const start_index = (&last_buffer_region[0] - &buffer[0]) + last_buffer_region.len;
            log(buffer[start_index..], level, scope, format, args) catch {
                log(&buffer, level, scope, format, args) catch return;
            };
        }

        fn log(
            write_region: []u8,
            comptime level: std.log.Level,
            comptime scope: @Type(.enum_literal),
            comptime format: []const u8,
            args: anytype,
        ) !void {
            var stream = std.io.fixedBufferStream(write_region);

            const timestamp = config.nanoTimestamp();
            const timestamp_struct = misc.Timestamp.fromNano(timestamp, config.time_zone) catch null;
            stream.writer().print("{?} ", .{timestamp_struct}) catch |err| {
                clearBufferRegion(write_region);
                return err;
            };
            const timestamp_str = write_region[0..(stream.pos - 1)];

            stream.writer().writeAll("[" ++ comptime level.asText() ++ "] ") catch |err| {
                clearBufferRegion(write_region);
                return err;
            };

            const scope_str = if (scope != std.log.default_log_scope) block: {
                const start_pos = stream.pos + 1;
                stream.writer().writeAll("(" ++ @tagName(scope) ++ ") ") catch |err| {
                    clearBufferRegion(write_region);
                    return err;
                };
                const end_pos = stream.pos - 2;
                break :block write_region[start_pos..end_pos];
            } else null;

            const message_start_pos = stream.pos;
            stream.writer().print(format ++ .{0}, args) catch |err| {
                clearBufferRegion(write_region);
                return err;
            };
            const end_pos = stream.pos;

            const entry = LogEntry{
                .timestamp = timestamp,
                .timestamp_str = timestamp_str,
                .level = level,
                .scope = scope_str,
                .message = write_region[message_start_pos..(end_pos - 1) :0],
                .full_message = write_region[0..(end_pos - 1) :0],
                .buffer_region = write_region[0..end_pos],
            };
            clearBufferRegion(entry.buffer_region);
            _ = entries.addToBack(entry);
        }

        fn clearBufferRegion(region: []const u8) void {
            while (entries.getFirst() catch null) |entry| {
                if (!colides(entry.buffer_region, region)) {
                    break;
                }
                _ = entries.removeFirst() catch unreachable;
            }
        }

        fn colides(a: []const u8, b: []const u8) bool {
            if (a.len == 0 or b.len == 0) {
                return false;
            }
            const a_min = @intFromPtr(&a[0]);
            const a_max = @intFromPtr(&a[a.len - 1]);
            const b_min = @intFromPtr(&b[0]);
            const b_max = @intFromPtr(&b[b.len - 1]);
            return (a_max >= b_min) and (b_max >= a_min);
        }
    };
}

const testing = std.testing;

test "should set correct values to entry fields" {
    const nanoTimestamp = struct {
        fn call() i128 {
            return 1577934245123456789;
        }
    }.call;

    const logger = BufferLogger(.{
        .level = .debug,
        .time_zone = .utc,
        .buffer_size = 4096,
        .max_entries = 64,
        .nanoTimestamp = nanoTimestamp,
    });

    logger.logFn(.debug, std.log.default_log_scope, "Message: {}", .{1});
    logger.logFn(.info, .scope_1, "Message: {}", .{2});
    logger.logFn(.warn, .scope_2, "Message: {}", .{3});
    logger.logFn(.err, .scope_3, "Message: {}", .{4});

    try testing.expectEqual(4, logger.getLen());

    const entry_1 = try logger.getEntry(0);
    try testing.expectEqual(1577934245123456789, entry_1.timestamp);
    try testing.expectEqualStrings("2020-01-02T03:04:05.123456789", entry_1.timestamp_str);
    try testing.expectEqual(.debug, entry_1.level);
    try testing.expectEqual(null, entry_1.scope);
    try testing.expectEqualStrings("Message: 1", entry_1.message);
    try testing.expectEqualStrings("2020-01-02T03:04:05.123456789 [debug] Message: 1", entry_1.full_message);
    try testing.expectEqual(0, entry_1.message[entry_1.message.len]);
    try testing.expectEqual(0, entry_1.full_message[entry_1.full_message.len]);

    const entry_2 = try logger.getEntry(1);
    try testing.expectEqual(1577934245123456789, entry_2.timestamp);
    try testing.expectEqualStrings("2020-01-02T03:04:05.123456789", entry_2.timestamp_str);
    try testing.expectEqual(.info, entry_2.level);
    try testing.expectEqualStrings("scope_1", entry_2.scope orelse @panic("entry_2.scope is null"));
    try testing.expectEqualStrings("Message: 2", entry_2.message);
    try testing.expectEqualStrings("2020-01-02T03:04:05.123456789 [info] (scope_1) Message: 2", entry_2.full_message);
    try testing.expectEqual(0, entry_2.message[entry_2.message.len]);
    try testing.expectEqual(0, entry_2.full_message[entry_2.full_message.len]);

    const entry_3 = try logger.getEntry(2);
    try testing.expectEqual(1577934245123456789, entry_3.timestamp);
    try testing.expectEqualStrings("2020-01-02T03:04:05.123456789", entry_3.timestamp_str);
    try testing.expectEqual(.warn, entry_3.level);
    try testing.expectEqualStrings("scope_2", entry_3.scope orelse @panic("entry_2.scope is null"));
    try testing.expectEqualStrings("Message: 3", entry_3.message);
    try testing.expectEqualStrings("2020-01-02T03:04:05.123456789 [warning] (scope_2) Message: 3", entry_3.full_message);
    try testing.expectEqual(0, entry_3.message[entry_3.message.len]);
    try testing.expectEqual(0, entry_3.full_message[entry_3.full_message.len]);

    const entry_4 = try logger.getEntry(3);
    try testing.expectEqual(1577934245123456789, entry_4.timestamp);
    try testing.expectEqualStrings("2020-01-02T03:04:05.123456789", entry_4.timestamp_str);
    try testing.expectEqual(.err, entry_4.level);
    try testing.expectEqualStrings("scope_3", entry_4.scope orelse @panic("entry_4.scope is null"));
    try testing.expectEqualStrings("Message: 4", entry_4.message);
    try testing.expectEqualStrings("2020-01-02T03:04:05.123456789 [error] (scope_3) Message: 4", entry_4.full_message);
    try testing.expectEqual(0, entry_4.message[entry_4.message.len]);
    try testing.expectEqual(0, entry_4.full_message[entry_4.full_message.len]);
}

test "should filter based on log level correctly" {
    const nanoTimestamp = struct {
        fn call() i128 {
            return 1577934245123456789;
        }
    }.call;

    const logger = BufferLogger(.{
        .level = .warn,
        .time_zone = .utc,
        .buffer_size = 4096,
        .max_entries = 64,
        .nanoTimestamp = nanoTimestamp,
    });

    logger.logFn(.debug, std.log.default_log_scope, "Message: 1", .{});
    logger.logFn(.info, std.log.default_log_scope, "Message: 2", .{});
    logger.logFn(.warn, std.log.default_log_scope, "Message: 3", .{});
    logger.logFn(.err, std.log.default_log_scope, "Message: 4", .{});

    try testing.expectEqual(2, logger.getLen());
    try testing.expectEqualStrings(
        "2020-01-02T03:04:05.123456789 [warning] Message: 3",
        (try logger.getEntry(0)).full_message,
    );
    try testing.expectEqualStrings(
        "2020-01-02T03:04:05.123456789 [error] Message: 4",
        (try logger.getEntry(1)).full_message,
    );
}

test "should discard earliest entries when exceeding max entries" {
    const nanoTimestamp = struct {
        fn call() i128 {
            return 1577934245123456789;
        }
    }.call;

    const logger = BufferLogger(.{
        .level = .debug,
        .time_zone = .utc,
        .buffer_size = 4096,
        .max_entries = 2,
        .nanoTimestamp = nanoTimestamp,
    });

    logger.logFn(.debug, std.log.default_log_scope, "Message: 1", .{});
    logger.logFn(.debug, std.log.default_log_scope, "Message: 2", .{});
    logger.logFn(.debug, std.log.default_log_scope, "Message: 3", .{});
    logger.logFn(.debug, std.log.default_log_scope, "Message: 4", .{});

    try testing.expectEqual(2, logger.getLen());
    try testing.expectEqualStrings(
        "2020-01-02T03:04:05.123456789 [debug] Message: 3",
        (try logger.getEntry(0)).full_message,
    );
    try testing.expectEqualStrings(
        "2020-01-02T03:04:05.123456789 [debug] Message: 4",
        (try logger.getEntry(1)).full_message,
    );
}

test "should discard earliest entries when exceeding buffer size" {
    const nanoTimestamp = struct {
        fn call() i128 {
            return 1577934245123456789;
        }
    }.call;

    const logger = BufferLogger(.{
        .level = .debug,
        .time_zone = .utc,
        .buffer_size = 98,
        .max_entries = 64,
        .nanoTimestamp = nanoTimestamp,
    });

    logger.logFn(.debug, std.log.default_log_scope, "Message: 1", .{});
    logger.logFn(.debug, std.log.default_log_scope, "Message: 2", .{});
    logger.logFn(.debug, std.log.default_log_scope, "Message: 3", .{});
    logger.logFn(.debug, std.log.default_log_scope, "Message: 4", .{});

    try testing.expectEqual(2, logger.getLen());
    try testing.expectEqualStrings(
        "2020-01-02T03:04:05.123456789 [debug] Message: 3",
        (try logger.getEntry(0)).full_message,
    );
    try testing.expectEqualStrings(
        "2020-01-02T03:04:05.123456789 [debug] Message: 4",
        (try logger.getEntry(1)).full_message,
    );

    logger.logFn(.debug, std.log.default_log_scope, "Message: 123", .{});
    logger.logFn(.debug, std.log.default_log_scope, "Message: 456", .{});

    try testing.expectEqual(1, logger.getLen());
    try testing.expectEqualStrings(
        "2020-01-02T03:04:05.123456789 [debug] Message: 456",
        (try logger.getEntry(0)).full_message,
    );
}

test "should discard all entries when full message is larger then the buffer" {
    const nanoTimestamp = struct {
        fn call() i128 {
            return 1577934245123456789;
        }
    }.call;

    const logger = BufferLogger(.{
        .level = .debug,
        .time_zone = .utc,
        .buffer_size = 50,
        .max_entries = 64,
        .nanoTimestamp = nanoTimestamp,
    });

    logger.logFn(.debug, std.log.default_log_scope, "Message: 1", .{});

    try testing.expectEqual(1, logger.getLen());
    try testing.expectEqualStrings(
        "2020-01-02T03:04:05.123456789 [debug] Message: 1",
        (try logger.getEntry(0)).full_message,
    );

    logger.logFn(.debug, std.log.default_log_scope, "Message: 123", .{});

    try testing.expectEqual(0, logger.getLen());
}
