const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const os = @import("root.zig");
const misc = @import("../misc/root.zig");

pub const WindowProcedure = struct {
    window: w32.HWND,
    original: w32.WNDPROC,
    test_allocation: if (builtin.is_test) *u8 else void,

    const Self = @This();

    pub fn init(window: w32.HWND, function: w32.WNDPROC) !Self {
        w32.SetLastError(.NO_ERROR);
        const i_original = w32.SetWindowLongPtrW(window, .P_WNDPROC, @intCast(@intFromPtr(function)));
        if (i_original == 0) {
            const os_error = os.Error.getLast();
            if (os_error.error_code != .NO_ERROR) {
                misc.error_context.new("{}", .{os_error});
                misc.error_context.append("SetWindowLongPtrW returned 0.", .{});
                return error.OsError;
            }
        }
        const u_original: usize = @bitCast(i_original);
        const original: w32.WNDPROC = @ptrFromInt(u_original);

        const test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {};

        return .{
            .window = window,
            .original = original,
            .test_allocation = test_allocation,
        };
    }

    pub fn deinit(self: *const Self) !void {
        const u_original = @intFromPtr(self.original);
        const i_original: isize = @bitCast(u_original);
        const return_value = w32.SetWindowLongPtrW(self.window, .P_WNDPROC, i_original);
        if (return_value == 0) {
            const os_error = os.Error.getLast();
            if (os_error.error_code != .NO_ERROR) {
                misc.error_context.new("{}", .{os_error});
                misc.error_context.append("SetWindowLongPtrW returned 0.", .{});
                return error.OsError;
            }
        }

        if (builtin.is_test) {
            std.testing.allocator.destroy(self.test_allocation);
        }
    }
};

const testing = std.testing;
const w = std.unicode.utf8ToUtf16LeStringLiteral;

test "should capture window events" {
    const module = try os.Module.getMain();

    const window_class = w32.WNDCLASSEXW{
        .cbSize = @sizeOf(w32.WNDCLASSEXW),
        .style = .{
            .HREDRAW = 1,
            .VREDRAW = 1,
        },
        .lpfnWndProc = w32.DefWindowProcW,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = module.handle,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = w("TestingWindowClass"),
        .hIconSm = null,
    };
    const register_success = w32.RegisterClassExW(&window_class);
    if (register_success == 0) {
        return error.OsError;
    }
    defer _ = w32.UnregisterClassW(window_class.lpszClassName, window_class.hInstance);

    const window = w32.CreateWindowExW(
        .{},
        window_class.lpszClassName,
        w("TestingWindowClass"),
        w32.WS_OVERLAPPEDWINDOW,
        0,
        0,
        100,
        100,
        null,
        null,
        window_class.hInstance,
        null,
    ) orelse {
        return error.OsError;
    };
    defer _ = w32.DestroyWindow(window);

    const Function = struct {
        var times_called: usize = 0;
        var last_window_handle: ?w32.HWND = null;
        var last_u_msg: ?u32 = null;
        var last_w_param: ?w32.WPARAM = null;
        var last_l_param: ?w32.LPARAM = null;

        fn call(
            window_handle: w32.HWND,
            u_msg: u32,
            w_param: w32.WPARAM,
            l_param: w32.LPARAM,
        ) callconv(.winapi) w32.LRESULT {
            times_called += 1;
            last_window_handle = window_handle;
            last_u_msg = u_msg;
            last_w_param = w_param;
            last_l_param = l_param;
            return 5;
        }
    };

    const procedure = try WindowProcedure.init(window, Function.call);
    defer procedure.deinit() catch @panic("Failed to de-initialize window procedure.");

    const win_proc: usize = @bitCast(w32.GetWindowLongPtrW(window, .P_WNDPROC));
    const return_value = w32.CallWindowProcW(@ptrFromInt(win_proc), window, 2, 3, 4);

    try testing.expectEqual(1, Function.times_called);
    try testing.expectEqual(window, Function.last_window_handle);
    try testing.expectEqual(2, Function.last_u_msg);
    try testing.expectEqual(3, Function.last_w_param);
    try testing.expectEqual(4, Function.last_l_param);
    try testing.expectEqual(5, return_value);
}
