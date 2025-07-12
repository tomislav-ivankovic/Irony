const std = @import("std");

pub const PauseDetectorConfig = struct {
    nanoTimestamp: *const fn () i128 = std.time.nanoTimestamp,
    no_change_time_for_pause: i128 = 33 * std.time.ns_per_ms,
};

pub fn PauseDetector(comptime config: PauseDetectorConfig) type {
    return struct {
        last_change_timestamp: i128 = 0,
        last_player_1_frame_number: ?u32 = null,
        last_player_2_frame_number: ?u32 = null,

        const Self = @This();

        pub fn update(self: *Self, player_1_frame_number: ?u32, player_2_frame_number: ?u32) void {
            const current_timestamp = config.nanoTimestamp();
            const changed = player_1_frame_number != self.last_player_1_frame_number or
                player_2_frame_number != self.last_player_2_frame_number or
                (player_1_frame_number == null and player_2_frame_number == null);
            if (changed) {
                self.last_change_timestamp = current_timestamp;
            }
            self.last_player_1_frame_number = player_1_frame_number;
            self.last_player_2_frame_number = player_2_frame_number;
        }

        pub fn isPaused(self: *const Self) bool {
            const current_timestamp = config.nanoTimestamp();
            const time = current_timestamp - self.last_change_timestamp;
            return time >= config.no_change_time_for_pause;
        }
    };
}

const testing = std.testing;

test "should report paused only if enough time passes without a change" {
    const NanoTimestamp = struct {
        var value: i128 = 0;
        fn call() i128 {
            return value;
        }
    };
    var detector: PauseDetector(.{
        .nanoTimestamp = NanoTimestamp.call,
        .no_change_time_for_pause = 10,
    }) = .{};

    detector.update(null, null);

    try testing.expectEqual(false, detector.isPaused());
    NanoTimestamp.value = 1;
    try testing.expectEqual(false, detector.isPaused());
    NanoTimestamp.value = 10;
    try testing.expectEqual(true, detector.isPaused());

    detector.update(1, null);

    try testing.expectEqual(false, detector.isPaused());
    NanoTimestamp.value = 11;
    try testing.expectEqual(false, detector.isPaused());
    NanoTimestamp.value = 20;
    try testing.expectEqual(true, detector.isPaused());

    detector.update(1, null);

    try testing.expectEqual(true, detector.isPaused());
    NanoTimestamp.value = 21;
    try testing.expectEqual(true, detector.isPaused());
    NanoTimestamp.value = 30;
    try testing.expectEqual(true, detector.isPaused());

    detector.update(2, null);

    try testing.expectEqual(false, detector.isPaused());
    NanoTimestamp.value = 31;
    try testing.expectEqual(false, detector.isPaused());
    NanoTimestamp.value = 40;
    try testing.expectEqual(true, detector.isPaused());

    detector.update(2, 1);

    try testing.expectEqual(false, detector.isPaused());
    NanoTimestamp.value = 41;
    try testing.expectEqual(false, detector.isPaused());
    NanoTimestamp.value = 50;
    try testing.expectEqual(true, detector.isPaused());

    detector.update(2, 1);

    try testing.expectEqual(true, detector.isPaused());
    NanoTimestamp.value = 51;
    try testing.expectEqual(true, detector.isPaused());
    NanoTimestamp.value = 60;
    try testing.expectEqual(true, detector.isPaused());

    detector.update(2, 2);

    try testing.expectEqual(false, detector.isPaused());
    NanoTimestamp.value = 61;
    try testing.expectEqual(false, detector.isPaused());
    NanoTimestamp.value = 70;
    try testing.expectEqual(true, detector.isPaused());
}
