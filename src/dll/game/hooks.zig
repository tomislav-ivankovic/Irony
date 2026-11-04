const std = @import("std");
const builtin = @import("builtin");
const build_info = @import("build_info");
const sdk = @import("../../sdk/root.zig");
const game = @import("root.zig");

pub fn Hooks(comptime game_id: build_info.Game, comptime onTick: *const fn () void) type {
    return struct {
        var tick_hook: ?TickHook = null;
        var process_input_hook: ?ProcessInputHook = null;
        var cancel_requirements_hook: ?CancelRequirementsHook = null;
        var render_targets_hook: ?RenderTargetsHook = null;
        var active_hook_calls = std.atomic.Value(u8).init(0);

        pub var input_override: game.InputOverride = .{};
        pub var cancel_requirements: game.CancelRequirements = .{};
        pub var depth_buffer_address: usize = 0;

        const TickHook = sdk.memory.Hook(game.TickFunction(game_id));
        const ProcessInputHook = sdk.memory.Hook(game.ProcessInputFunction(game_id));
        const CancelRequirementsHook = sdk.memory.Hook(game.ProcessCancelRequirementFunction);
        const RenderTargetsHook = sdk.memory.Hook(game.SetRenderTargetsFunction);

        pub fn init(game_functions: *const game.Memory(game_id).Functions) void {
            std.log.debug("Creating process input hook...", .{});
            if (game_functions.processInput) |function| {
                const detour = switch (game_id) {
                    .t7 => onT7ProcessInput,
                    .t8 => onT8ProcessInput,
                };
                if (ProcessInputHook.create(function, detour)) |hook| {
                    process_input_hook = hook;
                    std.log.info("Process input hook created.", .{});
                } else |err| {
                    if (!builtin.is_test) {
                        sdk.misc.error_context.append("Failed to create process input hook.", .{});
                        sdk.misc.error_context.logError(err);
                    }
                }
            } else if (!builtin.is_test) {
                sdk.misc.error_context.new("Process input function not found.", .{});
                sdk.misc.error_context.append("Failed to create process input hook.", .{});
                sdk.misc.error_context.logError(error.NotFound);
            }

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

            std.log.debug("Creating cancel requirements hook...", .{});
            if (game_functions.processCancelRequirement) |function| {
                if (CancelRequirementsHook.create(function, onProcessCancelRequirement)) |hook| {
                    cancel_requirements_hook = hook;
                    std.log.info("Cancel requirements hook created.", .{});
                } else |err| {
                    if (!builtin.is_test) {
                        sdk.misc.error_context.append("Failed to create cancel requirements hook.", .{});
                        sdk.misc.error_context.logError(err);
                    }
                }
            } else if (!builtin.is_test) {
                sdk.misc.error_context.new("Process cancel requirement function not found.", .{});
                sdk.misc.error_context.append("Failed to create cancel requirements hook.", .{});
                sdk.misc.error_context.logError(error.NotFound);
            }

            if (game_id == .t8) {
                std.log.debug("Creating render targets hook...", .{});
                if (game_functions.setRenderTargets) |function| {
                    const detour = onSetRenderTargets;
                    if (RenderTargetsHook.create(function, detour)) |hook| {
                        render_targets_hook = hook;
                        std.log.info("Render targets hook created.", .{});
                    } else |err| {
                        if (!builtin.is_test) {
                            sdk.misc.error_context.append("Failed to create render targets hook.", .{});
                            sdk.misc.error_context.logError(err);
                        }
                    }
                } else if (!builtin.is_test) {
                    sdk.misc.error_context.new("SetRenderTargets function not found.", .{});
                    sdk.misc.error_context.append("Failed to create render targets hook.", .{});
                    sdk.misc.error_context.logError(error.NotFound);
                }
            }

            if (process_input_hook) |*hook| {
                std.log.debug("Enabling process input hook...", .{});
                if (hook.enable()) {
                    std.log.info("Process input hook enabled.", .{});
                } else |err| {
                    sdk.misc.error_context.append("Failed to enable process input hook.", .{});
                    sdk.misc.error_context.logError(err);
                }
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

            if (cancel_requirements_hook) |*hook| {
                std.log.debug("Enabling cancel requirements hook...", .{});
                if (hook.enable()) {
                    std.log.info("Cancel requirements hook enabled.", .{});
                } else |err| {
                    sdk.misc.error_context.append("Failed to enable cancel requirements hook.", .{});
                    sdk.misc.error_context.logError(err);
                }
            }

            if (render_targets_hook) |*hook| {
                std.log.debug("Enabling render targets hook...", .{});
                if (hook.enable()) {
                    std.log.info("Render targets hook enabled.", .{});
                } else |err| {
                    sdk.misc.error_context.append("Failed to enable render targets hook.", .{});
                    sdk.misc.error_context.logError(err);
                }
            }
        }

        pub fn deinit(io: std.Io) void {
            var is_render_targets_hook_disabled = false;
            if (game_id == .t8) {
                std.log.debug("Disabling render targets hook...", .{});
                if (render_targets_hook) |*hook| {
                    if (hook.disable()) {
                        is_render_targets_hook_disabled = true;
                        std.log.info("Render targets hook disabled.", .{});
                    } else |err| switch (err) {
                        error.HookDisabled => is_render_targets_hook_disabled = true,
                        else => {
                            sdk.misc.error_context.append("Failed to disable render targets hook.", .{});
                            sdk.misc.error_context.logError(err);
                        },
                    }
                } else {
                    std.log.debug("Nothing to disable.", .{});
                }
            }

            std.log.debug("Disabling cancel requirements hook...", .{});
            var is_cancel_requirements_hook_disabled = false;
            if (cancel_requirements_hook) |*hook| {
                if (hook.disable()) {
                    is_cancel_requirements_hook_disabled = true;
                    std.log.info("Cancel requirements hook disabled.", .{});
                } else |err| switch (err) {
                    error.HookDisabled => is_cancel_requirements_hook_disabled = true,
                    else => {
                        sdk.misc.error_context.append("Failed to disable cancel requirements hook.", .{});
                        sdk.misc.error_context.logError(err);
                    },
                }
            } else {
                std.log.debug("Nothing to disable.", .{});
            }

            std.log.debug("Disabling tick hook...", .{});
            var is_tick_hook_disabled = false;
            if (tick_hook) |*hook| {
                if (hook.disable()) {
                    is_tick_hook_disabled = true;
                    std.log.info("Tick hook disabled.", .{});
                } else |err| switch (err) {
                    error.HookDisabled => is_tick_hook_disabled = true,
                    else => {
                        sdk.misc.error_context.append("Failed to disable tick hook.", .{});
                        sdk.misc.error_context.logError(err);
                    },
                }
            } else {
                std.log.debug("Nothing to disable.", .{});
            }

            std.log.debug("Disabling process input hook...", .{});
            var is_process_input_hook_disabled = false;
            if (process_input_hook) |*hook| {
                if (hook.disable()) {
                    is_process_input_hook_disabled = true;
                    std.log.info("Process input hook disabled.", .{});
                } else |err| switch (err) {
                    error.HookDisabled => is_process_input_hook_disabled = true,
                    else => {
                        sdk.misc.error_context.append("Failed to disable process input hook.", .{});
                        sdk.misc.error_context.logError(err);
                    },
                }
            } else {
                std.log.debug("Nothing to disable.", .{});
            }

            while (active_hook_calls.load(.seq_cst) > 0) {
                io.sleep(.fromMilliseconds(10), .awake) catch |err| {
                    sdk.misc.error_context.append("Failed to sleep for 10 ms while waiting on active game hooks.", .{});
                    sdk.misc.error_context.logError(err);
                };
            }

            if (game_id == .t8) {
                std.log.debug("Destroying render targets hook...", .{});
                if (render_targets_hook) |*hook| {
                    if (!is_render_targets_hook_disabled) {
                        std.log.warn("Skipping the destruction of render targets hook since disabling it failed.", .{});
                    } else if (hook.destroy()) {
                        std.log.info("Render targets hook destroyed.", .{});
                        render_targets_hook = null;
                    } else |err| {
                        sdk.misc.error_context.append("Failed to destroy render targets hook.", .{});
                        sdk.misc.error_context.logError(err);
                    }
                } else {
                    std.log.debug("Nothing to destroy.", .{});
                }
            }

            std.log.debug("Destroying cancel requirements hook...", .{});
            if (cancel_requirements_hook) |*hook| {
                if (!is_cancel_requirements_hook_disabled) {
                    std.log.warn(
                        "Skipping the destruction of cancel requirements hook since disabling it failed.",
                        .{},
                    );
                } else if (hook.destroy()) {
                    std.log.info("Cancel requirements hook destroyed.", .{});
                    cancel_requirements_hook = null;
                } else |err| {
                    sdk.misc.error_context.append("Failed to destroy cancel requirements hook.", .{});
                    sdk.misc.error_context.logError(err);
                }
            } else {
                std.log.debug("Nothing to destroy.", .{});
            }

            std.log.debug("Destroying tick hook...", .{});
            if (tick_hook) |*hook| {
                if (!is_tick_hook_disabled) {
                    std.log.warn("Skipping the destruction of tick hook since disabling it failed.", .{});
                } else if (hook.destroy()) {
                    std.log.info("Tick hook destroyed.", .{});
                    tick_hook = null;
                } else |err| {
                    sdk.misc.error_context.append("Failed to destroy tick hook.", .{});
                    sdk.misc.error_context.logError(err);
                }
            } else {
                std.log.debug("Nothing to destroy.", .{});
            }

            std.log.debug("Destroying process input hook...", .{});
            if (process_input_hook) |*hook| {
                if (!is_process_input_hook_disabled) {
                    std.log.warn("Skipping the destruction of process input hook since disabling it failed.", .{});
                } else if (hook.destroy()) {
                    std.log.info("Process input hook destroyed.", .{});
                    process_input_hook = null;
                } else |err| {
                    sdk.misc.error_context.append("Failed to destroy process input hook.", .{});
                    sdk.misc.error_context.logError(err);
                }
            } else {
                std.log.debug("Nothing to destroy.", .{});
            }
        }

        fn onT7Tick(param_1: u8, param_2: u32) callconv(.c) void {
            _ = active_hook_calls.fetchAdd(1, .seq_cst);
            defer _ = active_hook_calls.fetchSub(1, .seq_cst);
            cancel_requirements = .{};
            tick_hook.?.original(param_1, param_2);
            onTick();
        }

        fn onT8Tick(param_1: u64, param_2: u8, param_3: u8, param_4: u8) callconv(.c) void {
            _ = active_hook_calls.fetchAdd(1, .seq_cst);
            defer _ = active_hook_calls.fetchSub(1, .seq_cst);
            cancel_requirements = .{};
            tick_hook.?.original(param_1, param_2, param_3, param_4);
            onTick();
        }

        fn onT7ProcessInput(
            player: sdk.memory.Pointer(game.Player(.t7)),
            player_side: game.PlayerSide,
            down_input: game.Input(.t7),
            press_input: game.Input(.t7),
        ) callconv(.c) void {
            _ = active_hook_calls.fetchAdd(1, .seq_cst);
            defer _ = active_hook_calls.fetchSub(1, .seq_cst);
            var new_down_input = down_input;
            var new_press_input = press_input;
            applyInputOverride(player, player_side, &new_down_input, &new_press_input);
            process_input_hook.?.original(player, player_side, new_down_input, new_press_input);
        }

        fn onT8ProcessInput(
            player: sdk.memory.Pointer(game.Player(.t8)),
            player_side: game.PlayerSide,
            down_input: game.Input(.t8),
            press_input: game.Input(.t8),
            param_5: sdk.memory.Pointer(sdk.math.Vec2),
            param_6: sdk.memory.Pointer(sdk.math.Vec2),
            param_7: u8,
        ) callconv(.c) void {
            _ = active_hook_calls.fetchAdd(1, .seq_cst);
            defer _ = active_hook_calls.fetchSub(1, .seq_cst);
            var new_down_input = down_input;
            var new_press_input = press_input;
            applyInputOverride(player, player_side, &new_down_input, &new_press_input);
            process_input_hook.?.original(
                player,
                player_side,
                new_down_input,
                new_press_input,
                param_5,
                param_6,
                param_7,
            );
        }

        fn applyInputOverride(
            player_maybe: sdk.memory.Pointer(game.Player(game_id)),
            player_side: game.PlayerSide,
            down_input: *game.Input(game_id),
            press_input: *game.Input(game_id),
        ) void {
            const player = player_maybe.toConstPointer() orelse return;
            input_override.apply(game_id, player.id, player_side, down_input, press_input);
        }

        fn onProcessCancelRequirement(
            param_1: *const game.CancelRequirement,
            param_2: i64,
            param_3: i64,
        ) callconv(.c) u64 {
            _ = active_hook_calls.fetchAdd(1, .seq_cst);
            defer _ = active_hook_calls.fetchSub(1, .seq_cst);
            const requirement = param_1.*;
            switch (requirement) {
                .throw_escape_press_1 => cancel_requirements.throw_escape_press_1 = true,
                .throw_escape_press_2 => cancel_requirements.throw_escape_press_2 = true,
                .throw_escape_press_1_plus_2 => cancel_requirements.throw_escape_press_1_plus_2 = true,
                .throw_escape_hold => cancel_requirements.throw_escape_hold = true,
                else => {},
            }
            return cancel_requirements_hook.?.original(param_1, param_2, param_3);
        }

        fn onSetRenderTargets(this: usize, param_1: usize, param_2: u32, param_3: usize) callconv(.c) void {
            _ = active_hook_calls.fetchAdd(1, .seq_cst);
            defer _ = active_hook_calls.fetchSub(1, .seq_cst);
            render_targets_hook.?.original(this, param_1, param_2, param_3);
            if (param_3 == 0) {
                return;
            }
            const trail = sdk.memory.PointerTrail.fromArray(.{ param_3 +| 0x48, 0x20, 0x0 });
            depth_buffer_address = trail.resolve() orelse 0;
        }
    };
}

const testing = std.testing;

test "should call onTick and original when tick function is called in T7" {
    const Tick = struct {
        var times_called: usize = 0;
        var last_param_1: ?u8 = null;
        var last_param_2: ?u32 = null;
        fn call(param_1: u8, param_2: u32) callconv(.c) void {
            times_called += 1;
            last_param_1 = param_1;
            last_param_2 = param_2;
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
    defer hooks.deinit(testing.io);

    try testing.expectEqual(0, Tick.times_called);
    try testing.expectEqual(0, OnTick.times_called);
    Tick.call(123, 456);
    try testing.expectEqual(1, Tick.times_called);
    try testing.expectEqual(123, Tick.last_param_1);
    try testing.expectEqual(456, Tick.last_param_2);
    try testing.expectEqual(1, OnTick.times_called);
}

test "should call onTick and original when tick function is called in T8" {
    const Tick = struct {
        var times_called: usize = 0;
        var last_param_1: ?u64 = null;
        var last_param_2: ?u8 = null;
        var last_param_3: ?u8 = null;
        var last_param_4: ?u8 = null;
        fn call(param_1: u64, param_2: u8, param_3: u8, param_4: u8) callconv(.c) void {
            times_called += 1;
            last_param_1 = param_1;
            last_param_2 = param_2;
            last_param_3 = param_3;
            last_param_4 = param_4;
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
    defer hooks.deinit(testing.io);

    try testing.expectEqual(0, Tick.times_called);
    try testing.expectEqual(0, OnTick.times_called);
    Tick.call(2, 3, 4, 5);
    try testing.expectEqual(1, Tick.times_called);
    try testing.expectEqual(2, Tick.last_param_1);
    try testing.expectEqual(3, Tick.last_param_2);
    try testing.expectEqual(4, Tick.last_param_3);
    try testing.expectEqual(5, Tick.last_param_4);
    try testing.expectEqual(1, OnTick.times_called);
}

test "should apply input override correctly in T7" {
    const ProcessInput = struct {
        var times_called: usize = 0;
        var last_player: ?sdk.memory.Pointer(game.Player(.t7)) = null;
        var last_player_side: ?game.PlayerSide = null;
        var last_down_input: ?game.Input(.t7) = null;
        var last_press_input: ?game.Input(.t7) = null;
        fn call(
            player: sdk.memory.Pointer(game.Player(.t7)),
            player_side: game.PlayerSide,
            down_input: game.Input(.t7),
            press_input: game.Input(.t7),
        ) callconv(.c) void {
            times_called += 1;
            last_player = player;
            last_player_side = player_side;
            last_down_input = down_input;
            last_press_input = press_input;
        }
    };
    const OnTick = struct {
        fn call() void {}
    };
    const hooks = Hooks(.t7, OnTick.call);

    try sdk.memory.hooking.init();
    defer sdk.memory.hooking.deinit() catch @panic("Failed to de-initialize hooking.");
    hooks.init(&.{ .processInput = ProcessInput.call });
    defer hooks.deinit(testing.io);

    hooks.input_override = .{
        .player_1 = .{
            .previous_input = .{ .down = true, .button_1 = true },
            .current_input = .{ .down = true, .forward = true, .button_1 = true, .button_2 = true },
        },
        .player_2 = null,
    };
    const player_1 = sdk.memory.Pointer(game.Player(.t7)).fromPointer(&.{ .id = .player_1 });
    const player_2 = sdk.memory.Pointer(game.Player(.t7)).fromPointer(&.{ .id = .player_2 });

    ProcessInput.call(player_1, .left, .{ .button_3 = true }, .{ .button_4 = true });
    try testing.expectEqual(1, ProcessInput.times_called);
    try testing.expectEqual(player_1, ProcessInput.last_player);
    try testing.expectEqual(.left, ProcessInput.last_player_side);
    try testing.expectEqual(
        game.Input(.t7){ .down = true, .right = true, .button_1 = true, .button_2 = true },
        ProcessInput.last_down_input,
    );
    try testing.expectEqual(game.Input(.t7){ .right = true, .button_2 = true }, ProcessInput.last_press_input);

    ProcessInput.call(player_1, .right, .{ .button_3 = true }, .{ .button_4 = true });
    try testing.expectEqual(2, ProcessInput.times_called);
    try testing.expectEqual(player_1, ProcessInput.last_player);
    try testing.expectEqual(.right, ProcessInput.last_player_side);
    try testing.expectEqual(
        game.Input(.t7){ .down = true, .left = true, .button_1 = true, .button_2 = true },
        ProcessInput.last_down_input,
    );
    try testing.expectEqual(game.Input(.t7){ .left = true, .button_2 = true }, ProcessInput.last_press_input);

    ProcessInput.call(player_2, .right, .{ .button_3 = true }, .{ .button_4 = true });
    try testing.expectEqual(3, ProcessInput.times_called);
    try testing.expectEqual(player_2, ProcessInput.last_player);
    try testing.expectEqual(.right, ProcessInput.last_player_side);
    try testing.expectEqual(game.Input(.t7){ .button_3 = true }, ProcessInput.last_down_input);
    try testing.expectEqual(game.Input(.t7){ .button_4 = true }, ProcessInput.last_press_input);
}

test "should apply input override correctly in T8" {
    const ProcessInput = struct {
        var times_called: usize = 0;
        var last_player: ?sdk.memory.Pointer(game.Player(.t8)) = null;
        var last_player_side: ?game.PlayerSide = null;
        var last_down_input: ?game.Input(.t8) = null;
        var last_press_input: ?game.Input(.t8) = null;
        var last_param_5: ?sdk.memory.Pointer(sdk.math.Vec2) = null;
        var last_param_6: ?sdk.memory.Pointer(sdk.math.Vec2) = null;
        var last_param_7: ?u8 = null;
        fn call(
            player: sdk.memory.Pointer(game.Player(.t8)),
            player_side: game.PlayerSide,
            down_input: game.Input(.t8),
            press_input: game.Input(.t8),
            param_5: sdk.memory.Pointer(sdk.math.Vec2),
            param_6: sdk.memory.Pointer(sdk.math.Vec2),
            param_7: u8,
        ) callconv(.c) void {
            times_called += 1;
            last_player = player;
            last_player_side = player_side;
            last_down_input = down_input;
            last_press_input = press_input;
            last_param_5 = param_5;
            last_param_6 = param_6;
            last_param_7 = param_7;
        }
    };
    const OnTick = struct {
        fn call() void {}
    };
    const hooks = Hooks(.t8, OnTick.call);

    try sdk.memory.hooking.init();
    defer sdk.memory.hooking.deinit() catch @panic("Failed to de-initialize hooking.");
    hooks.init(&.{ .processInput = ProcessInput.call });
    defer hooks.deinit(testing.io);

    hooks.input_override = .{
        .player_1 = .{
            .previous_input = .{ .down = true, .button_1 = true },
            .current_input = .{ .down = true, .forward = true, .button_1 = true, .button_2 = true },
        },
        .player_2 = null,
    };
    const player_1 = sdk.memory.Pointer(game.Player(.t8)).fromPointer(&.{ .id = .player_1 });
    const player_2 = sdk.memory.Pointer(game.Player(.t8)).fromPointer(&.{ .id = .player_2 });
    const param_5 = sdk.memory.Pointer(sdk.math.Vec2).fromPointer(&.zero);
    const param_6 = sdk.memory.Pointer(sdk.math.Vec2).fromPointer(&.zero);

    ProcessInput.call(player_1, .left, .{ .button_3 = true }, .{ .button_4 = true }, param_5, param_6, 11);
    try testing.expectEqual(1, ProcessInput.times_called);
    try testing.expectEqual(player_1, ProcessInput.last_player);
    try testing.expectEqual(.left, ProcessInput.last_player_side);
    try testing.expectEqual(
        game.Input(.t8){ .down = true, .right = true, .button_1 = true, .button_2 = true },
        ProcessInput.last_down_input,
    );
    try testing.expectEqual(game.Input(.t8){ .right = true, .button_2 = true }, ProcessInput.last_press_input);
    try testing.expectEqual(param_5, ProcessInput.last_param_5);
    try testing.expectEqual(param_6, ProcessInput.last_param_6);
    try testing.expectEqual(11, ProcessInput.last_param_7);

    ProcessInput.call(player_1, .right, .{ .button_3 = true }, .{ .button_4 = true }, param_5, param_6, 12);
    try testing.expectEqual(2, ProcessInput.times_called);
    try testing.expectEqual(player_1, ProcessInput.last_player);
    try testing.expectEqual(.right, ProcessInput.last_player_side);
    try testing.expectEqual(
        game.Input(.t8){ .down = true, .left = true, .button_1 = true, .button_2 = true },
        ProcessInput.last_down_input,
    );
    try testing.expectEqual(game.Input(.t8){ .left = true, .button_2 = true }, ProcessInput.last_press_input);
    try testing.expectEqual(param_5, ProcessInput.last_param_5);
    try testing.expectEqual(param_6, ProcessInput.last_param_6);
    try testing.expectEqual(12, ProcessInput.last_param_7);

    ProcessInput.call(player_2, .right, .{ .button_3 = true }, .{ .button_4 = true }, param_5, param_6, 13);
    try testing.expectEqual(3, ProcessInput.times_called);
    try testing.expectEqual(player_2, ProcessInput.last_player);
    try testing.expectEqual(.right, ProcessInput.last_player_side);
    try testing.expectEqual(game.Input(.t8){ .button_3 = true }, ProcessInput.last_down_input);
    try testing.expectEqual(game.Input(.t8){ .button_4 = true }, ProcessInput.last_press_input);
    try testing.expectEqual(param_5, ProcessInput.last_param_5);
    try testing.expectEqual(param_6, ProcessInput.last_param_6);
    try testing.expectEqual(13, ProcessInput.last_param_7);
}

test "should set cancel_requirements and call original when process cancel requirement is called" {
    const ProcessCancelRequirement = struct {
        var times_called: usize = 0;
        var last_param_1: ?*const game.CancelRequirement = null;
        var last_param_2: ?i64 = null;
        var last_param_3: ?i64 = null;
        var return_value: u64 = 0;
        fn call(param_1: *const game.CancelRequirement, param_2: i64, param_3: i64) callconv(.c) u64 {
            times_called += 1;
            last_param_1 = param_1;
            last_param_2 = param_2;
            last_param_3 = param_3;
            return return_value;
        }
    };
    const OnTick = struct {
        fn call() void {}
    };
    const hooks = Hooks(.t8, OnTick.call);

    try sdk.memory.hooking.init();
    defer sdk.memory.hooking.deinit() catch @panic("Failed to de-initialize hooking.");
    hooks.init(&.{ .processCancelRequirement = ProcessCancelRequirement.call });
    defer hooks.deinit(testing.io);

    try testing.expectEqual(game.CancelRequirements{}, hooks.cancel_requirements);
    try testing.expectEqual(0, ProcessCancelRequirement.times_called);

    const throw_escape_press_1 = game.CancelRequirement.throw_escape_press_1;
    ProcessCancelRequirement.return_value = 10;
    const return_1 = ProcessCancelRequirement.call(&throw_escape_press_1, 11, 12);
    try testing.expectEqual(game.CancelRequirements{
        .throw_escape_press_1 = true,
    }, hooks.cancel_requirements);
    try testing.expectEqual(1, ProcessCancelRequirement.times_called);
    try testing.expectEqual(&throw_escape_press_1, ProcessCancelRequirement.last_param_1);
    try testing.expectEqual(11, ProcessCancelRequirement.last_param_2);
    try testing.expectEqual(12, ProcessCancelRequirement.last_param_3);
    try testing.expectEqual(return_1, 10);

    const throw_escape_press_2 = game.CancelRequirement.throw_escape_press_2;
    ProcessCancelRequirement.return_value = 20;
    const return_2 = ProcessCancelRequirement.call(&throw_escape_press_2, 21, 22);
    try testing.expectEqual(game.CancelRequirements{
        .throw_escape_press_1 = true,
        .throw_escape_press_2 = true,
    }, hooks.cancel_requirements);
    try testing.expectEqual(2, ProcessCancelRequirement.times_called);
    try testing.expectEqual(&throw_escape_press_2, ProcessCancelRequirement.last_param_1);
    try testing.expectEqual(21, ProcessCancelRequirement.last_param_2);
    try testing.expectEqual(22, ProcessCancelRequirement.last_param_3);
    try testing.expectEqual(return_2, 20);

    const throw_escape_press_1_plus_2 = game.CancelRequirement.throw_escape_press_1_plus_2;
    ProcessCancelRequirement.return_value = 30;
    const return_3 = ProcessCancelRequirement.call(&throw_escape_press_1_plus_2, 31, 32);
    try testing.expectEqual(game.CancelRequirements{
        .throw_escape_press_1 = true,
        .throw_escape_press_2 = true,
        .throw_escape_press_1_plus_2 = true,
    }, hooks.cancel_requirements);
    try testing.expectEqual(3, ProcessCancelRequirement.times_called);
    try testing.expectEqual(&throw_escape_press_1_plus_2, ProcessCancelRequirement.last_param_1);
    try testing.expectEqual(31, ProcessCancelRequirement.last_param_2);
    try testing.expectEqual(32, ProcessCancelRequirement.last_param_3);
    try testing.expectEqual(return_3, 30);

    const throw_escape_hold = game.CancelRequirement.throw_escape_hold;
    ProcessCancelRequirement.return_value = 40;
    const return_4 = ProcessCancelRequirement.call(&throw_escape_hold, 41, 42);
    try testing.expectEqual(game.CancelRequirements{
        .throw_escape_press_1 = true,
        .throw_escape_press_2 = true,
        .throw_escape_press_1_plus_2 = true,
        .throw_escape_hold = true,
    }, hooks.cancel_requirements);
    try testing.expectEqual(4, ProcessCancelRequirement.times_called);
    try testing.expectEqual(&throw_escape_hold, ProcessCancelRequirement.last_param_1);
    try testing.expectEqual(41, ProcessCancelRequirement.last_param_2);
    try testing.expectEqual(42, ProcessCancelRequirement.last_param_3);
    try testing.expectEqual(return_4, 40);
}

test "should reset cancel_requirements when tick function is called in T7" {
    const Tick = struct {
        fn call(_: u8, _: u32) callconv(.c) void {}
    };
    const OnTick = struct {
        fn call() void {}
    };
    const hooks = Hooks(.t7, OnTick.call);

    try sdk.memory.hooking.init();
    defer sdk.memory.hooking.deinit() catch @panic("Failed to de-initialize hooking.");
    hooks.init(&.{ .tick = Tick.call });
    defer hooks.deinit(testing.io);

    hooks.cancel_requirements = .{
        .throw_escape_press_1 = true,
        .throw_escape_press_2 = true,
        .throw_escape_press_1_plus_2 = true,
        .throw_escape_hold = true,
    };
    Tick.call(123, 456);
    try testing.expectEqual(game.CancelRequirements{}, hooks.cancel_requirements);
}

test "should reset cancel_requirements when tick function is called in T8" {
    const Tick = struct {
        fn call(_: u64, _: u8, _: u8, _: u8) callconv(.c) void {}
    };
    const OnTick = struct {
        fn call() void {}
    };
    const hooks = Hooks(.t8, OnTick.call);

    try sdk.memory.hooking.init();
    defer sdk.memory.hooking.deinit() catch @panic("Failed to de-initialize hooking.");
    hooks.init(&.{ .tick = Tick.call });
    defer hooks.deinit(testing.io);

    hooks.cancel_requirements = .{
        .throw_escape_press_1 = true,
        .throw_escape_press_2 = true,
        .throw_escape_press_1_plus_2 = true,
        .throw_escape_hold = true,
    };
    Tick.call(2, 3, 4, 5);
    try testing.expectEqual(game.CancelRequirements{}, hooks.cancel_requirements);
}

test "should set depth_buffer_address to correct value and call original when setRenderTargets function is called in T8" {
    const SetRenderTargets = struct {
        var times_called: usize = 0;
        var last_this: ?usize = null;
        var last_param_1: ?usize = null;
        var last_param_2: ?u32 = null;
        var last_param_3: ?usize = null;
        fn call(this: usize, param_1: usize, param_2: u32, param_3: usize) callconv(.c) void {
            times_called += 1;
            last_this = this;
            last_param_1 = param_1;
            last_param_2 = param_2;
            last_param_3 = param_3;
        }
    };
    const OnTick = struct {
        fn call() void {}
    };
    const hooks = Hooks(.t8, OnTick.call);

    try sdk.memory.hooking.init();
    defer sdk.memory.hooking.deinit() catch @panic("Failed to de-initialize hooking.");
    hooks.init(&.{ .setRenderTargets = SetRenderTargets.call });
    defer hooks.deinit(testing.io);

    const B = extern struct {
        _padding: [0x20]u8 = undefined,
        c: usize,
    };
    const A = extern struct {
        _padding: [0x48]u8 = undefined,
        b: *const B,
    };
    const a = &A{ .b = &.{ .c = 123 } };

    try testing.expectEqual(0, SetRenderTargets.times_called);

    SetRenderTargets.call(11, 12, 13, std.math.maxInt(usize));
    try testing.expectEqual(1, SetRenderTargets.times_called);
    try testing.expectEqual(11, SetRenderTargets.last_this);
    try testing.expectEqual(12, SetRenderTargets.last_param_1);
    try testing.expectEqual(13, SetRenderTargets.last_param_2);
    try testing.expectEqual(std.math.maxInt(usize), SetRenderTargets.last_param_3);
    try testing.expectEqual(0, hooks.depth_buffer_address);

    SetRenderTargets.call(11, 12, 13, @intFromPtr(a));
    try testing.expectEqual(2, SetRenderTargets.times_called);
    try testing.expectEqual(11, SetRenderTargets.last_this);
    try testing.expectEqual(12, SetRenderTargets.last_param_1);
    try testing.expectEqual(13, SetRenderTargets.last_param_2);
    try testing.expectEqual(@intFromPtr(a), SetRenderTargets.last_param_3);
    try testing.expectEqual(123, hooks.depth_buffer_address);

    SetRenderTargets.call(11, 12, 13, 0);
    try testing.expectEqual(3, SetRenderTargets.times_called);
    try testing.expectEqual(11, SetRenderTargets.last_this);
    try testing.expectEqual(12, SetRenderTargets.last_param_1);
    try testing.expectEqual(13, SetRenderTargets.last_param_2);
    try testing.expectEqual(0, SetRenderTargets.last_param_3);
    try testing.expectEqual(123, hooks.depth_buffer_address);
}
