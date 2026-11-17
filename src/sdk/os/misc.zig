const std = @import("std");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
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
        return path[(index + 1)..];
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
    var short_path_buffer_utf16: [os.max_file_path_length:0]u16 = @splat(0);
    const short_path_size = std.unicode.utf8ToUtf16Le(&short_path_buffer_utf16, short_path) catch |err| {
        misc.error_context.new("Failed to convert UTF8 string \"{s}\" to UTF16-LE.", .{short_path});
        return err;
    };
    const short_path_utf16 = short_path_buffer_utf16[0..short_path_size :0];
    var full_path_buffer_utf16: [os.max_file_path_length:0]u16 = undefined;
    const full_path_size = w32.GetFullPathNameW(
        short_path_utf16,
        full_path_buffer_utf16.len,
        &full_path_buffer_utf16,
        null,
    );
    if (full_path_size == 0) {
        misc.error_context.new("{f}", .{os.Error.getLast()});
        misc.error_context.append("GetFullPathNameW returned 0.", .{});
        return error.OsError;
    }
    const full_path_utf16 = full_path_buffer_utf16[0..full_path_size];
    return std.unicode.utf16LeToUtf8(full_path_buffer, full_path_utf16) catch |err| {
        misc.error_context.new("Failed to convert UTF16-LE string to UTF8.", .{});
        return err;
    };
}

pub fn setConsoleCloseHandler(onConsoleClose: *const fn () void) !void {
    const Handler = struct {
        var function: ?*const fn () void = null;
        fn call(event: u32) callconv(.c) w32.BOOL {
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
        misc.error_context.new("{f}", .{os.Error.getLast()});
        misc.error_context.append("SetConsoleCtrlHandler returned 0.", .{});
        return error.OsError;
    }
}

pub fn getExecutableTimestamp() !u32 {
    const handle = w32.GetModuleHandleW(null) orelse {
        misc.error_context.new("{f}", .{os.Error.getLast()});
        misc.error_context.append("GetModuleHandleW returned null.", .{});
        return error.OsError;
    };
    const dos_header: *align(1) const w32.IMAGE_DOS_HEADER = @ptrCast(handle);
    if (!os.isMemoryReadable(@intFromPtr(dos_header), @sizeOf(w32.IMAGE_DOS_HEADER))) {
        misc.error_context.new("DOS header memory not readable.", .{});
        return error.NotReadable;
    }
    if (dos_header.e_magic != w32.IMAGE_DOS_SIGNATURE) {
        misc.error_context.new("Incorrect magic number inside DOS header: {}", .{dos_header.e_magic});
        return error.IncorrectMagicNumber;
    }
    const base_address: usize = @intFromPtr(handle);
    const offset: usize = @intCast(dos_header.e_lfanew);
    const nt_headers: *align(1) const w32.IMAGE_NT_HEADERS64 = @ptrFromInt(base_address + offset);
    if (!os.isMemoryReadable(@intFromPtr(nt_headers), @sizeOf(w32.IMAGE_NT_HEADERS64))) {
        misc.error_context.new("NT headers memory not readable.", .{});
        return error.NotReadable;
    }
    if (nt_headers.Signature != w32.IMAGE_NT_SIGNATURE) {
        misc.error_context.new("Incorrect signature inside NT headers: {}", .{nt_headers.Signature});
        return error.IncorrectSignature;
    }
    return nt_headers.FileHeader.TimeDateStamp;
}

pub fn systemTimeFromNano(nano_timestamp: i128, time_zone: misc.TimeZone) !w32.SYSTEMTIME {
    const ticks_per_second = std.time.ns_per_s / 100;
    const windows_ticks = @divFloor(nano_timestamp, 100) - (std.time.epoch.windows * ticks_per_second);
    const ticks = std.math.cast(u63, windows_ticks) orelse {
        misc.error_context.new("Timestamp {} ns is out of the range representable by FILETIME.", .{nano_timestamp});
        return error.OutOfRange;
    };
    const file_time = w32.FILETIME{
        .dwLowDateTime = @truncate(ticks),
        .dwHighDateTime = @truncate(ticks >> 32),
    };
    var utc_time: w32.SYSTEMTIME = undefined;
    if (w32.FileTimeToSystemTime(&file_time, &utc_time) == 0) {
        misc.error_context.new("{f}", .{os.Error.getLast()});
        misc.error_context.append("FileTimeToSystemTime returned 0.", .{});
        return error.OsError;
    }
    switch (time_zone) {
        .utc => return utc_time,
        .local => {
            var local_time: w32.SYSTEMTIME = undefined;
            if (w32.SystemTimeToTzSpecificLocalTime(null, &utc_time, &local_time) == 0) {
                misc.error_context.new("{f}", .{os.Error.getLast()});
                misc.error_context.append("SystemTimeToTzSpecificLocalTime returned 0.", .{});
                return error.OsError;
            }
            return local_time;
        },
    }
}

pub fn httpsGet(
    allocator: std.mem.Allocator,
    comptime url: []const u8,
    comptime headers: []const u8,
    max_body_size: usize,
) ![]u8 {
    const host, const path = comptime block: {
        const prefix = "https://";
        if (!std.mem.startsWith(u8, url, prefix)) {
            @compileError("Expecting an HTTPS URL but got: " ++ url);
        }
        const rest = url[prefix.len..];
        const path_start = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
        break :block .{ rest[0..path_start], rest[path_start..] };
    };
    const headers_utf16 = std.unicode.utf8ToUtf16LeStringLiteral(headers);

    const session = w32.WinHttpOpen(
        std.unicode.utf8ToUtf16LeStringLiteral("Irony"),
        w32.WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
        null,
        null,
        0,
    ) orelse {
        misc.error_context.new("{f}", .{os.Error.getLast()});
        misc.error_context.append("WinHttpOpen returned null.", .{});
        return error.OsError;
    };
    defer _ = w32.WinHttpCloseHandle(session);

    const connection = w32.WinHttpConnect(
        session,
        std.unicode.utf8ToUtf16LeStringLiteral(host),
        w32.INTERNET_DEFAULT_HTTPS_PORT,
        0,
    ) orelse {
        misc.error_context.new("{f}", .{os.Error.getLast()});
        misc.error_context.append("WinHttpConnect returned null.", .{});
        return error.OsError;
    };
    defer _ = w32.WinHttpCloseHandle(connection);

    const request = w32.WinHttpOpenRequest(
        connection,
        std.unicode.utf8ToUtf16LeStringLiteral("GET"),
        std.unicode.utf8ToUtf16LeStringLiteral(path),
        null,
        null,
        null,
        w32.WINHTTP_FLAG_SECURE,
    ) orelse {
        misc.error_context.new("{f}", .{os.Error.getLast()});
        misc.error_context.append("WinHttpOpenRequest returned null.", .{});
        return error.OsError;
    };
    defer _ = w32.WinHttpCloseHandle(request);

    if (w32.WinHttpSendRequest(request, headers_utf16, headers_utf16.len, null, 0, 0, 0) == 0) {
        misc.error_context.new("{f}", .{os.Error.getLast()});
        misc.error_context.append("WinHttpSendRequest returned 0.", .{});
        return error.OsError;
    }
    if (w32.WinHttpReceiveResponse(request, null) == 0) {
        misc.error_context.new("{f}", .{os.Error.getLast()});
        misc.error_context.append("WinHttpReceiveResponse returned 0.", .{});
        return error.OsError;
    }

    var status_code: u32 = 0;
    var status_code_size: u32 = @sizeOf(u32);
    if (w32.WinHttpQueryHeaders(
        request,
        w32.WINHTTP_QUERY_STATUS_CODE | w32.WINHTTP_QUERY_FLAG_NUMBER,
        null,
        &status_code,
        &status_code_size,
        null,
    ) == 0) {
        misc.error_context.new("{f}", .{os.Error.getLast()});
        misc.error_context.append("WinHttpQueryHeaders returned 0.", .{});
        return error.OsError;
    }
    if (status_code != 200) {
        misc.error_context.new("Server responded with status code: {}", .{status_code});
        return error.BadResponseStatus;
    }

    var body: std.ArrayList(u8) = .empty;
    errdefer body.deinit(allocator);
    while (true) {
        body.ensureUnusedCapacity(allocator, 4096) catch |err| {
            misc.error_context.new("Failed to allocate memory for the response body.", .{});
            return err;
        };
        const unused = body.unusedCapacitySlice();
        var bytes_read: u32 = 0;
        if (w32.WinHttpReadData(request, unused.ptr, @intCast(unused.len), &bytes_read) == 0) {
            misc.error_context.new("{f}", .{os.Error.getLast()});
            misc.error_context.append("WinHttpReadData returned 0.", .{});
            return error.OsError;
        }
        if (bytes_read == 0) {
            break;
        }
        body.items.len += bytes_read;
        if (body.items.len > max_body_size) {
            misc.error_context.new("Response body exceeded the maximum size of {} bytes.", .{max_body_size});
            return error.StreamTooLong;
        }
    }
    return body.toOwnedSlice(allocator) catch |err| {
        misc.error_context.new("Failed to allocate memory for the response body.", .{});
        return err;
    };
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

test "getExecutableTimestamp should return a value greater than 1 day ago and less than or equal to now" {
    const timestamp = try getExecutableTimestamp();
    const now: u32 = @intCast(std.Io.Clock.real.now(testing.io).toSeconds());
    const day_ago = now - std.time.s_per_day;
    try testing.expect(timestamp > day_ago);
    try testing.expect(timestamp <= now);
}

test "systemTimeFromNano should return correct value when time zone is UTC" {
    try testing.expectEqual(w32.SYSTEMTIME{
        .wYear = 2020,
        .wMonth = 1,
        .wDayOfWeek = 4,
        .wDay = 2,
        .wHour = 3,
        .wMinute = 4,
        .wSecond = 5,
        .wMilliseconds = 123,
    }, systemTimeFromNano(1577934245123456789, .utc));
    try testing.expectEqual(w32.SYSTEMTIME{
        .wYear = 1601,
        .wMonth = 1,
        .wDayOfWeek = 1,
        .wDay = 1,
        .wHour = 0,
        .wMinute = 0,
        .wSecond = 0,
        .wMilliseconds = 0,
    }, systemTimeFromNano(-11644473600000000000, .utc));
}

test "systemTimeFromNano should offset local time from UTC by the bias of the current time zone" {
    var time_zone_information: w32.TIME_ZONE_INFORMATION = undefined;
    const time_zone_id = w32.GetTimeZoneInformation(&time_zone_information);
    try testing.expect(time_zone_id != std.math.maxInt(u32)); // TIME_ZONE_ID_INVALID
    const bias_minutes = time_zone_information.Bias + switch (time_zone_id) {
        w32.TIME_ZONE_ID_DAYLIGHT => time_zone_information.DaylightBias,
        else => time_zone_information.StandardBias,
    };

    const now = std.Io.Clock.real.now(testing.io).nanoseconds;
    const utc_time = try systemTimeFromNano(now, .utc);
    const local_time = try systemTimeFromNano(now, .local);

    var utc_file_time: w32.FILETIME = undefined;
    var local_file_time: w32.FILETIME = undefined;
    try testing.expect(w32.SystemTimeToFileTime(&utc_time, &utc_file_time) != 0);
    try testing.expect(w32.SystemTimeToFileTime(&local_time, &local_file_time) != 0);
    const utc_ticks = (@as(i64, utc_file_time.dwHighDateTime) << 32) | utc_file_time.dwLowDateTime;
    const local_ticks = (@as(i64, local_file_time.dwHighDateTime) << 32) | local_file_time.dwLowDateTime;
    const ticks_per_minute = 60 * (std.time.ns_per_s / 100);
    try testing.expectEqual(-bias_minutes, @divExact(local_ticks - utc_ticks, ticks_per_minute));
}

test "systemTimeFromNano should return error when timestamp is before year 1601" {
    try testing.expectError(error.OutOfRange, systemTimeFromNano(-11644473600000000001, .utc));
    try testing.expectError(error.OutOfRange, systemTimeFromNano(-11644473600000000001, .local));
}
