const std = @import("std");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const os = @import("../os/root.zig");

pub const BaseDir = struct {
    buffer: [os.max_file_path_length:0]u8,
    len: usize,

    const Self = @This();
    pub const working_dir = fromStr(".") catch @compileError("Failed to create a working directory base directory.");

    pub fn fromStr(base_dir: []const u8) !Self {
        if (base_dir.len > os.max_file_path_length) {
            misc.error_context.new(
                "Base directory \"{s}\" is larger then the maximum allowed file path: {}",
                .{ base_dir, os.max_file_path_length },
            );
            return error.NoSpaceLeft;
        }
        var buffer = [_:0]u8{0} ** (os.max_file_path_length);
        std.mem.copyForwards(u8, &buffer, base_dir);
        return .{
            .buffer = buffer,
            .len = base_dir.len,
        };
    }

    pub fn fromModule(module: *const os.Module) !Self {
        var module_path_buffer: [os.max_file_path_length]u8 = undefined;
        const module_path_size = module.getFilePath(&module_path_buffer) catch |err| {
            misc.error_context.append("Failed to get file path of module.", .{});
            return err;
        };
        const module_path = module_path_buffer[0..module_path_size];
        const base_dir = os.filePathToDirectoryPath(module_path);
        return fromStr(base_dir);
    }

    pub fn get(self: *const Self) [:0]const u8 {
        return self.buffer[0..self.len :0];
    }

    pub fn getPath(self: *const Self, buffer: *[os.max_file_path_length]u8, sub_path: []const u8) ![:0]u8 {
        return std.fmt.bufPrintZ(buffer, "{s}\\{s}", .{ self.get(), sub_path }) catch |err| {
            misc.error_context.new("Failed to put path into the buffer: {s}\\{s}", .{ self.get(), sub_path });
            return err;
        };
    }

    pub fn allocPath(self: *const Self, allocator: std.mem.Allocator, sub_path: []const u8) ![:0]u8 {
        return std.fmt.allocPrintSentinel(allocator, "{s}\\{s}", .{ self.get(), sub_path }, 0) catch |err| {
            misc.error_context.new("Failed to print allocate string: {s}\\{s}", .{ self.get(), sub_path });
            return err;
        };
    }
};

const testing = std.testing;

test "get should return the string passed to fromStr" {
    const base_dir = try BaseDir.fromStr("\\test_1\\test_2\\test_3");
    try testing.expectEqualStrings("\\test_1\\test_2\\test_3", base_dir.get());
}

test "fromModule should make the base dir the directory of the module" {
    const module = try os.Module.getMain();
    var module_path_buffer: [os.max_file_path_length]u8 = undefined;
    const module_path_size = try module.getFilePath(&module_path_buffer);
    const module_path = module_path_buffer[0..module_path_size];
    const module_directory = os.filePathToDirectoryPath(module_path);

    const base_dir = try BaseDir.fromModule(&module);
    try testing.expectEqualStrings(module_directory, base_dir.get());
}

test "getPath should combine base dir and sub dir" {
    const base_dir = try BaseDir.fromStr("\\test_1\\test_2\\test_3");
    var buffer: [os.max_file_path_length]u8 = undefined;
    const path = try base_dir.getPath(&buffer, "test_4\\test_5.txt");
    try testing.expectEqualStrings("\\test_1\\test_2\\test_3\\test_4\\test_5.txt", path);
}

test "allocPath should combine base dir and sub dir" {
    const base_dir = try BaseDir.fromStr("\\test_1\\test_2\\test_3");
    const path = try base_dir.allocPath(testing.allocator, "test_4\\test_5.txt");
    defer testing.allocator.free(path);
    try testing.expectEqualStrings("\\test_1\\test_2\\test_3\\test_4\\test_5.txt", path);
}
