const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const core = @import("../core/root.zig");
const game = @import("../game/root.zig");
const model = @import("../model/root.zig");

pub const Controller = struct {
    recording: Recording,
    mode: Mode,

    const Self = @This();
    pub const Recording = std.ArrayList(model.Frame);
    pub const Mode = union(enum) {
        live: LiveState,
        record: void,
        pause: PauseState,
        playback: PlaybackState,
    };
    pub const LiveState = struct {
        frame: model.Frame = .{},
    };
    pub const PauseState = struct {
        frame_index: usize = 0,
    };
    pub const PlaybackState = struct {
        frame_index: usize = 0,
        time_since_last_frame: f32 = 0.0,
    };
    pub const empty_frame = model.Frame{};
    pub const frame_time = 1.0 / 60.0;

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .recording = Recording.init(allocator),
            .mode = .{ .live = .{} },
        };
    }

    pub fn deinit(self: *Self) void {
        self.recording.deinit();
    }

    pub fn processFrame(self: *Self, frame: *const model.Frame) void {
        switch (self.mode) {
            .live => |*state| state.frame = frame.*,
            .record => self.recording.append(frame.*) catch |err| {
                sdk.misc.error_context.new("Failed to append a frame to the recording.", .{});
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
        while (state.time_since_last_frame >= frame_time) {
            state.frame_index += 1;
            state.time_since_last_frame -= frame_time;
            if (state.frame_index >= self.recording.items.len) {
                self.pause();
                return;
            }
        }
    }

    pub fn play(self: *Self) void {
        const index = self.getCurrentFrameIndex() orelse 0;
        self.mode = .{ .playback = .{ .frame_index = index } };
    }

    pub fn pause(self: *Self) void {
        const index = self.getCurrentFrameIndex() orelse 0;
        self.mode = .{ .pause = .{ .frame_index = index } };
    }

    pub fn stop(self: *Self) void {
        self.mode = .{ .live = .{} };
    }

    pub fn record(self: *Self) void {
        self.mode = .record;
    }

    pub fn clear(self: *Self) void {
        self.recording.clearAndFree();
        self.mode = .{ .live = .{} };
    }

    pub fn setCurrentFrameIndex(self: *Self, index: usize) void {
        switch (self.mode) {
            .pause => |*state| state.frame_index = index,
            .playback => |*state| state.frame_index = index,
            else => self.mode = .{ .pause = .{ .frame_index = index } },
        }
    }

    pub fn getCurrentFrameIndex(self: *const Self) ?usize {
        const index = switch (self.mode) {
            .live => return null,
            .record => std.math.maxInt(usize),
            .pause => |*state| state.frame_index,
            .playback => |*state| state.frame_index,
        };
        if (index < self.recording.items.len) {
            return index;
        } else if (self.recording.items.len == 0) {
            return null;
        } else {
            return self.recording.items.len - 1;
        }
    }

    pub fn getCurrentFrame(self: *const Self) *const model.Frame {
        switch (self.mode) {
            .live => |*state| return &state.frame,
            .record, .pause, .playback => {
                if (self.getCurrentFrameIndex()) |index| {
                    return &self.recording.items[index];
                } else {
                    return &empty_frame;
                }
            },
        }
    }
};
