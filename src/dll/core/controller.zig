const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const core = @import("../core/root.zig");
const game = @import("../game/root.zig");
const model = @import("../model/root.zig");

pub const Controller = struct {
    allocator: std.mem.Allocator,
    recording: Recording,
    mode: Mode,
    playback_speed: f32,

    const Self = @This();
    pub const Recording = std.ArrayList(model.Frame);
    pub const Mode = union(enum) {
        live: LiveState,
        record: RecordState,
        pause: PauseState,
        playback: PlaybackState,
        scrub: ScrubState,
    };
    pub const LiveState = struct {
        frame: model.Frame,
    };
    pub const RecordState = struct {
        segment_start_index: usize,
        segment: Recording,
    };
    pub const PauseState = struct {
        frame_index: usize,
        is_frame_processed: bool,
    };
    pub const PlaybackState = struct {
        frame_index: usize,
        frame_progress: f32,
        is_frame_processed: bool,
    };
    pub const ScrubState = struct {
        direction: ScrubDirection,
        frame_index: usize,
        frame_progress: f32,
        current_speed: f32,
        is_frame_processed: bool,
    };
    pub const ScrubDirection = enum {
        forward,
        backward,
        neutral,
    };

    pub const frame_time = 1.0 / 60.0;
    pub const min_scrub_speed = 1.0;
    pub const max_scrub_speed = 6.0;
    pub const scrub_ramp_up_time = 10.0;

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .recording = Recording.init(allocator),
            .mode = .{ .live = .{ .frame = .{} } },
            .playback_speed = 1.0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        self.recording.deinit();
    }

    pub fn processFrame(
        self: *Self,
        frame: *const model.Frame,
        context: anytype,
        onFrameChange: ?*const fn (context: @TypeOf(context), frame: *const model.Frame) void,
    ) void {
        switch (self.mode) {
            .live => |*state| {
                state.frame = frame.*;
                if (onFrameChange) |callback| {
                    callback(context, &state.frame);
                }
            },
            .record => |*state| {
                state.segment.append(frame.*) catch |err| {
                    sdk.misc.error_context.new("Failed to append a frame to the recorded segment.", .{});
                    sdk.misc.error_context.logError(err);
                    return;
                };
                if (onFrameChange) |callback| {
                    callback(context, &state.segment.items[state.segment.items.len - 1]);
                }
            },
            else => {},
        }
    }

    pub fn update(
        self: *Self,
        delta_time: f32,
        context: anytype,
        onFrameChange: ?*const fn (context: @TypeOf(context), frame: *const model.Frame) void,
    ) void {
        switch (self.mode) {
            .pause => |*state| if (!state.is_frame_processed) {
                if (onFrameChange) |callback| {
                    if (self.getCurrentFrame()) |frame| {
                        callback(context, frame);
                    }
                }
                state.is_frame_processed = true;
            },
            .playback => |*state| {
                if (!state.is_frame_processed) {
                    if (onFrameChange) |callback| {
                        if (self.getCurrentFrame()) |frame| {
                            callback(context, frame);
                        }
                    }
                    state.is_frame_processed = true;
                }
                state.frame_progress += self.playback_speed * delta_time / frame_time;
                while (state.frame_progress < 0.0) {
                    if (state.frame_index <= 0) {
                        self.pause();
                        return;
                    }
                    state.frame_index -= 1;
                    state.frame_progress += 1.0;
                    if (onFrameChange) |callback| {
                        callback(context, &self.recording.items[state.frame_index]);
                    }
                }
                while (state.frame_progress >= 1.0) {
                    if (state.frame_index >= self.recording.items.len - 1) {
                        self.pause();
                        return;
                    }
                    state.frame_index += 1;
                    state.frame_progress -= 1.0;
                    if (onFrameChange) |callback| {
                        callback(context, &self.recording.items[state.frame_index]);
                    }
                }
            },
            .scrub => |*state| {
                if (!state.is_frame_processed) {
                    if (onFrameChange) |callback| {
                        if (self.getCurrentFrame()) |frame| {
                            callback(context, frame);
                        }
                    }
                    state.is_frame_processed = true;
                }
                const k = comptime -std.math.log(f32, std.math.e, 0.1) / scrub_ramp_up_time;
                state.current_speed += (max_scrub_speed - state.current_speed) * (1 - std.math.exp(-k * delta_time));
                const speed = switch (state.direction) {
                    .forward => state.current_speed,
                    .backward => -state.current_speed,
                    .neutral => 0.0,
                };
                state.frame_progress += speed * delta_time / frame_time;
                while (state.frame_progress < 0.0) {
                    if (state.frame_index <= 0) {
                        self.pause();
                        return;
                    }
                    state.frame_index -= 1;
                    state.frame_progress += 1.0;
                    if (onFrameChange) |callback| {
                        callback(context, &self.recording.items[state.frame_index]);
                    }
                }
                while (state.frame_progress >= 1.0) {
                    if (state.frame_index >= self.recording.items.len - 1) {
                        self.pause();
                        return;
                    }
                    state.frame_index += 1;
                    state.frame_progress -= 1.0;
                    if (onFrameChange) |callback| {
                        callback(context, &self.recording.items[state.frame_index]);
                    }
                }
            },
            else => {},
        }
    }

    pub fn play(self: *Self) void {
        const total_frames = self.getTotalFrames();
        if (total_frames == 0) {
            return;
        }
        const index, const is_frame_processed = switch (self.mode) {
            .live => block: {
                if (self.playback_speed >= 0) {
                    break :block .{ 0, false };
                } else {
                    break :block .{ total_frames - 1, false };
                }
            },
            .record => |*state| block: {
                if (self.playback_speed >= 0) {
                    break :block .{ state.segment_start_index, false };
                } else {
                    break :block .{ state.segment_start_index + state.segment.items.len - 1, true };
                }
            },
            .pause => |*state| block: {
                if (self.playback_speed >= 0 and state.frame_index >= total_frames - 1) {
                    break :block .{ 0, false };
                } else if (self.playback_speed <= 0 and state.frame_index == 0) {
                    break :block .{ total_frames - 1, false };
                } else {
                    break :block .{ state.frame_index, state.is_frame_processed };
                }
            },
            .playback => return,
            .scrub => |*state| .{ state.frame_index, state.is_frame_processed },
        };
        self.flushSegment();
        self.mode = .{ .playback = .{
            .frame_index = index,
            .frame_progress = 0.5,
            .is_frame_processed = is_frame_processed,
        } };
    }

    pub fn pause(self: *Self) void {
        if (self.getTotalFrames() == 0) {
            return;
        }
        const is_frame_processed = switch (self.mode) {
            .live => false,
            .record => true,
            .pause => return,
            .playback => |*state| state.is_frame_processed,
            .scrub => |*state| state.is_frame_processed,
        };
        const index = self.getCurrentFrameIndex() orelse 0;
        self.flushSegment();
        self.mode = .{ .pause = .{
            .frame_index = index,
            .is_frame_processed = is_frame_processed,
        } };
    }

    pub fn stop(self: *Self) void {
        if (self.mode == .live) {
            return;
        }
        self.flushSegment();
        self.mode = .{ .live = .{ .frame = .{} } };
    }

    pub fn record(self: *Self) void {
        if (self.mode == .record) {
            return;
        }
        const segment_start = if (self.getCurrentFrameIndex()) |index| block: {
            break :block if (index != 0) index + 1 else 0;
        } else block: {
            break :block self.recording.items.len;
        };
        self.mode = .{ .record = .{
            .segment = Recording.init(self.allocator),
            .segment_start_index = segment_start,
        } };
    }

    pub fn scrub(self: *Self, direction: ScrubDirection) void {
        const total_frames = self.getTotalFrames();
        if (total_frames == 0) {
            return;
        }
        const index, const is_frame_processed = switch (self.mode) {
            .live => switch (direction) {
                .forward, .neutral => .{ 0, false },
                .backward => .{ total_frames - 1, false },
            },
            .record => |*state| switch (direction) {
                .forward, .neutral => .{ state.segment_start_index, false },
                .backward => .{ state.segment_start_index + state.segment.items.len - 1, true },
            },
            .pause => |*state| block: {
                if (direction == .forward and state.frame_index >= total_frames - 1) {
                    break :block .{ 0, false };
                } else if (direction == .backward and state.frame_index == 0) {
                    break :block .{ total_frames - 1, false };
                } else {
                    break :block .{ state.frame_index, state.is_frame_processed };
                }
            },
            .playback => |*state| .{ state.frame_index, state.is_frame_processed },
            .scrub => |*state| {
                state.direction = direction;
                return;
            },
        };
        self.flushSegment();
        self.mode = .{ .scrub = .{
            .direction = direction,
            .frame_index = index,
            .frame_progress = 0.5,
            .current_speed = min_scrub_speed,
            .is_frame_processed = is_frame_processed,
        } };
    }

    pub fn clear(self: *Self) void {
        if (self.getTotalFrames() == 0) {
            return;
        }
        self.flushSegment();
        self.recording.clearAndFree();
        self.mode = .{ .live = .{ .frame = .{} } };
    }

    fn flushSegment(self: *Self) void {
        const state: *RecordState = switch (self.mode) {
            .record => |*state| state,
            else => return,
        };
        self.recording.insertSlice(state.segment_start_index, state.segment.items) catch |err| {
            sdk.misc.error_context.new("Failed to insert the recorded segment into the recording.", .{});
            sdk.misc.error_context.logError(err);
        };
        state.segment.deinit();
    }

    pub fn getTotalFrames(self: *const Self) usize {
        return switch (self.mode) {
            .record => |*state| self.recording.items.len + state.segment.items.len,
            else => self.recording.items.len,
        };
    }

    pub fn setCurrentFrameIndex(self: *Self, index: usize) void {
        switch (self.mode) {
            .pause => |*state| {
                state.is_frame_processed = index == state.frame_index;
                state.frame_index = index;
            },
            .playback => |*state| {
                state.is_frame_processed = index == state.frame_index;
                state.frame_progress = 0.5;
                state.frame_index = index;
            },
            .scrub => |*state| {
                state.is_frame_processed = index == state.frame_index;
                state.frame_progress = 0.5;
                state.frame_index = index;
            },
            else => {
                self.flushSegment();
                self.mode = .{ .pause = .{
                    .frame_index = index,
                    .is_frame_processed = false,
                } };
            },
        }
    }

    pub fn getCurrentFrameIndex(self: *const Self) ?usize {
        const index = switch (self.mode) {
            .live => return null,
            .record => |*state| block: {
                const sum = state.segment_start_index + state.segment.items.len;
                if (sum > 0) {
                    break :block sum - 1;
                } else {
                    return null;
                }
            },
            .pause => |*state| state.frame_index,
            .playback => |*state| state.frame_index,
            .scrub => |*state| state.frame_index,
        };
        const total = self.getTotalFrames();
        if (index < total) {
            return index;
        } else if (total == 0) {
            return null;
        } else {
            return total - 1;
        }
    }

    pub fn getFrameAt(self: *const Self, index: usize) ?*const model.Frame {
        switch (self.mode) {
            .record => |*state| {
                const recording_len = self.recording.items.len;
                const segment_start = std.math.clamp(state.segment_start_index, 0, recording_len);
                const segment_len = state.segment.items.len;
                if (index < segment_start) {
                    return &self.recording.items[index];
                } else if (index < segment_start + segment_len) {
                    return &state.segment.items[index - segment_start];
                } else if (index < recording_len + segment_len) {
                    return &self.recording.items[index - segment_len];
                } else {
                    return null;
                }
            },
            else => if (index < self.recording.items.len) {
                return &self.recording.items[index];
            } else {
                return null;
            },
        }
    }

    pub fn getCurrentFrame(self: *const Self) ?*const model.Frame {
        switch (self.mode) {
            .live => |*state| return &state.frame,
            else => if (self.getCurrentFrameIndex()) |index| {
                return self.getFrameAt(index);
            } else {
                return null;
            },
        }
    }

    pub fn getScrubDirection(self: *const Self) ?ScrubDirection {
        return switch (self.mode) {
            .scrub => |*state| state.direction,
            else => null,
        };
    }
};

const testing = std.testing;

test "should present last processed frame as current when stopped" {
    const Callback = struct {
        var times_called: usize = 0;
        var last_frame: ?model.Frame = null;

        fn call(_: void, frame: *const model.Frame) void {
            times_called += 1;
            last_frame = frame.*;
        }
    };

    var controller = Controller.init(testing.allocator);
    defer controller.deinit();
    controller.stop();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    controller.processFrame(&frame_1, {}, Callback.call);
    try testing.expectEqual(1, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    controller.processFrame(&frame_2, {}, Callback.call);
    try testing.expectEqual(2, Callback.times_called);
    try testing.expectEqual(frame_2, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);
}

test "should present last processed frame as current when recording" {
    const Callback = struct {
        var times_called: usize = 0;
        var last_frame: ?model.Frame = null;

        fn call(_: void, frame: *const model.Frame) void {
            times_called += 1;
            last_frame = frame.*;
        }
    };

    var controller = Controller.init(testing.allocator);
    defer controller.deinit();
    controller.record();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    controller.processFrame(&frame_1, {}, Callback.call);
    try testing.expectEqual(1, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    controller.processFrame(&frame_2, {}, Callback.call);
    try testing.expectEqual(2, Callback.times_called);
    try testing.expectEqual(frame_2, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);
}

test "should store processed frames while recording" {
    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };
    const frame_4 = model.Frame{ .frames_since_round_start = 4 };

    controller.record();
    controller.processFrame(&frame_1, {}, null);
    controller.processFrame(&frame_2, {}, null);
    controller.stop();
    controller.record();
    controller.processFrame(&frame_3, {}, null);
    controller.processFrame(&frame_4, {}, null);

    try testing.expectEqual(4, controller.getTotalFrames());
    try testing.expect(controller.getFrameAt(0) != null);
    try testing.expect(controller.getFrameAt(1) != null);
    try testing.expect(controller.getFrameAt(2) != null);
    try testing.expect(controller.getFrameAt(3) != null);
    try testing.expectEqual(frame_1, controller.getFrameAt(0).?.*);
    try testing.expectEqual(frame_2, controller.getFrameAt(1).?.*);
    try testing.expectEqual(frame_3, controller.getFrameAt(2).?.*);
    try testing.expectEqual(frame_4, controller.getFrameAt(3).?.*);

    controller.stop();

    try testing.expectEqual(4, controller.getTotalFrames());
    try testing.expect(controller.getFrameAt(0) != null);
    try testing.expect(controller.getFrameAt(1) != null);
    try testing.expect(controller.getFrameAt(2) != null);
    try testing.expect(controller.getFrameAt(3) != null);
    try testing.expectEqual(frame_1, controller.getFrameAt(0).?.*);
    try testing.expectEqual(frame_2, controller.getFrameAt(1).?.*);
    try testing.expectEqual(frame_3, controller.getFrameAt(2).?.*);
    try testing.expectEqual(frame_4, controller.getFrameAt(3).?.*);
}

test "should store frames in correct order when recording in the beginning of the recording" {
    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };
    const frame_4 = model.Frame{ .frames_since_round_start = 4 };

    controller.record();
    controller.processFrame(&frame_1, {}, null);
    controller.processFrame(&frame_2, {}, null);
    controller.stop();
    controller.setCurrentFrameIndex(0);
    controller.record();
    controller.processFrame(&frame_3, {}, null);
    controller.processFrame(&frame_4, {}, null);

    try testing.expectEqual(4, controller.getTotalFrames());
    try testing.expect(controller.getFrameAt(0) != null);
    try testing.expect(controller.getFrameAt(1) != null);
    try testing.expect(controller.getFrameAt(2) != null);
    try testing.expect(controller.getFrameAt(3) != null);
    try testing.expectEqual(frame_3, controller.getFrameAt(0).?.*);
    try testing.expectEqual(frame_4, controller.getFrameAt(1).?.*);
    try testing.expectEqual(frame_1, controller.getFrameAt(2).?.*);
    try testing.expectEqual(frame_2, controller.getFrameAt(3).?.*);

    controller.stop();

    try testing.expectEqual(4, controller.getTotalFrames());
    try testing.expect(controller.getFrameAt(0) != null);
    try testing.expect(controller.getFrameAt(1) != null);
    try testing.expect(controller.getFrameAt(2) != null);
    try testing.expect(controller.getFrameAt(3) != null);
    try testing.expectEqual(frame_3, controller.getFrameAt(0).?.*);
    try testing.expectEqual(frame_4, controller.getFrameAt(1).?.*);
    try testing.expectEqual(frame_1, controller.getFrameAt(2).?.*);
    try testing.expectEqual(frame_2, controller.getFrameAt(3).?.*);
}

test "should store frames in correct order when recording in the middle of the recording" {
    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };
    const frame_4 = model.Frame{ .frames_since_round_start = 4 };
    const frame_5 = model.Frame{ .frames_since_round_start = 5 };

    controller.record();
    controller.processFrame(&frame_1, {}, null);
    controller.processFrame(&frame_2, {}, null);
    controller.processFrame(&frame_3, {}, null);
    controller.stop();
    controller.setCurrentFrameIndex(1);
    controller.record();
    controller.processFrame(&frame_4, {}, null);
    controller.processFrame(&frame_5, {}, null);

    try testing.expectEqual(5, controller.getTotalFrames());
    try testing.expect(controller.getFrameAt(0) != null);
    try testing.expect(controller.getFrameAt(1) != null);
    try testing.expect(controller.getFrameAt(2) != null);
    try testing.expect(controller.getFrameAt(3) != null);
    try testing.expect(controller.getFrameAt(4) != null);
    try testing.expectEqual(frame_1, controller.getFrameAt(0).?.*);
    try testing.expectEqual(frame_2, controller.getFrameAt(1).?.*);
    try testing.expectEqual(frame_4, controller.getFrameAt(2).?.*);
    try testing.expectEqual(frame_5, controller.getFrameAt(3).?.*);
    try testing.expectEqual(frame_3, controller.getFrameAt(4).?.*);

    controller.stop();

    try testing.expectEqual(5, controller.getTotalFrames());
    try testing.expect(controller.getFrameAt(0) != null);
    try testing.expect(controller.getFrameAt(1) != null);
    try testing.expect(controller.getFrameAt(2) != null);
    try testing.expect(controller.getFrameAt(3) != null);
    try testing.expect(controller.getFrameAt(4) != null);
    try testing.expectEqual(frame_1, controller.getFrameAt(0).?.*);
    try testing.expectEqual(frame_2, controller.getFrameAt(1).?.*);
    try testing.expectEqual(frame_4, controller.getFrameAt(2).?.*);
    try testing.expectEqual(frame_5, controller.getFrameAt(3).?.*);
    try testing.expectEqual(frame_3, controller.getFrameAt(4).?.*);
}

test "should present the last frame as current when pausing the recording" {
    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };

    controller.record();
    controller.processFrame(&frame_1, {}, null);
    controller.processFrame(&frame_2, {}, null);
    controller.pause();

    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);
}

test "should pause at the set frame when setting current frame while recording" {
    const Callback = struct {
        var times_called: usize = 0;
        var last_frame: ?model.Frame = null;

        fn call(_: void, frame: *const model.Frame) void {
            times_called += 1;
            last_frame = frame.*;
        }
    };

    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };

    controller.record();
    controller.processFrame(&frame_1, {}, Callback.call);
    controller.processFrame(&frame_2, {}, Callback.call);
    controller.processFrame(&frame_3, {}, Callback.call);
    controller.setCurrentFrameIndex(1);
    controller.update(123.0, {}, Callback.call);

    try testing.expectEqual(4, Callback.times_called);
    try testing.expectEqual(frame_2, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);
}

test "should stay paused but at the set frame when setting current frame while paused" {
    const Callback = struct {
        var times_called: usize = 0;
        var last_frame: ?model.Frame = null;

        fn call(_: void, frame: *const model.Frame) void {
            times_called += 1;
            last_frame = frame.*;
        }
    };

    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };

    controller.record();
    controller.processFrame(&frame_1, {}, Callback.call);
    controller.processFrame(&frame_2, {}, Callback.call);
    controller.processFrame(&frame_3, {}, Callback.call);
    controller.pause();
    controller.setCurrentFrameIndex(1);
    controller.update(123.0, {}, Callback.call);

    try testing.expectEqual(4, Callback.times_called);
    try testing.expectEqual(frame_2, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);
}

test "should play recording from beginning to end when playing with positive speed after recording" {
    const Callback = struct {
        var times_called: usize = 0;
        var last_frame: ?model.Frame = null;

        fn call(_: void, frame: *const model.Frame) void {
            times_called += 1;
            last_frame = frame.*;
        }
    };

    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };
    const frame_4 = model.Frame{ .frames_since_round_start = 4 };

    controller.record();
    controller.processFrame(&frame_1, {}, Callback.call);
    controller.processFrame(&frame_2, {}, Callback.call);
    controller.processFrame(&frame_3, {}, Callback.call);
    controller.processFrame(&frame_4, {}, Callback.call);
    controller.play();

    try testing.expectEqual(4, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    controller.update(0.0, {}, Callback.call);

    try testing.expectEqual(5, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(6, Callback.times_called);
    try testing.expectEqual(frame_2, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);

    controller.update(2.0 * Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(8, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(8, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);
}

test "should play recording from end to beginning when playing with negative speed after recording" {
    const Callback = struct {
        var times_called: usize = 0;
        var last_frame: ?model.Frame = null;

        fn call(_: void, frame: *const model.Frame) void {
            times_called += 1;
            last_frame = frame.*;
        }
    };

    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };
    const frame_4 = model.Frame{ .frames_since_round_start = 4 };

    controller.record();
    controller.processFrame(&frame_1, {}, Callback.call);
    controller.processFrame(&frame_2, {}, Callback.call);
    controller.processFrame(&frame_3, {}, Callback.call);
    controller.processFrame(&frame_4, {}, Callback.call);
    controller.playback_speed = -1.0;
    controller.play();

    try testing.expectEqual(4, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);

    controller.update(0.0, {}, Callback.call);

    try testing.expectEqual(4, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(5, Callback.times_called);
    try testing.expectEqual(frame_3, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_3, controller.getCurrentFrame().?.*);

    controller.update(2.0 * Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(7, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(7, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);
}

test "should play recording from current frame to end when playing with positive speed after paused in the middle of the recording" {
    const Callback = struct {
        var times_called: usize = 0;
        var last_frame: ?model.Frame = null;

        fn call(_: void, frame: *const model.Frame) void {
            times_called += 1;
            last_frame = frame.*;
        }
    };

    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };
    const frame_4 = model.Frame{ .frames_since_round_start = 4 };

    controller.record();
    controller.processFrame(&frame_1, {}, Callback.call);
    controller.processFrame(&frame_2, {}, Callback.call);
    controller.processFrame(&frame_3, {}, Callback.call);
    controller.processFrame(&frame_4, {}, Callback.call);
    controller.pause();
    controller.setCurrentFrameIndex(1);
    controller.play();

    try testing.expectEqual(4, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);

    controller.update(0.0, {}, Callback.call);

    try testing.expectEqual(5, Callback.times_called);
    try testing.expectEqual(frame_2, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(6, Callback.times_called);
    try testing.expectEqual(frame_3, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_3, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(7, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(7, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);
}

test "should play recording from current frame to beginning when playing with negative speed after paused in the middle of the recording" {
    const Callback = struct {
        var times_called: usize = 0;
        var last_frame: ?model.Frame = null;

        fn call(_: void, frame: *const model.Frame) void {
            times_called += 1;
            last_frame = frame.*;
        }
    };

    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };
    const frame_4 = model.Frame{ .frames_since_round_start = 4 };

    controller.record();
    controller.processFrame(&frame_1, {}, Callback.call);
    controller.processFrame(&frame_2, {}, Callback.call);
    controller.processFrame(&frame_3, {}, Callback.call);
    controller.processFrame(&frame_4, {}, Callback.call);
    controller.pause();
    controller.setCurrentFrameIndex(2);
    controller.playback_speed = -1.0;
    controller.play();

    try testing.expectEqual(4, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_3, controller.getCurrentFrame().?.*);

    controller.update(0.0, {}, Callback.call);

    try testing.expectEqual(5, Callback.times_called);
    try testing.expectEqual(frame_3, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_3, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(6, Callback.times_called);
    try testing.expectEqual(frame_2, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(7, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(7, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);
}

test "should play recording from beginning to end when playing with positive speed after paused on the end of the recording" {
    const Callback = struct {
        var times_called: usize = 0;
        var last_frame: ?model.Frame = null;

        fn call(_: void, frame: *const model.Frame) void {
            times_called += 1;
            last_frame = frame.*;
        }
    };

    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };
    const frame_4 = model.Frame{ .frames_since_round_start = 4 };

    controller.record();
    controller.processFrame(&frame_1, {}, Callback.call);
    controller.processFrame(&frame_2, {}, Callback.call);
    controller.processFrame(&frame_3, {}, Callback.call);
    controller.processFrame(&frame_4, {}, Callback.call);
    controller.pause();
    controller.setCurrentFrameIndex(3);
    controller.play();

    try testing.expectEqual(4, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    controller.update(0.0, {}, Callback.call);

    try testing.expectEqual(5, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(6, Callback.times_called);
    try testing.expectEqual(frame_2, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);

    controller.update(2.0 * Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(8, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(8, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);

    controller.play();

    try testing.expectEqual(8, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    controller.update(0.0, {}, Callback.call);

    try testing.expectEqual(9, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(10, Callback.times_called);
    try testing.expectEqual(frame_2, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);

    controller.update(2.0 * Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(12, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(12, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);
}

test "should play recording from end to beginning when playing with negative speed after paused on the beginning of the recording" {
    const Callback = struct {
        var times_called: usize = 0;
        var last_frame: ?model.Frame = null;

        fn call(_: void, frame: *const model.Frame) void {
            times_called += 1;
            last_frame = frame.*;
        }
    };

    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };
    const frame_4 = model.Frame{ .frames_since_round_start = 4 };

    controller.record();
    controller.processFrame(&frame_1, {}, Callback.call);
    controller.processFrame(&frame_2, {}, Callback.call);
    controller.processFrame(&frame_3, {}, Callback.call);
    controller.processFrame(&frame_4, {}, Callback.call);
    controller.pause();
    controller.setCurrentFrameIndex(0);
    controller.update(Controller.frame_time, {}, Callback.call);
    controller.playback_speed = -1.0;
    controller.play();

    try testing.expectEqual(5, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);

    controller.update(0.0, {}, Callback.call);

    try testing.expectEqual(6, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(7, Callback.times_called);
    try testing.expectEqual(frame_3, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_3, controller.getCurrentFrame().?.*);

    controller.update(2.0 * Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(9, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(9, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    controller.play();

    try testing.expectEqual(9, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);

    controller.update(0.0, {}, Callback.call);

    try testing.expectEqual(10, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(11, Callback.times_called);
    try testing.expectEqual(frame_3, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_3, controller.getCurrentFrame().?.*);

    controller.update(2.0 * Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(13, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(13, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);
}

test "should play recording correctly when changing the playback speed" {
    const Callback = struct {
        var times_called: usize = 0;
        var last_frame: ?model.Frame = null;

        fn call(_: void, frame: *const model.Frame) void {
            times_called += 1;
            last_frame = frame.*;
        }
    };

    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };
    const frame_4 = model.Frame{ .frames_since_round_start = 4 };
    const frame_5 = model.Frame{ .frames_since_round_start = 5 };

    controller.record();
    controller.processFrame(&frame_1, {}, Callback.call);
    controller.processFrame(&frame_2, {}, Callback.call);
    controller.processFrame(&frame_3, {}, Callback.call);
    controller.processFrame(&frame_4, {}, Callback.call);
    controller.processFrame(&frame_5, {}, Callback.call);
    controller.play();

    try testing.expectEqual(5, Callback.times_called);
    try testing.expectEqual(frame_5, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    controller.playback_speed = 0.0;
    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(6, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    controller.playback_speed = 1.0;
    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(7, Callback.times_called);
    try testing.expectEqual(frame_2, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);

    controller.playback_speed = 2.0;
    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(9, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);

    controller.playback_speed = -1.0;
    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(10, Callback.times_called);
    try testing.expectEqual(frame_3, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_3, controller.getCurrentFrame().?.*);

    controller.playback_speed = -2.0;
    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(12, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);
}

test "should pause at the current frame when pausing while playing" {
    const Callback = struct {
        var times_called: usize = 0;
        var last_frame: ?model.Frame = null;

        fn call(_: void, frame: *const model.Frame) void {
            times_called += 1;
            last_frame = frame.*;
        }
    };

    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };
    const frame_4 = model.Frame{ .frames_since_round_start = 4 };

    controller.record();
    controller.processFrame(&frame_1, {}, Callback.call);
    controller.processFrame(&frame_2, {}, Callback.call);
    controller.processFrame(&frame_3, {}, Callback.call);
    controller.processFrame(&frame_4, {}, Callback.call);
    controller.play();
    controller.update(0.4 * Controller.frame_time, {}, Callback.call);
    controller.pause();

    try testing.expectEqual(5, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    controller.update(10 * Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(5, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    controller.play();
    controller.update(1.4 * Controller.frame_time, {}, Callback.call);
    controller.pause();

    try testing.expectEqual(6, Callback.times_called);
    try testing.expectEqual(frame_2, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);

    controller.update(10 * Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(6, Callback.times_called);
    try testing.expectEqual(frame_2, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);

    controller.play();
    controller.update(2.4 * Controller.frame_time, {}, Callback.call);
    controller.pause();

    try testing.expectEqual(8, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);

    controller.update(10 * Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(8, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);
}

// TODO Scrubbing tests.
