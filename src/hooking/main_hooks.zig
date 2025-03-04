const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const hooking = @import("root.zig");
const dx12 = @import("../dx12/root.zig");

pub const OnPresent = fn (device: *const w32.ID3D12Device, command_queue: *const w32.ID3D12CommandQueue) void;

pub fn MainHooks(
    onFirstPresent: *const OnPresent,
    onNormalPresent: *const OnPresent,
    onLastPresent: *const OnPresent,
) type {
    return struct {
        var execute_command_lists_hook: ?hooking.Hook(dx12.Functions.ExecuteCommandLists) = null;
        var present_hook: ?hooking.Hook(dx12.Functions.Present) = null;
        var g_command_queue: ?*const w32.ID3D12CommandQueue = null;
        var is_first_present_called = false;
        var is_last_present_called = std.atomic.Value(bool).init(false);

        pub fn init() !void {
            std.log.debug("Finding DX12 functions...", .{});
            const dx12_functions = dx12.Functions.find() catch |err| {
                misc.errorContext().append(err, "Failed to find DX12 functions.");
                return err;
            };
            std.log.info("DX12 functions found.", .{});

            std.log.debug("Creating the execute command lists hook...", .{});
            execute_command_lists_hook = hooking.Hook(dx12.Functions.ExecuteCommandLists).create(
                dx12_functions.executeCommandLists,
                onExecuteCommandLists,
            ) catch |err| {
                misc.errorContext().append(err, "Failed to create execute command lists hook.");
                return err;
            };
            std.log.info("Execute command lists hook created.", .{});
            errdefer {
                execute_command_lists_hook.?.destroy() catch |err| {
                    misc.errorContext().append(err, "Failed to destroy execute command lists hook.");
                    misc.errorContext().logError();
                };
                execute_command_lists_hook = null;
            }

            std.log.debug("Creating the present hook...", .{});
            present_hook = hooking.Hook(dx12.Functions.Present).create(
                dx12_functions.present,
                onPresent,
            ) catch |err| {
                misc.errorContext().append(err, "Failed to create present hook.");
                return err;
            };
            std.log.info("Present hook created.", .{});
            errdefer {
                present_hook.?.destroy() catch |err| {
                    misc.errorContext().append(err, "Failed to destroy present hook hook.");
                    misc.errorContext().logError();
                };
                present_hook = null;
            }

            std.log.debug("Enabling execute command lists hook...", .{});
            execute_command_lists_hook.?.enable() catch |err| {
                misc.errorContext().append(err, "Failed to enable execute command lists hook.");
                return err;
            };
            std.log.info("Execute command lists hook enabled.", .{});

            std.log.debug("Enabling present hook...", .{});
            present_hook.?.enable() catch |err| {
                misc.errorContext().append(err, "Failed to enable present hook.");
                return err;
            };
            std.log.info("Present hook enabled.", .{});

            g_command_queue = null;
            is_first_present_called = false;
            is_last_present_called.store(false, .seq_cst);
        }

        pub fn deinit() void {
            std.log.debug("Destroying the present hook...", .{});
            const presentFunction = if (present_hook) |hook| block: {
                if (hook.destroy()) {
                    present_hook = null;
                    std.log.info("Present hook destroyed.", .{});
                    break :block hook.target;
                } else |err| {
                    misc.errorContext().append(err, "Failed destroy present hook.");
                    misc.errorContext().logError();
                    break :block null;
                }
            } else block: {
                std.log.debug("Nothing to destroy.", .{});
                break :block null;
            };

            std.log.debug("Destroying the execute command lists hook...", .{});
            if (execute_command_lists_hook) |hook| {
                if (hook.destroy()) {
                    execute_command_lists_hook = null;
                    std.log.info("Execute command lists hook destroyed.", .{});
                } else |err| {
                    misc.errorContext().append(err, "Failed destroy execute command lists hook.");
                    misc.errorContext().logError();
                }
            } else {
                std.log.debug("Nothing to destroy.", .{});
            }

            if (presentFunction) |present| last_present: {
                std.log.debug("Creating the last present hook...", .{});
                present_hook = hooking.Hook(dx12.Functions.Present).create(present, onPresentCleanup) catch |err| {
                    misc.errorContext().append(err, "Failed to create last present hook.");
                    misc.errorContext().logError();
                    break :last_present;
                };
                std.log.info("Last present hook created.", .{});
                defer {
                    std.log.debug("Destroying the last present hook...", .{});
                    if (present_hook.?.destroy()) {
                        present_hook = null;
                        std.log.info("Last present hook destroyed.", .{});
                    } else |err| {
                        misc.errorContext().append(err, "Failed destroy last present hook.");
                        misc.errorContext().logError();
                    }
                }

                std.log.debug("Enabling last present hook...", .{});
                present_hook.?.enable() catch |err| {
                    misc.errorContext().append(err, "Failed to enable last present hook.");
                    misc.errorContext().logError();
                    break :last_present;
                };
                std.log.info("Last present hook enabled.", .{});

                std.log.debug("Waiting for the last present call...", .{});
                while (!is_last_present_called.load(.seq_cst)) {
                    if (!builtin.is_test) {
                        std.time.sleep(100 * std.time.ns_per_ms);
                    }
                }
                std.log.debug("Waiting completed.", .{});

                g_command_queue = null;
                is_first_present_called = false;
                is_last_present_called.store(false, .seq_cst);
            }
        }

        fn onExecuteCommandLists(
            command_queue: *const w32.ID3D12CommandQueue,
            num_command_lists: u32,
            pp_command_lists: [*]?*w32.ID3D12CommandList,
        ) callconv(@import("std").os.windows.WINAPI) void {
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
        ) callconv(@import("std").os.windows.WINAPI) w32.HRESULT {
            const command_queue = g_command_queue orelse {
                std.log.debug("Present function was called before command queue was found. Skipping this frame.", .{});
                return present_hook.?.original(swap_chain, sync_interval, flags);
            };
            const device = dx12.getDeviceFromSwapChain(swap_chain) catch |err| {
                misc.errorContext().append(err, "Failed to get DX12 device from swap chain.");
                misc.errorContext().logError();
                return present_hook.?.original(swap_chain, sync_interval, flags);
            };
            if (!is_first_present_called) {
                std.log.info("First present function called.", .{});
                onFirstPresent(device, command_queue);
                is_first_present_called = true;
            } else {
                onNormalPresent(device, command_queue);
            }
            return present_hook.?.original(swap_chain, sync_interval, flags);
        }

        fn onPresentCleanup(
            swap_chain: *const w32.IDXGISwapChain,
            sync_interval: u32,
            flags: u32,
        ) callconv(@import("std").os.windows.WINAPI) w32.HRESULT {
            if (!is_first_present_called) {
                is_last_present_called.store(true, .seq_cst);
                return present_hook.?.original(swap_chain, sync_interval, flags);
            }
            if (is_last_present_called.load(.seq_cst)) {
                return present_hook.?.original(swap_chain, sync_interval, flags);
            }
            const device = dx12.getDeviceFromSwapChain(swap_chain) catch |err| {
                misc.errorContext().append(err, "Failed to get DX12 device from swap chain.");
                misc.errorContext().logError();
                return present_hook.?.original(swap_chain, sync_interval, flags);
            };
            std.log.info("Last present function called.", .{});
            onLastPresent(device, g_command_queue.?);
            is_last_present_called.store(true, .seq_cst);
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

    const OnFirstPresent = struct {
        var times_called: usize = 0;
        var last_device: ?*const w32.ID3D12Device = null;
        var last_command_queue: ?*const w32.ID3D12CommandQueue = null;
        fn call(device: *const w32.ID3D12Device, command_queue: *const w32.ID3D12CommandQueue) void {
            times_called += 1;
            last_device = device;
            last_command_queue = command_queue;
        }
    };
    const OnNormalPresent = struct {
        var times_called: usize = 0;
        var last_device: ?*const w32.ID3D12Device = null;
        var last_command_queue: ?*const w32.ID3D12CommandQueue = null;
        fn call(device: *const w32.ID3D12Device, command_queue: *const w32.ID3D12CommandQueue) void {
            times_called += 1;
            last_device = device;
            last_command_queue = command_queue;
        }
    };
    const OnLastPresent = struct {
        var times_called: usize = 0;
        var last_device: ?*const w32.ID3D12Device = null;
        var last_command_queue: ?*const w32.ID3D12CommandQueue = null;
        fn call(device: *const w32.ID3D12Device, command_queue: *const w32.ID3D12CommandQueue) void {
            times_called += 1;
            last_device = device;
            last_command_queue = command_queue;
        }
    };

    const hooks = MainHooks(OnFirstPresent.call, OnNormalPresent.call, OnLastPresent.call);
    try hooks.init();

    try testing.expectEqual(0, OnFirstPresent.times_called);
    try testing.expectEqual(0, OnNormalPresent.times_called);
    try testing.expectEqual(0, OnLastPresent.times_called);

    for (0..3) |_| {
        const present_return_code = dx12_context.swap_chain.IDXGISwapChain_Present(0, w32.DXGI_PRESENT_TEST);
        try testing.expectEqual(w32.S_OK, present_return_code);
    }

    try testing.expectEqual(0, OnFirstPresent.times_called);
    try testing.expectEqual(0, OnNormalPresent.times_called);
    try testing.expectEqual(0, OnLastPresent.times_called);

    const command_lists = [0](?*w32.ID3D12CommandList){};
    dx12_context.command_queue.ID3D12CommandQueue_ExecuteCommandLists(command_lists.len, &command_lists);

    try testing.expectEqual(0, OnFirstPresent.times_called);
    try testing.expectEqual(0, OnNormalPresent.times_called);
    try testing.expectEqual(0, OnLastPresent.times_called);

    for (0..5) |_| {
        const present_return_code = dx12_context.swap_chain.IDXGISwapChain_Present(0, w32.DXGI_PRESENT_TEST);
        try testing.expectEqual(w32.S_OK, present_return_code);
    }

    try testing.expectEqual(1, OnFirstPresent.times_called);
    try testing.expectEqual(4, OnNormalPresent.times_called);
    try testing.expectEqual(0, OnLastPresent.times_called);

    try testing.expectEqual(dx12_context.device, OnFirstPresent.last_device);
    try testing.expectEqual(dx12_context.command_queue, OnFirstPresent.last_command_queue);
    try testing.expectEqual(dx12_context.device, OnNormalPresent.last_device);
    try testing.expectEqual(dx12_context.command_queue, OnNormalPresent.last_command_queue);

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
        const present_return_code = dx12_context.swap_chain.IDXGISwapChain_Present(0, w32.DXGI_PRESENT_TEST);
        try testing.expectEqual(w32.S_OK, present_return_code);
    }

    try testing.expectEqual(1, OnLastPresent.times_called);
    try testing.expectEqual(dx12_context.device, OnLastPresent.last_device);
    try testing.expectEqual(dx12_context.command_queue, OnLastPresent.last_command_queue);
}

test "init should error when hooking is not initialized" {
    const dx12Context = try dx12.TestingContext.init();
    defer dx12Context.deinit();

    const onPresent = struct {
        fn call(device: *const w32.ID3D12Device, command_queue: *const w32.ID3D12CommandQueue) void {
            _ = device;
            _ = command_queue;
        }
    }.call;

    const hooks = MainHooks(onPresent, onPresent, onPresent);
    try testing.expectError(error.HookingNotInitialized, hooks.init());
}
