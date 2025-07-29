const std = @import("std");

pub const TimerConfig = struct {
    nanoTimestamp: *const fn () i128 = std.time.nanoTimestamp,
    first_delta_time: f32 = 1.0 / 60.0,
};

pub fn Timer(config: TimerConfig) type {
    return struct {
        last_measurement_time: ?i128 = null,

        const Self = @This();

        pub fn measureDeltaTime(self: *Self) f32 {
            const time_now = config.nanoTimestamp();
            const delta_time = if (self.last_measurement_time) |last_time| b: {
                const delta_nano: f32 = @floatFromInt(time_now - last_time);
                const delta_sec = delta_nano / std.time.ns_per_s;
                break :b delta_sec;
            } else config.first_delta_time;
            self.last_measurement_time = time_now;
            return delta_time;
        }
    };
}

const testing = std.testing;

test "should measure delta time correctly" {
    const nanoTimestamp = struct {
        var called_times: usize = 0;
        fn call() i128 {
            const return_value: i128 = switch (called_times) {
                0 => 0,
                1 => 1 * std.time.ns_per_s,
                2 => 3 * std.time.ns_per_s,
                else => 7 * std.time.ns_per_s,
            };
            called_times += 1;
            return return_value;
        }
    }.call;
    var timer = Timer(.{
        .nanoTimestamp = nanoTimestamp,
        .first_delta_time = 0.5,
    }){};

    try testing.expectEqual(0.5, timer.measureDeltaTime());
    try testing.expectEqual(1.0, timer.measureDeltaTime());
    try testing.expectEqual(2.0, timer.measureDeltaTime());
    try testing.expectEqual(4.0, timer.measureDeltaTime());
    try testing.expectEqual(0.0, timer.measureDeltaTime());
}
