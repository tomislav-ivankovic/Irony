const std = @import("std");
const misc = @import("../misc/root.zig");
const os = @import("../os/root.zig");

pub const FileLoggerConfig = struct {
    level: std.log.Level = .debug,
    time_zone: misc.TimeZone = .local,
    buffer_size: usize = 4096,
};

pub fn FileLogger(comptime config: FileLoggerConfig) type {
    return struct {
        var state_maybe: ?State = null;
        var buffer: [config.buffer_size]u8 = @splat(0);
        var mutex = std.Io.Mutex.init;

        const State = struct {
            io: std.Io,
            file: std.Io.File,
            file_writer: std.Io.File.Writer,
        };

        pub fn start(io: std.Io, file_path: []const u8) !void {
            if (state_maybe != null) {
                misc.error_context.new("File logger already started.", .{});
                return error.AlreadyStarted;
            }
            const file = std.Io.Dir.cwd().createFile(io, file_path, .{ .truncate = false, .read = true }) catch |err| {
                misc.error_context.new("Failed to create or open file: {s}", .{file_path});
                return err;
            };
            errdefer file.close(io);
            const file_length = file.length(io) catch |err| {
                misc.error_context.new("Failed to find file length: {s}", .{file_path});
                return err;
            };
            var file_writer = file.writerStreaming(io, &buffer);
            file_writer.seekTo(file_length) catch |err| {
                misc.error_context.new("Failed to seek to {} offset of the file: {s}", .{ file_length, file_path });
                return err;
            };
            state_maybe = .{
                .io = io,
                .file = file,
                .file_writer = file_writer,
            };
        }

        pub fn stop() void {
            const state = if (state_maybe) |*s| s else return;
            var end_error: ?anyerror = null;
            {
                const locked = if (mutex.lock(state.io)) true else |_| false;
                defer if (locked) mutex.unlock(state.io);
                state.file_writer.end() catch |err| {
                    end_error = err;
                };
                state.file.close(state.io);
                state_maybe = null;
            }
            // Logging must happen outside of the lock since logFn locks the same mutex.
            if (end_error) |err| {
                misc.error_context.new("Failed to end file writer.", .{});
                misc.error_context.append("Failed to stop file logger.", .{});
                misc.error_context.logError(err);
            }
        }

        pub fn logFn(
            comptime level: std.log.Level,
            comptime scope: @EnumLiteral(),
            comptime format: []const u8,
            args: anytype,
        ) void {
            if (@backingInt(level) > @backingInt(config.level)) {
                return;
            }
            const state = if (state_maybe) |*s| s else return;
            const nano_time = std.Io.Clock.real.now(state.io).nanoseconds;
            const timestamp = misc.Timestamp.fromNano(nano_time, config.time_zone) catch null;
            const scope_prefix = if (scope != std.log.default_log_scope) "(" ++ @tagName(scope) ++ ") " else "";
            const level_prefix = "[" ++ comptime level.asText() ++ "] ";
            const writer = &state.file_writer.interface;
            mutex.lock(state.io) catch return;
            defer mutex.unlock(state.io);
            if (state_maybe == null) {
                return; // Logger was stopped while waiting for the lock.
            }
            if (timestamp) |t| {
                writer.print("{f} " ++ level_prefix ++ scope_prefix ++ format ++ "\n", .{t} ++ args) catch |err| {
                    std.debug.print("Failed to write log message with file logger. Cause: {}\n", .{err});
                    return;
                };
            } else {
                writer.print(level_prefix ++ scope_prefix ++ format ++ "\n", args) catch |err| {
                    std.debug.print("Failed to write log message with file logger. Cause: {}\n", .{err});
                    return;
                };
            }
            writer.flush() catch |err| {
                std.debug.print("Failed to flush log buffer with file logger. Cause: {}\n", .{err});
                return;
            };
        }
    };
}

const testing = std.testing;

test "should format output correctly" {
    const file_path = "tmp1.log";
    var io = testing.io;
    var vtable = io.vtable.*;
    vtable.now = struct {
        fn call(_: ?*anyopaque, _: std.Io.Clock) std.Io.Timestamp {
            return .fromNanoseconds(1577934245123456789);
        }
    }.call;
    io.vtable = &vtable;

    const logger = FileLogger(.{
        .level = .debug,
        .time_zone = .utc,
    });
    try logger.start(io, file_path);
    logger.logFn(.debug, std.log.default_log_scope, "Message: {}", .{1});
    logger.logFn(.info, .scope_1, "Message: {}", .{2});
    logger.logFn(.warn, .scope_2, "Message: {}", .{3});
    logger.logFn(.err, .scope_3, "Message: {}", .{4});
    logger.stop();
    defer std.Io.Dir.cwd().deleteFile(io, file_path) catch @panic("Failed to clean up test file.");

    const content = try std.Io.Dir.cwd().readFileAlloc(io, file_path, testing.allocator, .limited(1_000_000));
    defer testing.allocator.free(content);

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
    const file_path = "tmp2.log";
    var io = testing.io;
    var vtable = io.vtable.*;
    vtable.now = struct {
        fn call(_: ?*anyopaque, _: std.Io.Clock) std.Io.Timestamp {
            return .fromNanoseconds(1577934245123456789);
        }
    }.call;
    io.vtable = &vtable;

    const logger = FileLogger(.{
        .level = .warn,
        .time_zone = .utc,
    });
    try logger.start(io, file_path);
    logger.logFn(.debug, std.log.default_log_scope, "Message: 1", .{});
    logger.logFn(.info, std.log.default_log_scope, "Message: 2", .{});
    logger.logFn(.warn, std.log.default_log_scope, "Message: 3", .{});
    logger.logFn(.err, std.log.default_log_scope, "Message: 4", .{});
    logger.stop();
    defer std.Io.Dir.cwd().deleteFile(io, file_path) catch @panic("Failed to clean up test file.");

    const content = try std.Io.Dir.cwd().readFileAlloc(io, file_path, testing.allocator, .limited(1_000_000));
    defer testing.allocator.free(content);

    const expected =
        \\2020-01-02T03:04:05.123456789 [warning] Message: 3
        \\2020-01-02T03:04:05.123456789 [error] Message: 4
        \\
    ;
    try testing.expectEqualStrings(expected, content);
}

test "should append logs to the end of the file" {
    const file_path = "tmp3.log";
    var io = testing.io;
    var vtable = io.vtable.*;
    vtable.now = struct {
        fn call(_: ?*anyopaque, _: std.Io.Clock) std.Io.Timestamp {
            return .fromNanoseconds(1577934245123456789);
        }
    }.call;
    io.vtable = &vtable;

    const file = try std.Io.Dir.cwd().createFile(io, file_path, .{});
    try file.writeStreamingAll(io, "Content before logging.\n");
    file.close(io);

    const logger = FileLogger(.{
        .level = .debug,
        .time_zone = .utc,
    });
    try logger.start(io, file_path);
    logger.logFn(.info, std.log.default_log_scope, "Logging content.", .{});
    logger.stop();
    defer std.Io.Dir.cwd().deleteFile(io, file_path) catch @panic("Failed to clean up test file.");

    const content = try std.Io.Dir.cwd().readFileAlloc(io, file_path, testing.allocator, .limited(1_000_000));
    defer testing.allocator.free(content);

    const expected =
        \\Content before logging.
        \\2020-01-02T03:04:05.123456789 [info] Logging content.
        \\
    ;
    try testing.expectEqualStrings(expected, content);
}
