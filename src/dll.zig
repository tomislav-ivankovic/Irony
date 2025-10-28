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
const Event = union(enum) {
    present: Dx12Event,
    tick: void,
    before_resize: Dx12Event,
    after_resize: Dx12Event,
    window_procedure: WindowProcedure,
    shut_down: void,

    pub const Dx12Event = struct {
        window: w32.HWND,
        device: *const w32.ID3D12Device,
        command_queue: *const w32.ID3D12CommandQueue,
        swap_chain: *const w32.IDXGISwapChain,
    };
    pub const WindowProcedure = struct {
        window: w32.HWND,
        u_msg: u32,
        w_param: w32.WPARAM,
        l_param: w32.LPARAM,
        out_window_procedure: *?sdk.os.WindowProcedure,
        out_result: *?w32.LRESULT,
    };
};

const dx12_hooks = sdk.dx12.Hooks(onPresent, beforeResize, afterResize);
const game_hooks = dll.game.Hooks(onTick);
const number_of_hooking_retries = 10;
const hooking_retry_sleep_time = 100 * std.time.ns_per_ms;

var dll_module: sdk.os.Module = undefined;
var module_handle_shared_value: ?sdk.os.SharedValue(w32.HINSTANCE) = null;
var main_thread: ?std.Thread = null;
var main_thread_running = std.atomic.Value(bool).init(false);

var pending_event_mutex = std.Thread.Mutex{};
var producer_mutex = std.Thread.Mutex{};
var consumer_condition = std.Thread.Condition{};
var producer_condition = std.Thread.Condition{};
var pending_event: ?Event = null;
var listening_to_events = std.atomic.Value(bool).init(false);

pub fn DllMain(
    module_handle: w32.HINSTANCE,
    forward_reason: u32,
    reserved: *anyopaque,
) callconv(.winapi) w32.BOOL {
    _ = reserved;
    switch (forward_reason) {
        w32.DLL_PROCESS_ATTACH => {
            std.log.info("DLL attached event detected.", .{});
            dll_module = sdk.os.Module{ .handle = module_handle, .process = .getCurrent() };

            std.log.debug("Creating module handle shared value...", .{});
            module_handle_shared_value = if (createModuleHandleSharedValue(module_handle)) |shared_value| block: {
                std.log.info("Module handle shared value created.", .{});
                break :block shared_value;
            } else |err| block: {
                sdk.misc.error_context.append("Failed to create module handle shared value.", .{});
                sdk.misc.error_context.logError(err);
                break :block null;
            };

            std.log.debug("Spawning the main thread...", .{});
            main_thread = std.Thread.spawn(.{}, main, .{}) catch |err| {
                sdk.misc.error_context.new("Failed to spawn main thread.", .{});
                sdk.misc.error_context.logError(err);
                return 0;
            };
            std.log.debug("Main thread spawned.", .{});
            main_thread_running.store(true, .seq_cst);

            std.log.info("DLL attached successfully.", .{});
            return 1;
        },
        w32.DLL_PROCESS_DETACH => {
            std.log.info("DLL detach event detected.", .{});

            std.log.debug("Shutting down main thread...", .{});
            if (main_thread) |*thread| {
                std.log.debug("Sending shutdown event...", .{});
                sendEvent(&.shut_down);
                std.log.info("Shutdown event sent.", .{});

                std.log.debug("Waiting for main thread to shut down...", .{});
                while (main_thread_running.load(.seq_cst)) {
                    std.Thread.sleep(100 * std.time.ns_per_ms);
                }
                thread.detach();
                std.log.info("Main thread shut down.", .{});
            } else {
                std.log.debug("Nothing to shut down.", .{});
            }

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

pub fn selfEject() void {
    const thread = std.Thread.spawn(.{}, struct {
        fn call() void {
            const success = w32.FreeLibrary(dll_module.handle);
            if (success == 0) {
                sdk.misc.error_context.new("{f}", .{sdk.os.Error.getLast()});
                sdk.misc.error_context.append("FreeLibrary returned 0.", .{});
                sdk.misc.error_context.append("Failed to self eject.", .{});
                return;
            }
        }
    }.call, .{}) catch |err| {
        sdk.misc.error_context.new("Failed to spawn ejection thread.", .{});
        sdk.misc.error_context.append("Failed to self eject.", .{});
        sdk.misc.error_context.logError(err);
        return;
    };
    thread.detach();
}

pub fn main() void {
    defer main_thread_running.store(false, .seq_cst);

    std.log.info("Main thread started.", .{});
    defer std.log.info("Main thread stopped.", .{});

    std.log.debug("Finding base directory...", .{});
    const base_dir = if (sdk.misc.BaseDir.fromModule(&dll_module)) |dir| block: {
        std.log.info("Base directory found: {s}", .{dir.get()});
        break :block dir;
    } else |err| block: {
        sdk.misc.error_context.append("Failed to find base directory. Using working directory instead.", .{});
        sdk.misc.error_context.logError(err);
        break :block sdk.misc.BaseDir.working_dir;
    };

    std.log.debug("Starting file logging...", .{});
    if (startFileLogging(&base_dir)) {
        std.log.info("File logging started.", .{});
    } else |err| {
        sdk.misc.error_context.append("Failed to start file logging.", .{});
        sdk.misc.error_context.logError(err);
    }
    defer {
        std.log.info("Stopping file logging...", .{});
        file_logger.stop();
        std.log.info("File logging stopped.", .{});
    }

    std.log.debug("Initializing main allocator...", .{});
    var main_allocator = MainAllocator.init;
    const allocator = main_allocator.allocator();
    std.log.info("Main allocator initialized.", .{});
    defer {
        std.log.debug("De-initializing main allocator...", .{});
        switch (main_allocator.deinit()) {
            .ok => std.log.info("Main allocator de-initialized.", .{}),
            .leak => std.log.err("Main allocator detected memory leaks.", .{}),
        }
    }

    std.log.debug("Initializing hooking...", .{});
    sdk.hooking.init() catch |err| {
        sdk.misc.error_context.append("Failed to initialize hooking.", .{});
        sdk.misc.error_context.logError(err);
        return;
    };
    std.log.info("Hooking initialized.", .{});
    defer {
        std.log.debug("De-initializing hooking...", .{});
        if (sdk.hooking.deinit()) {
            std.log.info("Hooking de-initialized.", .{});
        } else |err| {
            sdk.misc.error_context.append("Failed to de-initialize hooking.", .{});
            sdk.misc.error_context.logError(err);
        }
    }

    std.log.debug("Initializing DX12 hooks...", .{});
    for (0..number_of_hooking_retries) |retry_number| {
        dx12_hooks.init() catch |err| {
            if (retry_number < number_of_hooking_retries - 1) {
                std.Thread.sleep(hooking_retry_sleep_time);
                continue;
            } else {
                sdk.misc.error_context.append("Failed to initialize DX12 hooks.", .{});
                sdk.misc.error_context.logError(err);
                return;
            }
        };
        break;
    }
    std.log.info("DX12 hooks initialized.", .{});
    defer {
        std.log.debug("De-initializing DX12 hooks...", .{});
        dx12_hooks.deinit();
        std.log.info("DX12 hooks de-initialized.", .{});
    }

    std.log.debug("Spawning memory search task...", .{});
    var memory_search_task = if (MemorySearchTask.spawn(
        allocator,
        performMemorySearch,
        .{ allocator, &base_dir },
    )) |task| block: {
        std.log.info("Memory search task spawned.", .{});
        break :block task;
    } else |err| block: {
        sdk.misc.error_context.append("Failed to spawn memory search task. Searching in main thread...", .{});
        sdk.misc.error_context.logWarning(err);
        const result = performMemorySearch(allocator, &base_dir);
        break :block MemorySearchTask.createCompleted(result);
    };
    defer {
        std.log.debug("Joining memory search task...", .{});
        _ = memory_search_task.join();
        std.log.info("Memory search task joined.", .{});

        std.log.debug("De-initializing game hooks...", .{});
        game_hooks.deinit();
        std.log.info("Game hooks de-initialized.", .{});
    }

    const State = enum { starting_up, up, shutting_down };
    var state = State.starting_up;
    var event_buss: ?dll.EventBuss = null;
    var window_procedure: ?sdk.os.WindowProcedure = null;

    pending_event_mutex.lock();
    listening_to_events.store(true, .seq_cst);
    defer {
        listening_to_events.store(false, .seq_cst);
        pending_event_mutex.unlock();
        producer_condition.broadcast();
    }

    while (true) {
        consumer_condition.wait(&pending_event_mutex);
        const event = pending_event orelse continue;
        defer {
            pending_event = null;
            producer_condition.signal();
        }
        switch (event) {
            .present => |*e| switch (state) {
                .starting_up => {
                    std.log.info("Initializing event buss...", .{});
                    event_buss = .init(allocator, &base_dir, e.window, e.device, e.command_queue, e.swap_chain);
                    std.log.info("Event buss initialized.", .{});

                    std.log.debug("Initializing window procedure...", .{});
                    if (sdk.os.WindowProcedure.init(e.window, windowProcedure)) |procedure| {
                        std.log.info("Window procedure initialized.", .{});
                        window_procedure = procedure;
                    } else |err| {
                        sdk.misc.error_context.append("Failed to initialize window procedure.", .{});
                        sdk.misc.error_context.logError(err);
                    }

                    state = .up;
                },
                .up => {
                    if (event_buss) |*buss| {
                        const game_memory = memory_search_task.peek();
                        buss.draw(&base_dir, e.window, e.device, e.command_queue, e.swap_chain, game_memory);
                    }
                },
                .shutting_down => {
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
                        buss.deinit(&base_dir, e.window, e.device, e.command_queue, e.swap_chain);
                        event_buss = null;
                        std.log.info("Event buss de-initialized.", .{});
                    } else {
                        std.log.info("Nothing to de-initialize.", .{});
                    }

                    break;
                },
            },
            .tick => {
                if (event_buss) |*buss| {
                    const game_memory = memory_search_task.join();
                    buss.tick(game_memory);
                }
            },
            .before_resize => |*e| {
                std.log.info("Detected before resize event.", .{});
                if (event_buss) |*buss| {
                    buss.beforeResize(&base_dir, e.window, e.device, e.command_queue, e.swap_chain);
                }
            },
            .after_resize => |*e| {
                std.log.info("Detected after resize event.", .{});
                if (event_buss) |*buss| {
                    buss.afterResize(&base_dir, e.window, e.device, e.command_queue, e.swap_chain);
                }
            },
            .window_procedure => |*e| {
                e.out_window_procedure.* = window_procedure;
                if (event_buss) |*buss| {
                    e.out_result.* = buss.processWindowMessage(&base_dir, e.window, e.u_msg, e.w_param, e.l_param);
                }
            },
            .shut_down => {
                state = .shutting_down;
            },
        }
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

fn startFileLogging(base_dir: *const sdk.misc.BaseDir) !void {
    var buffer: [sdk.os.max_file_path_length]u8 = undefined;
    const file_path = base_dir.getPath(&buffer, log_file_name) catch |err| {
        sdk.misc.error_context.append("Failed to construct log file path.", .{});
        return err;
    };
    file_logger.start(file_path) catch |err| {
        sdk.misc.error_context.append("Failed to start file logging with file path: {s}", .{file_path});
        return err;
    };
}

fn performMemorySearch(allocator: std.mem.Allocator, dir: *const sdk.misc.BaseDir) dll.game.Memory {
    std.log.debug("Initializing game memory...", .{});
    const game_memory = dll.game.Memory.init(allocator, dir, &game_hooks.last_camera_manager_address);
    std.log.info("Game memory initialized.", .{});

    std.log.debug("Initializing game hooks...", .{});
    game_hooks.init(&game_memory.functions);
    std.log.info("Game hooks initialized.", .{});

    return game_memory;
}

fn sendEvent(event: *const Event) void {
    if (!listening_to_events.load(.seq_cst)) {
        return;
    }
    producer_mutex.lock();
    defer producer_mutex.unlock();
    pending_event_mutex.lock();
    defer pending_event_mutex.unlock();
    while (pending_event != null) {
        producer_condition.wait(&pending_event_mutex);
        if (!listening_to_events.load(.seq_cst)) {
            return;
        }
    }
    pending_event = event.*;
    consumer_condition.signal();
    while (pending_event != null) {
        producer_condition.wait(&pending_event_mutex);
        if (!listening_to_events.load(.seq_cst)) {
            return;
        }
    }
}

fn onPresent(
    window: w32.HWND,
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    swap_chain: *const w32.IDXGISwapChain,
) void {
    sendEvent(&.{ .present = .{
        .window = window,
        .device = device,
        .command_queue = command_queue,
        .swap_chain = swap_chain,
    } });
}

fn onTick() void {
    sendEvent(&.tick);
}

fn beforeResize(
    window: w32.HWND,
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    swap_chain: *const w32.IDXGISwapChain,
) void {
    sendEvent(&.{ .before_resize = .{
        .window = window,
        .device = device,
        .command_queue = command_queue,
        .swap_chain = swap_chain,
    } });
}

fn afterResize(
    window: w32.HWND,
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    swap_chain: *const w32.IDXGISwapChain,
) void {
    sendEvent(&.{ .after_resize = .{
        .window = window,
        .device = device,
        .command_queue = command_queue,
        .swap_chain = swap_chain,
    } });
}

fn windowProcedure(
    window: w32.HWND,
    u_msg: u32,
    w_param: w32.WPARAM,
    l_param: w32.LPARAM,
) callconv(.winapi) w32.LRESULT {
    var window_procedure: ?sdk.os.WindowProcedure = null;
    var result: ?w32.LRESULT = null;
    sendEvent(&.{ .window_procedure = .{
        .window = window,
        .u_msg = u_msg,
        .w_param = w_param,
        .l_param = l_param,
        .out_window_procedure = &window_procedure,
        .out_result = &result,
    } });
    if (result) |r| {
        return r;
    }
    if (window_procedure) |procedure| {
        return w32.CallWindowProcW(procedure.original, window, u_msg, w_param, l_param);
    }
    return 0;
}
