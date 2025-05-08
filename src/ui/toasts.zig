const std = @import("std");
const builtin = @import("builtin");
const imgui = @import("imgui");
const misc = @import("../misc/root.zig");
const ui = @import("root.zig");

pub const ToastType = union(enum) {
    default,
    info,
    success,
    warn,
    err,
    custom: imgui.ImVec4,

    const Self = @This();

    pub fn getColor(self: Self) imgui.ImVec4 {
        return switch (self) {
            .default => .{ .x = 1, .y = 1, .z = 1, .w = 1 },
            .info => .{ .x = 0, .y = 1, .z = 1, .w = 1 },
            .success => .{ .x = 0.5, .y = 1, .z = 0.5, .w = 1 },
            .warn => .{ .x = 1, .y = 1, .z = 0, .w = 1 },
            .err => .{ .x = 1, .y = 0.5, .z = 0.5, .w = 1 },
            .custom => |color| color,
        };
    }
};

const Toast = struct {
    message: [:0]const u8,
    color: imgui.ImVec4,
    duration: f32,
    life_time: f32,

    const Self = @This();

    pub fn getBufferRegion(self: *const Self) []const u8 {
        const message = self.message;
        return message[0..(message.len + 1)];
    }
};

pub const ToastsConfig = struct {
    buffer_size: usize = 2048,
    max_toasts: usize = 32,
    margin: f32 = 8.0,
    default_duration: f32 = 5.0,
    fly_in_time: f32 = 0.15,
    fly_out_time: f32 = 0.5,
};

pub fn Toasts(comptime config: ToastsConfig) type {
    return struct {
        var toasts = misc.CircularBuffer(config.max_toasts, Toast){};
        var buffer: [config.buffer_size]u8 = undefined;
        var mutex = std.Thread.Mutex{};

        pub fn send(toast_type: ToastType, duration: ?f32, comptime fmt: []const u8, args: anytype) void {
            mutex.lock();
            defer mutex.unlock();
            const last_toast = toasts.getLast() catch {
                addToast(&buffer, toast_type, duration, fmt, args) catch return;
                return;
            };
            const last_buffer_region = last_toast.getBufferRegion();
            const start_index = (&last_buffer_region[0] - &buffer[0]) + last_buffer_region.len;
            addToast(buffer[start_index..], toast_type, duration, fmt, args) catch {
                addToast(&buffer, toast_type, duration, fmt, args) catch return;
            };
        }

        fn addToast(
            write_region: []u8,
            toast_type: ToastType,
            duration: ?f32,
            comptime fmt: []const u8,
            args: anytype,
        ) !void {
            const message = std.fmt.bufPrintZ(write_region, fmt, args) catch |err| {
                clearBufferRegion(write_region);
                return err;
            };
            const toast = Toast{
                .message = message,
                .color = toast_type.getColor(),
                .duration = duration orelse config.default_duration,
                .life_time = 0.0,
            };
            clearBufferRegion(toast.getBufferRegion());
            _ = toasts.addToBack(toast);
        }

        fn clearBufferRegion(region: []const u8) void {
            while (toasts.getFirst() catch null) |toast| {
                if (!collides(toast.getBufferRegion(), region)) {
                    break;
                }
                _ = toasts.removeFirst() catch unreachable;
            }
        }

        fn collides(a: []const u8, b: []const u8) bool {
            if (a.len == 0 or b.len == 0) {
                return false;
            }
            const a_min = @intFromPtr(&a[0]);
            const a_max = @intFromPtr(&a[a.len - 1]);
            const b_min = @intFromPtr(&b[0]);
            const b_max = @intFromPtr(&b[b.len - 1]);
            return (a_max >= b_min) and (b_max >= a_min);
        }

        pub fn update(delta_time: f32) void {
            mutex.lock();
            defer mutex.unlock();
            for (0..toasts.len) |index| {
                const toast = toasts.getMut(index) catch continue;
                toast.life_time += delta_time;
            }
            while (toasts.getFirst() catch null) |toast| {
                if (toast.life_time < toast.duration) {
                    break;
                }
                _ = toasts.removeFirst() catch unreachable;
            }
        }

        pub fn draw() void {
            mutex.lock();
            defer mutex.unlock();
            var index: usize = 0;
            var current_y: f32 = 0.0;
            for (0..toasts.len) |i| {
                const toast = toasts.get(i) catch continue;
                if (toast.life_time >= toast.duration) {
                    continue;
                }
                drawToast(toast, index, &current_y);
                index += 1;
            }
        }

        fn drawToast(toast: *const Toast, index: usize, current_y: *f32) void {
            var window_name_buffer: [32]u8 = undefined;
            const window_name = std.fmt.bufPrintZ(&window_name_buffer, "toast-{}", .{index}) catch unreachable;
            const window_flags = imgui.ImGuiWindowFlags_AlwaysAutoResize | imgui.ImGuiWindowFlags_NoDecoration | imgui.ImGuiWindowFlags_NoInputs | imgui.ImGuiWindowFlags_NoSavedSettings;

            var text_size: imgui.ImVec2 = undefined;
            imgui.igCalcTextSize(&text_size, toast.message, null, false, -1.0);
            const window_size = imgui.ImVec2{
                .x = text_size.x + (2 * imgui.igGetStyle().*.WindowPadding.x),
                .y = text_size.y + (2 * imgui.igGetStyle().*.WindowPadding.y),
            };
            const min_x = -(window_size.x + config.margin);
            const max_x = config.margin;
            const animation_factor = getToastAnimationFactor(toast);
            const window_position = imgui.ImVec2{
                .x = min_x + (animation_factor * (max_x - min_x)),
                .y = current_y.* + config.margin,
            };
            current_y.* = window_position.y + window_size.y;

            imgui.igPushStyleVar_Float(imgui.ImGuiStyleVar_WindowBorderSize, 0);
            defer imgui.igPopStyleVar(1);
            imgui.igSetNextWindowPos(window_position, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(window_size, imgui.ImGuiCond_Always);
            _ = imgui.igBegin(window_name, null, window_flags);
            defer imgui.igEnd();

            textColored(toast.color, toast.message);
        }

        fn getToastAnimationFactor(toast: *const Toast) f32 {
            if (toast.duration < config.fly_in_time + config.fly_out_time) {
                return 1.0;
            }
            if (toast.life_time < config.fly_in_time) {
                return toast.life_time / config.fly_in_time;
            }
            const remaining_life_time = toast.duration - toast.life_time;
            if (remaining_life_time < config.fly_out_time) {
                return remaining_life_time / config.fly_out_time;
            }
            return 1.0;
        }

        pub fn logFn(
            comptime level: std.log.Level,
            comptime scope: @Type(.enum_literal),
            comptime format: []const u8,
            args: anytype,
        ) void {
            _ = scope;
            const toast_type: ToastType = switch (level) {
                .err => .err,
                .warn => .warn,
                else => return,
            };
            send(toast_type, null, format, args);
        }
    };
}

fn textColored(color: imgui.ImVec4, text: [:0]const u8) void {
    if (builtin.is_test) {
        var pos: imgui.ImVec2 = undefined;
        imgui.igGetCursorScreenPos(&pos);
        var size: imgui.ImVec2 = undefined;
        imgui.igCalcTextSize(&size, text, null, false, -1.0);
        const rect = imgui.ImRect{ .Min = pos, .Max = .{ .x = pos.x + size.x, .y = pos.y + size.y } };
        imgui.teItemAdd(imgui.igGetCurrentContext(), imgui.igGetID_Str(text), &rect, null);
    }
    imgui.igTextColored(color, "%s", text.ptr);
}

const testing = std.testing;

test "should render correct messages at correct time" {
    const toasts = Toasts(.{
        .buffer_size = 2048,
        .max_toasts = 32,
        .margin = 8.0,
        .default_duration = 5.0,
        .fly_in_time = 0.0,
        .fly_out_time = 0.0,
    });
    const context = try ui.getTestingContext();
    try context.runTest(
        .{},
        struct {
            fn call(_: ui.TestContext) !void {
                toasts.draw();
            }
        }.call,
        struct {
            fn call(ctx: ui.TestContext) !void {
                toasts.send(.default, 1.0, "Message: {}", .{1});
                toasts.send(.info, null, "Message: {}", .{2});
                toasts.send(.success, 2.0, "Message: {}", .{3});
                toasts.send(.warn, 6.0, "Message: {}", .{4});
                toasts.send(.err, 3.0, "Message: {}", .{5});

                toasts.update(0.5); //t = 0.5
                ctx.yield(1);

                try testing.expect(ctx.itemExists("//toast-0/Message: 1"));
                try testing.expect(ctx.itemExists("//toast-1/Message: 2"));
                try testing.expect(ctx.itemExists("//toast-2/Message: 3"));
                try testing.expect(ctx.itemExists("//toast-3/Message: 4"));
                try testing.expect(ctx.itemExists("//toast-4/Message: 5"));
                try testing.expect(!ctx.itemExists("//toast-5"));

                toasts.update(1.0); // t = 1.5
                ctx.yield(1);

                try testing.expect(ctx.itemExists("//toast-0/Message: 2"));
                try testing.expect(ctx.itemExists("//toast-1/Message: 3"));
                try testing.expect(ctx.itemExists("//toast-2/Message: 4"));
                try testing.expect(ctx.itemExists("//toast-3/Message: 5"));
                try testing.expect(!ctx.itemExists("//toast-4"));

                toasts.update(1.0); // t = 2.5
                ctx.yield(1);

                try testing.expect(ctx.itemExists("//toast-0/Message: 2"));
                try testing.expect(ctx.itemExists("//toast-1/Message: 4"));
                try testing.expect(ctx.itemExists("//toast-2/Message: 5"));
                try testing.expect(!ctx.itemExists("//toast-3"));

                toasts.update(1.0); // t = 3.5
                toasts.send(.default, 0.5, "Message: {}", .{6}); // lasts until t = 4.0
                ctx.yield(1);

                try testing.expect(ctx.itemExists("//toast-0/Message: 2"));
                try testing.expect(ctx.itemExists("//toast-1/Message: 4"));
                try testing.expect(ctx.itemExists("//toast-2/Message: 6"));
                try testing.expect(!ctx.itemExists("//toast-3"));

                toasts.update(1.0); // t = 4.5
                ctx.yield(1);

                try testing.expect(ctx.itemExists("//toast-0/Message: 2"));
                try testing.expect(ctx.itemExists("//toast-1/Message: 4"));
                try testing.expect(!ctx.itemExists("//toast-2"));

                toasts.update(1.0); // t = 5.5
                ctx.yield(1);

                try testing.expect(ctx.itemExists("//toast-0/Message: 4"));
                try testing.expect(!ctx.itemExists("//toast-1"));

                toasts.update(1.0); // t = 6.5
                ctx.yield(1);

                try testing.expect(!ctx.itemExists("//toast-0"));
            }
        }.call,
    );
}

test "should discard earliest toasts when exceeding max toasts" {
    const toasts = Toasts(.{
        .buffer_size = 2048,
        .max_toasts = 2,
        .margin = 8.0,
        .default_duration = 5.0,
        .fly_in_time = 0.0,
        .fly_out_time = 0.0,
    });
    const context = try ui.getTestingContext();
    try context.runTest(
        .{},
        struct {
            fn call(_: ui.TestContext) !void {
                toasts.draw();
            }
        }.call,
        struct {
            fn call(ctx: ui.TestContext) !void {
                toasts.send(.default, null, "Message: 1", .{});
                toasts.send(.default, null, "Message: 2", .{});
                ctx.yield(1);

                try testing.expect(ctx.itemExists("//toast-0/Message: 1"));
                try testing.expect(ctx.itemExists("//toast-1/Message: 2"));
                try testing.expect(!ctx.itemExists("//toast-2"));

                toasts.send(.default, null, "Message: 3", .{});
                ctx.yield(1);

                try testing.expect(ctx.itemExists("//toast-0/Message: 2"));
                try testing.expect(ctx.itemExists("//toast-1/Message: 3"));
                try testing.expect(!ctx.itemExists("//toast-2"));

                toasts.send(.default, null, "Message: 4", .{});
                ctx.yield(1);

                try testing.expect(ctx.itemExists("//toast-0/Message: 3"));
                try testing.expect(ctx.itemExists("//toast-1/Message: 4"));
                try testing.expect(!ctx.itemExists("//toast-2"));
            }
        }.call,
    );
}

test "should discard earliest entries when exceeding buffer size" {
    const toasts = Toasts(.{
        .buffer_size = 22,
        .max_toasts = 32,
        .margin = 8.0,
        .default_duration = 5.0,
        .fly_in_time = 0.0,
        .fly_out_time = 0.0,
    });
    const context = try ui.getTestingContext();
    try context.runTest(
        .{},
        struct {
            fn call(_: ui.TestContext) !void {
                toasts.draw();
            }
        }.call,
        struct {
            fn call(ctx: ui.TestContext) !void {
                toasts.send(.default, null, "Message: 1", .{});
                toasts.send(.default, null, "Message: 2", .{});
                ctx.yield(1);

                try testing.expect(ctx.itemExists("//toast-0/Message: 1"));
                try testing.expect(ctx.itemExists("//toast-1/Message: 2"));
                try testing.expect(!ctx.itemExists("//toast-2"));

                toasts.send(.default, null, "Message: 3", .{});
                ctx.yield(1);

                try testing.expect(ctx.itemExists("//toast-0/Message: 2"));
                try testing.expect(ctx.itemExists("//toast-1/Message: 3"));
                try testing.expect(!ctx.itemExists("//toast-2"));

                toasts.send(.default, null, "Message: 123", .{});
                ctx.yield(1);

                try testing.expect(ctx.itemExists("//toast-0/Message: 123"));
                try testing.expect(!ctx.itemExists("//toast-1"));
            }
        }.call,
    );
}

test "should discard all toasts when message is larger then the buffer" {
    const toasts = Toasts(.{
        .buffer_size = 12,
        .max_toasts = 32,
        .margin = 8.0,
        .default_duration = 5.0,
        .fly_in_time = 0.0,
        .fly_out_time = 0.0,
    });
    const context = try ui.getTestingContext();
    try context.runTest(
        .{},
        struct {
            fn call(_: ui.TestContext) !void {
                toasts.draw();
            }
        }.call,
        struct {
            fn call(ctx: ui.TestContext) !void {
                toasts.send(.default, null, "Message: 1", .{});
                ctx.yield(1);

                try testing.expect(ctx.itemExists("//toast-0/Message: 1"));
                try testing.expect(!ctx.itemExists("//toast-1"));

                toasts.send(.default, null, "Message: 123", .{});
                ctx.yield(1);

                try testing.expect(!ctx.itemExists("//toast-0"));
            }
        }.call,
    );
}

test "should send toasts only for warning and error logs" {
    const toasts = Toasts(.{
        .buffer_size = 2048,
        .max_toasts = 32,
        .margin = 8.0,
        .default_duration = 1.0,
        .fly_in_time = 0.0,
        .fly_out_time = 0.0,
    });
    const context = try ui.getTestingContext();
    try context.runTest(
        .{},
        struct {
            fn call(_: ui.TestContext) !void {
                toasts.draw();
            }
        }.call,
        struct {
            fn call(ctx: ui.TestContext) !void {
                toasts.logFn(.debug, std.log.default_log_scope, "Message: {}", .{1});
                toasts.logFn(.info, std.log.default_log_scope, "Message: {}", .{2});
                toasts.logFn(.warn, std.log.default_log_scope, "Message: {}", .{3});
                toasts.logFn(.err, std.log.default_log_scope, "Message: {}", .{4});
                ctx.yield(1);

                try testing.expect(ctx.itemExists("//toast-0/Message: 3"));
                try testing.expect(ctx.itemExists("//toast-1/Message: 4"));
                try testing.expect(!ctx.itemExists("//toast-2"));
            }
        }.call,
    );
}
