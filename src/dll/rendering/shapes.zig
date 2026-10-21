const std = @import("std");
const build_info = @import("build_info");
const sdk = @import("../../sdk/root.zig");
const game = @import("../game/root.zig");
const rendering = @import("root.zig");

pub const Shapes = struct {
    allocator: std.mem.Allocator,
    list: std.ArrayList(Shape),

    const Self = @This();
    pub const Shape = union(enum) {
        point: Point,
        line: Line,
        sphere: Sphere,
        cylinder: Cylinder,

        pub const Point = struct {
            geometry: sdk.math.Vec3,
            color: sdk.math.Vec4,
            thickness: f32,
        };
        pub const Line = struct {
            geometry: sdk.math.LineSegment3,
            color: sdk.math.Vec4,
            thickness: f32,
            is_outline: bool,
        };
        pub const Sphere = struct {
            geometry: sdk.math.Sphere,
            fill_color: sdk.math.Vec4,
            outline_color: sdk.math.Vec4,
            outline_thickness: f32,
        };
        pub const Cylinder = struct {
            geometry: sdk.math.Cylinder,
            fill_color: sdk.math.Vec4,
            outline_color: sdk.math.Vec4,
            outline_thickness: f32,
        };
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
        self.add(.{ .point = .{
            .geometry = point,
            .color = color,
            .thickness = thickness,
        } });
    }

    pub fn addLine(self: *Self, line: sdk.math.LineSegment3, color: sdk.math.Vec4, thickness: f32) void {
        self.add(.{ .line = .{
            .geometry = line,
            .color = color,
            .thickness = thickness,
            .is_outline = false,
        } });
    }

    pub fn addOutline(self: *Self, line: sdk.math.LineSegment3, color: sdk.math.Vec4, thickness: f32) void {
        self.add(.{ .line = .{
            .geometry = line,
            .color = color,
            .thickness = thickness,
            .is_outline = true,
        } });
    }

    pub fn addSphere(
        self: *Self,
        sphere: sdk.math.Sphere,
        fill_color: sdk.math.Vec4,
        outline_color: sdk.math.Vec4,
        outline_thickness: f32,
    ) void {
        self.add(.{ .sphere = .{
            .geometry = sphere,
            .fill_color = fill_color,
            .outline_color = outline_color,
            .outline_thickness = outline_thickness,
        } });
    }

    pub fn addCylinder(
        self: *Self,
        cylinder: sdk.math.Cylinder,
        fill_color: sdk.math.Vec4,
        outline_color: sdk.math.Vec4,
        outline_thickness: f32,
    ) void {
        self.add(.{ .cylinder = .{
            .geometry = cylinder,
            .fill_color = fill_color,
            .outline_color = outline_color,
            .outline_thickness = outline_thickness,
        } });
    }

    fn add(self: *Self, shape: Shape) void {
        self.list.append(self.allocator, shape) catch |err| {
            sdk.misc.error_context.append("Failed to add the shape to the array list.", .{});
            sdk.misc.error_context.append("Failed to add a shape to shape renderer.", .{});
            sdk.misc.error_context.logError(err);
            return;
        };
    }

    pub fn render(self: *const Self, triangles: anytype, lines: anytype, camera_position: sdk.math.Vec3) void {
        for (self.list.items) |*shape| {
            switch (shape.*) {
                .point => |*point| {
                    renderPoint(point.geometry, point.color, point.thickness, lines);
                },
                .line => |*line| {
                    renderLine(line.geometry, line.color, line.thickness, line.is_outline, lines);
                },
                .sphere => |*sphere| {
                    renderSphereFill(sphere.geometry, sphere.fill_color, triangles);
                    renderSphereOutline(
                        sphere.geometry,
                        sphere.outline_color,
                        sphere.outline_thickness,
                        lines,
                        camera_position,
                    );
                },
                .cylinder => |*cylinder| {
                    renderCylinderFill(cylinder.geometry, cylinder.fill_color, triangles);
                    renderCylinderOutline(
                        cylinder.geometry,
                        cylinder.outline_color,
                        cylinder.outline_thickness,
                        lines,
                        camera_position,
                    );
                },
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
        is_outline: bool,
        lines: anytype,
    ) void {
        const depth_factor: f16 = if (is_outline) 0.01 else 1;
        lines.add(line, color, thickness, depth_factor);
    }

    fn renderSphereFill(
        sphere: sdk.math.Sphere,
        color: sdk.math.Vec4,
        triangles: anytype,
    ) void {
        const center = sphere.center;
        const radius = sphere.radius;
        const start_index = triangles.getNextIndex() orelse unreachable;

        const latitude_segments = circle_segments / 2;
        for (1..latitude_segments) |latitude_index| {
            const latitude_i: f32 = @floatFromInt(latitude_index);
            const latitude_n: f32 = @floatFromInt(latitude_segments);
            const latitude = std.math.pi * latitude_i / latitude_n;

            const ring_radius = radius * std.math.sin(latitude);
            const z = radius * std.math.cos(latitude);

            for (0..circle_segments) |longitude_index| {
                const longitude_i: f32 = @floatFromInt(longitude_index);
                const longitude_n: f32 = @floatFromInt(circle_segments);
                const angle = 2 * std.math.pi * longitude_i / longitude_n;

                const x = ring_radius * std.math.cos(angle);
                const y = ring_radius * std.math.sin(angle);

                const point = center.add(.fromArray(.{ x, y, z }));
                triangles.addVertex(point, color);
            }
        }
        const top_pole = center.add(.fromArray(.{ 0, 0, radius }));
        const bottom_pole = center.add(.fromArray(.{ 0, 0, -radius }));
        triangles.addVertex(top_pole, color);
        triangles.addVertex(bottom_pole, color);

        const ring_count = latitude_segments - 1;
        const top_pole_index = start_index + ring_count * circle_segments;
        const bottom_pole_index = top_pole_index + 1;

        for (0..ring_count - 1) |ring_index| {
            for (0..circle_segments) |segment_index| {
                const next_segment_index = (segment_index + 1) % circle_segments;
                const current_index: @TypeOf(start_index) = @intCast(
                    start_index + ring_index * circle_segments + segment_index,
                );
                const next_index: @TypeOf(start_index) = @intCast(
                    start_index + ring_index * circle_segments + next_segment_index,
                );
                const next_ring_index: @TypeOf(start_index) = @intCast(
                    start_index + (ring_index + 1) * circle_segments + segment_index,
                );
                const next_ring_next_index: @TypeOf(start_index) = @intCast(
                    start_index + (ring_index + 1) * circle_segments + next_segment_index,
                );
                triangles.addTriangle(current_index, next_index, next_ring_index);
                triangles.addTriangle(next_index, next_ring_next_index, next_ring_index);
            }
        }

        for (0..circle_segments) |segment_index| {
            const next_segment_index = (segment_index + 1) % circle_segments;
            const current_index: @TypeOf(start_index) = @intCast(start_index + segment_index);
            const next_index: @TypeOf(start_index) = @intCast(start_index + next_segment_index);
            triangles.addTriangle(top_pole_index, current_index, next_index);
        }

        const last_ring_start = start_index + (ring_count - 1) * circle_segments;
        for (0..circle_segments) |segment_index| {
            const next_segment_index = (segment_index + 1) % circle_segments;
            const current_index: @TypeOf(start_index) = @intCast(last_ring_start + segment_index);
            const next_index: @TypeOf(start_index) = @intCast(last_ring_start + next_segment_index);
            triangles.addTriangle(current_index, bottom_pole_index, next_index);
        }
    }

    fn renderSphereOutline(
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

    fn renderCylinderFill(
        cylinder: sdk.math.Cylinder,
        color: sdk.math.Vec4,
        triangles: anytype,
    ) void {
        const center = cylinder.center;
        const radius = cylinder.radius;
        const half_height = cylinder.half_height;
        const start_index = triangles.getNextIndex() orelse unreachable;

        for (0..circle_segments) |index| {
            const i: f32 = @floatFromInt(index);
            const n: f32 = @floatFromInt(circle_segments);
            const angle = 2 * std.math.pi * i / n;
            const x = radius * std.math.cos(angle);
            const y = radius * std.math.sin(angle);
            const bottom_point = center.add(.fromArray(.{ x, y, -half_height }));
            const top_point = center.add(.fromArray(.{ x, y, half_height }));
            triangles.addVertex(bottom_point, color);
            triangles.addVertex(top_point, color);
        }
        const bottom_center = center.add(.fromArray(.{ 0, 0, -half_height }));
        const top_center = center.add(.fromArray(.{ 0, 0, half_height }));
        triangles.addVertex(bottom_center, color);
        triangles.addVertex(top_center, color);

        const bottom_center_index = start_index + (2 * circle_segments);
        const top_center_index = bottom_center_index + 1;
        for (0..circle_segments) |segment_index| {
            const next_segment_index = (segment_index + 1) % circle_segments;
            const bottom_index: @TypeOf(start_index) = @intCast(start_index + (2 * segment_index));
            const top_index = bottom_index + 1;
            const next_bottom_index: @TypeOf(start_index) = @intCast(start_index + (2 * next_segment_index));
            const next_top_index = next_bottom_index + 1;
            triangles.addTriangle(bottom_index, next_bottom_index, top_index);
            triangles.addTriangle(next_bottom_index, next_top_index, top_index);
            triangles.addTriangle(bottom_center_index, bottom_index, next_bottom_index);
            triangles.addTriangle(top_index, next_top_index, top_center_index);
        }
    }

    fn renderCylinderOutline(
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

const MockTriangles = struct {
    allocator: std.mem.Allocator,
    vertices: std.ArrayList(Vertex),
    indices: std.ArrayList(Index),

    const Self = @This();
    const Vertex = extern struct {
        position: sdk.math.Vec3,
        color: sdk.math.Vec4,
    };
    const Index = u16;

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .vertices = .empty,
            .indices = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.indices.deinit(self.allocator);
        self.vertices.deinit(self.allocator);
    }

    pub fn addVertex(self: *Self, position: sdk.math.Vec3, color: sdk.math.Vec4) void {
        self.vertices.append(self.allocator, .{ .position = position, .color = color }) catch
            @panic("Failed to add vertex to list.");
    }

    pub fn addTriangle(self: *Self, index_1: Index, index_2: Index, index_3: Index) void {
        self.indices.appendSlice(self.allocator, &.{ index_1, index_2, index_3 }) catch
            @panic("Failed to add indices to list.");
    }

    pub fn getNextIndex(self: *const Self) ?Index {
        return std.math.cast(Index, self.vertices.items.len);
    }
};

test "should render point correctly" {
    var triangles = MockTriangles.init(testing.allocator);
    defer triangles.deinit();
    var lines = MockLines.init(testing.allocator);
    defer lines.deinit();
    var shapes = Shapes.init(testing.allocator);
    defer shapes.deinit();

    shapes.addPoint(.fromArray(.{ 1, 2, 3 }), .fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), 10);
    shapes.render(&triangles, &lines, .zero);

    try testing.expectEqual(0, triangles.vertices.items.len);
    try testing.expectEqual(0, triangles.indices.items.len);
    try testing.expectEqual(1, lines.list.items.len);
    const line = &lines.list.items[0];
    try testing.expectEqual(sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ 1, 2, 3 }),
        .point_2 = .fromArray(.{ 1, 2, 3 }),
    }, line.geometry);
    try testing.expectEqual(sdk.math.Vec4.fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), line.color);
    try testing.expectEqual(10, line.thickness);
    try testing.expectEqual(1, line.depth_factor);
}

test "should render normal line correctly" {
    var triangles = MockTriangles.init(testing.allocator);
    defer triangles.deinit();
    var lines = MockLines.init(testing.allocator);
    defer lines.deinit();
    var shapes = Shapes.init(testing.allocator);
    defer shapes.deinit();

    shapes.addLine(
        .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
        .fromArray(.{ 0.1, 0.2, 0.3, 0.4 }),
        10,
    );
    shapes.render(&triangles, &lines, .zero);

    try testing.expectEqual(0, triangles.vertices.items.len);
    try testing.expectEqual(0, triangles.indices.items.len);
    try testing.expectEqual(1, lines.list.items.len);
    const line = &lines.list.items[0];
    try testing.expectEqual(sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ 1, 2, 3 }),
        .point_2 = .fromArray(.{ 4, 5, 6 }),
    }, line.geometry);
    try testing.expectEqual(sdk.math.Vec4.fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), line.color);
    try testing.expectEqual(10, line.thickness);
    try testing.expectEqual(1, line.depth_factor);
}

test "should render outline correctly" {
    var triangles = MockTriangles.init(testing.allocator);
    defer triangles.deinit();
    var lines = MockLines.init(testing.allocator);
    defer lines.deinit();
    var shapes = Shapes.init(testing.allocator);
    defer shapes.deinit();

    shapes.addOutline(
        .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
        .fromArray(.{ 0.1, 0.2, 0.3, 0.4 }),
        10,
    );
    shapes.render(&triangles, &lines, .zero);

    try testing.expectEqual(0, triangles.vertices.items.len);
    try testing.expectEqual(0, triangles.indices.items.len);
    try testing.expectEqual(1, lines.list.items.len);
    const line = lines.list.items[0];
    try testing.expectEqual(sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ 1, 2, 3 }),
        .point_2 = .fromArray(.{ 4, 5, 6 }),
    }, line.geometry);
    try testing.expectEqual(sdk.math.Vec4.fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), line.color);
    try testing.expectEqual(10, line.thickness);
    try testing.expectEqual(0.01, line.depth_factor);
}

test "should render sphere correctly" {
    var triangles = MockTriangles.init(testing.allocator);
    defer triangles.deinit();
    var lines = MockLines.init(testing.allocator);
    defer lines.deinit();
    var shapes = Shapes.init(testing.allocator);
    defer shapes.deinit();

    const center = sdk.math.Vec3.fromArray(.{ 1, 2, 3 });
    const camera = sdk.math.Vec3.fromArray(.{ 3, 4, 3 });
    shapes.addSphere(
        .{ .center = center, .radius = 2 },
        .fromArray(.{ 0.1, 0.2, 0.3, 0.4 }),
        .fromArray(.{ 0.5, 0.6, 0.7, 0.8 }),
        10,
    );
    shapes.render(&triangles, &lines, camera);

    const expected_vertex_count = ((Shapes.circle_segments / 2 - 1) * Shapes.circle_segments) + 2;
    try testing.expectEqual(expected_vertex_count, triangles.vertices.items.len);
    for (triangles.vertices.items) |*vertex| {
        try testing.expectApproxEqAbs(2, vertex.position.distanceTo(center), 0.0001);
        try testing.expectEqual(sdk.math.Vec4.fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), vertex.color);
    }

    try testing.expectEqual(Shapes.circle_segments, lines.list.items.len);
    for (lines.list.items) |*line| {
        try testing.expectApproxEqAbs(2, line.geometry.point_1.distanceTo(center), 0.0001);
        try testing.expectApproxEqAbs(2, line.geometry.point_2.distanceTo(center), 0.0001);
        try testing.expectApproxEqAbs(2, line.geometry.point_1.distanceTo(camera), 0.0001);
        try testing.expectApproxEqAbs(2, line.geometry.point_2.distanceTo(camera), 0.0001);
        try testing.expectEqual(sdk.math.Vec4.fromArray(.{ 0.5, 0.6, 0.7, 0.8 }), line.color);
        try testing.expectEqual(10, line.thickness);
        try testing.expectEqual(1, line.depth_factor);
    }
}

test "should render no lines when camera is inside sphere" {
    var triangles = MockTriangles.init(testing.allocator);
    defer triangles.deinit();
    var lines = MockLines.init(testing.allocator);
    defer lines.deinit();
    var shapes = Shapes.init(testing.allocator);
    defer shapes.deinit();

    shapes.addSphere(
        .{ .center = .zero, .radius = 2 },
        .fromArray(.{ 0.1, 0.2, 0.3, 0.4 }),
        .fromArray(.{ 0.5, 0.6, 0.7, 0.8 }),
        10,
    );
    shapes.render(&triangles, &lines, .plus_x);

    try testing.expectEqual(0, lines.list.items.len);
}

test "should render cylinder correctly" {
    var triangles = MockTriangles.init(testing.allocator);
    defer triangles.deinit();
    var lines = MockLines.init(testing.allocator);
    defer lines.deinit();
    var shapes = Shapes.init(testing.allocator);
    defer shapes.deinit();

    shapes.addCylinder(
        .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 2, .half_height = 1 },
        .fromArray(.{ 0.1, 0.2, 0.3, 0.4 }),
        .fromArray(.{ 0.5, 0.6, 0.7, 0.8 }),
        10,
    );
    shapes.render(&triangles, &lines, .fromArray(.{ 3, 4, 3 }));

    try testing.expectEqual(2 * Shapes.circle_segments + 2, triangles.vertices.items.len);
    try testing.expectEqual(3 * 4 * Shapes.circle_segments, triangles.indices.items.len);
    for (triangles.vertices.items[0..(triangles.vertices.items.len - 2)]) |*vertex| {
        try testing.expectApproxEqAbs(2, @min(
            vertex.position.distanceTo(.fromArray(.{ 1, 2, 4 })),
            vertex.position.distanceTo(.fromArray(.{ 1, 2, 2 })),
        ), 0.0001);
        try testing.expectApproxEqAbs(2, @min(
            vertex.position.distanceTo(.fromArray(.{ 1, 2, 4 })),
            vertex.position.distanceTo(.fromArray(.{ 1, 2, 2 })),
        ), 0.0001);
        try testing.expectEqual(sdk.math.Vec4.fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), vertex.color);
    }
    for (triangles.vertices.items[(triangles.vertices.items.len - 2)..triangles.vertices.items.len]) |*vertex| {
        try testing.expectApproxEqAbs(0, @min(
            vertex.position.distanceTo(.fromArray(.{ 1, 2, 4 })),
            vertex.position.distanceTo(.fromArray(.{ 1, 2, 2 })),
        ), 0.0001);
        try testing.expectApproxEqAbs(0, @min(
            vertex.position.distanceTo(.fromArray(.{ 1, 2, 4 })),
            vertex.position.distanceTo(.fromArray(.{ 1, 2, 2 })),
        ), 0.0001);
        try testing.expectEqual(sdk.math.Vec4.fromArray(.{ 0.1, 0.2, 0.3, 0.4 }), vertex.color);
    }

    try testing.expectEqual(2 * Shapes.circle_segments + 2, lines.list.items.len);
    for (lines.list.items[0..2]) |*line| {
        try testing.expectApproxEqAbs(2, line.geometry.point_1.distanceTo(.fromArray(.{ 1, 2, 4 })), 0.0001);
        try testing.expectApproxEqAbs(2, line.geometry.point_2.distanceTo(.fromArray(.{ 1, 2, 2 })), 0.0001);
        try testing.expectApproxEqAbs(2, line.geometry.point_1.distanceTo(.fromArray(.{ 3, 4, 4 })), 0.0001);
        try testing.expectApproxEqAbs(2, line.geometry.point_2.distanceTo(.fromArray(.{ 3, 4, 2 })), 0.0001);
        try testing.expectEqual(sdk.math.Vec4.fromArray(.{ 0.5, 0.6, 0.7, 0.8 }), line.color);
        try testing.expectEqual(10, line.thickness);
        try testing.expectEqual(1, line.depth_factor);
    }
    for (lines.list.items[2..lines.list.items.len]) |*line| {
        try testing.expectApproxEqAbs(2, @min(
            line.geometry.point_1.distanceTo(.fromArray(.{ 1, 2, 4 })),
            line.geometry.point_1.distanceTo(.fromArray(.{ 1, 2, 2 })),
        ), 0.0001);
        try testing.expectApproxEqAbs(2, @min(
            line.geometry.point_2.distanceTo(.fromArray(.{ 1, 2, 4 })),
            line.geometry.point_2.distanceTo(.fromArray(.{ 1, 2, 2 })),
        ), 0.0001);
        try testing.expectEqual(sdk.math.Vec4.fromArray(.{ 0.5, 0.6, 0.7, 0.8 }), line.color);
        try testing.expectEqual(10, line.thickness);
        try testing.expectEqual(1, line.depth_factor);
    }
}

test "should not render cylinder side lines when camera 2D projection is inside cylinder 2D projection" {
    var triangles = MockTriangles.init(testing.allocator);
    defer triangles.deinit();
    var lines = MockLines.init(testing.allocator);
    defer lines.deinit();
    var shapes = Shapes.init(testing.allocator);
    defer shapes.deinit();

    shapes.addCylinder(
        .{ .center = .zero, .radius = 2, .half_height = 1 },
        .fromArray(.{ 0.1, 0.2, 0.3, 0.4 }),
        .fromArray(.{ 0.5, 0.6, 0.7, 0.8 }),
        10,
    );
    shapes.render(&triangles, &lines, .fromArray(.{ 1, 0, 3 }));

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
        try testing.expectEqual(sdk.math.Vec4.fromArray(.{ 0.5, 0.6, 0.7, 0.8 }), item.color);
        try testing.expectEqual(10, item.thickness);
        try testing.expectEqual(1, item.depth_factor);
    }
}
