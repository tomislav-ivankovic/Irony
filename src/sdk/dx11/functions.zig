const std = @import("std");
const w32 = @import("win32").everything;
const os = @import("../os/root.zig");
const dx11 = @import("root.zig");
const misc = @import("../misc/root.zig");
const w = std.unicode.utf8ToUtf16LeStringLiteral;

pub const Functions = struct {
    present: *const Present,
    resizeBuffers: *const ResizeBuffers,

    const Self = @This();
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
            misc.error_context.append("Failed to get the main process module.", .{});
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
            misc.error_context.new("{f}", .{os.Error.getLast()});
            misc.error_context.append("RegisterClassExW returned 0.", .{});
            return error.OsError;
        }
        defer {
            const success = w32.UnregisterClassW(window_class.lpszClassName, window_class.hInstance);
            if (success == 0) {
                misc.error_context.new("{f}", .{os.Error.getLast()});
                misc.error_context.append("UnregisterClassW returned 0.", .{});
                misc.error_context.append("Failed to clean up after finding DX11 functions.", .{});
                misc.error_context.logError(error.OsError);
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
            misc.error_context.new("{f}", .{os.Error.getLast()});
            misc.error_context.append("CreateWindowExW returned 0.", .{});
            return error.OsError;
        };
        defer {
            const success = w32.DestroyWindow(window);
            if (success == 0) {
                misc.error_context.new("{f}", .{os.Error.getLast()});
                misc.error_context.append("DestroyWindow returned 0.", .{});
                misc.error_context.append("Failed to clean up after finding DX11 functions.", .{});
                misc.error_context.logError(error.OsError);
            }
        }

        const d3d11_module = os.Module.getLocal("d3d11.dll") catch |err| {
            misc.error_context.append("Failed to get local module: d3d11.dll", .{});
            return err;
        };

        const d3d11_create_device_and_swap_chain_address = d3d11_module.getProcedureAddress(
            "D3D11CreateDeviceAndSwapChain",
        ) catch |err| {
            misc.error_context.append("Failed to get procedure address of: D3D11CreateDeviceAndSwapChain", .{});
            return err;
        };
        const D3D11CreateDeviceAndSwapChain: *const @TypeOf(w32.D3D11CreateDeviceAndSwapChain) =
            @ptrFromInt(d3d11_create_device_and_swap_chain_address);
        const feature_levels = [_]w32.D3D_FEATURE_LEVEL{.@"10_1"};
        const swap_chain_desc = w32.DXGI_SWAP_CHAIN_DESC{
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
        const result = D3D11CreateDeviceAndSwapChain(
            null,
            .WARP,
            null,
            .{},
            &feature_levels,
            feature_levels.len,
            w32.D3D11_SDK_VERSION,
            &swap_chain_desc,
            &swap_chain,
            null,
            null,
            null,
        );
        if (dx11.Error.from(result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("D3D11CreateDeviceAndSwapChain returned a failure value.", .{});
            return error.Dx11Error;
        }
        defer _ = swap_chain.IUnknown.Release();

        return .{
            .present = swap_chain.vtable.Present,
            .resizeBuffers = swap_chain.vtable.ResizeBuffers,
        };
    }
};

const testing = std.testing;

test "find should return correct values" {
    const context = try dx11.TestingContext.init();
    defer context.deinit();
    const functions = try Functions.find();
    try testing.expectEqual(context.swap_chain.vtable.Present, functions.present);
    try testing.expectEqual(context.swap_chain.vtable.ResizeBuffers, functions.resizeBuffers);
}
