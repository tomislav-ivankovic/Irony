const std = @import("std");
const game = @import("root.zig");

const to_unreal_scale = 0.1;
const from_unreal_scale = 1.0 / to_unreal_scale;

pub fn pointToUnrealSpace(value: [3]f32) [3]f32 {
    return .{
        value[2] * to_unreal_scale,
        -value[0] * to_unreal_scale,
        value[1] * to_unreal_scale,
    };
}

pub fn pointFromUnrealSpace(value: [3]f32) [3]f32 {
    return .{
        -value[1] * from_unreal_scale,
        value[2] * from_unreal_scale,
        value[0] * from_unreal_scale,
    };
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

pub fn hurtCylinderToUnrealSpace(value: game.HurtCylinder) game.HurtCylinder {
    var converted = value;
    converted.position = pointToUnrealSpace(value.position);
    converted.half_height = value.half_height * to_unreal_scale;
    converted.squared_radius = value.squared_radius * to_unreal_scale * to_unreal_scale;
    converted.radius = value.radius * to_unreal_scale;
    return converted;
}

pub fn hurtCylinderFromUnrealSpace(value: game.HurtCylinder) game.HurtCylinder {
    var converted = value;
    converted.position = pointFromUnrealSpace(value.position);
    converted.half_height = value.half_height * from_unreal_scale;
    converted.squared_radius = value.squared_radius * from_unreal_scale * from_unreal_scale;
    converted.radius = value.radius * from_unreal_scale;
    return converted;
}

pub fn collisionSphereToUnrealSpace(value: game.CollisionSphere) game.CollisionSphere {
    var converted = value;
    converted.position = pointToUnrealSpace(value.position);
    converted.radius = value.radius * to_unreal_scale;
    return converted;
}

pub fn collisionSphereFromUnrealSpace(value: game.CollisionSphere) game.CollisionSphere {
    var converted = value;
    converted.position = pointFromUnrealSpace(value.position);
    converted.radius = value.radius * from_unreal_scale;
    return converted;
}

const testing = std.testing;

test "pointToUnrealSpace and pointFromUnrealSpace should cancel out" {
    const value = [3]f32{ 1, 2, 3 };
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
        .position = .{ 1, 2, 3 },
        ._padding = undefined,
    };
    try testing.expectEqual(value, hitLinePointToUnrealSpace(hitLinePointFromUnrealSpace(value)));
    try testing.expectEqual(value, hitLinePointFromUnrealSpace(hitLinePointToUnrealSpace(value)));
}

test "hurtCylinderToUnrealSpace and hurtCylinderFromUnrealSpace should cancel out" {
    const value = game.HurtCylinder{
        .position = .{ 1, 2, 3 },
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
        .position = .{ 1, 2, 3 },
        .multiplier = 4,
        .radius = 5,
        ._padding = undefined,
    };
    try testing.expectEqual(value, collisionSphereToUnrealSpace(collisionSphereFromUnrealSpace(value)));
    try testing.expectEqual(value, collisionSphereFromUnrealSpace(collisionSphereToUnrealSpace(value)));
}
