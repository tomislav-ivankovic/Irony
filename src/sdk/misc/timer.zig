const std = @import("std");

pub const Timer = struct {
    last_measurement: ?std.Io.Timestamp = null,
    first_delta_time: f32 = 1.0 / 60.0,

    const Self = @This();

    pub fn measureDeltaTime(self: *Self, io: std.Io) f32 {
        const now = std.Io.Clock.awake.now(io);
        const delta_time = if (self.last_measurement) |last| b: {
            const delta_nano: f32 = @floatFromInt(now.nanoseconds - last.nanoseconds);
            const delta_sec = delta_nano / std.time.ns_per_s;
            break :b delta_sec;
        } else self.first_delta_time;
        self.last_measurement = now;
        return delta_time;
    }
};

const testing = std.testing;

test "should measure delta time correctly" {
    var io = testing.io;
    var vtable = io.vtable.*;
    vtable.now = struct {
        var called_times: usize = 0;
        fn call(_: ?*anyopaque, _: std.Io.Clock) std.Io.Timestamp {
            const seconds: i96 = switch (called_times) {
                0 => 0,
                1 => 1,
                2 => 3,
                else => 7,
            };
            called_times += 1;
            return .fromNanoseconds(seconds * std.time.ns_per_s);
        }
    }.call;
    io.vtable = &vtable;

    var timer = Timer{ .first_delta_time = 0.5 };

    try testing.expectEqual(0.5, timer.measureDeltaTime(io));
    try testing.expectEqual(1.0, timer.measureDeltaTime(io));
    try testing.expectEqual(2.0, timer.measureDeltaTime(io));
    try testing.expectEqual(4.0, timer.measureDeltaTime(io));
    try testing.expectEqual(0.0, timer.measureDeltaTime(io));
}
