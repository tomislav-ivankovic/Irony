const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const os = @import("../os/root.zig");
const dx12 = @import("root.zig");
const w = std.unicode.utf8ToUtf16LeStringLiteral;

pub const TestingContext = struct {
    window_class: w32.WNDCLASSEXW,
    window: w32.HWND,
    factory: *w32.IDXGIFactory4,
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
            misc.error_context.new("{f}", .{os.Error.getLast()});
            misc.error_context.append("RegisterClassExW returned 0.", .{});
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
            misc.error_context.new("{f}", .{os.Error.getLast()});
            misc.error_context.append("CreateWindowExW returned 0.", .{});
            return error.OsError;
        };
        errdefer _ = w32.DestroyWindow(window);

        var factory: *w32.IDXGIFactory4 = undefined;
        const factory_result = w32.CreateDXGIFactory(w32.IID_IDXGIFactory4, @ptrCast(&factory));
        if (dx12.Error.from(factory_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("CreateDXGIFactory returned a failure value.", .{});
            return error.Dx12Error;
        }
        errdefer _ = factory.IUnknown.Release();

        var adapter: *w32.IDXGIAdapter = undefined;
        const adapter_result = factory.EnumWarpAdapter(w32.IID_IDXGIAdapter, @ptrCast(&adapter));
        if (dx12.Error.from(adapter_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("IDXGIFactory4.EnumWarpAdapter returned a failure value.", .{});
            return error.Dx12Error;
        }
        errdefer _ = adapter.IUnknown.Release();

        var device: *w32.ID3D12Device = undefined;
        const device_result = w32.D3D12CreateDevice(
            @ptrCast(adapter),
            w32.D3D_FEATURE_LEVEL_11_0,
            w32.IID_ID3D12Device,
            @ptrCast(&device),
        );
        if (dx12.Error.from(device_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("D3D12CreateDevice returned a failure value.", .{});
            return error.Dx12Error;
        }
        errdefer _ = device.IUnknown.Release();

        var command_queue: *w32.ID3D12CommandQueue = undefined;
        const command_queue_result = device.CreateCommandQueue(
            &w32.D3D12_COMMAND_QUEUE_DESC{
                .Type = w32.D3D12_COMMAND_LIST_TYPE_DIRECT,
                .Priority = 0,
                .Flags = w32.D3D12_COMMAND_QUEUE_FLAG_NONE,
                .NodeMask = 0,
            },
            w32.IID_ID3D12CommandQueue,
            @ptrCast(&command_queue),
        );
        if (dx12.Error.from(command_queue_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D12Device.CreateCommandQueue returned a failure value.", .{});
            return error.Dx12Error;
        }
        errdefer _ = command_queue.IUnknown.Release();

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
            .SwapEffect = .FLIP_DISCARD,
            .Flags = @intFromEnum(w32.DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH),
        };
        var swap_chain: *w32.IDXGISwapChain = undefined;
        const swap_chain_result = factory.IDXGIFactory.CreateSwapChain(
            @ptrCast(command_queue),
            &swap_chain_desc,
            @ptrCast(&swap_chain),
        );
        if (dx12.Error.from(swap_chain_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("IDXGIFactory.CreateSwapChain returned a failure value.", .{});
            return error.Dx12Error;
        }
        errdefer _ = swap_chain.IUnknown.Release();

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
        _ = self.swap_chain.IUnknown.Release();
        _ = self.command_queue.IUnknown.Release();
        _ = self.device.IUnknown.Release();
        _ = self.adapter.IUnknown.Release();
        _ = self.factory.IUnknown.Release();
        _ = w32.DestroyWindow(self.window);
        _ = w32.UnregisterClassW(self.window_class.lpszClassName, self.window_class.hInstance);
        std.testing.allocator.destroy(self.test_allocation);
    }
};

test "should init without errors" {
    const context = try TestingContext.init();
    defer context.deinit();
}
