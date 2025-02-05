const std = @import("std");
const misc = @import("../misc/root.zig");
const os = @import("../os/root.zig");

pub fn runProcessLoop(
    process_name: []const u8,
    interval_ns: u64,
    onProcessOpen: *const fn (process: *const os.Process) void,
    onProcessClose: *const fn (process: *const os.Process) void,
) void {
    std.log.info("Process loop started.", .{});
    var opened_process: ?os.Process = null;
    while (true) {
        runLoopLogic(&opened_process, process_name, onProcessOpen, onProcessClose);
        std.time.sleep(interval_ns);
    }
}

fn runLoopLogic(
    opened_process: *?os.Process,
    process_name: []const u8,
    onProcessOpen: *const fn (process: *const os.Process) void,
    onProcessClose: *const fn (process: *const os.Process) void,
) void {
    if (opened_process.*) |process| {
        const still_running = process.isStillRunning() catch |err| c: {
            misc.errorContext().appendFmt(err, "Failed to figure out if process (PID={}) is still running.", .{process.id.raw});
            misc.errorContext().logError();
            break :c false;
        };
        if (still_running) {
            return;
        }
        onProcessClose(&process);
        process.close() catch |err| {
            misc.errorContext().appendFmt(err, "Failed close process with PID: {}", .{process.id.raw});
            misc.errorContext().logError();
        };
        opened_process.* = null;
    } else {
        std.log.info("Searching for process ID of \"{s}\"...", .{process_name});
        const process_id = os.ProcessId.findByFileName(process_name) catch |err| switch (err) {
            error.NotFound => {
                std.log.info("Process not found.", .{});
                return;
            },
            else => {
                misc.errorContext().appendFmt(err, "Failed to find process: {s}", .{process_name});
                misc.errorContext().logError();
                return;
            },
        };
        std.log.info("Process ID found: {}", .{process_id.raw});
        std.log.info("Opening process with PID {}...", .{process_id.raw});
        const process = os.Process.open(process_id, .{
            .CREATE_THREAD = 1,
            .VM_OPERATION = 1,
            .VM_READ = 1,
            .VM_WRITE = 1,
            .QUERY_INFORMATION = 1,
            .QUERY_LIMITED_INFORMATION = 1,
            .SYNCHRONIZE = 1,
        }) catch |err| {
            misc.errorContext().appendFmt(err, "Failed to find process with PID: {}", .{process_id.raw});
            misc.errorContext().logError();
            return;
        };
        std.log.info("Process opened successfully.", .{});
        onProcessOpen(&process);
        opened_process.* = process;
    }
}
