const std = @import("std");
const w32 = @import("win32").everything;
const misc = @import("misc/root.zig");
const log = @import("log/root.zig");
const os = @import("os/root.zig");
const dx12 = @import("dx12/root.zig");
const hooking = @import("hooking/root.zig");
const ui = @import("ui/root.zig");
const game = @import("game/root.zig");
const EventBuss = @import("event_buss.zig").EventBuss;

pub const module_name = "irony.dll";

pub const log_file_name = "irony.log";
pub const buffer_logger = log.BufferLogger(.{});
pub const file_logger = log.FileLogger(.{});
pub const std_options = std.Options{
    .log_level = .info,
    .logFn = log.CompositeLogger(&.{
        buffer_logger.logFn,
        file_logger.logFn,
        ui.toasts.logFn,
    }).logFn,
};

const MainAllocator = std.heap.GeneralPurposeAllocator(.{});
const MemorySearchTask = misc.Task(MemorySearchResult);
const MemorySearchResult = struct {
    game_memory: game.Memory,
    tick_hook: ?TickHook,
};
const TickHook = hooking.Hook(game.TickFunction);

const main_hooks = hooking.MainHooks(onHooksInit, onHooksDeinit, onHooksUpdate, beforeHooksResize, afterHooksResize);

var module_handle_shared_value: ?os.SharedValue(w32.HINSTANCE) = null;
var base_dir = misc.BaseDir.working_dir;
var main_allocator: ?MainAllocator = null;
var window_procedure: ?os.WindowProcedure = null;
var event_buss: ?EventBuss = null;
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
                misc.error_context.append("Failed to create module handle shared value.", .{});
                misc.error_context.logError(err);
            }

            std.log.debug("Spawning the initialization thread...", .{});
            const thread = std.Thread.spawn(.{}, init, .{}) catch |err| {
                misc.error_context.new("Failed to spawn initialization thread.", .{});
                misc.error_context.logError(err);
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
                    misc.error_context.append("Failed to destroy module handle shared value.", .{});
                    misc.error_context.logError(err);
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

fn createModuleHandleSharedValue(module_handle: w32.HINSTANCE) !os.SharedValue(w32.HINSTANCE) {
    const shared_value = os.SharedValue(w32.HINSTANCE).create(module_name) catch |err| {
        misc.error_context.append("Failed to create shared value named: {s}", .{module_name});
        return err;
    };
    errdefer {
        shared_value.destroy() catch |err| {
            misc.error_context.append("Failed to destroy shared value.", .{});
            misc.error_context.logError(err);
        };
    }
    shared_value.write(module_handle) catch |err| {
        misc.error_context.append("Failed to write the module handle to shared value.", .{});
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
        misc.error_context.append("Failed to start file logging.", .{});
        misc.error_context.logError(err);
    }

    std.log.debug("Initializing main allocator...", .{});
    main_allocator = MainAllocator.init;
    std.log.info("Main allocator initialized.", .{});

    std.log.debug("Initializing hooking...", .{});
    hooking.init() catch |err| {
        misc.error_context.append("Failed to initialize hooking.", .{});
        misc.error_context.logError(err);
        return;
    };
    std.log.info("Hooking initialized.", .{});

    std.log.debug("Initializing main hooks...", .{});
    main_hooks.init() catch |err| {
        misc.error_context.append("Failed to initialize main hooks.", .{});
        misc.error_context.logError(err);
        return;
    };
    std.log.info("Main hooks initialized.", .{});

    std.log.info("Initialization completed.", .{});
}

fn deinit() void {
    std.log.info("Running de-initialization...", .{});

    std.log.debug("De-initializing main hooks...", .{});
    main_hooks.deinit();
    std.log.info("Main hooks de-initialized.", .{});

    std.log.debug("De-initializing hooking...", .{});
    if (hooking.deinit()) {
        std.log.info("Hooking de-initialized.", .{});
    } else |err| {
        misc.error_context.append("Failed to de-initialize hooking.", .{});
        misc.error_context.logError(err);
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
    const dll_module = os.Module.getLocal(module_name) catch |err| {
        misc.error_context.append("Failed to get local module: {s}", .{module_name});
        misc.error_context.append("Failed find base directory.", .{});
        misc.error_context.logError(err);
        std.log.info("Defaulting base directory to working directory.", .{});
        base_dir = misc.BaseDir.working_dir;
        return;
    };
    base_dir = misc.BaseDir.fromModule(&dll_module) catch |err| {
        misc.error_context.append("Failed to find base directory from module: {s}", .{module_name});
        misc.error_context.append("Failed find base directory.", .{});
        misc.error_context.logError(err);
        std.log.info("Defaulting base directory to working directory.", .{});
        base_dir = misc.BaseDir.working_dir;
        return;
    };
}

fn startFileLogging() !void {
    var buffer: [os.max_file_path_length]u8 = undefined;
    const size = base_dir.getPath(&buffer, log_file_name) catch |err| {
        misc.error_context.append("Failed to find log file path.", .{});
        return err;
    };
    const file_path = buffer[0..size];
    file_logger.start(file_path) catch |err| {
        misc.error_context.append("Failed to start file logging with file path: {s}", .{file_path});
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
    event_buss = EventBuss.init(allocator, &base_dir, window, device, command_queue, swap_chain);
    std.log.info("Event buss initialized.", .{});

    std.log.debug("Initializing window procedure...", .{});
    if (os.WindowProcedure.init(window, windowProcedure)) |procedure| {
        std.log.info("Window procedure initialized.", .{});
        window_procedure = procedure;
    } else |err| {
        misc.error_context.append("Failed to initialize window procedure.", .{});
        misc.error_context.logError(err);
    }

    std.log.debug("Spawning memory search task...", .{});
    if (MemorySearchTask.spawn(allocator, performMemorySearch, .{ allocator, &base_dir })) |task| {
        std.log.info("Memory search task spawned.", .{});
        memory_search_task = task;
    } else |err| {
        misc.error_context.append("Failed to spawn memory search task. Searching in main thread...", .{});
        misc.error_context.logWarning(err);
        const result = performMemorySearch(allocator, &base_dir);
        memory_search_task = MemorySearchTask.createCompleted(result);
    }
}

fn performMemorySearch(allocator: std.mem.Allocator, dir: *const misc.BaseDir) MemorySearchResult {
    std.log.debug("Initializing game memory...", .{});
    const game_memory = game.Memory.init(allocator, dir);
    std.log.info("Game memory initialized.", .{});

    std.log.debug("Creating tick hook...", .{});
    var tick_hook = if (game_memory.tick_function) |tick_function| block: {
        if (TickHook.create(tick_function, onTick)) |hook| {
            std.log.info("Tick hook created.", .{});
            break :block hook;
        } else |err| {
            misc.error_context.append("Failed to create tick hook.", .{});
            misc.error_context.logError(err);
            break :block null;
        }
    } else block: {
        misc.error_context.new("Tick function not found.", .{});
        misc.error_context.append("Failed to create tick hook.", .{});
        misc.error_context.logError(error.NotFound);
        break :block null;
    };

    if (tick_hook) |*hook| {
        std.log.debug("Enabling tick hook...", .{});
        if (hook.enable()) {
            std.log.info("Tick hook enabled.", .{});
        } else |err| {
            misc.error_context.append("Failed to enable tick hook.", .{});
            misc.error_context.logError(err);
        }
    }

    return .{ .game_memory = game_memory, .tick_hook = tick_hook };
}

fn onHooksDeinit(
    window: w32.HWND,
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    swap_chain: *const w32.IDXGISwapChain,
) void {
    std.log.debug("Joining memory search task...", .{});
    if (memory_search_task) |*task| {
        const result = task.join();
        std.log.info("Memory search task joined.", .{});

        std.log.debug("Destroying tick hook...", .{});
        if (result.tick_hook) |*hook| {
            if (hook.destroy()) {
                std.log.info("Tick hook destroyed.", .{});
                result.tick_hook = null;
            } else |err| {
                misc.error_context.append("Failed to destroy tick hook.", .{});
                misc.error_context.logError(err);
            }
        } else {
            std.log.debug("Nothing to destroy.", .{});
        }

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
            misc.error_context.append("Failed to de-initialize window procedure.", .{});
            misc.error_context.logError(err);
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

fn onTick(delta_time: f64) callconv(.c) void {
    const task = memory_search_task.?.join();
    task.tick_hook.?.original(delta_time);
    if (event_buss) |*buss| {
        buss.tick(&task.game_memory);
    }
}

fn onHooksUpdate(
    window: w32.HWND,
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    swap_chain: *const w32.IDXGISwapChain,
) void {
    if (event_buss) |*buss| {
        const task = memory_search_task.?.peek();
        const game_memory = if (task) |t| &t.game_memory else null;
        buss.draw(&base_dir, window, device, command_queue, swap_chain, game_memory);
    }
}

fn beforeHooksResize(
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

fn afterHooksResize(
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
