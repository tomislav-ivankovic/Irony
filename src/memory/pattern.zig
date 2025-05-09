const std = @import("std");
const misc = @import("../misc/root.zig");
const memory = @import("root.zig");

pub const Pattern = struct {
    buffer: [max_len]?u8,
    len: usize,

    const Self = @This();
    const max_len = 64;

    pub inline fn fromComptime(comptime pattern: []const u8) Self {
        comptime {
            var buffer: [max_len]?u8 = undefined;
            var len: usize = 0;
            var previous_char: ?u8 = null;
            for (pattern) |char| {
                if (std.ascii.isWhitespace(char)) {
                    continue;
                } else if (char == '?') {
                    if (previous_char == '?') {
                        if (len >= max_len) {
                            @compileError(std.fmt.comptimePrint(
                                "Memory pattern \"{s}\" is longer then then maximum length: {}",
                                .{ pattern, max_len },
                            ));
                        }
                        buffer[len] = null;
                        len += 1;
                        previous_char = null;
                    } else if (previous_char) |p_char| {
                        @compileError(std.fmt.comptimePrint(
                            "Memory pattern \"{s}\" contains a mix of question mark and hex digit: {c}?",
                            .{ pattern, p_char },
                        ));
                    } else {
                        previous_char = char;
                    }
                } else if (std.ascii.isHex(char)) {
                    if (previous_char == '?') {
                        @compileError(std.fmt.comptimePrint(
                            "Memory pattern \"{s}\" contains a mix of question mark and hex digit: ?{c}",
                            .{ pattern, char },
                        ));
                    } else if (previous_char) |p_char| {
                        if (len >= max_len) {
                            @compileError(std.fmt.comptimePrint(
                                "Memory pattern \"{s}\" is longer then then maximum length: {}",
                                .{ pattern, max_len },
                            ));
                        }
                        const p_digit = if (std.ascii.isDigit(p_char)) p_char - '0' else std.ascii.toUpper(p_char) - 'A' + 10;
                        const digit = if (std.ascii.isDigit(char)) char - '0' else std.ascii.toUpper(char) - 'A' + 10;
                        buffer[len] = 16 * p_digit + digit;
                        len += 1;
                        previous_char = null;
                    } else {
                        previous_char = char;
                    }
                } else {
                    @compileError(std.fmt.comptimePrint(
                        "Memory pattern \"{s}\" contains a invalid character: {c}",
                        .{ pattern, char },
                    ));
                }
            }
            if (previous_char) |p_char| {
                @compileError(std.fmt.comptimePrint(
                    "Memory pattern \"{s}\" ends with a incomplete byte: {c}",
                    .{ pattern, p_char },
                ));
            }
            return .{ .buffer = buffer, .len = len };
        }
    }

    pub fn getBytes(self: *const Self) []const ?u8 {
        return self.buffer[0..self.len];
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
                "Invalid MemoryPattern format {{{s}}}. The only allowed format for MemoryPattern is {{}}.",
                .{fmt},
            ));
        }
        var is_first = true;
        for (self.getBytes()) |byte| {
            if (is_first) {
                is_first = false;
            } else {
                try writer.writeByte(' ');
            }
            if (byte) |b| {
                const major_digit = (b & 0xF0) / 16;
                const minor_digit = b & 0x0F;
                const major_char = if (major_digit < 10) '0' + major_digit else 'A' + major_digit - 10;
                const minor_char = if (minor_digit < 10) '0' + minor_digit else 'A' + minor_digit - 10;
                try writer.writeByte(major_char);
                try writer.writeByte(minor_char);
            } else {
                try writer.writeByte('?');
                try writer.writeByte('?');
            }
        }
    }

    pub fn findAddress(self: *const Self, range: memory.Range) !usize {
        if (!range.isReadable()) {
            misc.error_context.new("Provided memory range is not readable.", .{});
            return error.NotReadable;
        }
        const pattern = self.getBytes();
        for (range.base_address..(range.base_address + range.size_in_bytes - pattern.len + 1)) |address| {
            var found = true;
            for (0..pattern.len) |i| {
                const pattern_byte = pattern[i] orelse continue;
                const pointer: *const u8 = @ptrFromInt(address + i);
                const memory_byte = pointer.*;
                if (memory_byte != pattern_byte) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return address;
            }
        }
        misc.error_context.new("Memory pattern not found.", .{});
        return error.NotFound;
    }
};

const testing = std.testing;

test "fromComptime should construct a correct memory pattern" {
    const pattern = Pattern.fromComptime("00 ?? 12 AB Cd eF 3a b4 5C D6");
    const expected = &[_]?u8{ 0x00, null, 0x12, 0xAB, 0xCD, 0xEF, 0x3A, 0xB4, 0x5C, 0xD6 };
    try testing.expectEqualSlices(?u8, expected, pattern.getBytes());
}

test "should format correctly" {
    const pattern = Pattern.fromComptime("00 ?? 12 AB Cd eF 3a b4 5C D6");
    const string = try std.fmt.allocPrint(testing.allocator, "{}", .{pattern});
    defer testing.allocator.free(string);
    try testing.expectEqualStrings("00 ?? 12 AB CD EF 3A B4 5C D6", string);
}

test "findAddress should return correct address when pattern exists" {
    const data = [_]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9 };
    const range = memory.Range.fromPointer(&data);
    const pattern = Pattern.fromComptime("04 ?? ?? 07");
    try testing.expectEqual(@intFromPtr(&data[4]), pattern.findAddress(range));
}

test "findAddress should error when invalid memory range" {
    const range = memory.Range{
        .base_address = std.math.maxInt(usize) - 5,
        .size_in_bytes = 5,
    };
    const pattern = Pattern.fromComptime("?? ?? ?? ??");
    try testing.expectError(error.NotReadable, pattern.findAddress(range));
}

test "findAddress should error when pattern does not exist" {
    const data = [_]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9 };
    const range = memory.Range.fromPointer(&data);
    const pattern = Pattern.fromComptime("05 ?? ?? 02");
    try testing.expectError(error.NotFound, pattern.findAddress(range));
}
