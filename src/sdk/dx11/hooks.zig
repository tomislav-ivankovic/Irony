const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const memory = @import("../memory/root.zig");
const dx11 = @import("root.zig");

pub const OnHookEvent = fn (
    window: w32.HWND,
    device: *const w32.ID3D11Device,
    swap_chain: *const w32.IDXGISwapChain,
) void;

pub fn Hooks(onPresent: *const OnHookEvent, beforeResize: *const OnHookEvent, afterResize: *const OnHookEvent) type {
    return struct {
        var resize_buffers_hook: ?memory.Hook(dx11.Functions.ResizeBuffers) = null;
        var present_hook: ?memory.Hook(dx11.Functions.Present) = null;
        var active_hook_calls = std.atomic.Value(u8).init(0);

        pub fn init() !void {
            std.log.debug("Finding DX11 functions...", .{});
            const dx11_functions = dx11.Functions.find() catch |err| {
                misc.error_context.append("Failed to find DX11 functions.", .{});
                return err;
            };
            std.log.info("DX11 functions found.", .{});

            std.log.debug("Creating the resize buffers hook...", .{});
            resize_buffers_hook = memory.Hook(dx11.Functions.ResizeBuffers).create(
                dx11_functions.resizeBuffers,
                onResizeBuffers,
            ) catch |err| {
                misc.error_context.append("Failed to create resize buffers hook.", .{});
                return err;
            };
            std.log.info("Resize buffers hook created.", .{});
            errdefer {
                resize_buffers_hook.?.destroy() catch |err| {
                    misc.error_context.append("Failed to destroy resize buffers hook.", .{});
                    misc.error_context.logError(err);
                };
                resize_buffers_hook = null;
            }

            std.log.debug("Creating the present hook...", .{});
            present_hook = memory.Hook(dx11.Functions.Present).create(
                dx11_functions.present,
                onPresentInternal,
            ) catch |err| {
                misc.error_context.append("Failed to create present hook.", .{});
                return err;
            };
            std.log.info("Present hook created.", .{});
            errdefer {
                present_hook.?.destroy() catch |err| {
                    misc.error_context.append("Failed to destroy present hook hook.", .{});
                    misc.error_context.logError(err);
                };
                present_hook = null;
            }

            std.log.debug("Enabling resize buffers hook...", .{});
            resize_buffers_hook.?.enable() catch |err| {
                misc.error_context.append("Failed to enable resize buffers hook.", .{});
                return err;
            };
            std.log.info("Resize buffers hook enabled.", .{});

            std.log.debug("Enabling present hook...", .{});
            present_hook.?.enable() catch |err| {
                misc.error_context.append("Failed to enable present hook.", .{});
                return err;
            };
            std.log.info("Present hook enabled.", .{});
        }

        pub fn deinit() void {
            std.log.debug("Destroying the present hook...", .{});
            if (present_hook) |hook| {
                if (hook.destroy()) {
                    present_hook = null;
                    std.log.info("Present hook destroyed.", .{});
                } else |err| {
                    misc.error_context.append("Failed destroy present hook.", .{});
                    misc.error_context.logError(err);
                }
            } else {
                std.log.debug("Nothing to destroy.", .{});
            }

            std.log.debug("Destroying the resize buffers hook...", .{});
            if (resize_buffers_hook) |hook| {
                if (hook.destroy()) {
                    resize_buffers_hook = null;
                    std.log.info("Resize buffers hook destroyed.", .{});
                } else |err| {
                    misc.error_context.append("Failed destroy resize buffers hook.", .{});
                    misc.error_context.logError(err);
                }
            } else {
                std.log.debug("Nothing to destroy.", .{});
            }

            while (active_hook_calls.load(.seq_cst) > 0) {
                std.Thread.sleep(10 * std.time.ns_per_ms);
            }
        }

        fn onPresentInternal(
            swap_chain: *const w32.IDXGISwapChain,
            sync_interval: u32,
            flags: u32,
        ) callconv(.winapi) w32.HRESULT {
            _ = active_hook_calls.fetchAdd(1, .seq_cst);
            defer _ = active_hook_calls.fetchSub(1, .seq_cst);

            const window = dx11.getWindowFromSwapChain(swap_chain) catch |err| {
                misc.error_context.append("Failed to get the window from DX12 swap chain.", .{});
                misc.error_context.logError(err);
                return present_hook.?.original(swap_chain, sync_interval, flags);
            };
            const device = dx11.getDeviceFromSwapChain(swap_chain) catch |err| {
                misc.error_context.append("Failed to get DX12 device from swap chain.", .{});
                misc.error_context.logError(err);
                return present_hook.?.original(swap_chain, sync_interval, flags);
            };
            onPresent(window, device, swap_chain);

            return present_hook.?.original(swap_chain, sync_interval, flags);
        }

        fn onResizeBuffers(
            swap_chain: *const w32.IDXGISwapChain,
            buffer_count: u32,
            width: u32,
            height: u32,
            new_format: w32.DXGI_FORMAT,
            swap_chain_flags: u32,
        ) callconv(.winapi) w32.HRESULT {
            _ = active_hook_calls.fetchAdd(1, .seq_cst);
            defer _ = active_hook_calls.fetchSub(1, .seq_cst);

            const window = dx11.getWindowFromSwapChain(swap_chain) catch |err| {
                misc.error_context.append("Failed to get the window from DX12 swap chain.", .{});
                misc.error_context.logError(err);
                return resize_buffers_hook.?.original(
                    swap_chain,
                    buffer_count,
                    width,
                    height,
                    new_format,
                    swap_chain_flags,
                );
            };
            const device = dx11.getDeviceFromSwapChain(swap_chain) catch |err| {
                misc.error_context.append("Failed to get DX12 device from swap chain.", .{});
                misc.error_context.logError(err);
                return resize_buffers_hook.?.original(
                    swap_chain,
                    buffer_count,
                    width,
                    height,
                    new_format,
                    swap_chain_flags,
                );
            };

            beforeResize(window, device, swap_chain);
            const return_value = resize_buffers_hook.?.original(
                swap_chain,
                buffer_count,
                width,
                height,
                new_format,
                swap_chain_flags,
            );
            afterResize(window, device, swap_chain);

            return return_value;
        }
    };
}

const testing = std.testing;

test "should call correct callbacks at correct times" {
    const dx11_context = try dx11.TestingContext.init();
    defer dx11_context.deinit();

    try memory.hooking.init();
    defer memory.hooking.deinit() catch @panic("Failed to de-initialize hooking.");

    const OnPresent = struct {
        var times_called: usize = 0;
        var last_window: ?w32.HWND = null;
        var last_device: ?*const w32.ID3D11Device = null;
        var last_swap_chain: ?*const w32.IDXGISwapChain = null;
        fn call(
            window: w32.HWND,
            device: *const w32.ID3D11Device,
            swap_chain: *const w32.IDXGISwapChain,
        ) void {
            times_called += 1;
            last_window = window;
            last_device = device;
            last_swap_chain = swap_chain;
        }
    };
    const BeforeResize = struct {
        var times_called: usize = 0;
        var last_window: ?w32.HWND = null;
        var last_device: ?*const w32.ID3D11Device = null;
        var last_swap_chain: ?*const w32.IDXGISwapChain = null;
        fn call(
            window: w32.HWND,
            device: *const w32.ID3D11Device,
            swap_chain: *const w32.IDXGISwapChain,
        ) void {
            times_called += 1;
            last_window = window;
            last_device = device;
            last_swap_chain = swap_chain;
        }
    };
    const AfterResize = struct {
        var times_called: usize = 0;
        var last_window: ?w32.HWND = null;
        var last_device: ?*const w32.ID3D11Device = null;
        var last_swap_chain: ?*const w32.IDXGISwapChain = null;
        fn call(
            window: w32.HWND,
            device: *const w32.ID3D11Device,
            swap_chain: *const w32.IDXGISwapChain,
        ) void {
            times_called += 1;
            last_window = window;
            last_device = device;
            last_swap_chain = swap_chain;
        }
    };

    const hooks = Hooks(OnPresent.call, BeforeResize.call, AfterResize.call);
    try hooks.init();
    defer hooks.deinit();

    try testing.expectEqual(0, OnPresent.times_called);
    try testing.expectEqual(0, BeforeResize.times_called);
    try testing.expectEqual(0, AfterResize.times_called);

    for (0..5) |_| {
        const present_result = dx11_context.swap_chain.Present(0, w32.DXGI_PRESENT_TEST);
        try testing.expectEqual(w32.S_OK, present_result);
    }

    try testing.expectEqual(5, OnPresent.times_called);
    try testing.expectEqual(0, BeforeResize.times_called);
    try testing.expectEqual(0, AfterResize.times_called);

    try testing.expectEqual(dx11_context.window, OnPresent.last_window);
    try testing.expectEqual(dx11_context.device, OnPresent.last_device);
    try testing.expectEqual(dx11_context.swap_chain, OnPresent.last_swap_chain);

    const resize_result_1 = dx11_context.swap_chain.ResizeBuffers(
        3,
        200,
        200,
        w32.DXGI_FORMAT_R8G8B8A8_UNORM,
        @intFromEnum(w32.DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH),
    );
    try testing.expectEqual(w32.S_OK, resize_result_1);

    try testing.expectEqual(1, BeforeResize.times_called);
    try testing.expectEqual(1, AfterResize.times_called);

    try testing.expectEqual(dx11_context.window, BeforeResize.last_window);
    try testing.expectEqual(dx11_context.device, BeforeResize.last_device);
    try testing.expectEqual(dx11_context.swap_chain, BeforeResize.last_swap_chain);

    try testing.expectEqual(dx11_context.window, AfterResize.last_window);
    try testing.expectEqual(dx11_context.device, AfterResize.last_device);
    try testing.expectEqual(dx11_context.swap_chain, AfterResize.last_swap_chain);
}

test "init should error when hooking is not initialized" {
    const dx11_context = try dx11.TestingContext.init();
    defer dx11_context.deinit();

    const onEvent = struct {
        fn call(
            window: w32.HWND,
            device: *const w32.ID3D11Device,
            swap_chain: *const w32.IDXGISwapChain,
        ) void {
            _ = window;
            _ = device;
            _ = swap_chain;
        }
    }.call;

    const hooks = Hooks(onEvent, onEvent, onEvent);
    try testing.expectError(error.HookingNotInitialized, hooks.init());
}
