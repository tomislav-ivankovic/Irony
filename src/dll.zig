const std = @import("std");
const w32 = @import("win32").everything;
const misc = @import("misc/root.zig");
const log = @import("log/root.zig");
const os = @import("os/root.zig");
const dx12 = @import("dx12/root.zig");
const hooking = @import("hooking/root.zig");
const EventBuss = @import("event_buss.zig").EventBuss;

pub const module_name = "irony.dll";

pub const log_file_name = "irony.log";
pub const file_logger = log.FileLogger(.{});
pub const std_options = std.Options{
    .log_level = .debug,
    .logFn = file_logger.logFn,
};
const main_hooks = hooking.MainHooks(onHooksInit, onHooksDeinit, onHooksUpdate, beforeHooksResize, afterHooksResize);

var base_dir = misc.BaseDir.working_dir;
var module_handle_shared_value: ?os.SharedValue(w32.HINSTANCE) = null;
var window_procedure: ?os.WindowProcedure = null;
var event_buss: ?EventBuss = null;

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
                misc.errorContext().append(err, "Failed to create module handle shared value.");
                misc.errorContext().logError();
            }

            std.log.debug("Spawning the initialization thread...", .{});
            const thread = std.Thread.spawn(.{}, init, .{}) catch |err| {
                misc.errorContext().new(err, "Failed to spawn initialization thread.");
                misc.errorContext().logError();
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
                    misc.errorContext().append(err, "Failed to destroy module handle shared value.");
                    misc.errorContext().logError();
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
        misc.errorContext().appendFmt(err, "Failed to create shared value named: {s}", .{module_name});
        return err;
    };
    errdefer {
        shared_value.destroy() catch |err| {
            misc.errorContext().append(err, "Failed to destroy shared value.");
            misc.errorContext().logError();
        };
    }
    shared_value.write(module_handle) catch |err| {
        misc.errorContext().append(err, "Failed to write the module handle to shared value.");
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
        misc.errorContext().append(err, "Failed to start file logging.");
        misc.errorContext().logError();
    }

    std.log.debug("Initializing hooking...", .{});
    hooking.init() catch |err| {
        misc.errorContext().append(err, "Failed to initialize hooking.");
        misc.errorContext().logError();
        return;
    };
    std.log.info("Hooking initialized.", .{});

    std.log.debug("Initializing main hooks...", .{});
    main_hooks.init() catch |err| {
        misc.errorContext().append(err, "Failed to initialize main hooks.");
        misc.errorContext().logError();
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
        misc.errorContext().append(err, "Failed to de-initialize hooking.");
        misc.errorContext().logError();
    }

    std.log.info("Stopping file logging...", .{});
    file_logger.stop();
    std.log.info("File logging stopped.", .{});

    std.log.info("De-initialization completed.", .{});
}

fn findBaseDir() void {
    const dll_module = os.Module.getLocal(module_name) catch |err| {
        misc.errorContext().appendFmt(err, "Failed to get local module: {s}", .{module_name});
        misc.errorContext().append(err, "Failed find base directory.");
        misc.errorContext().logError();
        std.log.info("Defaulting base directory to working directory.", .{});
        base_dir = misc.BaseDir.working_dir;
        return;
    };
    base_dir = misc.BaseDir.fromModule(&dll_module) catch |err| {
        misc.errorContext().appendFmt(err, "Failed to find base directory from module: {s}", .{module_name});
        misc.errorContext().append(err, "Failed find base directory.");
        misc.errorContext().logError();
        std.log.info("Defaulting base directory to working directory.", .{});
        base_dir = misc.BaseDir.working_dir;
        return;
    };
}

fn startFileLogging() !void {
    var buffer: [os.max_file_path_length]u8 = undefined;
    const size = base_dir.getPath(&buffer, log_file_name) catch |err| {
        misc.errorContext().append(err, "Failed to find log file path.");
        return err;
    };
    const file_path = buffer[0..size];
    file_logger.start(file_path) catch |err| {
        misc.errorContext().appendFmt(err, "Failed to start file logging with file path: {s}", .{file_path});
        return err;
    };
}

fn onHooksInit(
    window: w32.HWND,
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    swap_chain: *const w32.IDXGISwapChain,
) void {
    std.log.info("Initializing event buss...", .{});
    event_buss = EventBuss.init(&base_dir, window, device, command_queue, swap_chain);
    std.log.info("Event buss initialized.", .{});

    std.log.debug("Initializing window procedure...", .{});
    if (os.WindowProcedure.init(window, windowProcedure)) |procedure| {
        std.log.info("Window procedure initialized.", .{});
        window_procedure = procedure;
    } else |err| {
        misc.errorContext().append(err, "Failed to initialize window procedure.");
        misc.errorContext().logError();
    }
}

fn onHooksDeinit(
    window: w32.HWND,
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    swap_chain: *const w32.IDXGISwapChain,
) void {
    std.log.debug("De-initializing window procedure...", .{});
    if (window_procedure) |*procedure| {
        if (procedure.deinit()) {
            window_procedure = null;
            std.log.info("Window procedure de-initialized.", .{});
        } else |err| {
            misc.errorContext().append(err, "Failed to de-initialize window procedure.");
            misc.errorContext().logError();
        }
    } else {
        std.log.info("Nothing to de-initialize.", .{});
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

fn onHooksUpdate(
    window: w32.HWND,
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    swap_chain: *const w32.IDXGISwapChain,
) void {
    if (event_buss) |*buss| {
        buss.update(&base_dir, window, device, command_queue, swap_chain);
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
