const std = @import("std");
const build_info = @import("build_info");
const w32 = @import("win32").everything;
const sdk = @import("../../sdk/root.zig");
const game = @import("root.zig");

const Bool = sdk.memory.Boolean(.{});
const Pointer = sdk.memory.Pointer;
const Converted = sdk.memory.ConvertedValue;

fn field(
    comptime offset: ?usize,
    comptime name: [:0]const u8,
    comptime Type: type,
    comptime default_value_ptr: ?*const Type,
) sdk.memory.StructWithOffsetsMember {
    return .{
        .offset = offset,
        .name = name,
        .type = Type,
        .default_value_ptr = @ptrCast(default_value_ptr),
    };
}

pub fn Version(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => [5]u8,
        .t8 => [64]u8,
    };
}

pub const PlayerSide = enum(u8) {
    left = 0,
    right = 1,
    _,
};

// MovesetExtractor: VUNL
pub const StateFlags = sdk.memory.Bitfield(u32, &.{
    .{ .name = "crouching", .backing_value = 1 },
    .{ .name = "standing_or_airborne", .backing_value = 2 },
    .{ .name = "being_juggled_or_downed", .backing_value = 4 },
    .{ .name = "blocking_lows", .backing_value = 8 },
    .{ .name = "blocking_mids", .backing_value = 16 },
    .{ .name = "wants_to_crouch", .backing_value = 32 },
    .{ .name = "standing_or_airborne_and_not_juggled", .backing_value = 64 },
    .{ .name = "downed", .backing_value = 128 },
    .{ .name = "neutral_blocking", .backing_value = 256 },
    .{ .name = "face_down", .backing_value = 512 },
    .{ .name = "being_juggled", .backing_value = 1024 },
    .{ .name = "not_blocking_or_neutral_blocking", .backing_value = 2048 },
    .{ .name = "blocking", .backing_value = 4096 },
    .{ .name = "force_airborne_no_low_crushing", .backing_value = 8192 },
    .{ .name = "airborne_move_or_downed", .backing_value = 16384 },
    .{ .name = "low_crushing_move", .backing_value = 32768 },
    .{ .name = "forward_move_modifier", .backing_value = 65536 },
    .{ .name = "crouched_but_not_fully", .backing_value = 262144 },
});

pub const CancelFlags = sdk.memory.Bitfield(u32, &.{
    .{ .name = "in_active_frame_1", .backing_value = 1 },
    .{ .name = "in_active_frame_2", .backing_value = 2 },
    .{ .name = "can_interact", .backing_value = 65536 },
    .{ .name = "can_cancel_recovery", .backing_value = 16777216 },
});

// MovesetExtractor: req
pub const CancelRequirement = enum(u32) {
    throw_escape_press_1 = 0x83, // MovesetExtractor: Pressed ONLY LP (1)
    throw_escape_press_2 = 0x84, // MovesetExtractor: Pressed ONLY RP (2)
    throw_escape_press_1_plus_2 = 0x85, // MovesetExtractor: Pressed ONLY RP+LP (1+2)
    throw_escape_hold = 0x87,
    _,
};

pub const CancelRequirements = packed struct {
    throw_escape_press_1: bool = false,
    throw_escape_press_2: bool = false,
    throw_escape_press_1_plus_2: bool = false,
    throw_escape_hold: bool = false,
};

pub const ThrowEscapeInput = enum(u32) {
    none = 0xC000001D,
    press_1 = 0xD000001C,
    press_2 = 0xE000001F,
    press_1_plus_2 = 0xF000001E,
    hold_1 = 0x90000018,
    hold_2 = 0xA000001B,
    hold_1_plus_2 = 0xB000001A,
    _,
};

pub const ThrowEscapeFlags = sdk.memory.Bitfield(u32, &.{
    .{ .name = "escape_success", .backing_value = 2048 },
});

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

pub const SimpleState = enum(u32) {
    standing_forward = 1,
    standing_back = 2,
    standing = 3,
    steve = 4,
    crouch_forward = 5,
    crouch_back = 6,
    crouch = 7,
    ground_face_up = 12,
    ground_face_down = 13,
    juggled = 14,
    knockdown = 15,
    off_axis_getup = 8,
    wall_splat_18 = 18,
    wall_splat_19 = 19,
    invincible = 20,
    airborne_24 = 24,
    airborne = 25,
    airborne_26 = 26,
    fly = 27,
    _,
};

pub fn AttackInput(comptime game_id: build_info.Game) type {
    return packed struct(u32) {
        pressed_buttons: Buttons = .{},
        _padding_1: u1 = 0,
        down_buttons: Buttons = .{},
        _padding_2: u1 = 0,
        not_down_buttons: Buttons = .{},
        _padding_3: u6 = 0,

        pub const Buttons = switch (game_id) {
            .t7 => packed struct(u8) {
                button_1: bool = false,
                button_2: bool = false,
                button_3: bool = false,
                button_4: bool = false,
                rage: bool = false,
                _padding: u3 = 0,
            },
            .t8 => packed struct(u8) {
                button_1: bool = false,
                button_2: bool = false,
                button_3: bool = false,
                button_4: bool = false,
                heat: bool = false,
                special_style: bool = false,
                rage: bool = false,
                _padding: u1 = 0,
            },
        };
    };
}

pub const DirectionalInput = enum(u32) {
    down_back = 2,
    down = 4,
    down_forward = 8,
    back = 16,
    neutral = 32,
    forward = 64,
    up_back = 128,
    up = 256,
    up_forward = 512,
    _,
};

pub fn Input(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => sdk.memory.Bitfield(u32, &.{
            .{ .name = "up", .backing_value = 1 },
            .{ .name = "down", .backing_value = 2 },
            .{ .name = "left", .backing_value = 4 },
            .{ .name = "right", .backing_value = 8 },
            .{ .name = "special_style", .backing_value = 256 },
            .{ .name = "rage", .backing_value = 512 },
            .{ .name = "button_3", .backing_value = 4096 },
            .{ .name = "button_4", .backing_value = 8192 },
            .{ .name = "button_1", .backing_value = 16384 },
            .{ .name = "button_2", .backing_value = 32768 },
        }),
        .t8 => sdk.memory.Bitfield(u32, &.{
            .{ .name = "up", .backing_value = 1 },
            .{ .name = "down", .backing_value = 2 },
            .{ .name = "left", .backing_value = 4 },
            .{ .name = "right", .backing_value = 8 },
            .{ .name = "special_style", .backing_value = 256 },
            .{ .name = "heat", .backing_value = 512 },
            .{ .name = "rage", .backing_value = 2048 },
            .{ .name = "button_3", .backing_value = 4096 },
            .{ .name = "button_4", .backing_value = 8192 },
            .{ .name = "button_1", .backing_value = 16384 },
            .{ .name = "button_2", .backing_value = 32768 },
        }),
    };
}

pub const HitLinePoint = extern struct {
    position: sdk.math.Vec3 = .zero,
    _padding: f32 = 0,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 16);
    }
};

pub const HitLine = extern struct {
    points: [3]HitLinePoint = [1]HitLinePoint{.{}} ** 3,
    _padding_1: [8]u8 = [1]u8{0} ** 8,
    ignore: Bool = .false,
    _padding_2: [7]u8 = [1]u8{0} ** 7,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 64);
    }
};

pub fn HitLines(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => [6]Converted(
            HitLinePoint,
            HitLinePoint,
            game.hitLinePointToUnrealSpace,
            game.hitLinePointFromUnrealSpace,
        ),
        .t8 => [4]Converted(
            HitLine,
            HitLine,
            game.hitLineToUnrealSpace,
            game.hitLineFromUnrealSpace,
        ),
    };
}
fn getDefaultHitLines(comptime game_id: build_info.Game) HitLines(game_id) {
    return switch (game_id) {
        .t7 => .{ .fromRaw(.{}), .fromRaw(.{}), .fromRaw(.{}), .fromRaw(.{}), .fromRaw(.{}), .fromRaw(.{}) },
        .t8 => .{ .fromRaw(.{}), .fromRaw(.{}), .fromRaw(.{}), .fromRaw(.{}) },
    };
}
comptime {
    std.debug.assert(@sizeOf(HitLines(.t7)) == 96);
    std.debug.assert(@sizeOf(HitLines(.t8)) == 256);
}

pub fn HurtCylinder(comptime game_id: build_info.Game) type {
    return extern struct {
        center: sdk.math.Vec3 = .zero,
        multiplier: f32 = 0,
        half_height: f32 = 0,
        squared_radius: f32 = 0,
        radius: f32 = 0,
        _padding: [
            switch (game_id) {
                .t7 => 1,
                .t8 => 9,
            }
        ]f32 = switch (game_id) {
            .t7 => [1]f32{0} ** 1,
            .t8 => [1]f32{0} ** 9,
        },

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
        left_ankle: Element = .fromRaw(.{}),
        right_ankle: Element = .fromRaw(.{}),
        left_hand: Element = .fromRaw(.{}),
        right_hand: Element = .fromRaw(.{}),
        left_knee: Element = .fromRaw(.{}),
        right_knee: Element = .fromRaw(.{}),
        left_elbow: Element = .fromRaw(.{}),
        right_elbow: Element = .fromRaw(.{}),
        head: Element = .fromRaw(.{}),
        left_shoulder: Element = .fromRaw(.{}),
        right_shoulder: Element = .fromRaw(.{}),
        upper_torso: Element = .fromRaw(.{}),
        left_pelvis: Element = .fromRaw(.{}),
        right_pelvis: Element = .fromRaw(.{}),

        const Self = @This();
        pub const Element = Converted(
            HurtCylinder(game_id),
            HurtCylinder(game_id),
            game.hurtCylinderToUnrealSpace(game_id),
            game.hurtCylinderFromUnrealSpace(game_id),
        );

        pub const len = @typeInfo(Self).@"struct".fields.len;

        pub fn asArray(self: anytype) sdk.misc.SelfBasedPointer(@TypeOf(self), Self, [len]Element) {
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
    center: sdk.math.Vec3 = .zero,
    multiplier: f32 = 0,
    radius: f32 = 0,
    _padding: [3]f32 = [1]f32{0} ** 3,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 32);
    }
};

pub const CollisionSpheres = extern struct {
    neck: Element = .fromRaw(.{}),
    left_elbow: Element = .fromRaw(.{}),
    right_elbow: Element = .fromRaw(.{}),
    lower_torso: Element = .fromRaw(.{}),
    left_knee: Element = .fromRaw(.{}),
    right_knee: Element = .fromRaw(.{}),
    left_ankle: Element = .fromRaw(.{}),
    right_ankle: Element = .fromRaw(.{}),

    const Self = @This();
    pub const Element = Converted(
        CollisionSphere,
        CollisionSphere,
        game.collisionSphereToUnrealSpace,
        game.collisionSphereFromUnrealSpace,
    );

    pub const len = @typeInfo(Self).@"struct".fields.len;

    pub fn asArray(self: anytype) sdk.misc.SelfBasedPointer(@TypeOf(self), Self, [len]Element) {
        return @ptrCast(self);
    }

    comptime {
        std.debug.assert(@sizeOf(Self) == 256);
    }
};

pub const Health = extern struct {
    value: u32 = 0,
    _padding: u32 = 0,
    encryption_key: u64 = 0,
};

pub fn Player(comptime game_id: build_info.Game) type {
    @setEvalBranchQuota(4000);
    const Transform = Converted(sdk.math.Mat4, sdk.math.Mat4, game.matrixToUnrealSpace, game.matrixFromUnrealSpace);
    const FloorZ = Converted(f32, f32, game.scaleToUnrealSpace, game.scaleFromUnrealSpace);
    const Rotation = Converted(u16, f32, game.u16ToRadians, game.u16FromRadians);
    const HeatGauge = Converted(u32, f32, game.decryptHeatGauge, game.encryptHeatGauge);
    const HealthValue = Converted(Health, Health, game.decryptHealth, game.encryptHealth);
    const T7MaxHealth = Converted(u32, u32, game.bitShiftRight(u32, 16), game.bitShiftLeft(u32, 16));
    return switch (game_id) {
        .t7 => sdk.memory.StructWithOffsets(null, &.{
            field(0x00D8, "character_id", u32, &0),
            field(0x0130, "transform_matrix", Transform, &.fromRaw(.identity)),
            field(0x01B0, "floor_z", FloorZ, &.fromRaw(0)),
            field(0x01BE, "rotation", Rotation, &.fromRaw(0)),
            field(0x01D4, "animation_frame", u32, &0),
            field(0x0218, "animation", Pointer(Animation(.t7)), &.fromPointer(null)),
            field(0x0264, "state_flags", StateFlags, &.{}),
            field(0x0328, "attack_type", AttackType, &.not_attack),
            field(0x0350, "animation_id", u32, &0),
            field(0x0390, "can_move", Bool, &.false),
            field(0x039C, "animation_total_frames", u32, &0),
            field(0x03D8, "hit_outcome", HitOutcome, &.none),
            field(0x0428, "simple_state", SimpleState, &.standing),
            field(0x0450, "correct_throw_escape_input", ThrowEscapeInput, &.none),
            field(0x049C, "throw_escape_flags", ThrowEscapeFlags, &.{}),
            field(0x06C0, "power_crushing", Bool, &.false),
            field(0x0788, "cancel_flags", CancelFlags, &.{}),
            field(0x095C, "frames_since_round_start", u32, &0),
            field(0x0AE0, "floor_number", u32, &0),
            field(0x0C00, "in_rage", Bool, &.false),
            field(0x0DD8, "attack_input", AttackInput(.t7), &.{}),
            field(0x0DDC, "directional_input", DirectionalInput, &.neutral),
            field(0x0DE4, "input_side", PlayerSide, &.left),
            field(0x0E0C, "input", Input(.t7), &.{}),
            field(0x0E50, "hit_lines", HitLines(.t7), &getDefaultHitLines(.t7)),
            field(0x0F10, "hurt_cylinders", HurtCylinders(.t7), &.{}),
            field(0x10D0, "collision_spheres", CollisionSpheres, &.{}),
            field(0x14E8, "health", HealthValue, &.fromRaw(.{})),
            field(0x14F8, "max_health", T7MaxHealth, &.fromRaw(0)),
        }),
        .t8 => sdk.memory.StructWithOffsets(null, &.{
            field(0x0168, "character_id", u32, &0),
            field(0x0200, "transform_matrix", Transform, &.fromRaw(.identity)),
            field(0x0354, "floor_z", FloorZ, &.fromRaw(0)),
            field(0x0376, "rotation", Rotation, &.fromRaw(0)),
            field(0x0390, "animation_frame", u32, &0),
            field(0x03D8, "animation", Pointer(Animation(.t8)), &.fromPointer(null)),
            field(0x0434, "state_flags", StateFlags, &.{}),
            field(0x0510, "attack_type", AttackType, &.not_attack),
            field(0x0550, "animation_id", u32, &0),
            field(0x05D0, "can_move", Bool, &.false),
            field(0x05E0, "animation_total_frames", u32, &0),
            field(0x061C, "hit_outcome", HitOutcome, &.none),
            field(0x0670, "simple_state", SimpleState, &.standing),
            field(0x0698, "correct_throw_escape_input", ThrowEscapeInput, &.none),
            field(0x06F8, "throw_escape_flags", ThrowEscapeFlags, &.{}),
            field(0x0C31, "power_crushing", Bool, &.false),
            field(0x0F91, "in_rage", Bool, &.false),
            field(0x0F98, "cancel_flags", CancelFlags, &.{}),
            field(0x15D0, "frames_since_round_start", u32, &0),
            field(0x19B0, "floor_number", u32, &0),
            field(0x2490, "heat_gauge", HeatGauge, &.fromRaw(0)),
            field(0x24A0, "used_heat", Bool, &.false),
            field(0x24C1, "in_heat", Bool, &.false),
            field(0x2508, "stage_set_number", u32, &0),
            field(0x28B0, "attack_input", AttackInput(.t8), &.{}),
            field(0x28B4, "directional_input", DirectionalInput, &.neutral),
            field(0x28BC, "input_side", PlayerSide, &.left),
            field(0x28E4, "input", Input(.t8), &.{}),
            field(0x2950, "hit_lines", HitLines(.t8), &getDefaultHitLines(.t8)),
            field(0x2D50, "hurt_cylinders", HurtCylinders(.t8), &.{}),
            field(0x31D0, "collision_spheres", CollisionSpheres, &.{}),
            field(0x3968, "health", HealthValue, &.fromRaw(.{})),
            field(0x3978, "health_recover_limit", HealthValue, &.fromRaw(.{})),
            field(0x3988, "max_health", HealthValue, &.fromRaw(.{})),
        }),
    };
}

pub const PlayerId = enum(u8) {
    player_1 = 0,
    player_2 = 1,
    _,
};

pub const PlayerName = [32]u8;

pub fn PlayerInfo(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => sdk.memory.StructWithOffsets(null, &.{
            field(0x068, "player_id", PlayerId, &.player_1),
            field(0x11C, "name", PlayerName, &([1]u8{0} ** 32)),
        }),
        .t8 => sdk.memory.StructWithOffsets(null, &.{
            field(0x005, "player_id", PlayerId, &.player_1),
            field(0x0B0, "name", PlayerName, &([1]u8{0} ** 32)),
        }),
    };
}

// MovesetExtractor: TK__Move
pub fn Animation(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => sdk.memory.StructWithOffsets(null, &.{
            field(0x6C, "airborne_start", u32, &0), // MovesetExtractor: airborne_start
            field(0x70, "airborne_end", u32, &0), // MovesetExtractor: airborne_end
            field(0xA0, "active_start", u32, &0), // MovesetExtractor: startup
            field(0xA4, "active_end", u32, &0), // MovesetExtractor: recovery
        }),
        .t8 => sdk.memory.StructWithOffsets(null, &.{
            field(0x124, "airborne_start", u32, &0), // MovesetExtractor: airborne_start
            field(0x128, "airborne_end", u32, &0), // MovesetExtractor: airborne_end
            field(0x158, "active_start", u32, &0), // MovesetExtractor: startup
            field(0x15C, "active_end", u32, &0), // MovesetExtractor: recovery
        }),
    };
}

pub const GlobalKey = enum(u32) {
    match = 0x472D4C0B,
    ruleset = 0xEDFEC9B0,
    replay = 0xEC52DADE,
    _,
};

pub const MatchPhase = enum(u32) {
    intro_1 = 0,
    intro_2 = 1,
    round_start = 3,
    mid_round = 4,
    round_end = 5,
    win_loose_outro = 8,
    draw_outro = 9,
    stage_transformation = 10,
    @"continue" = 17,
    practice_mode = 21,
    move_showcase = 22,
    rematch_menu_1 = 37,
    rematch_menu_2 = 38,
    _,
};

pub fn Match(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => sdk.memory.StructWithOffsets(null, &.{
            field(0x48, "frames_left_in_round", u32, &0),
            field(0x54, "phase", MatchPhase, &.intro_1),
            field(0x60, "players", [2]MatchPlayer(.t7), &.{ .{}, .{} }),
        }),
        .t8 => sdk.memory.StructWithOffsets(null, &.{
            field(0x1C, "frames_left_in_round", u32, &0),
            field(0x28, "phase", MatchPhase, &.intro_1),
            field(0x40, "players", [2]MatchPlayer(.t8), &.{ .{}, .{} }),
        }),
    };
}

pub fn MatchPlayer(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => sdk.memory.StructWithOffsets(0x0F0, &.{
            field(0x00, "rounds_won", u32, &0),
            field(0x6C, "combo_hits", u32, &0),
            field(0x7C, "combo_damage", u32, &0),
        }),
        .t8 => sdk.memory.StructWithOffsets(0x160, &.{
            field(0x00, "rounds_won", u32, &0),
            field(0x90, "combo_hits", u32, &0),
            field(0xA0, "combo_damage", u32, &0),
        }),
    };
}

pub fn Ruleset(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => sdk.memory.StructWithOffsets(null, &.{
            field(0x60, "rounds_needed_to_win", u32, &0),
        }),
        .t8 => sdk.memory.StructWithOffsets(null, &.{
            field(0x60, "rounds_needed_to_win", u32, &0),
        }),
    };
}

pub const ReplayMode = enum(u8) {
    playback = 0,
    loading = 1,
    _,
};

pub fn DepthBuffer(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => w32.ID3D11Texture2D,
        .t8 => w32.ID3D12Resource,
    };
}

// UE: APlayerCameraManager
pub fn CameraManager(comptime game_id: build_info.Game) type {
    const Float = switch (game_id) {
        .t7 => f32,
        .t8 => f64,
    };
    const Fov = sdk.memory.ConvertedValue(
        f32,
        f32,
        game.degreesToRadians(f32),
        game.radiansToDegrees(f32),
    );
    const Vec = sdk.memory.ConvertedValue(
        sdk.math.Vector(3, Float),
        sdk.math.Vec3,
        game.convertEachVectorElement(3, game.floatCast(Float, f32)),
        game.convertEachVectorElement(3, game.floatCast(f32, Float)),
    );
    const Rot = sdk.memory.ConvertedValue(
        sdk.math.Vector(3, Float),
        sdk.math.Vec3,
        game.convertEachVectorElement(3, game.composeConversions(.{
            game.degreesToRadians(Float),
            game.floatCast(Float, f32),
        })),
        game.convertEachVectorElement(3, game.composeConversions(.{
            game.floatCast(f32, Float),
            game.radiansToDegrees(Float),
        })),
    );
    return switch (game_id) {
        .t7 => sdk.memory.StructWithOffsets(null, &.{
            field(0x39C, "horizontal_fov", Fov, &.fromRaw(0)), // UE: LockedFOV
            field(0x3F8, "position", Vec, &.fromRaw(.zero)), // UE: CameraCache.POV.Location
            field(0x404, "rotation", Rot, &.fromRaw(.zero)), // UE: CameraCache.POV.Rotation
        }),
        .t8 => sdk.memory.StructWithOffsets(null, &.{
            field(0x02B4, "horizontal_fov", Fov, &.fromRaw(0)), // UE: LockedFOV
            field(0x22D0, "position", Vec, &.fromRaw(.zero)), // UE: CameraCachePrivate.POV.Location
            field(0x22E8, "rotation", Rot, &.fromRaw(.zero)), // UE: CameraCachePrivate.POV.Rotation
        }),
    };
}

// UE: AActor
pub fn Actor(comptime game_id: build_info.Game) type {
    const HiddenPolaris = sdk.memory.Bitfield(u8, &.{
        .{ .name = "value", .backing_value = 1 },
    });
    const CollisionEnabled = sdk.memory.Bitfield(u8, &.{
        .{ .name = "value", .backing_value = 1 },
    });
    const RootComponent = sdk.memory.Pointer(SceneComponent(game_id));
    return switch (game_id) {
        .t7 => sdk.memory.StructWithOffsets(null, &.{
            field(0x010, "class", ?*const UnrealClass, &null), // UE: UObject::Class
            field(0x07E, "collision_enabled", CollisionEnabled, &.{}), // UE : bActorEnableCollision
            field(0x160, "root_component", RootComponent, &.fromPointer(null)), // UE: RootComponent
        }),
        .t8 => sdk.memory.StructWithOffsets(null, &.{
            field(0x010, "class", ?*const UnrealClass, &null), // UE: UObject::Class
            field(0x059, "hidden_polaris", HiddenPolaris, &.{}), // UE/T8: bHidden_Polaris
            field(0x05D, "collision_enabled", CollisionEnabled, &.{}), // UE: bActorEnableCollision
            field(0x1A0, "root_component", RootComponent, &.fromPointer(null)), // UE: RootComponent
        }),
    };
}

// UE: USceneComponent
pub fn SceneComponent(comptime game_id: build_info.Game) type {
    const Float = switch (game_id) {
        .t7 => f32,
        .t8 => f64,
    };
    const Vec = sdk.memory.ConvertedValue(
        sdk.math.Vector(3, Float),
        sdk.math.Vec3,
        game.convertEachVectorElement(3, game.floatCast(Float, f32)),
        game.convertEachVectorElement(3, game.floatCast(f32, Float)),
    );
    const Rot = sdk.memory.ConvertedValue(
        sdk.math.Vector(3, Float),
        sdk.math.Vec3,
        game.convertEachVectorElement(3, game.composeConversions(.{
            game.degreesToRadians(Float),
            game.floatCast(Float, f32),
        })),
        game.convertEachVectorElement(3, game.composeConversions(.{
            game.floatCast(f32, Float),
            game.radiansToDegrees(Float),
        })),
    );
    return switch (game_id) {
        .t7 => sdk.memory.StructWithOffsets(null, &.{
            field(0x180, "relative_position", Vec, &.fromRaw(.zero)), // UE: RelativeLocation
            field(0x18C, "relative_rotation", Rot, &.fromRaw(.zero)), // UE: RelativeRotation
            field(0x1C0, "relative_scale", Vec, &.fromRaw(.zero)), // UE: RelativeScale3D
        }),
        .t8 => sdk.memory.StructWithOffsets(null, &.{
            field(0x128, "relative_position", Vec, &.fromRaw(.zero)), // UE: RelativeLocation
            field(0x140, "relative_rotation", Rot, &.fromRaw(.zero)), // UE: RelativeRotation
            field(0x158, "relative_scale", Vec, &.fromRaw(.zero)), // UE: RelativeScale3D
        }),
    };
}

// T7: TekkenWallActor, T8: PolarisStageWallActor
pub fn Wall(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => sdk.memory.StructWithOffsets(null, &.{
            field(0x000, "actor", Actor(.t7), &.{}), // parent
            field(0x390, "floor_number", u32, &0), // T7: FloorNo
            field(0x398, "wall_attribute", WallAttribute, &.{}), // T7: WallAttribute
        }),
        .t8 => sdk.memory.StructWithOffsets(null, &.{
            field(0x000, "actor", Actor(.t8), &.{}), // parent
            field(0x2B0, "state", StageGimmickState, &.init), // T8: State
            field(0x2B4, "set_number", u32, &0), // T8: SetNo
            field(0x2B8, "floor_number", u32, &0), // T8: FloorNo
            field(0x2CC, "is_hard", Bool, &.false), //T8: IsDurable
            field(0x2D0, "destruction_level", u32, &0), //T8: DestructLevel
            field(0x5A0, "wall_attribute", WallAttribute, &.{}), // T8: WallAttribute
        }),
    };
}

// T7: ATekkenFloorActor, T8: APolarisStageFloorActor
pub fn Floor(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => sdk.memory.StructWithOffsets(null, &.{
            field(0x000, "actor", Actor(.t7), &.{}), // parent
            field(0x390, "floor_number", u32, &0), // T7: FloorNo
            field(0x398, "is_breakable", Bool, &.false), // T7: bFloorBreakable
        }),
        .t8 => sdk.memory.StructWithOffsets(null, &.{
            field(0x000, "actor", Actor(.t8), &.{}), // parent
            field(0x2B0, "state", StageGimmickState, &.init), // T8: State
            field(0x2B4, "set_number", u32, &0), // T8: SetNo
            field(0x2B8, "floor_number", u32, &0), // T8: FloorNo
            field(0x2CC, "is_hard", Bool, &.false), //T8: IsDurable
            field(0x2D0, "destruction_level", u32, &0), //T8: DestructLevel
            field(0x5A0, "is_breakable", Bool, &.false), // T8: IsFloorBreakable
            field(0x5A3, "is_floor_blast", Bool, &.false), // T8: IsFloorBlast
        }),
    };
}

pub const WallAttribute = sdk.memory.Bitfield(u32, &.{
    .{ .name = "wall_break", .backing_value = 1 },
    .{ .name = "balcony_break", .backing_value = 4 },
    .{ .name = "hard", .backing_value = 32768 },
    .{ .name = "wall_blast", .backing_value = 65536 },
    .{ .name = "wall_bound", .backing_value = 131072 },
});

// T8: EStageGimmickState
pub const StageGimmickState = enum(u8) {
    init = 0,
    main = 1,
    damage = 2,
    @"break" = 3,
    vanish_wait = 4,
    vanish_start = 5,
    vanish = 6,
    revival = 7,
    end = 8,
    _,
};

// T7: ATekkenPlayerStart, T8: PolarisBattlePlayerStart
pub fn PlayerStart(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => sdk.memory.StructWithOffsets(null, &.{
            field(0x000, "actor", Actor(.t7), &.{}), // parent
            field(0x3B0, "floor_number", u32, &0), // T7: FloorNo
            field(0x3B8, "type", PlayerStartType(.t7), &.drama_start), // T7: PosType
        }),
        .t8 => sdk.memory.StructWithOffsets(null, &.{
            field(0x000, "actor", Actor(.t8), &.{}), // parent
            field(0x2CC, "stage_broken_history", u32, &0), // T8: StageBrokenHistory
            field(0x2D0, "type", PlayerStartType(.t8), &.drama_start), // T8: StagePositionTypeId
            field(0x2D4, "floor_number", u32, &0), // T8: FloorId
        }),
    };
}

// T7: ETekkenPlayerStart, T8: EStagePositionTypeId
pub fn PlayerStartType(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => enum(u8) {
            drama_start = 0,
            game_start = 1,
            drama_win = 2,
            drama_continue = 3,
            drama_special = 4,
            _,

            const Self = @This();

            pub fn isGameStart(self: Self) bool {
                return self == .game_start;
            }
        },
        .t8 => enum(u8) {
            drama_start = 0,
            game_start = 1,
            drama_win = 2,
            drama_continue = 3,
            drama_special = 4,
            game_start_2 = 5,
            game_start_3 = 6,
            game_start_4 = 7,
            game_start_5 = 8,
            game_start_6 = 9,
            game_start_7 = 10,
            game_start_8 = 11,
            game_start_9 = 12,
            drama_fate_1P = 13,
            drama_fate_2P = 14,
            drama_fate_set_0 = 15,
            drama_fate_set_1 = 16,
            drama_fate_set_2 = 17,
            drama_fate_set_3 = 18,
            drama_fate_set_4 = 19,
            _,

            const Self = @This();

            pub fn isGameStart(self: Self) bool {
                return switch (self) {
                    .drama_start => false,
                    .game_start => true,
                    .drama_win => false,
                    .drama_continue => false,
                    .drama_special => false,
                    .game_start_2 => true,
                    .game_start_3 => true,
                    .game_start_4 => true,
                    .game_start_5 => true,
                    .game_start_6 => true,
                    .game_start_7 => true,
                    .game_start_8 => true,
                    .game_start_9 => true,
                    .drama_fate_1P => false,
                    .drama_fate_2P => false,
                    .drama_fate_set_0 => false,
                    .drama_fate_set_1 => false,
                    .drama_fate_set_2 => false,
                    .drama_fate_set_3 => false,
                    .drama_fate_set_4 => false,
                    _ => false,
                };
            }
        },
    };
}

// UE: TArray
pub fn UnrealArrayList(comptime Element: type) type {
    return extern struct {
        data: ?[*]Element, // UE: AllocatorInstance
        len: i32, // UE: ArrayNum
        capacity: i32, // UE: ArrayMax

        const Self = @This();
        pub const empty = Self{
            .data = null,
            .len = 0,
            .capacity = 0,
        };

        pub fn free(self: *Self, unrealFree: *const UnrealFreeFunction) void {
            if (self.data) |data| {
                unrealFree(@ptrCast(data));
                self.data = null;
            }
            self.len = 0;
            self.capacity = 0;
        }

        pub fn asSlice(self: anytype) sdk.misc.SelfBasedSlice(@TypeOf(self), Self, Element) {
            const data = self.data orelse return &.{};
            if (self.len < 0) {
                return &.{};
            }
            const len: usize = @intCast(self.len);
            return data[0..len];
        }
    };
}

// UE: EObjectFlags
pub const UnrealObjectFlags = packed struct(u32) {
    public: bool = false,
    standalone: bool = false,
    mark_as_native: bool = false,
    transactional: bool = false,
    class_default_object: bool = false,
    archetype_object: bool = false,
    transient: bool = false,
    mark_as_root_set: bool = false,
    tag_garbage_temp: bool = false,
    need_initialization: bool = false,
    need_load: bool = false,
    keep_for_cooker: bool = false,
    need_post_load: bool = false,
    need_post_load_subobjects: bool = false,
    newer_version_exists: bool = false,
    begin_destroyed: bool = false,
    finish_destroyed: bool = false,
    being_regenerated: bool = false,
    default_sub_object: bool = false,
    was_loaded: bool = false,
    text_export_transient: bool = false,
    load_completed: bool = false,
    inheritable_component_template: bool = false,
    duplicate_transient: bool = false,
    strong_ref_on_frame: bool = false,
    non_pie_duplicate_transient: bool = false,
    dynamic: bool = false,
    will_be_loaded: bool = false,
    has_external_package: bool = false,
    pending_kill: bool = false,
    garbage: bool = false,
    allocated_in_shared_page: bool = false,

    const Self = @This();

    pub const default_exclude = Self{
        .class_default_object = true,
        .archetype_object = true,
        .need_initialization = true,
        .need_load = true,
        .newer_version_exists = true,
        .begin_destroyed = true,
        .finish_destroyed = true,
        .pending_kill = true,
        .garbage = true,
    };
};

// UE: EInternalObjectFlags
pub const UnrealInternalObjectFlags = sdk.memory.Bitfield(u32, &.{
    .{ .name = "loader_import", .backing_value = 0x100000 },
    .{ .name = "garbage", .backing_value = 0x200000 },
    .{ .name = "reachable_in_cluster", .backing_value = 0x800000 },
    .{ .name = "cluster_root", .backing_value = 0x1000000 },
    .{ .name = "native", .backing_value = 0x2000000 },
    .{ .name = "async", .backing_value = 0x4000000 },
    .{ .name = "async_loading", .backing_value = 0x8000000 },
    .{ .name = "unreachable", .backing_value = 0x10000000 },
    .{ .name = "pending_kill", .backing_value = 0x20000000 },
    .{ .name = "root_set", .backing_value = 0x40000000 },
    .{ .name = "pending_construction", .backing_value = 0x80000000 },
});

// UE: UClass
pub const UnrealClass = opaque {};

// UE: UObject
pub const UnrealObject = opaque {};

// UE: TMap
pub const GlobalsMap = opaque {};

pub fn TickFunction(comptime game_id: build_info.Game) type {
    return switch (game_id) {
        .t7 => fn (param_1: u8, param_2: u32) callconv(.c) void,
        .t8 => fn (param_1: u64, param_2: u8, param_3: u8, param_4: u8) callconv(.c) void,
    };
}

pub const ProcessCancelRequirementFunction = fn (
    param_1: *const CancelRequirement,
    param_2: i64,
    param_3: i64,
) callconv(.c) u64;

// UE: FMemory::Free
pub const UnrealFreeFunction = fn (original: *anyopaque) callconv(.c) void;

// UE: FindObject<UClass>
pub const FindUnrealClassFunction = fn (
    outer: ?*const UnrealObject,
    name: [*:0]const u16,
    exact_class: bool,
) callconv(.c) ?*const UnrealClass;

// UE: GetObjectsOfClass
pub const FindUnrealObjectsOfClassFunction = fn (
    class_to_look_for: *const UnrealClass,
    results: *UnrealArrayList(*UnrealObject),
    b_include_derived_classes: bool,
    exclude_flags: UnrealObjectFlags,
    exclusion_internal_flags: UnrealInternalObjectFlags,
) callconv(.c) void;

// UE5: FD3D12DescriptorCache::SetRenderTargets
pub const SetRenderTargetsFunction = fn (this: usize, param_1: usize, param_2: u32, param_3: usize) callconv(.c) void;

// T8
pub const GetGlobalsMapFunction = fn () callconv(.c) *GlobalsMap;

// UE: TMap::Find
pub const FindGlobalAddressFunction = fn (map: *const GlobalsMap, key: *const GlobalKey) callconv(.c) usize;

// T8: IsReplayMode
pub const IsReplayFunction = fn (is_replay: *bool, is_pre_calculated: *bool) callconv(.c) void;
