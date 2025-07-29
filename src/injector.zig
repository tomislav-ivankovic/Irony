const std = @import("std");
const sdk = @import("sdk/root.zig");
const injector = @import("injector/root.zig");

const process_name = "Polaris-Win64-Shipping.exe";
const access_rights = sdk.os.Process.AccessRights{
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
const console_logger = sdk.log.ConsoleLogger(.{});
const file_logger = sdk.log.FileLogger(.{});
const composite_logger = sdk.log.CompositeLogger(&.{ console_logger.logFn, file_logger.logFn });
pub const std_options = std.Options{
    .log_level = .info,
    .logFn = composite_logger.logFn,
};

var only_inject_mode = false;

pub fn main() !void {
    std.log.info("Application started up.", .{});

    std.log.debug("Finding base directory...", .{});
    const base_dir = findBaseDir();
    std.log.info("Base directory set to: {s}", .{base_dir.get()});

    std.log.debug("Starting file logging...", .{});
    if (startFileLogging(&base_dir)) {
        std.log.info("File logging started.", .{});
    } else |err| {
        sdk.misc.error_context.append("Failed to start file logging.", .{});
        sdk.misc.error_context.logError(err);
    }

    std.log.debug("Checking for only inject mode...", .{});
    only_inject_mode = getOnlyInjectMode();
    if (only_inject_mode) {
        std.log.info("Only inject mode activated.", .{});
    } else {
        std.log.debug("Not using only inject mode.", .{});
    }

    std.log.debug("Setting console close handler...", .{});
    sdk.os.setConsoleCloseHandler(onConsoleClose) catch |err| {
        sdk.misc.error_context.append("Failed to set console close handler.", .{});
        sdk.misc.error_context.logError(err);
    };
    std.log.debug("Console close handler set.", .{});

    std.log.debug("Running process loop...", .{});
    injector.runProcessLoop(
        process_name,
        access_rights,
        interval_ns,
        &base_dir,
        onProcessOpen,
        onProcessClose,
    );
}

fn getOnlyInjectMode() bool {
    const allocator = std.heap.page_allocator;
    const args = std.process.argsAlloc(allocator) catch |err| {
        sdk.misc.error_context.new("Failed to get process command line arguments.", .{});
        sdk.misc.error_context.logError(err);
        return false;
    };
    defer allocator.free(args);
    return args.len >= 2;
}

fn findBaseDir() sdk.misc.BaseDir {
    const main_module = sdk.os.Module.getMain() catch |err| {
        sdk.misc.error_context.append("Failed to get process main module.", .{});
        sdk.misc.error_context.append("Failed find base directory.", .{});
        sdk.misc.error_context.logError(err);
        std.log.info("Defaulting base directory to working directory.", .{});
        return sdk.misc.BaseDir.working_dir;
    };
    return sdk.misc.BaseDir.fromModule(&main_module) catch |err| {
        sdk.misc.error_context.append("Failed to find base directory from main module.", .{});
        sdk.misc.error_context.append("Failed find base directory.", .{});
        sdk.misc.error_context.logError(err);
        std.log.info("Defaulting base directory to working directory.", .{});
        return sdk.misc.BaseDir.working_dir;
    };
}

fn startFileLogging(base_dir: *const sdk.misc.BaseDir) !void {
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

var injected_module: ?injector.InjectedModule = null;

pub fn onProcessOpen(base_dir: *const sdk.misc.BaseDir, process: *const sdk.os.Process) bool {
    std.log.debug("Getting full path of \"{s}\"...", .{module_name});
    var buffer: [sdk.os.max_file_path_length]u8 = undefined;
    const size = base_dir.getPath(&buffer, module_name) catch |err| {
        sdk.misc.error_context.append("Failed to get full file path of: {s}", .{module_name});
        sdk.misc.error_context.logError(err);
        return false;
    };
    const full_path = buffer[0..size];
    std.log.debug("Full path found: {s}", .{full_path});

    std.log.info("Injecting module \"{s}\"...", .{module_name});
    injected_module = injector.InjectedModule.inject(process.*, full_path) catch |err| {
        sdk.misc.error_context.append("Failed to inject module: {s}", .{full_path});
        sdk.misc.error_context.logError(err);
        return false;
    };
    std.log.info("Module injected successfully.", .{});

    if (only_inject_mode) {
        std.log.info("Closing process (PID = {})...", .{process.id});
        if (process.close()) {
            std.log.info("Process closed successfully.", .{});
        } else |err| {
            sdk.misc.error_context.append("Failed to close process with PID: {}", .{process.id});
            sdk.misc.error_context.logError(err);
        }

        std.log.info("Stopping file logging...", .{});
        file_logger.stop();

        std.log.info("Application shutting down...", .{});
        std.process.exit(0);
    }

    return true;
}

pub fn onProcessClose(base_dir: *const sdk.misc.BaseDir) void {
    _ = base_dir;
    const module = injected_module orelse {
        std.log.info("Nothing to eject.", .{});
        return;
    };
    std.log.info("Attempting to eject module \"{s}\"... ", .{module_name});
    if (module.eject()) {
        std.log.info("Module ejected successfully.", .{});
    } else |_| {
        std.log.info("Module ejection failed. But this is expected.", .{});
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
            sdk.misc.error_context.append("Failed to eject module: {s}", .{module_name});
            sdk.misc.error_context.logError(err);
        }

        std.log.info("Closing process (PID = {})...", .{module.module.process.id});
        if (module.module.process.close()) {
            std.log.info("Process closed successfully.", .{});
        } else |err| {
            sdk.misc.error_context.append("Failed to close process with PID: {}", .{module.module.process.id});
            sdk.misc.error_context.logError(err);
        }

        injected_module = null;
    } else {
        std.log.info("Nothing to eject.", .{});
    }

    std.log.info("Stopping file logging...", .{});
    file_logger.stop();

    std.log.info("Application shutting down...", .{});
}
