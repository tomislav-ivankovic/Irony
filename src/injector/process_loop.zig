const std = @import("std");
const misc = @import("../misc/root.zig");
const os = @import("../os/root.zig");

pub fn runProcessLoop(
    process_name: []const u8,
    access_rights: os.Process.AccessRights,
    interval_ns: u64,
    onProcessOpen: *const fn (process: *const os.Process) bool,
    onProcessClose: *const fn () void,
) void {
    var opened_process: ?os.Process = null;
    while (true) {
        runLoopLogic(&opened_process, access_rights, process_name, onProcessOpen, onProcessClose);
        std.time.sleep(interval_ns);
    }
}

fn runLoopLogic(
    opened_process: *?os.Process,
    access_rights: os.Process.AccessRights,
    process_name: []const u8,
    onProcessOpen: *const fn (process: *const os.Process) bool,
    onProcessClose: *const fn () void,
) void {
    if (opened_process.*) |process| {
        std.log.debug("Checking if the process (PID = {}) is still running...", .{process.id});
        const still_running = process.isStillRunning() catch |err| c: {
            misc.errorContext().appendFmt(
                err,
                "Failed to figure out if process (PID={}) is still running.",
                .{process.id},
            );
            misc.errorContext().logError();
            break :c false;
        };
        if (still_running) {
            std.log.debug("Still running...", .{});
            return;
        }
        std.log.info("Process (PID = {}) stopped running.", .{process.id});
        onProcessClose();
        std.log.info("Closing process (PID = {})...", .{process.id});
        if (process.close()) {
            std.log.info("Process closed successfully.", .{});
        } else |err| {
            misc.errorContext().appendFmt(err, "Failed close process with PID: {}", .{process.id});
            misc.errorContext().logError();
        }
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
        std.log.info("Process ID found: {}", .{process_id});
        std.log.info("Opening process (PID = {})...", .{process_id});
        const process = os.Process.open(process_id, access_rights) catch |err| {
            misc.errorContext().appendFmt(err, "Failed to open process with PID: {}", .{process_id});
            misc.errorContext().logError();
            return;
        };
        std.log.info("Process opened successfully.", .{});
        const success = onProcessOpen(&process);
        if (success) {
            opened_process.* = process;
        } else {
            std.log.info("Closing process (PID = {})...", .{process.id});
            if (process.close()) {
                std.log.info("Process closed successfully.", .{});
            } else |err| {
                misc.errorContext().appendFmt(err, "Failed close process with PID: {}", .{process.id});
                misc.errorContext().logError();
            }
        }
    }
}

const testing = std.testing;
const w32 = @import("win32").everything;
const w = std.unicode.utf8ToUtf16LeStringLiteral;

test "should do nothing when process is not found" {
    var opened_process: ?os.Process = null;
    const OnProcessOpen = struct {
        var times_called: usize = 0;
        fn call(process: *const os.Process) bool {
            times_called += 1;
            _ = process;
            return true;
        }
    };
    const OnProcessClose = struct {
        var times_called: usize = 0;
        fn call() void {
            times_called += 1;
        }
    };

    runLoopLogic(&opened_process, .{ .QUERY_INFORMATION = 1 }, "not_found.exe", OnProcessOpen.call, OnProcessClose.call);

    try testing.expectEqual(null, opened_process);
    try testing.expectEqual(0, OnProcessOpen.times_called);
    try testing.expectEqual(0, OnProcessClose.times_called);
}

test "should open process when process exists and onProcessOpen returns true" {
    var wait_process = std.process.Child.init(&.{"./test_assets/wait.exe"}, testing.allocator);
    try wait_process.spawn();
    defer _ = wait_process.kill() catch undefined;
    const pid = w32.GetProcessId(wait_process.id);

    var opened_process: ?os.Process = null;
    const OnProcessOpen = struct {
        var times_called: usize = 0;
        var process_id: ?os.ProcessId = null;
        fn call(process: *const os.Process) bool {
            times_called += 1;
            process_id = process.id;
            return true;
        }
    };
    const OnProcessClose = struct {
        var times_called: usize = 0;
        fn call() void {
            times_called += 1;
        }
    };

    for (0..3) |_| {
        runLoopLogic(&opened_process, .{ .QUERY_INFORMATION = 1 }, "wait.exe", OnProcessOpen.call, OnProcessClose.call);
    }
    defer opened_process.?.close() catch unreachable;

    try testing.expectEqual(pid, opened_process.?.id.raw);
    try testing.expectEqual(1, OnProcessOpen.times_called);
    try testing.expectEqual(pid, OnProcessOpen.process_id.?.raw);
    try testing.expectEqual(0, OnProcessClose.times_called);
}

test "should open and close process when process exists and onProcessOpen returns false" {
    var wait_process = std.process.Child.init(&.{"./test_assets/wait.exe"}, testing.allocator);
    try wait_process.spawn();
    defer _ = wait_process.kill() catch undefined;
    const pid = w32.GetProcessId(wait_process.id);

    var opened_process: ?os.Process = null;
    const OnProcessOpen = struct {
        var times_called: usize = 0;
        var process_id: ?os.ProcessId = null;
        fn call(process: *const os.Process) bool {
            times_called += 1;
            process_id = process.id;
            return false;
        }
    };
    const OnProcessClose = struct {
        var times_called: usize = 0;
        fn call() void {
            times_called += 1;
        }
    };

    runLoopLogic(&opened_process, .{ .QUERY_INFORMATION = 1 }, "wait.exe", OnProcessOpen.call, OnProcessClose.call);

    try testing.expectEqual(null, opened_process);
    try testing.expectEqual(1, OnProcessOpen.times_called);
    try testing.expectEqual(pid, OnProcessOpen.process_id.?.raw);
    try testing.expectEqual(0, OnProcessClose.times_called);
}

test "should close process when process stops running" {
    var wait_process = std.process.Child.init(&.{"./test_assets/wait.exe"}, testing.allocator);
    try wait_process.spawn();
    const pid = w32.GetProcessId(wait_process.id);

    var opened_process: ?os.Process = null;
    const OnProcessOpen = struct {
        var times_called: usize = 0;
        var process_id: ?os.ProcessId = null;
        fn call(process: *const os.Process) bool {
            times_called += 1;
            process_id = process.id;
            return true;
        }
    };
    const OnProcessClose = struct {
        var times_called: usize = 0;
        fn call() void {
            times_called += 1;
        }
    };

    for (0..3) |_| {
        runLoopLogic(&opened_process, .{ .QUERY_INFORMATION = 1 }, "wait.exe", OnProcessOpen.call, OnProcessClose.call);
    }
    _ = try wait_process.kill();
    for (0..3) |_| {
        runLoopLogic(&opened_process, .{ .QUERY_INFORMATION = 1 }, "wait.exe", OnProcessOpen.call, OnProcessClose.call);
    }

    try testing.expectEqual(null, opened_process);
    try testing.expectEqual(1, OnProcessOpen.times_called);
    try testing.expectEqual(pid, OnProcessOpen.process_id.?.raw);
    try testing.expectEqual(1, OnProcessClose.times_called);
}
