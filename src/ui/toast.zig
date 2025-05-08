const std = @import("std");
const imgui = @import("imgui");
const misc = @import("../misc/root.zig");

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
            for (0..toasts.len) |index| {
                const toast = toasts.get(index) catch continue;
                if (toast.life_time >= toast.duration) {
                    continue;
                }
                drawToast(index, toast);
            }
        }

        fn drawToast(index: usize, toast: *const Toast) void {
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
            const float_index: f32 = @floatFromInt(index);
            const window_position = imgui.ImVec2{
                .x = min_x + (animation_factor * (max_x - min_x)),
                .y = config.margin + float_index * (window_size.y + config.margin),
            };

            imgui.igPushStyleVar_Float(imgui.ImGuiStyleVar_WindowBorderSize, 0);
            defer imgui.igPopStyleVar(1);
            imgui.igSetNextWindowPos(window_position, imgui.ImGuiCond_Always, .{});
            imgui.igSetNextWindowSize(window_size, imgui.ImGuiCond_Always);
            _ = imgui.igBegin(window_name, null, window_flags);
            defer imgui.igEnd();
            imgui.igTextColored(toast.color, "%s", toast.message.ptr);
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
    };
}
