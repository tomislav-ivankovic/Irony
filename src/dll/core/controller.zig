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
    };
    pub const LiveState = struct {
        frame: model.Frame = .{},
    };
    pub const RecordState = struct {
        segment_start_index: usize = 0,
        segment: Recording,
    };
    pub const PauseState = struct {
        frame_index: usize = 0,
    };
    pub const PlaybackState = struct {
        frame_index: usize = 0,
        time_since_last_frame: f32 = 0.0,
    };
    pub const normal_speed_frame_time = 1.0 / 60.0;

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .recording = Recording.init(allocator),
            .mode = .{ .live = .{} },
            .playback_speed = 1.0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        self.recording.deinit();
    }

    pub fn processFrame(self: *Self, frame: *const model.Frame) void {
        switch (self.mode) {
            .live => |*state| state.frame = frame.*,
            .record => |*state| state.segment.append(frame.*) catch |err| {
                sdk.misc.error_context.new("Failed to append a frame to the recorded segment.", .{});
                sdk.misc.error_context.logError(err);
            },
            else => {},
        }
    }

    pub fn update(self: *Self, delta_time: f32) void {
        const state: *PlaybackState = switch (self.mode) {
            .playback => |*state| state,
            else => return,
        };
        state.time_since_last_frame += delta_time;
        const frame_time = normal_speed_frame_time / @abs(self.playback_speed);
        if (self.playback_speed >= 0) {
            while (state.time_since_last_frame >= frame_time) {
                if (state.frame_index >= self.recording.items.len - 1) {
                    self.pause();
                    return;
                }
                state.frame_index += 1;
                state.time_since_last_frame -= frame_time;
            }
        } else {
            while (state.time_since_last_frame >= frame_time) {
                if (state.frame_index <= 0) {
                    self.pause();
                    return;
                }
                state.frame_index -= 1;
                state.time_since_last_frame -= frame_time;
            }
        }
    }

    pub fn play(self: *Self) void {
        const total_frames = self.getTotalFrames();
        if (total_frames == 0) {
            return;
        }
        const index = switch (self.mode) {
            .live => 0,
            .record => |*state| state.segment_start_index,
            .pause => |*state| if (total_frames != 0 and state.frame_index < total_frames - 1) block: {
                break :block state.frame_index;
            } else block: {
                break :block 0;
            },
            .playback => return,
        };
        self.flushSegment();
        self.mode = .{ .playback = .{ .frame_index = index } };
    }

    pub fn pause(self: *Self) void {
        if (self.mode == .pause or self.getTotalFrames() == 0) {
            return;
        }
        const index = self.getCurrentFrameIndex() orelse 0;
        self.flushSegment();
        self.mode = .{ .pause = .{ .frame_index = index } };
    }

    pub fn stop(self: *Self) void {
        if (self.mode == .live) {
            return;
        }
        self.flushSegment();
        self.mode = .{ .live = .{} };
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

    pub fn clear(self: *Self) void {
        if (self.getTotalFrames() == 0) {
            return;
        }
        self.flushSegment();
        self.recording.clearAndFree();
        self.mode = .{ .live = .{} };
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
            .pause => |*state| state.frame_index = index,
            .playback => |*state| state.frame_index = index,
            else => {
                self.flushSegment();
                self.mode = .{ .pause = .{ .frame_index = index } };
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
};

const testing = std.testing;

test "should present last processed frame as current when stopped" {
    var controller = Controller.init(testing.allocator);
    defer controller.deinit();
    controller.stop();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    controller.processFrame(&frame_1);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    controller.processFrame(&frame_2);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);
}

test "should present last processed frame as current when recording" {
    var controller = Controller.init(testing.allocator);
    defer controller.deinit();
    controller.record();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    controller.processFrame(&frame_1);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    controller.processFrame(&frame_2);
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
    controller.processFrame(&frame_1);
    controller.processFrame(&frame_2);
    controller.stop();
    controller.record();
    controller.processFrame(&frame_3);
    controller.processFrame(&frame_4);

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
    controller.processFrame(&frame_1);
    controller.processFrame(&frame_2);
    controller.stop();
    controller.setCurrentFrameIndex(0);
    controller.record();
    controller.processFrame(&frame_3);
    controller.processFrame(&frame_4);

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
    controller.processFrame(&frame_1);
    controller.processFrame(&frame_2);
    controller.processFrame(&frame_3);
    controller.stop();
    controller.setCurrentFrameIndex(1);
    controller.record();
    controller.processFrame(&frame_4);
    controller.processFrame(&frame_5);

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
    controller.processFrame(&frame_1);
    controller.processFrame(&frame_2);
    controller.pause();

    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);
}

test "should pause at the set frame when setting current frame while recording" {
    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };

    controller.record();
    controller.processFrame(&frame_1);
    controller.processFrame(&frame_2);
    controller.processFrame(&frame_3);
    controller.setCurrentFrameIndex(1);
    controller.update(123.0);

    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);
}

test "should pause at the set frame when setting current frame while paused" {
    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };

    controller.record();
    controller.processFrame(&frame_1);
    controller.processFrame(&frame_2);
    controller.processFrame(&frame_3);
    controller.pause();
    controller.setCurrentFrameIndex(1);
    controller.update(123.0);

    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);
}

test "should play recording beginning when playing after recording" {
    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };
    const frame_4 = model.Frame{ .frames_since_round_start = 4 };

    controller.record();
    controller.processFrame(&frame_1);
    controller.processFrame(&frame_2);
    controller.processFrame(&frame_3);
    controller.processFrame(&frame_4);
    controller.play();

    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);
    controller.update(0.5 * Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);
    controller.update(Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);
    controller.update(2.0 * Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);
    controller.update(Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);
}

test "should play recording from current frame when playing after paused in the middle of the recording" {
    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };
    const frame_4 = model.Frame{ .frames_since_round_start = 4 };

    controller.record();
    controller.processFrame(&frame_1);
    controller.processFrame(&frame_2);
    controller.processFrame(&frame_3);
    controller.processFrame(&frame_4);
    controller.pause();
    controller.setCurrentFrameIndex(1);
    controller.play();

    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);
    controller.update(0.5 * Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);
    controller.update(Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_3, controller.getCurrentFrame().?.*);
    controller.update(Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);
    controller.update(Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);
}

test "should play recording from beginning when playing after paused on the end of the recording" {
    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };
    const frame_4 = model.Frame{ .frames_since_round_start = 4 };

    controller.record();
    controller.processFrame(&frame_1);
    controller.processFrame(&frame_2);
    controller.processFrame(&frame_3);
    controller.processFrame(&frame_4);
    controller.pause();
    controller.setCurrentFrameIndex(3);
    controller.play();

    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);
    controller.update(0.5 * Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);
    controller.update(Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);
    controller.update(2.0 * Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);
    controller.update(Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);

    controller.play();

    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);
    controller.update(0.5 * Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);
    controller.update(Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);
    controller.update(2.0 * Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);
    controller.update(Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);
}

test "should pause at the current frame when pausing while playing" {
    var controller = Controller.init(testing.allocator);
    defer controller.deinit();

    const frame_1 = model.Frame{ .frames_since_round_start = 1 };
    const frame_2 = model.Frame{ .frames_since_round_start = 2 };
    const frame_3 = model.Frame{ .frames_since_round_start = 3 };
    const frame_4 = model.Frame{ .frames_since_round_start = 4 };

    controller.record();
    controller.processFrame(&frame_1);
    controller.processFrame(&frame_2);
    controller.processFrame(&frame_3);
    controller.processFrame(&frame_4);
    controller.play();

    controller.update(0.9 * Controller.normal_speed_frame_time);

    controller.pause();
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);
    controller.update(10 * Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);
    controller.play();

    controller.update(1.9 * Controller.normal_speed_frame_time);

    controller.pause();
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);
    controller.update(10 * Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);
    controller.play();

    controller.update(2.9 * Controller.normal_speed_frame_time);

    controller.pause();
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);
    controller.update(10 * Controller.normal_speed_frame_time);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);
    controller.play();
}
