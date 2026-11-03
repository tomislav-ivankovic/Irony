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

// Caller needs to release the device!
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

// Caller needs to release the device context!
pub fn getDeviceContextFromDevice(device: *const w32.ID3D11Device) !(*const w32.ID3D11DeviceContext) {
    var device_context: ?*w32.ID3D11DeviceContext = undefined;
    device.GetImmediateContext(&device_context);
    return device_context orelse {
        misc.error_context.new("ID3D11Device.GetImmediateContext returned a null value.", .{});
        return error.Dx11Error;
    };
}

const testing = std.testing;

test "getWindowFromSwapChain should return correct value" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const context = try dx11.TestingContext.init();
    defer context.deinit();
    try testing.expectEqual(context.window, getWindowFromSwapChain(context.swap_chain));
}

test "getDeviceFromSwapChain should return correct value" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const context = try dx11.TestingContext.init();
    defer context.deinit();
    const device = try getDeviceFromSwapChain(context.swap_chain);
    defer _ = device.IUnknown.Release();
    try testing.expectEqual(context.device, device);
}

test "getDeviceContextFromDevice should return correct value" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const context = try dx11.TestingContext.init();
    defer context.deinit();
    const device_context = try getDeviceContextFromDevice(context.device);
    defer _ = device_context.IUnknown.Release();
    try testing.expectEqual(context.device_context, device_context);
}
