const std = @import("std");
const sdk = @import("../sdk/root.zig");

pub fn runProcessLoop(
    process_name: []const u8,
    access_rights: sdk.os.Process.AccessRights,
    interval_ns: u64,
    context: anytype,
    onProcessOpen: *const fn (context: @TypeOf(context), process: *const sdk.os.Process) bool,
    onProcessClose: *const fn (context: @TypeOf(context)) void,
) void {
    var opened_process: ?sdk.os.Process = null;
    while (true) {
        runLoopLogic(&opened_process, access_rights, process_name, context, onProcessOpen, onProcessClose);
        std.time.sleep(interval_ns);
    }
}

fn runLoopLogic(
    opened_process: *?sdk.os.Process,
    access_rights: sdk.os.Process.AccessRights,
    process_name: []const u8,
    context: anytype,
    onProcessOpen: *const fn (context: @TypeOf(context), process: *const sdk.os.Process) bool,
    onProcessClose: *const fn (context: @TypeOf(context)) void,
) void {
    if (opened_process.*) |process| {
        std.log.debug("Checking if the process (PID = {}) is still running...", .{process.id});
        const still_running = process.isStillRunning() catch |err| c: {
            sdk.misc.error_context.append("Failed to figure out if process (PID={}) is still running.", .{process.id});
            sdk.misc.error_context.logError(err);
            break :c false;
        };
        if (still_running) {
            std.log.debug("Process still running.", .{});
            return;
        }
        std.log.info("Process (PID = {}) stopped running.", .{process.id});

        onProcessClose(context);

        std.log.info("Closing process (PID = {})...", .{process.id});
        if (process.close()) {
            std.log.info("Process closed successfully.", .{});
        } else |err| {
            sdk.misc.error_context.append("Failed close process with PID: {}", .{process.id});
            sdk.misc.error_context.logError(err);
        }
        opened_process.* = null;
    } else {
        std.log.debug("Searching for process ID of \"{s}\"...", .{process_name});
        const process_id = sdk.os.ProcessId.findByFileName(process_name) catch |err| switch (err) {
            error.NotFound => {
                std.log.debug("Process not found.", .{});
                return;
            },
            else => {
                sdk.misc.error_context.append("Failed to find process: {s}", .{process_name});
                sdk.misc.error_context.logError(err);
                return;
            },
        };
        std.log.info("Process ID found: {}", .{process_id});

        std.log.info("Opening process (PID = {})...", .{process_id});
        const process = sdk.os.Process.open(process_id, access_rights) catch |err| {
            sdk.misc.error_context.append("Failed to open process with PID: {}", .{process_id});
            sdk.misc.error_context.logError(err);
            return;
        };
        std.log.info("Process opened successfully.", .{});

        const success = onProcessOpen(context, &process);
        if (success) {
            opened_process.* = process;
        } else {
            std.log.info("Closing process (PID = {})...", .{process.id});
            if (process.close()) {
                std.log.info("Process closed successfully.", .{});
            } else |err| {
                sdk.misc.error_context.append("Failed close process with PID: {}", .{process.id});
                sdk.misc.error_context.logError(err);
            }
        }
    }
}

const testing = std.testing;
const w32 = @import("win32").everything;
const w = std.unicode.utf8ToUtf16LeStringLiteral;

test "should do nothing when process is not found" {
    var opened_process: ?sdk.os.Process = null;
    const OnProcessOpen = struct {
        var times_called: usize = 0;
        fn call(context: void, process: *const sdk.os.Process) bool {
            times_called += 1;
            _ = context;
            _ = process;
            return true;
        }
    };
    const OnProcessClose = struct {
        var times_called: usize = 0;
        fn call(context: void) void {
            times_called += 1;
            _ = context;
        }
    };

    runLoopLogic(
        &opened_process,
        .{ .QUERY_INFORMATION = 1 },
        "not_found.exe",
        {},
        OnProcessOpen.call,
        OnProcessClose.call,
    );

    try testing.expectEqual(null, opened_process);
    try testing.expectEqual(0, OnProcessOpen.times_called);
    try testing.expectEqual(0, OnProcessClose.times_called);
}

test "should open process when process exists and onProcessOpen returns true" {
    var wait_process = std.process.Child.init(&.{"./test_assets/wait.exe"}, testing.allocator);
    try wait_process.spawn();
    defer _ = wait_process.kill() catch @panic("Failed to kill the wait process.");
    const pid = w32.GetProcessId(wait_process.id);

    var opened_process: ?sdk.os.Process = null;
    const OnProcessOpen = struct {
        var times_called: usize = 0;
        var process_id: ?sdk.os.ProcessId = null;
        var context_value: ?i32 = null;
        fn call(context: i32, process: *const sdk.os.Process) bool {
            times_called += 1;
            process_id = process.id;
            context_value = context;
            return true;
        }
    };
    const OnProcessClose = struct {
        var times_called: usize = 0;
        fn call(context: i32) void {
            times_called += 1;
            _ = context;
        }
    };

    for (0..3) |_| {
        runLoopLogic(
            &opened_process,
            .{ .QUERY_INFORMATION = 1 },
            "wait.exe",
            @as(i32, 123),
            OnProcessOpen.call,
            OnProcessClose.call,
        );
    }
    defer opened_process.?.close() catch @panic("Failed to close process.");

    try testing.expectEqual(pid, opened_process.?.id.raw);
    try testing.expectEqual(1, OnProcessOpen.times_called);
    try testing.expectEqual(pid, OnProcessOpen.process_id.?.raw);
    try testing.expectEqual(123, OnProcessOpen.context_value);
    try testing.expectEqual(0, OnProcessClose.times_called);
}

test "should open and close process when process exists and onProcessOpen returns false" {
    var wait_process = std.process.Child.init(&.{"./test_assets/wait.exe"}, testing.allocator);
    try wait_process.spawn();
    defer _ = wait_process.kill() catch @panic("Failed to kill the wait process.");
    const pid = w32.GetProcessId(wait_process.id);

    var opened_process: ?sdk.os.Process = null;
    const OnProcessOpen = struct {
        var times_called: usize = 0;
        var process_id: ?sdk.os.ProcessId = null;
        var context_value: ?i32 = null;
        fn call(context: i32, process: *const sdk.os.Process) bool {
            times_called += 1;
            process_id = process.id;
            context_value = context;
            return false;
        }
    };
    const OnProcessClose = struct {
        var times_called: usize = 0;
        fn call(context: i32) void {
            times_called += 1;
            _ = context;
        }
    };

    runLoopLogic(
        &opened_process,
        .{ .QUERY_INFORMATION = 1 },
        "wait.exe",
        @as(i32, 123),
        OnProcessOpen.call,
        OnProcessClose.call,
    );

    try testing.expectEqual(null, opened_process);
    try testing.expectEqual(1, OnProcessOpen.times_called);
    try testing.expectEqual(pid, OnProcessOpen.process_id.?.raw);
    try testing.expectEqual(123, OnProcessOpen.context_value);
    try testing.expectEqual(0, OnProcessClose.times_called);
}

test "should close process when process stops running" {
    var wait_process = std.process.Child.init(&.{"./test_assets/wait.exe"}, testing.allocator);
    try wait_process.spawn();
    const pid = w32.GetProcessId(wait_process.id);

    var opened_process: ?sdk.os.Process = null;
    const OnProcessOpen = struct {
        var times_called: usize = 0;
        var process_id: ?sdk.os.ProcessId = null;
        var context_value: ?i32 = null;
        fn call(context: i32, process: *const sdk.os.Process) bool {
            times_called += 1;
            process_id = process.id;
            context_value = context;
            return true;
        }
    };
    const OnProcessClose = struct {
        var times_called: usize = 0;
        var context_value: ?i32 = null;
        fn call(context: i32) void {
            times_called += 1;
            context_value = context;
        }
    };

    for (0..3) |_| {
        runLoopLogic(
            &opened_process,
            .{ .QUERY_INFORMATION = 1 },
            "wait.exe",
            @as(i32, 123),
            OnProcessOpen.call,
            OnProcessClose.call,
        );
    }
    _ = try wait_process.kill();
    for (0..3) |_| {
        runLoopLogic(
            &opened_process,
            .{ .QUERY_INFORMATION = 1 },
            "wait.exe",
            @as(i32, 123),
            OnProcessOpen.call,
            OnProcessClose.call,
        );
    }

    try testing.expectEqual(null, opened_process);
    try testing.expectEqual(1, OnProcessOpen.times_called);
    try testing.expectEqual(pid, OnProcessOpen.process_id.?.raw);
    try testing.expectEqual(123, OnProcessOpen.context_value);
    try testing.expectEqual(1, OnProcessClose.times_called);
    try testing.expectEqual(123, OnProcessClose.context_value);
}
