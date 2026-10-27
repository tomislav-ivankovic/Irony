const std = @import("std");
const w32 = @import("win32").everything;
const build_info = @import("build_info");
const sdk = @import("sdk/root.zig");
const dll = @import("dll/root.zig");

pub const module_name = @tagName(build_info.name) ++ "_" ++ @tagName(build_info.game) ++ ".dll";
pub const log_file_name = @tagName(build_info.name) ++ "_" ++ @tagName(build_info.game) ++ ".log";
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
const dx = switch (build_info.rendering_api) {
    .dx11 => sdk.dx11,
    .dx12 => sdk.dx12,
};

const MainAllocator = std.heap.DebugAllocator(.{ .enable_memory_limit = true });
const IoImplementation = sdk.io.WinIo;
const MemorySearchTask = sdk.misc.Task(dll.game.Memory(build_info.game));
const Event = union(enum) {
    present: dx.HostContext,
    tick: void,
    before_resize: dx.HostContext,
    after_resize: dx.HostContext,
    shut_down: void,
};
const ListeningToEvents = enum(u8) { none, all, only_present };

const dx_hooks = dx.Hooks(onPresent, beforeResize, afterResize);
const game_hooks = dll.game.Hooks(build_info.game, onTick);

var dll_module: sdk.os.Module = undefined;
var module_handle_shared_value: ?sdk.os.SharedValue(w32.HINSTANCE) = null;
var shutdown_routine_shared_value: ?sdk.os.SharedValue(w32.LPTHREAD_START_ROUTINE) = null;
var main_thread: ?std.Thread = null;
var main_thread_running = std.atomic.Value(bool).init(false);

var single_threaded_io = IoImplementation.init_single_threaded;
var pending_event_mutex = std.Io.Mutex.init;
var producer_mutex = std.Io.Mutex.init;
var consumer_condition = std.Io.Condition.init;
var producer_condition = std.Io.Condition.init;
var pending_event: ?Event = null;
var listening_to_events = std.atomic.Value(ListeningToEvents).init(.none);

var event_buss: ?dll.EventBuss = null;
var window_procedure: ?sdk.os.WindowProcedure = null;

pub fn DllMain(
    module_handle: std.os.windows.HINSTANCE,
    forward_reason: std.os.windows.DWORD,
    reserved: ?std.os.windows.LPVOID,
) std.os.windows.BOOL {
    switch (forward_reason) {
        w32.DLL_PROCESS_ATTACH => {
            std.log.info("DLL attached event detected.", .{});
            dll_module = sdk.os.Module{ .handle = module_handle, .process = .getCurrent() };
            initialize(module_handle) catch |err| {
                sdk.misc.error_context.append("Failed to initialize.", .{});
                sdk.misc.error_context.logError(err);
                return .FALSE;
            };
            std.log.info("DLL attached successfully.", .{});
            return .TRUE;
        },
        w32.DLL_PROCESS_DETACH => {
            std.log.info("DLL detach event detected.", .{});
            if (reserved == null) {
                deinitialize();
            } else {
                std.log.info("Skipping cleanup since the host process is terminating.", .{});
            }
            std.log.info("Detaching from the process now...", .{});
            return .TRUE;
        },
        else => return .FALSE,
    }
}

fn initialize(module_handle: w32.HINSTANCE) !void {
    const sio = single_threaded_io.io();
    buffer_logger.setIo(sio);
    sdk.ui.toasts.setIo(sio);

    std.log.debug("Creating module handle shared value...", .{});
    module_handle_shared_value = if (createModuleHandleSharedValue(module_handle)) |shared_value| block: {
        std.log.info("Module handle shared value created.", .{});
        break :block shared_value;
    } else |err| block: {
        sdk.misc.error_context.append("Failed to create module handle shared value.", .{});
        sdk.misc.error_context.logError(err);
        break :block null;
    };

    std.log.debug("Creating shutdown routine shared value...", .{});
    shutdown_routine_shared_value = if (createShutdownRoutineSharedValue()) |shared_value| block: {
        std.log.info("Shutdown routine shared value created.", .{});
        break :block shared_value;
    } else |err| block: {
        sdk.misc.error_context.append("Failed to create shutdown routine shared value.", .{});
        sdk.misc.error_context.logError(err);
        break :block null;
    };

    std.log.debug("Spawning the main thread...", .{});
    main_thread = std.Thread.spawn(.{}, main, .{}) catch |err| {
        sdk.misc.error_context.new("Failed to spawn main thread.", .{});
        return err;
    };
    main_thread_running.store(true, .seq_cst);
    std.log.debug("Main thread spawned.", .{});
}

fn deinitialize() void {
    const sio = single_threaded_io.io();
    std.log.debug("Shutting down main thread...", .{});
    if (main_thread_running.load(.seq_cst)) {
        if (main_thread) |*thread| {
            std.log.debug("Sending shutdown event...", .{});
            sendEvent(&.shut_down);
            std.log.info("Shutdown event sent.", .{});

            std.log.debug("Waiting for main thread to shut down...", .{});
            while (main_thread_running.load(.seq_cst)) {
                sio.sleep(.fromMilliseconds(100), .awake) catch |err| {
                    sdk.misc.error_context.new("Failed to sleep for 100 ms.", .{});
                    sdk.misc.error_context.logWarning(err);
                };
            }
            thread.detach();
            std.log.info("Main thread shut down.", .{});
        } else {
            std.log.debug("Nothing to shut down.", .{});
        }
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

    std.log.debug("Destroying shutdown routine shared value...", .{});
    if (module_handle_shared_value) |*shared_value| {
        if (shared_value.destroy()) {
            std.log.info("Shutdown routine shared value destroyed.", .{});
            module_handle_shared_value = null;
        } else |err| {
            sdk.misc.error_context.append("Failed to destroy shutdown routine shared value.", .{});
            sdk.misc.error_context.logError(err);
        }
    } else {
        std.log.debug("Nothing to destroy.", .{});
    }
}

pub fn selfShutDown() void {
    const handle = w32.CreateThread(null, 0, shutdownRoutine, null, .{}, null) orelse {
        sdk.misc.error_context.new("{f}", .{sdk.os.Error.getLast()});
        sdk.misc.error_context.append("Failed to spawn shut down routine thread.", .{});
        sdk.misc.error_context.append("Failed to self shut down.", .{});
        sdk.misc.error_context.logError(error.OsError);
        return;
    };
    _ = w32.CloseHandle(handle);
}

fn shutdownRoutine(_: ?*anyopaque) callconv(.winapi) u32 {
    deinitialize();
    w32.FreeLibraryAndExitThread(dll_module.handle, 0);
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

    std.log.debug("Initializing main IO...", .{});
    var main_io = IoImplementation.init(allocator, .{});
    std.log.info("Main IO initialized.", .{});
    defer {
        std.log.debug("De-initializing main IO...", .{});
        main_io.deinit();
        std.log.info("Main IO de-initialized.", .{});
    }
    const sio = single_threaded_io.io();
    const io = main_io.io();

    buffer_logger.setIo(io);
    sdk.ui.toasts.setIo(io);
    defer {
        sdk.ui.toasts.setIo(sio);
        buffer_logger.setIo(sio);
    }

    std.log.debug("Starting file logging...", .{});
    if (startFileLogging(io, &base_dir)) {
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

    std.log.info("{s} version {s}", .{ build_info.display_name, build_info.version });

    std.log.debug("Initializing hooking...", .{});
    sdk.memory.hooking.init() catch |err| {
        sdk.misc.error_context.append("Failed to initialize hooking.", .{});
        sdk.misc.error_context.logError(err);
        return;
    };
    std.log.info("Hooking initialized.", .{});
    defer {
        std.log.debug("De-initializing hooking...", .{});
        if (sdk.memory.hooking.deinit()) {
            std.log.info("Hooking de-initialized.", .{});
        } else |err| {
            sdk.misc.error_context.append("Failed to de-initialize hooking.", .{});
            sdk.misc.error_context.logError(err);
        }
    }

    std.log.debug("Initializing DirectX hooks...", .{});
    const number_of_retries = 10;
    for (0..number_of_retries) |retry_number| {
        dx_hooks.init() catch |err_1| {
            if (retry_number < number_of_retries - 1) {
                io.sleep(.fromMilliseconds(100), .awake) catch |err_2| {
                    sdk.misc.error_context.new("Failed to sleep for 100 ms.", .{});
                    sdk.misc.error_context.logWarning(err_2);
                };
                continue;
            } else {
                sdk.misc.error_context.append("Failed to initialize DirectX hooks.", .{});
                sdk.misc.error_context.logError(err_1);
                return;
            }
        };
        break;
    }
    std.log.info("DirectX hooks initialized.", .{});
    defer {
        std.log.debug("De-initializing DirectX hooks...", .{});
        dx_hooks.deinit(io);
        std.log.info("DirectX hooks de-initialized.", .{});
    }

    std.log.debug("Spawning memory search task...", .{});
    var memory_search_task = if (MemorySearchTask.spawn(
        allocator,
        performMemorySearch,
        .{ allocator, io, &base_dir },
    )) |task| block: {
        std.log.info("Memory search task spawned.", .{});
        break :block task;
    } else |err| block: {
        sdk.misc.error_context.append("Failed to spawn memory search task. Searching in main thread...", .{});
        sdk.misc.error_context.logWarning(err);
        const result = performMemorySearch(allocator, io, &base_dir);
        break :block MemorySearchTask.createCompleted(result);
    };
    defer {
        std.log.debug("Joining memory search task...", .{});
        _ = memory_search_task.join();
        std.log.info("Memory search task joined.", .{});

        std.log.debug("De-initializing game hooks...", .{});
        game_hooks.deinit(io);
        std.log.info("Game hooks de-initialized.", .{});
    }

    const State = enum { starting_up, up, shutting_down };
    var state = State.starting_up;

    defer producer_condition.broadcast(sio);
    pending_event_mutex.lock(sio) catch |err| {
        sdk.misc.error_context.append("Failed to get lock for pending event.", .{});
        sdk.misc.error_context.logError(err);
        return;
    };
    defer pending_event_mutex.unlock(sio);
    listening_to_events.store(.all, .seq_cst);
    defer listening_to_events.store(.none, .seq_cst);

    while (true) {
        consumer_condition.wait(sio, &pending_event_mutex) catch continue;
        const event = pending_event orelse continue;
        defer {
            pending_event = null;
            producer_condition.signal(sio);
        }
        switch (event) {
            .present => |*host_context| switch (state) {
                .starting_up => {
                    std.log.info("Initializing event buss...", .{});
                    event_buss = .init(allocator, io, &base_dir, host_context);
                    std.log.info("Event buss initialized.", .{});

                    std.log.debug("Initializing window procedure...", .{});
                    if (sdk.os.WindowProcedure.init(host_context.window, windowProcedure)) |procedure| {
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
                        const memory_usage = main_allocator.total_requested_bytes;
                        buss.draw(io, &base_dir, host_context, game_memory, memory_usage);
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
                        buss.deinit(io, &base_dir, host_context);
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
                    buss.tick(io, &base_dir, game_memory, &game_hooks.input_override);
                }
            },
            .before_resize => |*host_context| {
                std.log.info("Detected before resize event.", .{});
                if (event_buss) |*buss| {
                    buss.beforeResize(&base_dir, host_context);
                }
            },
            .after_resize => |*host_context| {
                std.log.info("Detected after resize event.", .{});
                if (event_buss) |*buss| {
                    buss.afterResize(&base_dir, host_context);
                }
            },
            .shut_down => {
                listening_to_events.store(.only_present, .seq_cst);
                state = .shutting_down;
                producer_condition.broadcast(sio);
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

fn createShutdownRoutineSharedValue() !sdk.os.SharedValue(w32.LPTHREAD_START_ROUTINE) {
    const name = "irony-shutdown-routine";
    const shared_value = sdk.os.SharedValue(w32.LPTHREAD_START_ROUTINE).create(name) catch |err| {
        sdk.misc.error_context.append("Failed to create shared value named: {s}", .{name});
        return err;
    };
    errdefer {
        shared_value.destroy() catch |err| {
            sdk.misc.error_context.append("Failed to destroy shared value.", .{});
            sdk.misc.error_context.logError(err);
        };
    }
    shared_value.write(shutdownRoutine) catch |err| {
        sdk.misc.error_context.append("Failed to write the module handle to shared value.", .{});
        return err;
    };
    return shared_value;
}

fn startFileLogging(io: std.Io, base_dir: *const sdk.misc.BaseDir) !void {
    var buffer: [sdk.os.max_file_path_length]u8 = undefined;
    const file_path = base_dir.getPath(&buffer, log_file_name) catch |err| {
        sdk.misc.error_context.append("Failed to construct log file path.", .{});
        return err;
    };
    file_logger.start(io, file_path) catch |err| {
        sdk.misc.error_context.append("Failed to start file logging with file path: {s}", .{file_path});
        return err;
    };
}

fn performMemorySearch(allocator: std.mem.Allocator, io: std.Io, dir: *const sdk.misc.BaseDir) dll.game.Memory(build_info.game) {
    std.log.debug("Initializing game memory...", .{});
    const game_memory = dll.game.Memory(build_info.game).init(allocator, io, dir, game_hooks);
    std.log.info("Game memory initialized.", .{});

    std.log.debug("Initializing game hooks...", .{});
    game_hooks.init(&game_memory.functions);
    std.log.info("Game hooks initialized.", .{});

    return game_memory;
}

fn sendEvent(event: *const Event) void {
    if (!isListeningToEvent(event)) {
        return;
    }
    const sio = single_threaded_io.io();
    producer_mutex.lock(sio) catch return;
    defer producer_mutex.unlock(sio);
    if (!isListeningToEvent(event)) {
        return;
    }
    pending_event_mutex.lock(sio) catch return;
    defer pending_event_mutex.unlock(sio);
    if (!isListeningToEvent(event)) {
        return;
    }
    while (pending_event != null) {
        const timeout = std.Io.Timeout{ .duration = .{ .raw = .fromMilliseconds(10), .clock = .awake } };
        producer_condition.waitTimeout(sio, &pending_event_mutex, timeout) catch {};
        if (!isListeningToEvent(event)) {
            return;
        }
    }
    pending_event = event.*;
    consumer_condition.signal(sio);
    while (pending_event != null) {
        const timeout = std.Io.Timeout{ .duration = .{ .raw = .fromMilliseconds(10), .clock = .awake } };
        producer_condition.waitTimeout(sio, &pending_event_mutex, timeout) catch {};
        if (!isListeningToEvent(event)) {
            return;
        }
    }
}

fn isListeningToEvent(event: *const Event) bool {
    const listening_to = listening_to_events.load(.seq_cst);
    return switch (listening_to) {
        .all => true,
        .only_present => event.* == .present,
        .none => false,
    };
}

fn onPresent(context: dx.HostContext) void {
    sendEvent(&.{ .present = context });
}

fn onTick() void {
    sendEvent(&.tick);
}

fn beforeResize(context: dx.HostContext) void {
    sendEvent(&.{ .before_resize = context });
}

fn afterResize(context: dx.HostContext) void {
    sendEvent(&.{ .after_resize = context });
}

fn windowProcedure(
    window: w32.HWND,
    u_msg: u32,
    w_param: w32.WPARAM,
    l_param: w32.LPARAM,
) callconv(.winapi) w32.LRESULT {
    if (event_buss) |*buss| {
        const result = buss.processWindowMessage(window, u_msg, w_param, l_param);
        if (result) |r| {
            return r;
        }
    }
    return w32.CallWindowProcW(window_procedure.?.original, window, u_msg, w_param, l_param);
}
