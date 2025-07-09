const math = @import("root.zig");

pub const LineSegment2 = struct {
    point_1: math.Vec2,
    point_2: math.Vec2,
};

pub const LineSegment3 = struct {
    point_1: math.Vec3,
    point_2: math.Vec3,
};

pub const Circle = struct {
    center: math.Vec2,
    radius: f32,
};

pub const Sphere = struct {
    center: math.Vec3,
    radius: f32,
};

pub const Cylinder = struct {
    center: math.Vec3,
    radius: f32,
    half_height: f32,
};
