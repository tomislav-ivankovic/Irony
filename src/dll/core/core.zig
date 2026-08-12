const std = @import("std");
const build_info = @import("build_info");
const sdk = @import("../../sdk/root.zig");
const core = @import("../core/root.zig");
const game = @import("../game/root.zig");
const model = @import("../model/root.zig");

pub const Core = struct {
    frame_detector: game.FrameDetector,
    capturer: game.Capturer(build_info.game),
    throw_escape_detector: core.ThrowEscapeDetector,
    hit_detector: core.HitDetector,
    move_detector: core.MoveDetector,
    move_measurer: core.MoveMeasurer,
    automation: core.Automation(.{}),
    controller: core.Controller,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .frame_detector = .{},
            .capturer = .{},
            .throw_escape_detector = .{},
            .hit_detector = .{},
            .move_detector = .{},
            .move_measurer = .{},
            .automation = .{},
            .controller = core.Controller.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.controller.deinit();
    }

    pub fn tick(
        self: *Self,
        base_dir: *const sdk.misc.BaseDir,
        settings: *const model.Settings,
        game_memory: *const game.Memory(build_info.game),
        context: anytype,
        processFrame: *const fn (context: @TypeOf(context), frame: *const model.Frame) void,
    ) void {
        if (!self.frame_detector.detect(build_info.game, game_memory)) {
            return;
        }
        var frame = self.capturer.captureFrame(game_memory);
        self.throw_escape_detector.detect(&frame);
        self.hit_detector.detect(&frame);
        self.move_detector.detect(&frame);
        self.move_measurer.measure(&frame);
        self.automation.processFrame(base_dir, &settings.automation, &self.controller, &frame);
        self.controller.processFrame(&frame, context, processFrame);
    }

    pub fn update(
        self: *Self,
        delta_time: f32,
        context: anytype,
        processFrame: *const fn (context: @TypeOf(context), frame: *const model.Frame) void,
    ) void {
        self.automation.update(&self.controller);
        self.controller.update(delta_time, context, processFrame);
    }
};
