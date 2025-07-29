const std = @import("std");
const builtin = @import("builtin");
const misc = @import("root.zig");

pub const ErrorContextConfig = struct {
    buffer_size: usize = 4096,
    max_items: usize = 64,
};

pub const ErrorContextMessage = union(enum) {
    static: []const u8,
    dynamic: []u8,
};

pub const ErrorContextItem = struct {
    message: ErrorContextMessage,

    const Self = @This();

    pub fn getBufferRegion(self: *const Self) ?[]const u8 {
        return switch (self.message) {
            .static => null,
            .dynamic => |msg| msg,
        };
    }
};

pub fn ErrorContext(comptime config: ErrorContextConfig) type {
    return struct {
        items: misc.CircularBuffer(config.max_items, ErrorContextItem) = .{},
        buffer: [config.buffer_size]u8 = undefined,

        const Self = @This();

        pub inline fn new(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.clear();
            @call(.always_inline, append, .{ self, fmt, args });
        }

        pub inline fn append(self: *Self, comptime fmt: []const u8, args: anytype) void {
            if (@typeInfo(@TypeOf(.{args})).@"struct".fields[0].is_comptime) {
                self.staticAppend(fmt, args);
            } else {
                self.dynamicAppend(fmt, args);
            }
        }

        fn staticAppend(
            self: *Self,
            comptime fmt: []const u8,
            comptime args: anytype,
        ) void {
            const message = std.fmt.comptimePrint(fmt, args);
            const item = ErrorContextItem{
                .message = .{ .static = message },
            };
            const removed_item = self.items.addToBack(item);
            if (removed_item != null and !builtin.is_test) {
                std.log.warn("Discarded the earliest item from the error context because max items was exceeded.", .{});
            }
        }

        fn dynamicAppend(self: *Self, comptime fmt: []const u8, args: anytype) void {
            var last_buffer_region: ?[]const u8 = null;
            var index = self.items.len;
            while (index > 0 and last_buffer_region == null) {
                index -= 1;
                const item = self.items.get(index) catch unreachable;
                last_buffer_region = item.getBufferRegion();
            }
            if (last_buffer_region) |region| {
                const start_index = (&region[0] - &self.buffer[0]) + region.len;
                if (self.addDynamicItem(self.buffer[start_index..], fmt, args) catch null) |_| {
                    return;
                }
            }
            self.addDynamicItem(&self.buffer, fmt, args) catch {
                if (!builtin.is_test) {
                    std.log.err("Failed to add item to error context. Error message is larger then the buffer.", .{});
                }
            };
        }

        fn addDynamicItem(
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
                .message = .{ .dynamic = message },
            };
            self.clearBufferRegion(message);
            const removed_item = self.items.addToBack(item);
            if (removed_item != null and !builtin.is_test) {
                std.log.warn("Discarded the earliest item from the error context because max items was exceeded.", .{});
            }
        }

        fn clearBufferRegion(self: *Self, region: []const u8) void {
            var elements_to_remove: usize = 0;
            for (0..self.items.len) |index| {
                const item = self.items.get(index) catch unreachable;
                const item_region = item.getBufferRegion() orelse continue;
                if (misc.doSlicesCollide(u8, item_region, region)) {
                    elements_to_remove = index + 1;
                } else {
                    break;
                }
            }
            for (0..elements_to_remove) |_| {
                _ = self.items.removeFirst() catch unreachable;
                if (!builtin.is_test) {
                    std.log.warn("Discarded the earliest item from the error context because buffer was full.", .{});
                }
            }
        }

        pub fn clear(self: *Self) void {
            self.items.clear();
        }

        pub fn logError(self: *const Self, err: anyerror) void {
            if (self.items.getLast() catch null) |last_item| {
                const message = switch (last_item.message) {
                    .static => |msg| msg,
                    .dynamic => |msg| msg,
                };
                std.log.err("{s} [{}]\nCausation chain:\n{}", .{ message, err, self });
            } else {
                std.log.err("No items inside the error context. [{}]", .{err});
            }
        }

        pub fn logWarning(self: *const Self, err: anyerror) void {
            if (self.items.getLast() catch null) |last_item| {
                const message = switch (last_item.message) {
                    .static => |msg| msg,
                    .dynamic => |msg| msg,
                };
                std.log.warn("{s} [{}]\nCausation chain:\n{}", .{ message, err, self });
            } else {
                std.log.warn("No items inside the error context. [{}]", .{err});
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
                const item = self.items.get(self.items.len - ordinal_number) catch unreachable;
                const message = switch (item.message) {
                    .static => |msg| msg,
                    .dynamic => |msg| msg,
                };
                try writer.print("{}) {s}\n", .{ ordinal_number, message });
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

    context.new("Error: {}", .{1});
    context.append("Error: {}", .{2});
    const message_1 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_1);
    try testing.expectEqualStrings("1) Error: 2\n2) Error: 1\n", message_1);

    context.append("Error: {}", .{3});
    const message_2 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_2);
    try testing.expectEqualStrings("1) Error: 3\n2) Error: 2\n", message_2);

    context.append("Error: {}", .{4});
    const message_3 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_3);
    try testing.expectEqualStrings("1) Error: 4\n2) Error: 3\n", message_3);
}

test "should discard earliest items when exceeding buffer size" {
    var context = ErrorContext(.{
        .buffer_size = 16,
        .max_items = 64,
    }){};
    var number: i32 = 0;

    number = 1;
    context.new("Error: {}", .{number});
    number = 2;
    context.append("Error: {}", .{number});
    const message_1 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_1);
    try testing.expectEqualStrings("1) Error: 2\n2) Error: 1\n", message_1);

    number = 3;
    context.append("Error: {}", .{number});
    const message_2 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_2);
    try testing.expectEqualStrings("1) Error: 3\n2) Error: 2\n", message_2);

    number = 123;
    context.append("Error: {}", .{number});
    const message_3 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_3);
    try testing.expectEqualStrings("1) Error: 123\n", message_3);
}

test "should discard all items when message is larger then the buffer" {
    var context = ErrorContext(.{
        .buffer_size = 16,
        .max_items = 64,
    }){};
    var number: i32 = 0;

    number = 1;
    context.new("Error: {}", .{number});
    number = 2;
    context.append("Error: {}", .{number});
    const message_1 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_1);
    try testing.expectEqualStrings("1) Error: 2\n2) Error: 1\n", message_1);

    number = 1234567890;
    context.append("Error: {}", .{number});
    const message_2 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_2);
    try testing.expectEqualStrings("No items inside the error context.", message_2);
}
