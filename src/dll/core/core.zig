const std = @import("std");
const build_info = @import("build_info");
const sdk = @import("../../sdk/root.zig");
const core = @import("../core/root.zig");
const game = @import("../game/root.zig");
const model = @import("../model/root.zig");

pub const Core = struct {
    frame_detector: game.FrameDetector,
    capturer: game.Capturer(build_info.game),
    throw_escape_detector: core.ThrowEscapeDetector(.{
        .one_plus_two_mode = switch (build_info.game) {
            .t7 => .strict,
            .t8 => .forgiving,
        },
    }),
    hit_detector: core.HitDetector,
    move_detector: core.MoveDetector,
    move_measurer: core.MoveMeasurer,
    automation: core.Automation(.{}),
    tool_assisted_input: core.ToolAssistedInput,
    controller: core.Controller,
    tai_recording_coordinator: core.TaiRecordingCoordinator,
    camera_director: core.CameraDirector,

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
            .tool_assisted_input = core.ToolAssistedInput.init(allocator),
            .controller = core.Controller.init(allocator),
            .tai_recording_coordinator = .{},
            .camera_director = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.controller.deinit();
        self.tool_assisted_input.deinit();
    }

    pub fn tick(
        self: *Self,
        io: std.Io,
        settings: *const model.Settings,
        game_memory: *const game.Memory(build_info.game),
        input_override: *game.InputOverride,
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
        self.automation.processFrame(io, &settings.automation, &self.controller, &frame);
        self.tool_assisted_input.processFrame(input_override, frame.source);
        self.controller.processFrame(&frame, context, processFrame);
        self.tai_recording_coordinator.processFrame(&self.tool_assisted_input, &self.controller);
    }

    pub fn update(
        self: *Self,
        delta_time: f32,
        game_memory_maybe: ?*const game.Memory(build_info.game),
        camera_override: *?model.Camera,
        context: anytype,
        processFrame: *const fn (context: @TypeOf(context), frame: *const model.Frame) void,
    ) void {
        self.automation.update(&self.controller);
        self.controller.update(delta_time, context, processFrame);
        const source = if (game_memory_maybe) |game_memory| block: {
            break :block game.Capturer(build_info.game).captureSource(
                game_memory.player_1.toConstPointer(),
                game_memory.player_2.toConstPointer(),
                game_memory.match.toConstPointer(),
                game_memory.replay_mode.toConstPointer(),
                &game_memory.functions,
            );
        } else null;
        self.camera_director.update(source, camera_override, self.controller.getCurrentFrame());
    }
};
