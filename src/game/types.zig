const std = @import("std");
const memory = @import("../memory/root.zig");
const math = @import("../math/root.zig");
const game = @import("root.zig");

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

pub const Stun = packed struct(u32) {
    _0: bool = false,
    _1: bool = false,
    _2: bool = false,
    _3: bool = false,
    _4: bool = false,
    _5: bool = false,
    _6: bool = false,
    _7: bool = false,
    _8: bool = false,
    _9: bool = false,
    _10: bool = false,
    _11: bool = false,
    _12: bool = false,
    _13: bool = false,
    _14: bool = false,
    _15: bool = false,
    any_stun: bool = false,
    _17: bool = false,
    _18: bool = false,
    _19: bool = false,
    _20: bool = false,
    _21: bool = false,
    _22: bool = false,
    _23: bool = false,
    attacking: bool = false,
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
        std.debug.assert((Self{ .any_stun = true }).toInt() == 65536);
        std.debug.assert((Self{ .attacking = true }).toInt() == 16777216);
    }
};

pub const CancelFlags = packed struct(u32) {
    _0: bool = false,
    _1: bool = false,
    _2: bool = false,
    _3: bool = false,
    _4: bool = false,
    _5: bool = false,
    _6: bool = false,
    _7: bool = false,
    _8: bool = false,
    _9: bool = false,
    _10: bool = false,
    _11: bool = false,
    _12: bool = false,
    _13: bool = false,
    _14: bool = false,
    _15: bool = false,
    cancellable: bool = false,
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
        std.debug.assert((Self{ .cancellable = true }).toInt() == 65536);
    }
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

pub const HitLineSet = extern struct {
    points: [3]HitLinePoint,
    _padding: [4]f32,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 64);
    }
};

pub const HitLines = [4]HitLineSet;
comptime {
    std.debug.assert(@sizeOf(HitLines) == 256);
}

pub const HurtCylinder = extern struct {
    position: math.Vec3,
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
    left_ankle: HurtCylinder,
    right_ankle: HurtCylinder,
    left_hand: HurtCylinder,
    right_hand: HurtCylinder,
    left_knee: HurtCylinder,
    right_knee: HurtCylinder,
    left_elbow: HurtCylinder,
    right_elbow: HurtCylinder,
    head: HurtCylinder,
    left_shoulder: HurtCylinder,
    right_shoulder: HurtCylinder,
    upper_torso: HurtCylinder,
    left_pelvis: HurtCylinder,
    right_pelvis: HurtCylinder,

    const Self = @This();

    pub const len = @typeInfo(Self).@"struct".fields.len;

    pub fn asConstArray(self: *const Self) *const [len]HurtCylinder {
        return @ptrCast(self);
    }

    pub fn asMutableArray(self: *Self) *[len]HurtCylinder {
        return @ptrCast(self);
    }

    comptime {
        std.debug.assert(@sizeOf(Self) == 896);
    }
};

pub const CollisionSphere = extern struct {
    position: math.Vec3,
    multiplier: f32,
    radius: f32,
    _padding: [3]f32,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 32);
    }
};

pub const CollisionSpheres = extern struct {
    neck: CollisionSphere,
    left_elbow: CollisionSphere,
    right_elbow: CollisionSphere,
    lower_torso: CollisionSphere,
    left_knee: CollisionSphere,
    right_knee: CollisionSphere,
    left_ankle: CollisionSphere,
    right_ankle: CollisionSphere,

    const Self = @This();

    pub const len = @typeInfo(Self).@"struct".fields.len;

    pub fn asConstArray(self: *const Self) *const [len]CollisionSphere {
        return @ptrCast(self);
    }

    pub fn asMutableArray(self: *Self) *[len]CollisionSphere {
        return @ptrCast(self);
    }

    comptime {
        std.debug.assert(@sizeOf(Self) == 256);
    }
};

pub const Player = struct {
    player_id: i32, // 0x0004
    is_picked_by_main_player: bool, // 0x0009
    character_id: i32, // 0x0168
    position_x_base: f32, // 0x0170
    position_y_base: f32, // 0x0178
    position_y_relative_to_floor: f32, // 0x0184
    position_x_relative_to_floor: f32, // 0x018C
    position_z_relative_to_floor: f32, // 0x01A4
    location: memory.ConvertedValue(
        math.Vec3,
        math.Vec3,
        game.conversions.pointToUnrealSpace,
        game.conversions.pointFromUnrealSpace,
    ), //0x0230
    current_frame_number: u32, // 0x0390
    current_frame_float: f32, // 0x03BC
    current_move_pointer: usize, // 0x03D8
    current_move_pointer_2: usize, // 0x03E0
    previous_move_pointer: usize, // 0x03E8
    attack_damage: i32, // 0x0504
    attack_type: AttackType, // 0x0510
    current_move_id: u32, // 0x0548
    can_move: u32, // 0x05C8
    current_move_total_frames: u32, // 0x05D4
    hit_outcome: f32, // 0x0610
    already_attacked: u32, // 0x066C
    already_attacked_2: u32, // 0x0674
    stun: Stun, // 0x0774
    cancel_flags: CancelFlags, // 0x0C80
    rage: bool, // 0x0D71
    floor_number_1: i32, // 0x1770
    floor_number_2: i32, // 0x1774
    floor_number_3: i32, // 0x1778
    frame_data_flags: u32, // 0x19E0
    next_move_pointer: usize, // 0x1F30
    next_move_id: u32, // 0x1F4C
    reaction_to_have: u32, // 0x1F50
    attack_input: u32, // 0x1F70
    direction_input: u32, // 0x1F74
    used_heat: u32, // 0x2110
    input: Input, // 0x2494
    hit_lines: memory.ConvertedValue(
        HitLines,
        HitLines,
        game.conversions.hitLinesToUnrealSpace,
        game.conversions.hitLinesFromUnrealSpace,
    ), // 0x2500
    hurt_cylinders: memory.ConvertedValue(
        HurtCylinders,
        HurtCylinders,
        game.conversions.hurtCylindersToUnrealSpace,
        game.conversions.hurtCylindersFromUnrealSpace,
    ), // 0x2900
    collision_spheres: memory.ConvertedValue(
        CollisionSpheres,
        CollisionSpheres,
        game.conversions.collisionSpheresToUnrealSpace,
        game.conversions.collisionSpheresFromUnrealSpace,
    ), // 0x2D40
    health: i32, // 0x2EE4
};

pub const TickFunction = fn (delta_time: f64) callconv(.c) void;
