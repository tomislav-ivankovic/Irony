const std = @import("std");
const w32 = @import("win32").everything;

pub fn isMemoryReadable(address: usize, size_in_bytes: usize) bool {
    if (size_in_bytes == 0) {
        return true;
    }
    if (!isRangeValid(address, size_in_bytes)) {
        return false;
    }
    var current_address = address;
    while (current_address <= address +% size_in_bytes -% 1) {
        var info: w32.MEMORY_BASIC_INFORMATION = undefined;
        const success = w32.VirtualQuery(@ptrFromInt(current_address), &info, @sizeOf(@TypeOf(info)));
        const protect = info.Protect;
        const is_readable = success != 0 and
            (protect.PAGE_EXECUTE == 1 or
            protect.PAGE_EXECUTE_READ == 1 or
            protect.PAGE_EXECUTE_READWRITE == 1 or
            protect.PAGE_EXECUTE_WRITECOPY == 1 or
            protect.PAGE_READONLY == 1 or
            protect.PAGE_READWRITE == 1 or
            protect.PAGE_WRITECOPY == 1);
        if (!is_readable) {
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

pub fn isMemoryWriteable(address: usize, size_in_bytes: usize) bool {
    if (size_in_bytes == 0) {
        return true;
    }
    if (!isRangeValid(address, size_in_bytes)) {
        return false;
    }
    var current_address = address;
    while (current_address <= address +% size_in_bytes -% 1) {
        var info: w32.MEMORY_BASIC_INFORMATION = undefined;
        const success = w32.VirtualQuery(@ptrFromInt(current_address), &info, @sizeOf(@TypeOf(info)));
        const protect = info.Protect;
        const is_writeable = success != 0 and
            (protect.PAGE_EXECUTE_READWRITE == 1 or
            protect.PAGE_EXECUTE_WRITECOPY == 1 or
            protect.PAGE_READWRITE == 1 or
            protect.PAGE_WRITECOPY == 1);
        if (!is_writeable) {
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

pub fn isRangeValid(address: usize, size_in_bytes: usize) bool {
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

test "isRangeValid should return true when range does not overflow" {
    try testing.expectEqual(true, isRangeValid(123, 456));
    try testing.expectEqual(true, isRangeValid(123, 0));
    try testing.expectEqual(true, isRangeValid(0, 0));
    try testing.expectEqual(true, isRangeValid(0, 5));
    try testing.expectEqual(true, isRangeValid(0, std.math.maxInt(usize)));
    try testing.expectEqual(true, isRangeValid(1, std.math.maxInt(usize)));
    try testing.expectEqual(true, isRangeValid(std.math.maxInt(usize) - 4, 5));
}

test "isRangeValid should return true when range overflows" {
    try testing.expectEqual(false, isRangeValid(std.math.maxInt(usize) / 2, std.math.maxInt(usize)));
    try testing.expectEqual(false, isRangeValid(2, std.math.maxInt(usize)));
    try testing.expectEqual(false, isRangeValid(std.math.maxInt(usize) - 4, 6));
}
