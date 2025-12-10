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
    contains_unsaved_changes: bool,
    did_last_save_or_load_succeed: bool,

    const Self = @This();
    pub const Recording = std.ArrayList(model.Frame);
    pub const Mode = union(enum) {
        live: LiveState,
        record: RecordState,
        pause: PauseState,
        playback: PlaybackState,
        scrub: ScrubState,
        load: LoadState,
        save: SaveState,
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
        unprocessed_frames_start: ?usize,
    };
    pub const PlaybackState = struct {
        frame_index: usize,
        frame_progress: f32,
        unprocessed_frames_start: ?usize,
    };
    pub const ScrubState = struct {
        direction: ScrubDirection,
        frame_index: usize,
        frame_progress: f32,
        scrubbing_time: f32,
        unprocessed_frames_start: ?usize,
    };
    pub const ScrubDirection = enum {
        forward,
        backward,
        neutral,
    };
    pub const LoadState = struct {
        task: LoadTask,
        frame_index: ?usize,
    };
    pub const LoadTask = sdk.misc.Task(?[]model.Frame);
    pub const SaveState = struct {
        task: SaveTask,
        frame_index: ?usize,
    };
    pub const SaveTask = sdk.misc.Task(?void);

    pub const frame_time = 1.0 / 60.0;
    pub const min_scrub_speed = 1.0;
    pub const max_scrub_speed = 6.0;
    pub const scrub_ramp_up_time = 10.0;
    pub const max_number_of_unprocessed_frames = 300;
    pub const serialization_config = sdk.io.RecordingConfig{
        .atomic_types = &.{
            ?bool,
            ?u32,
            ?f32,
            ?i32,
            ?model.MovePhase,
            ?model.AttackType,
            ?model.HitOutcome,
            ?model.Posture,
            ?model.Blocking,
            ?model.Crushing,
            ?model.Input,
            ?model.Rage,
            sdk.math.Vec3,
            model.HitLine,
        },
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .recording = .empty,
            .mode = .{ .live = .{ .frame = .{} } },
            .playback_speed = 1.0,
            .contains_unsaved_changes = false,
            .did_last_save_or_load_succeed = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.cleanUpModeState();
        self.recording.deinit(self.allocator);
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
                state.segment.append(self.allocator, frame.*) catch |err| {
                    sdk.misc.error_context.new("Failed to append a frame to the recorded segment.", .{});
                    sdk.misc.error_context.logError(err);
                    return;
                };
                self.contains_unsaved_changes = true;
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
            .pause => |*state| self.processUnprocessedFrames(
                &state.unprocessed_frames_start,
                state.frame_index,
                context,
                onFrameChange,
            ),
            .playback => |*state| {
                self.processUnprocessedFrames(
                    &state.unprocessed_frames_start,
                    state.frame_index,
                    context,
                    onFrameChange,
                );
                state.frame_progress += self.playback_speed * delta_time / frame_time;
                self.applyFrameProgress(&state.frame_progress, &state.frame_index, context, onFrameChange);
            },
            .scrub => |*state| {
                self.processUnprocessedFrames(
                    &state.unprocessed_frames_start,
                    state.frame_index,
                    context,
                    onFrameChange,
                );
                const abs_speed = std.math.lerp(
                    min_scrub_speed,
                    max_scrub_speed,
                    sdk.math.smoothStep(0, scrub_ramp_up_time, state.scrubbing_time),
                );
                const speed = switch (state.direction) {
                    .forward => abs_speed,
                    .backward => -abs_speed,
                    .neutral => 0.0,
                };
                state.frame_progress += speed * delta_time / frame_time;
                state.scrubbing_time += delta_time;
                self.applyFrameProgress(&state.frame_progress, &state.frame_index, context, onFrameChange);
            },
            .load => |*state| if (state.task.peek()) |task_result| {
                if (task_result.* != null) {
                    self.cleanUpModeState();
                    self.mode = .{ .pause = .{
                        .frame_index = self.recording.items.len -| 1,
                        .unprocessed_frames_start = self.recording.items.len -| 1,
                    } };
                } else if (state.frame_index) |frame_index| {
                    self.cleanUpModeState();
                    self.mode = .{ .pause = .{
                        .frame_index = frame_index,
                        .unprocessed_frames_start = frame_index,
                    } };
                } else {
                    self.cleanUpModeState();
                    self.mode = .{ .live = .{ .frame = .{} } };
                }
            },
            .save => |*state| if (state.task.peek() != null) {
                if (state.frame_index) |frame_index| {
                    self.cleanUpModeState();
                    self.mode = .{ .pause = .{
                        .frame_index = frame_index,
                        .unprocessed_frames_start = frame_index,
                    } };
                } else {
                    self.cleanUpModeState();
                    self.mode = .{ .live = .{ .frame = .{} } };
                }
            },
            else => {},
        }
    }

    fn processUnprocessedFrames(
        self: *const Self,
        unprocessed_frames_start: *?usize,
        target_frame_index: usize,
        context: anytype,
        onFrameChange: ?*const fn (context: @TypeOf(context), frame: *const model.Frame) void,
    ) void {
        defer unprocessed_frames_start.* = null;
        const callback = onFrameChange orelse return;
        var index = unprocessed_frames_start.* orelse return;
        if (index <= target_frame_index) {
            while (index <= target_frame_index) {
                if (self.getFrameAt(index)) |frame| {
                    callback(context, frame);
                }
                if (index == std.math.maxInt(usize)) {
                    break;
                }
                index += 1;
            }
        } else {
            while (index >= target_frame_index) {
                if (self.getFrameAt(index)) |frame| {
                    callback(context, frame);
                }
                if (index == 0) {
                    break;
                }
                index -= 1;
            }
        }
    }

    fn applyFrameProgress(
        self: *Self,
        frame_progress: *f32,
        frame_index: *usize,
        context: anytype,
        onFrameChange: ?*const fn (context: @TypeOf(context), frame: *const model.Frame) void,
    ) void {
        while (frame_progress.* < 0.0) {
            if (frame_index.* <= 0) {
                self.pause();
                return;
            }
            frame_index.* -= 1;
            frame_progress.* += 1.0;
            if (onFrameChange) |callback| {
                callback(context, &self.recording.items[frame_index.*]);
            }
        }
        while (frame_progress.* >= 1.0) {
            if (frame_index.* >= self.recording.items.len - 1) {
                self.pause();
                return;
            }
            frame_index.* += 1;
            frame_progress.* -= 1.0;
            if (onFrameChange) |callback| {
                callback(context, &self.recording.items[frame_index.*]);
            }
        }
    }

    pub fn play(self: *Self) void {
        const total_frames = self.getTotalFrames();
        if (total_frames == 0) {
            return;
        }
        const index, const unprocessed_frames_start = switch (self.mode) {
            .live => block: {
                if (self.playback_speed >= 0) {
                    break :block .{ 0, 0 };
                } else {
                    break :block .{ total_frames - 1, total_frames - 1 };
                }
            },
            .record => |*state| block: {
                if (self.playback_speed >= 0) {
                    break :block .{ state.segment_start_index, state.segment_start_index };
                } else {
                    break :block .{ state.segment_start_index + state.segment.items.len - 1, null };
                }
            },
            .pause => |*state| block: {
                if (self.playback_speed >= 0 and state.frame_index >= total_frames - 1) {
                    break :block .{ 0, 0 };
                } else if (self.playback_speed <= 0 and state.frame_index == 0) {
                    break :block .{ total_frames - 1, total_frames - 1 };
                } else {
                    break :block .{ state.frame_index, state.unprocessed_frames_start };
                }
            },
            .scrub => |*state| .{ state.frame_index, state.unprocessed_frames_start },
            .playback, .load, .save => return,
        };
        self.cleanUpModeState();
        self.mode = .{ .playback = .{
            .frame_index = index,
            .frame_progress = 0.5,
            .unprocessed_frames_start = unprocessed_frames_start,
        } };
    }

    pub fn pause(self: *Self) void {
        if (self.getTotalFrames() == 0) {
            return;
        }
        const index = self.getCurrentFrameIndex() orelse 0;
        const unprocessed_frames_start = switch (self.mode) {
            .live => index,
            .record => null,
            .playback => |*state| state.unprocessed_frames_start,
            .scrub => |*state| state.unprocessed_frames_start,
            .pause, .load, .save => return,
        };
        self.cleanUpModeState();
        self.mode = .{ .pause = .{
            .frame_index = index,
            .unprocessed_frames_start = unprocessed_frames_start,
        } };
    }

    pub fn stop(self: *Self) void {
        if (self.mode == .live or self.mode == .load or self.mode == .save) {
            return;
        }
        self.cleanUpModeState();
        self.mode = .{ .live = .{ .frame = .{} } };
    }

    pub fn record(self: *Self) void {
        if (self.mode == .record or self.mode == .load or self.mode == .save) {
            return;
        }
        const segment_start = if (self.getCurrentFrameIndex()) |index| block: {
            break :block if (index != 0) index + 1 else 0;
        } else block: {
            break :block self.recording.items.len;
        };
        self.cleanUpModeState();
        self.mode = .{ .record = .{
            .segment = .empty,
            .segment_start_index = segment_start,
        } };
    }

    pub fn scrub(self: *Self, direction: ScrubDirection) void {
        const total_frames = self.getTotalFrames();
        if (total_frames == 0) {
            return;
        }
        const index, const unprocessed_frames_start = switch (self.mode) {
            .live => switch (direction) {
                .forward, .neutral => .{ 0, 0 },
                .backward => .{ total_frames - 1, total_frames - 1 },
            },
            .record => |*state| switch (direction) {
                .forward, .neutral => .{ state.segment_start_index, state.segment_start_index },
                .backward => .{ state.segment_start_index + state.segment.items.len - 1, null },
            },
            .pause => |*state| block: {
                if (direction == .forward and state.frame_index >= total_frames - 1) {
                    break :block .{ 0, 0 };
                } else if (direction == .backward and state.frame_index == 0) {
                    break :block .{ total_frames - 1, total_frames - 1 };
                } else {
                    break :block .{ state.frame_index, state.unprocessed_frames_start };
                }
            },
            .playback => |*state| .{ state.frame_index, state.unprocessed_frames_start },
            .scrub => |*state| {
                state.direction = direction;
                return;
            },
            .load, .save => return,
        };
        self.cleanUpModeState();
        self.mode = .{ .scrub = .{
            .direction = direction,
            .frame_index = index,
            .frame_progress = 0.5,
            .scrubbing_time = 0.0,
            .unprocessed_frames_start = unprocessed_frames_start,
        } };
    }

    pub fn clear(self: *Self) void {
        if (self.getTotalFrames() == 0 or self.mode == .load or self.mode == .save) {
            return;
        }
        self.cleanUpModeState();
        self.recording.clearAndFree(self.allocator);
        self.contains_unsaved_changes = false;
        self.mode = .{ .live = .{ .frame = .{} } };
    }

    pub fn load(self: *Self, file_path: []const u8) void {
        if (self.mode == .load or self.mode == .save) {
            return;
        }
        std.log.info("Loading recording... {s}", .{file_path});
        var file_path_buffer: [sdk.os.max_file_path_length]u8 = undefined;
        const file_path_copy = std.fmt.bufPrint(&file_path_buffer, "{s}", .{file_path}) catch |err| {
            sdk.misc.error_context.new("Failed to copy file path to buffer.", .{});
            sdk.misc.error_context.append("Failed to load recording: {s}", .{file_path});
            sdk.misc.error_context.logError(err);
            return;
        };
        std.log.debug("Spawning load recording task...", .{});
        const task = LoadTask.spawn(self.allocator, struct {
            fn call(
                allocator: std.mem.Allocator,
                path_buffer: [sdk.os.max_file_path_length]u8,
                path_len: usize,
            ) ?[]model.Frame {
                std.log.debug("Load recording task spawned.", .{});
                const path = path_buffer[0..path_len];
                if (sdk.io.loadRecording(model.Frame, allocator, path, &serialization_config)) |frames| {
                    std.log.info("Recording loaded.", .{});
                    sdk.ui.toasts.send(.success, null, "Recording loaded successfully.", .{});
                    return frames;
                } else |err| {
                    sdk.misc.error_context.append("Failed to load recording: {s}", .{path});
                    sdk.misc.error_context.logError(err);
                    return null;
                }
            }
        }.call, .{ self.allocator, file_path_buffer, file_path_copy.len }) catch |err| {
            sdk.misc.error_context.append("Failed to spawn load recording task.", .{});
            sdk.misc.error_context.append("Failed to load recording: {s}", .{file_path});
            sdk.misc.error_context.logError(err);
            return;
        };
        const frame_index = self.getCurrentFrameIndex();
        self.cleanUpModeState();
        self.mode = .{ .load = .{
            .task = task,
            .frame_index = frame_index,
        } };
    }

    pub fn save(self: *Self, file_path: []const u8) void {
        if (self.mode == .load or self.mode == .save) {
            return;
        }
        std.log.info("Saving recording... {s}", .{file_path});
        var file_path_buffer: [sdk.os.max_file_path_length]u8 = undefined;
        const file_path_copy = std.fmt.bufPrint(&file_path_buffer, "{s}", .{file_path}) catch |err| {
            sdk.misc.error_context.new("Failed to copy file path to buffer.", .{});
            sdk.misc.error_context.append("Failed to save recording: {s}", .{file_path});
            sdk.misc.error_context.logError(err);
            return;
        };
        std.log.debug("Spawning save recording task...", .{});
        self.cleanUpModeState(); // Called here to ensure the recorded segment gets flushed before spawning the task.
        const task = SaveTask.spawn(self.allocator, struct {
            fn call(
                allocator: std.mem.Allocator,
                frames: []const model.Frame,
                path_buffer: [sdk.os.max_file_path_length]u8,
                path_len: usize,
            ) ?void {
                std.log.debug("Save recording task spawned.", .{});
                const path = path_buffer[0..path_len];
                if (sdk.io.saveRecording(model.Frame, allocator, frames, path, &serialization_config)) {
                    std.log.info("Recording saved.", .{});
                    sdk.ui.toasts.send(.success, null, "Recording saved successfully.", .{});
                } else |err| {
                    sdk.misc.error_context.append("Failed to save recording: {s}", .{path});
                    sdk.misc.error_context.logError(err);
                    return null;
                }
            }
        }.call, .{ self.allocator, self.recording.items, file_path_buffer, file_path_copy.len }) catch |err| {
            sdk.misc.error_context.append("Failed to spawn save recording task.", .{});
            sdk.misc.error_context.append("Failed to save recording: {s}", .{file_path});
            sdk.misc.error_context.logError(err);
            return;
        };
        const frame_index = self.getCurrentFrameIndex();
        self.mode = .{ .save = .{
            .task = task,
            .frame_index = frame_index,
        } };
    }

    fn cleanUpModeState(self: *Self) void {
        switch (self.mode) {
            .live, .pause, .playback, .scrub => {},
            .record => |*state| {
                self.recording.insertSlice(self.allocator, state.segment_start_index, state.segment.items) catch |err| {
                    sdk.misc.error_context.new("Failed to insert the recorded segment into the recording.", .{});
                    sdk.misc.error_context.logError(err);
                };
                state.segment.deinit(self.allocator);
            },
            .load => |*state| {
                if (state.task.join().*) |frames| {
                    self.recording.clearAndFree(self.allocator);
                    self.recording = .fromOwnedSlice(frames);
                    self.contains_unsaved_changes = false;
                    self.did_last_save_or_load_succeed = true;
                } else {
                    self.did_last_save_or_load_succeed = false;
                }
            },
            .save => |*state| {
                if (state.task.join().* != null) {
                    self.contains_unsaved_changes = false;
                    self.did_last_save_or_load_succeed = true;
                } else {
                    self.did_last_save_or_load_succeed = false;
                }
            },
        }
    }

    pub fn getTotalFrames(self: *const Self) usize {
        return switch (self.mode) {
            .record => |*state| self.recording.items.len + state.segment.items.len,
            else => self.recording.items.len,
        };
    }

    pub fn setCurrentFrameIndex(self: *Self, index: usize) void {
        const calculateUnprocessedFramesStart = struct {
            fn call(
                current_index: usize,
                target_index: usize,
                previous_start: ?usize,
            ) ?usize {
                if (previous_start) |i| {
                    return i;
                } else if (target_index > current_index) {
                    return @max(current_index +| 1, target_index -| max_number_of_unprocessed_frames);
                } else if (target_index < current_index) {
                    return @min(current_index -| 1, target_index +| max_number_of_unprocessed_frames);
                } else {
                    return null;
                }
            }
        }.call;
        switch (self.mode) {
            .pause => |*state| {
                state.unprocessed_frames_start = calculateUnprocessedFramesStart(
                    state.frame_index,
                    index,
                    state.unprocessed_frames_start,
                );
                state.frame_index = index;
            },
            .playback => |*state| {
                state.unprocessed_frames_start = calculateUnprocessedFramesStart(
                    state.frame_index,
                    index,
                    state.unprocessed_frames_start,
                );
                state.frame_progress = 0.5;
                state.frame_index = index;
            },
            .scrub => |*state| {
                state.unprocessed_frames_start = calculateUnprocessedFramesStart(
                    state.frame_index,
                    index,
                    state.unprocessed_frames_start,
                );
                state.frame_progress = 0.5;
                state.frame_index = index;
            },
            .live, .record => {
                self.cleanUpModeState();
                self.mode = .{ .pause = .{
                    .frame_index = index,
                    .unprocessed_frames_start = index,
                } };
            },
            .load, .save => return,
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
            .load => |*state| state.frame_index orelse return null,
            .save => |*state| state.frame_index orelse return null,
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

test "should present the last recorded frame as current when pausing the recording" {
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

    try testing.expectEqual(6, Callback.times_called);
    try testing.expectEqual(frame_2, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_2, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(7, Callback.times_called);
    try testing.expectEqual(frame_3, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_3, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

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

    try testing.expectEqual(7, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);

    controller.update(0.0, {}, Callback.call);

    try testing.expectEqual(8, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(9, Callback.times_called);
    try testing.expectEqual(frame_3, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_3, controller.getCurrentFrame().?.*);

    controller.update(2.0 * Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(11, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(11, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    controller.play();

    try testing.expectEqual(11, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);

    controller.update(0.0, {}, Callback.call);

    try testing.expectEqual(12, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_4, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(13, Callback.times_called);
    try testing.expectEqual(frame_3, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_3, controller.getCurrentFrame().?.*);

    controller.update(2.0 * Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(15, Callback.times_called);
    try testing.expectEqual(frame_1, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_1, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(15, Callback.times_called);
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

test "should scrub recording from beginning to end when scrubbing in forward direction after recording" {
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

    var frames: [100]model.Frame = undefined;
    for (0..frames.len) |index| {
        frames[index] = model.Frame{ .frames_since_round_start = @intCast(index) };
    }

    controller.record();
    for (&frames) |*frame| {
        controller.processFrame(frame, {}, Callback.call);
    }
    controller.scrub(.forward);

    try testing.expectEqual(frames.len, Callback.times_called);
    try testing.expectEqual(frames[frames.len - 1], Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frames[0], controller.getCurrentFrame().?.*);

    controller.update(0.0, {}, Callback.call);

    var scrubbing_time: f32 = 0.0;
    var frame_index: usize = 0;
    var frame_progress: f32 = 0.5;
    while (frame_index < frames.len) {
        try testing.expectEqual(frames.len + 1 + frame_index, Callback.times_called);
        try testing.expectEqual(frames[frame_index], Callback.last_frame);
        try testing.expect(controller.getCurrentFrame() != null);
        try testing.expectEqual(frames[frame_index], controller.getCurrentFrame().?.*);

        controller.update(Controller.frame_time, {}, Callback.call);

        const speed = std.math.lerp(
            Controller.min_scrub_speed,
            Controller.max_scrub_speed,
            sdk.math.smoothStep(0, Controller.scrub_ramp_up_time, scrubbing_time),
        );
        frame_progress += speed;
        frame_index += @intFromFloat(frame_progress);
        frame_progress -= @floor(frame_progress);
        scrubbing_time += Controller.frame_time;
    }

    controller.update(100 * Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(2 * frames.len, Callback.times_called);
    try testing.expectEqual(frames[frames.len - 1], Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frames[frames.len - 1], controller.getCurrentFrame().?.*);
}

test "should scrub recording from end to beginning when scrubbing in backward direction after recording" {
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

    var frames: [100]model.Frame = undefined;
    for (0..frames.len) |index| {
        frames[index] = model.Frame{ .frames_since_round_start = @intCast(index) };
    }

    controller.record();
    for (&frames) |*frame| {
        controller.processFrame(frame, {}, Callback.call);
    }
    controller.scrub(.backward);

    try testing.expectEqual(frames.len, Callback.times_called);
    try testing.expectEqual(frames[frames.len - 1], Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frames[frames.len - 1], controller.getCurrentFrame().?.*);

    var scrubbing_time: f32 = 0.0;
    var frame_index: usize = 0;
    var frame_progress: f32 = 0.5;
    while (frame_index < frames.len) {
        try testing.expectEqual(frames.len + frame_index, Callback.times_called);
        try testing.expectEqual(frames[frames.len - 1 - frame_index], Callback.last_frame);
        try testing.expect(controller.getCurrentFrame() != null);
        try testing.expectEqual(frames[frames.len - 1 - frame_index], controller.getCurrentFrame().?.*);

        controller.update(Controller.frame_time, {}, Callback.call);

        const speed = std.math.lerp(
            Controller.min_scrub_speed,
            Controller.max_scrub_speed,
            sdk.math.smoothStep(0, Controller.scrub_ramp_up_time, scrubbing_time),
        );
        frame_progress += speed;
        frame_index += @intFromFloat(frame_progress);
        frame_progress -= @floor(frame_progress);
        scrubbing_time += Controller.frame_time;
    }

    controller.update(100 * Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(2 * frames.len - 1, Callback.times_called);
    try testing.expectEqual(frames[0], Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frames[0], controller.getCurrentFrame().?.*);
}

test "should scrub staying on the same place when scrubbing in neutral direction" {
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
    controller.scrub(.neutral);

    try testing.expectEqual(4, Callback.times_called);
    try testing.expectEqual(frame_4, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_3, controller.getCurrentFrame().?.*);

    controller.update(Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(5, Callback.times_called);
    try testing.expectEqual(frame_3, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_3, controller.getCurrentFrame().?.*);

    controller.update(10 * Controller.frame_time, {}, Callback.call);

    try testing.expectEqual(5, Callback.times_called);
    try testing.expectEqual(frame_3, Callback.last_frame);
    try testing.expect(controller.getCurrentFrame() != null);
    try testing.expectEqual(frame_3, controller.getCurrentFrame().?.*);
}

test "should load the same frames that were previously saved" {
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

    controller.save("./test_assets/recording.irony");
    while (controller.mode == .save) {
        controller.update(Controller.frame_time, {}, Callback.call);
        std.Thread.yield() catch {};
    }
    try testing.expectEqual(true, controller.did_last_save_or_load_succeed);
    defer std.fs.cwd().deleteFile("./test_assets/recording.irony") catch @panic("Failed to cleanup test file.");

    controller.clear();
    controller.load("./test_assets/recording.irony");
    while (controller.mode == .load) {
        controller.update(Controller.frame_time, {}, Callback.call);
        std.Thread.yield() catch {};
    }
    try testing.expectEqual(true, controller.did_last_save_or_load_succeed);

    try testing.expectEqual(4, controller.getTotalFrames());
    try testing.expect(controller.getFrameAt(0) != null);
    try testing.expectEqual(frame_1, controller.getFrameAt(0).?.*);
    try testing.expect(controller.getFrameAt(1) != null);
    try testing.expectEqual(frame_2, controller.getFrameAt(1).?.*);
    try testing.expect(controller.getFrameAt(2) != null);
    try testing.expectEqual(frame_3, controller.getFrameAt(2).?.*);
    try testing.expect(controller.getFrameAt(3) != null);
    try testing.expectEqual(frame_4, controller.getFrameAt(3).?.*);
}

test "should pause at the previously current frame after recording save completes" {
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
    controller.setCurrentFrameIndex(2);
    controller.play();

    controller.save("./test_assets/recording.irony");
    while (controller.mode == .save) {
        controller.update(Controller.frame_time, {}, Callback.call);
        std.Thread.yield() catch {};
    }
    try testing.expectEqual(true, controller.did_last_save_or_load_succeed);
    defer std.fs.cwd().deleteFile("./test_assets/recording.irony") catch @panic("Failed to cleanup test file.");

    try testing.expect(controller.mode == .pause);
    try testing.expectEqual(2, controller.getCurrentFrameIndex());
}

test "should pause at the last frame of the recording after recording load completes" {
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
    controller.setCurrentFrameIndex(2);
    controller.play();

    controller.save("./test_assets/recording.irony");
    while (controller.mode == .save) {
        controller.update(Controller.frame_time, {}, Callback.call);
        std.Thread.yield() catch {};
    }
    try testing.expectEqual(true, controller.did_last_save_or_load_succeed);
    defer std.fs.cwd().deleteFile("./test_assets/recording.irony") catch @panic("Failed to cleanup test file.");

    controller.clear();
    controller.load("./test_assets/recording.irony");
    while (controller.mode == .load) {
        controller.update(Controller.frame_time, {}, Callback.call);
        std.Thread.yield() catch {};
    }
    try testing.expectEqual(true, controller.did_last_save_or_load_succeed);

    try testing.expect(controller.mode == .pause);
    try testing.expectEqual(3, controller.getCurrentFrameIndex());
}
