const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const core = @import("../core/root.zig");
const model = @import("../model/root.zig");

pub const AutomationConfig = struct {
    Controller: type = core.Controller,
    time_zone: sdk.misc.TimeZone = .local,
};

pub fn Automation(comptime config: AutomationConfig) type {
    return struct {
        state: State = .idle,
        previous_frame_match_phase: ?model.MatchPhase = null,

        const Self = @This();
        const State = union(enum) {
            idle: void,
            recording: model.Source,
            saving: void,
        };
        const directory_name = "recordings";

        pub fn update(self: *Self, controller: *config.Controller) void {
            switch (self.state) {
                .idle, .recording => {},
                .saving => self.updateSavingState(controller),
            }
        }

        pub fn processFrame(
            self: *Self,
            io: std.Io,
            settings: *const model.AutomationSettings,
            controller: *config.Controller,
            frame: *const model.Frame,
        ) void {
            defer self.previous_frame_match_phase = frame.match_phase;
            switch (self.state) {
                .idle => self.processIdleFrame(settings, controller, frame),
                .recording => |source| self.processRecordingFrame(io, settings, controller, frame, source),
                .saving => self.updateSavingState(controller),
            }
        }

        fn processIdleFrame(
            self: *Self,
            settings: *const model.AutomationSettings,
            controller: *config.Controller,
            frame: *const model.Frame,
        ) void {
            if (!settings.enabled) {
                return;
            }
            const first_frame_of_match = self.previous_frame_match_phase == .intro and frame.match_phase == .round_start;
            if (!first_frame_of_match) {
                return;
            }
            const source = frame.source orelse return;
            const setting = switch (source) {
                .live_game => settings.live_games,
                .replay_loading => settings.replays,
                .practice, .replay_playback => return,
            };
            switch (setting) {
                .do_not_record => return,
                .only_record, .record_and_save => {},
            }
            switch (controller.mode) {
                .record, .load, .save => return,
                .live, .pause, .playback, .scrub => {},
            }
            controller.clear();
            controller.record();
            self.state = .{ .recording = source };
        }

        fn processRecordingFrame(
            self: *Self,
            io: std.Io,
            settings: *const model.AutomationSettings,
            controller: *config.Controller,
            frame: *const model.Frame,
            source: model.Source,
        ) void {
            const setting = switch (source) {
                .live_game, .practice => settings.live_games,
                .replay_loading, .replay_playback => settings.replays,
            };
            const is_enabled = settings.enabled and setting != .do_not_record;
            const in_a_match = frame.match_phase != null and frame.match_phase != .not_in_a_match;
            const still_recording = controller.mode == .record;
            const source_changed = frame.source != source;
            const last_frame_of_match = self.previous_frame_match_phase == .round_end and frame.match_phase == .outro;
            if (is_enabled and in_a_match and still_recording and !source_changed and !last_frame_of_match) {
                return;
            }
            if (!still_recording) {
                self.state = .idle;
                return;
            }
            if (!is_enabled) {
                controller.stop();
                self.state = .idle;
                return;
            }
            switch (setting) {
                .do_not_record, .only_record => {
                    controller.stop();
                    self.state = .idle;
                },
                .record_and_save => {
                    const last_frame = controller.getFrameAt(controller.getTotalFrames() -| 1) orelse frame;
                    var buffer: [config.Controller.FilePath.max_len]u8 = undefined;
                    if (constructSaveFilePath(&buffer, io, last_frame, settings.save_format)) |path| {
                        controller.save(io, path);
                        self.state = .saving;
                    } else |err| {
                        sdk.misc.error_context.append("Failed to construct save file path.", .{});
                        sdk.misc.error_context.logError(err);
                        controller.stop();
                        self.state = .idle;
                    }
                },
            }
        }

        fn updateSavingState(self: *Self, controller: *config.Controller) void {
            if (controller.mode == .save) {
                return;
            }
            controller.stop();
            self.state = .idle;
        }

        fn constructSaveFilePath(
            buffer: []u8,
            io: std.Io,
            last_frame: *const model.Frame,
            format: model.RecordingFormat,
        ) ![]const u8 {
            var writer = std.Io.Writer.fixed(buffer);
            const p1: *const model.Player = last_frame.getPlayerById(.player_1);
            const p2: *const model.Player = last_frame.getPlayerById(.player_2);

            writer.print("{s}\\", .{directory_name}) catch |err| {
                sdk.misc.error_context.new("Failed to write directory path: {s}\\", .{directory_name});
                return err;
            };

            std.Io.Dir.cwd().createDirPath(io, buffer[0..writer.end]) catch |err| {
                sdk.misc.error_context.append("Failed to make directory: {s}", .{buffer[0..writer.end]});
                return err;
            };

            const p1_name = p1.name.asSlice();
            const p2_name = p2.name.asSlice();
            const is_character_invalid: [256]bool = comptime block: {
                var result: [256]bool = @splat(false);
                for (0..31) |c| {
                    result[c] = true;
                }
                result['<'] = true;
                result['>'] = true;
                result['"'] = true;
                result['/'] = true;
                result['\\'] = true;
                result['|'] = true;
                result['?'] = true;
                result['*'] = true;
                break :block result;
            };
            const placeholder_character = '_';
            if (p1.name.len > 0 and p2.name.len > 0) {
                var p1_iterator = (std.unicode.Utf8View{ .bytes = p1_name }).iterator();
                while (p1_iterator.nextCodepointSlice()) |codepoint| {
                    if (codepoint.len == 1 and is_character_invalid[codepoint[0]]) {
                        writer.writeByte(placeholder_character) catch |err| {
                            sdk.misc.error_context.new("Failed to write player 1 name: {s}", .{p1_name});
                            return err;
                        };
                    } else {
                        writer.writeAll(codepoint) catch |err| {
                            sdk.misc.error_context.new("Failed to write player 1 name: {s}", .{p1_name});
                            return err;
                        };
                    }
                }
                writer.writeAll(" vs ") catch |err| {
                    sdk.misc.error_context.new("Failed to write player names: {s} vs {s}", .{ p1_name, p2_name });
                    return err;
                };
                var p2_iterator = (std.unicode.Utf8View{ .bytes = p2_name }).iterator();
                while (p2_iterator.nextCodepointSlice()) |codepoint| {
                    if (codepoint.len == 1 and is_character_invalid[codepoint[0]]) {
                        writer.writeByte(placeholder_character) catch |err| {
                            sdk.misc.error_context.new("Failed to write player 2 name: {s}", .{p2_name});
                            return err;
                        };
                    } else {
                        writer.writeAll(codepoint) catch |err| {
                            sdk.misc.error_context.new("Failed to write player 2 name: {s}", .{p2_name});
                            return err;
                        };
                    }
                }
                writer.writeAll("  ") catch |err| {
                    sdk.misc.error_context.new("Failed to write player names: {s} vs {s}", .{ p1_name, p2_name });
                    return err;
                };
            }

            if (p1.rounds_won) |p1_rounds| {
                if (p2.rounds_won) |p2_round| {
                    writer.print("{}-{}  ", .{ p1_rounds, p2_round }) catch |err| {
                        sdk.misc.error_context.new("Failed to write match score: {}-{}", .{ p1_rounds, p2_round });
                        return err;
                    };
                }
            }

            const nano_time = std.Io.Clock.real.now(io).nanoseconds;
            const ts = sdk.misc.Timestamp.fromNano(nano_time, config.time_zone) catch |err| {
                sdk.misc.error_context.append(
                    "Failed to construct timestamp structure for nano timestamp: {}",
                    .{nano_time},
                );
                return err;
            };
            writer.print(
                "{:0>4}-{:0>2}-{:0>2}T{:0>2}-{:0>2}-{:0>2}",
                .{ @abs(ts.year), ts.month, ts.day, ts.hour, ts.minute, ts.second },
            ) catch |err| {
                sdk.misc.error_context.new("Failed to write the timestamp part of file name.", .{});
                return err;
            };

            writer.writeAll(format.getFileExtension()) catch |err| {
                sdk.misc.error_context.new("Failed to write file extension: {s}", .{format.getFileExtension()});
                return err;
            };

            return buffer[0..writer.end];
        }
    };
}

const testing = std.testing;

const MockController = struct {
    mode: Mode,
    total_frames: usize = 100,
    last_frame: ?model.Frame = null,
    clear_call_count: usize = 0,
    record_call_count: usize = 0,
    save_call_count: usize = 0,
    last_save_io: ?std.Io = null,
    last_save_path: ?FilePath = null,
    stop_call_count: usize = 0,

    pub const FilePath = sdk.misc.BoundedArray(sdk.os.max_file_path_length, u8, 0, true);

    const Self = @This();
    pub const Mode = enum {
        live,
        record,
        pause,
        playback,
        scrub,
        load,
        save,
    };
    pub const ScrubDirection = enum {
        forward,
        backward,
        neutral,
    };

    pub fn clear(self: *Self) void {
        self.clear_call_count += 1;
    }

    pub fn record(self: *Self) void {
        self.record_call_count += 1;
        self.mode = .record;
    }

    pub fn save(self: *Self, io: std.Io, path: []const u8) void {
        self.save_call_count += 1;
        self.last_save_io = io;
        self.last_save_path = .fromSliceTrimmed(path);
        self.mode = .save;
    }

    pub fn stop(self: *Self) void {
        self.stop_call_count += 1;
        self.mode = .live;
    }

    pub fn getTotalFrames(self: *const Self) usize {
        return self.total_frames;
    }

    pub fn getFrameAt(self: *const Self, index: usize) ?*const model.Frame {
        if (index + 1 != self.total_frames) {
            return null;
        }
        if (self.last_frame) |*frame| {
            return frame;
        } else {
            return null;
        }
    }
};

test "should not clear and record when disabled in settings" {
    const settings_cases = [_]model.AutomationSettings{
        .{ .enabled = false, .live_games = .record_and_save, .replays = .record_and_save },
        .{ .enabled = true, .live_games = .do_not_record, .replays = .record_and_save },
        .{ .enabled = true, .live_games = .record_and_save, .replays = .do_not_record },
    };
    const sources = [_]model.Source{ .live_game, .live_game, .replay_loading };
    for (settings_cases, sources) |settings, source| {
        var controller = MockController{ .mode = .live };
        var automation = Automation(.{ .Controller = MockController }){};
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .intro,
        });
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .round_start,
        });
        try testing.expectEqual(0, controller.clear_call_count);
        try testing.expectEqual(0, controller.record_call_count);
    }
}

test "should never clear and record in practice or replay playback" {
    const settings = model.AutomationSettings{
        .enabled = true,
        .live_games = .record_and_save,
        .replays = .record_and_save,
    };
    const sources = [_]model.Source{ .practice, .replay_playback };
    for (sources) |source| {
        var controller = MockController{ .mode = .live };
        var automation = Automation(.{ .Controller = MockController }){};
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .intro,
        });
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .round_start,
        });
        try testing.expectEqual(0, controller.clear_call_count);
        try testing.expectEqual(0, controller.record_call_count);
    }
}

test "should not clear and record when the user is already recording, saving or loading" {
    const settings = model.AutomationSettings{
        .enabled = true,
        .live_games = .record_and_save,
        .replays = .record_and_save,
    };
    const modes = [_]MockController.Mode{ .record, .save, .load };
    const sources = [_]model.Source{ .live_game, .replay_loading };
    for (modes) |mode| {
        for (sources) |source| {
            var controller = MockController{ .mode = mode };
            var automation = Automation(.{ .Controller = MockController }){};
            automation.processFrame(testing.io, &settings, &controller, &.{
                .source = source,
                .match_phase = .intro,
            });
            automation.processFrame(testing.io, &settings, &controller, &.{
                .source = source,
                .match_phase = .round_start,
            });
            try testing.expectEqual(0, controller.clear_call_count);
            try testing.expectEqual(0, controller.record_call_count);
        }
    }
}

test "should start recording on the first frame of the match" {
    const settings_cases = [_]model.AutomationSettings{
        .{ .enabled = true, .live_games = .only_record, .replays = .do_not_record },
        .{ .enabled = true, .live_games = .do_not_record, .replays = .only_record },
    };
    const sources = [_]model.Source{ .live_game, .replay_loading };
    for (settings_cases, sources) |settings, source| {
        var controller = MockController{ .mode = .live };
        var automation = Automation(.{ .Controller = MockController }){};
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .not_in_a_match,
        });
        try testing.expectEqual(0, controller.clear_call_count);
        try testing.expectEqual(0, controller.record_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .intro,
        });
        try testing.expectEqual(0, controller.clear_call_count);
        try testing.expectEqual(0, controller.record_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .round_start,
        });
        try testing.expectEqual(1, controller.clear_call_count);
        try testing.expectEqual(1, controller.record_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .round_start,
        });
        try testing.expectEqual(1, controller.clear_call_count);
        try testing.expectEqual(1, controller.record_call_count);
    }
}

test "should stop recording after the last frame of the match when set to only record" {
    const settings_cases = [_]model.AutomationSettings{
        .{ .enabled = true, .live_games = .only_record, .replays = .do_not_record },
        .{ .enabled = true, .live_games = .do_not_record, .replays = .only_record },
    };
    const sources = [_]model.Source{ .live_game, .replay_loading };
    for (settings_cases, sources) |settings, source| {
        var controller = MockController{ .mode = .live };
        var automation = Automation(.{ .Controller = MockController }){};
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .intro,
        });
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .round_start,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .round_start,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .mid_round,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .mid_round,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .round_end,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .round_end,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .outro,
        });
        try testing.expectEqual(1, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .outro,
        });
        try testing.expectEqual(1, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
    }
}

test "should save recording after the last frame of the match when set to record and save" {
    const settings_cases = [_]model.AutomationSettings{
        .{ .enabled = true, .live_games = .record_and_save, .replays = .do_not_record },
        .{ .enabled = true, .live_games = .do_not_record, .replays = .record_and_save },
    };
    const sources = [_]model.Source{ .live_game, .replay_loading };
    for (settings_cases, sources) |settings, source| {
        var controller = MockController{ .mode = .live };
        var automation = Automation(.{ .Controller = MockController }){};
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .intro,
        });
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .round_start,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .round_start,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .mid_round,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .mid_round,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .round_end,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .round_end,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .outro,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(1, controller.save_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .outro,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(1, controller.save_call_count);
    }
}

test "should stop recording and not save when disabled in settings" {
    const enabled_cases = [_]model.AutomationSettings{
        .{ .enabled = true, .live_games = .record_and_save, .replays = .record_and_save },
        .{ .enabled = true, .live_games = .record_and_save, .replays = .do_not_record },
        .{ .enabled = true, .live_games = .do_not_record, .replays = .record_and_save },
    };
    const disabled_cases = [_]model.AutomationSettings{
        .{ .enabled = false, .live_games = .record_and_save, .replays = .record_and_save },
        .{ .enabled = true, .live_games = .do_not_record, .replays = .do_not_record },
        .{ .enabled = true, .live_games = .do_not_record, .replays = .do_not_record },
    };
    const sources = [_]model.Source{ .live_game, .live_game, .replay_loading };
    for (enabled_cases, disabled_cases, sources) |enabled, disabled, source| {
        var controller = MockController{ .mode = .live };
        var automation = Automation(.{ .Controller = MockController }){};
        automation.processFrame(testing.io, &enabled, &controller, &.{
            .source = source,
            .match_phase = .intro,
        });
        automation.processFrame(testing.io, &enabled, &controller, &.{
            .source = source,
            .match_phase = .round_start,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        automation.processFrame(testing.io, &enabled, &controller, &.{
            .source = source,
            .match_phase = .round_start,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        automation.processFrame(testing.io, &disabled, &controller, &.{
            .source = source,
            .match_phase = .round_start,
        });
        try testing.expectEqual(1, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        automation.processFrame(testing.io, &disabled, &controller, &.{
            .source = source,
            .match_phase = .round_start,
        });
        try testing.expectEqual(1, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
    }
}

test "should do nothing when the user interrupts the recording" {
    const settings = model.AutomationSettings{
        .enabled = true,
        .live_games = .record_and_save,
        .replays = .record_and_save,
    };
    const sources = [_]model.Source{ .live_game, .replay_loading };
    for (sources) |source| {
        var controller = MockController{ .mode = .live };
        var automation = Automation(.{ .Controller = MockController }){};
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .intro,
        });
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .round_start,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .mid_round,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        controller.mode = .pause;
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .round_end,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .outro,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(0, controller.save_call_count);
    }
}

test "should call stop on the controller after the save is complete" {
    const settings_cases = [_]model.AutomationSettings{
        .{ .enabled = true, .live_games = .record_and_save, .replays = .do_not_record },
        .{ .enabled = true, .live_games = .do_not_record, .replays = .record_and_save },
    };
    const sources = [_]model.Source{ .live_game, .replay_loading };
    for (settings_cases, sources) |settings, source| {
        var controller = MockController{ .mode = .live };
        var automation = Automation(.{ .Controller = MockController }){};
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .intro,
        });
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .round_start,
        });
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .round_end,
        });
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .outro,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(1, controller.save_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .not_in_a_match,
        });
        try testing.expectEqual(0, controller.stop_call_count);
        try testing.expectEqual(1, controller.save_call_count);
        controller.mode = .pause;
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .not_in_a_match,
        });
        try testing.expectEqual(1, controller.stop_call_count);
        try testing.expectEqual(1, controller.save_call_count);
        automation.processFrame(testing.io, &settings, &controller, &.{
            .source = source,
            .match_phase = .not_in_a_match,
        });
        try testing.expectEqual(1, controller.stop_call_count);
        try testing.expectEqual(1, controller.save_call_count);
    }
}

test "should save recording to the correct path" {
    var io = testing.io;
    var vtable = io.vtable.*;
    vtable.now = struct {
        fn call(_: ?*anyopaque, _: std.Io.Clock) std.Io.Timestamp {
            return .fromNanoseconds(1577934245123456789);
        }
    }.call;
    io.vtable = &vtable;
    inline for (model.RecordingFormat.all) |format| {
        const settings = model.AutomationSettings{
            .enabled = true,
            .live_games = .record_and_save,
            .save_format = format,
        };
        var controller = MockController{
            .mode = .live,
            .last_frame = .{ .players = .{
                .{ .name = .fromSliceTrimmed("</Player1\\>"), .rounds_won = 1 },
                .{ .name = .fromSliceTrimmed("\"|Player2?*"), .rounds_won = 2 },
            } },
        };
        var automation = Automation(.{
            .Controller = MockController,
            .time_zone = .utc,
        }){};
        automation.processFrame(io, &settings, &controller, &.{
            .source = .live_game,
            .match_phase = .intro,
        });
        automation.processFrame(io, &settings, &controller, &.{
            .source = .live_game,
            .match_phase = .round_start,
        });
        automation.processFrame(io, &settings, &controller, &.{
            .source = .live_game,
            .match_phase = .round_end,
        });
        automation.processFrame(io, &settings, &controller, &.{
            .source = .live_game,
            .match_phase = .outro,
        });
        try testing.expectEqual(1, controller.save_call_count);
        try testing.expectEqual(controller.last_save_io, io);
        try testing.expect(controller.last_save_path != null);
        try testing.expectEqualStrings(
            Automation(.{}).directory_name ++
                "\\__Player1__ vs __Player2__  1-2  2020-01-02T03-04-05" ++
                comptime format.getFileExtension(),
            controller.last_save_path.?.asSlice(),
        );
    }
}
