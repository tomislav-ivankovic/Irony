const std = @import("std");
const build_info = @import("build_info");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const game = @import("../game/root.zig");

pub const ToolAssistedInput = struct {
    allocator: std.mem.Allocator,
    sequence: Sequence,
    mode: Mode,
    play_config: PlayConfig,

    const Self = @This();
    pub const Sequence = std.ArrayList(SequenceItem);
    pub const SequenceItem = struct {
        player_1: model.Input = .{},
        player_2: model.Input = .{},
    };
    pub const Mode = union(enum) {
        idle: void,
        play: Play,

        pub const Play = struct {
            current_index: usize,
        };
    };
    pub const PlayConfig = struct {
        start_index: usize = 0,
        length: usize = std.math.maxInt(usize),
        enable_player_1: bool = true,
        enable_player_2: bool = true,
        repeat: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .sequence = .empty,
            .mode = .idle,
            .play_config = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.sequence.deinit(self.allocator);
    }

    pub fn processFrame(self: *Self, input_override: *game.InputOverride, source_maybe: ?model.Source) void {
        const source = source_maybe orelse {
            input_override.player_1 = null;
            input_override.player_2 = null;
            self.mode = .idle;
            return;
        };
        switch (source) {
            .practice, .replay_playback => {},
            .live_game, .replay_loading => {
                input_override.player_1 = null;
                input_override.player_2 = null;
                self.mode = .idle;
                return;
            },
        }
        switch (self.mode) {
            .idle => {
                input_override.player_1 = null;
                input_override.player_2 = null;
            },
            .play => |*mode| {
                const config = &self.play_config;
                const end_index = @min(config.start_index +| config.length, self.sequence.items.len);
                if (mode.current_index >= end_index) {
                    if (config.repeat) {
                        mode.current_index = config.start_index;
                    } else {
                        self.mode = .idle;
                        input_override.player_1 = null;
                        input_override.player_2 = null;
                        return;
                    }
                }
                const previous_input = switch (mode.current_index) {
                    0 => SequenceItem{},
                    else => self.sequence.items[mode.current_index - 1],
                };
                const current_input = self.sequence.items[mode.current_index];
                input_override.player_1 = switch (config.enable_player_1) {
                    true => .{
                        .previous_input = previous_input.player_1,
                        .current_input = current_input.player_1,
                    },
                    false => null,
                };
                input_override.player_2 = switch (config.enable_player_2) {
                    true => .{
                        .previous_input = previous_input.player_2,
                        .current_input = current_input.player_2,
                    },
                    false => null,
                };
                mode.current_index += 1;
            },
        }
    }

    pub fn play(self: *Self) void {
        if (self.sequence.items.len == 0) {
            return;
        }
        self.mode = .{ .play = .{ .current_index = self.play_config.start_index } };
    }

    pub fn stop(self: *Self) void {
        self.mode = .idle;
    }
};

const testing = std.testing;

test "should not override inputs when idle" {
    var input_override = game.InputOverride{};
    var input = ToolAssistedInput.init(testing.allocator);
    defer input.deinit();

    input.processFrame(&input_override, .practice);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);
}

test "should override inputs with input sequence when put in play mode" {
    var input_override = game.InputOverride{};
    var input = ToolAssistedInput.init(testing.allocator);
    defer input.deinit();

    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_1 = true },
        .player_2 = .{ .button_2 = true },
    });
    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_3 = true },
        .player_2 = .{ .button_4 = true },
    });

    input.play();

    input.processFrame(&input_override, .practice);
    try testing.expect(input_override.player_1 != null);
    try testing.expect(input_override.player_2 != null);
    try testing.expectEqual(model.Input{}, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{}, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .button_1 = true }, input_override.player_1.?.current_input);
    try testing.expectEqual(model.Input{ .button_2 = true }, input_override.player_2.?.current_input);

    input.processFrame(&input_override, .practice);
    try testing.expect(input_override.player_1 != null);
    try testing.expect(input_override.player_2 != null);
    try testing.expectEqual(model.Input{ .button_1 = true }, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{ .button_2 = true }, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .button_3 = true }, input_override.player_1.?.current_input);
    try testing.expectEqual(model.Input{ .button_4 = true }, input_override.player_2.?.current_input);

    input.processFrame(&input_override, .practice);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);
}

test "should not override inputs when frame is captured from a disallowed source" {
    var input_override = game.InputOverride{};
    var input = ToolAssistedInput.init(testing.allocator);
    defer input.deinit();

    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_1 = true },
        .player_2 = .{ .button_2 = true },
    });
    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_3 = true },
        .player_2 = .{ .button_4 = true },
    });

    input.play();
    input.processFrame(&input_override, null);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);

    input.play();
    input.processFrame(&input_override, .live_game);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);

    input.play();
    input.processFrame(&input_override, .replay_loading);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);
}

test "should stop overriding inputs when play mode is stopped" {
    var input_override = game.InputOverride{};
    var input = ToolAssistedInput.init(testing.allocator);
    defer input.deinit();

    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_1 = true },
        .player_2 = .{ .button_2 = true },
    });
    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_3 = true },
        .player_2 = .{ .button_4 = true },
    });

    input.play();

    input.processFrame(&input_override, .practice);
    try testing.expect(input_override.player_1 != null);
    try testing.expect(input_override.player_2 != null);
    try testing.expectEqual(model.Input{}, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{}, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .button_1 = true }, input_override.player_1.?.current_input);
    try testing.expectEqual(model.Input{ .button_2 = true }, input_override.player_2.?.current_input);

    input.stop();

    input.processFrame(&input_override, .practice);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);
}

test "should override inputs with part of sequence when start index and length are used" {
    var input_override = game.InputOverride{};
    var input = ToolAssistedInput.init(testing.allocator);
    defer input.deinit();

    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_1 = true },
        .player_2 = .{ .button_2 = true },
    });
    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_3 = true },
        .player_2 = .{ .button_4 = true },
    });
    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .up = true },
        .player_2 = .{ .down = true },
    });
    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .left = true },
        .player_2 = .{ .right = true },
    });

    input.play_config.start_index = 1;
    input.play_config.length = 2;
    input.play();

    input.processFrame(&input_override, .practice);
    try testing.expect(input_override.player_1 != null);
    try testing.expect(input_override.player_2 != null);
    try testing.expectEqual(model.Input{ .button_1 = true }, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{ .button_2 = true }, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .button_3 = true }, input_override.player_1.?.current_input);
    try testing.expectEqual(model.Input{ .button_4 = true }, input_override.player_2.?.current_input);

    input.processFrame(&input_override, .practice);
    try testing.expect(input_override.player_1 != null);
    try testing.expect(input_override.player_2 != null);
    try testing.expectEqual(model.Input{ .button_3 = true }, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{ .button_4 = true }, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .up = true }, input_override.player_1.?.current_input);
    try testing.expectEqual(model.Input{ .down = true }, input_override.player_2.?.current_input);

    input.processFrame(&input_override, .practice);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);
}

test "should override inputs only for enabled players when enable player values are used" {
    var input_override = game.InputOverride{};
    var input = ToolAssistedInput.init(testing.allocator);
    defer input.deinit();

    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_1 = true },
        .player_2 = .{ .button_2 = true },
    });
    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_3 = true },
        .player_2 = .{ .button_4 = true },
    });

    input.processFrame(&input_override, .practice);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);

    input.play_config.enable_player_1 = true;
    input.play_config.enable_player_2 = false;
    input.play();

    input.processFrame(&input_override, .practice);
    try testing.expect(input_override.player_1 != null);
    try testing.expectEqual(null, input_override.player_2);
    try testing.expectEqual(model.Input{}, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{ .button_1 = true }, input_override.player_1.?.current_input);

    input.processFrame(&input_override, .practice);
    try testing.expect(input_override.player_1 != null);
    try testing.expectEqual(null, input_override.player_2);
    try testing.expectEqual(model.Input{ .button_1 = true }, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{ .button_3 = true }, input_override.player_1.?.current_input);

    input.processFrame(&input_override, .practice);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);

    input.play_config.enable_player_1 = false;
    input.play_config.enable_player_2 = true;
    input.play();

    input.processFrame(&input_override, .practice);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expect(input_override.player_2 != null);
    try testing.expectEqual(model.Input{}, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .button_2 = true }, input_override.player_2.?.current_input);

    input.processFrame(&input_override, .practice);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expect(input_override.player_2 != null);
    try testing.expectEqual(model.Input{ .button_2 = true }, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .button_4 = true }, input_override.player_2.?.current_input);

    input.processFrame(&input_override, .practice);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);
}

test "should repeat the input sequence until stopped when repeat is set to true" {
    var input_override = game.InputOverride{};
    var input = ToolAssistedInput.init(testing.allocator);
    defer input.deinit();

    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_1 = true },
        .player_2 = .{ .button_2 = true },
    });
    try input.sequence.append(input.allocator, .{
        .player_1 = .{ .button_3 = true },
        .player_2 = .{ .button_4 = true },
    });

    input.play_config.repeat = true;
    input.play();

    input.processFrame(&input_override, .practice);
    try testing.expect(input_override.player_1 != null);
    try testing.expect(input_override.player_2 != null);
    try testing.expectEqual(model.Input{}, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{}, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .button_1 = true }, input_override.player_1.?.current_input);
    try testing.expectEqual(model.Input{ .button_2 = true }, input_override.player_2.?.current_input);

    input.processFrame(&input_override, .practice);
    try testing.expect(input_override.player_1 != null);
    try testing.expect(input_override.player_2 != null);
    try testing.expectEqual(model.Input{ .button_1 = true }, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{ .button_2 = true }, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .button_3 = true }, input_override.player_1.?.current_input);
    try testing.expectEqual(model.Input{ .button_4 = true }, input_override.player_2.?.current_input);

    input.processFrame(&input_override, .practice);
    try testing.expectEqual(model.Input{}, input_override.player_1.?.previous_input);
    try testing.expectEqual(model.Input{}, input_override.player_2.?.previous_input);
    try testing.expectEqual(model.Input{ .button_1 = true }, input_override.player_1.?.current_input);
    try testing.expectEqual(model.Input{ .button_2 = true }, input_override.player_2.?.current_input);

    input.stop();

    input.processFrame(&input_override, .practice);
    try testing.expectEqual(null, input_override.player_1);
    try testing.expectEqual(null, input_override.player_2);
}
