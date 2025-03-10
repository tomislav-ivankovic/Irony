const std = @import("std");
const w32 = @import("win32").everything;
const dx12 = @import("root.zig");
const misc = @import("../misc/root.zig");

pub fn getWindowFromSwapChain(swap_chain: *const w32.IDXGISwapChain) !w32.HWND {
    var desc: w32.DXGI_SWAP_CHAIN_DESC = undefined;
    const return_code = swap_chain.IDXGISwapChain_GetDesc(&desc);
    if (return_code != w32.S_OK) {
        misc.errorContext().newFmt(error.Dx12Error, "IDXGISwapChain.GetDesc returned: {}", .{return_code});
        return error.Dx12Error;
    }
    return desc.OutputWindow orelse error.NotFound;
}

pub fn getDeviceFromSwapChain(swap_chain: *const w32.IDXGISwapChain) !(*const w32.ID3D12Device) {
    var device: *const w32.ID3D12Device = undefined;
    const return_code = swap_chain.IDXGIDeviceSubObject_GetDevice(w32.IID_ID3D12Device, @ptrCast(&device));
    if (return_code != w32.S_OK) {
        misc.errorContext().newFmt(error.Dx12Error, "IDXGISwapChain.GetDevice returned: {}", .{return_code});
        return error.Dx12Error;
    }
    return device;
}

pub fn getCpuDescriptorHandleForHeapStart(heap: *const w32.ID3D12DescriptorHeap) w32.D3D12_CPU_DESCRIPTOR_HANDLE {
    // Bypass for this issue: https://github.com/marlersoft/zigwin32/issues/16
    const get: *const fn (
        self: *const w32.ID3D12DescriptorHeap,
        out: ?*w32.D3D12_CPU_DESCRIPTOR_HANDLE,
    ) callconv(@import("std").os.windows.WINAPI) void = @ptrCast(
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
    ) callconv(@import("std").os.windows.WINAPI) void = @ptrCast(
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
    const return_code = context.device.ID3D12Device_CreateDescriptorHeap(&.{
        .Type = .CBV_SRV_UAV,
        .NumDescriptors = 3,
        .Flags = .{ .SHADER_VISIBLE = 1 },
        .NodeMask = 0,
    }, w32.IID_ID3D12DescriptorHeap, @ptrCast(&heap));
    if (return_code != w32.S_OK) {
        @panic("Failed to create descriptor heap.");
    }
    errdefer _ = heap.IUnknown_Release();

    const handle = getCpuDescriptorHandleForHeapStart(heap);
    try testing.expect(handle.ptr != 0);
}

test "getGpuDescriptorHandleForHeapStart should return non 0 value" {
    const context = try dx12.TestingContext.init();
    defer context.deinit();

    var heap: *w32.ID3D12DescriptorHeap = undefined;
    const return_code = context.device.ID3D12Device_CreateDescriptorHeap(&.{
        .Type = .CBV_SRV_UAV,
        .NumDescriptors = 3,
        .Flags = .{ .SHADER_VISIBLE = 1 },
        .NodeMask = 0,
    }, w32.IID_ID3D12DescriptorHeap, @ptrCast(&heap));
    if (return_code != w32.S_OK) {
        @panic("Failed to create descriptor heap.");
    }
    errdefer _ = heap.IUnknown_Release();

    const handle = getGpuDescriptorHandleForHeapStart(heap);
    try testing.expect(handle.ptr != 0);
}
