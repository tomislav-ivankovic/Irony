const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const os = @import("../os/root.zig");

pub const VirtualCwdIo = struct {
    base_io: std.Io,
    dir: std.Io.Dir,
    path: Path,

    const Self = @This();
    pub const Path = misc.BoundedArray(os.max_file_path_length, u8, 0, false);

    pub fn init(base_io: std.Io, path: []const u8) !Self {
        const dir = std.Io.Dir.openDir(.cwd(), base_io, path, .{ .iterate = true }) catch |err| {
            misc.error_context.append("Failed to open directory: {s}", .{path});
            return err;
        };
        errdefer dir.close(base_io);
        const path_array = Path.fromSlice(path) catch |err| {
            misc.error_context.append("Failed to construct directory path from: {s}", .{path});
            return err;
        };
        return .{
            .base_io = base_io,
            .dir = dir,
            .path = path_array,
        };
    }

    pub fn initFromModule(base_io: std.Io, module: *const os.Module) !Self {
        var module_path_buffer: [os.max_file_path_length]u8 = undefined;
        const module_path_size = module.getFilePath(&module_path_buffer) catch |err| {
            misc.error_context.append("Failed to get file path of module.", .{});
            return err;
        };
        const module_path = module_path_buffer[0..module_path_size];
        const path = os.filePathToDirectoryPath(module_path);
        return init(base_io, path);
    }

    pub fn initFromMainModule(base_io: std.Io) !Self {
        const main_module = os.Module.getMain() catch |err| {
            misc.error_context.append("Failed to get process main module.", .{});
            return err;
        };
        return initFromModule(base_io, &main_module);
    }

    pub fn deinit(self: *const Self) void {
        self.dir.close(self.base_io);
    }

    pub fn io(self: *const Self) std.Io {
        return .{
            .userdata = @constCast(self),
            .vtable = &vtable,
        };
    }

    const vtable: std.Io.VTable = block: {
        var result: std.Io.VTable = undefined;
        for (@typeInfo(std.Io.VTable).@"struct".field_names) |field_name| {
            @field(result, field_name) = autoImplement(field_name);
        }
        result.dirRead = &dirRead;
        result.processCurrentPath = &processCurrentPath;
        result.processSetCurrentDir = &processSetCurrentDir;
        result.processSetCurrentPath = &processSetCurrentPath;
        result.processReplace = &processReplace;
        result.processSpawn = &processSpawn;
        result.netListenUnix = &netListenUnix;
        result.netConnectUnix = &netConnectUnix;
        break :block result;
    };

    fn autoImplement(comptime name: []const u8) @FieldType(std.Io.VTable, name) {
        const info = @typeInfo(@typeInfo(@FieldType(std.Io.VTable, name)).pointer.child).@"fn";
        const R = info.return_type.?;
        const P = struct {
            fn ParameterType(comptime index: usize) type {
                return info.param_types[index].?;
            }
        }.ParameterType;
        const Impl = struct {
            inline fn implementation(userdata: ?*anyopaque, args: anytype) R {
                const self: *const Self = @ptrCast(@alignCast(userdata));
                var mapped_args = args;
                inline for (&mapped_args) |*arg| {
                    if (@TypeOf(arg.*) == std.Io.Dir) {
                        arg.* = self.mapDir(arg.*);
                    }
                }
                return @call(.auto, @field(self.base_io.vtable, name), .{self.base_io.userdata} ++ mapped_args);
            }
            fn f0(u: ?*anyopaque) R {
                return implementation(u, .{});
            }
            fn f1(u: ?*anyopaque, p1: P(1)) R {
                return implementation(u, .{p1});
            }
            fn f2(u: ?*anyopaque, p1: P(1), p2: P(2)) R {
                return implementation(u, .{ p1, p2 });
            }
            fn f3(u: ?*anyopaque, p1: P(1), p2: P(2), p3: P(3)) R {
                return implementation(u, .{ p1, p2, p3 });
            }
            fn f4(u: ?*anyopaque, p1: P(1), p2: P(2), p3: P(3), p4: P(4)) R {
                return implementation(u, .{ p1, p2, p3, p4 });
            }
            fn f5(u: ?*anyopaque, p1: P(1), p2: P(2), p3: P(3), p4: P(4), p5: P(5)) R {
                return implementation(u, .{ p1, p2, p3, p4, p5 });
            }
            fn f6(u: ?*anyopaque, p1: P(1), p2: P(2), p3: P(3), p4: P(4), p5: P(5), p6: P(6)) R {
                return implementation(u, .{ p1, p2, p3, p4, p5, p6 });
            }
        };
        return switch (info.param_types.len) {
            1 => &Impl.f0,
            2 => &Impl.f1,
            3 => &Impl.f2,
            4 => &Impl.f3,
            5 => &Impl.f4,
            6 => &Impl.f5,
            7 => &Impl.f6,
            else => @compileError(std.fmt.comptimePrint(
                "Unsupported number of arguments {} on function: {s}",
                .{ info.param_types.len, name },
            )),
        };
    }

    fn mapDir(self: *const Self, dir: std.Io.Dir) std.Io.Dir {
        if (dir.handle == std.Io.Dir.cwd().handle) {
            return self.dir;
        }
        return dir;
    }

    fn resolvePath(self: *const Self, buffer: []u8, path: []const u8) error{NameTooLong}![]const u8 {
        if (std.fs.path.isAbsolute(path)) {
            return path;
        }
        return std.fmt.bufPrint(
            buffer,
            "{s}{c}{s}",
            .{ self.path.asSlice(), std.fs.path.sep, path },
        ) catch error.NameTooLong;
    }

    fn resolveUnixAddress(
        self: *const Self,
        buffer: *[std.Io.net.UnixAddress.max_len]u8,
        address: *const std.Io.net.UnixAddress,
    ) error{NameTooLong}!std.Io.net.UnixAddress {
        if (address.isAbstract()) {
            return address.*;
        }
        return .{ .path = try self.resolvePath(buffer, address.path) };
    }

    fn resolveProcessOptions(
        self: *const Self,
        buffer: []u8,
        options: anytype,
    ) error{NameTooLong}!@TypeOf(options) {
        var resolved = options;
        resolved.cwd = switch (options.cwd) {
            .inherit => .{ .dir = self.dir },
            .dir => |dir| .{ .dir = self.mapDir(dir) },
            .path => |path| .{ .path = try self.resolvePath(buffer, path) },
        };
        resolved.exe = switch (options.exe) {
            // On POSIX a relative argv[0] containing '/' is resolved against the parent's working directory.
            // On Windows it is resolved against the child's working directory, which is already resolved above.
            .detect => if (builtin.os.tag != .windows and
                options.argv.len > 0 and
                std.mem.findScalar(u8, options.argv[0], '/') != null)
                .{ .path = self.base_dir }
            else
                .detect,
            .search, .file => options.exe,
            .path => |dir| .{ .path = self.mapDir(dir) },
            .explicit => |explicit| .{ .explicit = .{ .dir = self.mapDir(explicit.dir), .path = explicit.path } },
        };
        return resolved;
    }

    fn dirRead(
        userdata: ?*anyopaque,
        reader: *std.Io.Dir.Reader,
        entries: []std.Io.Dir.Entry,
    ) std.Io.Dir.Reader.Error!usize {
        const self: *const Self = @ptrCast(@alignCast(userdata));
        const original_dir = reader.dir;
        reader.dir = self.mapDir(original_dir);
        defer reader.dir = original_dir;
        return self.base_io.vtable.dirRead(self.base_io.userdata, reader, entries);
    }

    fn processCurrentPath(userdata: ?*anyopaque, buffer: []u8) std.process.CurrentPathError!usize {
        const self: *const Self = @ptrCast(@alignCast(userdata));
        const path = self.path.asSlice();
        if (buffer.len < path.len) {
            return error.NameTooLong;
        }
        @memcpy(buffer[0..path.len], path);
        return path.len;
    }

    fn processSetCurrentDir(userdata: ?*anyopaque, dir: std.Io.Dir) std.process.SetCurrentDirError!void {
        _ = userdata;
        _ = dir;
        return error.OperationUnsupported;
    }

    fn processSetCurrentPath(userdata: ?*anyopaque, path: []const u8) std.process.SetCurrentPathError!void {
        _ = userdata;
        _ = path;
        return error.OperationUnsupported;
    }

    fn processReplace(userdata: ?*anyopaque, options: std.process.ReplaceOptions) std.process.ReplaceError {
        const self: *const Self = @ptrCast(@alignCast(userdata));
        var buffer: [os.max_file_path_length]u8 = undefined;
        const resolved = self.resolveProcessOptions(&buffer, options) catch |err| return err;
        return self.base_io.vtable.processReplace(self.base_io.userdata, resolved);
    }

    fn processSpawn(
        userdata: ?*anyopaque,
        options: std.process.SpawnOptions,
    ) std.process.SpawnError!std.process.Child {
        const self: *const Self = @ptrCast(@alignCast(userdata));
        var buffer: [os.max_file_path_length]u8 = undefined;
        const resolved = try self.resolveProcessOptions(&buffer, options);
        return self.base_io.vtable.processSpawn(self.base_io.userdata, resolved);
    }

    fn netListenUnix(
        userdata: ?*anyopaque,
        address: *const std.Io.net.UnixAddress,
        options: std.Io.net.UnixAddress.ListenOptions,
    ) std.Io.net.UnixAddress.ListenError!std.Io.net.Socket.Handle {
        const self: *const Self = @ptrCast(@alignCast(userdata));
        var buffer: [std.Io.net.UnixAddress.max_len]u8 = undefined;
        const resolved = self.resolveUnixAddress(&buffer, address) catch return error.AddressUnavailable;
        return self.base_io.vtable.netListenUnix(self.base_io.userdata, &resolved, options);
    }

    fn netConnectUnix(
        userdata: ?*anyopaque,
        address: *const std.Io.net.UnixAddress,
    ) std.Io.net.UnixAddress.ConnectError!std.Io.net.Socket.Handle {
        const self: *const Self = @ptrCast(@alignCast(userdata));
        var buffer: [std.Io.net.UnixAddress.max_len]u8 = undefined;
        const resolved = self.resolveUnixAddress(&buffer, address) catch return error.FileNotFound;
        return self.base_io.vtable.netConnectUnix(self.base_io.userdata, &resolved);
    }
};

const testing = std.testing;

test "init should return self with the provided path and correct virtual dir when directory exists" {
    try std.Io.Dir.cwd().createDir(testing.io, "virtual_cwd", .default_dir);
    defer std.Io.Dir.cwd().deleteDir(testing.io, "virtual_cwd") catch @panic("Failed to clean up virtual_cwd directory.");
    const dir = try std.Io.Dir.cwd().openDir(testing.io, "virtual_cwd", .{});
    defer dir.close(testing.io);
    const virtual_cwd_io = try VirtualCwdIo.init(testing.io, "virtual_cwd");
    defer virtual_cwd_io.deinit();

    try testing.expectEqualStrings("virtual_cwd", virtual_cwd_io.path.asSlice());

    var expected_buffer: [os.max_file_path_length]u8 = undefined;
    const expected_len = try dir.realPath(testing.io, &expected_buffer);
    const expected_path = expected_buffer[0..expected_len];
    var actual_buffer: [os.max_file_path_length]u8 = undefined;
    const actual_len = try virtual_cwd_io.dir.realPath(testing.io, &actual_buffer);
    const actual_path = actual_buffer[0..actual_len];
    try testing.expectEqualStrings(expected_path, actual_path);
}

test "initFromModule init should return self with path to the directory of the provided module" {
    const module = try os.Module.getMain();
    const virtual_cwd_io = try VirtualCwdIo.initFromModule(testing.io, &module);
    defer virtual_cwd_io.deinit();

    var module_path_buffer: [os.max_file_path_length]u8 = undefined;
    const module_path_size = try module.getFilePath(&module_path_buffer);
    const module_path = module_path_buffer[0..module_path_size];
    const module_directory = os.filePathToDirectoryPath(module_path);
    try testing.expectEqualStrings(module_directory, virtual_cwd_io.path.asSlice());
}

test "initFromModule init should return self with path to the directory of the main module" {
    const virtual_cwd_io = try VirtualCwdIo.initFromMainModule(testing.io);
    defer virtual_cwd_io.deinit();

    const module = try os.Module.getMain();
    var module_path_buffer: [os.max_file_path_length]u8 = undefined;
    const module_path_size = try module.getFilePath(&module_path_buffer);
    const module_path = module_path_buffer[0..module_path_size];
    const module_directory = os.filePathToDirectoryPath(module_path);
    try testing.expectEqualStrings(module_directory, virtual_cwd_io.path.asSlice());
}

test "should create files relative to the virtual working directory" {
    try std.Io.Dir.cwd().createDir(testing.io, "virtual_cwd", .default_dir);
    defer std.Io.Dir.cwd().deleteDir(testing.io, "virtual_cwd") catch @panic("Failed to clean up virtual_cwd directory.");
    const virtual_cwd_io = try VirtualCwdIo.init(testing.io, "virtual_cwd");
    defer virtual_cwd_io.deinit();
    const vio = virtual_cwd_io.io();

    const file = try std.Io.Dir.cwd().createFile(vio, "test.txt", .{});
    file.close(vio);
    defer std.Io.Dir.cwd().deleteFile(vio, "test.txt") catch @panic("Failed to clean up file: test.txt");

    try std.Io.Dir.cwd().access(testing.io, "./virtual_cwd/test.txt", .{});
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(testing.io, "test.txt", .{}));
}

test "should return absolute paths created based on virtual working directory" {
    try std.Io.Dir.cwd().createDir(testing.io, "virtual_cwd", .default_dir);
    defer std.Io.Dir.cwd().deleteDir(testing.io, "virtual_cwd") catch @panic("Failed to clean up virtual_cwd directory.");
    const virtual_cwd_io = try VirtualCwdIo.init(testing.io, "virtual_cwd");
    defer virtual_cwd_io.deinit();
    const vio = virtual_cwd_io.io();

    var real_cwd_path_buffer: [os.max_file_path_length]u8 = undefined;
    const real_cwd_path_len = try std.Io.Dir.cwd().realPath(testing.io, &real_cwd_path_buffer);
    const real_cwd_path = real_cwd_path_buffer[0..real_cwd_path_len];

    var expected_buffer: [os.max_file_path_length]u8 = undefined;
    const expected_path = try std.fmt.bufPrint(
        &expected_buffer,
        "{s}{c}virtual_cwd",
        .{ real_cwd_path, std.fs.path.sep },
    );

    var actual_path_buffer: [os.max_file_path_length]u8 = undefined;
    const actual_path_len = try std.Io.Dir.cwd().realPath(vio, &actual_path_buffer);
    const actual_path = actual_path_buffer[0..actual_path_len];

    try testing.expectEqualStrings(expected_path, actual_path);
}

test "should not change absolute paths" {
    try std.Io.Dir.cwd().createDir(testing.io, "virtual_cwd", .default_dir);
    defer std.Io.Dir.cwd().deleteDir(testing.io, "virtual_cwd") catch @panic("Failed to clean up virtual_cwd directory.");
    const virtual_cwd_io = try VirtualCwdIo.init(testing.io, "virtual_cwd");
    defer virtual_cwd_io.deinit();
    const vio = virtual_cwd_io.io();

    var real_cwd_path_buffer: [os.max_file_path_length]u8 = undefined;
    const real_cwd_path_len = try std.Io.Dir.cwd().realPath(testing.io, &real_cwd_path_buffer);
    const real_cwd_path = real_cwd_path_buffer[0..real_cwd_path_len];

    var file_path_buffer: [os.max_file_path_length]u8 = undefined;
    const file_path = try std.fmt.bufPrint(&file_path_buffer, "{s}{c}test.txt", .{ real_cwd_path, std.fs.path.sep });

    const file = try std.Io.Dir.cwd().createFile(vio, file_path, .{});
    file.close(vio);
    defer std.Io.Dir.cwd().deleteFile(testing.io, "test.txt") catch @panic("Failed to clean up file: test.txt");

    try std.Io.Dir.cwd().access(testing.io, "test.txt", .{});
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(testing.io, "./virtual_cwd/test.txt", .{}));
}

test "should not change directories other than the working directory" {
    try std.Io.Dir.cwd().createDir(testing.io, "virtual_cwd", .default_dir);
    defer std.Io.Dir.cwd().deleteDir(testing.io, "virtual_cwd") catch @panic("Failed to clean up virtual_cwd directory.");
    try std.Io.Dir.cwd().createDir(testing.io, "other_dir", .default_dir);
    defer std.Io.Dir.cwd().deleteDir(testing.io, "other_dir") catch @panic("Failed to clean up other_dir directory.");
    const other_dir = try std.Io.Dir.cwd().openDir(testing.io, "other_dir", .{});
    defer other_dir.close(testing.io);
    const virtual_cwd_io = try VirtualCwdIo.init(testing.io, "virtual_cwd");
    defer virtual_cwd_io.deinit();
    const vio = virtual_cwd_io.io();

    const file = try other_dir.createFile(vio, "test.txt", .{});
    file.close(vio);
    defer other_dir.deleteFile(testing.io, "test.txt") catch @panic("Failed to clean up file: test.txt");

    try std.Io.Dir.cwd().access(testing.io, "./other_dir/test.txt", .{});
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(testing.io, "./virtual_cwd/test.txt", .{}));
}
