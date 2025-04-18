const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");

pub fn DescriptorHeapAllocator(comptime heap_size: usize) type {
    return struct {
        cpu_start: w32.D3D12_CPU_DESCRIPTOR_HANDLE,
        gpu_start: w32.D3D12_GPU_DESCRIPTOR_HANDLE,
        increment: u32,
        is_index_used: [heap_size]bool = [_]bool{false} ** heap_size,

        const Self = @This();

        pub fn alloc(
            self: *Self,
            cpu_handle: *w32.D3D12_CPU_DESCRIPTOR_HANDLE,
            gpu_handle: *w32.D3D12_GPU_DESCRIPTOR_HANDLE,
        ) !void {
            for (self.is_index_used, 0..) |is_used, index| {
                if (is_used) {
                    continue;
                }
                self.is_index_used[index] = true;
                cpu_handle.ptr = self.cpu_start.ptr + (index * self.increment);
                gpu_handle.ptr = self.gpu_start.ptr + (index * self.increment);
                return;
            }
            misc.errorContext().new("DescriptorHeap is full.");
            return error.HeapFull;
        }

        pub fn free(
            self: *Self,
            cpu_handle: w32.D3D12_CPU_DESCRIPTOR_HANDLE,
            gpu_handle: w32.D3D12_GPU_DESCRIPTOR_HANDLE,
        ) !void {
            const cpu_diff = @subWithOverflow(cpu_handle.ptr, self.cpu_start.ptr);
            const gpu_diff = @subWithOverflow(gpu_handle.ptr, self.gpu_start.ptr);
            if (cpu_diff[0] != gpu_diff[0] or cpu_diff[1] != gpu_diff[1]) {
                misc.errorContext().new("Provided CPU and GPU handle have different offsets from heap starts.");
                return error.OffsetsMismatch;
            }
            if (cpu_diff[1] == 1) {
                misc.errorContext().new("Provided handles are outside of heap bounds.");
                return error.HandleOutsideHeap;
            }
            const index = cpu_diff[0] / self.increment;
            if (index >= heap_size) {
                misc.errorContext().new("Provided handles are outside of heap bounds.");
                return error.HandleOutsideHeap;
            }
            if (!self.is_index_used[index]) {
                misc.errorContext().new("Provided handles are already free.");
                return error.AlreadyFree;
            }
            self.is_index_used[index] = false;
        }
    };
}

const testing = std.testing;

test "alloc should set correct handles" {
    var heap = DescriptorHeapAllocator(5){
        .cpu_start = .{ .ptr = 1 },
        .gpu_start = .{ .ptr = 2 },
        .increment = 3,
        .is_index_used = .{ true, true, false, true, false },
    };
    var cpu_handle: w32.D3D12_CPU_DESCRIPTOR_HANDLE = undefined;
    var gpu_handle: w32.D3D12_GPU_DESCRIPTOR_HANDLE = undefined;
    try heap.alloc(&cpu_handle, &gpu_handle);
    try testing.expectEqual(7, cpu_handle.ptr);
    try testing.expectEqual(8, gpu_handle.ptr);
}

test "alloc should mark correct index as used" {
    var heap = DescriptorHeapAllocator(5){
        .cpu_start = .{ .ptr = 1 },
        .gpu_start = .{ .ptr = 2 },
        .increment = 3,
        .is_index_used = .{ true, true, false, true, false },
    };
    var cpu_handle: w32.D3D12_CPU_DESCRIPTOR_HANDLE = undefined;
    var gpu_handle: w32.D3D12_GPU_DESCRIPTOR_HANDLE = undefined;
    try heap.alloc(&cpu_handle, &gpu_handle);
    try testing.expectEqual(.{ true, true, true, true, false }, heap.is_index_used);
}

test "alloc should error when heap full" {
    var heap = DescriptorHeapAllocator(5){
        .cpu_start = .{ .ptr = 1 },
        .gpu_start = .{ .ptr = 2 },
        .increment = 3,
        .is_index_used = .{ true, true, true, true, true },
    };
    var cpu_handle: w32.D3D12_CPU_DESCRIPTOR_HANDLE = undefined;
    var gpu_handle: w32.D3D12_GPU_DESCRIPTOR_HANDLE = undefined;
    try testing.expectError(error.HeapFull, heap.alloc(&cpu_handle, &gpu_handle));
}

test "free should mark correct index as not used" {
    var heap = DescriptorHeapAllocator(5){
        .cpu_start = .{ .ptr = 1 },
        .gpu_start = .{ .ptr = 2 },
        .increment = 3,
        .is_index_used = .{ true, true, false, true, false },
    };
    const cpu_handle = w32.D3D12_CPU_DESCRIPTOR_HANDLE{ .ptr = 4 };
    const gpu_handle = w32.D3D12_GPU_DESCRIPTOR_HANDLE{ .ptr = 5 };
    try heap.free(cpu_handle, gpu_handle);
    try testing.expectEqual(.{ true, false, false, true, false }, heap.is_index_used);
}

test "free should error when cpu and gpu handle offsets don't match" {
    var heap = DescriptorHeapAllocator(5){
        .cpu_start = .{ .ptr = 1 },
        .gpu_start = .{ .ptr = 2 },
        .increment = 3,
        .is_index_used = .{ true, true, false, true, false },
    };
    const cpu_handle = w32.D3D12_CPU_DESCRIPTOR_HANDLE{ .ptr = 5 };
    const gpu_handle = w32.D3D12_GPU_DESCRIPTOR_HANDLE{ .ptr = 5 };
    try testing.expectError(error.OffsetsMismatch, heap.free(cpu_handle, gpu_handle));
}

test "free should error when handles are smaller then heap starts" {
    var heap = DescriptorHeapAllocator(5){
        .cpu_start = .{ .ptr = 1 },
        .gpu_start = .{ .ptr = 2 },
        .increment = 3,
        .is_index_used = .{ true, true, false, true, false },
    };
    const cpu_handle = w32.D3D12_CPU_DESCRIPTOR_HANDLE{ .ptr = 0 };
    const gpu_handle = w32.D3D12_GPU_DESCRIPTOR_HANDLE{ .ptr = 1 };
    try testing.expectError(error.HandleOutsideHeap, heap.free(cpu_handle, gpu_handle));
}

test "free should error when handles are larger then heap limit" {
    var heap = DescriptorHeapAllocator(5){
        .cpu_start = .{ .ptr = 1 },
        .gpu_start = .{ .ptr = 2 },
        .increment = 3,
        .is_index_used = .{ true, true, false, true, false },
    };
    const cpu_handle = w32.D3D12_CPU_DESCRIPTOR_HANDLE{ .ptr = 16 };
    const gpu_handle = w32.D3D12_GPU_DESCRIPTOR_HANDLE{ .ptr = 17 };
    try testing.expectError(error.HandleOutsideHeap, heap.free(cpu_handle, gpu_handle));
}

test "free should error when handles are already free" {
    var heap = DescriptorHeapAllocator(5){
        .cpu_start = .{ .ptr = 1 },
        .gpu_start = .{ .ptr = 2 },
        .increment = 3,
        .is_index_used = .{ true, true, false, true, false },
    };
    const cpu_handle = w32.D3D12_CPU_DESCRIPTOR_HANDLE{ .ptr = 7 };
    const gpu_handle = w32.D3D12_GPU_DESCRIPTOR_HANDLE{ .ptr = 8 };
    try testing.expectError(error.AlreadyFree, heap.free(cpu_handle, gpu_handle));
}
