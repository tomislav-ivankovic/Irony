const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("root.zig");

pub const Projectile = struct {
    id: u32 = 0,
    shape: ProjectileShape,
    attack_type: ?model.AttackType = null,
    flags: model.HitLineFlags = .{},
};

pub const ProjectileShape = union(enum) {
    line: sdk.math.SweptCylinder,
    sphere: sdk.math.Sphere,
    cylinder: sdk.math.Cylinder,
    box: sdk.math.Box,
};

pub const Projectiles = sdk.misc.BoundedArray(8, Projectile, .{
    .shape = .{ .sphere = .{ .center = .zero, .radius = 0 } },
}, false);
