const std = @import("std");
const w32 = @import("win32").everything;
const os = @import("../os/root.zig");
const dx12 = @import("root.zig");
const misc = @import("../misc/root.zig");
const w = std.unicode.utf8ToUtf16LeStringLiteral;

pub const Functions = struct {
    executeCommandLists: *const ExecuteCommandLists,
    present: *const Present,
    resizeBuffers: *const ResizeBuffers,

    const Self = @This();
    pub const ExecuteCommandLists = @typeInfo(@FieldType(
        w32.ID3D12CommandQueue.VTable,
        "ExecuteCommandLists",
    )).pointer.child;
    pub const Present = @typeInfo(@FieldType(
        w32.IDXGISwapChain.VTable,
        "Present",
    )).pointer.child;
    pub const ResizeBuffers = @typeInfo(@FieldType(
        w32.IDXGISwapChain.VTable,
        "ResizeBuffers",
    )).pointer.child;

    pub fn find() !Self {
        const module = os.Module.getMain() catch |err| {
            misc.errorContext().append("Failed to get the main process module.");
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
            misc.errorContext().newFmt("{}", .{os.Error.getLast()});
            misc.errorContext().append("RegisterClassExW returned 0.");
            return error.OsError;
        }
        defer {
            const success = w32.UnregisterClassW(window_class.lpszClassName, window_class.hInstance);
            if (success == 0) {
                misc.errorContext().newFmt("{}", .{os.Error.getLast()});
                misc.errorContext().append("UnregisterClassW returned 0.");
                misc.errorContext().append("Failed to clean up after finding DX12 functions.");
                misc.errorContext().logError(error.OsError);
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
            misc.errorContext().newFmt("{}", .{os.Error.getLast()});
            misc.errorContext().append("CreateWindowExW returned 0.");
            return error.OsError;
        };
        defer {
            const success = w32.DestroyWindow(window);
            if (success == 0) {
                misc.errorContext().newFmt("{}", .{os.Error.getLast()});
                misc.errorContext().append("DestroyWindow returned 0.");
                misc.errorContext().append("Failed to clean up after finding DX12 functions.");
                misc.errorContext().logError(error.OsError);
            }
        }

        const dxgi_module = os.Module.getLocal("dxgi.dll") catch |err| {
            misc.errorContext().append("Failed to get local module: dxgi.dll");
            return err;
        };

        const create_dxgi_factory_address = dxgi_module.getProcedureAddress("CreateDXGIFactory") catch |err| {
            misc.errorContext().append("Failed to get procedure address of: CreateDXGIFactory");
            return err;
        };
        const CreateDXGIFactory: *const @TypeOf(w32.CreateDXGIFactory) = @ptrFromInt(create_dxgi_factory_address);
        var factory: *w32.IDXGIFactory4 = undefined;
        const factory_result = CreateDXGIFactory(w32.IID_IDXGIFactory4, @ptrCast(&factory));
        if (dx12.Error.from(factory_result)) |err| {
            misc.errorContext().newFmt("{}", .{err});
            misc.errorContext().append("CreateDXGIFactory returned a failure value.");
            return error.Dx12Error;
        }
        defer _ = factory.IUnknown.Release();

        var adapter: *w32.IDXGIAdapter = undefined;
        const adapter_result = factory.EnumWarpAdapter(w32.IID_IDXGIAdapter, @ptrCast(&adapter));
        if (dx12.Error.from(adapter_result)) |err| {
            misc.errorContext().newFmt("{}", .{err});
            misc.errorContext().append("IDXGIFactory4.EnumWarpAdapter returned a failure value.");
            return error.Dx12Error;
        }
        defer _ = adapter.IUnknown.Release();

        const d3d12_module = os.Module.getLocal("d3d12.dll") catch |err| {
            misc.errorContext().append("Failed to get local module: d3d12.dll");
            return err;
        };

        const create_device_address = d3d12_module.getProcedureAddress("D3D12CreateDevice") catch |err| {
            misc.errorContext().append("Failed to get procedure address of: D3D12CreateDevice");
            return err;
        };
        const D3D12CreateDevice: *const @TypeOf(w32.D3D12CreateDevice) = @ptrFromInt(create_device_address);
        var device: *w32.ID3D12Device = undefined;
        const device_result = D3D12CreateDevice(
            @ptrCast(adapter),
            w32.D3D_FEATURE_LEVEL_11_0,
            w32.IID_ID3D12Device,
            @ptrCast(&device),
        );
        if (dx12.Error.from(device_result)) |err| {
            misc.errorContext().newFmt("{}", .{err});
            misc.errorContext().append("D3D12CreateDevice returned a failure value.");
            return error.Dx12Error;
        }
        defer _ = device.IUnknown.Release();

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
            misc.errorContext().newFmt("{}", .{err});
            misc.errorContext().append("ID3D12Device.CreateCommandQueue returned a failure value.");
            return error.Dx12Error;
        }
        defer _ = command_queue.IUnknown.Release();

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
            misc.errorContext().newFmt("{}", .{err});
            misc.errorContext().append("IDXGIFactory.CreateSwapChain returned a failure value.");
            return error.Dx12Error;
        }
        defer _ = swap_chain.IUnknown.Release();

        return .{
            .executeCommandLists = command_queue.vtable.ExecuteCommandLists,
            .present = swap_chain.vtable.Present,
            .resizeBuffers = swap_chain.vtable.ResizeBuffers,
        };
    }
};

const testing = std.testing;

test "find should return correct values" {
    const context = try dx12.TestingContext.init();
    defer context.deinit();
    const functions = try Functions.find();
    try testing.expectEqual(context.command_queue.vtable.ExecuteCommandLists, functions.executeCommandLists);
    try testing.expectEqual(context.swap_chain.vtable.Present, functions.present);
    try testing.expectEqual(context.swap_chain.vtable.ResizeBuffers, functions.resizeBuffers);
}
