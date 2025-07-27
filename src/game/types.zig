const std = @import("std");
const memory = @import("../memory/root.zig");
const math = @import("../math/root.zig");
const game = @import("root.zig");

pub const PlayerSide = enum(u8) {
    left = 0,
    right = 1,
    _,
};

pub const AttackType = enum(u32) {
    not_attack = 0xC000001D,
    high = 0xA000050F,
    mid = 0x8000020A,
    low = 0x20000112,
    special_mid = 0x60000402,
    high_unblockable = 0x2000081B,
    mid_unblockable = 0xC000071A,
    low_unblockable = 0x2000091A,
    throw = 0x60000A1D,
    projectile = 0x10000302,
    antiair_only = 0x10000B1A,
    _,
};

pub const HitOutcome = enum(u32) {
    none = 0,
    blocked_standing = 1,
    blocked_crouching = 2,
    juggle = 3,
    screw = 4,
    unknown_screw_5 = 5,
    unknown_6 = 6,
    unknown_screw_7 = 7,
    grounded_face_down = 8,
    grounded_face_up = 9,
    counter_hit_standing = 10,
    counter_hit_crouching = 11,
    normal_hit_standing = 12,
    normal_hit_crouching = 13,
    normal_hit_standing_left = 14,
    normal_hit_crouching_left = 15,
    normal_hit_standing_back = 16,
    normal_hit_crouching_back = 17,
    normal_hit_standing_right = 18,
    normal_hit_crouching_right = 19,
    _,
};

pub const Input = packed struct(u32) {
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,
    _4: bool = false,
    _5: bool = false,
    _6: bool = false,
    _7: bool = false,
    special_style: bool = false,
    heat: bool = false,
    _10: bool = false,
    rage: bool = false,
    button_3: bool = false,
    button_4: bool = false,
    button_1: bool = false,
    button_2: bool = false,
    _16: bool = false,
    _17: bool = false,
    _18: bool = false,
    _19: bool = false,
    _20: bool = false,
    _21: bool = false,
    _22: bool = false,
    _23: bool = false,
    _24: bool = false,
    _25: bool = false,
    _26: bool = false,
    _27: bool = false,
    _28: bool = false,
    _29: bool = false,
    _30: bool = false,
    _31: bool = false,

    const Self = @This();

    fn fromInt(int: u32) Self {
        return @bitCast(int);
    }

    fn toInt(self: Self) u32 {
        return @bitCast(self);
    }

    comptime {
        std.debug.assert((Self{ .up = true }).toInt() == 1);
        std.debug.assert((Self{ .down = true }).toInt() == 2);
        std.debug.assert((Self{ .left = true }).toInt() == 4);
        std.debug.assert((Self{ .right = true }).toInt() == 8);
        std.debug.assert((Self{ .special_style = true }).toInt() == 256);
        std.debug.assert((Self{ .heat = true }).toInt() == 512);
        std.debug.assert((Self{ .rage = true }).toInt() == 2048);
        std.debug.assert((Self{ .button_3 = true }).toInt() == 4096);
        std.debug.assert((Self{ .button_4 = true }).toInt() == 8192);
        std.debug.assert((Self{ .button_1 = true }).toInt() == 16384);
        std.debug.assert((Self{ .button_2 = true }).toInt() == 32768);
    }
};

pub const HitLinePoint = extern struct {
    position: math.Vec3,
    _padding: f32,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 16);
    }
};

pub const HitLine = extern struct {
    points: [3]HitLinePoint,
    _padding_1: [8]u8,
    ignore: bool,
    _padding_2: [7]u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 64);
    }
};

pub const HitLines = [4]memory.ConvertedValue(
    HitLine,
    HitLine,
    game.hitLineToUnrealSpace,
    game.hitLineFromUnrealSpace,
);
comptime {
    std.debug.assert(@sizeOf(HitLines) == 256);
}

pub const HurtCylinder = extern struct {
    center: math.Vec3,
    multiplier: f32,
    half_height: f32,
    squared_radius: f32,
    radius: f32,
    _padding: [9]f32,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 64);
    }
};

pub const HurtCylinders = extern struct {
    left_ankle: Element,
    right_ankle: Element,
    left_hand: Element,
    right_hand: Element,
    left_knee: Element,
    right_knee: Element,
    left_elbow: Element,
    right_elbow: Element,
    head: Element,
    left_shoulder: Element,
    right_shoulder: Element,
    upper_torso: Element,
    left_pelvis: Element,
    right_pelvis: Element,

    const Self = @This();
    pub const Element = memory.ConvertedValue(
        HurtCylinder,
        HurtCylinder,
        game.hurtCylinderToUnrealSpace,
        game.hurtCylinderFromUnrealSpace,
    );

    pub const len = @typeInfo(Self).@"struct".fields.len;

    pub fn asConstArray(self: *const Self) *const [len]Element {
        return @ptrCast(self);
    }

    pub fn asMutableArray(self: *Self) *[len]Element {
        return @ptrCast(self);
    }

    comptime {
        std.debug.assert(@sizeOf(Self) == 896);
    }
};

pub const CollisionSphere = extern struct {
    center: math.Vec3,
    multiplier: f32,
    radius: f32,
    _padding: [3]f32,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 32);
    }
};

pub const CollisionSpheres = extern struct {
    neck: Element,
    left_elbow: Element,
    right_elbow: Element,
    lower_torso: Element,
    left_knee: Element,
    right_knee: Element,
    left_ankle: Element,
    right_ankle: Element,

    const Self = @This();
    pub const Element = memory.ConvertedValue(
        CollisionSphere,
        CollisionSphere,
        game.collisionSphereToUnrealSpace,
        game.collisionSphereFromUnrealSpace,
    );

    pub const len = @typeInfo(Self).@"struct".fields.len;

    pub fn asConstArray(self: *const Self) *const [len]Element {
        return @ptrCast(self);
    }

    pub fn asMutableArray(self: *Self) *[len]Element {
        return @ptrCast(self);
    }

    comptime {
        std.debug.assert(@sizeOf(Self) == 256);
    }
};

pub const EncryptedHealth = [16]u64;

pub const Player = struct {
    is_picked_by_main_player: bool, // 0x0009
    character_id: u32, // 0x0168
    transform_matrix: memory.ConvertedValue(
        math.Mat4,
        math.Mat4,
        game.matrixToUnrealSpace,
        game.matrixFromUnrealSpace,
    ), // 0x1F4
    floor_z: memory.ConvertedValue(
        f32,
        f32,
        game.scaleToUnrealSpace,
        game.scaleFromUnrealSpace,
    ), // 0x0354
    rotation: memory.ConvertedValue(
        u16,
        f32,
        game.u16ToRadians,
        game.u16FromRadians,
    ), // 0x376
    current_move_frame: u32, // 0x0390
    attack_damage: i32, // 0x0504
    attack_type: AttackType, // 0x0510
    current_move_id: u32, // 0x0548
    can_move: u32, // 0x05C8
    current_move_total_frames: u32, // 0x05D4
    hit_outcome: HitOutcome, // 0x0610
    in_rage: bool, // 0x0DD1
    used_rage: bool, // 0x0E08
    frames_since_round_start: u32, // 0x1410
    used_heat: bool, // 0x21C0
    heat_gauge: memory.ConvertedValue(
        u32,
        f32,
        game.decryptHeatGauge,
        game.encryptHeatGauge,
    ), // 0x21B0
    in_heat: bool, // 0x21E1
    input_side: PlayerSide, // 0x252C
    input: Input, // 0x2554
    hit_lines: HitLines, // 0x2500
    hurt_cylinders: HurtCylinders, // 0x2900
    collision_spheres: CollisionSpheres, // 0x2D40
    health: memory.ConvertedValue(
        EncryptedHealth,
        ?i32,
        game.decryptHealth,
        null,
    ), // 0x3580
};

pub const TickFunction = fn (delta_time: f64) callconv(.c) void;

pub const DecryptHealthFunction = fn (encrypted_health: *const EncryptedHealth) callconv(.c) i64;
