const std = @import("std");

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
};

pub const Stun = packed struct(u32) {
    _0: u1 = 0,
    _1: u1 = 0,
    _2: u1 = 0,
    _3: u1 = 0,
    _4: u1 = 0,
    _5: u1 = 0,
    _6: u1 = 0,
    _7: u1 = 0,
    _8: u1 = 0,
    _9: u1 = 0,
    _10: u1 = 0,
    _11: u1 = 0,
    _12: u1 = 0,
    _13: u1 = 0,
    _14: u1 = 0,
    _15: u1 = 0,
    any_stun: u1 = 0,
    _17: u1 = 0,
    _18: u1 = 0,
    _19: u1 = 0,
    _20: u1 = 0,
    _21: u1 = 0,
    _22: u1 = 0,
    _23: u1 = 0,
    attacking: u1 = 0,
    _25: u1 = 0,
    _26: u1 = 0,
    _27: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    _31: u1 = 0,
};

pub const CancelFlags = packed struct(u32) {
    _0: u1 = 0,
    _1: u1 = 0,
    _2: u1 = 0,
    _3: u1 = 0,
    _4: u1 = 0,
    _5: u1 = 0,
    _6: u1 = 0,
    _7: u1 = 0,
    _8: u1 = 0,
    _9: u1 = 0,
    _10: u1 = 0,
    _11: u1 = 0,
    _12: u1 = 0,
    _13: u1 = 0,
    _14: u1 = 0,
    _15: u1 = 0,
    cancellable: u1 = 0,
    _17: u1 = 0,
    _18: u1 = 0,
    _19: u1 = 0,
    _20: u1 = 0,
    _21: u1 = 0,
    _22: u1 = 0,
    _23: u1 = 0,
    _24: u1 = 0,
    _25: u1 = 0,
    _26: u1 = 0,
    _27: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    _31: u1 = 0,
};

pub const Player = extern struct {
    _0000: [4]u8, //0x0000
    player_id: i32, //0x0004
    _0008: [1]u8, //0x0008
    is_picked_by_main_player: bool, //0x0009
    _000A: [350]u8, //0x000A
    character_id: i32, //0x0168
    character_id_2: i32, //0x016C
    position_x: f32, //0x0170
    _0174: [4]u8, //0x0174
    position_y: f32, //0x0178
    _017C: [8]u8, //0x017C
    position_y_relative_to_floor: f32, //0x0184
    _0188: [4]u8, //0x0188
    position_x_relative_to_floor: f32, //0x018C
    _0190: [20]u8, //0x0190
    position_z_relative_to_floor: f32, //0x01A4
    _01A8: [104]u8, //0x01A8
    location: [4]f32, //0x0210
    _0220: [288]u8, //0x0220
    b7: f32, //0x0340
    _0344: [44]u8, //0x0344
    current_frame_int: i32, //0x0370
    _0374: [40]u8, //0x0374
    current_frame_float: f32, //0x039C
    _03A0: [24]u8, //0x03A0
    current_move_pointer: u64, //0x03B8
    current_move_pointer_2: u64, //0x03C0
    previous_move_pointer: u64, //0x03C8
    _03D0: [276]u8, //0x03D0
    attack_damage: i32, //0x04E4
    _04E8: [8]u8, //0x04E8
    attack_type: AttackType, //0x04F0
    _04F4: [40]u8, //0x04F4
    current_move_id: i32, //0x051C
    _0520: [124]u8, //0x0520
    _move: i32, //0x059C
    _05A0: [68]u8, //0x05A0
    hit_outcome: HitOutcome, //0x05E4
    _05E8: [92]u8, //0x05E8
    already_attacked: i32, //0x0644
    _0648: [260]u8, //0x0648
    stun: Stun,
    _0750: [1288]u8, //0x0750
    cancel_flags: CancelFlags, //0x0C58
    _0C5C: [2548]u8, //0x0C5C
    floor_number_1: i32, //0x1650
    _1654: [620]u8, //0x1654
    frame_data_flags: i32, //0x18C0
    _18C4: [1356]u8, //0x18C4
    next_move_pointer: u64, //0x1E10
    _1E18: [20]u8, //0x1E18
    next_move_id: i32, //0x1E2C
    reaction_to_have: i32, //0x1E30
    _1E34: [28]u8, //0x1E34
    attack_input: i32, //0x1E50
    direction_input: i32, //0x1E54
    _1E58: [3948]u8, //0x1E58
    health: i32, //0x2DC4
    _2DC8: [936]u8, //0x2DC8
};
comptime {
    std.debug.assert(@sizeOf(Player) == 0x3170);
}
