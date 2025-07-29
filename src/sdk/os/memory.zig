const std = @import("std");
const w32 = @import("win32").everything;

pub fn isMemoryReadable(address: usize, size_in_bytes: usize) bool {
    return isMemoryAccessibleAndInOneOfModes(address, size_in_bytes, &.{
        w32.PAGE_EXECUTE_READ,
        w32.PAGE_EXECUTE_READWRITE,
        w32.PAGE_EXECUTE_WRITECOPY,
        w32.PAGE_READONLY,
        w32.PAGE_READWRITE,
        w32.PAGE_WRITECOPY,
    });
}

pub fn isMemoryWriteable(address: usize, size_in_bytes: usize) bool {
    return isMemoryAccessibleAndInOneOfModes(address, size_in_bytes, &.{
        w32.PAGE_EXECUTE_READWRITE,
        w32.PAGE_EXECUTE_WRITECOPY,
        w32.PAGE_READWRITE,
        w32.PAGE_WRITECOPY,
    });
}

fn isMemoryAccessibleAndInOneOfModes(
    address: usize,
    size_in_bytes: usize,
    comptime modes: []const w32.PAGE_PROTECTION_FLAGS,
) bool {
    if (size_in_bytes == 0) {
        return true;
    }
    if (!isMemoryRangeValid(address, size_in_bytes)) {
        return false;
    }
    var current_address = address;
    while (current_address <= address +% size_in_bytes -% 1) {
        var info: w32.MEMORY_BASIC_INFORMATION = undefined;
        const success = w32.VirtualQuery(@ptrFromInt(current_address), &info, @sizeOf(@TypeOf(info)));
        if (success == 0 or info.State != w32.MEM_COMMIT) {
            return false;
        }
        const protect = info.Protect;
        if (protect.PAGE_GUARD == 1) {
            return false;
        }
        const actual_mode = w32.PAGE_PROTECTION_FLAGS{
            .PAGE_EXECUTE = protect.PAGE_EXECUTE,
            .PAGE_EXECUTE_READ = protect.PAGE_EXECUTE_READ,
            .PAGE_EXECUTE_READWRITE = protect.PAGE_EXECUTE_READWRITE,
            .PAGE_EXECUTE_WRITECOPY = protect.PAGE_EXECUTE_WRITECOPY,
            .PAGE_NOACCESS = protect.PAGE_NOACCESS,
            .PAGE_READONLY = protect.PAGE_READONLY,
            .PAGE_READWRITE = protect.PAGE_READWRITE,
            .PAGE_WRITECOPY = protect.PAGE_WRITECOPY,
            .PAGE_TARGETS_NO_UPDATE = protect.PAGE_TARGETS_NO_UPDATE,
        };
        inline for (modes) |expected_mode| {
            if (actual_mode == expected_mode) {
                break;
            }
        } else {
            return false;
        }
        const next_address = @addWithOverflow(@intFromPtr(info.BaseAddress), info.RegionSize);
        if (next_address[1] == 1) {
            return true;
        }
        current_address = next_address[0];
    }
    return true;
}

pub fn isMemoryRangeValid(address: usize, size_in_bytes: usize) bool {
    const add_result = @addWithOverflow(address, size_in_bytes);
    return add_result[1] == 0 or add_result[0] == 0;
}

const testing = std.testing;

test "isMemoryReadable should return true when memory range is readable and writeable" {
    var memory = [_]u8{ 0, 1, 2, 3, 4 };
    const address = @intFromPtr(&memory);
    const size_in_bytes = @sizeOf(@TypeOf(memory));
    try testing.expectEqual(true, isMemoryReadable(address, size_in_bytes));
}

test "isMemoryReadable should return true when memory range is only readable" {
    const memory = [_]u8{ 0, 1, 2, 3, 4 };
    const address = @intFromPtr(&memory);
    const size_in_bytes = @sizeOf(@TypeOf(memory));
    try testing.expectEqual(true, isMemoryReadable(address, size_in_bytes));
}

test "isMemoryReadable should return false when memory range is not readable" {
    const address = std.math.maxInt(usize) - 5;
    const size_in_bytes = 5;
    try testing.expectEqual(false, isMemoryReadable(address, size_in_bytes));
}

test "isMemoryReadable should return false when memory address is null" {
    const address = 0;
    const size_in_bytes = 5;
    try testing.expectEqual(false, isMemoryReadable(address, size_in_bytes));
}

test "isMemoryWriteable should return true when memory range is readable and writeable" {
    var memory = [_]u8{ 0, 1, 2, 3, 4 };
    const address = @intFromPtr(&memory);
    const size_in_bytes = @sizeOf(@TypeOf(memory));
    try testing.expectEqual(true, isMemoryWriteable(address, size_in_bytes));
}

test "isMemoryWriteable should return false when memory range is only readable" {
    const memory = [_]u8{ 0, 1, 2, 3, 4 };
    const address = @intFromPtr(&memory);
    const size_in_bytes = @sizeOf(@TypeOf(memory));
    try testing.expectEqual(false, isMemoryWriteable(address, size_in_bytes));
}

test "isMemoryWriteable should return false when memory range is not readable" {
    const address = std.math.maxInt(usize) - 5;
    const size_in_bytes = 5;
    try testing.expectEqual(false, isMemoryWriteable(address, size_in_bytes));
}

test "isMemoryWriteable should return false when memory address is null" {
    const address = 0;
    const size_in_bytes = 5;
    try testing.expectEqual(false, isMemoryWriteable(address, size_in_bytes));
}

test "isMemoryRangeValid should return true when range does not overflow" {
    try testing.expectEqual(true, isMemoryRangeValid(123, 456));
    try testing.expectEqual(true, isMemoryRangeValid(123, 0));
    try testing.expectEqual(true, isMemoryRangeValid(0, 0));
    try testing.expectEqual(true, isMemoryRangeValid(0, 5));
    try testing.expectEqual(true, isMemoryRangeValid(0, std.math.maxInt(usize)));
    try testing.expectEqual(true, isMemoryRangeValid(1, std.math.maxInt(usize)));
    try testing.expectEqual(true, isMemoryRangeValid(std.math.maxInt(usize) - 4, 5));
}

test "isMemoryRangeValid should return true when range overflows" {
    try testing.expectEqual(false, isMemoryRangeValid(std.math.maxInt(usize) / 2, std.math.maxInt(usize)));
    try testing.expectEqual(false, isMemoryRangeValid(2, std.math.maxInt(usize)));
    try testing.expectEqual(false, isMemoryRangeValid(std.math.maxInt(usize) - 4, 6));
}
