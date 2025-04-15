const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const os = @import("root.zig");
const memory = @import("../memory/root.zig");

pub const Module = struct {
    process: os.Process,
    handle: w32.HINSTANCE,

    const Self = @This();

    pub fn getMain() !Self {
        const handle = w32.GetModuleHandleW(null) orelse {
            misc.errorContext().newFmt(null, "{}", os.Error.getLast());
            misc.errorContext().append(error.OsError, "GetModuleHandleW returned null.");
            return error.OsError;
        };
        return .{ .process = os.Process.getCurrent(), .handle = handle };
    }

    pub fn getLocal(name: []const u8) !Self {
        var buffer = [_:0]u16{0} ** os.max_file_path_length;
        const size = std.unicode.utf8ToUtf16Le(&buffer, name) catch |err| {
            misc.errorContext().newFmt(err, "Failed to convert \"{s}\" to UTF-16LE.", .{name});
            return err;
        };
        const utf16_name = buffer[0..size :0];
        const handle = w32.GetModuleHandleW(utf16_name) orelse {
            misc.errorContext().newFmt(null, "{}", os.Error.getLast());
            misc.errorContext().append(error.OsError, "GetModuleHandleW returned null.");
            return error.OsError;
        };
        return .{ .process = os.Process.getCurrent(), .handle = handle };
    }

    pub fn getRemote(process: os.Process, name: []const u8) !Self {
        return getRemoteFromSharedMemory(process, name) catch {
            return getRemoteBySearching(process, name) catch |err| {
                misc.errorContext().append(err, "Failed to get the remote module by searching.");
                return err;
            };
        };
    }

    fn getRemoteFromSharedMemory(process: os.Process, name: []const u8) !Self {
        const shared_value = os.SharedValue(w32.HINSTANCE).open(process.id, name, .{ .READ = 1 }) catch |err| {
            misc.errorContext().append(err, "Failed to open shared value.");
            return err;
        };
        defer shared_value.close() catch |err| {
            misc.errorContext().append(err, "Failed to close shared value.");
            misc.errorContext().logError();
        };
        const handle = shared_value.read() catch |err| {
            misc.errorContext().append(err, "Failed to read shared value.");
            return err;
        };
        return .{
            .process = process,
            .handle = handle,
        };
    }

    fn getRemoteBySearching(process: os.Process, name: []const u8) !Self {
        var buffer = [_:0]u16{0} ** os.max_file_path_length;
        const size = std.unicode.utf8ToUtf16Le(&buffer, name) catch |err| {
            misc.errorContext().newFmt(err, "Failed to convert \"{s}\" to UTF-16LE.", .{name});
            return err;
        };
        const utf16_name = buffer[0..size :0];
        const snapshot_handle = w32.CreateToolhelp32Snapshot(.{ .SNAPMODULE = 1 }, process.id.raw);
        if (snapshot_handle == w32.INVALID_HANDLE_VALUE) {
            misc.errorContext().newFmt(null, "{}", os.Error.getLast());
            misc.errorContext().append(error.OsError, "CreateToolhelp32Snapshot returned INVALID_HANDLE_VALUE.");
            return error.OsError;
        }
        defer {
            const success = w32.CloseHandle(snapshot_handle);
            if (success == 0) {
                misc.errorContext().newFmt(null, "{}", os.Error.getLast());
                misc.errorContext().append(error.OsError, "CloseHandle returned 0.");
                misc.errorContext().append(error.OsError, "Failed to close snapshot handle.");
                misc.errorContext().logError();
            }
        }
        var entry: w32.MODULEENTRY32W = undefined;
        entry.dwSize = @sizeOf(@TypeOf(entry));
        var success = w32.Module32FirstW(snapshot_handle, &entry);
        while (success != 0) : (success = w32.Module32NextW(snapshot_handle, &entry)) {
            const module_name = std.mem.sliceTo(&entry.szModule, 0);
            if (!std.mem.eql(u16, module_name, utf16_name)) {
                continue;
            }
            if (entry.hModule) |handle| {
                return .{
                    .process = process,
                    .handle = handle,
                };
            } else {
                misc.errorContext().new(error.NotFound, "Module found, but the handle is NULL.");
                return error.HandleNull;
            }
        }
        const os_error = os.Error.getLast();
        if (os_error.error_code == w32.WIN32_ERROR.ERROR_NO_MORE_FILES) {
            misc.errorContext().new(error.NotFound, "Module not found.");
            return error.NotFound;
        } else {
            misc.errorContext().newFmt(null, "{}", os_error);
            misc.errorContext().append(error.OsError, "Module32First or Module32Next returned 0.");
            return error.OsError;
        }
    }

    pub fn getFilePath(self: *const Self, path_buffer: *[os.max_file_path_length]u8) !usize {
        var buffer: [os.max_file_path_length:0]u16 = undefined;
        const size = w32.K32GetModuleFileNameExW(self.process.handle, self.handle, &buffer, buffer.len);
        if (size == 0) {
            misc.errorContext().newFmt(null, "{}", os.Error.getLast());
            misc.errorContext().append(error.OsError, "K32GetModuleFileNameExW returned 0.");
            return error.OsError;
        }
        return std.unicode.utf16LeToUtf8(path_buffer, buffer[0..size]) catch |err| {
            misc.errorContext().new(err, "Failed to convert UTF-16LE string to UTF8.");
            return err;
        };
    }

    pub fn getMemoryRange(self: *const Self) !memory.MemoryRange {
        var info: w32.MODULEINFO = undefined;
        const success = w32.K32GetModuleInformation(self.process.handle, self.handle, &info, @sizeOf(@TypeOf(info)));
        if (success == 0) {
            misc.errorContext().newFmt(null, "{}", os.Error.getLast());
            misc.errorContext().append(error.OsError, "K32GetModuleInformation returned 0.");
            return error.OsError;
        }
        return .{
            .base_address = @intFromPtr(info.lpBaseOfDll),
            .size_in_bytes = info.SizeOfImage,
        };
    }

    pub fn getProcedureAddress(self: *const Self, procedure_name: [:0]const u8) !usize {
        if (self.process.handle != os.Process.getCurrent().handle) {
            misc.errorContext().new(error.NotCurrentProcess, "Module is not part of the current process.");
            return error.NotCurrentProcess;
        }
        const address = w32.GetProcAddress(self.handle, procedure_name) orelse {
            misc.errorContext().newFmt(null, "{}", os.Error.getLast());
            misc.errorContext().append(error.OsError, "GetProcAddress returned null.");
            return error.OsError;
        };
        return @intFromPtr(address);
    }
};

const testing = std.testing;

test "getMain should return a module with readable memory range" {
    const module = try Module.getMain();
    const memory_range = try module.getMemoryRange();
    try testing.expectEqual(true, memory_range.isReadable());
}

test "getLocal should return a module with readable memory range when module name is valid" {
    const module = try Module.getLocal("kernel32.dll");
    const memory_range = try module.getMemoryRange();
    try testing.expectEqual(true, memory_range.isReadable());
}

test "getLocal should error when module name is invalid" {
    try testing.expectError(error.OsError, Module.getLocal("invalid module name"));
}

test "getRemote should return a module with readable memory range when module name is valid" {
    const module = Module.getRemote(os.Process.getCurrent(), "kernel32.dll") catch // Wine
        try Module.getRemote(os.Process.getCurrent(), "KERNEL32.DLL"); // Windows
    const memory_range = try module.getMemoryRange();
    try testing.expectEqual(true, memory_range.isReadable());
}

test "getRemote should error when module name is invalid" {
    try testing.expectError(error.NotFound, Module.getRemote(os.Process.getCurrent(), "invalid module name"));
}

test "getFilePath should return correct value" {
    const module = try Module.getLocal("kernel32.dll");
    var buffer: [os.max_file_path_length]u8 = undefined;
    const size = try module.getFilePath(&buffer);
    const path = buffer[0..size];
    if (std.mem.endsWith(u8, path, "l")) { // Wine
        try testing.expectStringEndsWith(path, "kernel32.dll");
    } else { // Windows
        try testing.expectStringEndsWith(path, "KERNEL32.DLL");
    }
}

test "getProcedureAddress should return a address when procedure name is valid" {
    const module = try Module.getLocal("kernel32.dll");
    _ = try module.getProcedureAddress("GetModuleHandleW");
}

test "getProcedureAddress should error when procedure name is invalid" {
    const module = try Module.getLocal("kernel32.dll");
    try testing.expectError(error.OsError, module.getProcedureAddress("invalid procedure name"));
}
