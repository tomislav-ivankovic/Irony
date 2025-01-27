const std = @import("std");
const w32 = @import("win32").everything;
const testing = std.testing;

pub fn pathToFileName(path: []const u8) []const u8 {
    var last_separator_index: ?usize = null;
    var i: usize = path.len;
    while (i > 0) {
        i -= 1;
        const character = path[i];
        if (character == '\\' or character == '/') {
            last_separator_index = i;
            break;
        }
    }
    if (last_separator_index) |index| {
        return path[(index + 1)..path.len];
    } else {
        return path;
    }
}

test "pathToFileName should return correct value" {
    try testing.expectEqualStrings("test3.exe", pathToFileName("test1\\test2\\test3.exe"));
    try testing.expectEqualStrings("test3", pathToFileName("test1\\test2\\test3"));
    try testing.expectEqualStrings("test3", pathToFileName("test1/test2/test3"));
    try testing.expectEqualStrings("test", pathToFileName("test"));
    try testing.expectEqualStrings("", pathToFileName("test\\"));
    try testing.expectEqualStrings("test", pathToFileName("\\test"));
    try testing.expectEqualStrings("", pathToFileName(""));
    try testing.expectEqualStrings("", pathToFileName("\\"));
}

pub fn isReadableMemory(address: usize, size_in_bytes: usize) bool {
    return w32.IsBadReadPtr(@ptrFromInt(address), size_in_bytes) == 0;
}

test "isReadableMemory should return true when memory range is readable" {
    const memory = [_]u8{ 0, 1, 2, 3, 4 };
    const address = @intFromPtr(&memory);
    const size_in_bytes = @sizeOf(@TypeOf(memory));
    const is_readable = isReadableMemory(address, size_in_bytes);
    try testing.expectEqual(true, is_readable);
}

test "isReadableMemory should return false when memory range is not readable entirely" {
    const is_readable = isReadableMemory(0, std.math.maxInt(usize));
    try testing.expectEqual(false, is_readable);
}

pub fn isWriteableMemory(address: usize, size_in_bytes: usize) bool {
    return w32.IsBadWritePtr(@ptrFromInt(address), size_in_bytes) == 0;
}

test "isWriteableMemory should return true when memory range is writable" {
    var memory = [_]u8{ 0, 1, 2, 3, 4 };
    const address = @intFromPtr(&memory);
    const size_in_bytes = @sizeOf(@TypeOf(memory));
    const is_writeable = isWriteableMemory(address, size_in_bytes);
    try testing.expectEqual(true, is_writeable);
}

test "isWriteableMemory should return false when memory range is not writable entirely" {
    const is_writeable = isWriteableMemory(0, std.math.maxInt(usize));
    try testing.expectEqual(false, is_writeable);
}
