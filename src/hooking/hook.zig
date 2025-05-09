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

pub fn Hook(comptime Function: type) type {
    switch (@typeInfo(Function)) {
        .@"fn" => {},
        else => @compileError("Hook's Function must be a function type."),
    }

    return struct {
        target: *const Function,
        detour: *const Function,
        original: *const Function,
        test_allocation: if (builtin.is_test) *u8 else void,

        const Self = @This();

        pub fn create(target: *const Function, detour: *const Function) !Self {
            var original: *Function = undefined;
            const status = minhook.MH_CreateHook(@constCast(target), @constCast(detour), @ptrCast(&original));
            if (status != minhook.MH_OK) {
                misc.error_context.new("{s}", .{minHookStatusToDescription(status)});
                misc.error_context.append("MH_CreateHook returned: {}", .{status});
                return minHookStatusToError(status);
            }
            const test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {};
            return Self{
                .target = target,
                .detour = detour,
                .original = original,
                .test_allocation = test_allocation,
            };
        }

        pub fn destroy(self: *const Self) !void {
            const status = minhook.MH_RemoveHook(@constCast(self.target));
            if (status != minhook.MH_OK) {
                misc.error_context.new("{s}", .{minHookStatusToDescription(status)});
                misc.error_context.append("MH_RemoveHook returned: {}", .{status});
                return minHookStatusToError(status);
            }
            if (builtin.is_test) {
                std.testing.allocator.destroy(self.test_allocation);
            }
        }

        pub fn enable(self: *const Self) !void {
            const status = minhook.MH_EnableHook(@constCast(self.target));
            if (status != minhook.MH_OK) {
                misc.error_context.new("{s}", .{minHookStatusToDescription(status)});
                misc.error_context.append("MH_EnableHook returned: {}", .{status});
                return minHookStatusToError(status);
            }
        }

        pub fn disable(self: *const Self) !void {
            const status = minhook.MH_DisableHook(@constCast(self.target));
            if (status != minhook.MH_OK) {
                misc.error_context.new("{s}", .{minHookStatusToDescription(status)});
                misc.error_context.append("MH_DisableHook returned: {}", .{status});
                return minHookStatusToError(status);
            }
        }
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

test "target should get called when hook is disabled" {
    try hooking.init();
    defer hooking.deinit() catch @panic("Failed to de-initialize hooks.");

    const Target = struct {
        var times_called: usize = 0;
        fn call(a: i32, b: i32) i32 {
            times_called += 1;
            return a + b;
        }
    };
    const Dtour = struct {
        var times_called: usize = 0;
        fn call(a: i32, b: i32) i32 {
            times_called += 1;
            return a - b;
        }
    };
    const hook = try Hook(fn (i32, i32) i32).create(Target.call, Dtour.call);
    defer hook.destroy() catch @panic("Failed to destroy hook.");

    const return_value = Target.call(3, 2);
    try testing.expectEqual(1, Target.times_called);
    try testing.expectEqual(0, Dtour.times_called);
    try testing.expectEqual(5, return_value);
}

test "detour should get called when hook is enabled" {
    try hooking.init();
    defer hooking.deinit() catch @panic("Failed to de-initialize hooks.");

    const Target = struct {
        var times_called: usize = 0;
        fn call(a: i32, b: i32) i32 {
            times_called += 1;
            return a + b;
        }
    };
    const Dtour = struct {
        var times_called: usize = 0;
        fn call(a: i32, b: i32) i32 {
            times_called += 1;
            return a - b;
        }
    };
    const hook = try Hook(fn (i32, i32) i32).create(Target.call, Dtour.call);
    defer hook.destroy() catch @panic("Failed to destroy hook.");
    try hook.enable();

    const return_value = Target.call(3, 2);
    try testing.expectEqual(0, Target.times_called);
    try testing.expectEqual(1, Dtour.times_called);
    try testing.expectEqual(1, return_value);
}

test "original should still call target implementation even when hook is enabled" {
    try hooking.init();
    defer hooking.deinit() catch @panic("Failed to de-initialize hooks.");

    const Target = struct {
        var times_called: usize = 0;
        fn call(a: i32, b: i32) i32 {
            times_called += 1;
            return a + b;
        }
    };
    const Dtour = struct {
        var times_called: usize = 0;
        fn call(a: i32, b: i32) i32 {
            times_called += 1;
            return a - b;
        }
    };
    const hook = try Hook(fn (i32, i32) i32).create(Target.call, Dtour.call);
    defer hook.destroy() catch @panic("Failed to destroy hook.");
    try hook.enable();

    const return_value = hook.original(3, 2);
    try testing.expectEqual(1, Target.times_called);
    try testing.expectEqual(0, Dtour.times_called);
    try testing.expectEqual(5, return_value);
}
