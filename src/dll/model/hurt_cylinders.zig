const std = @import("std");
const sdk = @import("../../sdk/root.zig");

pub const HurtCylinderId = enum {
    left_ankle,
    right_ankle,
    left_hand,
    right_hand,
    left_knee,
    right_knee,
    left_elbow,
    right_elbow,
    head,
    left_shoulder,
    right_shoulder,
    upper_torso,
    left_pelvis,
    right_pelvis,
};

pub const HurtCylinder = struct {
    cylinder: sdk.math.Cylinder,
    flags: HurtCylinderFlags = .{},
};

pub const HurtCylinderFlags = packed struct {
    is_intersecting: bool = false,
    is_crushing: bool = false,
    is_power_crushing: bool = false,
    is_connected: bool = false,
    is_blocking: bool = false,
    is_being_hit: bool = false,
    is_being_counter_hit: bool = false,
};

pub const HurtCylinders = std.EnumArray(HurtCylinderId, HurtCylinder);
