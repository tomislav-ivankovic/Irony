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
const main_hooks = hooking.MainHooks(onFirstPresent, onNormalPresent, onLastPresent);

var window_procedure: ?os.WindowProcedure = null;
var event_buss: ?EventBuss = null;

pub fn DllMain(
    module_handle: w32.HINSTANCE,
    forward_reason: u32,
    reserved: *anyopaque,
) callconv(.winapi) w32.BOOL {
    _ = module_handle;
    _ = reserved;
    switch (forward_reason) {
        w32.DLL_PROCESS_ATTACH => {
            std.log.info("DLL attached event detected.", .{});
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
            std.log.info("Detaching from the process now...", .{});
            return 1;
        },
        else => return 0,
    }
}

fn init() void {
    std.log.info("Running initialization...", .{});

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

fn startFileLogging() !void {
    const main_module = os.Module.getLocal(module_name) catch |err| {
        misc.errorContext().appendFmt(err, "Failed to get local module: {s}", .{module_name});
        return err;
    };
    var buffer: [os.max_file_path_length]u8 = undefined;
    const size = os.getPathRelativeFromModule(&buffer, &main_module, log_file_name) catch |err| {
        misc.errorContext().append(err, "Failed to find log file path.");
        return err;
    };
    const file_path = buffer[0..size];
    file_logger.start(file_path) catch |err| {
        misc.errorContext().appendFmt(err, "Failed to start file logging with file path: {s}", .{file_path});
        return err;
    };
}

fn onFirstPresent(
    window: w32.HWND,
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    swap_chain: *const w32.IDXGISwapChain,
) void {
    std.log.info("Initializing event buss...", .{});
    event_buss = @as(EventBuss, undefined);
    event_buss.?.init(window, device, command_queue, swap_chain);
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

fn onNormalPresent(
    window: w32.HWND,
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    swap_chain: *const w32.IDXGISwapChain,
) void {
    if (event_buss) |*buss| {
        buss.update(window, device, command_queue, swap_chain);
    }
}

fn onLastPresent(
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
        buss.deinit(window, device, command_queue, swap_chain);
        event_buss = null;
        std.log.info("Event buss de-initialized.", .{});
    } else {
        std.log.info("Nothing to de-initialize.", .{});
    }
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
