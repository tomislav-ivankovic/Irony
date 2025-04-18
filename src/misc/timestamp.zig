const std = @import("std");
const lib_c_time = @import("lib_c_time");
const misc = @import("root.zig");

pub const TimeZone = enum {
    utc,
    local,
};

pub const Timestamp = struct {
    year: i32,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    nano: u32,

    const Self = @This();

    pub fn fromNano(nano_timestamp: i128, time_zone: TimeZone) !Self {
        const cFunction: *const @TypeOf(lib_c_time.gmtime) = switch (time_zone) {
            .utc => lib_c_time.gmtime,
            .local => lib_c_time.localtime,
        };
        const c_function_name = switch (time_zone) {
            .utc => "gmtime",
            .local => "localtime",
        };
        const sec_timestamp: lib_c_time.time_t = @intCast(@divFloor(nano_timestamp, std.time.ns_per_s));
        const time_struct_pointer = cFunction(&sec_timestamp) orelse {
            misc.errorContext().newFmt("C function {s} returned null.", .{c_function_name});
            return error.CError;
        };
        const time_struct: lib_c_time.struct_tm = time_struct_pointer.*;
        return Self{
            .year = time_struct.tm_year + 1900,
            .month = @intCast(time_struct.tm_mon + 1),
            .day = @intCast(time_struct.tm_mday),
            .hour = @intCast(time_struct.tm_hour),
            .minute = @intCast(time_struct.tm_min),
            .second = @intCast(time_struct.tm_sec),
            .nano = @intCast(@mod(nano_timestamp, std.time.ns_per_s)),
        };
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
                "Invalid Timestamp format {{{s}}}. The only allowed format for Timestamp is {{}}.",
                .{fmt},
            ));
        }
        if (self.year < 0) {
            try writer.writeByte('-');
        }
        try writer.print(
            "{:0>4}-{:0>2}-{:0>2}T{:0>2}:{:0>2}:{:0>2}.{:0>9}",
            .{ @abs(self.year), self.month, self.day, self.hour, self.minute, self.second, self.nano },
        );
    }
};

const testing = std.testing;

test "fromNano should return correct value" {
    try testing.expectEqual(Timestamp{
        .year = 2020,
        .month = 1,
        .day = 2,
        .hour = 3,
        .minute = 4,
        .second = 5,
        .nano = 123456789,
    }, Timestamp.fromNano(1577934245123456789, .utc));
    try testing.expectEqual(Timestamp{
        .year = 2030,
        .month = 9,
        .day = 8,
        .hour = 7,
        .minute = 6,
        .second = 5,
        .nano = 987654321,
    }, Timestamp.fromNano(1915081565987654321, .utc));
}

test "should format timestamp correctly" {
    const timestamp_1 = try std.fmt.allocPrint(testing.allocator, "{}", .{Timestamp{
        .year = 2020,
        .month = 1,
        .day = 2,
        .hour = 3,
        .minute = 4,
        .second = 5,
        .nano = 6,
    }});
    defer testing.allocator.free(timestamp_1);
    try testing.expectEqualStrings("2020-01-02T03:04:05.000000006", timestamp_1);
    const timestamp_2 = try std.fmt.allocPrint(testing.allocator, "{}", .{Timestamp{
        .year = 2030,
        .month = 12,
        .day = 31,
        .hour = 23,
        .minute = 59,
        .second = 58,
        .nano = 123456789,
    }});
    defer testing.allocator.free(timestamp_2);
    try testing.expectEqualStrings("2030-12-31T23:59:58.123456789", timestamp_2);
}
