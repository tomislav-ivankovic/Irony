const std = @import("std");
const math = @import("root.zig");

/// Finds the convex hull of the points using Andrew's monotone chain algorithm. Sorts the points in place.
/// Buffer has to be at least twice the size of the points. Returns the hull points in counter-clockwise order,
/// starting from the point with the smallest coordinates and omitting collinear points.
pub fn findConvexHull(points: []math.Vec2, buffer: []math.Vec2) []math.Vec2 {
    std.debug.assert(buffer.len >= 2 * points.len);
    if (points.len < 3) {
        @memcpy(buffer[0..points.len], points);
        return buffer[0..points.len];
    }
    std.mem.sort(math.Vec2, points, {}, isLessThan);
    var len: usize = 0;
    for (points) |point| {
        while (len >= 2 and findTurn(buffer[len - 2], buffer[len - 1], point) <= 0) {
            len -= 1;
        }
        buffer[len] = point;
        len += 1;
    }
    const lower_len = len + 1;
    var index = points.len - 1;
    while (index > 0) {
        index -= 1;
        const point = points[index];
        while (len >= lower_len and findTurn(buffer[len - 2], buffer[len - 1], point) <= 0) {
            len -= 1;
        }
        buffer[len] = point;
        len += 1;
    }
    return buffer[0..(len - 1)];
}

fn isLessThan(_: void, a: math.Vec2, b: math.Vec2) bool {
    return a.x() < b.x() or (a.x() == b.x() and a.y() < b.y());
}

fn findTurn(a: math.Vec2, b: math.Vec2, c: math.Vec2) f32 {
    return b.subtract(a).cross(c.subtract(a));
}

const testing = std.testing;

test "findConvexHull should return correct value" {
    var points = [_]math.Vec2{
        .fromArray(.{ 1, 1 }),
        .fromArray(.{ 4, 4 }),
        .fromArray(.{ 2, 3 }),
        .fromArray(.{ 0, 4 }),
        .fromArray(.{ 2, 0 }),
        .fromArray(.{ 4, 0 }),
        .fromArray(.{ 3, 2 }),
        .fromArray(.{ 0, 0 }),
        .fromArray(.{ 4, 2 }),
        .fromArray(.{ 0, 4 }),
    };
    var buffer: [2 * points.len]math.Vec2 = undefined;
    const hull = findConvexHull(&points, &buffer);
    try testing.expectEqualSlices(math.Vec2, &.{
        .fromArray(.{ 0, 0 }),
        .fromArray(.{ 4, 0 }),
        .fromArray(.{ 4, 4 }),
        .fromArray(.{ 0, 4 }),
    }, hull);
}

test "findConvexHull should return the points when there are less then 3 points" {
    var points = [_]math.Vec2{ .fromArray(.{ 3, 4 }), .fromArray(.{ 1, 2 }) };
    var buffer: [2 * points.len]math.Vec2 = undefined;
    const hull = findConvexHull(&points, &buffer);
    try testing.expectEqualSlices(math.Vec2, &.{ .fromArray(.{ 3, 4 }), .fromArray(.{ 1, 2 }) }, hull);
}
