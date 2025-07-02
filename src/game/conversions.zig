const std = @import("std");
const game = @import("root.zig");
const math = @import("../math/root.zig");

const to_unreal_scale = 0.1;
const from_unreal_scale = 1.0 / to_unreal_scale;

pub fn pointToUnrealSpace(value: math.Vec3) math.Vec3 {
    return math.Vec3.fromArray(.{
        value.z() * to_unreal_scale,
        -value.x() * to_unreal_scale,
        value.y() * to_unreal_scale,
    });
}

pub fn pointFromUnrealSpace(value: math.Vec3) math.Vec3 {
    return math.Vec3.fromArray(.{
        -value.y() * from_unreal_scale,
        value.z() * from_unreal_scale,
        value.x() * from_unreal_scale,
    });
}

pub fn scaleToUnrealSpace(value: f32) f32 {
    return value * to_unreal_scale;
}

pub fn scaleFromUnrealSpace(value: f32) f32 {
    return value * from_unreal_scale;
}

pub fn hitLinePointToUnrealSpace(value: game.HitLinePoint) game.HitLinePoint {
    var converted = value;
    converted.position = pointToUnrealSpace(value.position);
    return converted;
}

pub fn hitLinePointFromUnrealSpace(value: game.HitLinePoint) game.HitLinePoint {
    var converted = value;
    converted.position = pointFromUnrealSpace(value.position);
    return converted;
}

pub fn hitLineToUnrealSpace(value: game.HitLine) game.HitLine {
    var converted: game.HitLine = value;
    for (value.points, 0..) |element, index| {
        converted.points[index] = hitLinePointToUnrealSpace(element);
    }
    return converted;
}

pub fn hitLineFromUnrealSpace(value: game.HitLine) game.HitLine {
    var converted: game.HitLine = value;
    for (value.points, 0..) |element, index| {
        converted.points[index] = hitLinePointFromUnrealSpace(element);
    }
    return converted;
}

pub fn hitLinesToUnrealSpace(value: game.HitLines) game.HitLines {
    var converted: game.HitLines = undefined;
    for (value, 0..) |element, index| {
        converted[index] = hitLineToUnrealSpace(element);
    }
    return converted;
}

pub fn hitLinesFromUnrealSpace(value: game.HitLines) game.HitLines {
    var converted: game.HitLines = undefined;
    for (value, 0..) |element, index| {
        converted[index] = hitLineFromUnrealSpace(element);
    }
    return converted;
}

pub fn hurtCylinderToUnrealSpace(value: game.HurtCylinder) game.HurtCylinder {
    var converted = value;
    converted.position = pointToUnrealSpace(value.position);
    converted.half_height = scaleToUnrealSpace(value.half_height);
    converted.squared_radius = scaleToUnrealSpace(scaleToUnrealSpace(value.squared_radius));
    converted.radius = scaleToUnrealSpace(value.radius);
    return converted;
}

pub fn hurtCylinderFromUnrealSpace(value: game.HurtCylinder) game.HurtCylinder {
    var converted = value;
    converted.position = pointFromUnrealSpace(value.position);
    converted.half_height = scaleFromUnrealSpace(value.half_height);
    converted.squared_radius = scaleFromUnrealSpace(scaleFromUnrealSpace(value.squared_radius));
    converted.radius = scaleFromUnrealSpace(value.radius);
    return converted;
}

pub fn hurtCylindersToUnrealSpace(value: game.HurtCylinders) game.HurtCylinders {
    var converted: game.HurtCylinders = undefined;
    for (value.asConstArray(), 0..) |element, index| {
        converted.asMutableArray()[index] = hurtCylinderToUnrealSpace(element);
    }
    return converted;
}

pub fn collisionSphereToUnrealSpace(value: game.CollisionSphere) game.CollisionSphere {
    var converted = value;
    converted.position = pointToUnrealSpace(value.position);
    converted.radius = scaleToUnrealSpace(value.radius);
    return converted;
}

pub fn collisionSphereFromUnrealSpace(value: game.CollisionSphere) game.CollisionSphere {
    var converted = value;
    converted.position = pointFromUnrealSpace(value.position);
    converted.radius = scaleFromUnrealSpace(value.radius);
    return converted;
}

pub fn hurtCylindersFromUnrealSpace(value: game.HurtCylinders) game.HurtCylinders {
    var converted: game.HurtCylinders = undefined;
    for (value.asConstArray(), 0..) |element, index| {
        converted.asMutableArray()[index] = hurtCylinderFromUnrealSpace(element);
    }
    return converted;
}

pub fn collisionSpheresToUnrealSpace(value: game.CollisionSpheres) game.CollisionSpheres {
    var converted: game.CollisionSpheres = undefined;
    for (value.asConstArray(), 0..) |element, index| {
        converted.asMutableArray()[index] = collisionSphereToUnrealSpace(element);
    }
    return converted;
}

pub fn collisionSpheresFromUnrealSpace(value: game.CollisionSpheres) game.CollisionSpheres {
    var converted: game.CollisionSpheres = undefined;
    for (value.asConstArray(), 0..) |element, index| {
        converted.asMutableArray()[index] = collisionSphereFromUnrealSpace(element);
    }
    return converted;
}

const testing = std.testing;

test "pointToUnrealSpace and pointFromUnrealSpace should cancel out" {
    const value = math.Vec3.fromArray(.{ 1, 2, 3 });
    try testing.expectEqual(value, pointToUnrealSpace(pointFromUnrealSpace(value)));
    try testing.expectEqual(value, pointFromUnrealSpace(pointToUnrealSpace(value)));
}

test "scaleToUnrealSpace and scaleFromUnrealSpace should cancel out" {
    const value: f32 = 123;
    try testing.expectEqual(value, scaleToUnrealSpace(scaleFromUnrealSpace(value)));
    try testing.expectEqual(value, scaleFromUnrealSpace(scaleToUnrealSpace(value)));
}

test "hitLinePointToUnrealSpace and hitLinePointFromUnrealSpace should cancel out" {
    const value = game.HitLinePoint{
        .position = .fromArray(.{ 1, 2, 3 }),
        ._padding = undefined,
    };
    try testing.expectEqual(value, hitLinePointToUnrealSpace(hitLinePointFromUnrealSpace(value)));
    try testing.expectEqual(value, hitLinePointFromUnrealSpace(hitLinePointToUnrealSpace(value)));
}

test "hitLineToUnrealSpace and hitLineFromUnrealSpace should cancel out" {
    const value = game.HitLine{
        .points = .{
            .{ .position = .fromArray(.{ 1, 2, 3 }), ._padding = undefined },
            .{ .position = .fromArray(.{ 4, 5, 6 }), ._padding = undefined },
            .{ .position = .fromArray(.{ 7, 8, 9 }), ._padding = undefined },
        },
        ._padding_1 = undefined,
        .ignore = true,
        ._padding_2 = undefined,
    };
    try testing.expectEqual(value, hitLineToUnrealSpace(hitLineFromUnrealSpace(value)));
    try testing.expectEqual(value, hitLineFromUnrealSpace(hitLineToUnrealSpace(value)));
}

test "hitLinesToUnrealSpace and hitLinesFromUnrealSpace should cancel out" {
    const line = game.HitLine{
        .points = .{
            .{ .position = .fromArray(.{ 1, 2, 3 }), ._padding = undefined },
            .{ .position = .fromArray(.{ 4, 5, 6 }), ._padding = undefined },
            .{ .position = .fromArray(.{ 7, 8, 9 }), ._padding = undefined },
        },
        ._padding_1 = undefined,
        .ignore = true,
        ._padding_2 = undefined,
    };
    const value: game.HitLines = [1]game.HitLine{line} ** 4;
    try testing.expectEqual(value, hitLinesToUnrealSpace(hitLinesFromUnrealSpace(value)));
    try testing.expectEqual(value, hitLinesFromUnrealSpace(hitLinesToUnrealSpace(value)));
}

test "hurtCylinderToUnrealSpace and hurtCylinderFromUnrealSpace should cancel out" {
    const value = game.HurtCylinder{
        .position = .fromArray(.{ 1, 2, 3 }),
        .multiplier = 4,
        .half_height = 5,
        .squared_radius = 6,
        .radius = 7,
        ._padding = undefined,
    };
    try testing.expectEqual(value, hurtCylinderToUnrealSpace(hurtCylinderFromUnrealSpace(value)));
    try testing.expectEqual(value, hurtCylinderFromUnrealSpace(hurtCylinderToUnrealSpace(value)));
}

test "collisionSphereToUnrealSpace and collisionSphereFromUnrealSpace should cancel out" {
    const value = game.CollisionSphere{
        .position = .fromArray(.{ 1, 2, 3 }),
        .multiplier = 4,
        .radius = 5,
        ._padding = undefined,
    };
    try testing.expectEqual(value, collisionSphereToUnrealSpace(collisionSphereFromUnrealSpace(value)));
    try testing.expectEqual(value, collisionSphereFromUnrealSpace(collisionSphereToUnrealSpace(value)));
}

test "hurtCylindersToUnrealSpace and hurtCylindersFromUnrealSpace should cancel out" {
    const cylinder = game.HurtCylinder{
        .position = .fromArray(.{ 1, 2, 3 }),
        .multiplier = 4,
        .half_height = 5,
        .squared_radius = 6,
        .radius = 7,
        ._padding = undefined,
    };
    const value = game.HurtCylinders{
        .left_ankle = cylinder,
        .right_ankle = cylinder,
        .left_hand = cylinder,
        .right_hand = cylinder,
        .left_knee = cylinder,
        .right_knee = cylinder,
        .left_elbow = cylinder,
        .right_elbow = cylinder,
        .head = cylinder,
        .left_shoulder = cylinder,
        .right_shoulder = cylinder,
        .upper_torso = cylinder,
        .left_pelvis = cylinder,
        .right_pelvis = cylinder,
    };
    try testing.expectEqual(value, hurtCylindersToUnrealSpace(hurtCylindersFromUnrealSpace(value)));
    try testing.expectEqual(value, hurtCylindersFromUnrealSpace(hurtCylindersToUnrealSpace(value)));
}

test "collisionSpheresToUnrealSpace and collisionSpheresFromUnrealSpace should cancel out" {
    const sphere = game.CollisionSphere{
        .position = .fromArray(.{ 1, 2, 3 }),
        .multiplier = 4,
        .radius = 5,
        ._padding = undefined,
    };
    const value = game.CollisionSpheres{
        .neck = sphere,
        .left_elbow = sphere,
        .right_elbow = sphere,
        .lower_torso = sphere,
        .left_knee = sphere,
        .right_knee = sphere,
        .left_ankle = sphere,
        .right_ankle = sphere,
    };
    try testing.expectEqual(value, collisionSpheresToUnrealSpace(collisionSpheresFromUnrealSpace(value)));
    try testing.expectEqual(value, collisionSpheresFromUnrealSpace(collisionSpheresToUnrealSpace(value)));
}
