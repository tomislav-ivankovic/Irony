const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const dx12 = @import("root.zig");

pub const Leftovers = struct {
    descriptor_heap: *w32.ID3D12DescriptorHeap,
    command_allocator: *w32.ID3D12CommandAllocator,
    graphics_command_list: *w32.ID3D12GraphicsCommandList,
    test_allocation: if (builtin.is_test) *u8 else void,

    const Self = @This();

    pub fn init(device: *const w32.ID3D12Device) !Self {
        var descriptor_heap: *w32.ID3D12DescriptorHeap = undefined;
        const heap_return_code = device.ID3D12Device_CreateDescriptorHeap(&.{
            .Type = .CBV_SRV_UAV,
            .NumDescriptors = 2,
            .Flags = .{ .SHADER_VISIBLE = 1 },
            .NodeMask = 1,
        }, w32.IID_ID3D12DescriptorHeap, @ptrCast(&descriptor_heap));
        if (heap_return_code != w32.S_OK) {
            misc.errorContext().newFmt(
                error.Dx12Error,
                "ID3D12Device.CreateDescriptorHeap returned: {}",
                .{heap_return_code},
            );
            misc.errorContext().append(error.Dx12Error, "Failed to create descriptor heap.");
            return error.Dx12Error;
        }
        errdefer {
            const return_code = descriptor_heap.IUnknown_Release();
            if (return_code != w32.S_OK) {
                misc.errorContext().newFmt(
                    error.Dx12Error,
                    "ID3D12DescriptorHeap.Release returned: {}",
                    .{return_code},
                );
                misc.errorContext().append(
                    error.Dx12Error,
                    "Failed release descriptor heap while recovering from error.",
                );
                misc.errorContext().logError();
            }
        }

        var command_allocator: *w32.ID3D12CommandAllocator = undefined;
        const allocator_return_code = device.ID3D12Device_CreateCommandAllocator(
            .DIRECT,
            w32.IID_ID3D12CommandAllocator,
            @ptrCast(&command_allocator),
        );
        if (allocator_return_code != w32.S_OK) {
            misc.errorContext().newFmt(
                error.Dx12Error,
                "ID3D12Device.CreateCommandAllocator returned: {}",
                .{allocator_return_code},
            );
            misc.errorContext().append(error.Dx12Error, "Failed to create command allocator.");
            return error.Dx12Error;
        }
        errdefer {
            const return_code = command_allocator.IUnknown_Release();
            if (return_code != w32.S_OK) {
                misc.errorContext().newFmt(
                    error.Dx12Error,
                    "ID3D12CommandAllocator.Release returned: {}",
                    .{return_code},
                );
                misc.errorContext().append(
                    error.Dx12Error,
                    "Failed release command allocator while recovering from error.",
                );
                misc.errorContext().logError();
            }
        }

        var graphics_command_list: *w32.ID3D12GraphicsCommandList = undefined;
        const list_return_code = device.ID3D12Device_CreateCommandList(
            0,
            .DIRECT,
            command_allocator,
            null,
            w32.IID_ID3D12GraphicsCommandList,
            @ptrCast(&graphics_command_list),
        );
        if (list_return_code != w32.S_OK) {
            misc.errorContext().newFmt(
                error.Dx12Error,
                "ID3D12Device.CreateCommandList returned: {}",
                .{list_return_code},
            );
            misc.errorContext().append(error.Dx12Error, "Failed to create command list.");
            return error.Dx12Error;
        }
        errdefer {
            const return_code = graphics_command_list.IUnknown_Release();
            if (return_code != w32.S_OK) {
                misc.errorContext().newFmt(
                    error.Dx12Error,
                    "ID3D12GraphicsCommandList.Release returned: {}",
                    .{return_code},
                );
                misc.errorContext().append(
                    error.Dx12Error,
                    "Failed release command list while recovering from error.",
                );
                misc.errorContext().logError();
            }
        }

        const test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {};

        return .{
            .descriptor_heap = descriptor_heap,
            .command_allocator = command_allocator,
            .graphics_command_list = graphics_command_list,
            .test_allocation = test_allocation,
        };
    }

    pub fn deinit(self: *const Self) void {
        const list_return_code = self.graphics_command_list.IUnknown_Release();
        if (list_return_code != w32.S_OK) {
            misc.errorContext().newFmt(
                error.Dx12Error,
                "ID3D12GraphicsCommandList.Release returned: {}",
                .{list_return_code},
            );
            misc.errorContext().append(
                error.Dx12Error,
                "Failed release command list while de-initializing DX12 leftovers.",
            );
            misc.errorContext().logError();
        }

        const allocator_return_code = self.command_allocator.IUnknown_Release();
        if (allocator_return_code != w32.S_OK) {
            misc.errorContext().newFmt(
                error.Dx12Error,
                "ID3D12CommandAllocator.Release returned: {}",
                .{allocator_return_code},
            );
            misc.errorContext().append(
                error.Dx12Error,
                "Failed release command allocator while de-initializing DX12 leftovers.",
            );
            misc.errorContext().logError();
        }

        const heap_return_code = self.descriptor_heap.IUnknown_Release();
        if (heap_return_code != w32.S_OK) {
            misc.errorContext().newFmt(
                error.Dx12Error,
                "ID3D12DescriptorHeap.Release returned: {}",
                .{heap_return_code},
            );
            misc.errorContext().append(
                error.Dx12Error,
                "Failed release descriptor heap while de-initializing DX12 leftovers.",
            );
            misc.errorContext().logError();
        }

        if (builtin.is_test) {
            std.testing.allocator.destroy(self.test_allocation);
        }
    }

    pub fn getCpuDescriptorHandle(self: *const Self) w32.D3D12_CPU_DESCRIPTOR_HANDLE {
        // Bypass for this issue: https://github.com/marlersoft/zigwin32/issues/16
        const get: *const fn (
            self: *const w32.ID3D12DescriptorHeap,
            out: ?*w32.D3D12_CPU_DESCRIPTOR_HANDLE,
        ) callconv(@import("std").os.windows.WINAPI) void = @ptrCast(
            self.descriptor_heap.vtable.GetCPUDescriptorHandleForHeapStart,
        );
        var handle: w32.D3D12_CPU_DESCRIPTOR_HANDLE = undefined;
        get(self.descriptor_heap, &handle);
        return handle;
    }

    pub fn getGpuDescriptorHandle(self: *const Self) w32.D3D12_GPU_DESCRIPTOR_HANDLE {
        // Bypass for this issue: https://github.com/marlersoft/zigwin32/issues/16
        const get: *const fn (
            self: *const w32.ID3D12DescriptorHeap,
            out: ?*w32.D3D12_GPU_DESCRIPTOR_HANDLE,
        ) callconv(@import("std").os.windows.WINAPI) void = @ptrCast(
            self.descriptor_heap.vtable.GetGPUDescriptorHandleForHeapStart,
        );
        var handle: w32.D3D12_GPU_DESCRIPTOR_HANDLE = undefined;
        get(self.descriptor_heap, &handle);
        return handle;
    }
};

const testing = std.testing;

test "init and deinit should succeed" {
    const context = try dx12.TestingContext.init();
    defer context.deinit();
    const leftovers = try Leftovers.init(context.device);
    defer leftovers.deinit();
}

test "getCpuDescriptorHandle should return non 0 value" {
    const context = try dx12.TestingContext.init();
    defer context.deinit();
    const leftovers = try Leftovers.init(context.device);
    defer leftovers.deinit();
    const handle = leftovers.getCpuDescriptorHandle();
    try testing.expect(handle.ptr != 0);
}

test "getGpuDescriptorHandle should return non 0 value" {
    const context = try dx12.TestingContext.init();
    defer context.deinit();
    const leftovers = try Leftovers.init(context.device);
    defer leftovers.deinit();
    const handle = leftovers.getGpuDescriptorHandle();
    try testing.expect(handle.ptr != 0);
}
