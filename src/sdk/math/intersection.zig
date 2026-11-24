const std = @import("std");
const math = @import("root.zig");

pub fn checkCylinderLineSegmentIntersection(cylinder: math.Cylinder, line: math.LineSegment3) bool {
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

pub fn checkCylinderSweptCylinderIntersection(cylinder: math.Cylinder, swept_cylinder: math.SweptCylinder) bool {
    const inflated_cylinder = math.Cylinder{
        .center = cylinder.center,
        .radius = cylinder.radius + swept_cylinder.radius,
        .half_height = cylinder.half_height + swept_cylinder.half_height,
    };
    return checkCylinderLineSegmentIntersection(inflated_cylinder, swept_cylinder.line);
}

pub fn checkCylinderSphereIntersection(cylinder: math.Cylinder, sphere: math.Sphere) bool {
    const horizontal_distance = cylinder.center.swizzle("xy").distanceTo(sphere.center.swizzle("xy"));
    const vertical_distance = @abs(cylinder.center.z() - sphere.center.z());
    const horizontal_gap = @max(horizontal_distance - cylinder.radius, 0);
    const vertical_gap = @max(vertical_distance - cylinder.half_height, 0);
    return (horizontal_gap * horizontal_gap) + (vertical_gap * vertical_gap) <= sphere.radius * sphere.radius;
}

pub fn checkCylinderCylinderIntersection(a: math.Cylinder, b: math.Cylinder) bool {
    const horizontal_distance = a.center.swizzle("xy").distanceTo(b.center.swizzle("xy"));
    const vertical_distance = @abs(a.center.z() - b.center.z());
    return horizontal_distance <= a.radius + b.radius and vertical_distance <= a.half_height + b.half_height;
}

pub fn checkCylinderBoxIntersection(cylinder: math.Cylinder, box: math.Box) bool {
    const vertical_distance = @abs(cylinder.center.z() - box.center.z());
    if (vertical_distance > cylinder.half_height + box.half_size.z()) {
        return false;
    }
    return checkCircleRectangleIntersection(
        .{ .center = cylinder.center.swizzle("xy"), .radius = cylinder.radius },
        .{ .center = box.center.swizzle("xy"), .half_size = box.half_size.swizzle("xy"), .rotation = box.rotation },
    );
}

pub fn checkCircleRectangleIntersection(circle: math.Circle, rectangle: math.Rectangle) bool {
    const local_center = circle.center.subtract(rectangle.center).rotateZ(-rectangle.rotation);
    const closest_point = local_center.maxElements(rectangle.half_size.negate()).minElements(rectangle.half_size);
    return local_center.distanceSquaredTo(closest_point) <= circle.radius * circle.radius;
}

pub fn checkCircleLineSegmentIntersection(circle: math.Circle, line: math.LineSegment2) bool {
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

pub fn doSlicesIntersect(Element: type, a: []const Element, b: []const Element) bool {
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

test "checkCylinderSweptCylinderIntersection should return correct value" {
    const vec = struct {
        fn call(x: f32, z: f32) math.Vec3 {
            return math.Vec3.fromArray(.{ x, 0, z });
        }
    }.call;
    const swept = struct {
        fn call(point_1: math.Vec3, point_2: math.Vec3, radius: f32, half_height: f32) math.SweptCylinder {
            return .{
                .line = .{ .point_1 = point_1, .point_2 = point_2 },
                .radius = radius,
                .half_height = half_height,
            };
        }
    }.call;
    const cylinder = math.Cylinder{ .center = vec(0, 0), .radius = 1, .half_height = 1 };
    const intersection = checkCylinderSweptCylinderIntersection;
    try testing.expectEqual(false, intersection(cylinder, swept(vec(3, 0), vec(5, 0), 1.9, 1.9)));
    try testing.expectEqual(true, intersection(cylinder, swept(vec(3, 0), vec(5, 0), 2.1, 0)));
    try testing.expectEqual(false, intersection(cylinder, swept(vec(-1, 3), vec(1, 3), 1.9, 1.9)));
    try testing.expectEqual(true, intersection(cylinder, swept(vec(-1, 3), vec(1, 3), 0, 2.1)));
    try testing.expectEqual(false, intersection(cylinder, swept(vec(-1, 3), vec(1, 3), 10, 0)));
    try testing.expectEqual(false, intersection(cylinder, swept(vec(3, 3), vec(5, 3), 0, 10)));
    try testing.expectEqual(true, intersection(cylinder, swept(vec(-5, 0), vec(5, 0), 0, 0)));
}

test "checkCylinderSphereIntersection should return correct value" {
    const vec = struct {
        fn call(x: f32, z: f32) math.Vec3 {
            return math.Vec3.fromArray(.{ x, 0, z });
        }
    }.call;
    const sphere = struct {
        fn call(center: math.Vec3, radius: f32) math.Sphere {
            return .{ .center = center, .radius = radius };
        }
    }.call;
    const cylinder = math.Cylinder{ .center = vec(0, 0), .radius = 2, .half_height = 3 };
    const intersection = checkCylinderSphereIntersection;
    try testing.expectEqual(false, intersection(cylinder, sphere(vec(4, 0), 1.9)));
    try testing.expectEqual(true, intersection(cylinder, sphere(vec(4, 0), 2)));
    try testing.expectEqual(false, intersection(cylinder, sphere(vec(0, 5), 1.9)));
    try testing.expectEqual(true, intersection(cylinder, sphere(vec(0, 5), 2)));
    try testing.expectEqual(false, intersection(cylinder, sphere(vec(5, 7), 4.9)));
    try testing.expectEqual(true, intersection(cylinder, sphere(vec(5, 7), 5)));
    try testing.expectEqual(true, intersection(cylinder, sphere(vec(1, 1), 0.1)));
}

test "checkCylinderCylinderIntersection should return correct value" {
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
    const a = cylinder(vec(0, 0), 2, 3);
    const intersection = checkCylinderCylinderIntersection;
    try testing.expectEqual(false, intersection(a, cylinder(vec(4, 0), 1.9, 1)));
    try testing.expectEqual(true, intersection(a, cylinder(vec(4, 0), 2, 1)));
    try testing.expectEqual(false, intersection(a, cylinder(vec(0, 6), 1, 2.9)));
    try testing.expectEqual(true, intersection(a, cylinder(vec(0, 6), 1, 3)));
    try testing.expectEqual(true, intersection(a, cylinder(vec(3, 5), 1, 2)));
    try testing.expectEqual(false, intersection(a, cylinder(vec(3, 5), 0.9, 2)));
    try testing.expectEqual(true, intersection(a, cylinder(vec(1, 1), 0.1, 0.1)));
}

test "checkCylinderBoxIntersection should return correct value" {
    const vec = struct {
        fn call(x: f32, y: f32, z: f32) math.Vec3 {
            return math.Vec3.fromArray(.{ x, y, z });
        }
    }.call;
    const cylinder = struct {
        fn call(center: math.Vec3, radius: f32, half_height: f32) math.Cylinder {
            return .{ .center = center, .radius = radius, .half_height = half_height };
        }
    }.call;
    const box = math.Box{ .center = vec(0, 0, 0), .half_size = vec(4, 1, 2), .rotation = 0.5 * std.math.pi };
    const intersection = checkCylinderBoxIntersection;
    try testing.expectEqual(false, intersection(cylinder(vec(3, 0, 0), 1.9, 1), box));
    try testing.expectEqual(true, intersection(cylinder(vec(3, 0, 0), 2.1, 1), box));
    try testing.expectEqual(true, intersection(cylinder(vec(0, 5.9, 0), 2, 1), box));
    try testing.expectEqual(false, intersection(cylinder(vec(0, 6.1, 0), 2, 1), box));
    try testing.expectEqual(false, intersection(cylinder(vec(0, 0, 4), 1, 1.9), box));
    try testing.expectEqual(true, intersection(cylinder(vec(0, 0, 4), 1, 2.1), box));
    try testing.expectEqual(false, intersection(cylinder(vec(0, 0, 4), 10, 1.9), box));
}

test "checkCircleRectangleIntersection should return correct value" {
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
    const rectangle = struct {
        fn call(rotation: f32) math.Rectangle {
            return .{ .center = vec(1, 2), .half_size = vec(4, 1), .rotation = rotation };
        }
    }.call;
    const intersection = checkCircleRectangleIntersection;
    try testing.expectEqual(false, intersection(circle(vec(1, 5), 1.9), rectangle(0)));
    try testing.expectEqual(true, intersection(circle(vec(1, 5), 2), rectangle(0)));
    try testing.expectEqual(false, intersection(circle(vec(7, 2), 1.9), rectangle(0)));
    try testing.expectEqual(true, intersection(circle(vec(7, 2), 2), rectangle(0)));
    try testing.expectEqual(false, intersection(circle(vec(8, 7), 4.9), rectangle(0)));
    try testing.expectEqual(true, intersection(circle(vec(8, 7), 5), rectangle(0)));
    try testing.expectEqual(true, intersection(circle(vec(1, 7.9), 2), rectangle(0.5 * std.math.pi)));
    try testing.expectEqual(false, intersection(circle(vec(1, 8.1), 2), rectangle(0.5 * std.math.pi)));
    try testing.expectEqual(false, intersection(circle(vec(4, 2), 1.9), rectangle(0.5 * std.math.pi)));
    try testing.expectEqual(true, intersection(circle(vec(4, 2), 2.1), rectangle(0.5 * std.math.pi)));
    try testing.expectEqual(true, intersection(circle(vec(1, 2), 0.1), rectangle(0.25 * std.math.pi)));
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

test "doSlicesIntersect should return correct value" {
    const data = [_]i32{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };

    try testing.expectEqual(false, doSlicesIntersect(i32, data[5..5], data[5..5]));
    try testing.expectEqual(false, doSlicesIntersect(i32, data[0..5], data[5..10]));
    try testing.expectEqual(false, doSlicesIntersect(i32, data[5..10], data[0..5]));
    try testing.expectEqual(false, doSlicesIntersect(i32, data[1..4], data[6..9]));
    try testing.expectEqual(false, doSlicesIntersect(i32, data[6..9], data[1..4]));

    try testing.expectEqual(true, doSlicesIntersect(i32, data[0..6], data[5..10]));
    try testing.expectEqual(true, doSlicesIntersect(i32, data[4..10], data[0..5]));
    try testing.expectEqual(true, doSlicesIntersect(i32, data[1..8], data[2..9]));
    try testing.expectEqual(true, doSlicesIntersect(i32, data[2..9], data[1..8]));
    try testing.expectEqual(true, doSlicesIntersect(i32, data[1..9], data[4..6]));
    try testing.expectEqual(true, doSlicesIntersect(i32, data[4..6], data[1..9]));
}
