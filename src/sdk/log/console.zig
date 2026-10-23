const std = @import("std");
const misc = @import("../misc/root.zig");

pub const ConsoleLoggerConfig = struct {
    level: std.log.Level = .debug,
    time_zone: misc.TimeZone = .local,
    buffer_size: usize = 4096,
};

pub fn ConsoleLogger(comptime config: ConsoleLoggerConfig) type {
    return struct {
        var io_maybe: ?std.Io = null;
        var buffer: [config.buffer_size]u8 = undefined;

        pub fn setIo(io: std.Io) void {
            io_maybe = io;
        }

        pub fn logFn(
            comptime level: std.log.Level,
            comptime scope: @EnumLiteral(),
            comptime format: []const u8,
            args: anytype,
        ) void {
            if (@intFromEnum(level) > @intFromEnum(config.level)) {
                return;
            }
            const io = io_maybe orelse return;
            const nano_time = std.Io.Clock.real.now(io).nanoseconds;
            const timestamp = misc.Timestamp.fromNano(nano_time, config.time_zone) catch null;
            const scope_prefix = if (scope != std.log.default_log_scope) "(" ++ @tagName(scope) ++ ") " else "";
            const level_prefix = "[" ++ comptime level.asText() ++ "] ";
            const stderr = io.lockStderr(&buffer, null) catch return;
            defer io.unlockStderr();
            const writer = &stderr.file_writer.interface;
            if (timestamp) |t| {
                writer.print("{f} " ++ level_prefix ++ scope_prefix ++ format ++ "\n", .{t} ++ args) catch return;
            } else {
                writer.print(level_prefix ++ scope_prefix ++ format ++ "\n", args) catch return;
            }
            writer.flush() catch return;
        }
    };
}

const testing = std.testing;

test "should format output correctly" {
    const Io = struct {
        pub const instance = block: {
            var io = testing.io;
            var vtable = io.vtable.*;
            vtable.now = now;
            vtable.lockStderr = lockStderr;
            vtable.unlockStderr = unlockStderr;
            const vtable_final = vtable;
            io.vtable = &vtable_final;
            break :block io;
        };
        var result_buffer: [512]u8 = undefined;
        var result_writer = std.Io.Writer.fixed(&result_buffer);
        var file_writer = std.Io.File.Writer{
            .io = instance,
            .file = undefined,
            .interface = .fixed(&.{}),
            .mode = .streaming_simple,
        };
        var is_locked = false;

        pub fn getStderrContent() []const u8 {
            return result_buffer[0..result_writer.end];
        }

        fn now(_: ?*anyopaque, _: std.Io.Clock) std.Io.Timestamp {
            return .fromNanoseconds(1577934245123456789);
        }

        fn lockStderr(_: ?*anyopaque, terminal_mode: ?std.Io.Terminal.Mode) std.Io.Cancelable!std.Io.LockedStderr {
            if (is_locked) @panic("Already locked.");
            is_locked = true;
            return .{
                .file_writer = &file_writer,
                .terminal_mode = terminal_mode orelse .no_color,
            };
        }

        fn unlockStderr(_: ?*anyopaque) void {
            if (!is_locked) @panic("Not locked.");
            is_locked = false;
            result_writer.writeAll(file_writer.interface.buffer[0..file_writer.interface.end]) catch {
                @panic("Result buffer full.");
            };
            file_writer.interface = .fixed(&.{});
        }
    };

    const logger = ConsoleLogger(.{
        .level = .debug,
        .time_zone = .utc,
    });
    logger.setIo(Io.instance);

    logger.logFn(.debug, std.log.default_log_scope, "Message: {}", .{1});
    logger.logFn(.info, .scope_1, "Message: {}", .{2});
    logger.logFn(.warn, .scope_2, "Message: {}", .{3});
    logger.logFn(.err, .scope_3, "Message: {}", .{4});
    const expected =
        \\2020-01-02T03:04:05.123456789 [debug] Message: 1
        \\2020-01-02T03:04:05.123456789 [info] (scope_1) Message: 2
        \\2020-01-02T03:04:05.123456789 [warning] (scope_2) Message: 3
        \\2020-01-02T03:04:05.123456789 [error] (scope_3) Message: 4
        \\
    ;
    try testing.expectEqualStrings(expected, Io.getStderrContent());
}

test "should filter based on log level correctly" {
    const Io = struct {
        pub const instance = block: {
            var io = testing.io;
            var vtable = io.vtable.*;
            vtable.now = now;
            vtable.lockStderr = lockStderr;
            vtable.unlockStderr = unlockStderr;
            const vtable_final = vtable;
            io.vtable = &vtable_final;
            break :block io;
        };
        var result_buffer: [512]u8 = undefined;
        var result_writer = std.Io.Writer.fixed(&result_buffer);
        var file_writer = std.Io.File.Writer{
            .io = instance,
            .file = undefined,
            .interface = .fixed(&.{}),
            .mode = .streaming_simple,
        };
        var is_locked = false;

        pub fn getStderrContent() []const u8 {
            return result_buffer[0..result_writer.end];
        }

        fn now(_: ?*anyopaque, _: std.Io.Clock) std.Io.Timestamp {
            return .fromNanoseconds(1577934245123456789);
        }

        fn lockStderr(_: ?*anyopaque, terminal_mode: ?std.Io.Terminal.Mode) std.Io.Cancelable!std.Io.LockedStderr {
            if (is_locked) @panic("Already locked.");
            is_locked = true;
            return .{
                .file_writer = &file_writer,
                .terminal_mode = terminal_mode orelse .no_color,
            };
        }

        fn unlockStderr(_: ?*anyopaque) void {
            if (!is_locked) @panic("Not locked.");
            is_locked = false;
            result_writer.writeAll(file_writer.interface.buffer[0..file_writer.interface.end]) catch {
                @panic("Result buffer full.");
            };
            file_writer.interface = .fixed(&.{});
        }
    };

    const logger = ConsoleLogger(.{
        .level = .warn,
        .time_zone = .utc,
    });
    logger.setIo(Io.instance);

    logger.logFn(.debug, std.log.default_log_scope, "Message: 1", .{});
    logger.logFn(.info, std.log.default_log_scope, "Message: 2", .{});
    logger.logFn(.warn, std.log.default_log_scope, "Message: 3", .{});
    logger.logFn(.err, std.log.default_log_scope, "Message: 4", .{});

    const expected =
        \\2020-01-02T03:04:05.123456789 [warning] Message: 3
        \\2020-01-02T03:04:05.123456789 [error] Message: 4
        \\
    ;
    try testing.expectEqualStrings(expected, Io.getStderrContent());
}
