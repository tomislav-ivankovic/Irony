const std = @import("std");
const MessageBox = @import("win32").ui.windows_and_messaging.MessageBoxW;
const W = std.unicode.utf8ToUtf16LeStringLiteral;

pub fn main() !void {
    _ = MessageBox(null, W("Hello world."), W("caption"), .{});
}

test "hello test" {
    try std.testing.expectEqual(123, 123);
}
