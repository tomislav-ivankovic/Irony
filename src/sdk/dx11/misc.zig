const std = @import("std");
const w32 = @import("win32").everything;
const dx11 = @import("root.zig");
const misc = @import("../misc/root.zig");

pub fn getWindowFromSwapChain(swap_chain: *const w32.IDXGISwapChain) !w32.HWND {
    var desc: w32.DXGI_SWAP_CHAIN_DESC = undefined;
    const result = swap_chain.GetDesc(&desc);
    if (dx11.Error.from(result)) |err| {
        misc.error_context.new("{f}", .{err});
        misc.error_context.append("IDXGISwapChain.GetDesc returned a failure value.", .{});
        return error.Dx11Error;
    }
    return desc.OutputWindow orelse error.NotFound;
}

pub fn getDeviceFromSwapChain(swap_chain: *const w32.IDXGISwapChain) !(*const w32.ID3D11Device) {
    var device: *const w32.ID3D11Device = undefined;
    const result = swap_chain.IDXGIDeviceSubObject.GetDevice(w32.IID_ID3D11Device, @ptrCast(&device));
    if (dx11.Error.from(result)) |err| {
        misc.error_context.new("{f}", .{err});
        misc.error_context.append("IDXGISwapChain.GetDevice returned a failure value.", .{});
        return error.Dx11Error;
    }
    return device;
}

const testing = std.testing;

test "getWindowFromSwapChain should return correct value" {
    const context = try dx11.TestingContext.init();
    defer context.deinit();
    try testing.expectEqual(context.window, getWindowFromSwapChain(context.swap_chain));
}

test "getDeviceFromSwapChain should return correct value" {
    const context = try dx11.TestingContext.init();
    defer context.deinit();
    try testing.expectEqual(context.device, getDeviceFromSwapChain(context.swap_chain));
}
