const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const os = @import("root.zig");
const misc = @import("../misc/root.zig");

pub const WindowProcedureCallbackFn = fn (
    window: w32.HWND,
    u_msg: u32,
    w_param: w32.WPARAM,
    l_param: w32.LPARAM,
) ?w32.LRESULT;

pub fn WindowProcedure(callback: *const WindowProcedureCallbackFn) type {
    return struct {
        var window: ?w32.HWND = null;
        var original = std.atomic.Value(usize).init(0);
        var active_calls = std.atomic.Value(u32).init(0);
        var test_allocation: if (builtin.is_test) ?*u8 else void = if (builtin.is_test) null else {};

        pub fn init(target_window: w32.HWND) !void {
            if (window != null) {
                misc.error_context.new("Window procedure is already initialized.", .{});
                return error.AlreadyInitialized;
            }
            const current = getWindowProcedure(target_window) catch |err| {
                misc.error_context.append("Failed to get the current window procedure.", .{});
                return err;
            };
            original.store(current, .seq_cst);
            const replaced = setWindowProcedure(target_window, @intFromPtr(&windowProcedure)) catch |err| {
                misc.error_context.append("Failed to set the window procedure.", .{});
                return err;
            };
            original.store(replaced, .seq_cst);
            window = target_window;
            if (builtin.is_test) {
                test_allocation = try std.testing.allocator.create(u8);
            }
        }

        pub fn deinit(io: std.Io) !void {
            const target_window = window orelse return;
            const current = getWindowProcedure(target_window) catch |err| {
                misc.error_context.append("Failed to get the current window procedure.", .{});
                return err;
            };
            if (current != @intFromPtr(&windowProcedure)) {
                misc.error_context.new("The window procedure was replaced by someone else.", .{});
                return error.ProcedureReplaced;
            }
            _ = setWindowProcedure(target_window, original.load(.seq_cst)) catch |err| {
                misc.error_context.append("Failed to restore the original window procedure.", .{});
                return err;
            };
            window = null;
            while (active_calls.load(.seq_cst) > 0) {
                io.sleep(.fromMilliseconds(10), .awake) catch |err| {
                    misc.error_context.new("Failed to sleep for 10 ms while waiting on window procedure.", .{});
                    misc.error_context.logError(err);
                };
            }
            if (builtin.is_test) {
                if (test_allocation) |allocation| {
                    std.testing.allocator.destroy(allocation);
                    test_allocation = null;
                }
            }
        }

        fn windowProcedure(
            target_window: w32.HWND,
            u_msg: u32,
            w_param: w32.WPARAM,
            l_param: w32.LPARAM,
        ) callconv(.winapi) w32.LRESULT {
            _ = active_calls.fetchAdd(1, .seq_cst);
            defer _ = active_calls.fetchSub(1, .seq_cst);
            if (callback(target_window, u_msg, w_param, l_param)) |result| {
                return result;
            }
            const original_procedure: ?w32.WNDPROC = @ptrFromInt(original.load(.seq_cst));
            return w32.CallWindowProcW(original_procedure, target_window, u_msg, w_param, l_param);
        }
    };
}

fn getWindowProcedure(window: w32.HWND) !usize {
    w32.SetLastError(.NO_ERROR);
    const address = w32.GetWindowLongPtrW(window, .P_WNDPROC);
    if (address == 0) {
        const os_error = os.Error.getLast();
        if (os_error.error_code != .NO_ERROR) {
            misc.error_context.new("{f}", .{os_error});
            misc.error_context.append("GetWindowLongPtrW returned 0.", .{});
            return error.OsError;
        }
    }
    return @bitCast(address);
}

fn setWindowProcedure(window: w32.HWND, address: usize) !usize {
    w32.SetLastError(.NO_ERROR);
    const replaced = w32.SetWindowLongPtrW(window, .P_WNDPROC, @bitCast(address));
    if (replaced == 0) {
        const os_error = os.Error.getLast();
        if (os_error.error_code != .NO_ERROR) {
            misc.error_context.new("{f}", .{os_error});
            misc.error_context.append("SetWindowLongPtrW returned 0.", .{});
            return error.OsError;
        }
    }
    return @bitCast(replaced);
}

const testing = std.testing;
const w = std.unicode.utf8ToUtf16LeStringLiteral;

fn TestWindow(comptime class_name: []const u8) type {
    return struct {
        var times_called: usize = 0;
        var last_u_msg: ?u32 = null;
        var last_w_param: ?w32.WPARAM = null;
        var last_l_param: ?w32.LPARAM = null;

        fn create() !w32.HWND {
            const module = try os.Module.getMain();
            const window_class = w32.WNDCLASSEXW{
                .cbSize = @sizeOf(w32.WNDCLASSEXW),
                .style = .{},
                .lpfnWndProc = procedure,
                .cbClsExtra = 0,
                .cbWndExtra = 0,
                .hInstance = module.handle,
                .hIcon = null,
                .hCursor = null,
                .hbrBackground = null,
                .lpszMenuName = null,
                .lpszClassName = w(class_name),
                .hIconSm = null,
            };
            if (w32.RegisterClassExW(&window_class) == 0) {
                return error.OsError;
            }
            errdefer _ = w32.UnregisterClassW(window_class.lpszClassName, window_class.hInstance);
            return w32.CreateWindowExW(
                .{},
                window_class.lpszClassName,
                w(class_name),
                w32.WS_OVERLAPPEDWINDOW,
                0,
                0,
                100,
                100,
                null,
                null,
                window_class.hInstance,
                null,
            ) orelse error.OsError;
        }

        fn destroy(window: w32.HWND) void {
            const module = os.Module.getMain() catch @panic("Failed to get main module.");
            _ = w32.DestroyWindow(window);
            _ = w32.UnregisterClassW(w(class_name), module.handle);
        }

        fn procedure(window: w32.HWND, u_msg: u32, w_param: w32.WPARAM, l_param: w32.LPARAM) callconv(.winapi) w32.LRESULT {
            if (u_msg < w32.WM_USER) {
                return w32.DefWindowProcW(window, u_msg, w_param, l_param);
            }
            times_called += 1;
            last_u_msg = u_msg;
            last_w_param = w_param;
            last_l_param = l_param;
            return 6;
        }
    };
}

test "should call callback instead of original when callback returns a value" {
    if (@import("config").skip_display) {
        return error.SkipZigTest;
    }
    const Window = TestWindow("WindowProcedureTestWindow1");
    const window = try Window.create();
    defer Window.destroy(window);

    const Callback = struct {
        var times_called: usize = 0;
        var last_window: ?w32.HWND = null;
        var last_u_msg: ?u32 = null;
        var last_w_param: ?w32.WPARAM = null;
        var last_l_param: ?w32.LPARAM = null;
        fn call(target_window: w32.HWND, u_msg: u32, w_param: w32.WPARAM, l_param: w32.LPARAM) ?w32.LRESULT {
            if (u_msg < w32.WM_USER) {
                return null;
            }
            times_called += 1;
            last_window = target_window;
            last_u_msg = u_msg;
            last_w_param = w_param;
            last_l_param = l_param;
            return 5;
        }
    };
    const procedure = WindowProcedure(Callback.call);
    try procedure.init(window);
    defer procedure.deinit(testing.io) catch @panic("Failed to de-initialize window procedure.");

    const return_value = w32.SendMessageW(window, w32.WM_USER + 2, 3, 4);

    try testing.expectEqual(1, Callback.times_called);
    try testing.expectEqual(window, Callback.last_window);
    try testing.expectEqual(w32.WM_USER + 2, Callback.last_u_msg);
    try testing.expectEqual(3, Callback.last_w_param);
    try testing.expectEqual(4, Callback.last_l_param);
    try testing.expectEqual(0, Window.times_called);
    try testing.expectEqual(5, return_value);
}

test "should call original when callback returns null" {
    if (@import("config").skip_display) {
        return error.SkipZigTest;
    }
    const Window = TestWindow("WindowProcedureTestWindow2");
    const window = try Window.create();
    defer Window.destroy(window);

    const Callback = struct {
        var times_called: usize = 0;
        fn call(target_window: w32.HWND, u_msg: u32, w_param: w32.WPARAM, l_param: w32.LPARAM) ?w32.LRESULT {
            _ = target_window;
            _ = w_param;
            _ = l_param;
            if (u_msg >= w32.WM_USER) {
                times_called += 1;
            }
            return null;
        }
    };
    const procedure = WindowProcedure(Callback.call);
    try procedure.init(window);
    defer procedure.deinit(testing.io) catch @panic("Failed to de-initialize window procedure.");

    const return_value = w32.SendMessageW(window, w32.WM_USER + 2, 3, 4);

    try testing.expectEqual(1, Callback.times_called);
    try testing.expectEqual(1, Window.times_called);
    try testing.expectEqual(w32.WM_USER + 2, Window.last_u_msg);
    try testing.expectEqual(3, Window.last_w_param);
    try testing.expectEqual(4, Window.last_l_param);
    try testing.expectEqual(6, return_value);
}

test "should stop calling callback after de-initialization" {
    if (@import("config").skip_display) {
        return error.SkipZigTest;
    }
    const Window = TestWindow("WindowProcedureTestWindow3");
    const window = try Window.create();
    defer Window.destroy(window);

    const Callback = struct {
        var times_called: usize = 0;
        fn call(target_window: w32.HWND, u_msg: u32, w_param: w32.WPARAM, l_param: w32.LPARAM) ?w32.LRESULT {
            _ = target_window;
            _ = w_param;
            _ = l_param;
            if (u_msg < w32.WM_USER) {
                return null;
            }
            times_called += 1;
            return 5;
        }
    };
    const procedure = WindowProcedure(Callback.call);
    try procedure.init(window);
    try procedure.deinit(testing.io);

    const return_value = w32.SendMessageW(window, w32.WM_USER + 2, 3, 4);

    try testing.expectEqual(0, Callback.times_called);
    try testing.expectEqual(1, Window.times_called);
    try testing.expectEqual(6, return_value);
}

test "deinit should error and leave the procedure chain alone when someone replaced the procedure" {
    if (@import("config").skip_display) {
        return error.SkipZigTest;
    }
    const Window = TestWindow("WindowProcedureTestWindow4");
    const window = try Window.create();
    defer Window.destroy(window);

    const Callback = struct {
        fn call(target_window: w32.HWND, u_msg: u32, w_param: w32.WPARAM, l_param: w32.LPARAM) ?w32.LRESULT {
            _ = target_window;
            _ = u_msg;
            _ = w_param;
            _ = l_param;
            return null;
        }
    };
    const procedure = WindowProcedure(Callback.call);
    try procedure.init(window);

    const ours = try setWindowProcedure(window, @intFromPtr(&Window.procedure));
    try testing.expectError(error.ProcedureReplaced, procedure.deinit(testing.io));
    try testing.expectEqual(@intFromPtr(&Window.procedure), try getWindowProcedure(window));

    _ = try setWindowProcedure(window, ours);
    try procedure.deinit(testing.io);
}
