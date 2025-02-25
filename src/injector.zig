const std = @import("std");
const log = @import("log/root.zig");
const misc = @import("misc/root.zig");
const os = @import("os/root.zig");
const injector = @import("injector/root.zig");

const process_name = "Polaris-Win64-Shipping.exe";
const access_rights = os.Process.AccessRights{
    .CREATE_THREAD = 1,
    .VM_OPERATION = 1,
    .VM_READ = 1,
    .VM_WRITE = 1,
    .QUERY_INFORMATION = 1,
    .QUERY_LIMITED_INFORMATION = 1,
    .SYNCHRONIZE = 1,
};
const module_name = "irony.dll";
const interval_ns = 1_000_000_000;

const log_file_name = "irony_injector.log";
const console_logger = log.ConsoleLogger(.{});
const file_logger = log.FileLogger(.{});
const composite_logger = log.CompositeLogger(&.{ console_logger.logFn, file_logger.logFn });
pub const std_options = .{
    .log_level = .info,
    .logFn = composite_logger.logFn,
};

pub fn main() !void {
    std.log.info("Application started up.", .{});
    std.log.debug("Starting file logging...", .{});
    if (startFileLogging()) {
        std.log.info("File logging started.", .{});
    } else |err| {
        misc.errorContext().append(err, "Failed to start file logging.");
        misc.errorContext().logError();
    }
    std.log.debug("Setting console close handler...", .{});
    os.setConsoleCloseHandler(onConsoleClose) catch |err| {
        misc.errorContext().append(err, "Failed to set console close handler.");
        misc.errorContext().logError();
    };
    std.log.debug("Console close handler set.", .{});
    std.log.debug("Running process loop...", .{});
    injector.runProcessLoop(process_name, access_rights, interval_ns, onProcessOpen, onProcessClose);
}

fn startFileLogging() !void {
    const main_module = os.Module.getMain() catch |err| {
        misc.errorContext().append(err, "Failed to get process main module.");
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

var injected_module: ?injector.InjectedModule = null;

pub fn onProcessOpen(process: *const os.Process) bool {
    const main_module = os.Module.getMain() catch |err| {
        misc.errorContext().append(err, "Failed to get process main module.");
        misc.errorContext().logError();
        return false;
    };
    std.log.debug("Getting full path of \"{s}\"...", .{module_name});
    var buffer: [os.max_file_path_length]u8 = undefined;
    const size = os.getPathRelativeFromModule(&buffer, &main_module, module_name) catch |err| {
        misc.errorContext().appendFmt(err, "Failed to get full file path of: {s}", .{module_name});
        misc.errorContext().logError();
        return false;
    };
    const full_path = buffer[0..size];
    std.log.debug("Full path found: {s}", .{full_path});
    std.log.info("Injecting module \"{s}\"...", .{module_name});
    injected_module = injector.InjectedModule.inject(process.*, full_path) catch |err| {
        misc.errorContext().appendFmt(err, "Failed to inject module: {s}", .{full_path});
        misc.errorContext().logError();
        return false;
    };
    std.log.info("Module injected successfully.", .{});
    return true;
}

pub fn onProcessClose() void {
    if (injected_module == null) {
        std.log.info("Nothing to eject.", .{});
        return;
    }
    const module = injected_module orelse unreachable;
    std.log.info("Attempting to eject module \"{s}\"... ", .{module_name});
    if (module.eject()) {
        std.log.info("Module ejected successfully.", .{});
    } else |_| {
        std.log.info("Module ejected failed. But this is expected.", .{});
    }
    injected_module = null;
}

pub fn onConsoleClose() void {
    std.log.info("Detected close event.", .{});
    if (injected_module) |module| {
        std.log.info("Ejecting module \"{s}\"... ", .{module_name});
        if (module.eject()) {
            std.log.info("Module ejected successfully.", .{});
        } else |err| {
            misc.errorContext().appendFmt(err, "Failed to eject module: {s}", .{module_name});
            misc.errorContext().logError();
        }
        std.log.info("Closing process (PID = {})...", .{module.module.process.id});
        if (module.module.process.close()) {
            std.log.info("Process closed successfully.", .{});
        } else |err| {
            misc.errorContext().appendFmt(err, "Failed to close process with PID: {}", .{module.module.process.id});
        }
        injected_module = null;
    } else {
        std.log.info("Nothing to eject.", .{});
    }
    std.log.info("Stopping file logging...", .{});
    file_logger.stop();
    std.log.info("Application shutting down...", .{});
}
