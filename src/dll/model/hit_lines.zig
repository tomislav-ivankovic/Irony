const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const game = @import("../game/root.zig");

pub const HitLine = struct {
    line: sdk.math.LineSegment3,
    flags: HitLineFlags = .{},
};

pub const HitLineFlags = packed struct(u8) {
    is_inactive: bool = false,
    is_intersecting: bool = false,
    is_crushed: bool = false,
    is_power_crushed: bool = false,
    is_connected: bool = false,
    is_blocked: bool = false,
    is_normal_hitting: bool = false,
    is_counter_hitting: bool = false,
};

pub const HitLines = sdk.misc.BoundedArray(8, HitLine, .{
    .line = .{ .point_1 = .zero, .point_2 = .zero },
}, false);
