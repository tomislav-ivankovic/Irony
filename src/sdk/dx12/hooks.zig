const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const memory = @import("../memory/root.zig");
const dx12 = @import("root.zig");

pub const OnHookEvent = fn (context: dx12.HostContext) void;

pub fn Hooks(onPresent: *const OnHookEvent, beforeResize: *const OnHookEvent, afterResize: *const OnHookEvent) type {
    return struct {
        var execute_command_lists_hook: ?memory.Hook(dx12.Functions.ExecuteCommandLists) = null;
        var resize_buffers_hook: ?memory.Hook(dx12.Functions.ResizeBuffers) = null;
        var present_hook: ?memory.Hook(dx12.Functions.Present) = null;
        var g_command_queue: ?*const w32.ID3D12CommandQueue = null;
        var active_hook_calls = std.atomic.Value(u8).init(0);

        pub fn init() !void {
            std.log.debug("Finding DX12 functions...", .{});
            const dx12_functions = dx12.Functions.find() catch |err| {
                misc.error_context.append("Failed to find DX12 functions.", .{});
                return err;
            };
            std.log.info("DX12 functions found.", .{});

            std.log.debug("Creating the execute command lists hook...", .{});
            execute_command_lists_hook = memory.Hook(dx12.Functions.ExecuteCommandLists).create(
                dx12_functions.executeCommandLists,
                onExecuteCommandLists,
            ) catch |err| {
                misc.error_context.append("Failed to create execute command lists hook.", .{});
                return err;
            };
            std.log.info("Execute command lists hook created.", .{});
            errdefer {
                const saved = misc.error_context.save();
                defer misc.error_context.restore(&saved);
                execute_command_lists_hook.?.destroy() catch |err| {
                    misc.error_context.append("Failed to destroy execute command lists hook.", .{});
                    misc.error_context.logError(err);
                };
                execute_command_lists_hook = null;
            }

            std.log.debug("Creating the resize buffers hook...", .{});
            resize_buffers_hook = memory.Hook(dx12.Functions.ResizeBuffers).create(
                dx12_functions.resizeBuffers,
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
            present_hook = memory.Hook(dx12.Functions.Present).create(
                dx12_functions.present,
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

        pub fn deinit(io: std.Io) void {
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

            while (active_hook_calls.load(.seq_cst) > 0) {
                io.sleep(.fromMilliseconds(10), .awake) catch |err| {
                    misc.error_context.append("Failed to sleep for 10 ms while waiting on active DX12 hooks.", .{});
                    misc.error_context.logError(err);
                };
            }

            std.log.debug("Releasing the DX12 command queue...", .{});
            if (g_command_queue) |command_queue| {
                _ = command_queue.IUnknown.Release();
                std.log.info("DX12 command queue released.", .{});
            } else {
                std.log.debug("Nothing to release.", .{});
            }
        }

        fn onExecuteCommandLists(
            command_queue: *const w32.ID3D12CommandQueue,
            num_command_lists: u32,
            pp_command_lists: [*]?*w32.ID3D12CommandList,
        ) callconv(.winapi) void {
            _ = active_hook_calls.fetchAdd(1, .seq_cst);
            defer _ = active_hook_calls.fetchSub(1, .seq_cst);

            execute_command_lists_hook.?.original(command_queue, num_command_lists, pp_command_lists);
            if (command_queue == g_command_queue) {
                return;
            }

            const getDesc: *const fn (
                self: *const w32.ID3D12CommandQueue,
                out: *w32.D3D12_COMMAND_QUEUE_DESC,
            ) callconv(.winapi) void = @ptrCast(command_queue.vtable.GetDesc);
            var desc: w32.D3D12_COMMAND_QUEUE_DESC = undefined;
            getDesc(command_queue, &desc);
            if (desc.Type != .DIRECT) {
                return;
            }

            if (g_command_queue) |previous_command_queue| {
                _ = previous_command_queue.IUnknown.Release();
            } else {
                std.log.info("DX12 command queue found.", .{});
            }
            _ = command_queue.IUnknown.AddRef();
            g_command_queue = command_queue;
        }

        fn onPresentInternal(
            swap_chain: *const w32.IDXGISwapChain,
            sync_interval: u32,
            flags: u32,
        ) callconv(.winapi) w32.HRESULT {
            _ = active_hook_calls.fetchAdd(1, .seq_cst);
            defer _ = active_hook_calls.fetchSub(1, .seq_cst);

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
            const context = dx12.HostContext{
                .window = window,
                .device = device,
                .command_queue = command_queue,
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

            const context = dx12.HostContext{
                .window = window,
                .device = device,
                .command_queue = command_queue,
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
    const dx12_context = try dx12.TestingContext.init();
    defer dx12_context.deinit();

    try memory.hooking.init();
    defer memory.hooking.deinit() catch @panic("Failed to de-initialize hooking.");

    const OnPresent = struct {
        var times_called: usize = 0;
        var last_context: ?dx12.HostContext = null;
        fn call(context: dx12.HostContext) void {
            times_called += 1;
            last_context = context;
        }
    };
    const BeforeResize = struct {
        var times_called: usize = 0;
        var last_context: ?dx12.HostContext = null;
        fn call(context: dx12.HostContext) void {
            times_called += 1;
            last_context = context;
        }
    };
    const AfterResize = struct {
        var times_called: usize = 0;
        var last_context: ?dx12.HostContext = null;
        fn call(context: dx12.HostContext) void {
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

    for (0..3) |_| {
        const present_result = dx12_context.swap_chain.Present(0, w32.DXGI_PRESENT_TEST);
        try testing.expectEqual(w32.S_OK, present_result);
    }

    try testing.expectEqual(0, OnPresent.times_called);
    try testing.expectEqual(0, BeforeResize.times_called);
    try testing.expectEqual(0, AfterResize.times_called);

    const command_lists = [0](?*w32.ID3D12CommandList){};
    dx12_context.command_queue.ExecuteCommandLists(command_lists.len, &command_lists);

    try testing.expectEqual(0, OnPresent.times_called);
    try testing.expectEqual(0, BeforeResize.times_called);
    try testing.expectEqual(0, AfterResize.times_called);

    for (0..5) |_| {
        const present_result = dx12_context.swap_chain.Present(0, w32.DXGI_PRESENT_TEST);
        try testing.expectEqual(w32.S_OK, present_result);
    }

    try testing.expectEqual(5, OnPresent.times_called);
    try testing.expectEqual(0, BeforeResize.times_called);
    try testing.expectEqual(0, AfterResize.times_called);

    try testing.expectEqual(dx12_context.getHostContext(), OnPresent.last_context);

    const resize_result_1 = dx12_context.swap_chain.ResizeBuffers(
        3,
        200,
        200,
        w32.DXGI_FORMAT_R8G8B8A8_UNORM,
        @intFromEnum(w32.DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH),
    );
    try testing.expectEqual(w32.S_OK, resize_result_1);

    try testing.expectEqual(1, BeforeResize.times_called);
    try testing.expectEqual(dx12_context.getHostContext(), BeforeResize.last_context);
    try testing.expectEqual(1, AfterResize.times_called);
    try testing.expectEqual(dx12_context.getHostContext(), AfterResize.last_context);
}

test "init should error when hooking is not initialized" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const dx12_context = try dx12.TestingContext.init();
    defer dx12_context.deinit();

    const onEvent = struct {
        fn call(context: dx12.HostContext) void {
            _ = context;
        }
    }.call;

    const hooks = Hooks(onEvent, onEvent, onEvent);
    try testing.expectError(error.HookingNotInitialized, hooks.init());
}
