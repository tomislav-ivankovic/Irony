const std = @import("std");
const builtin = @import("builtin");
const misc = @import("../misc/root.zig");
const c = @cImport({
    @cInclude("MinHook.h");
});

pub const hooking = struct {
    var test_allocation: if (builtin.is_test) ?*u8 else void = if (builtin.is_test) null else {};

    pub fn init() !void {
        const status = c.MH_Initialize();
        if (status != c.MH_OK) {
            const err = minHookStatusToError(status);
            misc.errorContext().newFmt(err, "MH_Initialize returned: {}", .{status});
            return err;
        }
        if (builtin.is_test) {
            if (test_allocation != null) {
                @panic("Hooking was initialized twice.");
            }
            test_allocation = try std.testing.allocator.create(u8);
        }
    }

    pub fn deinit() !void {
        const status = c.MH_Uninitialize();
        if (status != c.MH_OK) {
            const err = minHookStatusToError(status);
            misc.errorContext().newFmt(err, "MH_Uninitialize returned: {}", .{status});
            return err;
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
    _ = switch (@typeInfo(Function)) {
        .Fn => |f| f,
        else => @compileError("Hook's Function must be a function type."),
    };

    return struct {
        target: *const Function,
        detour: *const Function,
        original: *const Function,
        test_allocation: if (builtin.is_test) *u8 else void,

        const Self = @This();

        pub fn create(target: *const Function, detour: *const Function) !Self {
            var original: *Function = undefined;
            const status = c.MH_CreateHook(@constCast(target), @constCast(detour), @ptrCast(&original));
            if (status != c.MH_OK) {
                const err = minHookStatusToError(status);
                misc.errorContext().newFmt(err, "MH_CreateHook returned: {}", .{status});
                return err;
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
            const status = c.MH_RemoveHook(@constCast(self.target));
            if (status != c.MH_OK) {
                const err = minHookStatusToError(status);
                misc.errorContext().newFmt(err, "MH_RemoveHook returned: {}", .{status});
                return err;
            }
            if (builtin.is_test) {
                std.testing.allocator.destroy(self.test_allocation);
            }
        }

        pub fn enable(self: *const Self) !void {
            const status = c.MH_EnableHook(@constCast(self.target));
            if (status != c.MH_OK) {
                const err = minHookStatusToError(status);
                misc.errorContext().newFmt(err, "MH_EnableHook returned: {}", .{status});
                return err;
            }
        }

        pub fn disable(self: *const Self) !void {
            const status = c.MH_DisableHook(@constCast(self.target));
            if (status != c.MH_OK) {
                const err = minHookStatusToError(status);
                misc.errorContext().newFmt(err, "MH_DisableHook returned: {}", .{status});
                return err;
            }
        }
    };
}

fn minHookStatusToError(status: c.MH_STATUS) anyerror {
    return switch (status) {
        c.MH_ERROR_ALREADY_INITIALIZED => error.HookingAlreadyInitialized,
        c.MH_ERROR_NOT_INITIALIZED => error.HookingNotInitialized,
        c.MH_ERROR_ALREADY_CREATED => error.HookAlreadyCreated,
        c.MH_ERROR_NOT_CREATED => error.HookNotCreated,
        c.MH_ERROR_ENABLED => error.HookEnabled,
        c.MH_ERROR_DISABLED => error.HookDisabled,
        c.MH_ERROR_NOT_EXECUTABLE => error.MemoryNotExecutable,
        c.MH_ERROR_UNSUPPORTED_FUNCTION => error.UnsupportedFunction,
        c.MH_ERROR_MEMORY_ALLOC => error.MemoryAllocationFailed,
        c.MH_ERROR_MEMORY_PROTECT => error.MemoryProtectionChangeFailed,
        c.MH_ERROR_MODULE_NOT_FOUND => error.ModuleNotFound,
        c.MH_ERROR_FUNCTION_NOT_FOUND => error.FunctionNotFound,
        else => error.Unknown,
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

test "minHookStatusToError should return correct value" {
    const testCase = struct {
        fn call(status: c.MH_STATUS, expected_error: anyerror) !void {
            try testing.expectEqual(expected_error, minHookStatusToError(status));
        }
    }.call;
    try testCase(c.MH_ERROR_ALREADY_INITIALIZED, error.HookingAlreadyInitialized);
    try testCase(c.MH_ERROR_NOT_INITIALIZED, error.HookingNotInitialized);
    try testCase(c.MH_ERROR_ALREADY_CREATED, error.HookAlreadyCreated);
    try testCase(c.MH_ERROR_NOT_CREATED, error.HookNotCreated);
    try testCase(c.MH_ERROR_ENABLED, error.HookEnabled);
    try testCase(c.MH_ERROR_DISABLED, error.HookDisabled);
    try testCase(c.MH_ERROR_NOT_EXECUTABLE, error.MemoryNotExecutable);
    try testCase(c.MH_ERROR_UNSUPPORTED_FUNCTION, error.UnsupportedFunction);
    try testCase(c.MH_ERROR_MEMORY_ALLOC, error.MemoryAllocationFailed);
    try testCase(c.MH_ERROR_MEMORY_PROTECT, error.MemoryProtectionChangeFailed);
    try testCase(c.MH_ERROR_MODULE_NOT_FOUND, error.ModuleNotFound);
    try testCase(c.MH_ERROR_FUNCTION_NOT_FOUND, error.FunctionNotFound);
    try testCase(c.MH_OK, error.Unknown);
}
