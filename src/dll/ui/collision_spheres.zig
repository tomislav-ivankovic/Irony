const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("../ui/root.zig");

const color = sdk.math.Vec4.fromArray(.{ 0.0, 0.0, 1.0, 0.5 });
const thickness = 1.0;

pub fn drawCollisionSpheres(frame: *const model.Frame, matrix: sdk.math.Mat4, inverse_matrix: sdk.math.Mat4) void {
    for (&frame.players) |*player| {
        const spheres: *const model.CollisionSpheres = if (player.collision_spheres) |*s| s else continue;
        for (spheres.values) |sphere| {
            ui.drawSphere(sphere, color, thickness, matrix, inverse_matrix);
        }
    }
}
