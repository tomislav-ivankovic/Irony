const std = @import("std");
const sdk = @import("../../../sdk/root.zig");
const t7 = @import("root.zig");

const to_unreal_scale = 0.1;
const from_unreal_scale = 1.0 / to_unreal_scale;

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

pub fn hitLinePointToUnrealSpace(value: t7.HitLinePoint) t7.HitLinePoint {
    var converted = value;
    converted.position = pointToUnrealSpace(value.position);
    return converted;
}

pub fn hitLinePointFromUnrealSpace(value: t7.HitLinePoint) t7.HitLinePoint {
    var converted = value;
    converted.position = pointFromUnrealSpace(value.position);
    return converted;
}

pub fn hurtCylinderToUnrealSpace(value: t7.HurtCylinder) t7.HurtCylinder {
    var converted = value;
    converted.center = pointToUnrealSpace(value.center);
    converted.half_height = scaleToUnrealSpace(value.half_height);
    converted.squared_radius = scaleToUnrealSpace(scaleToUnrealSpace(value.squared_radius));
    converted.radius = scaleToUnrealSpace(value.radius);
    return converted;
}

pub fn hurtCylinderFromUnrealSpace(value: t7.HurtCylinder) t7.HurtCylinder {
    var converted = value;
    converted.center = pointFromUnrealSpace(value.center);
    converted.half_height = scaleFromUnrealSpace(value.half_height);
    converted.squared_radius = scaleFromUnrealSpace(scaleFromUnrealSpace(value.squared_radius));
    converted.radius = scaleFromUnrealSpace(value.radius);
    return converted;
}

pub fn collisionSphereToUnrealSpace(value: t7.CollisionSphere) t7.CollisionSphere {
    var converted = value;
    converted.center = pointToUnrealSpace(value.center);
    converted.radius = scaleToUnrealSpace(value.radius);
    return converted;
}

pub fn collisionSphereFromUnrealSpace(value: t7.CollisionSphere) t7.CollisionSphere {
    var converted = value;
    converted.center = pointFromUnrealSpace(value.center);
    converted.radius = scaleFromUnrealSpace(value.radius);
    return converted;
}

const cc = std.zig.c_translation.cast;

pub fn decryptHealth(value: t7.HealthWithEncryptionKey) t7.HealthWithEncryptionKey {
    var converted = value;
    converted.health = cc(u32, sub_14504f430_decrypt(cc(i32, converted.health), cc(i64, converted.encryption_key)));
    converted.health = converted.health >> 16;
    return converted;
}

pub fn encryptHealth(value: t7.HealthWithEncryptionKey) t7.HealthWithEncryptionKey {
    var converted = value;
    converted.health = converted.health << 16;
    converted.health = cc(u32, sub_1451dd670_encrypt(cc(i32, converted.health), cc(i64, converted.encryption_key)));
    return converted;
}

fn sub_14504ef00(a1: i32, a2: i64) i64 {
    var v2: i32 = undefined; // er8
    var v3: i64 = undefined; // r11
    var v4: i32 = undefined; // er10
    var i: u32 = undefined; // er9
    var v6: i64 = undefined; // rax
    var v7: i64 = undefined; // rdx
    var v8: i32 = undefined; // er8

    v2 = 0;
    v3 = a2;
    v4 = a1 & 0xFFFFFFF;
    i = 0;
    while (i < 0x1C) {
        v6 = v3;
        v7 = cc(i64, i +% 4);
        v7 = v7 & 0xFF;
        v7 = cc(i64, cc(u8, v7));
        while (true) {
            v6 = (if (v6 < 0) cc(i64, 1) else cc(i64, 0)) +% (v6 *% 2);
            v7 -= 1;
            if (v7 == 0) {
                break;
            }
        }
        v2 = cc(i32, cc(i64, v2) ^ (cc(i64, v4) ^ v6));
        v4 >>= 4;

        i +%= 4;
    }
    v8 = v2 & 0xF;
    if (v8 == 0) {
        v8 = 1;
    }

    return cc(i64, (a1 & 0xFFFFFFF) + (v8 << 28));
}

fn sub_14504f430_decrypt(encrypted_value: i32, encryption_key: i64) i64 {
    var v2: i64 = undefined; // rbx
    var v3: i32 = undefined; // edi
    var v4: i32 = undefined; // edi
    var v5: i64 = undefined; // rcx

    v2 = encryption_key;
    v3 = encrypted_value;
    if (cc(u32, sub_14504ef00(encrypted_value, encryption_key)) != cc(u32, encrypted_value)) {
        return 0;
    }
    v4 = v3 ^ 0x1D;
    if (v4 & 0x1F != 0) {
        v5 = cc(i64, (v4 & 0x1F));
        while (true) {
            v2 = (if (v2 < 0) cc(i64, 1) else cc(i64, 0)) +% (v2 *% 2);
            v5 -%= 1;
            if (v5 == 0) {
                break;
            }
        }
    }
    return cc(i64, cc(u32, @divFloor(cc(i32, 16 *% (cc(i64, v4) ^ v2 & 0xFFFFFFE0)), 16)));
}

fn sub_1451dd670_encrypt(decrypted_value: i32, encryption_key: i64) i64 {
    var v2: i64 = undefined; // rbx
    var v3: i64 = undefined; // r10
    var v4: i64 = undefined; // r8
    var v5: i32 = undefined; // er8
    var v6: i32 = undefined; // er10
    var v7: i32 = undefined; // er11
    var i: u32 = undefined; // er9
    var v9: i64 = undefined; // rax
    var v10: i64 = undefined; // rdx
    var v11: i32 = undefined; // er8

    v2 = encryption_key;
    v3 = encryption_key;
    if (decrypted_value & 0x1F != 0) {
        v4 = cc(i64, decrypted_value & 0x1F);
        while (true) {
            v3 = (if (v3 < 0) cc(i64, 1) else cc(i64, 0)) +% (v3 *% 2);
            v4 -%= 1;
            if (v4 == 0) {
                break;
            }
        }
    }
    v5 = 0;
    v6 = cc(i32, (cc(i64, decrypted_value) ^ v3 & 0xFFFFFFE0 ^ 0x1D) & 0xFFFFFFF);
    v7 = v6;

    i = 0;
    while (i < 0x1C) {
        v9 = v2;
        v10 = cc(i64, cc(u8, i +% 4));
        while (true) {
            v9 = (if (v9 < 0) cc(i64, 1) else cc(i64, 0)) +% (v9 *% 2);
            v10 -%= 1;
            if (v10 == 0) {
                break;
            }
        }
        v5 = cc(i32, (cc(i64, v5) ^ (cc(i64, v7) ^ v9)));
        v7 >>= 4;

        i += 4;
    }
    v11 = v5 & 0xF;
    if (v11 == 0) {
        v11 = 1;
    }

    return cc(i64, v6 +% (v11 << 28));
}

pub fn rawToConvertedCamera(value: t7.CameraData) t7.CameraData {
    return .{
        .position = value.position,
        .pitch = std.math.degreesToRadians(value.pitch),
        .yaw = std.math.degreesToRadians(value.yaw),
        .roll = std.math.degreesToRadians(value.roll),
    };
}

pub fn convertedToRawCamera(value: t7.CameraData) t7.CameraData {
    return .{
        .position = value.position,
        .pitch = std.math.radiansToDegrees(value.pitch),
        .yaw = std.math.radiansToDegrees(value.yaw),
        .roll = std.math.radiansToDegrees(value.roll),
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

test "hitLinePointToUnrealSpace and hitLinePointFromUnrealSpace should cancel out" {
    const value = t7.HitLinePoint{
        .position = .fromArray(.{ 1, 2, 3 }),
        ._padding = undefined,
    };
    try testing.expectEqual(value, hitLinePointToUnrealSpace(hitLinePointFromUnrealSpace(value)));
    try testing.expectEqual(value, hitLinePointFromUnrealSpace(hitLinePointToUnrealSpace(value)));
}

test "hurtCylinderToUnrealSpace and hurtCylinderFromUnrealSpace should cancel out" {
    const value = t7.HurtCylinder{
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
    const value = t7.CollisionSphere{
        .center = .fromArray(.{ 1, 2, 3 }),
        .multiplier = 4,
        .radius = 5,
        ._padding = undefined,
    };
    try testing.expectEqual(value, collisionSphereToUnrealSpace(collisionSphereFromUnrealSpace(value)));
    try testing.expectEqual(value, collisionSphereFromUnrealSpace(collisionSphereToUnrealSpace(value)));
}

test "encryptHealth and decryptHealth should return correct value" {
    const clear_text = t7.HealthWithEncryptionKey{
        .health = 175,
        .encryption_key = 0xBD20A1539B61342F,
    };
    const encrypted = t7.HealthWithEncryptionKey{
        .health = 0xABCE343D,
        .encryption_key = 0xBD20A1539B61342F,
    };
    try testing.expectEqual(encrypted, encryptHealth(clear_text));
    try testing.expectEqual(clear_text, decryptHealth(encrypted));
}

test "rawToConvertedCamera and convertedToRawCamera should cancel out" {
    const converted = t7.CameraData{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 0.25 * std.math.pi,
        .roll = 0.5 * std.math.pi,
        .yaw = 0.75 * std.math.pi,
    };
    try testing.expectEqual(converted, rawToConvertedCamera(convertedToRawCamera(converted)));
    const raw = t7.CameraData{
        .position = .fromArray(.{ 1, 2, 3 }),
        .pitch = 45,
        .roll = 90,
        .yaw = 135,
    };
    try testing.expectEqual(raw, convertedToRawCamera(rawToConvertedCamera(raw)));
}
