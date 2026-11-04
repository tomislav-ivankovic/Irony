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

    pub fn detect(self: *Self, comptime game_id: build_info.Game, game_memory: *const game.Memory(game_id)) bool {
        const player_1 = game_memory.player_1.toConstPointer() orelse return false;
        const player_2 = game_memory.player_2.toConstPointer() orelse return false;
        const is_new_frame = player_1.frames_since_round_start != self.last_player_1.frames_since_round_start or
            player_2.frames_since_round_start != self.last_player_2.frames_since_round_start or
            player_1.animation_frame != self.last_player_1.animation_frame or
            player_2.animation_frame != self.last_player_2.animation_frame;
        self.last_player_1.frames_since_round_start = player_1.frames_since_round_start;
        self.last_player_1.animation_frame = player_1.animation_frame;
        self.last_player_2.frames_since_round_start = player_2.frames_since_round_start;
        self.last_player_2.animation_frame = player_2.animation_frame;
        return is_new_frame;
    }
};

const testing = std.testing;

test "should detect frames only when frame values are changing" {
    const detect = struct {
        var frame_detector = FrameDetector{};
        fn call(
            comptime game_id: build_info.Game,
            frame_1: u32,
            frame_2: u32,
            frame_3: u32,
            frame_4: u32,
        ) bool {
            const memory = game.Memory(game_id).testingInit(.{
                .player_1 = &.{ .frames_since_round_start = frame_1, .animation_frame = frame_2 },
                .player_2 = &.{ .frames_since_round_start = frame_3, .animation_frame = frame_4 },
            });
            return frame_detector.detect(game_id, &memory);
        }
    }.call;
    try testing.expectEqual(true, detect(.t7, 1, 2, 3, 4));
    try testing.expectEqual(false, detect(.t7, 1, 2, 3, 4));
    try testing.expectEqual(true, detect(.t7, 5, 2, 3, 4));
    try testing.expectEqual(false, detect(.t7, 5, 2, 3, 4));
    try testing.expectEqual(true, detect(.t7, 5, 6, 3, 4));
    try testing.expectEqual(false, detect(.t8, 5, 6, 3, 4));
    try testing.expectEqual(true, detect(.t8, 5, 6, 7, 4));
    try testing.expectEqual(false, detect(.t8, 5, 6, 7, 4));
    try testing.expectEqual(true, detect(.t8, 5, 6, 7, 8));
    try testing.expectEqual(false, detect(.t8, 5, 6, 7, 8));
}

test "should not detect frames when one or both of players are not found" {
    const detect = struct {
        var frame_detector = FrameDetector{};
        fn call(
            comptime game_id: build_info.Game,
            player_1: ?u32,
            player_2: ?u32,
        ) bool {
            const memory = game.Memory(game_id).testingInit(.{
                .player_1 = if (player_1) |p1| &.{ .frames_since_round_start = p1, .animation_frame = p1 } else null,
                .player_2 = if (player_2) |p2| &.{ .frames_since_round_start = p2, .animation_frame = p2 } else null,
            });
            return frame_detector.detect(game_id, &memory);
        }
    }.call;
    try testing.expectEqual(true, detect(.t7, 1, 1));
    try testing.expectEqual(true, detect(.t7, 2, 2));
    try testing.expectEqual(false, detect(.t7, null, 3));
    try testing.expectEqual(false, detect(.t7, null, 4));
    try testing.expectEqual(true, detect(.t7, 5, 5));
    try testing.expectEqual(true, detect(.t7, 6, 6));
    try testing.expectEqual(false, detect(.t7, 7, null));
    try testing.expectEqual(false, detect(.t7, 8, null));
    try testing.expectEqual(true, detect(.t7, 9, 9));
    try testing.expectEqual(true, detect(.t7, 10, 10));
    try testing.expectEqual(false, detect(.t7, null, null));
    try testing.expectEqual(false, detect(.t7, null, null));
    try testing.expectEqual(true, detect(.t7, 11, 11));
    try testing.expectEqual(true, detect(.t7, 12, 12));
}
