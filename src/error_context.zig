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
        err: ?anyerror,
        return_address: usize,
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

    pub inline fn new(self: *Self, err: ?anyerror, message: []const u8) void {
        self.clear();
        self.append(err, message);
    }

    pub inline fn newFmt(self: *Self, err: ?anyerror, comptime fmt: []const u8, args: anytype) void {
        self.clear();
        self.appendFmt(err, fmt, args);
    }

    pub fn append(self: *Self, err: ?anyerror, message: []const u8) void {
        const item = TraceItem{ .message = .{ .constant = message }, .err = err, .return_address = @returnAddress() };
        self.trace.append(item) catch |append_err| {
            std.log.err("Failed to append message \"{s}\" to error context. [{}]", .{ message, append_err });
        };
    }

    pub fn appendFmt(self: *Self, err: ?anyerror, comptime fmt: []const u8, args: anytype) void {
        const message = std.fmt.allocPrint(self.allocator, fmt, args) catch null;
        const item = TraceItem{
            .message = if (message) |msg| .{ .formatted = msg } else .{ .constant = fmt },
            .err = err,
            .return_address = @returnAddress(),
        };
        self.trace.append(item) catch |append_err| {
            std.log.err("Failed to append message \"{s}\" to error context. [{}]", .{ message orelse fmt, append_err });
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

    pub fn logError(self: *const Self) void {
        if (self.trace.getLastOrNull()) |last_item| {
            const message = switch (last_item.message) {
                .constant => |msg| msg,
                .formatted => |msg| msg,
            };
            std.log.err("{s}\nCausation chain:\n{}", .{ message, self });
        } else {
            std.log.err("No items inside the error context.", .{});
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
            @compileError(std.fmt.comptimePrint("Invalid ErrorContext format {{{s}}}. The only allowed format for ErrorContext is {{}}.", .{fmt}));
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
            try writer.print("{}) {s}", .{ ordinal_number, message });
            if (item.err) |err| {
                try writer.print(" [{}]", .{err});
            }
            if (getSymbolInfoAtAddress(self.allocator, item.return_address)) |symbol_info| {
                defer symbol_info.deinit(self.allocator);
                try writer.print(" {}", .{symbol_info});
            }
            try writer.writeAll("\n");
        }
    }

    fn getSymbolInfoAtAddress(allocator: std.mem.Allocator, address: usize) ?std.debug.SymbolInfo {
        const debug_info = std.debug.getSelfDebugInfo() catch return null;
        const module = debug_info.getModuleForAddress(address) catch return null;
        return module.getSymbolAtAddress(allocator, address) catch return null;
    }
};

const testing = std.testing;

test "should correctly format error message" {
    var context = ErrorContext.init(testing.allocator);
    defer context.deinit();

    context.new(null, "Error 1.");
    context.append(error.Error2, "Error 2.");
    context.appendFmt(error.Error3, "Error 3 with context: {}", .{123});
    const message_1 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_1);
    try testing.expectEqualStrings("1) Error 3 with context: 123 [error.Error3]\n2) Error 2. [error.Error2]\n3) Error 1.\n", message_1);

    context.newFmt(error.Error4, "Error 4 with context: {}", .{456});
    context.append(null, "Error 5.");
    const message_2 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_2);
    try testing.expectEqualStrings("1) Error 5.\n2) Error 4 with context: 456 [error.Error4]\n", message_2);

    context.clear();
    const message_3 = try std.fmt.allocPrint(testing.allocator, "{}", .{context});
    defer testing.allocator.free(message_3);
    try testing.expectEqualStrings("No items inside the error context.", message_3);
}
