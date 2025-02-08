const std = @import("std");
const misc = @import("../misc/root.zig");
const os = @import("../os/root.zig");

pub fn runProcessLoop(
    process_name: []const u8,
    access_rights: os.Process.AccessRights,
    interval_ns: u64,
    onProcessOpen: *const fn (process: *const os.Process) void,
    onProcessClose: *const fn (process: *const os.Process) void,
) void {
    std.log.info("Process loop started.", .{});
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
    onProcessOpen: *const fn (process: *const os.Process) void,
    onProcessClose: *const fn (process: *const os.Process) void,
) void {
    if (opened_process.*) |process| {
        const still_running = process.isStillRunning() catch |err| c: {
            misc.errorContext().appendFmt(err, "Failed to figure out if process (PID={}) is still running.", .{process.id});
            misc.errorContext().logError();
            break :c false;
        };
        if (still_running) {
            return;
        }
        onProcessClose(&process);
        process.close() catch |err| {
            misc.errorContext().appendFmt(err, "Failed close process with PID: {}", .{process.id});
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
        std.log.info("Process ID found: {}", .{process_id});
        std.log.info("Opening process with PID {}...", .{process_id});
        const process = os.Process.open(process_id, access_rights) catch |err| {
            misc.errorContext().appendFmt(err, "Failed to find process with PID: {}", .{process_id});
            misc.errorContext().logError();
            return;
        };
        std.log.info("Process opened successfully.", .{});
        onProcessOpen(&process);
        opened_process.* = process;
    }
}

const testing = std.testing;
const w32 = @import("win32").everything;
const w = std.unicode.utf8ToUtf16LeStringLiteral;

test "should do nothing when process is not found" {
    var opened_process: ?os.Process = null;
    const OnProcessOpen = struct {
        var times_called: usize = 0;
        fn call(process: *const os.Process) void {
            times_called += 1;
            _ = process;
        }
    };
    const OnProcessClose = struct {
        var times_called: usize = 0;
        fn call(process: *const os.Process) void {
            times_called += 1;
            _ = process;
        }
    };
    for (0..3) |_| {
        runLoopLogic(&opened_process, .{ .QUERY_INFORMATION = 1 }, "not_found.exe", OnProcessOpen.call, OnProcessClose.call);
    }
    try testing.expectEqual(null, opened_process);
    try testing.expectEqual(0, OnProcessOpen.times_called);
    try testing.expectEqual(0, OnProcessClose.times_called);
}

test "should open process when process exists" {
    var opened_process: ?os.Process = null;
    const OnProcessOpen = struct {
        var times_called: usize = 0;
        var process_id: ?os.ProcessId = null;
        fn call(process: *const os.Process) void {
            times_called += 1;
            process_id = process.id;
        }
    };
    const OnProcessClose = struct {
        var times_called: usize = 0;
        fn call(process: *const os.Process) void {
            times_called += 1;
            _ = process;
        }
    };

    for (0..3) |_| {
        runLoopLogic(&opened_process, .{ .QUERY_INFORMATION = 1 }, "test.exe", OnProcessOpen.call, OnProcessClose.call);
    }
    defer opened_process.?.close() catch unreachable;

    try testing.expectEqual(os.ProcessId.getCurrent(), opened_process.?.id);
    try testing.expectEqual(1, OnProcessOpen.times_called);
    try testing.expectEqual(os.ProcessId.getCurrent(), OnProcessOpen.process_id);
    try testing.expectEqual(0, OnProcessClose.times_called);
}

// TODO figure out why spawning a process crashes the test
// test "should close process when process stops running" {
//     var process = std.process.Child.init(&.{ "echo", "test" }, testing.allocator);
//     _ = try process.spawnAndWait();
// }
