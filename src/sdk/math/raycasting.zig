const std = @import("std");
const math = @import("root.zig");

pub const Ray2 = struct {
    origin: math.Vec2,
    direction: math.Vec2,
};

pub const RaycastLineSegmentResult = union(enum) {
    hit: Hit,
    overlap: Overlap,
    miss: void,

    pub const Overlap = struct {
        entrance_t: f32,
        exit_t: f32,
    };

    pub const Hit = struct {
        position: math.Vec2,
        normal: math.Vec2,
        t: f32,
    };
};

pub fn raycastLineSegment(ray: Ray2, line: math.LineSegment2) RaycastLineSegmentResult {
    const eps: f32 = 1e-6;
    const line_diff = line.point_2.subtract(line.point_1);
    const ray_cross_line = ray.direction.cross(line_diff);
    const origin_to_point_1 = line.point_1.subtract(ray.origin);
    const point_1_cross_direction = origin_to_point_1.cross(ray.direction);
    if (@abs(ray_cross_line) < eps) {
        if (@abs(origin_to_point_1.cross(ray.direction)) >= eps) {
            return .miss;
        }
        const squared_length = ray.direction.lengthSquared();
        const origin_to_point_2 = line.point_2.subtract(ray.origin);
        const t1 = origin_to_point_1.dot(ray.direction) / squared_length;
        const t2 = origin_to_point_2.dot(ray.direction) / squared_length;
        return .{ .overlap = .{
            .entrance_t = @min(t1, t2),
            .exit_t = @max(t1, t2),
        } };
    }
    const t = origin_to_point_1.cross(line_diff) / ray_cross_line;
    const u = point_1_cross_direction / ray_cross_line;
    if (u < 0 or u > 1) {
        return .miss;
    }
    const hit_pos = ray.origin.add(ray.direction.scale(t));
    var normal = math.Vec2.fromArray(.{ -line_diff.y(), line_diff.x() });
    normal = normal.normalize();
    if (normal.dot(ray.direction) > 0.0) {
        normal = normal.scale(-1.0);
    }
    return .{ .hit = .{
        .position = hit_pos,
        .normal = normal,
        .t = t,
    } };
}

pub const RaycastRectangleResult = union(enum) {
    hit: Hit,
    side_scrape: SideScrape,
    miss: void,

    pub const Hit = struct {
        entrance: HitPoint,
        exit: HitPoint,
    };

    pub const SideScrape = struct {
        entrance: HitPoint,
        exit: HitPoint,
        scraping_side_normal: math.Vec2,
    };

    pub const HitPoint = struct {
        position: math.Vec2,
        normal: math.Vec2,
        t: f32,
    };
};

pub fn raycastRectangle(ray: Ray2, rect: math.Rectangle) RaycastRectangleResult {
    const eps = 1e-6;
    const scrape_eps = 0.01;

    const world_to_local = math.Mat3.fromTranslation(rect.center.negate()).rotateZ(-rect.rotation);
    const local_to_world = math.Mat3.fromZRotation(rect.rotation).translate(rect.center);
    const local_ray = Ray2{
        .origin = ray.origin.pointTransform(world_to_local),
        .direction = ray.direction.directionTransform(world_to_local),
    };

    const min = rect.half_size.scale(-1.0);
    const max = rect.half_size;

    var entrance_t: f32 = -std.math.inf(f32);
    var entrance_normal: math.Vec2 = .zero;
    var exit_t: f32 = std.math.inf(f32);
    var exit_normal: math.Vec2 = .zero;
    var scrape_normal: math.Vec2 = .zero;

    if (@abs(local_ray.direction.x()) < eps) {
        if (local_ray.origin.x() - min.x() < -scrape_eps or local_ray.origin.x() - max.x() > scrape_eps) {
            return .miss;
        } else if (local_ray.origin.x() - min.x() < scrape_eps) {
            scrape_normal = .minus_x;
        } else if (local_ray.origin.x() - max.x() > -scrape_eps) {
            scrape_normal = .plus_x;
        }
    } else {
        const inv_dx = 1.0 / local_ray.direction.x();
        var tx1 = (min.x() - local_ray.origin.x()) * inv_dx;
        var tx2 = (max.x() - local_ray.origin.x()) * inv_dx;
        var tx1_normal = math.Vec2.minus_x;
        var tx2_normal = math.Vec2.plus_x;
        if (tx1 > tx2) {
            std.mem.swap(f32, &tx1, &tx2);
            std.mem.swap(math.Vec2, &tx1_normal, &tx2_normal);
        }
        if (tx1 > entrance_t) {
            entrance_t = tx1;
            entrance_normal = tx1_normal;
        }
        if (tx2 < exit_t) {
            exit_t = tx2;
            exit_normal = tx2_normal;
        }
    }

    if (@abs(local_ray.direction.y()) < eps) {
        if (local_ray.origin.y() - min.y() < -scrape_eps or local_ray.origin.y() - max.y() > scrape_eps) {
            return .miss;
        } else if (local_ray.origin.y() - min.y() < scrape_eps) {
            scrape_normal = .minus_y;
        } else if (local_ray.origin.y() - max.y() > -scrape_eps) {
            scrape_normal = .plus_y;
        }
    } else {
        const inv_dy = 1.0 / local_ray.direction.y();
        var ty1 = (min.y() - local_ray.origin.y()) * inv_dy;
        var ty2 = (max.y() - local_ray.origin.y()) * inv_dy;
        var ty1_normal = math.Vec2.minus_y;
        var ty2_normal = math.Vec2.plus_y;
        if (ty1 > ty2) {
            std.mem.swap(f32, &ty1, &ty2);
            std.mem.swap(math.Vec2, &ty1_normal, &ty2_normal);
        }
        if (ty1 > entrance_t) {
            entrance_t = ty1;
            entrance_normal = ty1_normal;
        }
        if (ty2 < exit_t) {
            exit_t = ty2;
            exit_normal = ty2_normal;
        }
    }

    if (entrance_t > exit_t) {
        return .miss;
    }

    const entrance = RaycastRectangleResult.HitPoint{
        .position = ray.origin.add(ray.direction.scale(entrance_t)),
        .normal = entrance_normal.directionTransform(local_to_world),
        .t = entrance_t,
    };
    const exit = RaycastRectangleResult.HitPoint{
        .position = ray.origin.add(ray.direction.scale(exit_t)),
        .normal = exit_normal.directionTransform(local_to_world),
        .t = exit_t,
    };
    return if (std.meta.eql(scrape_normal, .zero)) .{
        .hit = .{
            .entrance = entrance,
            .exit = exit,
        },
    } else .{
        .side_scrape = .{
            .entrance = entrance,
            .exit = exit,
            .scraping_side_normal = scrape_normal.directionTransform(local_to_world),
        },
    };
}

const testing = std.testing;

fn expectEqual(expected: anytype, actual: anytype) !void {
    if (@TypeOf(actual) == f32) {
        try testing.expectApproxEqAbs(expected, actual, 0.0001);
    } else if (@TypeOf(actual) == math.Vec2) {
        try testing.expectApproxEqAbs(expected.x(), actual.x(), 0.0001);
        try testing.expectApproxEqAbs(expected.y(), actual.y(), 0.0001);
    } else {
        try testing.expectEqual(expected, actual);
    }
}

test "raycastLineSegment should return hit with positive t when line segment is in front of ray" {
    const vec = struct {
        fn call(x: f32, y: f32) math.Vec2 {
            return math.Vec2.fromArray(.{ x, y });
        }
    }.call;
    const ray = struct {
        fn call(origin: math.Vec2, direction: math.Vec2) Ray2 {
            return .{ .origin = origin, .direction = direction };
        }
    }.call;
    const line = math.LineSegment2{ .point_1 = .fromArray(.{ 4, 1 }), .point_2 = .fromArray(.{ 1, 7 }) };

    const r1 = raycastLineSegment(ray(vec(0, 1), vec(1, 2)), line);
    try testing.expect(r1 == .hit);
    try expectEqual(vec(2, 5), r1.hit.position);
    try expectEqual(vec(-2, -1).normalize(), r1.hit.normal);
    try expectEqual(2, r1.hit.t);

    const r2 = raycastLineSegment(ray(vec(6, 6), vec(-1, -1)), line);
    try testing.expect(r2 == .hit);
    try expectEqual(vec(3, 3), r2.hit.position);
    try expectEqual(vec(2, 1).normalize(), r2.hit.normal);
    try expectEqual(3, r2.hit.t);

    const r3 = raycastLineSegment(ray(vec(0, 7), vec(1, 0)), line);
    try testing.expect(r3 == .hit);
    try expectEqual(vec(1, 7), r3.hit.position);
    try expectEqual(vec(-2, -1).normalize(), r3.hit.normal);
    try expectEqual(1, r3.hit.t);

    const r4 = raycastLineSegment(ray(vec(4, 2), vec(0, -1)), line);
    try testing.expect(r4 == .hit);
    try expectEqual(vec(4, 1), r4.hit.position);
    try expectEqual(vec(2, 1).normalize(), r4.hit.normal);
    try expectEqual(1, r4.hit.t);
}

test "raycastLineSegment should return hit with negative t when line segment is behind the ray" {
    const vec = struct {
        fn call(x: f32, y: f32) math.Vec2 {
            return math.Vec2.fromArray(.{ x, y });
        }
    }.call;
    const ray = struct {
        fn call(origin: math.Vec2, direction: math.Vec2) Ray2 {
            return .{ .origin = origin, .direction = direction };
        }
    }.call;
    const line = math.LineSegment2{ .point_1 = .fromArray(.{ 4, 1 }), .point_2 = .fromArray(.{ 1, 7 }) };

    const r1 = raycastLineSegment(ray(vec(0, 1), vec(-1, -2)), line);
    try testing.expect(r1 == .hit);
    try expectEqual(vec(2, 5), r1.hit.position);
    try expectEqual(vec(2, 1).normalize(), r1.hit.normal);
    try expectEqual(-2, r1.hit.t);

    const r2 = raycastLineSegment(ray(vec(6, 6), vec(1, 1)), line);
    try testing.expect(r2 == .hit);
    try expectEqual(vec(3, 3), r2.hit.position);
    try expectEqual(vec(-2, -1).normalize(), r2.hit.normal);
    try expectEqual(-3, r2.hit.t);

    const r3 = raycastLineSegment(ray(vec(0, 7), vec(-1, 0)), line);
    try testing.expect(r3 == .hit);
    try expectEqual(vec(1, 7), r3.hit.position);
    try expectEqual(vec(2, 1).normalize(), r3.hit.normal);
    try expectEqual(-1, r3.hit.t);

    const r4 = raycastLineSegment(ray(vec(4, 2), vec(0, 1)), line);
    try testing.expect(r4 == .hit);
    try expectEqual(vec(4, 1), r4.hit.position);
    try expectEqual(vec(-2, -1).normalize(), r4.hit.normal);
    try expectEqual(-1, r4.hit.t);
}

test "raycastLineSegment should return hit with zero t when ray originates from within line and is not parallel with line" {
    const vec = struct {
        fn call(x: f32, y: f32) math.Vec2 {
            return math.Vec2.fromArray(.{ x, y });
        }
    }.call;
    const ray = struct {
        fn call(origin: math.Vec2, direction: math.Vec2) Ray2 {
            return .{ .origin = origin, .direction = direction };
        }
    }.call;
    const line = math.LineSegment2{ .point_1 = .fromArray(.{ 4, 1 }), .point_2 = .fromArray(.{ 1, 7 }) };

    const r1 = raycastLineSegment(ray(vec(3, 3), vec(-1, -1)), line);
    try testing.expect(r1 == .hit);
    try expectEqual(vec(3, 3), r1.hit.position);
    try expectEqual(vec(2, 1).normalize(), r1.hit.normal);
    try expectEqual(0, r1.hit.t);

    const r2 = raycastLineSegment(ray(vec(2, 5), vec(1, 2)), line);
    try testing.expect(r2 == .hit);
    try expectEqual(vec(2, 5), r2.hit.position);
    try expectEqual(vec(-2, -1).normalize(), r2.hit.normal);
    try expectEqual(0, r2.hit.t);

    const r3 = raycastLineSegment(ray(vec(1, 7), vec(1, 0)), line);
    try testing.expect(r3 == .hit);
    try expectEqual(vec(1, 7), r3.hit.position);
    try expectEqual(vec(-2, -1).normalize(), r3.hit.normal);
    try expectEqual(0, r3.hit.t);

    const r4 = raycastLineSegment(ray(vec(4, 1), vec(0, -1)), line);
    try testing.expect(r4 == .hit);
    try expectEqual(vec(4, 1), r4.hit.position);
    try expectEqual(vec(2, 1).normalize(), r4.hit.normal);
    try expectEqual(0, r4.hit.t);
}

test "raycastLineSegment should return overlap when ray line passes through line segment" {
    const vec = struct {
        fn call(x: f32, y: f32) math.Vec2 {
            return math.Vec2.fromArray(.{ x, y });
        }
    }.call;
    const ray = struct {
        fn call(origin: math.Vec2, direction: math.Vec2) Ray2 {
            return .{ .origin = origin, .direction = direction };
        }
    }.call;
    const line = math.LineSegment2{ .point_1 = .fromArray(.{ 4, 1 }), .point_2 = .fromArray(.{ 1, 7 }) };

    const r1 = raycastLineSegment(ray(vec(-1, 11), vec(1, -2)), line);
    try testing.expect(r1 == .overlap);
    try expectEqual(2, r1.overlap.entrance_t);
    try expectEqual(5, r1.overlap.exit_t);

    const r2 = raycastLineSegment(ray(vec(-1, 11), vec(-1, 2)), line);
    try testing.expect(r2 == .overlap);
    try expectEqual(-5, r2.overlap.entrance_t);
    try expectEqual(-2, r2.overlap.exit_t);

    const r3 = raycastLineSegment(ray(vec(4, 1), vec(-1, 2)), line);
    try testing.expect(r3 == .overlap);
    try expectEqual(0, r3.overlap.entrance_t);
    try expectEqual(3, r3.overlap.exit_t);

    const r4 = raycastLineSegment(ray(vec(4, 1), vec(1, -2)), line);
    try testing.expect(r4 == .overlap);
    try expectEqual(-3, r4.overlap.entrance_t);
    try expectEqual(0, r4.overlap.exit_t);
}

test "raycastLineSegment should return miss when ray misses the line segment" {
    const vec = struct {
        fn call(x: f32, y: f32) math.Vec2 {
            return math.Vec2.fromArray(.{ x, y });
        }
    }.call;
    const ray = struct {
        fn call(origin: math.Vec2, direction: math.Vec2) Ray2 {
            return .{ .origin = origin, .direction = direction };
        }
    }.call;
    const line = math.LineSegment2{ .point_1 = .fromArray(.{ 4, 1 }), .point_2 = .fromArray(.{ 1, 7 }) };

    try expectEqual(.miss, raycastLineSegment(ray(vec(0, 0), vec(1, 0)), line));
    try expectEqual(.miss, raycastLineSegment(ray(vec(0, 0), vec(0, 1)), line));
    try expectEqual(.miss, raycastLineSegment(ray(vec(2, 3), vec(-1, 2)), line));
    try expectEqual(.miss, raycastLineSegment(ray(vec(3, 5), vec(1, -2)), line));
}

test "raycastRectangle should return hit with positive t values when rectangle is in front of the ray" {
    const vec = struct {
        fn call(x: f32, y: f32) math.Vec2 {
            return math.Vec2.fromArray(.{ x, y });
        }
    }.call;
    const ray = struct {
        fn call(origin: math.Vec2, direction: math.Vec2) Ray2 {
            return .{ .origin = origin, .direction = direction };
        }
    }.call;
    const rect = math.Rectangle{
        .center = .fromArray(.{ 10, 11 }),
        .half_size = .fromArray(.{ 5, 10 }),
        .rotation = -std.math.atan2(@as(f32, 6), @as(f32, 8)),
    };

    const r1 = raycastRectangle(ray(vec(-3, 2), vec(7, 1)), rect);
    try testing.expect(r1 == .hit);
    try expectEqual(vec(4, 3), r1.hit.entrance.position);
    try expectEqual(vec(0, -1).rotateZ(rect.rotation), r1.hit.entrance.normal);
    try expectEqual(1, r1.hit.entrance.t);
    try expectEqual(vec(11, 4), r1.hit.exit.position);
    try expectEqual(vec(1, 0).rotateZ(rect.rotation), r1.hit.exit.normal);
    try expectEqual(2, r1.hit.exit.t);

    const r2 = raycastRectangle(ray(vec(-5, 16), vec(4, -3)), rect);
    try testing.expect(r2 == .hit);
    try expectEqual(vec(3, 10), r2.hit.entrance.position);
    try expectEqual(vec(-1, 0).rotateZ(rect.rotation), r2.hit.entrance.normal);
    try expectEqual(2, r2.hit.entrance.t);
    try expectEqual(vec(11, 4), r2.hit.exit.position);
    try expectEqual(vec(1, 0).rotateZ(rect.rotation), r2.hit.exit.normal);
    try expectEqual(4, r2.hit.exit.t);

    const r3 = raycastRectangle(ray(vec(19, 23), vec(-3, -4)), rect);
    try testing.expect(r3 == .hit);
    try expectEqual(vec(16, 19), r3.hit.entrance.position);
    try expectEqual(vec(0, 1).rotateZ(rect.rotation), r3.hit.entrance.normal);
    try expectEqual(1, r3.hit.entrance.t);
    try expectEqual(vec(4, 3), r3.hit.exit.position);
    try expectEqual(vec(0, -1).rotateZ(rect.rotation), r3.hit.exit.normal);
    try expectEqual(5, r3.hit.exit.t);

    const r4 = raycastRectangle(ray(vec(12, -3), vec(2, 11)), rect);
    try testing.expect(r4 == .hit);
    try expectEqual(vec(14, 8), r4.hit.entrance.position);
    try expectEqual(vec(1, 0).rotateZ(rect.rotation), r4.hit.entrance.normal);
    try expectEqual(1, r4.hit.entrance.t);
    try expectEqual(vec(16, 19), r4.hit.exit.position);
    try expectEqual(vec(0, 1).rotateZ(rect.rotation), r4.hit.exit.normal);
    try expectEqual(2, r4.hit.exit.t);
}

test "raycastRectangle should return hit with negative t values when rectangle is behind the ray" {
    const vec = struct {
        fn call(x: f32, y: f32) math.Vec2 {
            return math.Vec2.fromArray(.{ x, y });
        }
    }.call;
    const ray = struct {
        fn call(origin: math.Vec2, direction: math.Vec2) Ray2 {
            return .{ .origin = origin, .direction = direction };
        }
    }.call;
    const rect = math.Rectangle{
        .center = .fromArray(.{ 10, 11 }),
        .half_size = .fromArray(.{ 5, 10 }),
        .rotation = -std.math.atan2(@as(f32, 6), @as(f32, 8)),
    };

    const r1 = raycastRectangle(ray(vec(-3, 2), vec(-7, -1)), rect);
    try testing.expect(r1 == .hit);
    try expectEqual(vec(11, 4), r1.hit.entrance.position);
    try expectEqual(vec(1, 0).rotateZ(rect.rotation), r1.hit.entrance.normal);
    try expectEqual(-2, r1.hit.entrance.t);
    try expectEqual(vec(4, 3), r1.hit.exit.position);
    try expectEqual(vec(0, -1).rotateZ(rect.rotation), r1.hit.exit.normal);
    try expectEqual(-1, r1.hit.exit.t);

    const r2 = raycastRectangle(ray(vec(-5, 16), vec(-4, 3)), rect);
    try testing.expect(r2 == .hit);
    try expectEqual(vec(11, 4), r2.hit.entrance.position);
    try expectEqual(vec(1, 0).rotateZ(rect.rotation), r2.hit.entrance.normal);
    try expectEqual(-4, r2.hit.entrance.t);
    try expectEqual(vec(3, 10), r2.hit.exit.position);
    try expectEqual(vec(-1, 0).rotateZ(rect.rotation), r2.hit.exit.normal);
    try expectEqual(-2, r2.hit.exit.t);

    const r3 = raycastRectangle(ray(vec(19, 23), vec(3, 4)), rect);
    try testing.expect(r3 == .hit);
    try expectEqual(vec(4, 3), r3.hit.entrance.position);
    try expectEqual(vec(0, -1).rotateZ(rect.rotation), r3.hit.entrance.normal);
    try expectEqual(-5, r3.hit.entrance.t);
    try expectEqual(vec(16, 19), r3.hit.exit.position);
    try expectEqual(vec(0, 1).rotateZ(rect.rotation), r3.hit.exit.normal);
    try expectEqual(-1, r3.hit.exit.t);

    const r4 = raycastRectangle(ray(vec(12, -3), vec(-2, -11)), rect);
    try testing.expect(r4 == .hit);
    try expectEqual(vec(16, 19), r4.hit.entrance.position);
    try expectEqual(vec(0, 1).rotateZ(rect.rotation), r4.hit.entrance.normal);
    try expectEqual(-2, r4.hit.entrance.t);
    try expectEqual(vec(14, 8), r4.hit.exit.position);
    try expectEqual(vec(1, 0).rotateZ(rect.rotation), r4.hit.exit.normal);
    try expectEqual(-1, r4.hit.exit.t);
}

test "raycastRectangle should return hit with non-positive t entrance and non-negative t exit when ray originates within the rectangle" {
    const vec = struct {
        fn call(x: f32, y: f32) math.Vec2 {
            return math.Vec2.fromArray(.{ x, y });
        }
    }.call;
    const ray = struct {
        fn call(origin: math.Vec2, direction: math.Vec2) Ray2 {
            return .{ .origin = origin, .direction = direction };
        }
    }.call;
    const rect = math.Rectangle{
        .center = .fromArray(.{ 10, 11 }),
        .half_size = .fromArray(.{ 5, 10 }),
        .rotation = -std.math.atan2(@as(f32, 6), @as(f32, 8)),
    };

    const r1 = raycastRectangle(ray(vec(4, 3), vec(7, 1)), rect);
    try testing.expect(r1 == .hit);
    try expectEqual(vec(4, 3), r1.hit.entrance.position);
    try expectEqual(vec(0, -1).rotateZ(rect.rotation), r1.hit.entrance.normal);
    try expectEqual(0, r1.hit.entrance.t);
    try expectEqual(vec(11, 4), r1.hit.exit.position);
    try expectEqual(vec(1, 0).rotateZ(rect.rotation), r1.hit.exit.normal);
    try expectEqual(1, r1.hit.exit.t);

    const r2 = raycastRectangle(ray(vec(7, 7), vec(4, -3)), rect);
    try testing.expect(r2 == .hit);
    try expectEqual(vec(3, 10), r2.hit.entrance.position);
    try expectEqual(vec(-1, 0).rotateZ(rect.rotation), r2.hit.entrance.normal);
    try expectEqual(-1, r2.hit.entrance.t);
    try expectEqual(vec(11, 4), r2.hit.exit.position);
    try expectEqual(vec(1, 0).rotateZ(rect.rotation), r2.hit.exit.normal);
    try expectEqual(1, r2.hit.exit.t);

    const r3 = raycastRectangle(ray(vec(7, 7), vec(-3, -4)), rect);
    try testing.expect(r3 == .hit);
    try expectEqual(vec(16, 19), r3.hit.entrance.position);
    try expectEqual(vec(0, 1).rotateZ(rect.rotation), r3.hit.entrance.normal);
    try expectEqual(-3, r3.hit.entrance.t);
    try expectEqual(vec(4, 3), r3.hit.exit.position);
    try expectEqual(vec(0, -1).rotateZ(rect.rotation), r3.hit.exit.normal);
    try expectEqual(1, r3.hit.exit.t);

    const r4 = raycastRectangle(ray(vec(16, 19), vec(2, 11)), rect);
    try testing.expect(r4 == .hit);
    try expectEqual(vec(14, 8), r4.hit.entrance.position);
    try expectEqual(vec(1, 0).rotateZ(rect.rotation), r4.hit.entrance.normal);
    try expectEqual(-1, r4.hit.entrance.t);
    try expectEqual(vec(16, 19), r4.hit.exit.position);
    try expectEqual(vec(0, 1).rotateZ(rect.rotation), r4.hit.exit.normal);
    try expectEqual(0, r4.hit.exit.t);
}

test "raycastRectangle should return side scrape when ray is overlapping with a rectangle's side" {
    const vec = struct {
        fn call(x: f32, y: f32) math.Vec2 {
            return math.Vec2.fromArray(.{ x, y });
        }
    }.call;
    const ray = struct {
        fn call(origin: math.Vec2, direction: math.Vec2) Ray2 {
            return .{ .origin = origin, .direction = direction };
        }
    }.call;
    const rect = math.Rectangle{
        .center = .fromArray(.{ 10, 11 }),
        .half_size = .fromArray(.{ 5, 10 }),
        .rotation = -std.math.atan2(@as(f32, 6), @as(f32, 8)),
    };

    const r1 = raycastRectangle(ray(vec(5, -4), vec(3, 4)), rect);
    try testing.expect(r1 == .side_scrape);
    try expectEqual(vec(8, 0), r1.side_scrape.entrance.position);
    try expectEqual(vec(0, -1).rotateZ(rect.rotation), r1.side_scrape.entrance.normal);
    try expectEqual(1, r1.side_scrape.entrance.t);
    try expectEqual(vec(20, 16), r1.side_scrape.exit.position);
    try expectEqual(vec(0, 1).rotateZ(rect.rotation), r1.side_scrape.exit.normal);
    try expectEqual(5, r1.side_scrape.exit.t);
    try expectEqual(vec(1, 0).rotateZ(rect.rotation), r1.side_scrape.scraping_side_normal);

    const r2 = raycastRectangle(ray(vec(4, 3), vec(4, -3)), rect);
    try testing.expect(r2 == .side_scrape);
    try expectEqual(vec(0, 6), r2.side_scrape.entrance.position);
    try expectEqual(vec(-1, 0).rotateZ(rect.rotation), r2.side_scrape.entrance.normal);
    try expectEqual(-1, r2.side_scrape.entrance.t);
    try expectEqual(vec(8, 0), r2.side_scrape.exit.position);
    try expectEqual(vec(1, 0).rotateZ(rect.rotation), r2.side_scrape.exit.normal);
    try expectEqual(1, r2.side_scrape.exit.t);
    try expectEqual(vec(0, -1).rotateZ(rect.rotation), r2.side_scrape.scraping_side_normal);

    const r3 = raycastRectangle(ray(vec(0, 6), vec(3, 4)), rect);
    try testing.expect(r3 == .side_scrape);
    try expectEqual(vec(0, 6), r3.side_scrape.entrance.position);
    try expectEqual(vec(0, -1).rotateZ(rect.rotation), r3.side_scrape.entrance.normal);
    try expectEqual(0, r3.side_scrape.entrance.t);
    try expectEqual(vec(12, 22), r3.side_scrape.exit.position);
    try expectEqual(vec(0, 1).rotateZ(rect.rotation), r3.side_scrape.exit.normal);
    try expectEqual(4, r3.side_scrape.exit.t);
    try expectEqual(vec(-1, 0).rotateZ(rect.rotation), r3.side_scrape.scraping_side_normal);

    const r4 = raycastRectangle(ray(vec(20, 16), vec(4, -3)), rect);
    try testing.expect(r4 == .side_scrape);
    try expectEqual(vec(12, 22), r4.side_scrape.entrance.position);
    try expectEqual(vec(-1, 0).rotateZ(rect.rotation), r4.side_scrape.entrance.normal);
    try expectEqual(-2, r4.side_scrape.entrance.t);
    try expectEqual(vec(20, 16), r4.side_scrape.exit.position);
    try expectEqual(vec(1, 0).rotateZ(rect.rotation), r4.side_scrape.exit.normal);
    try expectEqual(0, r4.side_scrape.exit.t);
    try expectEqual(vec(0, 1).rotateZ(rect.rotation), r4.side_scrape.scraping_side_normal);
}

test "raycastRectangle should return miss when the ray completely misses the rectangle" {
    const vec = struct {
        fn call(x: f32, y: f32) math.Vec2 {
            return math.Vec2.fromArray(.{ x, y });
        }
    }.call;
    const ray = struct {
        fn call(origin: math.Vec2, direction: math.Vec2) Ray2 {
            return .{ .origin = origin, .direction = direction };
        }
    }.call;
    const rect = math.Rectangle{
        .center = .fromArray(.{ 10, 11 }),
        .half_size = .fromArray(.{ 5, 10 }),
        .rotation = -std.math.atan2(@as(f32, 6), @as(f32, 8)),
    };

    try expectEqual(.miss, raycastRectangle(ray(vec(0, -1), vec(1, 0)), rect));
    try expectEqual(.miss, raycastRectangle(ray(vec(-1, 0), vec(0, 1)), rect));
    try expectEqual(.miss, raycastRectangle(ray(vec(0, -1), vec(1, 0)), rect));
    try expectEqual(.miss, raycastRectangle(ray(vec(9, 0), vec(3, 4)), rect));
    try expectEqual(.miss, raycastRectangle(ray(vec(8, -1), vec(-4, 3)), rect));
}
