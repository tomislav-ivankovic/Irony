const std = @import("std");
const w32 = @import("win32").everything;
const dx12 = @import("root.zig");
const misc = @import("../misc/root.zig");

pub fn getWindowFromSwapChain(swap_chain: *const w32.IDXGISwapChain) !w32.HWND {
    var desc: w32.DXGI_SWAP_CHAIN_DESC = undefined;
    const result = swap_chain.GetDesc(&desc);
    if (dx12.Error.from(result)) |err| {
        misc.errorContext().newFmt("{}", .{err});
        misc.errorContext().append("IDXGISwapChain.GetDesc returned a failure value.");
        return error.Dx12Error;
    }
    return desc.OutputWindow orelse error.NotFound;
}

pub fn getDeviceFromSwapChain(swap_chain: *const w32.IDXGISwapChain) !(*const w32.ID3D12Device) {
    var device: *const w32.ID3D12Device = undefined;
    const result = swap_chain.IDXGIDeviceSubObject.GetDevice(w32.IID_ID3D12Device, @ptrCast(&device));
    if (dx12.Error.from(result)) |err| {
        misc.errorContext().newFmt("{}", .{err});
        misc.errorContext().append("IDXGISwapChain.GetDevice returned a failure value.");
        return error.Dx12Error;
    }
    return device;
}

pub fn getCpuDescriptorHandleForHeapStart(heap: *const w32.ID3D12DescriptorHeap) w32.D3D12_CPU_DESCRIPTOR_HANDLE {
    // Bypass for this issue: https://github.com/marlersoft/zigwin32/issues/16
    const get: *const fn (
        self: *const w32.ID3D12DescriptorHeap,
        out: ?*w32.D3D12_CPU_DESCRIPTOR_HANDLE,
    ) callconv(.winapi) void = @ptrCast(
        heap.vtable.GetCPUDescriptorHandleForHeapStart,
    );
    var handle: w32.D3D12_CPU_DESCRIPTOR_HANDLE = undefined;
    get(heap, &handle);
    return handle;
}

pub fn getGpuDescriptorHandleForHeapStart(heap: *const w32.ID3D12DescriptorHeap) w32.D3D12_GPU_DESCRIPTOR_HANDLE {
    // Bypass for this issue: https://github.com/marlersoft/zigwin32/issues/16
    const get: *const fn (
        self: *const w32.ID3D12DescriptorHeap,
        out: ?*w32.D3D12_GPU_DESCRIPTOR_HANDLE,
    ) callconv(.winapi) void = @ptrCast(
        heap.vtable.GetGPUDescriptorHandleForHeapStart,
    );
    var handle: w32.D3D12_GPU_DESCRIPTOR_HANDLE = undefined;
    get(heap, &handle);
    return handle;
}

const testing = std.testing;

test "getWindowFromSwapChain should return correct value" {
    const context = try dx12.TestingContext.init();
    defer context.deinit();
    try testing.expectEqual(context.window, getWindowFromSwapChain(context.swap_chain));
}

test "getDeviceFromSwapChain should return correct value" {
    const context = try dx12.TestingContext.init();
    defer context.deinit();
    try testing.expectEqual(context.device, getDeviceFromSwapChain(context.swap_chain));
}

test "getCpuDescriptorHandleForHeapStart should return non 0 value" {
    const context = try dx12.TestingContext.init();
    defer context.deinit();

    var heap: *w32.ID3D12DescriptorHeap = undefined;
    const result = context.device.CreateDescriptorHeap(&.{
        .Type = .CBV_SRV_UAV,
        .NumDescriptors = 3,
        .Flags = .{ .SHADER_VISIBLE = 1 },
        .NodeMask = 0,
    }, w32.IID_ID3D12DescriptorHeap, @ptrCast(&heap));
    if (dx12.Error.from(result) != null) {
        @panic("Failed to create descriptor heap.");
    }
    errdefer _ = heap.IUnknown.Release();

    const handle = getCpuDescriptorHandleForHeapStart(heap);
    try testing.expect(handle.ptr != 0);
}

test "getGpuDescriptorHandleForHeapStart should return non 0 value" {
    const context = try dx12.TestingContext.init();
    defer context.deinit();

    var heap: *w32.ID3D12DescriptorHeap = undefined;
    const result = context.device.CreateDescriptorHeap(&.{
        .Type = .CBV_SRV_UAV,
        .NumDescriptors = 3,
        .Flags = .{ .SHADER_VISIBLE = 1 },
        .NodeMask = 0,
    }, w32.IID_ID3D12DescriptorHeap, @ptrCast(&heap));
    if (dx12.Error.from(result) != null) {
        @panic("Failed to create descriptor heap.");
    }
    errdefer _ = heap.IUnknown.Release();

    const handle = getGpuDescriptorHandleForHeapStart(heap);
    try testing.expect(handle.ptr != 0);
}
