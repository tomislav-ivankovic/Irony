const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const game = @import("root.zig");

pub const BooleanConfig = struct {
    BackingInt: type = u8,
    false_value: comptime_int = 0,
    true_value: comptime_int = 1,
};

pub fn Boolean(comptime config: BooleanConfig) type {
    return enum(config.BackingInt) {
        false = config.false_value,
        true = config.true_value,
        _,

        const Self = @This();

        pub fn fromBool(b: bool) Self {
            return switch (b) {
                false => .false,
                true => .true,
            };
        }

        pub fn toBool(self: Self) ?bool {
            return switch (self) {
                .false => false,
                .true => true,
                else => null,
            };
        }

        comptime {
            const false_v = config.false_value;
            const true_v = config.true_value;
            const third_v = if (false_v != 0 and true_v != 0) 0 else if (false_v != 1 and true_v != 1) 1 else 2;
            std.debug.assert(Self.fromBool(false) == .false);
            std.debug.assert(Self.fromBool(true) == .true);
            std.debug.assert(@as(Self, @enumFromInt(false_v)).toBool() == false);
            std.debug.assert(@as(Self, @enumFromInt(true_v)).toBool() == true);
            std.debug.assert(@as(Self, @enumFromInt(third_v)).toBool() == null);
        }
    };
}

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

    pub fn fromInt(int: u32) Self {
        return @bitCast(int);
    }

    pub fn toInt(self: Self) u32 {
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
    position: sdk.math.Vec3,
    _padding: f32,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 16);
    }
};

pub const HitLine = extern struct {
    points: [3]HitLinePoint,
    _padding_1: [8]u8,
    ignore: Boolean(.{}),
    _padding_2: [7]u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 64);
    }
};

pub const HitLines = [4]sdk.memory.ConvertedValue(
    HitLine,
    HitLine,
    game.hitLineToUnrealSpace,
    game.hitLineFromUnrealSpace,
);
comptime {
    std.debug.assert(@sizeOf(HitLines) == 256);
}

pub const HurtCylinder = extern struct {
    center: sdk.math.Vec3,
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
    pub const Element = sdk.memory.ConvertedValue(
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
    center: sdk.math.Vec3,
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
    pub const Element = sdk.memory.ConvertedValue(
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
    is_picked_by_main_player: Boolean(.{}), // 0x0009
    character_id: u32, // 0x0168
    transform_matrix: sdk.memory.ConvertedValue(
        sdk.math.Mat4,
        sdk.math.Mat4,
        game.matrixToUnrealSpace,
        game.matrixFromUnrealSpace,
    ), // 0x1F4
    floor_z: sdk.memory.ConvertedValue(
        f32,
        f32,
        game.scaleToUnrealSpace,
        game.scaleFromUnrealSpace,
    ), // 0x0354
    rotation: sdk.memory.ConvertedValue(
        u16,
        f32,
        game.u16ToRadians,
        game.u16FromRadians,
    ), // 0x376
    current_move_frame: u32, // 0x0390
    state_flags: StateFlags, //0x0434
    attack_damage: i32, // 0x0504
    attack_type: AttackType, // 0x0510
    current_move_id: u32, // 0x0548
    can_move: Boolean(.{}), // 0x05C8
    current_move_total_frames: u32, // 0x05D4
    hit_outcome: HitOutcome, // 0x0610
    is_a_parry_move: Boolean(.{ .true_value = 2 }), // 0xA2C
    power_crushing: Boolean(.{}), // 0x0A70
    airborne_flags: AirborneFlags, // 0x0D9C
    in_rage: Boolean(.{}), // 0x0DD1
    used_rage: Boolean(.{}), // 0x0E08
    frames_since_round_start: u32, // 0x1410
    used_heat: Boolean(.{}), // 0x21C0
    heat_gauge: sdk.memory.ConvertedValue(
        u32,
        f32,
        game.decryptHeatGauge,
        game.encryptHeatGauge,
    ), // 0x21B0
    in_heat: Boolean(.{}), // 0x21E1
    input_side: PlayerSide, // 0x252C
    input: Input, // 0x2554
    hit_lines: HitLines, // 0x2500
    hurt_cylinders: HurtCylinders, // 0x2900
    collision_spheres: CollisionSpheres, // 0x2D40
    health: sdk.memory.ConvertedValue(
        EncryptedHealth,
        ?i32,
        game.decryptHealth,
        null,
    ), // 0x3580
};

pub const TickFunction = fn (delta_time: f64) callconv(.c) void;

pub const DecryptHealthFunction = fn (encrypted_health: *const EncryptedHealth) callconv(.c) i64;

pub const StateFlags = packed struct(u16) {
    crouching: bool,
    standing_or_airborne: bool,
    being_juggled_or_downed: bool,
    blocking_lows: bool,
    blocking_mids: bool,
    wants_to_crouch: bool,
    not_high_crushing: bool,
    downed: bool,
    neutral_blocking: bool,
    face_down: bool,
    being_juggled: bool,
    not_blocking_or_neutral_blocking: bool,
    blocking: bool,
    high_crushing: bool,
    airborne_move_or_downed: bool,
    airborne_move_and_not_juggled: bool,
};

pub const AirborneFlags = packed struct(u32) {
    _0: bool,
    _1: bool,
    _2: bool,
    _3: bool,
    _4: bool,
    _5: bool,
    _6: bool,
    _7: bool,
    _8: bool,
    low_crushing_end: bool,
    _10: bool,
    _11: bool,
    _12: bool,
    _13: bool,
    _14: bool,
    _15: bool,
    _16: bool,
    _17: bool,
    _18: bool,
    _19: bool,
    _20: bool,
    probably_low_crushing: bool,
    low_crushing_start: bool,
    airborne_end: bool,
    _24: bool,
    _25: bool,
    _26: bool,
    _27: bool,
    _28: bool,
    _29: bool,
    not_airborne_and_not_downed: bool,
    _31: bool,
};
