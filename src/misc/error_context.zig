const std = @import("std");

threadlocal var gpa = std.heap.GeneralPurposeAllocator(.{}){};
threadlocal var instance: ?ErrorContext = null;

pub fn errorContext() *ErrorContext {
    if (instance == null) {
        instance = ErrorContext.init(gpa.allocator());
    }
    return &instance.?;
}

pub const ErrorContext = struct {
    allocator: std.mem.Allocator,
    trace: std.ArrayList(TraceItem),

    pub const TraceItem = struct {
        message: Message,
    };
    pub const Message = union(enum) {
        constant: []const u8,
        formatted: []u8,
    };
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .trace = std.ArrayList(TraceItem).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.clear();
        self.trace.deinit();
    }

    pub fn new(self: *Self, message: []const u8) void {
        self.clear();
        @call(.always_inline, append, .{ self, message });
    }

    pub fn newFmt(self: *Self, comptime fmt: []const u8, args: anytype) void {
        self.clear();
        @call(.always_inline, appendFmt, .{ self, fmt, args });
    }

    pub fn append(self: *Self, message: []const u8) void {
        const item = TraceItem{
            .message = .{ .constant = message },
        };
        self.trace.append(item) catch |err| {
            std.log.err("Failed to append message \"{s}\" to error context. [{}]", .{ message, err });
        };
    }

    pub fn appendFmt(self: *Self, comptime fmt: []const u8, args: anytype) void {
        const message = std.fmt.allocPrint(self.allocator, fmt, args) catch null;
        const item = TraceItem{
            .message = if (message) |msg| .{ .formatted = msg } else .{ .constant = fmt },
        };
        self.trace.append(item) catch |err| {
            std.log.err("Failed to append message \"{s}\" to error context. [{}]", .{ message orelse fmt, err });
            if (message) |msg| {
                self.allocator.free(msg);
            }
        };
    }

    pub fn clear(self: *Self) void {
        for (self.trace.items) |element| {
            switch (element.message) {
                .constant => continue,
                .formatted => |value| self.allocator.free(value),
            }
        }
        self.trace.clearRetainingCapacity();
    }

    pub fn logError(self: *const Self, err: anyerror) void {
        if (self.trace.getLastOrNull()) |last_item| {
            const message = switch (last_item.message) {
                .constant => |msg| msg,
                .formatted => |msg| msg,
            };
            std.log.err("{s} [{}]\nCausation chain:\n{}", .{ message, err, self });
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
        if (self.trace.items.len == 0) {
            try writer.writeAll("No items inside the error context.");
            return;
        }
        for (1..(self.trace.items.len + 1)) |ordinal_number| {
            const item = self.trace.items[self.trace.items.len - ordinal_number];
            const message = switch (item.message) {
                .constant => |msg| msg,
                .formatted => |msg| msg,
            };
            try writer.print("{}) {s}\n", .{ ordinal_number, message });
        }
    }
};

const testing = std.testing;

test "should correctly format error message" {
    var context = ErrorContext.init(testing.allocator);
    defer context.deinit();

    context.new("Error 1.");
    context.appendFmt("Error 2 with context: {}", .{123});
    const message_1 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_1);
    const expected_1 = "1) Error 2 with context: 123\n2) Error 1.\n";
    try testing.expectEqualStrings(expected_1, message_1);

    context.newFmt("Error 3 with context: {}", .{456});
    context.append("Error 4.");
    const message_2 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_2);
    const expected_2 = "1) Error 4.\n2) Error 3 with context: 456\n";
    try testing.expectEqualStrings(expected_2, message_2);

    context.clear();
    const message_3 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_3);
    const expected_3 = "No items inside the error context.";
    try testing.expectEqualStrings(expected_3, message_3);
}
