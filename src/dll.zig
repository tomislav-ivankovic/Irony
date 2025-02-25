const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("misc/root.zig");
const log = @import("log/root.zig");
const os = @import("os/root.zig");

pub const module_name = "irony.dll";

pub const log_file_name = "irony.log";
// TODO start and stop fileLogger
pub const file_logger = log.FileLogger(.{});
pub const std_options = .{
    .log_level = .debug,
    .logFn = file_logger.logFn,
};

pub fn DllMain(
    module_handle: w32.HINSTANCE,
    forward_reason: u32,
    reserved: *anyopaque,
) callconv(std.os.windows.WINAPI) w32.BOOL {
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

    std.log.info("Initialization completed.", .{});
}

fn deinit() void {
    std.log.info("Running de-initialization...", .{});

    std.log.info("Stopping file logging...", .{});
    file_logger.stop();

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
