const std = @import("std");
const build_info = @import("build_info");
const sdk = @import("../../sdk/root.zig");
const game = @import("root.zig");

pub const PlayerSide = enum(u8) {
    left = 0,
    right = 1,
    _,
};

pub const StateFlags = packed struct(u32) {
    crouching: bool = false,
    standing_or_airborne: bool = false,
    being_juggled_or_downed: bool = false,
    blocking_lows: bool = false,
    blocking_mids: bool = false,
    wants_to_crouch: bool = false,
    standing_or_airborne_and_not_juggled: bool = false,
    downed: bool = false,
    neutral_blocking: bool = false,
    face_down: bool = false,
    being_juggled: bool = false,
    not_blocking_or_neutral_blocking: bool = false,
    blocking: bool = false,
    crouching_or_downed_or_being_juggled: bool = false,
    airborne_move_or_downed: bool = false,
    airborne_move_and_not_juggled: bool = false,
    forward_move_modifier: bool = false,
    backward_move_modifier: bool = false,
    _18: bool = false,
    crouched_but_not_fully: bool = false,
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
        std.debug.assert((Self{ .crouching = true }).toInt() == 1);
        std.debug.assert((Self{ .standing_or_airborne = true }).toInt() == 2);
        std.debug.assert((Self{ .being_juggled_or_downed = true }).toInt() == 4);
        std.debug.assert((Self{ .blocking_lows = true }).toInt() == 8);
        std.debug.assert((Self{ .blocking_mids = true }).toInt() == 16);
        std.debug.assert((Self{ .wants_to_crouch = true }).toInt() == 32);
        std.debug.assert((Self{ .standing_or_airborne_and_not_juggled = true }).toInt() == 64);
        std.debug.assert((Self{ .downed = true }).toInt() == 128);
        std.debug.assert((Self{ .neutral_blocking = true }).toInt() == 256);
        std.debug.assert((Self{ .face_down = true }).toInt() == 512);
        std.debug.assert((Self{ .being_juggled = true }).toInt() == 1024);
        std.debug.assert((Self{ .not_blocking_or_neutral_blocking = true }).toInt() == 2048);
        std.debug.assert((Self{ .blocking = true }).toInt() == 4096);
        std.debug.assert((Self{ .crouching_or_downed_or_being_juggled = true }).toInt() == 8192);
        std.debug.assert((Self{ .airborne_move_or_downed = true }).toInt() == 16384);
        std.debug.assert((Self{ .airborne_move_and_not_juggled = true }).toInt() == 32768);
    }
};

pub const AirborneFlags = packed struct(u32) {
    _0: bool = false,
    _1: bool = false,
    _2: bool = false,
    _3: bool = false,
    _4: bool = false,
    _5: bool = false,
    _6: bool = false,
    _7: bool = false,
    _8: bool = false,
    low_crushing_end: bool = false,
    _10: bool = false,
    _11: bool = false,
    _12: bool = false,
    _13: bool = false,
    _14: bool = false,
    _15: bool = false,
    _16: bool = false,
    _17: bool = false,
    _18: bool = false,
    _19: bool = false,
    _20: bool = false,
    probably_airborne: bool = false,
    low_crushing_start: bool = false,
    airborne_end: bool = false,
    _24: bool = false,
    _25: bool = false,
    _26: bool = false,
    _27: bool = false,
    _28: bool = false,
    _29: bool = false,
    not_airborne_and_not_downed: bool = false,
    _31: bool = false,

    const Self = @This();

    pub fn fromInt(int: u32) Self {
        return @bitCast(int);
    }

    pub fn toInt(self: Self) u32 {
        return @bitCast(self);
    }

    comptime {
        std.debug.assert((Self{ .low_crushing_end = true }).toInt() == 512);
        std.debug.assert((Self{ .probably_airborne = true }).toInt() == 2097152);
        std.debug.assert((Self{ .low_crushing_start = true }).toInt() == 4194304);
        std.debug.assert((Self{ .airborne_end = true }).toInt() == 8388608);
        std.debug.assert((Self{ .not_airborne_and_not_downed = true }).toInt() == 1073741824);
    }
};

pub const PhaseFlags = packed struct(u32) {
    _0: bool = false,
    _1: bool = false,
    _2: bool = false,
    _3: bool = false,
    _4: bool = false,
    _5: bool = false,
    _6: bool = false,
    _7: bool = false,
    is_active: bool = false,
    _9: bool = false,
    is_recovery: bool = false,
    _11: bool = false,
    _12: bool = false,
    _13: bool = false,
    _14: bool = false,
    _15: bool = false,
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
        std.debug.assert((Self{ .is_active = true }).toInt() == 256);
        std.debug.assert((Self{ .is_recovery = true }).toInt() == 1024);
    }
};

pub const AttackType = enum(u32) {
    not_attack = 0xC000001D,
    high = 0xA000050F,
    mid = 0x8000020A,
    low = 0x20000112,
    special_low = 0x60000402,
    unblockable_high = 0x2000081B,
    unblockable_mid = 0xC000071A,
    unblockable_low = 0x2000091A,
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

pub fn Input(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => packed struct(u32) {
            up: bool = false,
            down: bool = false,
            left: bool = false,
            right: bool = false,
            _4: bool = false,
            _5: bool = false,
            _6: bool = false,
            _7: bool = false,
            special_style: bool = false,
            rage: bool = false,
            _10: bool = false,
            _11: bool = false,
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
                std.debug.assert((Self{ .rage = true }).toInt() == 512);
                std.debug.assert((Self{ .button_3 = true }).toInt() == 4096);
                std.debug.assert((Self{ .button_4 = true }).toInt() == 8192);
                std.debug.assert((Self{ .button_1 = true }).toInt() == 16384);
                std.debug.assert((Self{ .button_2 = true }).toInt() == 32768);
            }
        },
        .t8 => packed struct(u32) {
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
        },
    };
}

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
    ignore: sdk.memory.Boolean(.{}),
    _padding_2: [7]u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 64);
    }
};

pub fn HitLines(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => [6]sdk.memory.ConvertedValue(
            HitLinePoint,
            HitLinePoint,
            game.hitLinePointToUnrealSpace,
            game.hitLinePointFromUnrealSpace,
        ),
        .t8 => [4]sdk.memory.ConvertedValue(
            HitLine,
            HitLine,
            game.hitLineToUnrealSpace,
            game.hitLineFromUnrealSpace,
        ),
    };
}
comptime {
    std.debug.assert(@sizeOf(HitLines(.t7)) == 96);
    std.debug.assert(@sizeOf(HitLines(.t8)) == 256);
}

pub fn HurtCylinder(comptime game_id: build_info.Game) type {
    return extern struct {
        center: sdk.math.Vec3,
        multiplier: f32,
        half_height: f32,
        squared_radius: f32,
        radius: f32,
        _padding: [
            switch (game_id) {
                .t7 => 1,
                .t8 => 9,
            }
        ]f32,

        comptime {
            switch (game_id) {
                .t7 => std.debug.assert(@sizeOf(@This()) == 32),
                .t8 => std.debug.assert(@sizeOf(@This()) == 64),
            }
        }
    };
}

pub fn HurtCylinders(comptime game_id: build_info.Game) type {
    return extern struct {
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
            HurtCylinder(game_id),
            HurtCylinder(game_id),
            game.hurtCylinderToUnrealSpace(game_id),
            game.hurtCylinderFromUnrealSpace(game_id),
        );

        pub const len = @typeInfo(Self).@"struct".fields.len;

        pub fn asConstArray(self: *const Self) *const [len]Element {
            return @ptrCast(self);
        }

        pub fn asMutableArray(self: *Self) *[len]Element {
            return @ptrCast(self);
        }

        comptime {
            switch (game_id) {
                .t7 => std.debug.assert(@sizeOf(Self) == 448),
                .t8 => std.debug.assert(@sizeOf(Self) == 896),
            }
        }
    };
}

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

pub fn Health(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => extern struct {
            value: u32,
            encryption_key: u64,
        },
        .t8 => [16]u64,
    };
}

pub fn Player(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => struct {
            is_picked_by_main_player: sdk.memory.Boolean(.{}),
            character_id: u32,
            transform_matrix: sdk.memory.ConvertedValue(
                sdk.math.Mat4,
                sdk.math.Mat4,
                game.matrixToUnrealSpace,
                game.matrixFromUnrealSpace,
            ),
            floor_z: sdk.memory.ConvertedValue(
                f32,
                f32,
                game.scaleToUnrealSpace,
                game.scaleFromUnrealSpace,
            ),
            rotation: sdk.memory.ConvertedValue(
                u16,
                f32,
                game.u16ToRadians,
                game.u16FromRadians,
            ),
            animation_frame: u32,
            state_flags: StateFlags,
            attack_damage: i32,
            attack_type: AttackType,
            animation_id: u32,
            can_move: sdk.memory.Boolean(.{}),
            animation_total_frames: u32,
            hit_outcome: HitOutcome,
            invincible: sdk.memory.Boolean(.{}),
            power_crushing: sdk.memory.Boolean(.{}),
            airborne_flags: AirborneFlags,
            frames_since_round_start: u32,
            in_rage: sdk.memory.Boolean(.{}),
            phase_flags: PhaseFlags,
            input_side: PlayerSide,
            input: Input(.t7),
            hit_lines: HitLines(.t7),
            hurt_cylinders: HurtCylinders(.t7),
            collision_spheres: CollisionSpheres,
            health: sdk.memory.ConvertedValue(
                Health(.t7),
                Health(.t7),
                game.decryptT7Health,
                game.encryptT7Health,
            ),
        },
        .t8 => struct {
            is_picked_by_main_player: sdk.memory.Boolean(.{}),
            character_id: u32,
            transform_matrix: sdk.memory.ConvertedValue(
                sdk.math.Mat4,
                sdk.math.Mat4,
                game.matrixToUnrealSpace,
                game.matrixFromUnrealSpace,
            ),
            floor_z: sdk.memory.ConvertedValue(
                f32,
                f32,
                game.scaleToUnrealSpace,
                game.scaleFromUnrealSpace,
            ),
            rotation: sdk.memory.ConvertedValue(
                u16,
                f32,
                game.u16ToRadians,
                game.u16FromRadians,
            ),
            animation_frame: u32,
            state_flags: StateFlags,
            attack_damage: i32,
            attack_type: AttackType,
            animation_id: u32,
            can_move: sdk.memory.Boolean(.{}),
            animation_total_frames: u32,
            hit_outcome: HitOutcome,
            invincible: sdk.memory.Boolean(.{}),
            is_a_parry_move: sdk.memory.Boolean(.{ .true_value = 2 }),
            power_crushing: sdk.memory.Boolean(.{}),
            airborne_flags: AirborneFlags,
            in_rage: sdk.memory.Boolean(.{}),
            used_rage: sdk.memory.Boolean(.{}),
            frames_since_round_start: u32,
            phase_flags: PhaseFlags,
            heat_gauge: sdk.memory.ConvertedValue(
                u32,
                f32,
                game.decryptHeatGauge,
                game.encryptHeatGauge,
            ),
            used_heat: sdk.memory.Boolean(.{}),
            in_heat: sdk.memory.Boolean(.{}),
            input_side: PlayerSide,
            input: Input(.t8),
            hit_lines: HitLines(.t8),
            hurt_cylinders: HurtCylinders(.t8),
            collision_spheres: CollisionSpheres,
            health: sdk.memory.ConvertedValue(
                Health(.t8),
                ?i32,
                game.decryptT8Health,
                null,
            ),
        },
    };
}

pub fn RawCamera(comptime game_id: build_info.Game) type {
    const Float = switch (game_id) {
        .t7 => f32,
        .t8 => f64,
    };
    return extern struct {
        position: sdk.math.Vector(3, Float),
        pitch: Float,
        yaw: Float,
        roll: Float,
    };
}

pub const ConvertedCamera = extern struct {
    position: sdk.math.Vec3,
    pitch: f32,
    yaw: f32,
    roll: f32,
};

pub fn Camera(comptime game_id: build_info.Game) type {
    return sdk.memory.ConvertedValue(
        RawCamera(game_id),
        ConvertedCamera,
        game.rawToConvertedCamera(game_id),
        game.convertedToRawCamera(game_id),
    );
}

pub fn TickFunction(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => fn (game_mode_address: usize, delta_time: f32) callconv(.c) void,
        .t8 => fn (delta_time: f64) callconv(.c) void,
    };
}

pub const UpdateCameraFunction = fn (camera_manager_address: usize, delta_time: f32) callconv(.c) void;

pub const DecryptT8HealthFunction = fn (encrypted_health: *const Health(.t8)) callconv(.c) i64;
