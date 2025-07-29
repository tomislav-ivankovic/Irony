const std = @import("std");
const w32 = @import("win32").everything;

pub const Error = struct {
    error_code: w32.WIN32_ERROR,

    const Self = @This();

    pub fn getLast() Self {
        return .{ .error_code = w32.GetLastError() };
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        if (fmt.len != 0) {
            @compileError(std.fmt.comptimePrint(
                "Invalid Error format {{{s}}}. The only allowed format for Error is {{}}.",
                .{fmt},
            ));
        }

        const language_id = 1024 * w32.SUBLANG_ENGLISH_US | w32.LANG_ENGLISH;
        var message: [*:0]u16 = undefined;
        const message_length = w32.FormatMessageW(.{
            .ALLOCATE_BUFFER = 1,
            .IGNORE_INSERTS = 1,
            .FROM_SYSTEM = 1,
        }, null, @intFromEnum(self.error_code), language_id, @ptrCast(&message), 0, null);
        defer _ = w32.LocalFree(@bitCast(@intFromPtr(message)));

        if (message_length > 0) {
            var iterator = std.unicode.Utf16LeIterator.init(message[0..message_length]);
            while (try iterator.nextCodepoint()) |codepoint| {
                var buffer = [_]u8{undefined} ** 4;
                const len = try std.unicode.utf8Encode(codepoint, &buffer);
                try writer.writeAll(buffer[0..len]);
            }
            try writer.writeAll(" (");
        }

        try writer.print("error code 0x{X} {s}", .{ @intFromEnum(self.error_code), @tagName(self.error_code) });

        if (message_length > 0) {
            try writer.writeAll(")");
        }
    }
};

const testing = std.testing;
const w = std.unicode.utf8ToUtf16LeStringLiteral;

test "getLast should get correct error code" {
    _ = w32.GetModuleHandleW(w("invalid module name"));
    const err = Error.getLast();
    try testing.expectEqual(err.error_code, w32.ERROR_MOD_NOT_FOUND);
}

test "should format correctly when error has message" {
    const err = Error{ .error_code = w32.ERROR_FILE_NOT_FOUND };
    const message = try std.fmt.allocPrint(testing.allocator, "{}", .{err});
    defer testing.allocator.free(message);
    if (std.mem.startsWith(u8, message, "F")) { // Wine
        try testing.expectEqualStrings("File not found.\r\n (error code 0x2 ERROR_FILE_NOT_FOUND)", message);
    } else { // Windows
        try testing.expectEqualStrings(
            "The system cannot find the file specified.\r\n (error code 0x2 ERROR_FILE_NOT_FOUND)",
            message,
        );
    }
}

test "should format correctly when error has no message" {
    const err = Error{ .error_code = w32.WAIT_FAILED };
    const message = try std.fmt.allocPrint(testing.allocator, "{}", .{err});
    defer testing.allocator.free(message);
    try testing.expectEqualStrings("error code 0xFFFFFFFF WAIT_FAILED", message);
}
