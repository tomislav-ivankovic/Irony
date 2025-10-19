const std = @import("std");
const misc = @import("../misc/root.zig");

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

pub fn loadSettings(comptime Type: type, file_path: []const u8) !Type {
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        misc.error_context.new("Failed to open file: {s}", .{file_path});
        return err;
    };
    defer file.close();
    var buffer: [1024]u8 = undefined;
    var file_reader = file.reader(&buffer);

    var arena: [1024]u8 = undefined; // All values in settings should be comptime known size.
    var allocator = std.heap.FixedBufferAllocator.init(&arena);
    var json_reader = std.json.Reader.init(allocator.allocator(), &file_reader.interface);
    defer json_reader.deinit();

    return settingsInnerParse(Type, allocator.allocator(), &json_reader, &.{}) catch |err| {
        misc.error_context.new("Failed to parse JSON content.", .{});
        return err;
    };
}

const parse_options = std.json.ParseOptions{
    .duplicate_field_behavior = .use_last,
    .ignore_unknown_fields = true,
    .max_value_len = std.json.Scanner.default_max_value_len,
    .allocate = .alloc_if_needed,
    .parse_numbers = true,
};

pub fn settingsInnerParse(
    comptime Type: type,
    allocator: std.mem.Allocator,
    reader: *std.json.Reader,
    default_value: *const Type,
) !Type {
    return switch (@typeInfo(Type)) {
        .array => parseArray(Type, allocator, reader, default_value),
        .@"struct" => parseStruct(Type, allocator, reader, default_value),
        else => std.json.innerParse(Type, allocator, reader, parse_options),
    };
}

fn parseArray(
    comptime Type: type,
    allocator: std.mem.Allocator,
    reader: *std.json.Reader,
    default_value: *const Type,
) !Type {
    const info = @typeInfo(Type).array;
    if (try reader.next() != .array_begin) {
        return error.UnexpectedToken;
    }
    var array: Type = undefined;
    for (0..info.len) |index| {
        array[index] = try settingsInnerParse(info.child, allocator, reader, &default_value[index]);
    }
    if (try reader.next() != .array_end) {
        return error.UnexpectedToken;
    }
    return array;
}

fn parseStruct(
    comptime Type: type,
    allocator: std.mem.Allocator,
    reader: *std.json.Reader,
    default_value: *const Type,
) !Type {
    if (std.meta.hasFn(Type, "settingsParse")) {
        return Type.settingsParse(allocator, reader, default_value);
    }
    if (std.meta.hasFn(Type, "jsonParse")) {
        return Type.jsonParse(allocator, reader, parse_options);
    }
    const info = @typeInfo(Type).@"struct";
    if (info.is_tuple) {
        if (try reader.next() != .array_begin) {
            return error.UnexpectedToken;
        }
        var tuple: Type = undefined;
        for (info.fields, 0..) |*field, index| {
            tuple[index] = try settingsInnerParse(field.type, allocator, reader, &default_value[index]);
        }
        if (try reader.next() != .array_end) {
            return error.UnexpectedToken;
        }
        return tuple;
    }
    if (try reader.next() != .object_begin) {
        return error.UnexpectedToken;
    }
    var object = default_value.*;
    while (true) {
        var token: ?std.json.Token = try reader.nextAllocMax(
            allocator,
            .alloc_if_needed,
            parse_options.max_value_len.?,
        );
        defer if (token) |t| switch (t) {
            .allocated_string => |slice| allocator.free(slice),
            else => {},
        };
        const field_name = switch (token.?) {
            .object_end => break, // end of object
            inline .string, .allocated_string => |slice| slice,
            else => return error.UnexpectedToken,
        };

        inline for (info.fields) |*field| {
            if (std.mem.eql(u8, field.name, field_name)) {
                if (token) |t| switch (t) { // don't waste memory on field name while deep inside recursion
                    .allocated_string => |slice| allocator.free(slice),
                    else => {},
                };
                token = null;
                const field_default = &@field(default_value, field.name);
                @field(object, field.name) = try settingsInnerParse(field.type, allocator, reader, field_default);
                break;
            }
        } else {
            try reader.skipValue();
        }
    }
    return object;
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

    const expected = Settings{
        .bool = true,
        .integer = 2,
        .float = 3.0,
        .array = .{ 4, 5, 6 },
        .@"struct" = .{
            .a = 'b',
            .b = 'c',
        },
    };
    try saveSettings(expected, "./test_assets/settings.json");
    defer std.fs.cwd().deleteFile("./test_assets/settings.json") catch @panic("Failed to cleanup test file.");
    const actual = try loadSettings(Settings, "./test_assets/settings.json");

    try testing.expectEqual(expected, actual);
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
    const InnerLoadedSettings = struct { a: u32, b: u32 };
    const LoadedSettings = struct {
        a: u32 = 1,
        b: u32 = 2,
        c: InnerLoadedSettings = .{ .a = 3, .b = 4 },
        d: InnerLoadedSettings = .{ .a = 5, .b = 6 },
    };
    const SavedSettings = struct {
        a: u32 = 123,
        c: struct {
            a: u32 = 456,
        } = .{},
    };

    try saveSettings(SavedSettings{}, "./test_assets/settings.json");
    defer std.fs.cwd().deleteFile("./test_assets/settings.json") catch @panic("Failed to cleanup test file.");
    const actual = try loadSettings(LoadedSettings, "./test_assets/settings.json");

    const expected = LoadedSettings{
        .a = 123,
        .b = 2,
        .c = .{ .a = 456, .b = 4 },
        .d = .{ .a = 5, .b = 6 },
    };
    try testing.expectEqual(expected, actual);
}

test "loadSettings should succeed when settings file contains more values then required" {
    const LoadedSettings = struct {
        a: u32 = 1,
        c: struct { a: u32 = 2 } = .{},
    };
    const SavedSettings = struct {
        a: u32 = 10,
        b: u32 = 20,
        c: struct {
            a: u32 = 30,
            b: u32 = 40,
        } = .{},
        d: struct {
            a: u32 = 50,
            b: u32 = 60,
        } = .{},
    };

    try saveSettings(SavedSettings{}, "./test_assets/settings.json");
    defer std.fs.cwd().deleteFile("./test_assets/settings.json") catch @panic("Failed to cleanup test file.");
    const actual = try loadSettings(LoadedSettings, "./test_assets/settings.json");

    const expected = LoadedSettings{
        .a = 10,
        .c = .{ .a = 30 },
    };
    try testing.expectEqual(expected, actual);
}
