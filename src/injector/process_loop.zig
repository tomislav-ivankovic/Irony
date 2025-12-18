const std = @import("std");
const sdk = @import("../sdk/root.zig");

pub fn runProcessLoop(
    comptime process_names: []const []const u8,
    access_rights: sdk.os.Process.AccessRights,
    interval_ns: u64,
    context: anytype,
    onProcessOpen: *const fn (context: @TypeOf(context), index: usize, process: *const sdk.os.Process) bool,
    onProcessClose: *const fn (context: @TypeOf(context), index: usize) void,
) void {
    var open_processes = [1]?sdk.os.Process{null} ** process_names.len;
    while (true) {
        runLoopLogic(&open_processes, process_names, access_rights, context, onProcessOpen, onProcessClose);
        std.Thread.sleep(interval_ns);
    }
}

fn runLoopLogic(
    open_processes: []?sdk.os.Process,
    process_names: []const []const u8,
    access_rights: sdk.os.Process.AccessRights,
    context: anytype,
    onProcessOpen: *const fn (context: @TypeOf(context), index: usize, process: *const sdk.os.Process) bool,
    onProcessClose: *const fn (context: @TypeOf(context), index: usize) void,
) void {
    for (open_processes, process_names, 0..) |*open_process, process_name, index| {
        runProcessLogic(index, open_process, process_name, access_rights, context, onProcessOpen, onProcessClose);
    }
}

fn runProcessLogic(
    index: usize,
    open_process: *?sdk.os.Process,
    process_name: []const u8,
    access_rights: sdk.os.Process.AccessRights,
    context: anytype,
    onProcessOpen: *const fn (context: @TypeOf(context), index: usize, process: *const sdk.os.Process) bool,
    onProcessClose: *const fn (context: @TypeOf(context), index: usize) void,
) void {
    if (open_process.*) |process| {
        std.log.debug("Checking if the process (PID = {f}) is still running...", .{process.id});
        const still_running = process.isStillRunning() catch |err| c: {
            sdk.misc.error_context.append("Failed to figure out if process (PID={f}) is still running.", .{process.id});
            sdk.misc.error_context.logError(err);
            break :c false;
        };
        if (still_running) {
            std.log.debug("Process still running.", .{});
            return;
        }
        std.log.info("Process (PID = {f}) stopped running.", .{process.id});

        onProcessClose(context, index);

        std.log.info("Closing process (PID = {f})...", .{process.id});
        if (process.close()) {
            std.log.info("Process closed successfully.", .{});
        } else |err| {
            sdk.misc.error_context.append("Failed close process with PID: {f}", .{process.id});
            sdk.misc.error_context.logError(err);
        }
        open_process.* = null;
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
        std.log.info("Process ID found: {f}", .{process_id});

        std.log.info("Opening process (PID = {f})...", .{process_id});
        const process = sdk.os.Process.open(process_id, access_rights) catch |err| {
            sdk.misc.error_context.append("Failed to open process with PID: {f}", .{process_id});
            sdk.misc.error_context.logError(err);
            return;
        };
        std.log.info("Process opened successfully.", .{});

        const success = onProcessOpen(context, index, &process);
        if (success) {
            open_process.* = process;
        } else {
            std.log.info("Closing process (PID = {f})...", .{process.id});
            if (process.close()) {
                std.log.info("Process closed successfully.", .{});
            } else |err| {
                sdk.misc.error_context.append("Failed close process with PID: {f}", .{process.id});
                sdk.misc.error_context.logError(err);
            }
        }
    }
}

const testing = std.testing;
const w32 = @import("win32").everything;
const w = std.unicode.utf8ToUtf16LeStringLiteral;

test "should do nothing when process no process is found" {
    const OnProcessOpen = struct {
        var times_called: usize = 0;
        fn call(context: void, index: usize, process: *const sdk.os.Process) bool {
            times_called += 1;
            _ = context;
            _ = index;
            _ = process;
            return true;
        }
    };
    const OnProcessClose = struct {
        var times_called: usize = 0;
        fn call(context: void, index: usize) void {
            times_called += 1;
            _ = context;
            _ = index;
        }
    };

    var open_processes = [2]?sdk.os.Process{ null, null };
    runLoopLogic(
        &open_processes,
        &.{ "not_found_1.exe", "not_found_2.exe" },
        .{ .QUERY_INFORMATION = 1 },
        {},
        OnProcessOpen.call,
        OnProcessClose.call,
    );

    try testing.expectEqual(.{ null, null }, open_processes);
    try testing.expectEqual(0, OnProcessOpen.times_called);
    try testing.expectEqual(0, OnProcessClose.times_called);
}

test "should open process when process exists and onProcessOpen returns true" {
    var wait_process = std.process.Child.init(&.{"./test_assets/wait.exe"}, testing.allocator);
    try wait_process.spawn();
    defer _ = wait_process.kill() catch @panic("Failed to kill the wait process.");
    const pid = w32.GetProcessId(wait_process.id);

    const OnProcessOpen = struct {
        var times_called: usize = 0;
        var last_context: ?i32 = null;
        var last_index: ?usize = null;
        var process_id: ?sdk.os.ProcessId = null;
        fn call(context: i32, index: usize, process: *const sdk.os.Process) bool {
            times_called += 1;
            last_context = context;
            last_index = index;
            process_id = process.id;
            return true;
        }
    };
    const OnProcessClose = struct {
        var times_called: usize = 0;
        var last_context: ?i32 = null;
        var last_index: ?usize = null;
        fn call(context: i32, index: usize) void {
            times_called += 1;
            last_context = context;
            last_index = index;
        }
    };

    var open_processes = [2]?sdk.os.Process{ null, null };
    for (0..3) |_| {
        runLoopLogic(
            &open_processes,
            &.{ "not_found.exe", "wait.exe" },
            .{ .QUERY_INFORMATION = 1 },
            @as(i32, 123),
            OnProcessOpen.call,
            OnProcessClose.call,
        );
    }
    defer open_processes[1].?.close() catch @panic("Failed to close process.");

    try testing.expectEqual(null, open_processes[0]);
    try testing.expect(open_processes[1] != null);
    try testing.expectEqual(pid, open_processes[1].?.id.raw);
    try testing.expectEqual(1, OnProcessOpen.times_called);
    try testing.expectEqual(123, OnProcessOpen.last_context);
    try testing.expectEqual(1, OnProcessOpen.last_index);
    try testing.expectEqual(pid, OnProcessOpen.process_id.?.raw);
    try testing.expectEqual(0, OnProcessClose.times_called);
}

test "should open and close process when process exists and onProcessOpen returns false" {
    var wait_process = std.process.Child.init(&.{"./test_assets/wait.exe"}, testing.allocator);
    try wait_process.spawn();
    defer _ = wait_process.kill() catch @panic("Failed to kill the wait process.");
    const pid = w32.GetProcessId(wait_process.id);

    const OnProcessOpen = struct {
        var times_called: usize = 0;
        var last_context: ?i32 = null;
        var last_index: ?usize = null;
        var process_id: ?sdk.os.ProcessId = null;
        fn call(context: i32, index: usize, process: *const sdk.os.Process) bool {
            times_called += 1;
            last_context = context;
            last_index = index;
            process_id = process.id;
            return false;
        }
    };
    const OnProcessClose = struct {
        var times_called: usize = 0;
        var last_context: ?i32 = null;
        var last_index: ?usize = null;
        fn call(context: i32, index: usize) void {
            times_called += 1;
            last_context = context;
            last_index = index;
        }
    };

    var open_processes = [2]?sdk.os.Process{ null, null };
    runLoopLogic(
        &open_processes,
        &.{ "wait.exe", "not_found.exe" },
        .{ .QUERY_INFORMATION = 1 },
        @as(i32, 123),
        OnProcessOpen.call,
        OnProcessClose.call,
    );

    try testing.expectEqual(null, open_processes[0]);
    try testing.expectEqual(null, open_processes[1]);
    try testing.expectEqual(1, OnProcessOpen.times_called);
    try testing.expectEqual(123, OnProcessOpen.last_context);
    try testing.expectEqual(0, OnProcessOpen.last_index);
    try testing.expectEqual(pid, OnProcessOpen.process_id.?.raw);
    try testing.expectEqual(0, OnProcessClose.times_called);
}

test "should close process when process stops running" {
    var wait_process = std.process.Child.init(&.{"./test_assets/wait.exe"}, testing.allocator);
    try wait_process.spawn();
    const pid = w32.GetProcessId(wait_process.id);

    const OnProcessOpen = struct {
        var times_called: usize = 0;
        var last_context: ?i32 = null;
        var last_index: ?usize = null;
        var process_id: ?sdk.os.ProcessId = null;
        fn call(context: i32, index: usize, process: *const sdk.os.Process) bool {
            times_called += 1;
            last_context = context;
            last_index = index;
            process_id = process.id;
            return true;
        }
    };
    const OnProcessClose = struct {
        var times_called: usize = 0;
        var last_context: ?i32 = null;
        var last_index: ?usize = null;
        fn call(context: i32, index: usize) void {
            times_called += 1;
            last_context = context;
            last_index = index;
        }
    };

    var open_processes = [2]?sdk.os.Process{ null, null };
    for (0..3) |_| {
        runLoopLogic(
            &open_processes,
            &.{ "not_found.exe", "wait.exe" },
            .{ .QUERY_INFORMATION = 1 },
            @as(i32, 123),
            OnProcessOpen.call,
            OnProcessClose.call,
        );
    }
    _ = try wait_process.kill();
    for (0..3) |_| {
        runLoopLogic(
            &open_processes,
            &.{ "not_found.exe", "wait.exe" },
            .{ .QUERY_INFORMATION = 1 },
            @as(i32, 123),
            OnProcessOpen.call,
            OnProcessClose.call,
        );
    }

    try testing.expectEqual(null, open_processes[0]);
    try testing.expectEqual(null, open_processes[1]);
    try testing.expectEqual(1, OnProcessOpen.times_called);
    try testing.expectEqual(123, OnProcessOpen.last_context);
    try testing.expectEqual(1, OnProcessOpen.last_index);
    try testing.expectEqual(pid, OnProcessOpen.process_id.?.raw);
    try testing.expectEqual(1, OnProcessClose.times_called);
    try testing.expectEqual(123, OnProcessClose.last_context);
    try testing.expectEqual(1, OnProcessClose.last_index);
}
