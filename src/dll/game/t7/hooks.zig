const std = @import("std");
const builtin = @import("builtin");
const sdk = @import("../../../sdk/root.zig");
const t7 = @import("root.zig");

pub fn Hooks(onTick: *const fn () void) type {
    return struct {
        var tick_hook: ?TickHook = null;
        var active_hook_calls = std.atomic.Value(u8).init(0);

        const TickHook = sdk.memory.Hook(t7.TickFunction);

        pub fn init(game_functions: *const t7.Memory.Functions) void {
            std.log.debug("Creating tick hook...", .{});
            if (game_functions.tick) |function| {
                if (TickHook.create(function, onTickInternal)) |hook| {
                    tick_hook = hook;
                    std.log.info("Tick hook created.", .{});
                } else |err| {
                    if (!builtin.is_test) {
                        sdk.misc.error_context.append("Failed to create tick hook.", .{});
                        sdk.misc.error_context.logError(err);
                    }
                }
            } else if (!builtin.is_test) {
                sdk.misc.error_context.new("Tick function not found.", .{});
                sdk.misc.error_context.append("Failed to create tick hook.", .{});
                sdk.misc.error_context.logError(error.NotFound);
            }

            if (tick_hook) |*hook| {
                std.log.debug("Enabling tick hook...", .{});
                if (hook.enable()) {
                    std.log.info("Tick hook enabled.", .{});
                } else |err| {
                    sdk.misc.error_context.append("Failed to enable tick hook.", .{});
                    sdk.misc.error_context.logError(err);
                }
            }
        }

        pub fn deinit() void {
            std.log.debug("Destroying tick hook...", .{});
            if (tick_hook) |*hook| {
                if (hook.destroy()) {
                    std.log.info("Tick hook destroyed.", .{});
                    tick_hook = null;
                } else |err| {
                    sdk.misc.error_context.append("Failed to destroy tick hook.", .{});
                    sdk.misc.error_context.logError(err);
                }
            } else {
                std.log.debug("Nothing to destroy.", .{});
            }

            while (active_hook_calls.load(.seq_cst) > 0) {
                std.Thread.sleep(10 * std.time.ns_per_ms);
            }
        }

        fn onTickInternal(game_mode_address: usize, delta_time: f32) callconv(.c) void {
            _ = active_hook_calls.fetchAdd(1, .seq_cst);
            defer _ = active_hook_calls.fetchSub(1, .seq_cst);
            tick_hook.?.original(game_mode_address, delta_time);
            onTick();
        }
    };
}

const testing = std.testing;

test "should call onTick and original when tick function is called" {
    const Tick = struct {
        var times_called: usize = 0;
        var last_game_mode_address: ?usize = null;
        var last_delta_time: ?f64 = null;
        fn call(game_mode_address: usize, delta_time: f32) callconv(.c) void {
            times_called += 1;
            last_game_mode_address = game_mode_address;
            last_delta_time = delta_time;
        }
    };
    const OnTick = struct {
        var times_called: usize = 0;
        fn call() void {
            times_called += 1;
        }
    };
    const hooks = Hooks(OnTick.call);

    try sdk.memory.hooking.init();
    defer sdk.memory.hooking.deinit() catch @panic("Failed to de-initialize hooking.");
    hooks.init(&.{ .tick = Tick.call });
    defer hooks.deinit();

    try testing.expectEqual(0, Tick.times_called);
    try testing.expectEqual(0, OnTick.times_called);
    Tick.call(123, 456);
    try testing.expectEqual(1, Tick.times_called);
    try testing.expectEqual(123, Tick.last_game_mode_address);
    try testing.expectEqual(456, Tick.last_delta_time);
    try testing.expectEqual(1, OnTick.times_called);
}
