const std = @import("std");
const misc = @import("root.zig");
const os = @import("../os/root.zig");

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
        const system_time = os.systemTimeFromNano(nano_timestamp, time_zone) catch |err| {
            misc.error_context.append("Failed to convert nano timestamp to system time.", .{});
            return err;
        };
        return Self{
            .year = system_time.wYear,
            .month = @intCast(system_time.wMonth),
            .day = @intCast(system_time.wDay),
            .hour = @intCast(system_time.wHour),
            .minute = @intCast(system_time.wMinute),
            .second = @intCast(system_time.wSecond),
            .nano = @intCast(@mod(nano_timestamp, std.time.ns_per_s)),
        };
    }

    pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
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
    const timestamp_1 = try std.fmt.allocPrint(testing.allocator, "{f}", .{Timestamp{
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
    const timestamp_2 = try std.fmt.allocPrint(testing.allocator, "{f}", .{Timestamp{
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
