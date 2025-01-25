const w32 = @import("win32").everything;
const std = @import("std");
const w = std.unicode.utf8ToUtf16LeStringLiteral;

pub const OsError = struct {
    error_code: w32.WIN32_ERROR,

    const Self = @This();

    pub fn getLast() Self {
        return .{ .error_code = w32.GetLastError() };
    }

    pub fn getMessage(self: *const Self, allocator: std.mem.Allocator) ![:0]const u8 {
        const error_code = @intFromEnum(self.error_code);
        const language_id = 1024 * w32.SUBLANG_ENGLISH_US | w32.LANG_ENGLISH;
        var null_terminated_message: [*:0]u16 = undefined;
        const message_length = w32.FormatMessageW(.{
            .ALLOCATE_BUFFER = 1,
            .IGNORE_INSERTS = 1,
            .FROM_SYSTEM = 1,
        }, null, error_code, language_id, @ptrCast(&null_terminated_message), 0, null);
        defer _ = w32.LocalFree(@bitCast(@intFromPtr(null_terminated_message)));
        if (message_length == 0) {
            return error.OsError;
        }
        const message_slice = null_terminated_message[0..message_length];
        return try std.unicode.utf16LeToUtf8AllocZ(allocator, message_slice);
    }
};

const testing = std.testing;

test "getLast should get correct error code" {
    _ = w32.GetModuleHandleW(w("invalid module name"));
    const err = OsError.getLast();
    try testing.expectEqual(err.error_code, w32.ERROR_MOD_NOT_FOUND);
}

test "getMessage should return correct message when error code is valid" {
    const err = OsError{ .error_code = w32.ERROR_MOD_NOT_FOUND };
    const message = try err.getMessage(testing.allocator);
    defer testing.allocator.free(message);
    try testing.expectEqualStrings("Module not found.\r\n", message);
}

test "getMessage should return OsError when error code is invalid" {
    const err = OsError{ .error_code = @enumFromInt(0xFFFFFFFF) };
    try testing.expectError(error.OsError, err.getMessage(testing.allocator));
}
