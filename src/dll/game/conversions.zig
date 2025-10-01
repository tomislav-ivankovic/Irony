const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const game = @import("root.zig");

const to_unreal_scale = 0.1;
const from_unreal_scale = 1.0 / to_unreal_scale;

pub const conversion_globals = struct {
    pub var decryptHealth: ?*const game.DecryptHealthFunction = null;
};

pub fn scaleToUnrealSpace(value: f32) f32 {
    return value * to_unreal_scale;
}

pub fn scaleFromUnrealSpace(value: f32) f32 {
    return value * from_unreal_scale;
}

pub fn pointToUnrealSpace(value: sdk.math.Vec3) sdk.math.Vec3 {
    return sdk.math.Vec3.fromArray(.{
        value.z() * to_unreal_scale,
        -value.x() * to_unreal_scale,
        value.y() * to_unreal_scale,
    });
}

pub fn pointFromUnrealSpace(value: sdk.math.Vec3) sdk.math.Vec3 {
    return sdk.math.Vec3.fromArray(.{
        -value.y() * from_unreal_scale,
        value.z() * from_unreal_scale,
        value.x() * from_unreal_scale,
    });
}

pub fn matrixToUnrealSpace(value: sdk.math.Mat4) sdk.math.Mat4 {
    const conversion_matrix = comptime sdk.math.Mat4.fromArray(.{
        pointToUnrealSpace(sdk.math.Vec3.plus_x).extend(0).array,
        pointToUnrealSpace(sdk.math.Vec3.plus_y).extend(0).array,
        pointToUnrealSpace(sdk.math.Vec3.plus_z).extend(0).array,
        .{ 0, 0, 0, 1 },
    });
    return value.multiply(conversion_matrix);
}

pub fn matrixFromUnrealSpace(value: sdk.math.Mat4) sdk.math.Mat4 {
    const conversion_matrix = comptime sdk.math.Mat4.fromArray(.{
        pointFromUnrealSpace(sdk.math.Vec3.plus_x).extend(0).array,
        pointFromUnrealSpace(sdk.math.Vec3.plus_y).extend(0).array,
        pointFromUnrealSpace(sdk.math.Vec3.plus_z).extend(0).array,
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
    if (value[0] != 0 and value[0] != 1) {
        return null; // Decrypting invalid encrypted health value can cause a crash. This prevents it.
    }
    const decrypt = conversion_globals.decryptHealth orelse return null;
    const shifted = decrypt(&value);
    return @intCast(shifted >> 16);
}

pub fn rawToConvertedCamera(value: game.RawCamera) game.ConvertedCamera {
    return .{
        .position = .fromArray(.{
            @floatCast(value.position.array[0]),
            @floatCast(value.position.array[1]),
            @floatCast(value.position.array[2]),
        }),
        .pitch = @floatCast(std.math.degreesToRadians(value.pitch)),
        .yaw = @floatCast(std.math.degreesToRadians(value.yaw)),
        .roll = @floatCast(std.math.degreesToRadians(value.roll)),
    };
}

pub fn convertedToRawCamera(value: game.ConvertedCamera) game.RawCamera {
    return .{
        .position = .fromArray(.{
            @floatCast(value.position.array[0]),
            @floatCast(value.position.array[1]),
            @floatCast(value.position.array[2]),
        }),
        .pitch = @floatCast(std.math.radiansToDegrees(value.pitch)),
        .yaw = @floatCast(std.math.radiansToDegrees(value.yaw)),
        .roll = @floatCast(std.math.radiansToDegrees(value.roll)),
    };
}

const testing = std.testing;

test "scaleToUnrealSpace and scaleFromUnrealSpace should cancel out" {
    const value: f32 = 123;
    try testing.expectEqual(value, scaleToUnrealSpace(scaleFromUnrealSpace(value)));
    try testing.expectEqual(value, scaleFromUnrealSpace(scaleToUnrealSpace(value)));
}

test "pointToUnrealSpace and pointFromUnrealSpace should cancel out" {
    const value = sdk.math.Vec3.fromArray(.{ 1, 2, 3 });
    try testing.expectEqual(value, pointToUnrealSpace(pointFromUnrealSpace(value)));
    try testing.expectEqual(value, pointFromUnrealSpace(pointToUnrealSpace(value)));
}

test "matrixToUnrealSpace and matrixFromUnrealSpace should cancel out" {
    const value = sdk.math.Mat4.fromArray(.{
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
        .ignore = .true,
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

test "rawToConvertedCamera and convertedToRawCamera should cancel out" {
    const converted = game.ConvertedCamera{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 0.25 * std.math.pi,
        .roll = 0.5 * std.math.pi,
        .yaw = 0.75 * std.math.pi,
    };
    try testing.expectEqual(converted, rawToConvertedCamera(convertedToRawCamera(converted)));
    const raw = game.RawCamera{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 45,
        .roll = 90,
        .yaw = 135,
    };
    try testing.expectEqual(raw, convertedToRawCamera(rawToConvertedCamera(raw)));
}
