const std = @import("std");
const w32 = @import("win32").everything;
const mics = @import("../misc/root.zig");
const os = @import("root.zig");

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

pub fn filePathToDirectoryPath(path: []const u8) []const u8 {
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
        if (index == 0) {
            return path[0..1];
        } else {
            return path[0..index];
        }
    } else {
        return ".";
    }
}

pub fn getFullPath(full_path_buffer: *[os.max_file_path_length]u8, short_path: []const u8) !usize {
    var short_path_buffer_utf16 = [_:0]u16{0} ** os.max_file_path_length;
    const short_path_size = std.unicode.utf8ToUtf16Le(&short_path_buffer_utf16, short_path) catch |err| {
        mics.errorContext().newFmt(err, "Failed to convert UTF8 string \"{s}\" to UTF16-LE.", .{short_path});
        return err;
    };
    const short_path_utf16 = short_path_buffer_utf16[0..short_path_size :0];
    var full_path_buffer_utf16: [os.max_file_path_length:0]u16 = undefined;
    const full_path_size = w32.GetFullPathNameW(short_path_utf16, full_path_buffer_utf16.len, &full_path_buffer_utf16, null);
    if (full_path_size == 0) {
        mics.errorContext().newFmt(null, "{}", os.OsError.getLast());
        mics.errorContext().append(error.OsError, "GetFullPathNameW returned 0.");
        return error.OsError;
    }
    const full_path_utf16 = full_path_buffer_utf16[0..full_path_size];
    return std.unicode.utf16LeToUtf8(full_path_buffer, full_path_utf16) catch |err| {
        mics.errorContext().new(err, "Failed to convert UTF16-LE string to UTF8.");
        return err;
    };
}

pub fn setConsoleCloseHandler(onConsoleClose: *const fn () void) !void {
    const Handler = struct {
        var function: ?*const fn () void = null;
        fn call(event: u32) callconv(.C) w32.BOOL {
            if (event != w32.CTRL_C_EVENT and event != w32.CTRL_CLOSE_EVENT) {
                return 0;
            }
            (function orelse unreachable)();
            return 0;
        }
    };
    Handler.function = onConsoleClose;
    const success = w32.SetConsoleCtrlHandler(Handler.call, 1);
    if (success == 0) {
        mics.errorContext().newFmt(null, "{}", os.OsError.getLast());
        mics.errorContext().append(error.OsError, "SetConsoleCtrlHandler returned 0.");
        return error.OsError;
    }
}

const testing = std.testing;

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

test "filePathToDirectoryPath should return correct value" {
    try testing.expectEqualStrings("test1\\test2", filePathToDirectoryPath("test1\\test2\\test3.exe"));
    try testing.expectEqualStrings("test1\\test2", filePathToDirectoryPath("test1\\test2\\test3"));
    try testing.expectEqualStrings(".\\test1\\test2", filePathToDirectoryPath(".\\test1\\test2\\test3"));
    try testing.expectEqualStrings("\\test1\\test2", filePathToDirectoryPath("\\test1\\test2\\test3"));
    try testing.expectEqualStrings("test1/test2", filePathToDirectoryPath("test1/test2/test3"));
    try testing.expectEqualStrings(".", filePathToDirectoryPath("test"));
    try testing.expectEqualStrings("test", filePathToDirectoryPath("test\\"));
    try testing.expectEqualStrings("\\", filePathToDirectoryPath("\\test"));
    try testing.expectEqualStrings(".", filePathToDirectoryPath(""));
    try testing.expectEqualStrings("\\", filePathToDirectoryPath("\\"));
}

test "getFullPath should produce correct full path" {
    var buffer: [os.max_file_path_length]u8 = undefined;
    const size = try getFullPath(&buffer, "./test_1/test_2/test_3.txt");
    const full_path = buffer[0..size];
    try testing.expectStringEndsWith(full_path, "\\test_1\\test_2\\test_3.txt");
}
