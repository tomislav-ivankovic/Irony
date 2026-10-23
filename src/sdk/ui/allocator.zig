const std = @import("std");
const imgui = @import("imgui");

const ImguiAllocator = struct {
    allocator: std.mem.Allocator,

    const Self = @This();
    const alignment = @alignOf(std.c.max_align_t);
    const header_size = std.mem.alignForward(usize, @sizeOf(usize), alignment);

    fn alloc(size: usize, user_data: ?*anyopaque) callconv(.c) ?*anyopaque {
        const self: *Self = @ptrCast(@alignCast(user_data));
        const total_size = header_size + size;
        const data = self.allocator.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(alignment), total_size) catch {
            std.log.err("Imgui failed to allocate {} bytes of memory.", .{size});
            return null;
        };
        const header: *usize = @ptrCast(data.ptr);
        header.* = size;
        return &data[header_size];
    }

    fn free(pointer: ?*anyopaque, user_data: ?*anyopaque) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(user_data));
        if (pointer == null) {
            return;
        }
        if (@intFromPtr(pointer) % alignment != 0) {
            std.log.err("Imgui attempted to free a misaligned pointer: 0x{X}", .{@intFromPtr(pointer)});
            return;
        }
        const data: [*]align(alignment) u8 = @ptrFromInt(@intFromPtr(pointer) - header_size);
        const header: *usize = @ptrCast(data);
        const total_size = header_size + header.*;
        self.allocator.free(data[0..total_size]);
    }
};

var current_imgui_allocator: ?ImguiAllocator = null;

pub fn setAllocator(allocator_maybe: ?std.mem.Allocator) void {
    if (allocator_maybe) |allocator| {
        current_imgui_allocator = .{ .allocator = allocator };
        imgui.igSetAllocatorFunctions(
            ImguiAllocator.alloc,
            ImguiAllocator.free,
            @ptrCast(&current_imgui_allocator),
        );
    } else {
        current_imgui_allocator = null;
        imgui.igSetAllocatorFunctions(cAlloc, cFree, null);
    }
}

pub fn getAllocator() ?std.mem.Allocator {
    return if (current_imgui_allocator) |*a| a.allocator else null;
}

fn cAlloc(size: usize, _: ?*anyopaque) callconv(.c) ?*anyopaque {
    return std.c.malloc(size);
}

fn cFree(pointer: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    std.c.free(pointer);
}

const testing = std.testing;

test "setAllocator should make Imgui use the provided allocator" {
    var gpa = std.heap.DebugAllocator(.{ .enable_memory_limit = true }){};
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
