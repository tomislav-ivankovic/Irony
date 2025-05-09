const std = @import("std");
const builtin = @import("builtin");
const misc = @import("root.zig");

pub const ErrorContextConfig = struct {
    buffer_size: usize = 4096,
    max_items: usize = 64,
};

pub const ErrorContextItem = struct {
    message: []u8,

    const Self = @This();

    pub fn getBufferRegion(self: *const Self) []const u8 {
        return self.message;
    }
};

pub fn ErrorContext(comptime config: ErrorContextConfig) type {
    return struct {
        items: misc.CircularBuffer(config.max_items, ErrorContextItem) = .{},
        buffer: [config.buffer_size]u8 = undefined,

        const Self = @This();

        pub fn new(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.clear();
            @call(.always_inline, append, .{ self, fmt, args });
        }

        pub fn append(self: *Self, comptime fmt: []const u8, args: anytype) void {
            const last_item = self.items.getLast() catch {
                self.addItem(&self.buffer, fmt, args) catch return;
                return;
            };
            const last_buffer_region = last_item.getBufferRegion();
            const start_index = (&last_buffer_region[0] - &self.buffer[0]) + last_buffer_region.len;
            self.addItem(self.buffer[start_index..], fmt, args) catch {
                self.addItem(&self.buffer, fmt, args) catch {
                    if (!builtin.is_test) {
                        std.log.err(
                            "Failed to add item to error context. Error message was larger then the buffer.",
                            .{},
                        );
                    }
                };
            };
        }

        fn addItem(
            self: *Self,
            write_region: []u8,
            comptime fmt: []const u8,
            args: anytype,
        ) !void {
            const message = std.fmt.bufPrint(write_region, fmt, args) catch |err| {
                self.clearBufferRegion(write_region);
                return err;
            };
            const item = ErrorContextItem{
                .message = message,
            };
            self.clearBufferRegion(item.getBufferRegion());
            const removed_item = self.items.addToBack(item);
            if (removed_item != null and !builtin.is_test) {
                std.log.warn("Discarded the earliest item from the error context because max items was exceeded.", .{});
            }
        }

        fn clearBufferRegion(self: *Self, region: []const u8) void {
            while (self.items.getFirst() catch null) |item| {
                if (!collides(item.getBufferRegion(), region)) {
                    break;
                }
                _ = self.items.removeFirst() catch unreachable;
                if (!builtin.is_test) {
                    std.log.warn("Discarded the earliest item from the error context because buffer was full.", .{});
                }
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

        pub fn clear(self: *Self) void {
            self.items.clear();
        }

        pub fn logError(self: *const Self, err: anyerror) void {
            if (self.items.getLast() catch null) |last_item| {
                std.log.err("{s} [{}]\nCausation chain:\n{}", .{ last_item.message, err, self });
            } else {
                std.log.err("No items inside the error context. [{}]", .{err});
            }
        }

        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = options;
            if (fmt.len != 0) {
                @compileError(std.fmt.comptimePrint(
                    "Invalid ErrorContext format {{{s}}}. The only allowed format for ErrorContext is {{}}.",
                    .{fmt},
                ));
            }
            if (self.items.len == 0) {
                try writer.writeAll("No items inside the error context.");
                return;
            }
            for (1..(self.items.len + 1)) |ordinal_number| {
                const item = self.items.get(self.items.len - ordinal_number) catch continue;
                try writer.print("{}) {s}\n", .{ ordinal_number, item.message });
            }
        }
    };
}

const testing = std.testing;

test "should correctly format error message" {
    var context = ErrorContext(.{
        .buffer_size = 4096,
        .max_items = 64,
    }){};

    context.new("Error 1.", .{});
    context.append("Error 2 with context: {}", .{123});
    const message_1 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_1);
    try testing.expectEqualStrings("1) Error 2 with context: 123\n2) Error 1.\n", message_1);

    context.new("Error 3 with context: {}", .{456});
    context.append("Error 4.", .{});
    const message_2 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_2);
    try testing.expectEqualStrings("1) Error 4.\n2) Error 3 with context: 456\n", message_2);

    context.clear();
    const message_3 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_3);
    try testing.expectEqualStrings("No items inside the error context.", message_3);
}

test "should discard earliest items when exceeding max items" {
    var context = ErrorContext(.{
        .buffer_size = 4096,
        .max_items = 2,
    }){};

    context.new("Error: 1", .{});
    context.append("Error: 2", .{});
    const message_1 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_1);
    try testing.expectEqualStrings("1) Error: 2\n2) Error: 1\n", message_1);

    context.append("Error: 3", .{});
    const message_2 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_2);
    try testing.expectEqualStrings("1) Error: 3\n2) Error: 2\n", message_2);

    context.append("Error: 4", .{});
    const message_3 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_3);
    try testing.expectEqualStrings("1) Error: 4\n2) Error: 3\n", message_3);
}

test "should discard earliest items when exceeding buffer size" {
    var context = ErrorContext(.{
        .buffer_size = 16,
        .max_items = 64,
    }){};

    context.new("Error: 1", .{});
    context.append("Error: 2", .{});
    const message_1 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_1);
    try testing.expectEqualStrings("1) Error: 2\n2) Error: 1\n", message_1);

    context.append("Error: 3", .{});
    const message_2 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_2);
    try testing.expectEqualStrings("1) Error: 3\n2) Error: 2\n", message_2);

    context.append("Error: 123", .{});
    const message_3 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_3);
    try testing.expectEqualStrings("1) Error: 123\n", message_3);
}

test "should discard all items when message is larger then the buffer" {
    var context = ErrorContext(.{
        .buffer_size = 16,
        .max_items = 64,
    }){};

    context.new("Error: 1", .{});
    context.append("Error: 2", .{});
    const message_1 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_1);
    try testing.expectEqualStrings("1) Error: 2\n2) Error: 1\n", message_1);

    context.append("Error: 1234567890", .{});
    const message_2 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_2);
    try testing.expectEqualStrings("No items inside the error context.", message_2);
}
