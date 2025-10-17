const sdk = @import("../../sdk/root.zig");

pub const U32ActualMax = struct {
    actual: ?u32,
    max: ?u32,
};

pub const U32ActualMinMax = struct {
    actual: ?u32,
    min: ?u32,
    max: ?u32,
};

pub const I32ActualMinMax = struct {
    actual: ?i32,
    min: ?i32,
    max: ?i32,
};

pub const F32MinMax = struct {
    min: ?f32,
    max: ?f32,
};

pub const MovePhase = enum(u8) {
    neutral = 0,
    start_up = 1,
    active = 2,
    active_recovery = 3,
    recovery = 4,
};

pub const AttackType = enum(u8) {
    not_attack = 0,
    high = 1,
    mid = 2,
    low = 3,
    special_low = 4,
    unblockable_high = 5,
    unblockable_mid = 6,
    unblockable_low = 7,
    throw = 8,
    projectile = 9,
    antiair_only = 10,
};

pub const HitOutcome = enum(u8) {
    none = 0,
    blocked_standing = 1,
    blocked_crouching = 2,
    juggle = 3,
    screw = 4,
    grounded_face_down = 5,
    grounded_face_up = 6,
    counter_hit_standing = 7,
    counter_hit_crouching = 8,
    normal_hit_standing = 9,
    normal_hit_crouching = 10,
    normal_hit_standing_left = 11,
    normal_hit_crouching_left = 12,
    normal_hit_standing_back = 13,
    normal_hit_crouching_back = 14,
    normal_hit_standing_right = 15,
    normal_hit_crouching_right = 16,
};

pub const Posture = enum(u8) {
    standing = 0,
    crouching = 1,
    downed_face_up = 2,
    downed_face_down = 3,
    airborne = 4,
};

pub const Blocking = enum(u8) {
    not_blocking = 0,
    neutral_blocking_mids = 1,
    fully_blocking_mids = 2,
    neutral_blocking_lows = 3,
    fully_blocking_lows = 4,
};

pub const Crushing = packed struct {
    high_crushing: bool = false,
    low_crushing: bool = false,
    anti_air_only_crushing: bool = true,
    invincibility: bool = false,
    power_crushing: bool = false,
};

pub const Input = packed struct {
    forward: bool = false,
    back: bool = false,
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,
    special_style: bool = false,
    heat: bool = false,
    rage: bool = false,
    button_1: bool = false,
    button_2: bool = false,
    button_3: bool = false,
    button_4: bool = false,
};

pub const Rage = enum {
    available,
    activated,
    used_up,
};

pub const Heat = union(HeatTag) {
    available: void,
    activated: ActivatedHeat,
    used_up: void,
};

pub const HeatTag = enum(u8) {
    available = 0,
    activated = 1,
    used_up = 2,
};

pub const ActivatedHeat = struct {
    gauge: f32,
};

pub const Camera = struct {
    position: sdk.math.Vec3,
    pitch: f32,
    yaw: f32,
    roll: f32,
};
