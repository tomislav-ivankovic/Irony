const std = @import("std");
const core = @import("root.zig");

pub const PauseDetectorConfig = struct {
    nanoTimestamp: *const fn () i128 = std.time.nanoTimestamp,
    no_update_time_for_pause: i128 = 33 * std.time.ns_per_ms,
};

pub fn PauseDetector(comptime config: PauseDetectorConfig) type {
    return struct {
        last_update_timestamp: i128 = 0,

        const Self = @This();

        pub fn update(self: *Self) void {
            self.last_update_timestamp = config.nanoTimestamp();
        }

        pub fn isPaused(self: *const Self) bool {
            const time = config.nanoTimestamp() - self.last_update_timestamp;
            return time >= config.no_update_time_for_pause;
        }
    };
}

const testing = std.testing;

test "should report paused only if enough time passes without update" {
    const NanoTimestamp = struct {
        var value: i128 = 0;
        fn call() i128 {
            return value;
        }
    };
    var detector: PauseDetector(.{
        .nanoTimestamp = NanoTimestamp.call,
        .no_update_time_for_pause = 10,
    }) = .{};

    detector.update();

    try testing.expectEqual(false, detector.isPaused());
    NanoTimestamp.value = 1;
    try testing.expectEqual(false, detector.isPaused());
    NanoTimestamp.value = 10;
    try testing.expectEqual(true, detector.isPaused());

    detector.update();

    try testing.expectEqual(false, detector.isPaused());
    NanoTimestamp.value = 11;
    try testing.expectEqual(false, detector.isPaused());
    NanoTimestamp.value = 20;
    try testing.expectEqual(true, detector.isPaused());
}
