const std = @import("std");
const misc = @import("root.zig");

pub fn CircularBuffer(comptime capacity: usize, comptime Element: type) type {
    if (capacity == 0) {
        @compileError("Circular buffers with 0 capacity are not supported.");
    }
    return struct {
        array: [capacity]Element = undefined,
        start_index: usize = 0,
        len: usize = 0,

        const Self = @This();

        pub fn addToFront(self: *Self, element: Element) ?Element {
            const removed_element = if (self.len >= capacity) (self.removeLast() catch unreachable) else null;
            self.start_index = if (self.start_index > 0) self.start_index - 1 else capacity - 1;
            self.len += 1;
            self.set(0, element) catch unreachable;
            return removed_element;
        }

        pub fn addToBack(self: *Self, element: Element) ?Element {
            const removed_element = if (self.len >= capacity) (self.removeFirst() catch unreachable) else null;
            self.len += 1;
            self.set(self.len - 1, element) catch unreachable;
            return removed_element;
        }

        pub fn removeFirst(self: *Self) !Element {
            const element = try self.getFirst();
            self.start_index = self.getArrayIndex(1);
            self.len -= 1;
            return element;
        }

        pub fn removeLast(self: *Self) !Element {
            const element = try self.getLast();
            self.len -= 1;
            return element;
        }

        pub fn getFirst(self: *Self) !Element {
            if (self.len == 0) {
                misc.errorContext().new("Buffer is empty.");
                return error.Empty;
            }
            return self.get(0) catch unreachable;
        }

        pub fn getLast(self: *Self) !Element {
            if (self.len == 0) {
                misc.errorContext().new("Buffer is empty.");
                return error.Empty;
            }
            return self.get(self.len - 1) catch unreachable;
        }

        pub fn get(self: *const Self, index: usize) !Element {
            if (index >= self.len) {
                misc.errorContext().newFmt("Provided index {} is out of bounds. (length = {})", .{ index, self.len });
                return error.IndexOutOfBounds;
            }
            const array_index = self.getArrayIndex(index);
            return self.array[array_index];
        }

        pub fn set(self: *Self, index: usize, element: Element) !void {
            if (index >= self.len) {
                misc.errorContext().newFmt("Provided index {} is out of bounds. (length = {})", .{ index, self.len });
                return error.IndexOutOfBounds;
            }
            const array_index = self.getArrayIndex(index);
            self.array[array_index] = element;
        }

        fn getArrayIndex(self: *const Self, index: usize) usize {
            return (self.start_index + index) % capacity;
        }
    };
}

const testing = std.testing;

test "addToFront should add the element to the lowest index" {
    var buffer = CircularBuffer(5, i32){};
    _ = buffer.addToFront(1);
    _ = buffer.addToFront(2);
    _ = buffer.addToFront(3);
    try testing.expectEqual(3, buffer.get(0));
    try testing.expectEqual(2, buffer.get(1));
    try testing.expectEqual(1, buffer.get(2));
    try testing.expectEqual(3, buffer.len);
}

test "addToFront should return the element that's been removed as the result of buffer being full" {
    var buffer = CircularBuffer(2, i32){};
    const removed_1 = buffer.addToFront(1);
    const removed_2 = buffer.addToFront(2);
    const removed_3 = buffer.addToFront(3);
    try testing.expectEqual(null, removed_1);
    try testing.expectEqual(null, removed_2);
    try testing.expectEqual(1, removed_3);
    try testing.expectEqual(3, buffer.get(0));
    try testing.expectEqual(2, buffer.get(1));
    try testing.expectEqual(2, buffer.len);
}

test "addToBack should add the element to the highest index" {
    var buffer = CircularBuffer(5, i32){};
    _ = buffer.addToBack(1);
    _ = buffer.addToBack(2);
    _ = buffer.addToBack(3);
    try testing.expectEqual(1, buffer.get(0));
    try testing.expectEqual(2, buffer.get(1));
    try testing.expectEqual(3, buffer.get(2));
    try testing.expectEqual(3, buffer.len);
}

test "addToBack should return the element that's been removed as the result of buffer being full" {
    var buffer = CircularBuffer(2, i32){};
    const removed_1 = buffer.addToBack(1);
    const removed_2 = buffer.addToBack(2);
    const removed_3 = buffer.addToBack(3);
    try testing.expectEqual(null, removed_1);
    try testing.expectEqual(null, removed_2);
    try testing.expectEqual(1, removed_3);
    try testing.expectEqual(2, buffer.get(0));
    try testing.expectEqual(3, buffer.get(1));
    try testing.expectEqual(2, buffer.len);
}

test "removeFirst should remove and return the element with the lowest index" {
    var buffer = CircularBuffer(5, i32){};
    _ = buffer.addToBack(1);
    _ = buffer.addToBack(2);
    _ = buffer.addToBack(3);
    const removed = try buffer.removeFirst();
    try testing.expectEqual(1, removed);
    try testing.expectEqual(2, buffer.get(0));
    try testing.expectEqual(3, buffer.get(1));
    try testing.expectEqual(2, buffer.len);
}

test "removeFirst should error when buffer is empty" {
    var buffer = CircularBuffer(5, i32){};
    try testing.expectError(error.Empty, buffer.removeFirst());
}

test "removeLast should remove and return the element with the highest index" {
    var buffer = CircularBuffer(5, i32){};
    _ = buffer.addToBack(1);
    _ = buffer.addToBack(2);
    _ = buffer.addToBack(3);
    const removed = try buffer.removeLast();
    try testing.expectEqual(3, removed);
    try testing.expectEqual(1, buffer.get(0));
    try testing.expectEqual(2, buffer.get(1));
    try testing.expectEqual(2, buffer.len);
}

test "removeLast should error when buffer is empty" {
    var buffer = CircularBuffer(5, i32){};
    try testing.expectError(error.Empty, buffer.removeLast());
}

test "getFirst should return the element with the lowest index" {
    var buffer = CircularBuffer(5, i32){};
    _ = buffer.addToBack(1);
    _ = buffer.addToBack(2);
    _ = buffer.addToBack(3);
    const element = try buffer.getFirst();
    try testing.expectEqual(1, element);
}

test "getFirst should error when buffer is empty" {
    var buffer = CircularBuffer(5, i32){};
    try testing.expectError(error.Empty, buffer.getFirst());
}

test "getLast should return the element with the highest index" {
    var buffer = CircularBuffer(5, i32){};
    _ = buffer.addToBack(1);
    _ = buffer.addToBack(2);
    _ = buffer.addToBack(3);
    const element = try buffer.getLast();
    try testing.expectEqual(3, element);
}

test "getLast should error when buffer is empty" {
    var buffer = CircularBuffer(5, i32){};
    try testing.expectError(error.Empty, buffer.getLast());
}

test "get should return correct element when index in bounds" {
    var buffer = CircularBuffer(5, i32){};
    _ = buffer.addToBack(1);
    _ = buffer.addToBack(2);
    _ = buffer.addToFront(3);
    try testing.expectEqual(3, buffer.get(0));
    try testing.expectEqual(1, buffer.get(1));
    try testing.expectEqual(2, buffer.get(2));
}

test "get should error when index out of bounds" {
    var buffer = CircularBuffer(5, i32){};
    _ = buffer.addToBack(1);
    _ = buffer.addToBack(2);
    _ = buffer.addToFront(3);
    try testing.expectError(error.IndexOutOfBounds, buffer.get(3));
}

test "set should set value of correct element when index in bounds" {
    var buffer = CircularBuffer(5, i32){};
    _ = buffer.addToBack(1);
    _ = buffer.addToBack(2);
    _ = buffer.addToFront(3);
    try buffer.set(1, 4);
    try testing.expectEqual(3, buffer.get(0));
    try testing.expectEqual(4, buffer.get(1));
    try testing.expectEqual(2, buffer.get(2));
}

test "set should error when index out of bounds" {
    var buffer = CircularBuffer(5, i32){};
    _ = buffer.addToBack(1);
    _ = buffer.addToBack(2);
    _ = buffer.addToFront(3);
    try testing.expectError(error.IndexOutOfBounds, buffer.set(3, 4));
}
