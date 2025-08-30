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

pub const AttackPhase = enum {
    not_attack,
    start_up,
    active,
    recovery,
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
