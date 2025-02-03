const std = @import("std");
const w32 = @import("win32").everything;
const w = std.unicode.utf8ToUtf16LeStringLiteral;
const Process = @import("process.zig").Process;
const MemoryRange = @import("../memory/memory_range.zig").MemoryRange;

pub const Module = struct {
    handle: w32.HINSTANCE,

    const Self = @This();

    pub fn getMain() !Self {
        const handle = w32.GetModuleHandleW(null) orelse return error.OsError;
        return .{ .handle = handle };
    }

    pub fn getByName(comptime name: []const u8) !Self {
        const handle = w32.GetModuleHandleW(w(name)) orelse return error.OsError;
        return .{ .handle = handle };
    }

    pub fn getMemoryRange(self: *const Self) !MemoryRange {
        const process = Process.getCurrent();
        var info: w32.MODULEINFO = undefined;
        const success = w32.K32GetModuleInformation(process.handle, self.handle, &info, @sizeOf(@TypeOf(info)));
        if (success == 0) {
            return error.OsError;
        }
        return .{
            .base_address = @intFromPtr(info.lpBaseOfDll),
            .size_in_bytes = info.SizeOfImage,
        };
    }

    pub fn getProcedureAddress(self: *const Self, procedure_name: [:0]const u8) !usize {
        const address = w32.GetProcAddress(self.handle, procedure_name) orelse return error.OsError;
        return @intFromPtr(address);
    }
};

const testing = std.testing;

test "getMain should return a module with readable memory range" {
    const module = try Module.getMain();
    const memory_range = try module.getMemoryRange();
    std.debug.print("\nmemory_range = {}\n", .{memory_range});
    try testing.expectEqual(true, memory_range.isReadable());
}

test "getByName should return a module with readable memory range when module name is valid" {
    const module = try Module.getByName("KERNEL32.DLL");
    const memory_range = try module.getMemoryRange();
    try testing.expectEqual(true, memory_range.isReadable());
}

test "getByName should return error when module name is invalid" {
    try testing.expectError(error.OsError, Module.getByName("invalid module name"));
}

test "getProcedureAddress should return a address when procedure name is valid" {
    const module = try Module.getByName("KERNEL32.DLL");
    _ = try module.getProcedureAddress("GetModuleHandleW");
}

test "getProcedureAddress should error when procedure name is invalid" {
    const module = try Module.getByName("KERNEL32.DLL");
    try testing.expectError(error.OsError, module.getProcedureAddress("invalid procedure name"));
}
