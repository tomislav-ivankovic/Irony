const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const os = @import("../os/root.zig");
const w = std.unicode.utf8ToUtf16LeStringLiteral;

pub const TestingContext = struct {
    window_class: w32.WNDCLASSEXW,
    window: w32.HWND,
    factory: *w32.IDXGIFactory,
    adapter: *w32.IDXGIAdapter,
    device: *w32.ID3D12Device,
    command_queue: *w32.ID3D12CommandQueue,
    swap_chain: *w32.IDXGISwapChain,
    test_allocation: *u8,

    const Self = @This();

    pub fn init() !Self {
        if (!builtin.is_test) {
            @compileError("TestingContext is only allowed to be used in tests.");
        }

        const module = try os.Module.getMain();

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
            .lpszClassName = w("TestingWindowClass"),
            .hIconSm = null,
        };
        const register_success = w32.RegisterClassExW(&window_class);
        if (register_success == 0) {
            return error.OsError;
        }
        errdefer _ = w32.UnregisterClassW(window_class.lpszClassName, window_class.hInstance);

        const window = w32.CreateWindowExW(
            .{},
            window_class.lpszClassName,
            w("TestingWindowClass"),
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
            return error.OsError;
        };
        errdefer _ = w32.DestroyWindow(window);

        var factory: *w32.IDXGIFactory = undefined;
        const factory_return_code = w32.CreateDXGIFactory(w32.IID_IDXGIFactory, @ptrCast(&factory));
        if (factory_return_code != w32.S_OK) {
            return error.Dx12Error;
        }
        errdefer _ = factory.IUnknown_Release();

        var adapter: *w32.IDXGIAdapter = undefined;
        const adapter_return_code = factory.IDXGIFactory_EnumAdapters(0, @ptrCast(&adapter));
        if (adapter_return_code != w32.S_OK) {
            return error.Dx12Error;
        }
        errdefer _ = adapter.IUnknown_Release();

        var device: *w32.ID3D12Device = undefined;
        const device_return_code = w32.D3D12CreateDevice(
            @ptrCast(adapter),
            w32.D3D_FEATURE_LEVEL_11_0,
            w32.IID_ID3D12Device,
            @ptrCast(&device),
        );
        if (device_return_code != w32.S_OK) {
            return error.Dx12Error;
        }
        errdefer _ = device.IUnknown_Release();

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
            return error.Dx12Error;
        }
        errdefer _ = command_queue.IUnknown_Release();

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
            .BufferCount = 3,
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
            return error.Dx12Error;
        }
        errdefer _ = swap_chain.IUnknown_Release();

        const test_allocation = try std.testing.allocator.create(u8);

        return .{
            .window_class = window_class,
            .window = window,
            .factory = factory,
            .adapter = adapter,
            .device = device,
            .command_queue = command_queue,
            .swap_chain = swap_chain,
            .test_allocation = test_allocation,
        };
    }

    pub fn deinit(self: *const Self) void {
        _ = self.swap_chain.IUnknown_Release();
        _ = self.command_queue.IUnknown_Release();
        _ = self.device.IUnknown_Release();
        _ = self.adapter.IUnknown_Release();
        _ = self.factory.IUnknown_Release();
        _ = w32.DestroyWindow(self.window);
        _ = w32.UnregisterClassW(self.window_class.lpszClassName, self.window_class.hInstance);
        std.testing.allocator.destroy(self.test_allocation);
    }
};

test "should init without errors" {
    const context = try TestingContext.init();
    defer context.deinit();
}
