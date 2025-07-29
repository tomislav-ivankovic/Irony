const std = @import("std");
const misc = @import("../misc/root.zig");
const os = @import("../os/root.zig");

pub const FileLoggerConfig = struct {
    level: std.log.Level = .debug,
    time_zone: misc.TimeZone = .local,
    buffer_size: usize = 4096,
    nanoTimestamp: *const fn () i128 = std.time.nanoTimestamp,
};

pub fn FileLogger(comptime config: FileLoggerConfig) type {
    return struct {
        var log_file: ?std.fs.File = null;
        var log_writer: ?std.io.BufferedWriter(config.buffer_size, std.fs.File.Writer) = null;
        var mutex = std.Thread.Mutex{};

        pub fn start(file_path: []const u8) !void {
            const file = std.fs.cwd().createFile(file_path, .{ .truncate = false }) catch |err| {
                misc.error_context.new("Failed to create or open file: {s}\n", .{file_path});
                return err;
            };
            const end_pos = file.getEndPos() catch |err| {
                misc.error_context.new("Failed to get the end position of the file: {s}\n", .{file_path});
                return err;
            };
            file.seekTo(end_pos) catch |err| {
                misc.error_context.new(
                    "Failed to seek to end position ({}) of the file: {s}\n",
                    .{ end_pos, file_path },
                );
                return err;
            };
            log_file = file;
            log_writer = .{ .unbuffered_writer = file.writer() };
        }

        pub fn stop() void {
            if (log_writer) |*writer| {
                writer.flush() catch |err| {
                    std.debug.print("Failed to flush buffer before closing the file logger. Cause: {}\n", .{err});
                };
                log_writer = null;
            }
            if (log_file) |*file| {
                file.close();
                log_file = null;
            }
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
            const timestamp = misc.Timestamp.fromNano(config.nanoTimestamp(), config.time_zone) catch null;
            const scope_prefix = if (scope != std.log.default_log_scope) "(" ++ @tagName(scope) ++ ") " else "";
            const level_prefix = "[" ++ comptime level.asText() ++ "] ";
            var writer = log_writer orelse return;
            mutex.lock();
            defer mutex.unlock();
            writer.writer().print(
                "{?} " ++ level_prefix ++ scope_prefix ++ format ++ "\n",
                .{timestamp} ++ args,
            ) catch |err| {
                std.debug.print("Failed to write log message with file logger. Cause: {}\n", .{err});
                return;
            };
            writer.flush() catch |err| {
                std.debug.print("Failed to flush log buffer with file logger. Cause: {}\n", .{err});
                return;
            };
        }
    };
}

const testing = std.testing;

test "should format output correctly" {
    const file_path = "./test_assets/tmp1.log";
    const nanoTimestamp = struct {
        fn call() i128 {
            return 1577934245123456789;
        }
    }.call;

    const logger = FileLogger(.{
        .level = .debug,
        .time_zone = .utc,
        .nanoTimestamp = nanoTimestamp,
    });
    try logger.start(file_path);
    logger.logFn(.debug, std.log.default_log_scope, "Message: {}", .{1});
    logger.logFn(.info, .scope_1, "Message: {}", .{2});
    logger.logFn(.warn, .scope_2, "Message: {}", .{3});
    logger.logFn(.err, .scope_3, "Message: {}", .{4});
    logger.stop();

    const content = try std.fs.cwd().readFileAlloc(testing.allocator, file_path, 1_000_000);
    defer testing.allocator.free(content);
    try std.fs.cwd().deleteFile(file_path);

    const expected =
        \\2020-01-02T03:04:05.123456789 [debug] Message: 1
        \\2020-01-02T03:04:05.123456789 [info] (scope_1) Message: 2
        \\2020-01-02T03:04:05.123456789 [warning] (scope_2) Message: 3
        \\2020-01-02T03:04:05.123456789 [error] (scope_3) Message: 4
        \\
    ;
    try testing.expectEqualStrings(expected, content);
}

test "should filter based on log level correctly" {
    const file_path = "./test_assets/tmp2.log";
    const nanoTimestamp = struct {
        fn call() i128 {
            return 1577934245123456789;
        }
    }.call;

    const logger = FileLogger(.{
        .level = .warn,
        .time_zone = .utc,
        .nanoTimestamp = nanoTimestamp,
    });
    try logger.start(file_path);
    logger.logFn(.debug, std.log.default_log_scope, "Message: 1", .{});
    logger.logFn(.info, std.log.default_log_scope, "Message: 2", .{});
    logger.logFn(.warn, std.log.default_log_scope, "Message: 3", .{});
    logger.logFn(.err, std.log.default_log_scope, "Message: 4", .{});
    logger.stop();

    const content = try std.fs.cwd().readFileAlloc(testing.allocator, file_path, 1_000_000);
    defer testing.allocator.free(content);
    try std.fs.cwd().deleteFile(file_path);

    const expected =
        \\2020-01-02T03:04:05.123456789 [warning] Message: 3
        \\2020-01-02T03:04:05.123456789 [error] Message: 4
        \\
    ;
    try testing.expectEqualStrings(expected, content);
}

test "should append logs to the end of the file" {
    const file_path = "./test_assets/tmp3.log";
    const nanoTimestamp = struct {
        fn call() i128 {
            return 1577934245123456789;
        }
    }.call;

    const file = try std.fs.cwd().createFile(file_path, .{});
    try file.writeAll("Content before logging.\n");
    file.close();

    const logger = FileLogger(.{
        .level = .debug,
        .time_zone = .utc,
        .nanoTimestamp = nanoTimestamp,
    });
    try logger.start(file_path);
    logger.logFn(.info, std.log.default_log_scope, "Logging content.", .{});
    logger.stop();

    const content = try std.fs.cwd().readFileAlloc(testing.allocator, file_path, 1_000_000);
    defer testing.allocator.free(content);
    try std.fs.cwd().deleteFile(file_path);

    const expected =
        \\Content before logging.
        \\2020-01-02T03:04:05.123456789 [info] Logging content.
        \\
    ;
    try testing.expectEqualStrings(expected, content);
}
