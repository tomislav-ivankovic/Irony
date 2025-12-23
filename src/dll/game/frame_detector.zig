const std = @import("std");
const build_info = @import("build_info");
const sdk = @import("../../sdk/root.zig");
const game = @import("root.zig");

pub const FrameDetector = struct {
    last_player_1: Player = .{},
    last_player_2: Player = .{},

    const Self = @This();
    const Player = struct {
        frames_since_round_start: ?u32 = null,
        animation_frame: ?u32 = null,
    };

    pub fn detect(
        self: *Self,
        comptime game_id: build_info.Game,
        player_1: *const sdk.misc.Partial(game.Player(game_id)),
        player_2: *const sdk.misc.Partial(game.Player(game_id)),
    ) bool {
        const is_new_frame = player_1.frames_since_round_start != self.last_player_1.frames_since_round_start or
            player_2.frames_since_round_start != self.last_player_2.frames_since_round_start or
            player_1.animation_frame != self.last_player_1.animation_frame or
            player_2.animation_frame != self.last_player_2.animation_frame or
            (player_1.frames_since_round_start == null and
                player_2.frames_since_round_start == null and
                player_1.animation_frame == null and
                player_2.animation_frame == null and
                !sdk.misc.areAllFieldsNull(player_1) and
                !sdk.misc.areAllFieldsNull(player_2));
        self.last_player_1.frames_since_round_start = player_1.frames_since_round_start;
        self.last_player_1.animation_frame = player_1.animation_frame;
        self.last_player_2.frames_since_round_start = player_2.frames_since_round_start;
        self.last_player_2.animation_frame = player_2.animation_frame;
        return is_new_frame;
    }
};

const testing = std.testing;

test "should detect frames only when frame values are changing or every frame value is null" {
    const detect = struct {
        var frame_detector = FrameDetector{};
        fn call(
            comptime game_id: build_info.Game,
            frame_1: ?u32,
            frame_2: ?u32,
            frame_3: ?u32,
            frame_4: ?u32,
            id_1: ?u32,
            id_2: ?u32,
        ) bool {
            return frame_detector.detect(
                game_id,
                &.{ .frames_since_round_start = frame_1, .animation_frame = frame_2, .character_id = id_1 },
                &.{ .frames_since_round_start = frame_3, .animation_frame = frame_4, .character_id = id_2 },
            );
        }
    }.call;
    try testing.expectEqual(false, detect(.t7, null, null, null, null, null, null));
    try testing.expectEqual(false, detect(.t8, null, null, null, null, null, null));
    try testing.expectEqual(true, detect(.t7, null, null, null, null, 1, 2));
    try testing.expectEqual(true, detect(.t8, null, null, null, null, 1, 2));
    try testing.expectEqual(true, detect(.t7, 1, null, null, null, null, null));
    try testing.expectEqual(false, detect(.t8, 1, null, null, null, null, null));
    try testing.expectEqual(true, detect(.t7, 2, null, null, null, null, null));
    try testing.expectEqual(false, detect(.t8, 2, null, null, null, null, null));
    try testing.expectEqual(true, detect(.t7, 2, 1, null, null, null, null));
    try testing.expectEqual(false, detect(.t8, 2, 1, null, null, null, null));
    try testing.expectEqual(true, detect(.t7, 2, 2, null, null, null, null));
    try testing.expectEqual(false, detect(.t8, 2, 2, null, null, null, null));
    try testing.expectEqual(true, detect(.t7, 2, 2, 1, null, null, null));
    try testing.expectEqual(false, detect(.t8, 2, 2, 1, null, null, null));
    try testing.expectEqual(true, detect(.t7, 2, 2, 2, null, null, null));
    try testing.expectEqual(false, detect(.t8, 2, 2, 2, null, null, null));
    try testing.expectEqual(true, detect(.t7, 2, 2, 2, 1, null, null));
    try testing.expectEqual(false, detect(.t8, 2, 2, 2, 1, null, null));
    try testing.expectEqual(true, detect(.t7, 2, 2, 2, 2, null, null));
    try testing.expectEqual(false, detect(.t8, 2, 2, 2, 2, null, null));
}
