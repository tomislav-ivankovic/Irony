const std = @import("std");
const game = @import("root.zig");
const math = @import("../math/root.zig");

const to_unreal_scale = 0.1;
const from_unreal_scale = 1.0 / to_unreal_scale;

pub const conversion_globals = struct {
    pub var decrypt_health_function: ?*const game.DecryptHealthFunction = null;
};

pub fn scaleToUnrealSpace(value: f32) f32 {
    return value * to_unreal_scale;
}

pub fn scaleFromUnrealSpace(value: f32) f32 {
    return value * from_unreal_scale;
}

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

pub fn matrixToUnrealSpace(value: math.Mat4) math.Mat4 {
    const conversion_matrix = comptime math.Mat4.fromArray(.{
        pointToUnrealSpace(math.Vec3.plus_x).extend(0).array,
        pointToUnrealSpace(math.Vec3.plus_y).extend(0).array,
        pointToUnrealSpace(math.Vec3.plus_z).extend(0).array,
        .{ 0, 0, 0, 1 },
    });
    return value.multiply(conversion_matrix);
}

pub fn matrixFromUnrealSpace(value: math.Mat4) math.Mat4 {
    const conversion_matrix = comptime math.Mat4.fromArray(.{
        pointFromUnrealSpace(math.Vec3.plus_x).extend(0).array,
        pointFromUnrealSpace(math.Vec3.plus_y).extend(0).array,
        pointFromUnrealSpace(math.Vec3.plus_z).extend(0).array,
        .{ 0, 0, 0, 1 },
    });
    return value.multiply(conversion_matrix);
}

pub fn u16ToRadians(value: u16) f32 {
    const u16_max: comptime_float = comptime @floatFromInt(std.math.maxInt(u16));
    const two_pi = comptime 2.0 * std.math.pi;
    const conversion_factor = comptime -1.0 * two_pi / (u16_max + 1.0);
    const float_value: f32 = @floatFromInt(value);
    var converted = float_value * conversion_factor;
    if (converted < -std.math.pi) {
        converted += two_pi;
    }
    return converted;
}

pub fn u16FromRadians(value: f32) u16 {
    const u16_max: comptime_float = comptime @floatFromInt(std.math.maxInt(u16));
    const two_pi = comptime 2.0 * std.math.pi;
    const conversion_factor = comptime -1.0 * (u16_max + 1.0) / two_pi;
    var normalized = value;
    while (normalized < -two_pi) {
        normalized += two_pi;
    }
    while (normalized > 0) {
        normalized -= two_pi;
    }
    return @intFromFloat(normalized * conversion_factor);
}

pub fn hitLineToUnrealSpace(value: game.HitLine) game.HitLine {
    var converted: game.HitLine = value;
    for (value.points, 0..) |element, index| {
        converted.points[index].position = pointToUnrealSpace(element.position);
    }
    return converted;
}

pub fn hitLineFromUnrealSpace(value: game.HitLine) game.HitLine {
    var converted: game.HitLine = value;
    for (value.points, 0..) |element, index| {
        converted.points[index].position = pointFromUnrealSpace(element.position);
    }
    return converted;
}

pub fn hurtCylinderToUnrealSpace(value: game.HurtCylinder) game.HurtCylinder {
    var converted = value;
    converted.center = pointToUnrealSpace(value.center);
    converted.half_height = scaleToUnrealSpace(value.half_height);
    converted.squared_radius = scaleToUnrealSpace(scaleToUnrealSpace(value.squared_radius));
    converted.radius = scaleToUnrealSpace(value.radius);
    return converted;
}

pub fn hurtCylinderFromUnrealSpace(value: game.HurtCylinder) game.HurtCylinder {
    var converted = value;
    converted.center = pointFromUnrealSpace(value.center);
    converted.half_height = scaleFromUnrealSpace(value.half_height);
    converted.squared_radius = scaleFromUnrealSpace(scaleFromUnrealSpace(value.squared_radius));
    converted.radius = scaleFromUnrealSpace(value.radius);
    return converted;
}

pub fn collisionSphereToUnrealSpace(value: game.CollisionSphere) game.CollisionSphere {
    var converted = value;
    converted.center = pointToUnrealSpace(value.center);
    converted.radius = scaleToUnrealSpace(value.radius);
    return converted;
}

pub fn collisionSphereFromUnrealSpace(value: game.CollisionSphere) game.CollisionSphere {
    var converted = value;
    converted.center = pointFromUnrealSpace(value.center);
    converted.radius = scaleFromUnrealSpace(value.radius);
    return converted;
}

const max_int_heat_gauge = 23039456;

pub fn decryptHeatGauge(value: u32) f32 {
    const int_value = std.math.rotl(u32, value, @as(usize, 8));
    const float_value: f32 = @floatFromInt(int_value);
    return float_value / max_int_heat_gauge;
}

pub fn encryptHeatGauge(value: f32) u32 {
    const float_value = value * max_int_heat_gauge;
    const int_value: u32 = @intFromFloat(float_value);
    return std.math.rotr(u32, int_value, @as(usize, 8));
}

pub fn decryptHealth(value: game.EncryptedHealth) ?i32 {
    const decrypt = conversion_globals.decrypt_health_function orelse return null;
    const shifted = decrypt(&value);
    return @intCast(shifted >> 16);
}

const testing = std.testing;

test "scaleToUnrealSpace and scaleFromUnrealSpace should cancel out" {
    const value: f32 = 123;
    try testing.expectEqual(value, scaleToUnrealSpace(scaleFromUnrealSpace(value)));
    try testing.expectEqual(value, scaleFromUnrealSpace(scaleToUnrealSpace(value)));
}

test "pointToUnrealSpace and pointFromUnrealSpace should cancel out" {
    const value = math.Vec3.fromArray(.{ 1, 2, 3 });
    try testing.expectEqual(value, pointToUnrealSpace(pointFromUnrealSpace(value)));
    try testing.expectEqual(value, pointFromUnrealSpace(pointToUnrealSpace(value)));
}

test "matrixToUnrealSpace and matrixFromUnrealSpace should cancel out" {
    const value = math.Mat4.fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 8, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    const result_1 = matrixToUnrealSpace(matrixFromUnrealSpace(value));
    const result_2 = matrixFromUnrealSpace(matrixToUnrealSpace(value));
    for (0..4) |i| {
        for (0..4) |j| {
            try testing.expectApproxEqAbs(value.array[i][j], result_1.array[i][j], 0.0001);
            try testing.expectApproxEqAbs(value.array[i][j], result_2.array[i][j], 0.0001);
        }
    }
}

test "u16ToRadians and u16FromRadians should cancel out" {
    try testing.expectApproxEqAbs(-0.5 * std.math.pi, u16ToRadians(u16FromRadians(-0.5 * std.math.pi)), 0.000001);
    try testing.expectEqual(0xAAAA, u16FromRadians(u16ToRadians(0xAAAA)));
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

test "hurtCylinderToUnrealSpace and hurtCylinderFromUnrealSpace should cancel out" {
    const value = game.HurtCylinder{
        .center = .fromArray(.{ 1, 2, 3 }),
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
        .center = .fromArray(.{ 1, 2, 3 }),
        .multiplier = 4,
        .radius = 5,
        ._padding = undefined,
    };
    try testing.expectEqual(value, collisionSphereToUnrealSpace(collisionSphereFromUnrealSpace(value)));
    try testing.expectEqual(value, collisionSphereFromUnrealSpace(collisionSphereToUnrealSpace(value)));
}

test "decryptHeatGauge and encryptHeatGauge should cancel out" {
    try testing.expectEqual(0.12345, decryptHeatGauge(encryptHeatGauge(0.12345)));
    try testing.expectEqual(12345, encryptHeatGauge(decryptHeatGauge(12345)));
}
