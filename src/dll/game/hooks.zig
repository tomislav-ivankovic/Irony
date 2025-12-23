const std = @import("std");
const builtin = @import("builtin");
const build_info = @import("build_info");
const sdk = @import("../../sdk/root.zig");
const game = @import("root.zig");

pub fn Hooks(comptime game_id: build_info.Game, comptime onTick: *const fn () void) type {
    return struct {
        var tick_hook: ?TickHook = null;
        var update_camera_hook: ?UpdateCameraHook = null;
        pub var last_camera_manager_address: usize = 0;
        var active_hook_calls = std.atomic.Value(u8).init(0);

        const TickHook = sdk.memory.Hook(game.TickFunction(game_id));
        const UpdateCameraHook = sdk.memory.Hook(game.UpdateCameraFunction);

        pub fn init(game_functions: *const game.Memory(game_id).Functions) void {
            std.log.debug("Creating tick hook...", .{});
            if (game_functions.tick) |function| {
                const detour = switch (game_id) {
                    .t7 => onT7Tick,
                    .t8 => onT8Tick,
                };
                if (TickHook.create(function, detour)) |hook| {
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

            std.log.debug("Creating update camera hook...", .{});
            if (game_functions.updateCamera) |function| {
                if (UpdateCameraHook.create(function, onUpdateCamera)) |hook| {
                    update_camera_hook = hook;
                    std.log.info("Update camera hook created.", .{});
                } else |err| {
                    sdk.misc.error_context.append("Failed to create update camera hook.", .{});
                    sdk.misc.error_context.logError(err);
                }
            } else if (!builtin.is_test) {
                sdk.misc.error_context.new("Update camera function not found.", .{});
                sdk.misc.error_context.append("Failed to create update camera hook.", .{});
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

            if (update_camera_hook) |*hook| {
                std.log.debug("Enabling update camera hook...", .{});
                if (hook.enable()) {
                    std.log.info("Update camera hook enabled.", .{});
                } else |err| {
                    sdk.misc.error_context.append("Failed to enable update camera hook.", .{});
                    sdk.misc.error_context.logError(err);
                }
            }
        }

        pub fn deinit() void {
            std.log.debug("Destroying update camera hook...", .{});
            if (update_camera_hook) |*hook| {
                if (hook.destroy()) {
                    std.log.info("Update camera hook destroyed.", .{});
                    update_camera_hook = null;
                } else |err| {
                    sdk.misc.error_context.append("Failed to destroy update camera hook.", .{});
                    sdk.misc.error_context.logError(err);
                }
            } else {
                std.log.debug("Nothing to destroy.", .{});
            }

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

        fn onT7Tick(game_mode_address: usize, delta_time: f32) callconv(.c) void {
            _ = active_hook_calls.fetchAdd(1, .seq_cst);
            defer _ = active_hook_calls.fetchSub(1, .seq_cst);
            tick_hook.?.original(game_mode_address, delta_time);
            onTick();
        }

        fn onT8Tick(delta_time: f64) callconv(.c) void {
            _ = active_hook_calls.fetchAdd(1, .seq_cst);
            defer _ = active_hook_calls.fetchSub(1, .seq_cst);
            tick_hook.?.original(delta_time);
            onTick();
        }

        fn onUpdateCamera(camera_manager_address: usize, delta_time: f32) callconv(.c) void {
            _ = active_hook_calls.fetchAdd(1, .seq_cst);
            defer _ = active_hook_calls.fetchSub(1, .seq_cst);
            last_camera_manager_address = camera_manager_address;
            update_camera_hook.?.original(camera_manager_address, delta_time);
        }
    };
}

const testing = std.testing;

test "should call onTick and original when tick function is called in T7" {
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
    const hooks = Hooks(.t7, OnTick.call);

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

test "should call onTick and original when tick function is called in T8" {
    const Tick = struct {
        var times_called: usize = 0;
        var last_delta_time: ?f64 = null;
        fn call(delta_time: f64) callconv(.c) void {
            times_called += 1;
            last_delta_time = delta_time;
        }
    };
    const OnTick = struct {
        var times_called: usize = 0;
        fn call() void {
            times_called += 1;
        }
    };
    const hooks = Hooks(.t8, OnTick.call);

    try sdk.memory.hooking.init();
    defer sdk.memory.hooking.deinit() catch @panic("Failed to de-initialize hooking.");
    hooks.init(&.{ .tick = Tick.call });
    defer hooks.deinit();

    try testing.expectEqual(0, Tick.times_called);
    try testing.expectEqual(0, OnTick.times_called);
    Tick.call(123.456);
    try testing.expectEqual(1, Tick.times_called);
    try testing.expectEqual(123.456, Tick.last_delta_time);
    try testing.expectEqual(1, OnTick.times_called);
}

test "should call original and set last_camera_manager_address to the latest value when update camera function is called" {
    const UpdateCamera = struct {
        var times_called: usize = 0;
        var last_camera_manager_address: ?usize = null;
        var last_delta_time: ?f32 = null;
        fn call(camera_manager_address: usize, delta_time: f32) callconv(.c) void {
            times_called += 1;
            last_camera_manager_address = camera_manager_address;
            last_delta_time = delta_time;
        }
    };
    const onTick = struct {
        fn call() void {}
    }.call;
    const hooks = Hooks(.t8, onTick);

    try sdk.memory.hooking.init();
    defer sdk.memory.hooking.deinit() catch @panic("Failed to de-initialize hooking.");
    hooks.init(&.{ .updateCamera = UpdateCamera.call });
    defer hooks.deinit();

    try testing.expectEqual(0, UpdateCamera.times_called);
    try testing.expectEqual(0, hooks.last_camera_manager_address);
    UpdateCamera.call(123456, 123.456);
    try testing.expectEqual(1, UpdateCamera.times_called);
    try testing.expectEqual(123456, UpdateCamera.last_camera_manager_address);
    try testing.expectEqual(123.456, UpdateCamera.last_delta_time);
    try testing.expectEqual(123456, hooks.last_camera_manager_address);
}
