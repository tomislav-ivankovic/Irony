const std = @import("std");

pub const MemoryUsageAllocator = struct {
    base_allocator: std.mem.Allocator,
    used_bytes: std.atomic.Value(usize) = .init(0),

    const Self = @This();
    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    pub fn getUsedBytes(self: *const Self) usize {
        return self.used_bytes.load(.monotonic);
    }

    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, return_address: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(context));
        const pointer = self.base_allocator.rawAlloc(len, alignment, return_address) orelse return null;
        _ = self.used_bytes.fetchAdd(len, .monotonic);
        return pointer;
    }

    fn resize(
        context: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        return_address: usize,
    ) bool {
        const self: *Self = @ptrCast(@alignCast(context));
        if (!self.base_allocator.rawResize(memory, alignment, new_len, return_address)) {
            return false;
        }
        self.updateUsedBytes(memory.len, new_len);
        return true;
    }

    fn remap(
        context: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        return_address: usize,
    ) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(context));
        const pointer = self.base_allocator.rawRemap(memory, alignment, new_len, return_address) orelse return null;
        self.updateUsedBytes(memory.len, new_len);
        return pointer;
    }

    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, return_address: usize) void {
        const self: *Self = @ptrCast(@alignCast(context));
        self.base_allocator.rawFree(memory, alignment, return_address);
        _ = self.used_bytes.fetchSub(memory.len, .monotonic);
    }

    fn updateUsedBytes(self: *Self, old_len: usize, new_len: usize) void {
        if (new_len > old_len) {
            _ = self.used_bytes.fetchAdd(new_len - old_len, .monotonic);
        } else {
            _ = self.used_bytes.fetchSub(old_len - new_len, .monotonic);
        }
    }
};

const testing = std.testing;

test "getUsedBytes should return zero when nothing is allocated" {
    var usage_allocator = MemoryUsageAllocator{ .base_allocator = testing.allocator };
    try testing.expectEqual(0, usage_allocator.getUsedBytes());
}

test "getUsedBytes should return sum of allocated lengths" {
    var usage_allocator = MemoryUsageAllocator{ .base_allocator = testing.allocator };
    const allocator = usage_allocator.allocator();
    const a = try allocator.alloc(u8, 10);
    defer allocator.free(a);
    const b = try allocator.alloc(u32, 5);
    defer allocator.free(b);
    try testing.expectEqual(30, usage_allocator.getUsedBytes());
}

test "getUsedBytes should return zero after everything is freed" {
    var usage_allocator = MemoryUsageAllocator{ .base_allocator = testing.allocator };
    const allocator = usage_allocator.allocator();
    const a = try allocator.alloc(u8, 10);
    const b = try allocator.alloc(u32, 5);
    allocator.free(a);
    allocator.free(b);
    try testing.expectEqual(0, usage_allocator.getUsedBytes());
}

test "getUsedBytes should not change when allocation fails" {
    var usage_allocator = MemoryUsageAllocator{ .base_allocator = testing.failing_allocator };
    const allocator = usage_allocator.allocator();
    try testing.expectError(error.OutOfMemory, allocator.alloc(u8, 10));
    try testing.expectEqual(0, usage_allocator.getUsedBytes());
}

test "getUsedBytes should return new length after successful resize" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(&buffer);
    var usage_allocator = MemoryUsageAllocator{ .base_allocator = fixed_buffer_allocator.allocator() };
    const allocator = usage_allocator.allocator();
    const memory = try allocator.alloc(u8, 10);
    try testing.expectEqual(true, allocator.resize(memory, 25));
    try testing.expectEqual(25, usage_allocator.getUsedBytes());
    try testing.expectEqual(true, allocator.resize(memory.ptr[0..25], 5));
    try testing.expectEqual(5, usage_allocator.getUsedBytes());
}

test "getUsedBytes should not change when resize fails" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(&buffer);
    var usage_allocator = MemoryUsageAllocator{ .base_allocator = fixed_buffer_allocator.allocator() };
    const allocator = usage_allocator.allocator();
    const memory = try allocator.alloc(u8, 10);
    try testing.expectEqual(false, allocator.resize(memory, 200));
    try testing.expectEqual(10, usage_allocator.getUsedBytes());
}

test "getUsedBytes should return new length after successful remap" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(&buffer);
    var usage_allocator = MemoryUsageAllocator{ .base_allocator = fixed_buffer_allocator.allocator() };
    const allocator = usage_allocator.allocator();
    const memory = try allocator.alloc(u8, 10);
    const remapped = allocator.remap(memory, 25) orelse return error.RemapFailed;
    try testing.expectEqual(25, usage_allocator.getUsedBytes());
    _ = allocator.remap(remapped, 5) orelse return error.RemapFailed;
    try testing.expectEqual(5, usage_allocator.getUsedBytes());
}

test "getUsedBytes should not change when remap fails" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(&buffer);
    var usage_allocator = MemoryUsageAllocator{ .base_allocator = fixed_buffer_allocator.allocator() };
    const allocator = usage_allocator.allocator();
    const memory = try allocator.alloc(u8, 10);
    try testing.expectEqual(null, allocator.remap(memory, 200));
    try testing.expectEqual(10, usage_allocator.getUsedBytes());
}

test "allocator should allocate memory using the base allocator" {
    var buffer: [100]u8 = undefined;
    var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(&buffer);
    var usage_allocator = MemoryUsageAllocator{ .base_allocator = fixed_buffer_allocator.allocator() };
    const allocator = usage_allocator.allocator();
    const memory = try allocator.alloc(u8, 10);
    try testing.expect(fixed_buffer_allocator.ownsSlice(memory));
    try testing.expectEqual(10, fixed_buffer_allocator.end_index);
}
