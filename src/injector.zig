const std = @import("std");
const build_info = @import("build_info");
const sdk = @import("sdk/root.zig");
const injector = @import("injector/root.zig");

const log_file_name = @tagName(build_info.name) ++ "_injector.log";
const console_logger = sdk.log.ConsoleLogger(.{});
const file_logger = sdk.log.FileLogger(.{});
const composite_logger = sdk.log.CompositeLogger(&.{ console_logger.logFn, file_logger.logFn });
pub const std_options = std.Options{
    .log_level = .info,
    .logFn = composite_logger.logFn,
};

const access_rights = sdk.os.Process.AccessRights{
    .CREATE_THREAD = 1,
    .VM_OPERATION = 1,
    .VM_READ = 1,
    .VM_WRITE = 1,
    .QUERY_INFORMATION = 1,
    .QUERY_LIMITED_INFORMATION = 1,
    .SYNCHRONIZE = 1,
};
const Target = struct {
    process_name: []const u8,
    module_name: []const u8,
};
const targets = [_]Target{
    .{
        .process_name = "Polaris-Win64-Shipping.exe",
        .module_name = @tagName(build_info.name) ++ "_t8.dll",
    },
    .{
        .process_name = "TekkenGame-Win64-Shipping.exe",
        .module_name = @tagName(build_info.name) ++ "_t7.dll",
    },
};
const interval_ns = 1 * std.time.ns_per_s;

pub const Mode = enum {
    normal,
    only_inject,
};
var mode = Mode.normal;

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

    std.log.info("{s} Injector version {s}", .{ build_info.display_name, build_info.version });

    std.log.debug("Checking for only inject mode...", .{});
    mode = getGetMode() catch |err| {
        sdk.misc.error_context.append("Failed to get the injector mode.", .{});
        sdk.misc.error_context.logError(err);
        return;
    };
    switch (mode) {
        .normal => std.log.info("Using normal mode.", .{}),
        .only_inject => std.log.info("Using only inject mode.", .{}),
    }

    std.log.debug("Setting console close handler...", .{});
    sdk.os.setConsoleCloseHandler(onConsoleClose) catch |err| {
        sdk.misc.error_context.append("Failed to set console close handler.", .{});
        sdk.misc.error_context.logError(err);
    };
    std.log.debug("Console close handler set.", .{});

    std.log.debug("Running process loop...", .{});
    const process_names = comptime block: {
        var names: [targets.len]([]const u8) = undefined;
        for (targets, 0..) |target, index| {
            names[index] = target.process_name;
        }
        break :block names;
    };
    injector.runProcessLoop(
        &process_names,
        access_rights,
        interval_ns,
        &base_dir,
        onProcessOpen,
        onProcessClose,
    );
}

fn getGetMode() !Mode {
    const allocator = std.heap.page_allocator;
    const args = std.process.argsAlloc(allocator) catch |err| {
        sdk.misc.error_context.new("Failed to get process command line arguments.", .{});
        return err;
    };
    defer std.process.argsFree(allocator, args);
    switch (args.len) {
        0, 1 => return .normal,
        2 => {
            const arg = args[1];
            if (std.mem.eql(u8, arg, "only_inject")) {
                return .only_inject;
            } else {
                sdk.misc.error_context.new(
                    "Expecting command line argument to be \"only_inject\" but got: \"{s}\"",
                    .{arg},
                );
                return error.UnexpectedArg;
            }
        },
        else => {
            sdk.misc.error_context.new("Expecting 0 or 1 command line arguments but got: {}", .{args.len - 1});
            return error.UnexpectedArgsLen;
        },
    }
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
    const file_path = base_dir.getPath(&buffer, log_file_name) catch |err| {
        sdk.misc.error_context.append("Failed to find log file path.", .{});
        return err;
    };
    file_logger.start(file_path) catch |err| {
        sdk.misc.error_context.append("Failed to start file logging with file path: {s}", .{file_path});
        return err;
    };
}

var injected_modules = [1]?injector.InjectedModule{null} ** targets.len;

pub fn onProcessOpen(base_dir: *const sdk.misc.BaseDir, index: usize, process: *const sdk.os.Process) bool {
    const module_name = targets[index].module_name;

    std.log.debug("Getting full path of \"{s}\"...", .{module_name});
    var buffer: [sdk.os.max_file_path_length]u8 = undefined;
    const full_path = base_dir.getPath(&buffer, module_name) catch |err| {
        sdk.misc.error_context.append("Failed to get full file path of: {s}", .{module_name});
        sdk.misc.error_context.logError(err);
        return false;
    };
    std.log.debug("Full path found: {s}", .{full_path});

    std.log.info("Injecting module \"{s}\"...", .{module_name});
    injected_modules[index] = injector.InjectedModule.inject(process.*, full_path) catch |err| {
        sdk.misc.error_context.append("Failed to inject module: {s}", .{full_path});
        sdk.misc.error_context.logError(err);
        return false;
    };
    std.log.info("Module injected successfully.", .{});

    if (mode == .only_inject) {
        std.log.info("Closing process (PID = {f})...", .{process.id});
        if (process.close()) {
            std.log.info("Process closed successfully.", .{});
        } else |err| {
            sdk.misc.error_context.append("Failed to close process with PID: {f}", .{process.id});
            sdk.misc.error_context.logError(err);
        }

        std.log.info("Stopping file logging...", .{});
        file_logger.stop();

        std.log.info("Application shutting down...", .{});
        std.process.exit(0);
    }

    return true;
}

pub fn onProcessClose(base_dir: *const sdk.misc.BaseDir, index: usize) void {
    _ = base_dir;
    const module_name = targets[index].module_name;
    const module = if (injected_modules[index]) |*m| m else {
        std.log.info("Nothing to eject.", .{});
        return;
    };
    std.log.info("Attempting to eject module \"{s}\"... ", .{module_name});
    if (module.eject()) {
        std.log.info("Module ejected successfully.", .{});
    } else |_| {
        std.log.info("Module ejection failed. But this is expected.", .{});
    }
    injected_modules[index] = null;
}

pub fn onConsoleClose() void {
    std.log.info("Detected close event.", .{});

    for (0..targets.len) |index| {
        const module_name = targets[index].module_name;
        const module = if (injected_modules[index]) |*m| m else continue;

        std.log.info("Ejecting module \"{s}\"... ", .{module_name});
        if (module.eject()) {
            std.log.info("Module ejected successfully.", .{});
        } else |err| {
            sdk.misc.error_context.append("Failed to eject module: {s}", .{module_name});
            sdk.misc.error_context.logError(err);
        }

        std.log.info("Closing process (PID = {f})...", .{module.module.process.id});
        if (module.module.process.close()) {
            std.log.info("Process closed successfully.", .{});
        } else |err| {
            sdk.misc.error_context.append("Failed to close process with PID: {f}", .{module.module.process.id});
            sdk.misc.error_context.logError(err);
        }

        injected_modules[index] = null;
    }

    std.log.info("Stopping file logging...", .{});
    file_logger.stop();

    std.log.info("Application shutting down...", .{});
}
