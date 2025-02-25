const std = @import("std");
const w32 = @import("win32").everything;
const os = @import("root.zig");
const misc = @import("../misc/root.zig");
const w = std.unicode.utf8ToUtf16LeStringLiteral;

pub const PresentFunction = std.meta.FieldType(w32.IDXGISwapChain.VTable, .Present);

pub fn findPresentFunction() !PresentFunction {
    const module = os.Module.getMain() catch |err| {
        misc.errorContext().new(err, "Failed to get the main process module.");
        return err;
    };

    const window_class = w32.WNDCLASSEXW{
        .cbSize = @sizeOf(w32.WNDCLASSEXW),
        .style = .{
            .HREDRAW = 1,
            .VREDRAW = 1,
        },
        .lpfnWndProc = w32.DefWindowProcW,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = module.handle,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = w("IronyWindowClass"),
        .hIconSm = null,
    };

    const register_success = w32.RegisterClassExW(&window_class);
    if (register_success == 0) {
        misc.errorContext().newFmt(null, "{}", os.OsError.getLast());
        misc.errorContext().append(error.OsError, "RegisterClassExW returned 0.");
        return error.OsError;
    }
    defer {
        const success = w32.UnregisterClassW(window_class.lpszClassName, window_class.hInstance);
        if (success == 0) {
            misc.errorContext().newFmt(null, "{}", os.OsError.getLast());
            misc.errorContext().append(error.OsError, "UnregisterClassW returned 0.");
            misc.errorContext().logError();
        }
    }

    const window = w32.CreateWindowExW(
        .{},
        window_class.lpszClassName,
        w("IronyWindowClass"),
        w32.WS_OVERLAPPEDWINDOW,
        0,
        0,
        100,
        100,
        null,
        null,
        window_class.hInstance,
        null,
    ) orelse {
        misc.errorContext().newFmt(null, "{}", os.OsError.getLast());
        misc.errorContext().append(error.OsError, "CreateWindowExW returned 0.");
        return error.OsError;
    };
    defer {
        const success = w32.DestroyWindow(window);
        if (success == 0) {
            misc.errorContext().newFmt(null, "{}", os.OsError.getLast());
            misc.errorContext().append(error.OsError, "DestroyWindow returned 0.");
            misc.errorContext().logError();
        }
    }

    const dxgi_module = os.Module.getLocal("dxgi.dll") catch |err| {
        misc.errorContext().new(err, "Failed to get local module: dxgi.dll");
        return err;
    };

    const create_dxgi_factory_address = dxgi_module.getProcedureAddress("CreateDXGIFactory") catch |err| {
        misc.errorContext().new(err, "Failed to get procedure address of: CreateDXGIFactory");
        return err;
    };
    const CreateDXGIFactory: *const @TypeOf(w32.CreateDXGIFactory) = @ptrFromInt(create_dxgi_factory_address);
    var factory: *w32.IDXGIFactory = undefined;
    const factory_return_code = CreateDXGIFactory(w32.IID_IDXGIFactory, @ptrCast(&factory));
    if (factory_return_code != w32.S_OK) {
        misc.errorContext().newFmt(error.DxgiError, "CreateDXGIFactory returned: {}", .{factory_return_code});
        return error.DxgiError;
    }
    defer _ = factory.IUnknown_Release();

    var adapter: *w32.IDXGIAdapter = undefined;
    const adapter_return_code = factory.IDXGIFactory_EnumAdapters(0, @ptrCast(&adapter));
    if (adapter_return_code != w32.S_OK) {
        misc.errorContext().newFmt(error.DxgiError, "IDXGIFactory.EnumAdapters returned: {}", .{adapter_return_code});
        return error.DxgiError;
    }
    defer _ = adapter.IUnknown_Release();

    const d3d12_module = os.Module.getLocal("d3d12.dll") catch |err| {
        misc.errorContext().new(err, "Failed to get local module: d3d12.dll");
        return err;
    };

    const create_device_address = d3d12_module.getProcedureAddress("D3D12CreateDevice") catch |err| {
        misc.errorContext().new(err, "Failed to get procedure address of: D3D12CreateDevice");
        return err;
    };
    const D3D12CreateDevice: *const @TypeOf(w32.D3D12CreateDevice) = @ptrFromInt(create_device_address);
    var device: *w32.ID3D12Device = undefined;
    const device_return_code = D3D12CreateDevice(
        @ptrCast(adapter),
        w32.D3D_FEATURE_LEVEL_11_0,
        w32.IID_ID3D12Device,
        @ptrCast(&device),
    );
    if (device_return_code != w32.S_OK) {
        misc.errorContext().newFmt(error.Direct3dError, "D3D12CreateDevice returned: {}", .{device_return_code});
        return error.Direct3dError;
    }
    defer _ = device.IUnknown_Release();

    var command_queue: *w32.ID3D12CommandQueue = undefined;
    const command_queue_return_code = device.ID3D12Device_CreateCommandQueue(
        &w32.D3D12_COMMAND_QUEUE_DESC{
            .Type = w32.D3D12_COMMAND_LIST_TYPE_DIRECT,
            .Priority = 0,
            .Flags = w32.D3D12_COMMAND_QUEUE_FLAG_NONE,
            .NodeMask = 0,
        },
        w32.IID_ID3D12CommandQueue,
        @ptrCast(&command_queue),
    );
    if (command_queue_return_code != w32.S_OK) {
        misc.errorContext().newFmt(
            error.Direct3dError,
            "ID3D12Device.CreateCommandQueue returned: {}",
            .{command_queue_return_code},
        );
        return error.Direct3dError;
    }
    defer _ = command_queue.IUnknown_Release();

    var swap_chain_desc = w32.DXGI_SWAP_CHAIN_DESC{
        .BufferDesc = .{
            .Width = 100,
            .Height = 100,
            .RefreshRate = .{ .Numerator = 60, .Denominator = 1 },
            .Format = w32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .ScanlineOrdering = w32.DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED,
            .Scaling = w32.DXGI_MODE_SCALING_UNSPECIFIED,
        },
        .SampleDesc = .{ .Count = 1, .Quality = 0 },
        .BufferUsage = w32.DXGI_USAGE_RENDER_TARGET_OUTPUT,
        .BufferCount = 2,
        .OutputWindow = window,
        .Windowed = 1,
        .SwapEffect = .DISCARD,
        .Flags = @intFromEnum(w32.DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH),
    };
    var swap_chain: *w32.IDXGISwapChain = undefined;
    const swap_chain_return_code = factory.IDXGIFactory_CreateSwapChain(
        @ptrCast(command_queue),
        &swap_chain_desc,
        @ptrCast(&swap_chain),
    );
    if (swap_chain_return_code != w32.S_OK) {
        misc.errorContext().newFmt(
            error.Direct3dError,
            "IDXGIFactory.CreateSwapChain returned: {}",
            .{swap_chain_return_code},
        );
        return error.Direct3dError;
    }
    defer _ = swap_chain.IUnknown_Release();

    return swap_chain.vtable.Present;
}

const testing = std.testing;

test "findPresentFunction should return correct value" {
    const module = os.Module.getMain() catch |err| {
        misc.errorContext().new(err, "Failed to get the main process module.");
        return err;
    };

    const window_class = w32.WNDCLASSEXW{
        .cbSize = @sizeOf(w32.WNDCLASSEXW),
        .style = .{
            .HREDRAW = 1,
            .VREDRAW = 1,
        },
        .lpfnWndProc = w32.DefWindowProcW,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = module.handle,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = w("TestWindowClass"),
        .hIconSm = null,
    };

    const register_success = w32.RegisterClassExW(&window_class);
    try testing.expect(register_success != 0);
    defer _ = w32.UnregisterClassW(window_class.lpszClassName, window_class.hInstance);

    const window = w32.CreateWindowExW(
        .{},
        window_class.lpszClassName,
        w("TestWindowClass"),
        w32.WS_OVERLAPPEDWINDOW,
        0,
        0,
        100,
        100,
        null,
        null,
        window_class.hInstance,
        null,
    ) orelse {
        try testing.expect(false);
        unreachable;
    };
    defer _ = w32.DestroyWindow(window);

    var factory: *w32.IDXGIFactory = undefined;
    const factory_return_code = w32.CreateDXGIFactory(w32.IID_IDXGIFactory, @ptrCast(&factory));
    try testing.expectEqual(w32.S_OK, factory_return_code);
    defer _ = factory.IUnknown_Release();

    var adapter: *w32.IDXGIAdapter = undefined;
    const adapter_return_code = factory.IDXGIFactory_EnumAdapters(0, @ptrCast(&adapter));
    try testing.expectEqual(w32.S_OK, adapter_return_code);
    defer _ = adapter.IUnknown_Release();

    var device: *w32.ID3D12Device = undefined;
    const device_return_code = w32.D3D12CreateDevice(
        @ptrCast(adapter),
        w32.D3D_FEATURE_LEVEL_11_0,
        w32.IID_ID3D12Device,
        @ptrCast(&device),
    );
    try testing.expectEqual(w32.S_OK, device_return_code);
    defer _ = device.IUnknown_Release();

    var command_queue: *w32.ID3D12CommandQueue = undefined;
    const command_queue_return_code = device.ID3D12Device_CreateCommandQueue(
        &w32.D3D12_COMMAND_QUEUE_DESC{
            .Type = w32.D3D12_COMMAND_LIST_TYPE_DIRECT,
            .Priority = 0,
            .Flags = w32.D3D12_COMMAND_QUEUE_FLAG_NONE,
            .NodeMask = 0,
        },
        w32.IID_ID3D12CommandQueue,
        @ptrCast(&command_queue),
    );
    try testing.expectEqual(w32.S_OK, command_queue_return_code);
    defer _ = command_queue.IUnknown_Release();

    var swap_chain_desc = w32.DXGI_SWAP_CHAIN_DESC{
        .BufferDesc = .{
            .Width = 100,
            .Height = 100,
            .RefreshRate = .{ .Numerator = 60, .Denominator = 1 },
            .Format = w32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .ScanlineOrdering = w32.DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED,
            .Scaling = w32.DXGI_MODE_SCALING_UNSPECIFIED,
        },
        .SampleDesc = .{ .Count = 1, .Quality = 0 },
        .BufferUsage = w32.DXGI_USAGE_RENDER_TARGET_OUTPUT,
        .BufferCount = 2,
        .OutputWindow = window,
        .Windowed = 1,
        .SwapEffect = .DISCARD,
        .Flags = @intFromEnum(w32.DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH),
    };
    var swap_chain: *w32.IDXGISwapChain = undefined;
    const swap_chain_return_code = factory.IDXGIFactory_CreateSwapChain(
        @ptrCast(command_queue),
        &swap_chain_desc,
        @ptrCast(&swap_chain),
    );
    try testing.expectEqual(w32.S_OK, swap_chain_return_code);
    defer _ = swap_chain.IUnknown_Release();

    try testing.expectEqual(swap_chain.vtable.Present, findPresentFunction());
}
