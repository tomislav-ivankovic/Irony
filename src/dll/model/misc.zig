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

pub const MovePhase = enum {
    neutral,
    start_up,
    active,
    active_recovery,
    recovery,
};

pub const AttackType = enum {
    not_attack,
    high,
    mid,
    low,
    special_low,
    unblockable_high,
    unblockable_mid,
    unblockable_low,
    throw,
    projectile,
    antiair_only,
};

pub const HitOutcome = enum {
    none,
    blocked_standing,
    blocked_crouching,
    juggle,
    screw,
    grounded_face_down,
    grounded_face_up,
    counter_hit_standing,
    counter_hit_crouching,
    normal_hit_standing,
    normal_hit_crouching,
    normal_hit_standing_left,
    normal_hit_crouching_left,
    normal_hit_standing_back,
    normal_hit_crouching_back,
    normal_hit_standing_right,
    normal_hit_crouching_right,
};

pub const Posture = enum {
    standing,
    crouching,
    downed_face_up,
    downed_face_down,
    airborne,
};

pub const Blocking = enum {
    not_blocking,
    neutral_blocking_mids,
    fully_blocking_mids,
    neutral_blocking_lows,
    fully_blocking_lows,
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

pub const Heat = union(enum) {
    available: void,
    activated: ActivatedHeat,
    used_up: void,
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
