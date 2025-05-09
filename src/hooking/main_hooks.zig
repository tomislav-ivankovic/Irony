const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const hooking = @import("root.zig");
const dx12 = @import("../dx12/root.zig");

pub const OnEvent = fn (
    window: w32.HWND,
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    swap_chain: *const w32.IDXGISwapChain,
) void;

pub fn MainHooks(
    onInit: *const OnEvent,
    onDeinit: *const OnEvent,
    onUpdate: *const OnEvent,
    beforeResize: *const OnEvent,
    afterResize: *const OnEvent,
) type {
    return struct {
        var execute_command_lists_hook: ?hooking.Hook(dx12.Functions.ExecuteCommandLists) = null;
        var resize_buffers_hook: ?hooking.Hook(dx12.Functions.ResizeBuffers) = null;
        var present_hook: ?hooking.Hook(dx12.Functions.Present) = null;
        var g_command_queue: ?*const w32.ID3D12CommandQueue = null;
        var is_init_called = false;
        var is_deinit_called = std.atomic.Value(bool).init(false);

        pub fn init() !void {
            g_command_queue = null;
            is_init_called = false;
            is_deinit_called.store(false, .seq_cst);

            std.log.debug("Finding DX12 functions...", .{});
            const dx12_functions = dx12.Functions.find() catch |err| {
                misc.error_context.append("Failed to find DX12 functions.", .{});
                return err;
            };
            std.log.info("DX12 functions found.", .{});

            std.log.debug("Creating the execute command lists hook...", .{});
            execute_command_lists_hook = hooking.Hook(dx12.Functions.ExecuteCommandLists).create(
                dx12_functions.executeCommandLists,
                onExecuteCommandLists,
            ) catch |err| {
                misc.error_context.append("Failed to create execute command lists hook.", .{});
                return err;
            };
            std.log.info("Execute command lists hook created.", .{});
            errdefer {
                execute_command_lists_hook.?.destroy() catch |err| {
                    misc.error_context.append("Failed to destroy execute command lists hook.", .{});
                    misc.error_context.logError(err);
                };
                execute_command_lists_hook = null;
            }

            std.log.debug("Creating the resize buffers hook...", .{});
            resize_buffers_hook = hooking.Hook(dx12.Functions.ResizeBuffers).create(
                dx12_functions.resizeBuffers,
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
            present_hook = hooking.Hook(dx12.Functions.Present).create(
                dx12_functions.present,
                onPresent,
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

            std.log.debug("Enabling execute command lists hook...", .{});
            execute_command_lists_hook.?.enable() catch |err| {
                misc.error_context.append("Failed to enable execute command lists hook.", .{});
                return err;
            };
            std.log.info("Execute command lists hook enabled.", .{});

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
            const presentFunction = if (present_hook) |hook| block: {
                if (hook.destroy()) {
                    present_hook = null;
                    std.log.info("Present hook destroyed.", .{});
                    break :block hook.target;
                } else |err| {
                    misc.error_context.append("Failed destroy present hook.", .{});
                    misc.error_context.logError(err);
                    break :block null;
                }
            } else block: {
                std.log.debug("Nothing to destroy.", .{});
                break :block null;
            };

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

            std.log.debug("Destroying the execute command lists hook...", .{});
            if (execute_command_lists_hook) |hook| {
                if (hook.destroy()) {
                    execute_command_lists_hook = null;
                    std.log.info("Execute command lists hook destroyed.", .{});
                } else |err| {
                    misc.error_context.append("Failed destroy execute command lists hook.", .{});
                    misc.error_context.logError(err);
                }
            } else {
                std.log.debug("Nothing to destroy.", .{});
            }

            if (presentFunction) |present| last_present: {
                std.log.debug("Creating the last present hook...", .{});
                present_hook = hooking.Hook(dx12.Functions.Present).create(present, onPresentCleanup) catch |err| {
                    misc.error_context.append("Failed to create last present hook.", .{});
                    misc.error_context.logError(err);
                    break :last_present;
                };
                std.log.info("Last present hook created.", .{});
                defer {
                    std.log.debug("Destroying the last present hook...", .{});
                    if (present_hook.?.destroy()) {
                        present_hook = null;
                        std.log.info("Last present hook destroyed.", .{});
                    } else |err| {
                        misc.error_context.append("Failed destroy last present hook.", .{});
                        misc.error_context.logError(err);
                    }
                }

                std.log.debug("Enabling last present hook...", .{});
                present_hook.?.enable() catch |err| {
                    misc.error_context.append("Failed to enable last present hook.", .{});
                    misc.error_context.logError(err);
                    break :last_present;
                };
                std.log.info("Last present hook enabled.", .{});

                std.log.debug("Waiting for the last present call...", .{});
                while (!is_deinit_called.load(.seq_cst)) {
                    if (!builtin.is_test) {
                        std.time.sleep(100 * std.time.ns_per_ms);
                    }
                }
                std.log.debug("Waiting completed.", .{});

                g_command_queue = null;
                is_init_called = false;
                is_deinit_called.store(false, .seq_cst);
            }
        }

        fn onExecuteCommandLists(
            command_queue: *const w32.ID3D12CommandQueue,
            num_command_lists: u32,
            pp_command_lists: [*]?*w32.ID3D12CommandList,
        ) callconv(.winapi) void {
            if (g_command_queue == null) {
                std.log.info("DX12 command queue found.", .{});
            }
            g_command_queue = command_queue;
            return execute_command_lists_hook.?.original(command_queue, num_command_lists, pp_command_lists);
        }

        fn onPresent(
            swap_chain: *const w32.IDXGISwapChain,
            sync_interval: u32,
            flags: u32,
        ) callconv(.winapi) w32.HRESULT {
            const command_queue = g_command_queue orelse {
                std.log.debug("Present function was called before command queue was found. Skipping this frame.", .{});
                return present_hook.?.original(swap_chain, sync_interval, flags);
            };
            const window = dx12.getWindowFromSwapChain(swap_chain) catch |err| {
                misc.error_context.append("Failed to get the window from DX12 swap chain.", .{});
                misc.error_context.logError(err);
                return present_hook.?.original(swap_chain, sync_interval, flags);
            };
            const device = dx12.getDeviceFromSwapChain(swap_chain) catch |err| {
                misc.error_context.append("Failed to get DX12 device from swap chain.", .{});
                misc.error_context.logError(err);
                return present_hook.?.original(swap_chain, sync_interval, flags);
            };
            if (!is_init_called) {
                std.log.info("First present function called.", .{});
                onInit(window, device, command_queue, swap_chain);
                is_init_called = true;
            } else {
                onUpdate(window, device, command_queue, swap_chain);
            }
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
            const command_queue = g_command_queue orelse {
                std.log.debug("Resize buffers was called before command queue was found. Skipping this call.", .{});
                return resize_buffers_hook.?.original(
                    swap_chain,
                    buffer_count,
                    width,
                    height,
                    new_format,
                    swap_chain_flags,
                );
            };
            if (!is_init_called) {
                std.log.debug("Resize buffers was called before initialization. Skipping this call.", .{});
                return resize_buffers_hook.?.original(
                    swap_chain,
                    buffer_count,
                    width,
                    height,
                    new_format,
                    swap_chain_flags,
                );
            }
            const window = dx12.getWindowFromSwapChain(swap_chain) catch |err| {
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
            const device = dx12.getDeviceFromSwapChain(swap_chain) catch |err| {
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
            beforeResize(window, device, command_queue, swap_chain);
            const return_value = resize_buffers_hook.?.original(
                swap_chain,
                buffer_count,
                width,
                height,
                new_format,
                swap_chain_flags,
            );
            afterResize(window, device, command_queue, swap_chain);
            return return_value;
        }

        fn onPresentCleanup(
            swap_chain: *const w32.IDXGISwapChain,
            sync_interval: u32,
            flags: u32,
        ) callconv(.winapi) w32.HRESULT {
            if (!is_init_called) {
                is_deinit_called.store(true, .seq_cst);
                return present_hook.?.original(swap_chain, sync_interval, flags);
            }
            if (is_deinit_called.load(.seq_cst)) {
                return present_hook.?.original(swap_chain, sync_interval, flags);
            }
            const window = dx12.getWindowFromSwapChain(swap_chain) catch |err| {
                misc.error_context.append("Failed to get the window from DX12 swap chain.", .{});
                misc.error_context.logError(err);
                return present_hook.?.original(swap_chain, sync_interval, flags);
            };
            const device = dx12.getDeviceFromSwapChain(swap_chain) catch |err| {
                misc.error_context.append("Failed to get DX12 device from swap chain.", .{});
                misc.error_context.logError(err);
                return present_hook.?.original(swap_chain, sync_interval, flags);
            };
            std.log.info("Last present function called.", .{});
            onDeinit(window, device, g_command_queue.?, swap_chain);
            is_deinit_called.store(true, .seq_cst);
            return present_hook.?.original(swap_chain, sync_interval, flags);
        }
    };
}

const testing = std.testing;

test "should call correct callbacks at correct times" {
    const dx12_context = try dx12.TestingContext.init();
    defer dx12_context.deinit();

    try hooking.init();
    defer hooking.deinit() catch @panic("Failed to de-initialize hooking.");

    const OnInit = struct {
        var times_called: usize = 0;
        var last_window: ?w32.HWND = null;
        var last_device: ?*const w32.ID3D12Device = null;
        var last_command_queue: ?*const w32.ID3D12CommandQueue = null;
        var last_swap_chain: ?*const w32.IDXGISwapChain = null;
        fn call(
            window: w32.HWND,
            device: *const w32.ID3D12Device,
            command_queue: *const w32.ID3D12CommandQueue,
            swap_chain: *const w32.IDXGISwapChain,
        ) void {
            times_called += 1;
            last_window = window;
            last_device = device;
            last_command_queue = command_queue;
            last_swap_chain = swap_chain;
        }
    };
    const OnDeinit = struct {
        var times_called: usize = 0;
        var last_window: ?w32.HWND = null;
        var last_device: ?*const w32.ID3D12Device = null;
        var last_command_queue: ?*const w32.ID3D12CommandQueue = null;
        var last_swap_chain: ?*const w32.IDXGISwapChain = null;
        fn call(
            window: w32.HWND,
            device: *const w32.ID3D12Device,
            command_queue: *const w32.ID3D12CommandQueue,
            swap_chain: *const w32.IDXGISwapChain,
        ) void {
            times_called += 1;
            last_window = window;
            last_device = device;
            last_command_queue = command_queue;
            last_swap_chain = swap_chain;
        }
    };
    const OnUpdate = struct {
        var times_called: usize = 0;
        var last_window: ?w32.HWND = null;
        var last_device: ?*const w32.ID3D12Device = null;
        var last_command_queue: ?*const w32.ID3D12CommandQueue = null;
        var last_swap_chain: ?*const w32.IDXGISwapChain = null;
        fn call(
            window: w32.HWND,
            device: *const w32.ID3D12Device,
            command_queue: *const w32.ID3D12CommandQueue,
            swap_chain: *const w32.IDXGISwapChain,
        ) void {
            times_called += 1;
            last_window = window;
            last_device = device;
            last_command_queue = command_queue;
            last_swap_chain = swap_chain;
        }
    };
    const BeforeResize = struct {
        var times_called: usize = 0;
        var last_window: ?w32.HWND = null;
        var last_device: ?*const w32.ID3D12Device = null;
        var last_command_queue: ?*const w32.ID3D12CommandQueue = null;
        var last_swap_chain: ?*const w32.IDXGISwapChain = null;
        fn call(
            window: w32.HWND,
            device: *const w32.ID3D12Device,
            command_queue: *const w32.ID3D12CommandQueue,
            swap_chain: *const w32.IDXGISwapChain,
        ) void {
            times_called += 1;
            last_window = window;
            last_device = device;
            last_command_queue = command_queue;
            last_swap_chain = swap_chain;
        }
    };
    const AfterResize = struct {
        var times_called: usize = 0;
        var last_window: ?w32.HWND = null;
        var last_device: ?*const w32.ID3D12Device = null;
        var last_command_queue: ?*const w32.ID3D12CommandQueue = null;
        var last_swap_chain: ?*const w32.IDXGISwapChain = null;
        fn call(
            window: w32.HWND,
            device: *const w32.ID3D12Device,
            command_queue: *const w32.ID3D12CommandQueue,
            swap_chain: *const w32.IDXGISwapChain,
        ) void {
            times_called += 1;
            last_window = window;
            last_device = device;
            last_command_queue = command_queue;
            last_swap_chain = swap_chain;
        }
    };

    const hooks = MainHooks(OnInit.call, OnDeinit.call, OnUpdate.call, BeforeResize.call, AfterResize.call);
    try hooks.init();

    try testing.expectEqual(0, OnInit.times_called);
    try testing.expectEqual(0, OnDeinit.times_called);
    try testing.expectEqual(0, OnUpdate.times_called);
    try testing.expectEqual(0, BeforeResize.times_called);
    try testing.expectEqual(0, AfterResize.times_called);

    for (0..3) |_| {
        const present_result = dx12_context.swap_chain.Present(0, w32.DXGI_PRESENT_TEST);
        try testing.expectEqual(w32.S_OK, present_result);
    }

    try testing.expectEqual(0, OnInit.times_called);
    try testing.expectEqual(0, OnDeinit.times_called);
    try testing.expectEqual(0, OnUpdate.times_called);
    try testing.expectEqual(0, BeforeResize.times_called);
    try testing.expectEqual(0, AfterResize.times_called);

    const command_lists = [0](?*w32.ID3D12CommandList){};
    dx12_context.command_queue.ExecuteCommandLists(command_lists.len, &command_lists);

    try testing.expectEqual(0, OnInit.times_called);
    try testing.expectEqual(0, OnDeinit.times_called);
    try testing.expectEqual(0, OnUpdate.times_called);
    try testing.expectEqual(0, BeforeResize.times_called);
    try testing.expectEqual(0, AfterResize.times_called);

    for (0..5) |_| {
        const present_result = dx12_context.swap_chain.Present(0, w32.DXGI_PRESENT_TEST);
        try testing.expectEqual(w32.S_OK, present_result);
    }

    try testing.expectEqual(1, OnInit.times_called);
    try testing.expectEqual(0, OnDeinit.times_called);
    try testing.expectEqual(4, OnUpdate.times_called);
    try testing.expectEqual(0, BeforeResize.times_called);
    try testing.expectEqual(0, AfterResize.times_called);

    try testing.expectEqual(dx12_context.window, OnInit.last_window);
    try testing.expectEqual(dx12_context.device, OnInit.last_device);
    try testing.expectEqual(dx12_context.command_queue, OnInit.last_command_queue);
    try testing.expectEqual(dx12_context.swap_chain, OnInit.last_swap_chain);

    try testing.expectEqual(dx12_context.window, OnUpdate.last_window);
    try testing.expectEqual(dx12_context.device, OnUpdate.last_device);
    try testing.expectEqual(dx12_context.command_queue, OnUpdate.last_command_queue);
    try testing.expectEqual(dx12_context.swap_chain, OnUpdate.last_swap_chain);

    const resize_result = dx12_context.swap_chain.ResizeBuffers(
        3,
        200,
        200,
        w32.DXGI_FORMAT_R8G8B8A8_UNORM,
        @intFromEnum(w32.DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH),
    );
    try testing.expectEqual(w32.S_OK, resize_result);

    try testing.expectEqual(1, BeforeResize.times_called);
    try testing.expectEqual(1, AfterResize.times_called);

    try testing.expectEqual(dx12_context.window, BeforeResize.last_window);
    try testing.expectEqual(dx12_context.device, BeforeResize.last_device);
    try testing.expectEqual(dx12_context.command_queue, BeforeResize.last_command_queue);
    try testing.expectEqual(dx12_context.swap_chain, BeforeResize.last_swap_chain);

    try testing.expectEqual(dx12_context.window, AfterResize.last_window);
    try testing.expectEqual(dx12_context.device, AfterResize.last_device);
    try testing.expectEqual(dx12_context.command_queue, AfterResize.last_command_queue);
    try testing.expectEqual(dx12_context.swap_chain, AfterResize.last_swap_chain);

    const Deinit = struct {
        var is_complete = std.atomic.Value(bool).init(false);
        fn call() void {
            hooks.deinit();
            is_complete.store(true, .seq_cst);
        }
    };
    const thread = try std.Thread.spawn(.{}, Deinit.call, .{});
    defer thread.join();

    while (!Deinit.is_complete.load(.seq_cst)) {
        try std.Thread.yield();
        const present_result = dx12_context.swap_chain.Present(0, w32.DXGI_PRESENT_TEST);
        try testing.expectEqual(w32.S_OK, present_result);
    }

    try testing.expectEqual(1, OnDeinit.times_called);

    try testing.expectEqual(dx12_context.window, OnDeinit.last_window);
    try testing.expectEqual(dx12_context.device, OnDeinit.last_device);
    try testing.expectEqual(dx12_context.command_queue, OnDeinit.last_command_queue);
    try testing.expectEqual(dx12_context.swap_chain, OnDeinit.last_swap_chain);
}

test "init should error when hooking is not initialized" {
    const dx12Context = try dx12.TestingContext.init();
    defer dx12Context.deinit();

    const onEvent = struct {
        fn call(
            window: w32.HWND,
            device: *const w32.ID3D12Device,
            command_queue: *const w32.ID3D12CommandQueue,
            swap_chain: *const w32.IDXGISwapChain,
        ) void {
            _ = window;
            _ = device;
            _ = command_queue;
            _ = swap_chain;
        }
    }.call;

    const hooks = MainHooks(onEvent, onEvent, onEvent, onEvent, onEvent);
    try testing.expectError(error.HookingNotInitialized, hooks.init());
}
