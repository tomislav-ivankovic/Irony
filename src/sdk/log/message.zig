const std = @import("std");

pub const Message = struct {
    level: std.log.Level,
    scope: ?[]const u8,
    print: Print,
    args: *const anyopaque,

    const Self = @This();
    pub const Print = *const fn (writer: *std.Io.Writer, args: *const anyopaque) std.Io.Writer.Error!void;

    pub fn fromParams(
        comptime level: std.log.Level,
        comptime scope: @EnumLiteral(),
        comptime fmt: []const u8,
        args_pointer: anytype,
    ) Self {
        const Args = @typeInfo(@TypeOf(args_pointer)).pointer.child;
        const print = struct {
            fn call(writer: *std.Io.Writer, args: *const anyopaque) std.Io.Writer.Error!void {
                const typed_args: *const Args = @ptrCast(@alignCast(args));
                return writer.print(fmt, typed_args.*);
            }
        }.call;
        return .{
            .level = level,
            .scope = if (scope != std.log.default_log_scope) @tagName(scope) else null,
            .print = print,
            .args = args_pointer,
        };
    }

    pub fn getLevelText(self: *const Self) []const u8 {
        return switch (self.level) {
            inline else => |level| level.asText(),
        };
    }

    pub fn format(self: *const Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        return self.print(writer, self.args);
    }
};

const testing = std.testing;

test "fromParams should set correct level" {
    const args = .{};
    const message = Message.fromParams(.warn, .scope, "Message.", &args);
    try testing.expectEqual(.warn, message.level);
}

test "fromParams should set scope to null when scope is the default scope" {
    const args = .{};
    const message = Message.fromParams(.info, std.log.default_log_scope, "Message.", &args);
    try testing.expectEqual(null, message.scope);
}

test "fromParams should set scope to scope name when scope is not the default scope" {
    const args = .{};
    const message = Message.fromParams(.info, .some_scope, "Message.", &args);
    try testing.expectEqualStrings("some_scope", message.scope orelse return error.ScopeIsNull);
}

test "getLevelText should return correct text" {
    const args = .{};
    try testing.expectEqualStrings("error", Message.fromParams(.err, .scope, "", &args).getLevelText());
    try testing.expectEqualStrings("warning", Message.fromParams(.warn, .scope, "", &args).getLevelText());
    try testing.expectEqualStrings("info", Message.fromParams(.info, .scope, "", &args).getLevelText());
    try testing.expectEqualStrings("debug", Message.fromParams(.debug, .scope, "", &args).getLevelText());
}

test "format should write formatted message" {
    const args = .{ 1, "two" };
    const message = Message.fromParams(.info, .scope, "Message: {} {s}", &args);
    var buffer: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try message.format(&writer);
    try testing.expectEqualStrings("Message: 1 two", writer.buffered());
}

test "should be formattable with the f format specifier" {
    const args = .{123};
    const message = Message.fromParams(.info, .scope, "Message: {}", &args);
    const result = try std.fmt.allocPrint(testing.allocator, "{f}", .{&message});
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("Message: 123", result);
}
