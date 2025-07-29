const std = @import("std");
const misc = @import("../misc/root.zig");
const memory = @import("root.zig");

pub const PatternCache = struct {
    allocator: std.mem.Allocator,
    memory_range: memory.Range,
    map: CacheMap,

    const Self = @This();
    const CacheMap = std.HashMap(memory.Pattern, ?usize, struct {
        pub fn hash(_: @This(), pattern: memory.Pattern) u64 {
            const bytes = pattern.getBytes();
            var hasher = std.hash.Wyhash.init(0);
            std.hash.autoHashStrat(&hasher, bytes, .Deep);
            return hasher.final();
        }

        pub fn eql(_: @This(), a: memory.Pattern, b: memory.Pattern) bool {
            return std.mem.eql(?u8, a.getBytes(), b.getBytes());
        }
    }, 80);
    const FileContent = std.json.ArrayHashMap(std.json.ArrayHashMap(?usize));

    pub fn init(allocator: std.mem.Allocator, memory_range: memory.Range) Self {
        return .{
            .allocator = allocator,
            .memory_range = memory_range,
            .map = CacheMap.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
    }

    pub fn findAddress(self: *Self, pattern: *const memory.Pattern) !usize {
        if (self.map.get(pattern.*)) |value| {
            return value orelse {
                misc.error_context.new("Memory pattern cached as not found.", .{});
                return error.NotFound;
            };
        }
        const address = pattern.findAddress(self.memory_range) catch |err_1| {
            if (err_1 == error.NotFound) {
                self.map.put(pattern.*, null) catch |err_2| {
                    std.log.warn("Failed to put memory pattern \"{}\" into cache. [{}]", .{ pattern, err_2 });
                };
            }
            return err_1;
        };
        self.map.put(pattern.*, address) catch |err| {
            std.log.warn("Failed to put memory pattern \"{}\" into cache. [{}]", .{ pattern, err });
        };
        return address;
    }

    pub fn load(self: *Self, file_path: []const u8, version_id: u32) !void {
        const file_data = std.fs.cwd().readFileAlloc(self.allocator, file_path, 131072) catch |err| {
            misc.error_context.new("Failed to read file: {s}", .{file_path});
            return err;
        };
        defer self.allocator.free(file_data);

        const parsed = std.json.parseFromSlice(FileContent, self.allocator, file_data, .{}) catch |err| {
            misc.error_context.new("Failed to parse file: {s}", .{file_path});
            return err;
        };
        defer parsed.deinit();

        var buffer: [10]u8 = undefined;
        const version_str = std.fmt.bufPrint(&buffer, "{}", .{version_id}) catch |err| {
            misc.error_context.new("Failed to convert version ID to string: {}", .{version_id});
            return err;
        };
        const version = parsed.value.map.getPtr(version_str) orelse {
            misc.error_context.new("Failed to find cache version \"{s}\" inside the file content.", .{version_str});
            return error.VersionNotFound;
        };

        self.map.clearRetainingCapacity();
        var iterator = version.map.iterator();
        while (iterator.next()) |entry| {
            const pattern_str = entry.key_ptr.*;
            const address = entry.value_ptr.*;
            const pattern = memory.Pattern.fromString(pattern_str) catch |err| {
                misc.error_context.append("Failed to convert string to memory pattern: {s}", .{pattern_str});
                return err;
            };
            self.map.put(pattern, address) catch |err| {
                misc.error_context.new("Failed to copy data from file structure to cache map.", .{});
                return err;
            };
        }
    }

    pub fn save(self: *const Self, file_path: []const u8, version_id: u32) !void {
        const file_data = std.fs.cwd().readFileAlloc(self.allocator, file_path, 131072) catch null;
        defer if (file_data) |data| {
            self.allocator.free(data);
        };

        var parsed = std.json.parseFromSlice(FileContent, self.allocator, file_data orelse "{}", .{}) catch |err| {
            misc.error_context.new("Failed to parse file: {s}", .{file_path});
            return err;
        };
        defer parsed.deinit();

        var buffer: [10]u8 = undefined;
        const version_str = std.fmt.bufPrint(&buffer, "{}", .{version_id}) catch |err| {
            misc.error_context.new("Failed to convert version ID to string: {}", .{version_id});
            return err;
        };
        const version = parsed.value.map.getPtr(version_str) orelse block: {
            const new_version = std.json.ArrayHashMap(?usize){};
            parsed.value.map.put(parsed.arena.allocator(), version_str, new_version) catch |err| {
                misc.error_context.new("Failed to add a new version inside the file structure.", .{});
                return err;
            };
            break :block parsed.value.map.getPtr(version_str).?;
        };

        version.map.clearRetainingCapacity();
        var iterator = self.map.iterator();
        while (iterator.next()) |entry| {
            const pattern = entry.key_ptr;
            const address = entry.value_ptr.*;
            const pattern_str = std.fmt.allocPrint(parsed.arena.allocator(), "{}", .{pattern}) catch |err| {
                misc.error_context.new("Failed to convert memory pattern to string: {}", .{pattern});
                return err;
            };
            version.map.put(parsed.arena.allocator(), pattern_str, address) catch |err| {
                misc.error_context.new("Failed to copy data from cache map to file structure.", .{});
                return err;
            };
        }

        const new_file_data = std.json.stringifyAlloc(
            self.allocator,
            parsed.value,
            .{ .whitespace = .indent_4 },
        ) catch |err| {
            misc.error_context.new("Failed to stringify the file structure.", .{});
            return err;
        };
        defer self.allocator.free(new_file_data);

        std.fs.cwd().writeFile(.{ .sub_path = file_path, .data = new_file_data }) catch |err| {
            misc.error_context.new("Failed to write the data to file: {s}", .{file_path});
            return err;
        };
    }
};

const testing = std.testing;

test "findAddress should cache the found address and use it the next time it's called with the same pattern" {
    var data = [_]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9 };
    const range = memory.Range.fromPointer(&data);
    const pattern_1 = memory.Pattern.fromComptime("04 ?? ?? 07");
    const pattern_2 = memory.Pattern.fromComptime("04 ?? ?? 07 08");
    var cache = PatternCache.init(testing.allocator, range);
    defer cache.deinit();

    try testing.expectEqual(@intFromPtr(&data[4]), cache.findAddress(&pattern_1));
    data[4] = 0x44;
    try testing.expectEqual(@intFromPtr(&data[4]), cache.findAddress(&pattern_1));
    try testing.expectError(error.NotFound, cache.findAddress(&pattern_2));
}

test "findAddress should cache the fact that address was not found and use it the next time it's called with the same pattern" {
    var data = [_]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9 };
    const range = memory.Range.fromPointer(&data);
    const pattern_1 = memory.Pattern.fromComptime("44 ?? ?? 07");
    const pattern_2 = memory.Pattern.fromComptime("44 ?? ?? 07 08");
    var cache = PatternCache.init(testing.allocator, range);
    defer cache.deinit();

    try testing.expectError(error.NotFound, cache.findAddress(&pattern_1));
    data[4] = 0x44;
    try testing.expectError(error.NotFound, cache.findAddress(&pattern_1));
    try testing.expectEqual(@intFromPtr(&data[4]), cache.findAddress(&pattern_2));
}

test "save/load should save/load the cache state to/from a file" {
    var data = [_]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9 };
    const range = memory.Range.fromPointer(&data);
    const pattern_1 = memory.Pattern.fromComptime("04 ?? ?? 07");
    const pattern_2 = memory.Pattern.fromComptime("05 ?? ?? 08");
    var cache_1 = PatternCache.init(testing.allocator, range);
    defer cache_1.deinit();
    var cache_2 = PatternCache.init(testing.allocator, range);
    defer cache_2.deinit();

    try testing.expectEqual(@intFromPtr(&data[4]), cache_1.findAddress(&pattern_1));
    try testing.expectEqual(@intFromPtr(&data[5]), cache_1.findAddress(&pattern_2));

    try cache_1.save("./test_assets/cache.json", 123);
    defer std.fs.cwd().deleteFile("./test_assets/cache.json") catch @panic("Failed to cleanup test file.");
    try cache_2.load("./test_assets/cache.json", 123);

    data[4] = 0x44;
    data[5] = 0x55;
    try testing.expectEqual(@intFromPtr(&data[4]), cache_2.findAddress(&pattern_1));
    try testing.expectEqual(@intFromPtr(&data[5]), cache_2.findAddress(&pattern_2));
}

test "save/load should work correctly when multiple version ids are inside the file" {
    var data = [_]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9 };
    const range = memory.Range.fromPointer(&data);
    const pattern = memory.Pattern.fromComptime("FF");
    var cache_1 = PatternCache.init(testing.allocator, range);
    defer cache_1.deinit();
    var cache_2 = PatternCache.init(testing.allocator, range);
    defer cache_2.deinit();

    data[4] = 0xFF;
    try testing.expectEqual(@intFromPtr(&data[4]), cache_1.findAddress(&pattern));
    data[4] = 0x04;
    data[5] = 0xFF;
    try testing.expectEqual(@intFromPtr(&data[5]), cache_2.findAddress(&pattern));
    data[5] = 0x05;

    try cache_1.save("./test_assets/cache.json", 111);
    defer std.fs.cwd().deleteFile("./test_assets/cache.json") catch @panic("Failed to cleanup test file.");
    try cache_2.save("./test_assets/cache.json", 222);

    try cache_1.load("./test_assets/cache.json", 222);
    try cache_2.load("./test_assets/cache.json", 111);

    try testing.expectEqual(@intFromPtr(&data[5]), cache_1.findAddress(&pattern));
    try testing.expectEqual(@intFromPtr(&data[4]), cache_2.findAddress(&pattern));
}
