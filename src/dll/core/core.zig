const std = @import("std");
const core = @import("../core/root.zig");
const game = @import("../game/root.zig");
const model = @import("../model/root.zig");

pub const Core = struct {
    frame_detector: core.FrameDetector,
    pause_detector: core.PauseDetector(.{}),
    capturer: core.Capturer,
    attack_detector: core.AttackDetector,
    hit_detector: core.HitDetector,
    controller: core.Controller,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .frame_detector = .{},
            .pause_detector = .{},
            .capturer = .{},
            .attack_detector = .{},
            .hit_detector = .{},
            .controller = core.Controller.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.controller.deinit();
    }

    pub fn tick(
        self: *Self,
        game_memory: *const game.Memory,
        context: anytype,
        processFrame: *const fn (context: @TypeOf(context), frame: *const model.Frame) void,
    ) void {
        const player_1 = game_memory.player_1.takePartialCopy();
        const player_2 = game_memory.player_2.takePartialCopy();
        if (!self.frame_detector.detect(&player_1, &player_2)) {
            return;
        }
        self.pause_detector.update();
        var frame = self.capturer.captureFrame(&.{ .player_1 = player_1, .player_2 = player_2 });
        self.attack_detector.detect(&frame);
        self.hit_detector.detect(&frame);
        self.controller.processFrame(&frame, context, processFrame);
    }

    pub fn update(
        self: *Self,
        delta_time: f32,
        context: anytype,
        processFrame: *const fn (context: @TypeOf(context), frame: *const model.Frame) void,
    ) void {
        self.controller.update(delta_time, context, processFrame);
    }
};
