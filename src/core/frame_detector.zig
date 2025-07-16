const std = @import("std");
const misc = @import("../misc/root.zig");
const game = @import("../game/root.zig");

pub const FrameDetector = struct {
    last_player_1: Player = .{},
    last_player_2: Player = .{},

    const Self = @This();
    const Player = struct {
        frames_since_round_start: ?u32 = null,
        current_frame_number: ?u32 = null,
    };

    pub fn detect(
        self: *Self,
        player_1: *const misc.Partial(game.Player),
        player_2: *const misc.Partial(game.Player),
    ) bool {
        const is_new_frame = player_1.frames_since_round_start != self.last_player_1.frames_since_round_start or
            player_2.frames_since_round_start != self.last_player_2.frames_since_round_start or
            player_1.current_frame_number != self.last_player_1.current_frame_number or
            player_2.current_frame_number != self.last_player_2.current_frame_number or
            (player_1.frames_since_round_start == null and
                player_2.frames_since_round_start == null and
                player_1.current_frame_number == null and
                player_2.current_frame_number == null);
        self.last_player_1.frames_since_round_start = player_1.frames_since_round_start;
        self.last_player_1.current_frame_number = player_1.current_frame_number;
        self.last_player_2.frames_since_round_start = player_2.frames_since_round_start;
        self.last_player_2.current_frame_number = player_2.current_frame_number;
        return is_new_frame;
    }
};

const testing = std.testing;

test "should detect frames only when frame values are changing or every frame value is null" {
    const detect = struct {
        var frame_detector = FrameDetector{};
        fn call(frame_1: ?u32, frame_2: ?u32, frame_3: ?u32, frame_4: ?u32) bool {
            return frame_detector.detect(
                &.{ .frames_since_round_start = frame_1, .current_frame_number = frame_2 },
                &.{ .frames_since_round_start = frame_3, .current_frame_number = frame_4 },
            );
        }
    }.call;
    try testing.expectEqual(true, detect(null, null, null, null));
    try testing.expectEqual(true, detect(null, null, null, null));
    try testing.expectEqual(true, detect(1, null, null, null));
    try testing.expectEqual(false, detect(1, null, null, null));
    try testing.expectEqual(true, detect(2, null, null, null));
    try testing.expectEqual(false, detect(2, null, null, null));
    try testing.expectEqual(true, detect(2, 1, null, null));
    try testing.expectEqual(false, detect(2, 1, null, null));
    try testing.expectEqual(true, detect(2, 2, null, null));
    try testing.expectEqual(false, detect(2, 2, null, null));
    try testing.expectEqual(true, detect(2, 2, 1, null));
    try testing.expectEqual(false, detect(2, 2, 1, null));
    try testing.expectEqual(true, detect(2, 2, 2, null));
    try testing.expectEqual(false, detect(2, 2, 2, null));
    try testing.expectEqual(true, detect(2, 2, 2, 1));
    try testing.expectEqual(false, detect(2, 2, 2, 1));
    try testing.expectEqual(true, detect(2, 2, 2, 2));
    try testing.expectEqual(false, detect(2, 2, 2, 2));
}
