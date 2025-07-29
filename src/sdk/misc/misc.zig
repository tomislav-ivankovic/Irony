const std = @import("std");

pub fn doSlicesCollide(Element: type, a: []const Element, b: []const Element) bool {
    if (a.len == 0 or b.len == 0) {
        return false;
    }
    const a_min = @intFromPtr(&a[0]);
    const a_max = @intFromPtr(&a[a.len - 1]);
    const b_min = @intFromPtr(&b[0]);
    const b_max = @intFromPtr(&b[b.len - 1]);
    return (a_max >= b_min) and (b_max >= a_min);
}

const testing = std.testing;

test "doSlicesCollide should return correct value" {
    const data = [_]i32{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };

    try testing.expectEqual(false, doSlicesCollide(i32, data[5..5], data[5..5]));
    try testing.expectEqual(false, doSlicesCollide(i32, data[0..5], data[5..10]));
    try testing.expectEqual(false, doSlicesCollide(i32, data[5..10], data[0..5]));
    try testing.expectEqual(false, doSlicesCollide(i32, data[1..4], data[6..9]));
    try testing.expectEqual(false, doSlicesCollide(i32, data[6..9], data[1..4]));

    try testing.expectEqual(true, doSlicesCollide(i32, data[0..6], data[5..10]));
    try testing.expectEqual(true, doSlicesCollide(i32, data[4..10], data[0..5]));
    try testing.expectEqual(true, doSlicesCollide(i32, data[1..8], data[2..9]));
    try testing.expectEqual(true, doSlicesCollide(i32, data[2..9], data[1..8]));
    try testing.expectEqual(true, doSlicesCollide(i32, data[1..9], data[4..6]));
    try testing.expectEqual(true, doSlicesCollide(i32, data[4..6], data[1..9]));
}
