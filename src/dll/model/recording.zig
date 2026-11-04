const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("root.zig");

pub const Recording = std.ArrayList(model.Frame);

pub const RecordingFormat = enum {
    irony,
    json,
    json_zstd,

    const Self = @This();
    pub const all = std.meta.tags(Self);

    pub fn getFileExtension(self: Self) [:0]const u8 {
        return switch (self) {
            .irony => ".irony",
            .json => ".json",
            .json_zstd => ".json.zstd",
        };
    }

    pub fn fromFilePath(path: []const u8) ?Self {
        for (Self.all) |self| {
            const extension = self.getFileExtension();
            if (std.ascii.endsWithIgnoreCase(path, extension)) {
                return self;
            }
        }
        return null;
    }
};

const buffer_size = 4096;

pub fn saveRecording(
    allocator: std.mem.Allocator,
    io: std.Io,
    file_path: []const u8,
    frames: []const model.Frame,
) !void {
    const file = std.Io.Dir.cwd().createFile(io, file_path, .{}) catch |err| {
        sdk.misc.error_context.new("Failed to create or open file: {s}", .{file_path});
        return err;
    };
    defer file.close(io);
    var buffer: [buffer_size]u8 = undefined;
    var writer = file.writer(io, &buffer);

    const format = RecordingFormat.fromFilePath(file_path) orelse .irony;
    switch (format) {
        .irony => {
            sdk.io.writeIronyFormat(model.Frame, allocator, frames, &writer.interface) catch |err| {
                sdk.misc.error_context.append("Failed to write recording content in Irony format.", .{});
                return err;
            };
        },
        .json => {
            sdk.io.writeLargeJsonArray(model.Frame, frames, &writer.interface) catch |err| {
                sdk.misc.error_context.append("Failed to write recording content in JSON format.", .{});
                return err;
            };
        },
        .json_zstd => {
            errdefer sdk.misc.error_context.append("Failed to write recording content in JSON zstd format.", .{});
            var encoder = sdk.io.ZstdEncoder.init(allocator, &writer.interface, 0) catch |err| {
                sdk.misc.error_context.append("Failed to initialize zstd encoder.", .{});
                return err;
            };
            defer encoder.deinit();
            var encoder_writer = encoder.writer();
            sdk.io.writeLargeJsonArray(model.Frame, frames, &encoder_writer) catch |err| {
                sdk.misc.error_context.append("Failed to write recording content in JSON format.", .{});
                return err;
            };
            encoder_writer.flush() catch |err| {
                sdk.misc.error_context.new("Failed to flush zstd encoder.", .{});
                return err;
            };
        },
    }

    writer.end() catch |err| {
        sdk.misc.error_context.new("Failed to end file writing.", .{});
        return err;
    };
}

pub fn loadRecording(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8) !Recording {
    const file = std.Io.Dir.cwd().openFile(io, file_path, .{}) catch |err| {
        sdk.misc.error_context.new("Failed to open file: {s}", .{file_path});
        return err;
    };
    defer file.close(io);
    var buffer: [buffer_size]u8 = undefined;
    var reader = file.reader(io, &buffer);

    const format = RecordingFormat.fromFilePath(file_path) orelse .irony;
    switch (format) {
        .irony => {
            const slice = sdk.io.readIronyFormat(model.Frame, allocator, &reader.interface, &.{}) catch |err| {
                sdk.misc.error_context.append("Failed to read recording content from Irony format.", .{});
                return err;
            };
            return .fromOwnedSlice(slice);
        },
        .json => {
            return sdk.io.readLargeJsonArray(model.Frame, allocator, &reader.interface, &.{}) catch |err| {
                sdk.misc.error_context.append("Failed to read recording content from JSON format.", .{});
                return err;
            };
        },
        .json_zstd => {
            errdefer sdk.misc.error_context.append("Failed to read recording content from JSON zstd format.", .{});
            var decoder = sdk.io.ZstdDecoder.init(allocator, &reader.interface) catch |err| {
                sdk.misc.error_context.append("Failed to initialize zstd decoder.", .{});
                return err;
            };
            defer decoder.deinit();
            var decoder_buffer: [buffer_size]u8 = undefined;
            var decoder_reader = decoder.reader(&decoder_buffer);
            return sdk.io.readLargeJsonArray(model.Frame, allocator, &decoder_reader, &.{}) catch |err| {
                sdk.misc.error_context.append("Failed to read recording content from JSON format.", .{});
                return err;
            };
        },
    }
}

const testing = std.testing;

test "RecordingFormat.getFileExtension should return correct value" {
    try testing.expectEqualStrings(".irony", RecordingFormat.irony.getFileExtension());
    try testing.expectEqualStrings(".json", RecordingFormat.json.getFileExtension());
    try testing.expectEqualStrings(".json.zstd", RecordingFormat.json_zstd.getFileExtension());
}

test "RecordingFormat.fromFilePath should return correct value" {
    try testing.expectEqual(RecordingFormat.irony, RecordingFormat.fromFilePath("test.iRoNy"));
    try testing.expectEqual(RecordingFormat.json, RecordingFormat.fromFilePath("test.JsOn"));
    try testing.expectEqual(RecordingFormat.json_zstd, RecordingFormat.fromFilePath("test.jSoN.zStD"));
    try testing.expectEqual(null, RecordingFormat.fromFilePath("test.txt"));
}

test "loadRecording should load the same frames that the saveRecording saved when format is irony" {
    const frames = [_]model.Frame{
        .{ .frames_since_round_start = 1 },
        .{ .frames_since_round_start = 2 },
        .{ .frames_since_round_start = 3 },
    };
    try saveRecording(testing.allocator, testing.io, "recording.irony", &frames);
    defer std.Io.Dir.cwd().deleteFile(testing.io, "recording.irony") catch {
        @panic("Failed to clean up test file.");
    };
    var recording = try loadRecording(testing.allocator, testing.io, "recording.irony");
    defer recording.deinit(testing.allocator);
    try testing.expectEqualSlices(model.Frame, &frames, recording.items);
}

test "loadRecording should load the same frames that the saveRecording saved when format is json" {
    const frames = [_]model.Frame{
        .{ .frames_since_round_start = 1 },
        .{ .frames_since_round_start = 2 },
        .{ .frames_since_round_start = 3 },
    };
    try saveRecording(testing.allocator, testing.io, "recording.json", &frames);
    defer std.Io.Dir.cwd().deleteFile(testing.io, "recording.json") catch {
        @panic("Failed to clean up test file.");
    };
    var recording = try loadRecording(testing.allocator, testing.io, "recording.json");
    defer recording.deinit(testing.allocator);
    try testing.expectEqualSlices(model.Frame, &frames, recording.items);
}

test "loadRecording should load the same frames that the saveRecording saved when format is json zstd" {
    const frames = [_]model.Frame{
        .{ .frames_since_round_start = 1 },
        .{ .frames_since_round_start = 2 },
        .{ .frames_since_round_start = 3 },
    };
    try saveRecording(testing.allocator, testing.io, "recording.json.zstd", &frames);
    defer std.Io.Dir.cwd().deleteFile(testing.io, "recording.json.zstd") catch {
        @panic("Failed to clean up test file.");
    };
    var recording = try loadRecording(testing.allocator, testing.io, "recording.json.zstd");
    defer recording.deinit(testing.allocator);
    try testing.expectEqualSlices(model.Frame, &frames, recording.items);
}

test "saveRecording should overwrite the file if it already exists" {
    try saveRecording(testing.allocator, testing.io, "recording.irony", &.{
        .{ .frames_since_round_start = 1 },
        .{ .frames_since_round_start = 2 },
        .{ .frames_since_round_start = 3 },
    });
    defer std.Io.Dir.cwd().deleteFile(testing.io, "recording.irony") catch {
        @panic("Failed to clean up test file.");
    };
    try saveRecording(testing.allocator, testing.io, "recording.irony", &.{
        .{ .frames_since_round_start = 4 },
        .{ .frames_since_round_start = 5 },
        .{ .frames_since_round_start = 6 },
    });
    var recording = try loadRecording(testing.allocator, testing.io, "recording.irony");
    defer recording.deinit(testing.allocator);
    try testing.expectEqualSlices(model.Frame, &.{
        .{ .frames_since_round_start = 4 },
        .{ .frames_since_round_start = 5 },
        .{ .frames_since_round_start = 6 },
    }, recording.items);
}
