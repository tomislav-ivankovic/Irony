const std = @import("std");
const builtin = @import("builtin");
const build_info = @import("build_info");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const game = @import("root.zig");

pub fn Hooks(comptime game_id: build_info.Game, comptime onTick: *const fn () void) type {
    return struct {
        pub var input_override: game.InputOverride = .{};
        pub var cancel_requirements: game.CancelRequirements = .{};
        pub var depth_buffer_address: usize = 0;
        pub var camera_override: ?model.Camera = null;
        pub var last_original_view_info: game.ViewInfo(game_id) = .{};
        pub var last_overridden_view_info: game.ViewInfo(game_id) = .{};

        const tick_hook = sdk.memory.Hook(game.TickFunction(game_id), switch (game_id) {
            .t7 => onT7Tick,
            .t8 => onT8Tick,
        });
        const process_input_hook = sdk.memory.Hook(game.ProcessInputFunction(game_id), switch (game_id) {
            .t7 => onT7ProcessInput,
            .t8 => onT8ProcessInput,
        });
        const cancel_requirements_hook = sdk.memory.Hook(
            game.ProcessCancelRequirementFunction,
            onProcessCancelRequirement,
        );
        const render_targets_hook = sdk.memory.Hook(game.SetRenderTargetsFunction, onSetRenderTargets);
        const get_view_point_hook = sdk.memory.Hook(game.GetViewPointFunction(game_id), switch (game_id) {
            .t7 => onT7GetViewPoint,
            .t8 => onT8GetViewPoint,
        });

        pub fn init(game_functions: *const game.Memory(game_id).Functions) void {
            std.log.debug("Initializing process input hook...", .{});
            if (game_functions.processInput) |function| {
                if (process_input_hook.init(function)) {
                    std.log.info("Process input hook initialized.", .{});
                } else |err| {
                    if (!builtin.is_test) {
                        sdk.misc.error_context.append("Failed to initialize process input hook.", .{});
                        sdk.misc.error_context.logError(err);
                    }
                }
            } else if (!builtin.is_test) {
                sdk.misc.error_context.new("Process input function not found.", .{});
                sdk.misc.error_context.append("Failed to initialize process input hook.", .{});
                sdk.misc.error_context.logError(error.NotFound);
            }

            std.log.debug("Initializing tick hook...", .{});
            if (game_functions.tick) |function| {
                if (tick_hook.init(function)) {
                    std.log.info("Tick hook initialized.", .{});
                } else |err| {
                    if (!builtin.is_test) {
                        sdk.misc.error_context.append("Failed to initialize tick hook.", .{});
                        sdk.misc.error_context.logError(err);
                    }
                }
            } else if (!builtin.is_test) {
                sdk.misc.error_context.new("Tick function not found.", .{});
                sdk.misc.error_context.append("Failed to initialize tick hook.", .{});
                sdk.misc.error_context.logError(error.NotFound);
            }

            std.log.debug("Initializing cancel requirements hook...", .{});
            if (game_functions.processCancelRequirement) |function| {
                if (cancel_requirements_hook.init(function)) {
                    std.log.info("Cancel requirements hook initialized.", .{});
                } else |err| {
                    if (!builtin.is_test) {
                        sdk.misc.error_context.append("Failed to initialize cancel requirements hook.", .{});
                        sdk.misc.error_context.logError(err);
                    }
                }
            } else if (!builtin.is_test) {
                sdk.misc.error_context.new("Process cancel requirement function not found.", .{});
                sdk.misc.error_context.append("Failed to initialize cancel requirements hook.", .{});
                sdk.misc.error_context.logError(error.NotFound);
            }

            if (game_id == .t8) {
                std.log.debug("Initializing render targets hook...", .{});
                if (game_functions.setRenderTargets) |function| {
                    if (render_targets_hook.init(function)) {
                        std.log.info("Render targets hook initialized.", .{});
                    } else |err| {
                        if (!builtin.is_test) {
                            sdk.misc.error_context.append("Failed to initialize render targets hook.", .{});
                            sdk.misc.error_context.logError(err);
                        }
                    }
                } else if (!builtin.is_test) {
                    sdk.misc.error_context.new("SetRenderTargets function not found.", .{});
                    sdk.misc.error_context.append("Failed to initialize render targets hook.", .{});
                    sdk.misc.error_context.logError(error.NotFound);
                }
            }

            std.log.debug("Initializing get view point hook...", .{});
            if (game_functions.getViewPoint) |function| {
                if (get_view_point_hook.init(function)) {
                    std.log.info("Get view point hook initialized.", .{});
                } else |err| {
                    if (!builtin.is_test) {
                        sdk.misc.error_context.append("Failed to initialize get view point hook.", .{});
                        sdk.misc.error_context.logError(err);
                    }
                }
            } else if (!builtin.is_test) {
                sdk.misc.error_context.new("Get view point function not found.", .{});
                sdk.misc.error_context.append("Failed to initialize get view point hook.", .{});
                sdk.misc.error_context.logError(error.NotFound);
            }
        }

        pub fn deinit(io: std.Io) void {
            std.log.debug("De-initializing get view point hook...", .{});
            if (!get_view_point_hook.isInitialized()) {
                std.log.debug("Nothing to de-initialize.", .{});
            } else if (get_view_point_hook.deinit(io)) {
                std.log.info("Get view point hook de-initialized.", .{});
            } else |err| {
                sdk.misc.error_context.append("Failed to de-initialize get view point hook.", .{});
                sdk.misc.error_context.logError(err);
            }

            if (game_id == .t8) {
                std.log.debug("De-initializing render targets hook...", .{});
                if (!render_targets_hook.isInitialized()) {
                    std.log.debug("Nothing to de-initialize.", .{});
                } else if (render_targets_hook.deinit(io)) {
                    std.log.info("Render targets hook de-initialized.", .{});
                } else |err| {
                    sdk.misc.error_context.append("Failed to de-initialize render targets hook.", .{});
                    sdk.misc.error_context.logError(err);
                }
            }

            std.log.debug("De-initializing cancel requirements hook...", .{});
            if (!cancel_requirements_hook.isInitialized()) {
                std.log.debug("Nothing to de-initialize.", .{});
            } else if (cancel_requirements_hook.deinit(io)) {
                std.log.info("Cancel requirements hook de-initialized.", .{});
            } else |err| {
                sdk.misc.error_context.append("Failed to de-initialize cancel requirements hook.", .{});
                sdk.misc.error_context.logError(err);
            }

            std.log.debug("De-initializing tick hook...", .{});
            if (!tick_hook.isInitialized()) {
                std.log.debug("Nothing to de-initialize.", .{});
            } else if (tick_hook.deinit(io)) {
                std.log.info("Tick hook de-initialized.", .{});
            } else |err| {
                sdk.misc.error_context.append("Failed to de-initialize tick hook.", .{});
                sdk.misc.error_context.logError(err);
            }

            std.log.debug("De-initializing process input hook...", .{});
            if (!process_input_hook.isInitialized()) {
                std.log.debug("Nothing to de-initialize.", .{});
            } else if (process_input_hook.deinit(io)) {
                std.log.info("Process input hook de-initialized.", .{});
            } else |err| {
                sdk.misc.error_context.append("Failed to de-initialize process input hook.", .{});
                sdk.misc.error_context.logError(err);
            }
        }

        fn onT7Tick(use_fixed_step: sdk.memory.Boolean(.{}), delta_time: f32) callconv(.c) void {
            cancel_requirements = .{};
            tick_hook.original.?(use_fixed_step, delta_time);
            onTick();
        }

        fn onT8Tick(param_1: u64, use_fixed_step: sdk.memory.Boolean(.{}), delta_time: f32, param_4: u8) callconv(.c) void {
            cancel_requirements = .{};
            tick_hook.original.?(param_1, use_fixed_step, delta_time, param_4);
            onTick();
        }

        fn onT7ProcessInput(
            player: sdk.memory.Pointer(game.Player(.t7)),
            player_side: game.PlayerSide,
            down_input: game.Input(.t7),
            press_input: game.Input(.t7),
        ) callconv(.c) void {
            var new_down_input = down_input;
            var new_press_input = press_input;
            applyInputOverride(player, player_side, &new_down_input, &new_press_input);
            process_input_hook.original.?(player, player_side, new_down_input, new_press_input);
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
            var new_down_input = down_input;
            var new_press_input = press_input;
            applyInputOverride(player, player_side, &new_down_input, &new_press_input);
            process_input_hook.original.?(
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
            const requirement = param_1.*;
            switch (requirement) {
                .throw_escape_press_1 => cancel_requirements.throw_escape_press_1 = true,
                .throw_escape_press_2 => cancel_requirements.throw_escape_press_2 = true,
                .throw_escape_press_1_plus_2 => cancel_requirements.throw_escape_press_1_plus_2 = true,
                .throw_escape_hold => cancel_requirements.throw_escape_hold = true,
                else => {},
            }
            return cancel_requirements_hook.original.?(param_1, param_2, param_3);
        }

        fn onSetRenderTargets(this: usize, param_1: usize, param_2: u32, param_3: usize) callconv(.c) void {
            render_targets_hook.original.?(this, param_1, param_2, param_3);
            if (param_3 == 0) {
                return;
            }
            const trail = sdk.memory.PointerTrail.fromArray(.{ param_3 +| 0x48, 0x20, 0x0 });
            depth_buffer_address = trail.resolve() orelse 0;
        }

        fn onT7GetViewPoint(
            this: *const anyopaque,
            out_view_info: *game.ViewInfo(.t7),
            stereo_pass: u32,
        ) callconv(.c) void {
            get_view_point_hook.original.?(this, out_view_info, stereo_pass);
            applyCameraOverride(out_view_info);
        }

        fn onT8GetViewPoint(this: *const anyopaque, out_view_info: *game.ViewInfo(.t8)) callconv(.c) void {
            get_view_point_hook.original.?(this, out_view_info);
            applyCameraOverride(out_view_info);
        }

        fn applyCameraOverride(out_view_info: *game.ViewInfo(game_id)) void {
            last_original_view_info = out_view_info.*;
            if (camera_override) |*camera| {
                out_view_info.position.setConverted(camera.position);
                out_view_info.rotation.setConverted(.fromArray(.{ camera.pitch, camera.yaw, camera.roll }));
                out_view_info.horizontal_fov.setConverted(camera.horizontal_fov);
                if (game_id == .t8) {
                    out_view_info.desired_horizontal_fov.setConverted(camera.horizontal_fov);
                }
            }
            last_overridden_view_info = out_view_info.*;
        }
    };
}

const testing = std.testing;

test "should call onTick and original when tick function is called in T7" {
    const Tick = struct {
        var times_called: usize = 0;
        var last_use_fixed_step: ?sdk.memory.Boolean(.{}) = null;
        var last_delta_time: ?f32 = null;
        fn call(use_fixed_step: sdk.memory.Boolean(.{}), delta_time: f32) callconv(.c) void {
            times_called += 1;
            last_use_fixed_step = use_fixed_step;
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
    defer hooks.deinit(testing.io);

    try testing.expectEqual(0, Tick.times_called);
    try testing.expectEqual(0, OnTick.times_called);
    Tick.call(.false, 0.25);
    try testing.expectEqual(1, Tick.times_called);
    try testing.expectEqual(.false, Tick.last_use_fixed_step);
    try testing.expectEqual(0.25, Tick.last_delta_time);
    try testing.expectEqual(1, OnTick.times_called);
}

test "should call onTick and original when tick function is called in T8" {
    const Tick = struct {
        var times_called: usize = 0;
        var last_param_1: ?u64 = null;
        var last_use_fixed_step: ?sdk.memory.Boolean(.{}) = null;
        var last_delta_time: ?f32 = null;
        var last_param_4: ?u8 = null;
        fn call(param_1: u64, use_fixed_step: sdk.memory.Boolean(.{}), delta_time: f32, param_4: u8) callconv(.c) void {
            times_called += 1;
            last_param_1 = param_1;
            last_use_fixed_step = use_fixed_step;
            last_delta_time = delta_time;
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
    Tick.call(2, .false, 0.25, 5);
    try testing.expectEqual(1, Tick.times_called);
    try testing.expectEqual(2, Tick.last_param_1);
    try testing.expectEqual(.false, Tick.last_use_fixed_step);
    try testing.expectEqual(0.25, Tick.last_delta_time);
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
        fn call(_: sdk.memory.Boolean(.{}), _: f32) callconv(.c) void {}
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
    Tick.call(.true, 0);
    try testing.expectEqual(game.CancelRequirements{}, hooks.cancel_requirements);
}

test "should reset cancel_requirements when tick function is called in T8" {
    const Tick = struct {
        fn call(_: u64, _: sdk.memory.Boolean(.{}), _: f32, _: u8) callconv(.c) void {}
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
    Tick.call(2, .true, 0, 5);
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

test "should call original and apply camera override when get view point function is called in T7" {
    const ViewInfo = game.ViewInfo(.t7);
    const GetViewPoint = struct {
        var times_called: usize = 0;
        var last_this: ?*const anyopaque = null;
        var last_stereo_pass: ?u32 = null;
        fn call(this: *const anyopaque, out_view_info: *ViewInfo, stereo_pass: u32) callconv(.c) void {
            times_called += 1;
            last_this = this;
            last_stereo_pass = stereo_pass;
            out_view_info.* = .{
                .position = .fromRaw(.fromArray(.{ 1, 2, 3 })),
                .rotation = .fromRaw(.fromArray(.{ 4, 5, 6 })),
                .horizontal_fov = .fromRaw(7),
            };
        }
    };
    const OnTick = struct {
        fn call() void {}
    };
    const hooks = Hooks(.t7, OnTick.call);

    try sdk.memory.hooking.init();
    defer sdk.memory.hooking.deinit() catch @panic("Failed to de-initialize hooking.");
    hooks.init(&.{ .getViewPoint = GetViewPoint.call });
    defer hooks.deinit(testing.io);

    const this_value: u8 = 0;
    const this: *const anyopaque = &this_value;
    var view_info = ViewInfo{};

    hooks.camera_override = null;
    GetViewPoint.call(this, &view_info, 1);
    try testing.expectEqual(1, GetViewPoint.times_called);
    try testing.expectEqual(this, GetViewPoint.last_this);
    try testing.expectEqual(1, GetViewPoint.last_stereo_pass);
    try testing.expectEqual(ViewInfo{
        .position = .fromRaw(.fromArray(.{ 1, 2, 3 })),
        .rotation = .fromRaw(.fromArray(.{ 4, 5, 6 })),
        .horizontal_fov = .fromRaw(7),
    }, view_info);
    try testing.expectEqual(ViewInfo{
        .position = .fromRaw(.fromArray(.{ 1, 2, 3 })),
        .rotation = .fromRaw(.fromArray(.{ 4, 5, 6 })),
        .horizontal_fov = .fromRaw(7),
    }, hooks.last_original_view_info);
    try testing.expectEqual(ViewInfo{
        .position = .fromRaw(.fromArray(.{ 1, 2, 3 })),
        .rotation = .fromRaw(.fromArray(.{ 4, 5, 6 })),
        .horizontal_fov = .fromRaw(7),
    }, hooks.last_overridden_view_info);

    hooks.camera_override = .{
        .position = .fromArray(.{ 11, 12, 13 }),
        .pitch = 0.5 * std.math.pi,
        .yaw = std.math.pi,
        .roll = -0.25 * std.math.pi,
        .horizontal_fov = 0.5 * std.math.pi,
    };
    GetViewPoint.call(this, &view_info, 2);
    try testing.expectEqual(2, GetViewPoint.times_called);
    try testing.expectEqual(this, GetViewPoint.last_this);
    try testing.expectEqual(2, GetViewPoint.last_stereo_pass);
    try testing.expectEqual(sdk.math.Vec3.fromArray(.{ 11, 12, 13 }), view_info.position.raw);
    try testing.expectApproxEqAbs(90, view_info.rotation.raw.x(), 0.0001);
    try testing.expectApproxEqAbs(180, view_info.rotation.raw.y(), 0.0001);
    try testing.expectApproxEqAbs(-45, view_info.rotation.raw.z(), 0.0001);
    try testing.expectApproxEqAbs(90, view_info.horizontal_fov.raw, 0.0001);
    try testing.expectEqual(ViewInfo{
        .position = .fromRaw(.fromArray(.{ 1, 2, 3 })),
        .rotation = .fromRaw(.fromArray(.{ 4, 5, 6 })),
        .horizontal_fov = .fromRaw(7),
    }, hooks.last_original_view_info);
    try testing.expectEqual(view_info, hooks.last_overridden_view_info);
}

test "should call original and apply camera override when get view point function is called in T8" {
    const ViewInfo = game.ViewInfo(.t8);
    const GetViewPoint = struct {
        var times_called: usize = 0;
        var last_this: ?*const anyopaque = null;
        fn call(this: *const anyopaque, out_view_info: *ViewInfo) callconv(.c) void {
            times_called += 1;
            last_this = this;
            out_view_info.* = .{
                .position = .fromRaw(.fromArray(.{ 1, 2, 3 })),
                .rotation = .fromRaw(.fromArray(.{ 4, 5, 6 })),
                .horizontal_fov = .fromRaw(7),
                .desired_horizontal_fov = .fromRaw(8),
            };
        }
    };
    const OnTick = struct {
        fn call() void {}
    };
    const hooks = Hooks(.t8, OnTick.call);

    try sdk.memory.hooking.init();
    defer sdk.memory.hooking.deinit() catch @panic("Failed to de-initialize hooking.");
    hooks.init(&.{ .getViewPoint = GetViewPoint.call });
    defer hooks.deinit(testing.io);

    const this_value: u8 = 0;
    const this: *const anyopaque = &this_value;
    var view_info = ViewInfo{};

    hooks.camera_override = null;
    GetViewPoint.call(this, &view_info);
    try testing.expectEqual(1, GetViewPoint.times_called);
    try testing.expectEqual(this, GetViewPoint.last_this);
    try testing.expectEqual(ViewInfo{
        .position = .fromRaw(.fromArray(.{ 1, 2, 3 })),
        .rotation = .fromRaw(.fromArray(.{ 4, 5, 6 })),
        .horizontal_fov = .fromRaw(7),
        .desired_horizontal_fov = .fromRaw(8),
    }, view_info);
    try testing.expectEqual(ViewInfo{
        .position = .fromRaw(.fromArray(.{ 1, 2, 3 })),
        .rotation = .fromRaw(.fromArray(.{ 4, 5, 6 })),
        .horizontal_fov = .fromRaw(7),
        .desired_horizontal_fov = .fromRaw(8),
    }, hooks.last_original_view_info);
    try testing.expectEqual(ViewInfo{
        .position = .fromRaw(.fromArray(.{ 1, 2, 3 })),
        .rotation = .fromRaw(.fromArray(.{ 4, 5, 6 })),
        .horizontal_fov = .fromRaw(7),
        .desired_horizontal_fov = .fromRaw(8),
    }, hooks.last_overridden_view_info);

    hooks.camera_override = .{
        .position = .fromArray(.{ 11, 12, 13 }),
        .pitch = 0.5 * std.math.pi,
        .yaw = std.math.pi,
        .roll = -0.25 * std.math.pi,
        .horizontal_fov = 0.5 * std.math.pi,
    };
    GetViewPoint.call(this, &view_info);
    try testing.expectEqual(2, GetViewPoint.times_called);
    try testing.expectEqual(this, GetViewPoint.last_this);
    try testing.expectEqual(sdk.math.Vector(3, f64).fromArray(.{ 11, 12, 13 }), view_info.position.raw);
    try testing.expectApproxEqAbs(90, view_info.rotation.raw.x(), 0.0001);
    try testing.expectApproxEqAbs(180, view_info.rotation.raw.y(), 0.0001);
    try testing.expectApproxEqAbs(-45, view_info.rotation.raw.z(), 0.0001);
    try testing.expectApproxEqAbs(90, view_info.horizontal_fov.raw, 0.0001);
    try testing.expectApproxEqAbs(90, view_info.desired_horizontal_fov.raw, 0.0001);
    try testing.expectEqual(ViewInfo{
        .position = .fromRaw(.fromArray(.{ 1, 2, 3 })),
        .rotation = .fromRaw(.fromArray(.{ 4, 5, 6 })),
        .horizontal_fov = .fromRaw(7),
        .desired_horizontal_fov = .fromRaw(8),
    }, hooks.last_original_view_info);
    try testing.expectEqual(view_info, hooks.last_overridden_view_info);
}
