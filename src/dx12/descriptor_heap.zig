const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const dx12 = @import("root.zig");

pub const DescriptorHeap = struct {
    raw: *w32.ID3D12DescriptorHeap,
    test_allocation: if (builtin.is_test) *u8 else void,

    const Self = @This();

    pub fn create(device: *const w32.ID3D12Device) !Self {
        var descriptor_heap: *w32.ID3D12DescriptorHeap = undefined;
        const return_code = device.ID3D12Device_CreateDescriptorHeap(&.{
            .Type = .CBV_SRV_UAV,
            .NumDescriptors = 2,
            .Flags = .{ .SHADER_VISIBLE = 1 },
            .NodeMask = 1,
        }, w32.IID_ID3D12DescriptorHeap, @ptrCast(&descriptor_heap));
        if (return_code != w32.S_OK) {
            misc.errorContext().newFmt(
                error.Dx12Error,
                "ID3D12Device.CreateDescriptorHeap returned: {}",
                .{return_code},
            );
            return error.Dx12Error;
        }
        const test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {};
        return .{
            .raw = descriptor_heap,
            .test_allocation = test_allocation,
        };
    }

    pub fn destroy(self: *const Self) !void {
        const return_code = self.raw.IUnknown_Release();
        if (return_code != w32.S_OK) {
            misc.errorContext().newFmt(
                error.Dx12Error,
                "ID3D12Device.Release returned: {}",
                .{return_code},
            );
            return error.Dx12Error;
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
            self.raw.vtable.GetCPUDescriptorHandleForHeapStart,
        );
        var handle: w32.D3D12_CPU_DESCRIPTOR_HANDLE = undefined;
        get(self.raw, &handle);
        return handle;
    }

    pub fn getGpuDescriptorHandle(self: *const Self) w32.D3D12_GPU_DESCRIPTOR_HANDLE {
        // Bypass for this issue: https://github.com/marlersoft/zigwin32/issues/16
        const get: *const fn (
            self: *const w32.ID3D12DescriptorHeap,
            out: ?*w32.D3D12_GPU_DESCRIPTOR_HANDLE,
        ) callconv(@import("std").os.windows.WINAPI) void = @ptrCast(
            self.raw.vtable.GetGPUDescriptorHandleForHeapStart,
        );
        var handle: w32.D3D12_GPU_DESCRIPTOR_HANDLE = undefined;
        get(self.raw, &handle);
        return handle;
    }
};

const testing = std.testing;

test "create and destroy should succeed" {
    const context = try dx12.TestingContext.init();
    defer context.deinit();
    const heap = try DescriptorHeap.create(context.device);
    defer heap.destroy() catch @panic("Failed to destroy descriptor heap.");
}

test "getCpuDescriptorHandle should return non 0 value" {
    const context = try dx12.TestingContext.init();
    defer context.deinit();
    const heap = try DescriptorHeap.create(context.device);
    defer heap.destroy() catch @panic("Failed to destroy descriptor heap.");
    const handle = heap.getCpuDescriptorHandle();
    try testing.expect(handle.ptr != 0);
}

test "getGpuDescriptorHandle should return non 0 value" {
    const context = try dx12.TestingContext.init();
    defer context.deinit();
    const heap = try DescriptorHeap.create(context.device);
    defer heap.destroy() catch @panic("Failed to destroy descriptor heap.");
    const handle = heap.getGpuDescriptorHandle();
    try testing.expect(handle.ptr != 0);
}
