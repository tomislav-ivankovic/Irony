const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const os = @import("root.zig");
const memory = @import("../memory/root.zig");
const misc = @import("../misc/root.zig");

pub const RawInputHookCallbackFn = fn (
    h_raw_input: ?w32.HRAWINPUT,
    ui_command: w32.RAW_INPUT_DATA_COMMAND_FLAGS,
    p_data: ?*anyopaque,
    pcb_size: ?*u32,
    cb_size_header: u32,
    return_value: u32,
) u32;

pub fn RawInputHook(callback: *const RawInputHookCallbackFn) type {
    return struct {
        var hook: ?Hook = null;
        var active_hook_calls = std.atomic.Value(u8).init(0);

        const Hook = memory.Hook(@TypeOf(w32.GetRawInputData));

        pub fn init(getRawInputData: ?*const @TypeOf(w32.GetRawInputData)) !void {
            const target: *const @TypeOf(w32.GetRawInputData) = if (getRawInputData) |target| target else block: {
                const module = os.Module.getLocal("USER32.DLL") catch |err| {
                    misc.error_context.append("Failed to get USER32.DLL module.", .{});
                    return err;
                };
                const address = module.getProcedureAddress("GetRawInputData") catch |err| {
                    misc.error_context.append("Failed to find the address of GetRawInputData.", .{});
                    return err;
                };
                break :block @ptrFromInt(address);
            };
            hook = Hook.create(target, onGetRawInputData) catch |err| {
                misc.error_context.append("Failed to create GetRawInputData hook.", .{});
                return err;
            };
            errdefer {
                const saved = misc.error_context.save();
                defer misc.error_context.restore(&saved);
                if (hook.?.destroy()) {
                    hook = null;
                } else |err| {
                    misc.error_context.append("Failed to destroy GetRawInputData hook.", .{});
                    misc.error_context.logError(err);
                }
            }
            hook.?.enable() catch |err| {
                misc.error_context.append("Failed to enable GetRawInputData hook.", .{});
                return err;
            };
        }

        pub fn deinit(io: std.Io) void {
            if (hook) |*h| {
                h.disable() catch |err| switch (err) {
                    error.HookDisabled => {},
                    else => {
                        misc.error_context.append("Failed to disable GetRawInputData hook.", .{});
                        misc.error_context.logError(err);
                        return;
                    },
                };
            }
            while (active_hook_calls.load(.seq_cst) > 0) {
                io.sleep(.fromMilliseconds(10), .awake) catch |err| {
                    misc.error_context.new("Failed to sleep for 10 ms while waiting on raw input hook.", .{});
                    misc.error_context.logError(err);
                };
            }
            if (hook) |*h| {
                if (h.destroy()) {
                    hook = null;
                } else |err| {
                    misc.error_context.append("Failed to destroy GetRawInputData hook.", .{});
                    misc.error_context.logError(err);
                }
            }
        }

        fn onGetRawInputData(
            h_raw_input: ?w32.HRAWINPUT,
            ui_command: w32.RAW_INPUT_DATA_COMMAND_FLAGS,
            p_data: ?*anyopaque,
            pcb_size: ?*u32,
            cb_size_header: u32,
        ) callconv(.winapi) u32 {
            _ = active_hook_calls.fetchAdd(1, .seq_cst);
            defer _ = active_hook_calls.fetchSub(1, .seq_cst);
            const return_value = hook.?.original(h_raw_input, ui_command, p_data, pcb_size, cb_size_header);
            return callback(h_raw_input, ui_command, p_data, pcb_size, cb_size_header, return_value);
        }
    };
}

const testing = std.testing;

test "should find GetRawInputData function address when not provided" {
    const GetRawInputData = struct {
        extern "user32" var __imp_GetRawInputData: *const @TypeOf(w32.GetRawInputData);
    }.__imp_GetRawInputData;
    const Callback = struct {
        fn call(
            h_raw_input: ?w32.HRAWINPUT,
            ui_command: w32.RAW_INPUT_DATA_COMMAND_FLAGS,
            p_data: ?*anyopaque,
            pcb_size: ?*u32,
            cb_size_header: u32,
            return_value: u32,
        ) u32 {
            _ = h_raw_input;
            _ = ui_command;
            _ = p_data;
            _ = pcb_size;
            _ = cb_size_header;
            return return_value;
        }
    };
    const hook = RawInputHook(Callback.call);

    try memory.hooking.init();
    defer memory.hooking.deinit() catch @panic("Failed to de-initialize hooking.");
    try hook.init(null);
    defer hook.deinit(testing.io);

    try testing.expectEqual(GetRawInputData, hook.hook.?.target);
}

test "should call callback and original when target is called" {
    const GetRawInputData = struct {
        var times_called: usize = 0;
        var last_h_raw_input: ?w32.HRAWINPUT = null;
        var last_ui_command: ?w32.RAW_INPUT_DATA_COMMAND_FLAGS = null;
        var last_p_data: ?*anyopaque = null;
        var last_pcb_size: ?*u32 = null;
        var last_cb_size_header: ?u32 = null;
        var value_to_return: u32 = 0;
        fn call(
            h_raw_input: ?w32.HRAWINPUT,
            ui_command: w32.RAW_INPUT_DATA_COMMAND_FLAGS,
            p_data: ?*anyopaque,
            pcb_size: ?*u32,
            cb_size_header: u32,
        ) callconv(.winapi) u32 {
            times_called += 1;
            last_h_raw_input = h_raw_input;
            last_ui_command = ui_command;
            last_p_data = p_data;
            last_pcb_size = pcb_size;
            last_cb_size_header = cb_size_header;
            return value_to_return;
        }
    };
    const Callback = struct {
        var times_called: usize = 0;
        var last_h_raw_input: ?w32.HRAWINPUT = null;
        var last_ui_command: ?w32.RAW_INPUT_DATA_COMMAND_FLAGS = null;
        var last_p_data: ?*anyopaque = null;
        var last_pcb_size: ?*u32 = null;
        var last_cb_size_header: ?u32 = null;
        var last_return_value: ?u32 = null;
        var value_to_return: u32 = 0;
        fn call(
            h_raw_input: ?w32.HRAWINPUT,
            ui_command: w32.RAW_INPUT_DATA_COMMAND_FLAGS,
            p_data: ?*anyopaque,
            pcb_size: ?*u32,
            cb_size_header: u32,
            return_value: u32,
        ) u32 {
            times_called += 1;
            last_h_raw_input = h_raw_input;
            last_ui_command = ui_command;
            last_p_data = p_data;
            last_pcb_size = pcb_size;
            last_cb_size_header = cb_size_header;
            last_return_value = return_value;
            return value_to_return;
        }
    };
    const hook = RawInputHook(Callback.call);

    try memory.hooking.init();
    defer memory.hooking.deinit() catch @panic("Failed to de-initialize hooking.");
    try hook.init(GetRawInputData.call);
    defer hook.deinit(testing.io);

    try testing.expectEqual(0, GetRawInputData.times_called);
    try testing.expectEqual(0, Callback.times_called);

    var pcb_size: u32 = 0;
    GetRawInputData.value_to_return = 2;
    Callback.value_to_return = 3;
    const return_value = GetRawInputData.call(@ptrFromInt(16), .INPUT, @ptrFromInt(32), &pcb_size, 4);

    try testing.expectEqual(1, GetRawInputData.times_called);
    try testing.expectEqual(16, @intFromPtr(GetRawInputData.last_h_raw_input));
    try testing.expectEqual(.INPUT, GetRawInputData.last_ui_command);
    try testing.expectEqual(32, @intFromPtr(GetRawInputData.last_p_data));
    try testing.expectEqual(&pcb_size, GetRawInputData.last_pcb_size);
    try testing.expectEqual(4, GetRawInputData.last_cb_size_header);

    try testing.expectEqual(1, Callback.times_called);
    try testing.expectEqual(16, @intFromPtr(Callback.last_h_raw_input));
    try testing.expectEqual(.INPUT, Callback.last_ui_command);
    try testing.expectEqual(32, @intFromPtr(Callback.last_p_data));
    try testing.expectEqual(&pcb_size, Callback.last_pcb_size);
    try testing.expectEqual(4, Callback.last_cb_size_header);
    try testing.expectEqual(2, Callback.last_return_value);

    try testing.expectEqual(3, return_value);
}
