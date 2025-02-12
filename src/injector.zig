const std = @import("std");
const log = @import("log/root.zig");
const misc = @import("misc/root.zig");
const os = @import("os/root.zig");
const injector = @import("injector/root.zig");

pub const std_options = .{
    .log_level = .debug,
    .logFn = log.ConsoleLogger(.{}).logFn,
};

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

pub fn main() !void {
    std.log.debug("Setting console close handler...", .{});
    os.setConsoleCloseHandler(onConsoleClose) catch |err| {
        misc.errorContext().append(err, "Failed to set console close handler.");
        misc.errorContext().logError();
    };
    std.log.debug("Console close handler set.", .{});
    std.log.debug("Running process loop...", .{});
    injector.runProcessLoop(process_name, access_rights, interval_ns, onProcessOpen, onProcessClose);
}

var injected_module: ?injector.InjectedModule = null;

pub fn onProcessOpen(process: *const os.Process) bool {
    const relative_path = "./" ++ module_name;
    std.log.debug("Getting full path of \"{s}\"...", .{relative_path});
    var buffer: [os.max_file_path_length]u8 = undefined;
    const size = os.getFullPath(&buffer, relative_path) catch |err| {
        misc.errorContext().appendFmt(err, "Failed to get full file path of: {s}", .{relative_path});
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
}

pub fn onConsoleClose() void {
    std.log.info("Detected close event.", .{});
    if (injected_module == null) {
        std.log.info("Nothing to eject. Shutting down...", .{});
        return;
    }
    const module = injected_module orelse unreachable;
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
    std.log.info("Shutting down...", .{});
}
