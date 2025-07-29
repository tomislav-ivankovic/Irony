const std = @import("std");
const sdk = @import("../sdk/root.zig");
const core = @import("root.zig");

pub const HitDetector = struct {
    const Self = @This();

    pub fn detect(self: *Self, frame: *core.Frame) void {
        _ = self;
        detectIntersections(&frame.players[0].hurt_cylinders, &frame.players[1].hit_lines);
        detectIntersections(&frame.players[1].hurt_cylinders, &frame.players[0].hit_lines);
    }

    fn detectIntersections(hurt_cylinders: *?core.HurtCylinders, hit_lines: *core.HitLines) void {
        const cylinders: *core.HurtCylinders = if (hurt_cylinders.*) |*c| c else return;
        for (&cylinders.values) |*cylinder| {
            for (hit_lines.asMutableSlice()) |*line| {
                const intersects = sdk.math.checkCylinderLineSegmentIntersection(cylinder.cylinder, line.line);
                cylinder.intersects = intersects;
                line.intersects = intersects;
            }
        }
    }
};

// TODO write tests for this.
