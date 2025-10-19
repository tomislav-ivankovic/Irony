const std = @import("std");
const w32 = @import("win32").everything;
const sdk = @import("sdk/root.zig");
const dll = @import("dll/root.zig");

pub const module_name = "irony.dll";

pub const log_file_name = "irony.log";
pub const buffer_logger = sdk.log.BufferLogger(.{});
pub const file_logger = sdk.log.FileLogger(.{});
pub const std_options = std.Options{
    .log_level = .info,
    .logFn = sdk.log.CompositeLogger(&.{
        buffer_logger.logFn,
        file_logger.logFn,
        sdk.ui.toasts.logFn,
    }).logFn,
};

const MainAllocator = std.heap.GeneralPurposeAllocator(.{});
const MemorySearchTask = sdk.misc.Task(dll.game.Memory);

const main_hooks = sdk.hooking.MainHooks(onHooksInit, onHooksDeinit, onUpdate, beforeResize, afterResize);
const game_hooks = dll.game.Hooks(onTick);
const number_of_hooking_retries = 10;
const hooking_retry_sleep_time = 100 * std.time.ns_per_ms;

var module_handle_shared_value: ?sdk.os.SharedValue(w32.HINSTANCE) = null;
var base_dir = sdk.fs.BaseDir.working_dir;
var main_allocator: ?MainAllocator = null;
var window_procedure: ?sdk.os.WindowProcedure = null;
var event_buss: ?dll.EventBuss = null;
var memory_search_task: ?MemorySearchTask = null;

pub fn DllMain(
    module_handle: w32.HINSTANCE,
    forward_reason: u32,
    reserved: *anyopaque,
) callconv(.winapi) w32.BOOL {
    _ = reserved;
    switch (forward_reason) {
        w32.DLL_PROCESS_ATTACH => {
            std.log.info("DLL attached event detected.", .{});

            std.log.debug("Creating module handle shared value...", .{});
            if (createModuleHandleSharedValue(module_handle)) |shared_value| {
                std.log.info("Module handle shared value created.", .{});
                module_handle_shared_value = shared_value;
            } else |err| {
                sdk.misc.error_context.append("Failed to create module handle shared value.", .{});
                sdk.misc.error_context.logError(err);
            }

            std.log.debug("Spawning the initialization thread...", .{});
            const thread = std.Thread.spawn(.{}, init, .{}) catch |err| {
                sdk.misc.error_context.new("Failed to spawn initialization thread.", .{});
                sdk.misc.error_context.logError(err);
                return 0;
            };
            thread.detach();
            std.log.debug("Initialization thread spawned.", .{});

            std.log.info("DLL attached successfully.", .{});
            return 1;
        },
        w32.DLL_PROCESS_DETACH => {
            std.log.info("DLL detach event detected.", .{});

            deinit();

            std.log.debug("Destroying module handle shared value...", .{});
            if (module_handle_shared_value) |*shared_value| {
                if (shared_value.destroy()) {
                    std.log.info("Module handle shared value destroyed.", .{});
                    module_handle_shared_value = null;
                } else |err| {
                    sdk.misc.error_context.append("Failed to destroy module handle shared value.", .{});
                    sdk.misc.error_context.logError(err);
                }
            } else {
                std.log.debug("Nothing to destroy.", .{});
            }

            std.log.info("Detaching from the process now...", .{});
            return 1;
        },
        else => return 0,
    }
}

fn createModuleHandleSharedValue(module_handle: w32.HINSTANCE) !sdk.os.SharedValue(w32.HINSTANCE) {
    const shared_value = sdk.os.SharedValue(w32.HINSTANCE).create(module_name) catch |err| {
        sdk.misc.error_context.append("Failed to create shared value named: {s}", .{module_name});
        return err;
    };
    errdefer {
        shared_value.destroy() catch |err| {
            sdk.misc.error_context.append("Failed to destroy shared value.", .{});
            sdk.misc.error_context.logError(err);
        };
    }
    shared_value.write(module_handle) catch |err| {
        sdk.misc.error_context.append("Failed to write the module handle to shared value.", .{});
        return err;
    };
    return shared_value;
}

fn init() void {
    std.log.info("Running initialization...", .{});

    std.log.debug("Finding base directory...", .{});
    findBaseDir();
    std.log.info("Base directory set to: {s}", .{base_dir.get()});

    std.log.debug("Starting file logging...", .{});
    if (startFileLogging()) {
        std.log.info("File logging started.", .{});
    } else |err| {
        sdk.misc.error_context.append("Failed to start file logging.", .{});
        sdk.misc.error_context.logError(err);
    }

    std.log.debug("Initializing main allocator...", .{});
    main_allocator = MainAllocator.init;
    std.log.info("Main allocator initialized.", .{});

    std.log.debug("Initializing hooking...", .{});
    sdk.hooking.init() catch |err| {
        sdk.misc.error_context.append("Failed to initialize hooking.", .{});
        sdk.misc.error_context.logError(err);
        return;
    };
    std.log.info("Hooking initialized.", .{});

    std.log.debug("Initializing main hooks...", .{});
    for (0..number_of_hooking_retries) |retry_number| {
        main_hooks.init() catch |err| {
            if (retry_number < number_of_hooking_retries - 1) {
                std.Thread.sleep(hooking_retry_sleep_time);
                continue;
            } else {
                sdk.misc.error_context.append("Failed to initialize main hooks.", .{});
                sdk.misc.error_context.logError(err);
                return;
            }
        };
        break;
    }
    std.log.info("Main hooks initialized.", .{});

    std.log.info("Initialization completed.", .{});
}

fn deinit() void {
    std.log.info("Running de-initialization...", .{});

    std.log.debug("De-initializing main hooks...", .{});
    main_hooks.deinit();
    std.log.info("Main hooks de-initialized.", .{});

    std.log.debug("De-initializing hooking...", .{});
    if (sdk.hooking.deinit()) {
        std.log.info("Hooking de-initialized.", .{});
    } else |err| {
        sdk.misc.error_context.append("Failed to de-initialize hooking.", .{});
        sdk.misc.error_context.logError(err);
    }

    std.log.debug("De-initializing main allocator...", .{});
    if (main_allocator) |*allocator| {
        switch (allocator.deinit()) {
            .ok => std.log.info("Main allocator de-initialized.", .{}),
            .leak => std.log.err("Main allocator detected memory leaks.", .{}),
        }
    } else {
        std.log.debug("Nothing to de-initialize.", .{});
    }

    std.log.info("Stopping file logging...", .{});
    file_logger.stop();
    std.log.info("File logging stopped.", .{});

    std.log.info("De-initialization completed.", .{});
}

fn findBaseDir() void {
    const dll_module = sdk.os.Module.getLocal(module_name) catch |err| {
        sdk.misc.error_context.append("Failed to get local module: {s}", .{module_name});
        sdk.misc.error_context.append("Failed find base directory.", .{});
        sdk.misc.error_context.logError(err);
        std.log.info("Defaulting base directory to working directory.", .{});
        base_dir = sdk.fs.BaseDir.working_dir;
        return;
    };
    base_dir = sdk.fs.BaseDir.fromModule(&dll_module) catch |err| {
        sdk.misc.error_context.append("Failed to find base directory from module: {s}", .{module_name});
        sdk.misc.error_context.append("Failed find base directory.", .{});
        sdk.misc.error_context.logError(err);
        std.log.info("Defaulting base directory to working directory.", .{});
        base_dir = sdk.fs.BaseDir.working_dir;
        return;
    };
}

fn startFileLogging() !void {
    var buffer: [sdk.os.max_file_path_length]u8 = undefined;
    const size = base_dir.getPath(&buffer, log_file_name) catch |err| {
        sdk.misc.error_context.append("Failed to find log file path.", .{});
        return err;
    };
    const file_path = buffer[0..size];
    file_logger.start(file_path) catch |err| {
        sdk.misc.error_context.append("Failed to start file logging with file path: {s}", .{file_path});
        return err;
    };
}

fn onHooksInit(
    window: w32.HWND,
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    swap_chain: *const w32.IDXGISwapChain,
) void {
    const allocator = if (main_allocator) |*a| a.allocator() else return;

    std.log.info("Initializing event buss...", .{});
    event_buss = dll.EventBuss.init(allocator, &base_dir, window, device, command_queue, swap_chain);
    std.log.info("Event buss initialized.", .{});

    std.log.debug("Initializing window procedure...", .{});
    if (sdk.os.WindowProcedure.init(window, windowProcedure)) |procedure| {
        std.log.info("Window procedure initialized.", .{});
        window_procedure = procedure;
    } else |err| {
        sdk.misc.error_context.append("Failed to initialize window procedure.", .{});
        sdk.misc.error_context.logError(err);
    }

    std.log.debug("Spawning memory search task...", .{});
    if (MemorySearchTask.spawn(allocator, performMemorySearch, .{ allocator, &base_dir })) |task| {
        std.log.info("Memory search task spawned.", .{});
        memory_search_task = task;
    } else |err| {
        sdk.misc.error_context.append("Failed to spawn memory search task. Searching in main thread...", .{});
        sdk.misc.error_context.logWarning(err);
        const result = performMemorySearch(allocator, &base_dir);
        memory_search_task = MemorySearchTask.createCompleted(result);
    }
}

fn performMemorySearch(allocator: std.mem.Allocator, dir: *const sdk.fs.BaseDir) dll.game.Memory {
    std.log.debug("Initializing game memory...", .{});
    const game_memory = dll.game.Memory.init(allocator, dir, &game_hooks.last_camera_manager_address);
    std.log.info("Game memory initialized.", .{});

    std.log.debug("Initializing game hooks...", .{});
    game_hooks.init(&game_memory.functions);
    std.log.info("Game hooks initialized.", .{});

    return game_memory;
}

fn onHooksDeinit(
    window: w32.HWND,
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    swap_chain: *const w32.IDXGISwapChain,
) void {
    std.log.debug("Joining memory search task...", .{});
    if (memory_search_task) |*task| {
        _ = task.join();
        std.log.info("Memory search task joined.", .{});

        std.log.debug("De-initializing game hooks...", .{});
        game_hooks.deinit();
        std.log.info("Game hooks de-initialized.", .{});

        memory_search_task = null;
    } else {
        std.log.debug("Nothing to join.", .{});
    }

    std.log.debug("De-initializing window procedure...", .{});
    if (window_procedure) |*procedure| {
        if (procedure.deinit()) {
            window_procedure = null;
            std.log.info("Window procedure de-initialized.", .{});
        } else |err| {
            sdk.misc.error_context.append("Failed to de-initialize window procedure.", .{});
            sdk.misc.error_context.logError(err);
        }
    } else {
        std.log.debug("Nothing to de-initialize.", .{});
    }

    std.log.info("De-initializing event buss...", .{});
    if (event_buss) |*buss| {
        buss.deinit(&base_dir, window, device, command_queue, swap_chain);
        event_buss = null;
        std.log.info("Event buss de-initialized.", .{});
    } else {
        std.log.info("Nothing to de-initialize.", .{});
    }
}

fn onTick() void {
    if (event_buss) |*buss| {
        const game_memory = memory_search_task.?.join();
        buss.tick(game_memory);
    }
}

fn onUpdate(
    window: w32.HWND,
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    swap_chain: *const w32.IDXGISwapChain,
) void {
    if (event_buss) |*buss| {
        const game_memory = memory_search_task.?.peek();
        buss.draw(&base_dir, window, device, command_queue, swap_chain, game_memory);
    }
}

fn beforeResize(
    window: w32.HWND,
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    swap_chain: *const w32.IDXGISwapChain,
) void {
    std.log.info("Detected before resize event.", .{});
    if (event_buss) |*buss| {
        buss.beforeResize(&base_dir, window, device, command_queue, swap_chain);
    }
}

fn afterResize(
    window: w32.HWND,
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    swap_chain: *const w32.IDXGISwapChain,
) void {
    std.log.info("Detected after resize event.", .{});
    std.log.info("Detected before resize event.", .{});
    if (event_buss) |*buss| {
        buss.afterResize(&base_dir, window, device, command_queue, swap_chain);
    }
}

fn windowProcedure(
    window: w32.HWND,
    u_msg: u32,
    w_param: w32.WPARAM,
    l_param: w32.LPARAM,
) callconv(.winapi) w32.LRESULT {
    if (event_buss) |*buss| {
        const result = buss.processWindowMessage(&base_dir, window, u_msg, w_param, l_param);
        if (result) |r| {
            return r;
        }
    }
    return w32.CallWindowProcW(window_procedure.?.original, window, u_msg, w_param, l_param);
}
