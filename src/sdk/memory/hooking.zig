const std = @import("std");
const builtin = @import("builtin");
const misc = @import("../misc/root.zig");
const minhook = @import("minhook");

pub const hooking = struct {
    var test_allocation: if (builtin.is_test) ?*u8 else void = if (builtin.is_test) null else {};

    pub fn init() !void {
        const status = minhook.MH_Initialize();
        if (status != minhook.MH_OK) {
            misc.error_context.new("{s}", .{minHookStatusToDescription(status)});
            misc.error_context.append("MH_Initialize returned: {}", .{status});
            return minHookStatusToError(status);
        }
        if (builtin.is_test) {
            if (test_allocation != null) {
                @panic("Hooking was initialized twice.");
            }
            test_allocation = try std.testing.allocator.create(u8);
        }
    }

    pub fn deinit() !void {
        const status = minhook.MH_Uninitialize();
        if (status != minhook.MH_OK) {
            misc.error_context.new("{s}", .{minHookStatusToDescription(status)});
            misc.error_context.append("MH_Uninitialize returned: {}", .{status});
            return minHookStatusToError(status);
        }
        if (builtin.is_test) {
            if (test_allocation) |allocation| {
                std.testing.allocator.destroy(allocation);
                test_allocation = null;
            } else {
                @panic("Hooking was de-initialized without being initialized.");
            }
        }
    }
};

pub fn Hook(comptime Function: type, comptime detour: *const Function) type {
    return struct {
        pub var original: ?*const Function = null;
        pub var target: ?*const Function = null;
        var active_calls = std.atomic.Value(u32).init(0);
        var test_allocation: if (builtin.is_test) ?*u8 else void = if (builtin.is_test) null else {};

        pub fn init(targetFunction: *const Function) !void {
            if (target != null) {
                misc.error_context.new("The hook is already initialized.", .{});
                return error.HookAlreadyInitialized;
            }
            create(targetFunction) catch |err| {
                misc.error_context.append("Failed to create the hook.", .{});
                return err;
            };
            errdefer {
                const saved = misc.error_context.save();
                defer misc.error_context.restore(&saved);
                destroy(targetFunction) catch |err| {
                    misc.error_context.append("Failed to destroy the hook.", .{});
                    misc.error_context.logError(err);
                };
            }
            enable(targetFunction) catch |err| {
                misc.error_context.append("Failed to enable the hook.", .{});
                return err;
            };
            target = targetFunction;
        }

        pub fn deinit(io: std.Io) !void {
            const targetFunction = target orelse return;
            const disable_attempts = 10;
            for (0..disable_attempts) |attempt| {
                if (disable(targetFunction)) {
                    break;
                } else |err| switch (err) {
                    error.HookDisabled => break,
                    else => {
                        misc.error_context.append("Failed to disable the hook.", .{});
                        if (attempt == disable_attempts - 1) {
                            return err;
                        }
                        misc.error_context.logWarning(err);
                        io.sleep(.fromMilliseconds(10), .awake) catch |sleep_err| {
                            misc.error_context.new("Failed to sleep for 10 ms before retrying to disable.", .{});
                            misc.error_context.logError(sleep_err);
                        };
                    },
                }
            }
            while (active_calls.load(.seq_cst) > 0) {
                io.sleep(.fromMilliseconds(10), .awake) catch |err| {
                    misc.error_context.new("Failed to sleep for 10 ms while waiting on active hook calls.", .{});
                    misc.error_context.logError(err);
                };
            }
            destroy(targetFunction) catch |err| {
                misc.error_context.append("Failed to destroy the hook.", .{});
                return err;
            };
            target = null;
        }

        pub fn isInitialized() bool {
            return target != null;
        }

        fn create(targetFunction: *const Function) !void {
            var originalFunction: *Function = undefined;
            const status = minhook.MH_CreateHook(
                @constCast(targetFunction),
                @constCast(wrapper),
                @ptrCast(&originalFunction),
            );
            if (status != minhook.MH_OK) {
                misc.error_context.new("{s}", .{minHookStatusToDescription(status)});
                misc.error_context.append("MH_CreateHook returned: {}", .{status});
                return minHookStatusToError(status);
            }
            errdefer _ = minhook.MH_RemoveHook(@constCast(targetFunction));
            if (builtin.is_test) {
                test_allocation = std.testing.allocator.create(u8) catch |err| {
                    misc.error_context.new("Failed to allocate the testing allocation.", .{});
                    return err;
                };
            }
            original = originalFunction;
        }

        fn destroy(targetFunction: *const Function) !void {
            const status = minhook.MH_RemoveHook(@constCast(targetFunction));
            if (status != minhook.MH_OK) {
                misc.error_context.new("{s}", .{minHookStatusToDescription(status)});
                misc.error_context.append("MH_RemoveHook returned: {}", .{status});
                return minHookStatusToError(status);
            }
            original = null;
            if (builtin.is_test) {
                std.testing.allocator.destroy(test_allocation.?);
                test_allocation = null;
            }
        }

        fn enable(targetFunction: *const Function) !void {
            const status = minhook.MH_EnableHook(@constCast(targetFunction));
            if (status != minhook.MH_OK) {
                misc.error_context.new("{s}", .{minHookStatusToDescription(status)});
                misc.error_context.append("MH_EnableHook returned: {}", .{status});
                return minHookStatusToError(status);
            }
        }

        fn disable(targetFunction: *const Function) !void {
            const status = minhook.MH_DisableHook(@constCast(targetFunction));
            if (status != minhook.MH_OK) {
                misc.error_context.new("{s}", .{minHookStatusToDescription(status)});
                misc.error_context.append("MH_DisableHook returned: {}", .{status});
                return minHookStatusToError(status);
            }
        }

        const wrapper: *const Function = block: {
            const info = switch (@typeInfo(Function)) {
                .@"fn" => |info| info,
                else => @compileError("Hook's Function must be a function type."),
            };
            if (info.is_generic or info.attrs.varargs) {
                @compileError("Hook's Function must not be generic or variadic.");
            }
            const R = info.return_type.?;
            const cc = info.attrs.@"callconv";
            const P = struct {
                fn ParameterType(comptime index: usize) type {
                    return info.param_types[index].?;
                }
            }.ParameterType;
            const Impl = struct {
                inline fn implementation(args: anytype) R {
                    _ = active_calls.fetchAdd(1, .seq_cst);
                    defer _ = active_calls.fetchSub(1, .seq_cst);
                    return @call(.auto, detour, args);
                }
                fn f0() callconv(cc) R {
                    return implementation(.{});
                }
                fn f1(p0: P(0)) callconv(cc) R {
                    return implementation(.{p0});
                }
                fn f2(p0: P(0), p1: P(1)) callconv(cc) R {
                    return implementation(.{ p0, p1 });
                }
                fn f3(p0: P(0), p1: P(1), p2: P(2)) callconv(cc) R {
                    return implementation(.{ p0, p1, p2 });
                }
                fn f4(p0: P(0), p1: P(1), p2: P(2), p3: P(3)) callconv(cc) R {
                    return implementation(.{ p0, p1, p2, p3 });
                }
                fn f5(p0: P(0), p1: P(1), p2: P(2), p3: P(3), p4: P(4)) callconv(cc) R {
                    return implementation(.{ p0, p1, p2, p3, p4 });
                }
                fn f6(p0: P(0), p1: P(1), p2: P(2), p3: P(3), p4: P(4), p5: P(5)) callconv(cc) R {
                    return implementation(.{ p0, p1, p2, p3, p4, p5 });
                }
                fn f7(p0: P(0), p1: P(1), p2: P(2), p3: P(3), p4: P(4), p5: P(5), p6: P(6)) callconv(cc) R {
                    return implementation(.{ p0, p1, p2, p3, p4, p5, p6 });
                }
                fn f8(p0: P(0), p1: P(1), p2: P(2), p3: P(3), p4: P(4), p5: P(5), p6: P(6), p7: P(7)) callconv(cc) R {
                    return implementation(.{ p0, p1, p2, p3, p4, p5, p6, p7 });
                }
            };
            break :block switch (info.param_types.len) {
                0 => &Impl.f0,
                1 => &Impl.f1,
                2 => &Impl.f2,
                3 => &Impl.f3,
                4 => &Impl.f4,
                5 => &Impl.f5,
                6 => &Impl.f6,
                7 => &Impl.f7,
                8 => &Impl.f8,
                else => @compileError("Hook's Function can have at most 8 parameters."),
            };
        };
    };
}

fn minHookStatusToError(status: minhook.MH_STATUS) anyerror {
    return switch (status) {
        minhook.MH_ERROR_ALREADY_INITIALIZED => error.HookingAlreadyInitialized,
        minhook.MH_ERROR_NOT_INITIALIZED => error.HookingNotInitialized,
        minhook.MH_ERROR_ALREADY_CREATED => error.HookAlreadyCreated,
        minhook.MH_ERROR_NOT_CREATED => error.HookNotCreated,
        minhook.MH_ERROR_ENABLED => error.HookEnabled,
        minhook.MH_ERROR_DISABLED => error.HookDisabled,
        minhook.MH_ERROR_NOT_EXECUTABLE => error.MemoryNotExecutable,
        minhook.MH_ERROR_UNSUPPORTED_FUNCTION => error.UnsupportedFunction,
        minhook.MH_ERROR_MEMORY_ALLOC => error.MemoryAllocationFailed,
        minhook.MH_ERROR_MEMORY_PROTECT => error.MemoryProtectionChangeFailed,
        minhook.MH_ERROR_MODULE_NOT_FOUND => error.ModuleNotFound,
        minhook.MH_ERROR_FUNCTION_NOT_FOUND => error.FunctionNotFound,
        else => error.Unknown,
    };
}

fn minHookStatusToDescription(status: minhook.MH_STATUS) [:0]const u8 {
    return switch (status) {
        minhook.MH_ERROR_ALREADY_INITIALIZED => "MinHook is already initialized.",
        minhook.MH_ERROR_NOT_INITIALIZED => "MinHook is not initialized yet, or already uninitialized.",
        minhook.MH_ERROR_ALREADY_CREATED => "The hook for the specified target function is already created.",
        minhook.MH_ERROR_NOT_CREATED => "The hook for the specified target function is not created yet.",
        minhook.MH_ERROR_ENABLED => "The hook for the specified target function is already enabled.",
        minhook.MH_ERROR_DISABLED => "The hook for the specified target function is not enabled yet, or already disabled.",
        minhook.MH_ERROR_NOT_EXECUTABLE => "The specified pointer is invalid. It points the address of non-allocated and/or non-executable region.",
        minhook.MH_ERROR_UNSUPPORTED_FUNCTION => "The specified target function cannot be hooked.",
        minhook.MH_ERROR_MEMORY_ALLOC => "Failed to allocate memory.",
        minhook.MH_ERROR_MEMORY_PROTECT => "Failed to change the memory protection.",
        minhook.MH_ERROR_MODULE_NOT_FOUND => "The specified module is not loaded.",
        minhook.MH_ERROR_FUNCTION_NOT_FOUND => "The specified function is not found.",
        else => "Unknown error.",
    };
}

const testing = std.testing;

test "initializing and de-initializing hooking should succeed" {
    try hooking.init();
    try hooking.deinit();
}

test "detour should get called when hook is initialized" {
    try hooking.init();
    defer hooking.deinit() catch @panic("Failed to de-initialize hooks.");

    const Target = struct {
        var times_called: usize = 0;
        fn call(a: i32, b: i32) i32 {
            times_called += 1;
            return a + b;
        }
    };
    const Detour = struct {
        var times_called: usize = 0;
        fn call(a: i32, b: i32) i32 {
            times_called += 1;
            return a - b;
        }
    };
    const hook = Hook(fn (i32, i32) i32, Detour.call);
    try hook.init(Target.call);
    defer hook.deinit(testing.io) catch @panic("Failed to de-initialize hook.");

    const return_value = Target.call(3, 2);
    try testing.expectEqual(0, Target.times_called);
    try testing.expectEqual(1, Detour.times_called);
    try testing.expectEqual(1, return_value);
}

test "original should still call target implementation even when hook is initialized" {
    try hooking.init();
    defer hooking.deinit() catch @panic("Failed to de-initialize hooks.");

    const Target = struct {
        var times_called: usize = 0;
        fn call(a: i32, b: i32) i32 {
            times_called += 1;
            return a + b;
        }
    };
    const Detour = struct {
        var times_called: usize = 0;
        fn call(a: i32, b: i32) i32 {
            times_called += 1;
            return a - b;
        }
    };
    const hook = Hook(fn (i32, i32) i32, Detour.call);
    try hook.init(Target.call);
    defer hook.deinit(testing.io) catch @panic("Failed to de-initialize hook.");

    const return_value = hook.original.?(3, 2);
    try testing.expectEqual(1, Target.times_called);
    try testing.expectEqual(0, Detour.times_called);
    try testing.expectEqual(5, return_value);
}

test "target should get called after hook is de-initialized" {
    try hooking.init();
    defer hooking.deinit() catch @panic("Failed to de-initialize hooks.");

    const Target = struct {
        var times_called: usize = 0;
        fn call(a: i32, b: i32) i32 {
            times_called += 1;
            return a + b;
        }
    };
    const Detour = struct {
        var times_called: usize = 0;
        fn call(a: i32, b: i32) i32 {
            times_called += 1;
            return a - b;
        }
    };
    const hook = Hook(fn (i32, i32) i32, Detour.call);
    try hook.init(Target.call);
    try hook.deinit(testing.io);

    const return_value = Target.call(3, 2);
    try testing.expectEqual(1, Target.times_called);
    try testing.expectEqual(0, Detour.times_called);
    try testing.expectEqual(5, return_value);
}

test "init should fail when hook is already initialized" {
    try hooking.init();
    defer hooking.deinit() catch @panic("Failed to de-initialize hooks.");

    const Target = struct {
        fn call(a: i32, b: i32) i32 {
            return a + b;
        }
    };
    const Detour = struct {
        fn call(a: i32, b: i32) i32 {
            return a - b;
        }
    };
    const hook = Hook(fn (i32, i32) i32, Detour.call);
    try hook.init(Target.call);
    defer hook.deinit(testing.io) catch @panic("Failed to de-initialize hook.");

    try testing.expectError(error.HookAlreadyInitialized, hook.init(Target.call));
}
