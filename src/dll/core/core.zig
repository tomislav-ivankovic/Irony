const std = @import("std");
const build_info = @import("build_info");
const core = @import("../core/root.zig");
const game = @import("../game/root.zig");
const model = @import("../model/root.zig");

pub const Core = struct {
    frame_detector: game.FrameDetector,
    capturer: game.Capturer(build_info.game),
    pause_detector: core.PauseDetector(.{}),
    hit_detector: core.HitDetector,
    move_detector: core.MoveDetector,
    move_measurer: core.MoveMeasurer,
    controller: core.Controller,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .frame_detector = .{},
            .capturer = .{},
            .pause_detector = .{},
            .hit_detector = .{},
            .move_detector = .{},
            .move_measurer = .{},
            .controller = core.Controller.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.controller.deinit();
    }

    pub fn tick(
        self: *Self,
        game_memory: *const game.Memory(build_info.game),
        context: anytype,
        processFrame: *const fn (context: @TypeOf(context), frame: *const model.Frame) void,
    ) void {
        const player_1 = game_memory.player_1.takePartialCopy();
        const player_2 = game_memory.player_2.takePartialCopy();
        if (!self.frame_detector.detect(build_info.game, &player_1, &player_2)) {
            return;
        }
        const camera = game_memory.camera.takeCopy();
        var frame = self.capturer.captureFrame(&.{ .player_1 = player_1, .player_2 = player_2, .camera = camera });
        self.pause_detector.update();
        self.hit_detector.detect(&frame);
        self.move_detector.detect(&frame);
        self.move_measurer.measure(&frame);
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
