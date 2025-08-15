const std = @import("std");

pub fn step(edge: f32, x: f32) f32 {
    return if (x <= edge) 0 else 1;
}

pub fn linearStep(edge_0: f32, edge_1: f32, x: f32) f32 {
    if (edge_0 == edge_1) {
        return step(edge_0, x);
    }
    const t = (x - edge_0) / (edge_1 - edge_0);
    return std.math.clamp(t, 0.0, 1.0);
}

pub fn smoothStep(edge_0: f32, edge_1: f32, x: f32) f32 {
    const t = linearStep(edge_0, edge_1, x);
    return t * t * (3.0 - 2.0 * t);
}

const testing = std.testing;

test "step should return correct value" {
    try testing.expectEqual(0.0, step(1.0, 0.5));
    try testing.expectEqual(0.0, step(1.0, 1.0));
    try testing.expectEqual(1.0, step(1.0, 1.5));
}

test "linearStep should return correct value" {
    try testing.expectEqual(0.0, linearStep(1.0, 2.0, 0.75));
    try testing.expectEqual(0.0, linearStep(1.0, 2.0, 1.0));
    try testing.expectEqual(0.25, linearStep(1.0, 2.0, 1.25));
    try testing.expectEqual(0.5, linearStep(1.0, 2.0, 1.5));
    try testing.expectEqual(0.75, linearStep(1.0, 2.0, 1.75));
    try testing.expectEqual(1.0, linearStep(1.0, 2.0, 2.0));
    try testing.expectEqual(1.0, linearStep(1.0, 2.0, 2.25));
}

test "smoothStep should return correct value" {
    try testing.expectEqual(0.0, smoothStep(1.0, 2.0, 0.75));
    try testing.expectEqual(0.0, smoothStep(1.0, 2.0, 1.0));
    try testing.expect(smoothStep(1.0, 2.0, 1.25) > 0.0);
    try testing.expect(smoothStep(1.0, 2.0, 1.25) < 0.25);
    try testing.expectEqual(0.5, smoothStep(1.0, 2.0, 1.5));
    try testing.expect(smoothStep(1.0, 2.0, 1.75) > 0.75);
    try testing.expect(smoothStep(1.0, 2.0, 1.75) < 1.0);
    try testing.expectEqual(1.0, smoothStep(1.0, 2.0, 2.0));
    try testing.expectEqual(1.0, smoothStep(1.0, 2.0, 2.25));
}
