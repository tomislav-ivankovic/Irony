const std = @import("std");
const build_info = @import("build_info");
const sdk = @import("../../sdk/root.zig");
const game = @import("root.zig");
const cc = std.zig.c_translation.cast;

const to_unreal_scale = 0.1;
const from_unreal_scale = 1.0 / to_unreal_scale;

pub const conversion_globals = struct {
    pub var decryptT8Health: ?*const game.DecryptT8HealthFunction = null;
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
    var converted = value;
    for (value.points, 0..) |element, index| {
        converted.points[index] = hitLinePointToUnrealSpace(element);
    }
    return converted;
}

pub fn hitLineFromUnrealSpace(value: game.HitLine) game.HitLine {
    var converted = value;
    for (value.points, 0..) |element, index| {
        converted.points[index] = hitLinePointFromUnrealSpace(element);
    }
    return converted;
}

pub fn hurtCylinderToUnrealSpace(
    comptime game_id: build_info.Game,
) *const fn (value: game.HurtCylinder(game_id)) game.HurtCylinder(game_id) {
    return struct {
        fn hurtCylinderToUnrealSpace(value: game.HurtCylinder(game_id)) game.HurtCylinder(game_id) {
            var converted = value;
            converted.center = pointToUnrealSpace(value.center);
            converted.half_height = scaleToUnrealSpace(value.half_height);
            converted.squared_radius = scaleToUnrealSpace(scaleToUnrealSpace(value.squared_radius));
            converted.radius = scaleToUnrealSpace(value.radius);
            return converted;
        }
    }.hurtCylinderToUnrealSpace;
}

pub fn hurtCylinderFromUnrealSpace(
    comptime game_id: build_info.Game,
) *const fn (value: game.HurtCylinder(game_id)) game.HurtCylinder(game_id) {
    return struct {
        fn hurtCylinderFromUnrealSpace(value: game.HurtCylinder(game_id)) game.HurtCylinder(game_id) {
            var converted = value;
            converted.center = pointFromUnrealSpace(value.center);
            converted.half_height = scaleFromUnrealSpace(value.half_height);
            converted.squared_radius = scaleFromUnrealSpace(scaleFromUnrealSpace(value.squared_radius));
            converted.radius = scaleFromUnrealSpace(value.radius);
            return converted;
        }
    }.hurtCylinderFromUnrealSpace;
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

pub fn decryptT7Health(value: game.Health(.t7)) game.Health(.t7) {
    var converted = value;
    converted.value = cc(u32, sub_14504f430_decrypt(cc(i32, converted.value), cc(i64, converted.encryption_key)));
    converted.value = converted.value >> 16;
    return converted;
}

pub fn encryptT7Health(value: game.Health(.t7)) game.Health(.t7) {
    var converted = value;
    converted.value = converted.value << 16;
    converted.value = cc(u32, sub_1451dd670_encrypt(cc(i32, converted.value), cc(i64, converted.encryption_key)));
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

pub fn decryptT8Health(value: game.Health(.t8)) ?i32 {
    if (value[0] != 0 and value[0] != 1) {
        return null; // Decrypting invalid encrypted health value can cause a crash. This prevents it.
    }
    const decrypt = conversion_globals.decryptT8Health orelse return null;
    const shifted = decrypt(&value);
    return @intCast(shifted >> 16);
}

pub fn rawToConvertedCamera(
    comptime game_id: build_info.Game,
) *const fn (value: game.RawCamera(game_id)) game.ConvertedCamera {
    return struct {
        fn rawToConvertedCamera(value: game.RawCamera(game_id)) game.ConvertedCamera {
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
    }.rawToConvertedCamera;
}

pub fn convertedToRawCamera(
    comptime game_id: build_info.Game,
) *const fn (value: game.ConvertedCamera) game.RawCamera(game_id) {
    return struct {
        fn convertedToRawCamera(value: game.ConvertedCamera) game.RawCamera(game_id) {
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
    }.convertedToRawCamera;
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
        .ignore = .true,
        ._padding_2 = undefined,
    };
    try testing.expectEqual(value, hitLineToUnrealSpace(hitLineFromUnrealSpace(value)));
    try testing.expectEqual(value, hitLineFromUnrealSpace(hitLineToUnrealSpace(value)));
}

test "hurtCylinderToUnrealSpace and hurtCylinderFromUnrealSpace should cancel out in T7" {
    const value = game.HurtCylinder(.t7){
        .center = .fromArray(.{ 1, 2, 3 }),
        .multiplier = 4,
        .half_height = 5,
        .squared_radius = 6,
        .radius = 7,
        ._padding = undefined,
    };
    try testing.expectEqual(value, hurtCylinderToUnrealSpace(.t7)(hurtCylinderFromUnrealSpace(.t7)(value)));
    try testing.expectEqual(value, hurtCylinderFromUnrealSpace(.t7)(hurtCylinderToUnrealSpace(.t7)(value)));
}

test "hurtCylinderToUnrealSpace and hurtCylinderFromUnrealSpace should cancel out in T8" {
    const value = game.HurtCylinder(.t8){
        .center = .fromArray(.{ 1, 2, 3 }),
        .multiplier = 4,
        .half_height = 5,
        .squared_radius = 6,
        .radius = 7,
        ._padding = undefined,
    };
    try testing.expectEqual(value, hurtCylinderToUnrealSpace(.t8)(hurtCylinderFromUnrealSpace(.t8)(value)));
    try testing.expectEqual(value, hurtCylinderFromUnrealSpace(.t8)(hurtCylinderToUnrealSpace(.t8)(value)));
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

test "encryptT7Health and decryptT7Health should return correct value" {
    const clear_text = game.Health(.t7){
        .value = 175,
        .encryption_key = 0xBD20A1539B61342F,
    };
    const encrypted = game.Health(.t7){
        .value = 0xABCE343D,
        .encryption_key = 0xBD20A1539B61342F,
    };
    try testing.expectEqual(encrypted, encryptT7Health(clear_text));
    try testing.expectEqual(clear_text, decryptT7Health(encrypted));
}
