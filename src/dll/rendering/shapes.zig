const std = @import("std");
const build_info = @import("build_info");
const sdk = @import("../../sdk/root.zig");
const game = @import("../game/root.zig");
const rendering = @import("root.zig");

pub const Shapes = struct {
    allocator: std.mem.Allocator,
    list: std.ArrayList(Shape),

    const Self = @This();
    pub const Shape = struct {
        geometry: Geometry,
        color: sdk.math.Vec4,
        thickness: f32,
    };
    pub const Geometry = union(enum) {
        point: sdk.math.Vec3,
        line: sdk.math.LineSegment3,
        outline: sdk.math.LineSegment3,
        sphere: sdk.math.Sphere,
        cylinder: sdk.math.Cylinder,
    };

    const circle_segments = 32;

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .list = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.list.deinit(self.allocator);
    }

    pub fn clear(self: *Self) void {
        self.list.clearRetainingCapacity();
    }

    pub fn addPoint(self: *Self, point: sdk.math.Vec3, color: sdk.math.Vec4, thickness: f32) void {
        self.add(.{
            .geometry = .{ .point = point },
            .color = color,
            .thickness = thickness,
        });
    }

    pub fn addLine(self: *Self, line: sdk.math.LineSegment3, color: sdk.math.Vec4, thickness: f32) void {
        self.add(.{
            .geometry = .{ .line = line },
            .color = color,
            .thickness = thickness,
        });
    }

    pub fn addOutline(self: *Self, line: sdk.math.LineSegment3, color: sdk.math.Vec4, thickness: f32) void {
        self.add(.{
            .geometry = .{ .outline = line },
            .color = color,
            .thickness = thickness,
        });
    }

    pub fn addSphere(self: *Self, sphere: sdk.math.Sphere, color: sdk.math.Vec4, thickness: f32) void {
        self.add(.{
            .geometry = .{ .sphere = sphere },
            .color = color,
            .thickness = thickness,
        });
    }

    pub fn addCylinder(self: *Self, cylinder: sdk.math.Cylinder, color: sdk.math.Vec4, thickness: f32) void {
        self.add(.{
            .geometry = .{ .cylinder = cylinder },
            .color = color,
            .thickness = thickness,
        });
    }

    fn add(self: *Self, shape: Shape) void {
        self.list.append(self.allocator, shape) catch |err| {
            sdk.misc.error_context.append("Failed to add the shape to array list.", .{});
            sdk.misc.error_context.append("Failed to add a shape to shape renderer.", .{});
            sdk.misc.error_context.logError(err);
            return;
        };
    }

    pub fn render(self: *const Self, lines: anytype, camera_position: sdk.math.Vec3) void {
        for (self.list.items) |*shape| {
            switch (shape.geometry) {
                .point => |point| renderPoint(point, shape.color, shape.thickness, lines),
                .line => |line| renderLine(line, shape.color, shape.thickness, lines),
                .outline => |line| renderOutline(line, shape.color, shape.thickness, lines),
                .sphere => |sphere| renderSphere(sphere, shape.color, shape.thickness, lines, camera_position),
                .cylinder => |cylinder| renderCylinder(cylinder, shape.color, shape.thickness, lines, camera_position),
            }
        }
    }

    fn renderPoint(
        point: sdk.math.Vec3,
        color: sdk.math.Vec4,
        thickness: f32,
        lines: anytype,
    ) void {
        lines.add(.{ .point_1 = point, .point_2 = point }, color, thickness, 1);
    }

    fn renderLine(
        line: sdk.math.LineSegment3,
        color: sdk.math.Vec4,
        thickness: f32,
        lines: anytype,
    ) void {
        lines.add(line, color, thickness, 1);
    }

    fn renderOutline(
        line: sdk.math.LineSegment3,
        color: sdk.math.Vec4,
        thickness: f32,
        lines: anytype,
    ) void {
        lines.add(line, color, thickness, 0.01);
    }

    fn renderSphere(
        sphere: sdk.math.Sphere,
        color: sdk.math.Vec4,
        thickness: f32,
        lines: anytype,
        camera_position: sdk.math.Vec3,
    ) void {
        const camera_to_sphere = camera_position.distanceTo(sphere.center);
        const circle_radius, const camera_to_circle = if (sphere.radius != 0) block: {
            if (camera_to_sphere < sphere.radius) {
                return;
            }
            const camera_to_edge = std.math.sqrt(
                (camera_to_sphere * camera_to_sphere) - (sphere.radius * sphere.radius),
            );
            const circle_radius = sphere.radius * camera_to_edge / camera_to_sphere;
            const camera_to_circle = circle_radius * camera_to_edge / sphere.radius;
            break :block .{ circle_radius, camera_to_circle };
        } else .{ 0, camera_to_sphere };

        const forward = sphere.center.subtract(camera_position).normalize();
        const arbitrary: sdk.math.Vec3 = if (forward.z() < 0.999) .plus_z else .plus_x;
        const right = arbitrary.cross(forward).normalize();
        const up = forward.cross(right);
        const circle_center = camera_position.add(forward.scale(camera_to_circle));

        for (0..circle_segments) |index| {
            const i_1: f32 = @floatFromInt(index);
            const i_2: f32 = @floatFromInt(index + 1);
            const n: f32 = @floatFromInt(circle_segments);
            const angle_1 = 2 * std.math.pi * i_1 / n;
            const angle_2 = 2 * std.math.pi * i_2 / n;
            const point_1 = right.scale(std.math.cos(angle_1))
                .add(up.scale(std.math.sin(angle_1)))
                .scale(circle_radius)
                .add(circle_center);
            const point_2 = right.scale(std.math.cos(angle_2))
                .add(up.scale(std.math.sin(angle_2)))
                .scale(circle_radius)
                .add(circle_center);
            lines.add(.{ .point_1 = point_1, .point_2 = point_2 }, color, thickness, 1);
        }
    }

    fn renderCylinder(
        cylinder: sdk.math.Cylinder,
        color: sdk.math.Vec4,
        thickness: f32,
        lines: anytype,
        camera_position: sdk.math.Vec3,
    ) void {
        const radius = cylinder.radius;
        const center = cylinder.center;
        const half_height = cylinder.half_height;

        const camera_to_center = camera_position.swizzle("xy").distanceTo(center.swizzle("xy"));
        if (camera_to_center > radius) {
            const edge_offset, const camera_to_edges_base = if (radius != 0) block: {
                const camera_to_edge = std.math.sqrt(
                    (camera_to_center * camera_to_center) - (radius * radius),
                );
                const edge_offset = radius * camera_to_edge / camera_to_center;
                const camera_to_edges_base = edge_offset * camera_to_edge / radius;
                break :block .{ edge_offset, camera_to_edges_base };
            } else .{ 0, camera_to_center };

            const forward = center.swizzle("xy").subtract(camera_position.swizzle("xy")).normalize();
            const right = sdk.math.Vec2.fromArray(.{ -forward.y(), forward.x() });
            const base = camera_position.swizzle("xy").add(forward.scale(camera_to_edges_base));
            const offset = right.scale(edge_offset);

            const line_1 = sdk.math.LineSegment3{
                .point_1 = base.add(offset).extend(center.z() + half_height),
                .point_2 = base.add(offset).extend(center.z() - half_height),
            };
            const line_2 = sdk.math.LineSegment3{
                .point_1 = base.subtract(offset).extend(center.z() + half_height),
                .point_2 = base.subtract(offset).extend(center.z() - half_height),
            };
            lines.add(line_1, color, thickness, 1);
            lines.add(line_2, color, thickness, 1);
        }

        for (0..circle_segments) |index| {
            const i_1: f32 = @floatFromInt(index);
            const i_2: f32 = @floatFromInt(index + 1);
            const n: f32 = @floatFromInt(circle_segments);
            const angle_1 = 2 * std.math.pi * i_1 / n;
            const angle_2 = 2 * std.math.pi * i_2 / n;
            const line_1 = sdk.math.LineSegment3{
                .point_1 = center.add(.fromArray(.{
                    radius * std.math.cos(angle_1),
                    radius * std.math.sin(angle_1),
                    half_height,
                })),
                .point_2 = center.add(.fromArray(.{
                    radius * std.math.cos(angle_2),
                    radius * std.math.sin(angle_2),
                    half_height,
                })),
            };
            const line_2 = sdk.math.LineSegment3{
                .point_1 = center.add(.fromArray(.{
                    radius * std.math.cos(angle_1),
                    radius * std.math.sin(angle_1),
                    -half_height,
                })),
                .point_2 = center.add(.fromArray(.{
                    radius * std.math.cos(angle_2),
                    radius * std.math.sin(angle_2),
                    -half_height,
                })),
            };
            lines.add(line_1, color, thickness, 1);
            lines.add(line_2, color, thickness, 1);
        }
    }
};

const testing = std.testing;

const MockLines = struct {
    allocator: std.mem.Allocator,
    list: std.ArrayList(Line),

    const Self = @This();
    const Line = struct {
        geometry: sdk.math.LineSegment3,
        color: sdk.math.Vec4,
        thickness: f32,
        depth_factor: f16,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .list = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.list.deinit(self.allocator);
    }

    pub fn add(
        self: *Self,
        line: sdk.math.LineSegment3,
        color: sdk.math.Vec4,
        thickness: f32,
        depth_factor: f16,
    ) void {
        self.list.append(self.allocator, .{
            .geometry = line,
            .color = color,
            .thickness = thickness,
            .depth_factor = depth_factor,
        }) catch @panic("Failed to add line to list.");
    }
};

test "should render point correctly" {
    var lines = MockLines.init(testing.allocator);
    defer lines.deinit();
    var shapes = Shapes.init(testing.allocator);
    defer shapes.deinit();

    shapes.addPoint(.fromArray(.{ 1, 2, 3 }), .fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), 10);
    shapes.render(&lines, .zero);

    const items = lines.list.items;
    try testing.expectEqual(1, items.len);
    try testing.expectEqual(sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ 1, 2, 3 }),
        .point_2 = .fromArray(.{ 1, 2, 3 }),
    }, items[0].geometry);
    try testing.expectEqual(sdk.math.Vec4.fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), items[0].color);
    try testing.expectEqual(10, items[0].thickness);
    try testing.expectEqual(1, items[0].depth_factor);
}

test "should render line correctly" {
    var lines = MockLines.init(testing.allocator);
    defer lines.deinit();
    var shapes = Shapes.init(testing.allocator);
    defer shapes.deinit();

    shapes.addLine(
        .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
        .fromArray(.{ 0.1, 0.2, 0.3, 0.4 }),
        10,
    );
    shapes.render(&lines, .zero);

    const items = lines.list.items;
    try testing.expectEqual(1, items.len);
    try testing.expectEqual(sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ 1, 2, 3 }),
        .point_2 = .fromArray(.{ 4, 5, 6 }),
    }, items[0].geometry);
    try testing.expectEqual(sdk.math.Vec4.fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), items[0].color);
    try testing.expectEqual(10, items[0].thickness);
    try testing.expectEqual(1, items[0].depth_factor);
}

test "should render outline correctly" {
    var lines = MockLines.init(testing.allocator);
    defer lines.deinit();
    var shapes = Shapes.init(testing.allocator);
    defer shapes.deinit();

    shapes.addOutline(
        .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
        .fromArray(.{ 0.1, 0.2, 0.3, 0.4 }),
        10,
    );
    shapes.render(&lines, .zero);

    const items = lines.list.items;
    try testing.expectEqual(1, items.len);
    try testing.expectEqual(sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ 1, 2, 3 }),
        .point_2 = .fromArray(.{ 4, 5, 6 }),
    }, items[0].geometry);
    try testing.expectEqual(sdk.math.Vec4.fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), items[0].color);
    try testing.expectEqual(10, items[0].thickness);
    try testing.expectEqual(0.01, items[0].depth_factor);
}

test "should render sphere correctly" {
    var lines = MockLines.init(testing.allocator);
    defer lines.deinit();
    var shapes = Shapes.init(testing.allocator);
    defer shapes.deinit();

    const center = sdk.math.Vec3.fromArray(.{ 1, 2, 3 });
    const camera = sdk.math.Vec3.fromArray(.{ 3, 4, 3 });
    shapes.addSphere(.{ .center = center, .radius = 2 }, .fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), 10);
    shapes.render(&lines, camera);

    const items = lines.list.items;
    try testing.expectEqual(Shapes.circle_segments, items.len);
    for (items) |*item| {
        try testing.expectApproxEqAbs(2, item.geometry.point_1.distanceTo(center), 0.0001);
        try testing.expectApproxEqAbs(2, item.geometry.point_2.distanceTo(center), 0.0001);
        try testing.expectApproxEqAbs(2, item.geometry.point_1.distanceTo(camera), 0.0001);
        try testing.expectApproxEqAbs(2, item.geometry.point_2.distanceTo(camera), 0.0001);
        try testing.expectEqual(sdk.math.Vec4.fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), item.color);
        try testing.expectEqual(10, item.thickness);
        try testing.expectEqual(1, item.depth_factor);
    }
}

test "should render nothing when camera is inside sphere" {
    var lines = MockLines.init(testing.allocator);
    defer lines.deinit();
    var shapes = Shapes.init(testing.allocator);
    defer shapes.deinit();

    shapes.addSphere(.{ .center = .zero, .radius = 2 }, .fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), 10);
    shapes.render(&lines, .plus_x);

    try testing.expectEqual(0, lines.list.items.len);
}

test "should render cylinder correctly" {
    var lines = MockLines.init(testing.allocator);
    defer lines.deinit();
    var shapes = Shapes.init(testing.allocator);
    defer shapes.deinit();

    shapes.addCylinder(.{
        .center = .fromArray(.{ 1, 2, 3 }),
        .radius = 2,
        .half_height = 1,
    }, .fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), 10);
    shapes.render(&lines, .fromArray(.{ 3, 4, 3 }));

    const items = lines.list.items;
    try testing.expectEqual(2 * Shapes.circle_segments + 2, items.len);
    for (items[0..2]) |*item| {
        try testing.expectApproxEqAbs(2, item.geometry.point_1.distanceTo(.fromArray(.{ 1, 2, 4 })), 0.0001);
        try testing.expectApproxEqAbs(2, item.geometry.point_2.distanceTo(.fromArray(.{ 1, 2, 2 })), 0.0001);
        try testing.expectApproxEqAbs(2, item.geometry.point_1.distanceTo(.fromArray(.{ 3, 4, 4 })), 0.0001);
        try testing.expectApproxEqAbs(2, item.geometry.point_2.distanceTo(.fromArray(.{ 3, 4, 2 })), 0.0001);
        try testing.expectEqual(sdk.math.Vec4.fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), item.color);
        try testing.expectEqual(10, item.thickness);
        try testing.expectEqual(1, item.depth_factor);
    }
    for (items[2..items.len]) |*item| {
        try testing.expectApproxEqAbs(2, @min(
            item.geometry.point_1.distanceTo(.fromArray(.{ 1, 2, 4 })),
            item.geometry.point_1.distanceTo(.fromArray(.{ 1, 2, 2 })),
        ), 0.0001);
        try testing.expectApproxEqAbs(2, @min(
            item.geometry.point_2.distanceTo(.fromArray(.{ 1, 2, 4 })),
            item.geometry.point_2.distanceTo(.fromArray(.{ 1, 2, 2 })),
        ), 0.0001);
        try testing.expectEqual(sdk.math.Vec4.fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), item.color);
        try testing.expectEqual(10, item.thickness);
        try testing.expectEqual(1, item.depth_factor);
    }
}

test "should not render cylinder side lines when camera 2D projection is inside cylinder 2D projection" {
    var lines = MockLines.init(testing.allocator);
    defer lines.deinit();
    var shapes = Shapes.init(testing.allocator);
    defer shapes.deinit();

    shapes.addCylinder(.{ .center = .zero, .radius = 2, .half_height = 1 }, .fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), 10);
    shapes.render(&lines, .fromArray(.{ 1, 0, 3 }));

    const items = lines.list.items;
    try testing.expectEqual(2 * Shapes.circle_segments, items.len);
    for (items) |*item| {
        try testing.expectApproxEqAbs(2, @min(
            item.geometry.point_1.distanceTo(.fromArray(.{ 0, 0, 1 })),
            item.geometry.point_1.distanceTo(.fromArray(.{ 0, 0, -1 })),
        ), 0.0001);
        try testing.expectApproxEqAbs(2, @min(
            item.geometry.point_2.distanceTo(.fromArray(.{ 0, 0, 1 })),
            item.geometry.point_2.distanceTo(.fromArray(.{ 0, 0, -1 })),
        ), 0.0001);
        try testing.expectEqual(sdk.math.Vec4.fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), item.color);
        try testing.expectEqual(10, item.thickness);
        try testing.expectEqual(1, item.depth_factor);
    }
}
