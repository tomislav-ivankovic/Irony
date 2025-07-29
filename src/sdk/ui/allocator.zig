const std = @import("std");
const imgui = @import("imgui");

const AllocatorWrapper = struct {
    allocator: std.mem.Allocator,
    map: std.AutoHashMap([*]align(alignment) u8, usize),

    const Self = @This();
    const alignment = @alignOf(std.c.max_align_t);

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .map = std.AutoHashMap([*]align(alignment) u8, usize).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
    }

    pub fn alloc(self: *Self, size: usize) !*anyopaque {
        const slice = try self.allocator.alignedAlloc(u8, alignment, size);
        try self.map.put(slice.ptr, slice.len);
        return slice.ptr;
    }

    pub fn free(self: *Self, ptr: *anyopaque) !void {
        const aligned: [*]align(alignment) u8 = @alignCast(@ptrCast(ptr));
        const len = (self.map.fetchRemove(aligned) orelse return error.AllocationNotFound).value;
        const slice = aligned[0..len];
        self.allocator.free(slice);
    }
};

var current_wrapper: ?AllocatorWrapper = null;

pub fn setAllocator(allocator: ?std.mem.Allocator) void {
    if (current_wrapper) |*wrapper| {
        wrapper.deinit();
    }
    if (allocator) |a| {
        current_wrapper = AllocatorWrapper.init(a);
    } else {
        current_wrapper = null;
    }
    imgui.igSetAllocatorFunctions(alloc, free, null);
}

pub fn getAllocator() ?std.mem.Allocator {
    return if (current_wrapper) |*wrapper| wrapper.allocator else null;
}

fn alloc(size: usize, _: ?*anyopaque) callconv(.c) ?*anyopaque {
    if (current_wrapper) |*wrapper| {
        return wrapper.alloc(size) catch |err| {
            std.log.err("Imgui failed to allocate memory. [{}]", .{err});
            @panic("Imgui failed to allocate memory.");
        };
    } else {
        return std.c.malloc(size);
    }
}

fn free(ptr: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    if (current_wrapper) |*wrapper| {
        if (ptr) |pointer| {
            wrapper.free(pointer) catch |err| {
                std.log.err("Imgui failed to free memory. [{}]", .{err});
                @panic("Imgui failed to free memory.");
            };
        }
    } else {
        std.c.free(ptr);
    }
}

const testing = std.testing;

test "setAllocator should make Imgui use the provided allocator" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){};
    defer switch (gpa.deinit()) {
        .ok => {},
        .leak => std.log.err("GPA detected a memory leak.", .{}),
    };

    const old_allocator = getAllocator();
    setAllocator(gpa.allocator());
    defer setAllocator(old_allocator);

    const context = imgui.igCreateContext(null) orelse @panic("Failed to create context.");
    defer imgui.igDestroyContext(context);

    try testing.expect(gpa.total_requested_bytes > 0);
}

test "imgui should keep working even when allocator is set to null" {
    const old_allocator = getAllocator();
    setAllocator(null);
    defer setAllocator(old_allocator);

    const context = imgui.igCreateContext(null) orelse @panic("Failed to create context.");
    defer imgui.igDestroyContext(context);
}
