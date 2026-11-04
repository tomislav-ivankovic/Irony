const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const memory = @import("../memory/root.zig");
const dx11 = @import("root.zig");

pub const OnHookEvent = fn (context: dx11.HostContext) void;

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
                const saved = misc.error_context.save();
                defer misc.error_context.restore(&saved);
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
                const saved = misc.error_context.save();
                defer misc.error_context.restore(&saved);
                present_hook.?.destroy() catch |err| {
                    misc.error_context.append("Failed to destroy present hook.", .{});
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

        pub fn deinit(io: std.Io) void {
            std.log.debug("Disabling the present hook...", .{});
            var is_present_hook_disabled = false;
            if (present_hook) |hook| {
                if (hook.disable()) {
                    is_present_hook_disabled = true;
                    std.log.info("Present hook disabled.", .{});
                } else |err| switch (err) {
                    error.HookDisabled => is_present_hook_disabled = true,
                    else => {
                        misc.error_context.append("Failed to disable present hook.", .{});
                        misc.error_context.logError(err);
                    },
                }
            } else {
                std.log.debug("Nothing to disable.", .{});
            }

            std.log.debug("Disabling the resize buffers hook...", .{});
            var is_resize_buffers_hook_disabled = false;
            if (resize_buffers_hook) |hook| {
                if (hook.disable()) {
                    is_resize_buffers_hook_disabled = true;
                    std.log.info("Resize buffers hook disabled.", .{});
                } else |err| switch (err) {
                    error.HookDisabled => is_resize_buffers_hook_disabled = true,
                    else => {
                        misc.error_context.append("Failed to disable resize buffers hook.", .{});
                        misc.error_context.logError(err);
                    },
                }
            } else {
                std.log.debug("Nothing to disable.", .{});
            }

            while (active_hook_calls.load(.seq_cst) > 0) {
                io.sleep(.fromMilliseconds(10), .awake) catch |err| {
                    misc.error_context.new("Failed to sleep for 10 ms while waiting on active DX11 hooks.", .{});
                    misc.error_context.logError(err);
                };
            }

            std.log.debug("Destroying the present hook...", .{});
            if (present_hook) |hook| {
                if (!is_present_hook_disabled) {
                    std.log.warn("Skipping the destruction of present hook since disabling it failed.", .{});
                } else if (hook.destroy()) {
                    present_hook = null;
                    std.log.info("Present hook destroyed.", .{});
                } else |err| {
                    misc.error_context.append("Failed to destroy present hook.", .{});
                    misc.error_context.logError(err);
                }
            } else {
                std.log.debug("Nothing to destroy.", .{});
            }

            std.log.debug("Destroying the resize buffers hook...", .{});
            if (resize_buffers_hook) |hook| {
                if (!is_resize_buffers_hook_disabled) {
                    std.log.warn("Skipping the destruction of resize buffers hook since disabling it failed.", .{});
                } else if (hook.destroy()) {
                    resize_buffers_hook = null;
                    std.log.info("Resize buffers hook destroyed.", .{});
                } else |err| {
                    misc.error_context.append("Failed to destroy resize buffers hook.", .{});
                    misc.error_context.logError(err);
                }
            } else {
                std.log.debug("Nothing to destroy.", .{});
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
                misc.error_context.append("Failed to get the window from DX11 swap chain.", .{});
                misc.error_context.logError(err);
                return present_hook.?.original(swap_chain, sync_interval, flags);
            };
            const device = dx11.getDeviceFromSwapChain(swap_chain) catch |err| {
                misc.error_context.append("Failed to get DX11 device from swap chain.", .{});
                misc.error_context.logError(err);
                return present_hook.?.original(swap_chain, sync_interval, flags);
            };
            defer _ = device.IUnknown.Release();
            const device_context = dx11.getDeviceContextFromDevice(device) catch |err| {
                misc.error_context.append("Failed to get DX11 device context from device.", .{});
                misc.error_context.logError(err);
                return present_hook.?.original(swap_chain, sync_interval, flags);
            };
            defer _ = device_context.IUnknown.Release();

            const context = dx11.HostContext{
                .window = window,
                .device = device,
                .device_context = device_context,
                .swap_chain = swap_chain,
            };
            onPresent(context);

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
                misc.error_context.append("Failed to get the window from DX11 swap chain.", .{});
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
                misc.error_context.append("Failed to get DX11 device from swap chain.", .{});
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
            defer _ = device.IUnknown.Release();
            const device_context = dx11.getDeviceContextFromDevice(device) catch |err| {
                misc.error_context.append("Failed to get DX11 device context from device.", .{});
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
            defer _ = device_context.IUnknown.Release();

            const context = dx11.HostContext{
                .window = window,
                .device = device,
                .device_context = device_context,
                .swap_chain = swap_chain,
            };
            beforeResize(context);
            const return_value = resize_buffers_hook.?.original(
                swap_chain,
                buffer_count,
                width,
                height,
                new_format,
                swap_chain_flags,
            );
            afterResize(context);

            return return_value;
        }
    };
}

const testing = std.testing;

test "should call correct callbacks at correct times" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const dx11_context = try dx11.TestingContext.init();
    defer dx11_context.deinit();

    try memory.hooking.init();
    defer memory.hooking.deinit() catch @panic("Failed to de-initialize hooking.");

    const OnPresent = struct {
        var times_called: usize = 0;
        var last_context: ?dx11.HostContext = null;
        fn call(context: dx11.HostContext) void {
            times_called += 1;
            last_context = context;
        }
    };
    const BeforeResize = struct {
        var times_called: usize = 0;
        var last_context: ?dx11.HostContext = null;
        fn call(context: dx11.HostContext) void {
            times_called += 1;
            last_context = context;
        }
    };
    const AfterResize = struct {
        var times_called: usize = 0;
        var last_context: ?dx11.HostContext = null;
        fn call(context: dx11.HostContext) void {
            times_called += 1;
            last_context = context;
        }
    };

    const hooks = Hooks(OnPresent.call, BeforeResize.call, AfterResize.call);
    try hooks.init();
    defer hooks.deinit(testing.io);

    try testing.expectEqual(0, OnPresent.times_called);
    try testing.expectEqual(0, BeforeResize.times_called);
    try testing.expectEqual(0, AfterResize.times_called);

    for (0..5) |_| {
        const present_result = dx11_context.swap_chain.Present(0, w32.DXGI_PRESENT_TEST);
        try testing.expectEqual(w32.S_OK, present_result);
    }

    try testing.expectEqual(5, OnPresent.times_called);
    try testing.expectEqual(dx11_context.getHostContext(), OnPresent.last_context);
    try testing.expectEqual(0, BeforeResize.times_called);
    try testing.expectEqual(0, AfterResize.times_called);

    const resize_result_1 = dx11_context.swap_chain.ResizeBuffers(
        3,
        200,
        200,
        w32.DXGI_FORMAT_R8G8B8A8_UNORM,
        @intFromEnum(w32.DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH),
    );
    try testing.expectEqual(w32.S_OK, resize_result_1);

    try testing.expectEqual(1, BeforeResize.times_called);
    try testing.expectEqual(dx11_context.getHostContext(), BeforeResize.last_context);
    try testing.expectEqual(1, AfterResize.times_called);
    try testing.expectEqual(dx11_context.getHostContext(), AfterResize.last_context);
}

test "init should error when hooking is not initialized" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const dx11_context = try dx11.TestingContext.init();
    defer dx11_context.deinit();

    const onEvent = struct {
        fn call(context: dx11.HostContext) void {
            _ = context;
        }
    }.call;

    const hooks = Hooks(onEvent, onEvent, onEvent);
    try testing.expectError(error.HookingNotInitialized, hooks.init());
}
