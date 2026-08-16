const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("root.zig");

pub const Frame = struct {
    irony_version: ?model.IronyVersion = null,
    game: ?model.Game = null,
    game_version: model.GameVersion = .empty,
    source: ?model.Source = null,
    match_phase: ?model.MatchPhase = null,
    rounds_needed_to_win: ?u32 = null,
    frames_since_round_start: ?u32 = null,
    frames_left_in_round: ?u32 = null,
    floor_z: ?f32 = null,
    players: [2]model.Player = .{ .{}, .{} },
    camera: ?model.Camera = null,
    walls: model.Walls = .empty,
    floor_gimmicks: model.FloorGimmicks = .empty,
    left_player_id: model.PlayerId = .player_1,
    main_player_id: model.PlayerId = .player_1,

    const Self = @This();

    pub fn getPlayerById(
        self: anytype,
        id: model.PlayerId,
    ) sdk.misc.SelfBasedPointer(@TypeOf(self), Self, model.Player) {
        switch (id) {
            .player_1 => return &self.players[0],
            .player_2 => return &self.players[1],
        }
    }

    pub fn getPlayerBySide(
        self: anytype,
        side: model.PlayerSide,
    ) sdk.misc.SelfBasedPointer(@TypeOf(self), Self, model.Player) {
        return switch (side) {
            .left => return self.getPlayerById(self.left_player_id),
            .right => return self.getPlayerById(self.left_player_id.getOther()),
        };
    }

    pub fn getPlayerByRole(
        self: anytype,
        role: model.PlayerRole,
    ) sdk.misc.SelfBasedPointer(@TypeOf(self), Self, model.Player) {
        return switch (role) {
            .main => return self.getPlayerById(self.main_player_id),
            .secondary => return self.getPlayerById(self.main_player_id.getOther()),
        };
    }
};

const testing = std.testing;

test "Frame.getPlayerById should return correct player" {
    const frame = Frame{};
    try testing.expectEqual(&frame.players[0], frame.getPlayerById(.player_1));
    try testing.expectEqual(&frame.players[1], frame.getPlayerById(.player_2));
}

test "Frame.getPlayerBySide should return correct player" {
    const frame_1 = Frame{ .left_player_id = .player_1 };
    const frame_2 = Frame{ .left_player_id = .player_2 };
    try testing.expectEqual(&frame_1.players[0], frame_1.getPlayerBySide(.left));
    try testing.expectEqual(&frame_1.players[1], frame_1.getPlayerBySide(.right));
    try testing.expectEqual(&frame_2.players[1], frame_2.getPlayerBySide(.left));
    try testing.expectEqual(&frame_2.players[0], frame_2.getPlayerBySide(.right));
}

test "Frame.getPlayerByRole should return correct player" {
    const frame_1 = Frame{ .main_player_id = .player_1 };
    const frame_2 = Frame{ .main_player_id = .player_2 };
    try testing.expectEqual(&frame_1.players[0], frame_1.getPlayerByRole(.main));
    try testing.expectEqual(&frame_1.players[1], frame_1.getPlayerByRole(.secondary));
    try testing.expectEqual(&frame_2.players[1], frame_2.getPlayerByRole(.main));
    try testing.expectEqual(&frame_2.players[0], frame_2.getPlayerByRole(.secondary));
}
