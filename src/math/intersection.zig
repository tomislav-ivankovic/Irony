const std = @import("std");
const math = @import("root.zig");

pub fn checkCylinderLineSegmentIntersection(
    cylinder: math.Cylinder,
    line: math.LineSegment3,
) bool {
    const z_interval_1 = Interval{
        .min = cylinder.center.z() - cylinder.half_height,
        .max = cylinder.center.z() + cylinder.half_height,
    };
    const z_interval_2 = Interval{
        .min = @min(line.point_1.z(), line.point_2.z()),
        .max = @max(line.point_1.z(), line.point_2.z()),
    };
    const z_interval = findIntervalIntersection(z_interval_1, z_interval_2) orelse return false;

    const difference = line.point_2.subtract(line.point_1);
    if (difference.z() == 0) {
        return checkCircleLineSegmentIntersection(
            .{ .center = cylinder.center.swizzle("xy"), .radius = cylinder.radius },
            .{ .point_1 = line.point_1.swizzle("xy"), .point_2 = line.point_2.swizzle("xy") },
        );
    }

    const t1 = (z_interval.min - line.point_1.z()) / difference.z();
    const t2 = (z_interval.max - line.point_1.z()) / difference.z();
    const p1 = line.point_1.add(difference.scale(t1));
    const p2 = line.point_1.add(difference.scale(t2));
    return checkCircleLineSegmentIntersection(
        .{ .center = cylinder.center.swizzle("xy"), .radius = cylinder.radius },
        .{ .point_1 = p1.swizzle("xy"), .point_2 = p2.swizzle("xy") },
    );
}

pub fn checkCircleLineSegmentIntersection(
    circle: math.Circle,
    line: math.LineSegment2,
) bool {
    const p1 = line.point_1.subtract(circle.center);
    const p2 = line.point_2.subtract(circle.center);

    const radius_squared = circle.radius * circle.radius;
    const p1_squared = p1.lengthSquared();
    const p2_squared = p2.lengthSquared();

    if (p1_squared <= radius_squared or p2_squared <= radius_squared) {
        return true;
    }

    const difference = p2.subtract(p1);
    const a = difference.lengthSquared();
    const b = 2 * p1.dot(difference);
    const c = p1_squared - radius_squared;

    const discriminant_squared = b * b - 4 * a * c;
    if (discriminant_squared < 0) {
        return false;
    }
    const discriminant = std.math.sqrt(discriminant_squared);

    const t1 = (-b - discriminant) / (2 * a);
    const t2 = (-b + discriminant) / (2 * a);

    return (t1 >= 0 and t1 <= 1) or (t2 >= 0 and t2 <= 1);
}

const Interval = struct {
    min: f32,
    max: f32,
};

pub fn findIntervalIntersection(a: Interval, b: Interval) ?Interval {
    const start = @max(a.min, b.min);
    const end = @min(a.max, b.max);
    if (start <= end) {
        return .{ .min = start, .max = end };
    } else {
        return null;
    }
}

const testing = std.testing;

test "checkCylinderLineSegmentIntersection should return correct value" {
    const vec = struct {
        fn call(x: f32, z: f32) math.Vec3 {
            return math.Vec3.fromArray(.{ x, 0, z });
        }
    }.call;
    const cylinder = struct {
        fn call(center: math.Vec3, radius: f32, half_height: f32) math.Cylinder {
            return .{ .center = center, .radius = radius, .half_height = half_height };
        }
    }.call;
    const line = struct {
        fn call(point_1: math.Vec3, point_2: math.Vec3) math.LineSegment3 {
            return .{ .point_1 = point_1, .point_2 = point_2 };
        }
    }.call;
    const intersection = checkCylinderLineSegmentIntersection;
    try testing.expectEqual(false, intersection(cylinder(vec(6, 12), 2, 4), line(vec(9, 5), vec(11, 7))));
    try testing.expectEqual(false, intersection(cylinder(vec(6, 12), 2, 4), line(vec(5, 5), vec(7, 7))));
    try testing.expectEqual(false, intersection(cylinder(vec(6, 12), 2, 4), line(vec(9, 8), vec(11, 10))));
    try testing.expectEqual(false, intersection(cylinder(vec(6, 12), 2, 4), line(vec(5, 4), vec(11, 11))));
    try testing.expectEqual(true, intersection(cylinder(vec(6, 12), 2, 4), line(vec(7, 7), vec(9, 9))));
    try testing.expectEqual(true, intersection(cylinder(vec(6, 12), 2, 4), line(vec(8, 8), vec(10, 6))));
    try testing.expectEqual(true, intersection(cylinder(vec(6, 12), 2, 4), line(vec(5, 8), vec(7, 6))));
    try testing.expectEqual(true, intersection(cylinder(vec(6, 12), 2, 4), line(vec(8, 9), vec(10, 10))));
    try testing.expectEqual(true, intersection(cylinder(vec(6, 12), 2, 4), line(vec(2, 13), vec(9, 6))));
    try testing.expectEqual(true, intersection(cylinder(vec(6, 12), 2, 4), line(vec(5, 9), vec(7, 7))));
    try testing.expectEqual(true, intersection(cylinder(vec(6, 12), 2, 4), line(vec(7, 10), vec(9, 11))));
    try testing.expectEqual(true, intersection(cylinder(vec(6, 12), 2, 4), line(vec(5, 10), vec(7, 14))));
    try testing.expectEqual(true, intersection(cylinder(vec(6, 12), 2, 4), line(vec(7, 8), vec(9, 8))));
    try testing.expectEqual(true, intersection(cylinder(vec(6, 12), 2, 4), line(vec(8, 7), vec(8, 9))));
}

test "checkCircleLineSegmentIntersection should return correct value" {
    const vec = struct {
        fn call(x: f32, y: f32) math.Vec2 {
            return math.Vec2.fromArray(.{ x, y });
        }
    }.call;
    const circle = struct {
        fn call(center: math.Vec2, radius: f32) math.Circle {
            return .{ .center = center, .radius = radius };
        }
    }.call;
    const line = struct {
        fn call(point_1: math.Vec2, point_2: math.Vec2) math.LineSegment2 {
            return .{ .point_1 = point_1, .point_2 = point_2 };
        }
    }.call;
    const intersection = checkCircleLineSegmentIntersection;
    try testing.expectEqual(false, intersection(circle(vec(8, 12), 4), line(vec(13, 23), vec(18, 17))));
    try testing.expectEqual(false, intersection(circle(vec(8, 12), 4), line(vec(10, 7), vec(14, 13))));
    try testing.expectEqual(true, intersection(circle(vec(8, 12), 4), line(vec(12, 8), vec(12, 16))));
    try testing.expectEqual(true, intersection(circle(vec(8, 12), 4), line(vec(12, 12), vec(16, 13))));
    try testing.expectEqual(true, intersection(circle(vec(8, 12), 4), line(vec(10, 11), vec(13, 9))));
    try testing.expectEqual(true, intersection(circle(vec(8, 12), 4), line(vec(8, 10), vec(10, 12))));
}

test "findIntervalIntersection should return correct value" {
    const interval = struct {
        fn call(min: f32, max: f32) Interval {
            return .{ .min = min, .max = max };
        }
    }.call;
    const intersection = findIntervalIntersection;
    try testing.expectEqual(null, intersection(interval(1, 2), interval(3, 4)));
    try testing.expectEqual(null, intersection(interval(3, 4), interval(1, 2)));
    try testing.expectEqual(interval(2, 3), intersection(interval(1, 3), interval(2, 4)));
    try testing.expectEqual(interval(2, 3), intersection(interval(2, 4), interval(1, 3)));
    try testing.expectEqual(interval(2, 3), intersection(interval(1, 4), interval(2, 3)));
    try testing.expectEqual(interval(2, 3), intersection(interval(2, 3), interval(1, 4)));
}
