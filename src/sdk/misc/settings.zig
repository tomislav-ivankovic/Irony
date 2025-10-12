const std = @import("std");
const misc = @import("../misc/root.zig");

pub fn loadSettings(comptime Type: type, file_path: []const u8) !Type {
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        misc.error_context.new("Failed to open file: {s}", .{file_path});
        return err;
    };
    defer file.close();
    var buffer: [1024]u8 = undefined;
    var file_reader = file.reader(&buffer);

    var arena: [1024]u8 = undefined; // All values in settings should be comptime known.
    var allocator = std.heap.FixedBufferAllocator.init(&arena);
    var json_reader = std.json.Reader.init(allocator.allocator(), &file_reader.interface);
    defer json_reader.deinit();

    const json_value = std.json.parseFromTokenSource(
        Type,
        allocator.allocator(),
        &json_reader,
        .{ .ignore_unknown_fields = true, .allocate = .alloc_if_needed },
    ) catch |err| {
        misc.error_context.new("Failed to parse JSON content.", .{});
        return err;
    };
    return json_value.value;
}

pub fn saveSettings(settings: anytype, file_path: []const u8) !void {
    const file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
        misc.error_context.new("Failed to create or open file: {s}", .{file_path});
        return err;
    };
    defer file.close();
    var buffer: [1024]u8 = undefined;
    var writer = file.writer(&buffer);

    std.json.Stringify.value(settings, .{ .whitespace = .indent_4 }, &writer.interface) catch |err| {
        misc.error_context.new("Failed to stringify value as JSON.", .{});
        return err;
    };
    writer.interface.flush() catch |err| {
        misc.error_context.new("Failed to flush file writer.", .{});
        return err;
    };
}

const testing = std.testing;

test "loadSettings should should load the same settings that were saved with saveSettings" {
    const Settings = struct {
        bool: bool = false,
        integer: i32 = 1,
        float: f32 = 2.0,
        array: [3]u16 = .{ 3, 4, 5 },
        @"struct": struct {
            a: u8 = 'a',
            b: u8 = 'b',
        } = .{},
    };

    try saveSettings(Settings{}, "./test_assets/settings.json");
    defer std.fs.cwd().deleteFile("./test_assets/settings.json") catch @panic("Failed to cleanup test file.");
    const settings = try loadSettings(Settings, "./test_assets/settings.json");

    try testing.expectEqual(Settings{}, settings);
}

test "saveSettings should overwrite the settings file if it already exists" {
    const Settings = struct { a: u32 = 0 };

    try saveSettings(Settings{ .a = 1 }, "./test_assets/settings.json");
    defer std.fs.cwd().deleteFile("./test_assets/settings.json") catch @panic("Failed to cleanup test file.");
    try saveSettings(Settings{ .a = 2 }, "./test_assets/settings.json");
    const settings = try loadSettings(Settings, "./test_assets/settings.json");

    try testing.expectEqual(Settings{ .a = 2 }, settings);
}

test "loadSettings should load settings partially when settings file does not have all values" {
    const SavedSettings = struct { a: u32 = 1 };
    const LoadedSettings = struct { a: u32 = 2, b: u32 = 3 };

    try saveSettings(SavedSettings{}, "./test_assets/settings.json");
    defer std.fs.cwd().deleteFile("./test_assets/settings.json") catch @panic("Failed to cleanup test file.");
    const result = try loadSettings(LoadedSettings, "./test_assets/settings.json");

    try testing.expectEqual(LoadedSettings{ .a = 1, .b = 3 }, result);
}
