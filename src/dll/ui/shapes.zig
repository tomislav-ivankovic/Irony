const std = @import("std");
const builtin = @import("builtin");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const rendering = @import("../rendering/root.zig");
const ui = @import("../ui/root.zig");

pub const Shapes = union(enum) {
    _2d: Shapes2D,
    _3d: Shapes3D,
    _void: VoidShapes,

    const Self = @This();

    pub fn drawPoint(self: *const Self, position: sdk.math.Vec3, color: sdk.math.Vec4, thickness: f32) void {
        switch (self.*) {
            ._2d => |*s| s.drawPoint(position, color, thickness),
            ._3d => |*s| s.drawPoint(position, color, thickness),
            ._void => |*s| s.drawPoint(position, color, thickness),
        }
    }

    pub fn drawLine(
        self: *const Self,
        line: sdk.math.LineSegment3,
        color: sdk.math.Vec4,
        thickness: f32,
        offset: f32,
    ) void {
        switch (self.*) {
            ._2d => |*s| s.drawLine(line, color, thickness, offset),
            ._3d => |*s| s.drawLine(line, color, thickness),
            ._void => |*s| s.drawLine(line, color, thickness),
        }
    }

    pub fn drawOutline(
        self: *const Self,
        line: sdk.math.LineSegment3,
        color: sdk.math.Vec4,
        thickness: f32,
        offset: f32,
    ) void {
        switch (self.*) {
            ._2d => |*s| s.drawOutline(line, color, thickness, offset),
            ._3d => |*s| s.drawOutline(line, color, thickness),
            ._void => |*s| s.drawOutline(line, color, thickness),
        }
    }

    pub fn drawSphere(self: *const Self, sphere: sdk.math.Sphere, color: sdk.math.Vec4, thickness: f32) void {
        switch (self.*) {
            ._2d => |*s| s.drawSphere(sphere, color, thickness),
            ._3d => |*s| s.drawSphere(sphere, color, thickness),
            ._void => |*s| s.drawSphere(sphere, color, thickness),
        }
    }

    pub fn drawCylinder(self: *const Self, cylinder: sdk.math.Cylinder, color: sdk.math.Vec4, thickness: f32) void {
        switch (self.*) {
            ._2d => |*s| s.drawCylinder(cylinder, color, thickness),
            ._3d => |*s| s.drawCylinder(cylinder, color, thickness),
            ._void => |*s| s.drawCylinder(cylinder, color, thickness),
        }
    }
};

pub const Shapes2D = struct {
    direction: ui.ViewDirection,
    matrix: sdk.math.Mat4,
    inverse_matrix: sdk.math.Mat4,
    thickness_scale: f32 = 1.0,

    const Self = @This();

    pub fn drawPoint(self: *const Self, position: sdk.math.Vec3, color: sdk.math.Vec4, thickness: f32) void {
        const draw_list = imgui.igGetWindowDrawList();
        const transformed = position.pointTransform(self.matrix).swizzle("xy");
        const u32_color = imgui.igGetColorU32_Vec4(color.toImVec());
        const scaled_thickness = self.thickness_scale * thickness;

        imgui.ImDrawList_AddCircleFilled(draw_list, transformed.toImVec(), 0.5 * scaled_thickness, u32_color, 16);

        if (builtin.is_test) {
            testing_shapes.append(.{ .point = .{
                .world_position = position,
                .screen_position = transformed,
                .color = color,
                .thickness = self.thickness_scale * thickness,
            } });
        }
    }

    pub fn drawLine(
        self: *const Self,
        line: sdk.math.LineSegment3,
        color: sdk.math.Vec4,
        thickness: f32,
        offset: f32,
    ) void {
        const draw_list = imgui.igGetWindowDrawList();
        const point_1 = line.point_1.pointTransform(self.matrix).swizzle("xy");
        const point_2 = line.point_2.pointTransform(self.matrix).swizzle("xy");
        const rotate_90 = comptime sdk.math.Mat2.fromZRotation(0.5 * std.math.pi);
        const difference = point_2.subtract(point_1);
        const offset_vector = switch (difference.isZero(1e-6)) {
            true => sdk.math.Vec2.zero,
            false => difference.normalize().multiply(rotate_90).scale(offset),
        };
        const offset_point_1 = point_1.add(offset_vector);
        const offset_point_2 = point_2.add(offset_vector);
        const u32_color = imgui.igGetColorU32_Vec4(color.toImVec());
        const scaled_thickness = self.thickness_scale * thickness;

        imgui.ImDrawList_AddLine(
            draw_list,
            offset_point_1.toImVec(),
            offset_point_2.toImVec(),
            u32_color,
            scaled_thickness,
        );

        if (builtin.is_test) {
            testing_shapes.append(.{ .line = .{
                .world_line = line,
                .screen_line = .{ .point_1 = offset_point_1, .point_2 = offset_point_2 },
                .color = color,
                .thickness = scaled_thickness,
            } });
        }
    }

    pub fn drawOutline(
        self: *const Self,
        line: sdk.math.LineSegment3,
        color: sdk.math.Vec4,
        thickness: f32,
        offset: f32,
    ) void {
        const draw_list = imgui.igGetWindowDrawList();
        const point_1 = line.point_1.pointTransform(self.matrix).swizzle("xy");
        const point_2 = line.point_2.pointTransform(self.matrix).swizzle("xy");
        const rotate_90 = comptime sdk.math.Mat2.fromZRotation(0.5 * std.math.pi);
        const difference = point_2.subtract(point_1);
        const offset_vector = switch (difference.isZero(1e-6)) {
            true => sdk.math.Vec2.zero,
            false => difference.normalize().multiply(rotate_90).scale(offset),
        };
        const offset_point_1 = point_1.add(offset_vector);
        const offset_point_2 = point_2.add(offset_vector);
        const u32_color = imgui.igGetColorU32_Vec4(color.toImVec());
        const scaled_thickness = self.thickness_scale * thickness;

        imgui.ImDrawList_AddLine(
            draw_list,
            offset_point_1.toImVec(),
            offset_point_2.toImVec(),
            u32_color,
            scaled_thickness,
        );

        if (builtin.is_test) {
            testing_shapes.append(.{ .outline = .{
                .world_line = line,
                .screen_line = .{ .point_1 = offset_point_1, .point_2 = offset_point_2 },
                .color = color,
                .thickness = scaled_thickness,
            } });
        }
    }

    pub fn drawSphere(self: *const Self, sphere: sdk.math.Sphere, color: sdk.math.Vec4, thickness: f32) void {
        const world_right = sdk.math.Vec3.plus_x.directionTransform(self.inverse_matrix).normalize();
        const world_up = sdk.math.Vec3.plus_y.directionTransform(self.inverse_matrix).normalize();

        const draw_list = imgui.igGetWindowDrawList();
        const center = sphere.center.pointTransform(self.matrix).swizzle("xy");
        const radius = world_up.add(world_right).scale(sphere.radius).directionTransform(self.matrix).swizzle("xy");
        const u32_color = imgui.igGetColorU32_Vec4(color.toImVec());
        const scaled_thickness = self.thickness_scale * thickness;

        imgui.ImDrawList_AddEllipse(draw_list, center.toImVec(), radius.toImVec(), u32_color, 0, 32, scaled_thickness);

        if (builtin.is_test) {
            testing_shapes.append(.{ .sphere = .{
                .world_sphere = sphere,
                .screen_center = center,
                .screen_half_size = radius,
                .color = color,
                .thickness = scaled_thickness,
            } });
        }
    }

    pub fn drawCylinder(self: *const Self, cylinder: sdk.math.Cylinder, color: sdk.math.Vec4, thickness: f32) void {
        const world_right = sdk.math.Vec3.plus_x.directionTransform(self.inverse_matrix).normalize();
        const world_up = sdk.math.Vec3.plus_y.directionTransform(self.inverse_matrix).normalize();

        const draw_list = imgui.igGetWindowDrawList();
        const center = cylinder.center.pointTransform(self.matrix).swizzle("xy");
        const u32_color = imgui.igGetColorU32_Vec4(color.toImVec());
        const scaled_thickness = self.thickness_scale * thickness;

        switch (self.direction) {
            .front, .side => {
                const half_size = world_up.scale(cylinder.half_height)
                    .add(world_right.scale(cylinder.radius))
                    .directionTransform(self.matrix)
                    .swizzle("xy");
                const min = center.subtract(half_size).toImVec();
                const max = center.add(half_size).toImVec();
                imgui.ImDrawList_AddRect(draw_list, min, max, u32_color, 0, 0, scaled_thickness);

                if (builtin.is_test) {
                    testing_shapes.append(.{ .cylinder = .{
                        .world_cylinder = cylinder,
                        .screen_shape = .rectangle,
                        .screen_center = center,
                        .screen_half_size = half_size,
                        .color = color,
                        .thickness = scaled_thickness,
                    } });
                }
            },
            .top => {
                const im_center = center.toImVec();
                const radius = world_up
                    .add(world_right)
                    .scale(cylinder.radius)
                    .directionTransform(self.matrix)
                    .swizzle("xy");
                imgui.ImDrawList_AddEllipse(draw_list, im_center, radius.toImVec(), u32_color, 0, 32, scaled_thickness);

                if (builtin.is_test) {
                    testing_shapes.append(.{ .cylinder = .{
                        .world_cylinder = cylinder,
                        .screen_shape = .ellipse,
                        .screen_center = center,
                        .screen_half_size = radius,
                        .color = color,
                        .thickness = scaled_thickness,
                    } });
                }
            },
        }
    }
};

pub const Shapes3D = struct {
    renderer: *rendering.Shapes,
    thickness_scale: f32 = 1.0,
    fill_alpha: f32 = 0.25,

    const Self = @This();

    pub fn drawPoint(self: *const Self, position: sdk.math.Vec3, color: sdk.math.Vec4, thickness: f32) void {
        const scaled_thickness = self.thickness_scale * thickness;
        self.renderer.addPoint(position, color, scaled_thickness);
        if (builtin.is_test) {
            testing_shapes.append(.{ .point = .{
                .world_position = position,
                .screen_position = null,
                .color = color,
                .thickness = scaled_thickness,
            } });
        }
    }

    pub fn drawLine(self: *const Self, line: sdk.math.LineSegment3, color: sdk.math.Vec4, thickness: f32) void {
        const scaled_thickness = self.thickness_scale * thickness;
        self.renderer.addLine(line, color, scaled_thickness);
        if (builtin.is_test) {
            testing_shapes.append(.{ .line = .{
                .world_line = line,
                .screen_line = null,
                .color = color,
                .thickness = scaled_thickness,
            } });
        }
    }

    pub fn drawOutline(self: *const Self, line: sdk.math.LineSegment3, color: sdk.math.Vec4, thickness: f32) void {
        const scaled_thickness = self.thickness_scale * thickness;
        self.renderer.addOutline(line, color, scaled_thickness);
        if (builtin.is_test) {
            testing_shapes.append(.{ .outline = .{
                .world_line = line,
                .screen_line = null,
                .color = color,
                .thickness = scaled_thickness,
            } });
        }
    }

    pub fn drawSphere(self: *const Self, sphere: sdk.math.Sphere, color: sdk.math.Vec4, thickness: f32) void {
        var fill_color = color;
        fill_color.asColor().a *= self.fill_alpha;
        const scaled_thickness = self.thickness_scale * thickness;
        self.renderer.addSphere(sphere, fill_color, color, scaled_thickness);
        if (builtin.is_test) {
            testing_shapes.append(.{ .sphere = .{
                .world_sphere = sphere,
                .screen_center = null,
                .screen_half_size = null,
                .color = color,
                .thickness = scaled_thickness,
            } });
        }
    }

    pub fn drawCylinder(self: *const Self, cylinder: sdk.math.Cylinder, color: sdk.math.Vec4, thickness: f32) void {
        var fill_color = color;
        fill_color.asColor().a *= self.fill_alpha;
        const scaled_thickness = self.thickness_scale * thickness;
        self.renderer.addCylinder(cylinder, fill_color, color, scaled_thickness);
        if (builtin.is_test) {
            testing_shapes.append(.{ .cylinder = .{
                .world_cylinder = cylinder,
                .screen_shape = null,
                .screen_center = null,
                .screen_half_size = null,
                .color = color,
                .thickness = scaled_thickness,
            } });
        }
    }
};

pub const VoidShapes = struct {
    const Self = @This();

    pub fn drawPoint(self: *const Self, position: sdk.math.Vec3, color: sdk.math.Vec4, thickness: f32) void {
        _ = self;
        if (builtin.is_test) {
            testing_shapes.append(.{ .point = .{
                .world_position = position,
                .screen_position = null,
                .color = color,
                .thickness = thickness,
            } });
        }
    }

    pub fn drawLine(self: *const Self, line: sdk.math.LineSegment3, color: sdk.math.Vec4, thickness: f32) void {
        _ = self;
        if (builtin.is_test) {
            testing_shapes.append(.{ .line = .{
                .world_line = line,
                .screen_line = null,
                .color = color,
                .thickness = thickness,
            } });
        }
    }

    pub fn drawOutline(self: *const Self, line: sdk.math.LineSegment3, color: sdk.math.Vec4, thickness: f32) void {
        _ = self;
        if (builtin.is_test) {
            testing_shapes.append(.{ .outline = .{
                .world_line = line,
                .screen_line = null,
                .color = color,
                .thickness = thickness,
            } });
        }
    }

    pub fn drawSphere(self: *const Self, sphere: sdk.math.Sphere, color: sdk.math.Vec4, thickness: f32) void {
        _ = self;
        if (builtin.is_test) {
            testing_shapes.append(.{ .sphere = .{
                .world_sphere = sphere,
                .screen_center = null,
                .screen_half_size = null,
                .color = color,
                .thickness = thickness,
            } });
        }
    }

    pub fn drawCylinder(self: *const Self, cylinder: sdk.math.Cylinder, color: sdk.math.Vec4, thickness: f32) void {
        _ = self;
        if (builtin.is_test) {
            testing_shapes.append(.{ .cylinder = .{
                .world_cylinder = cylinder,
                .screen_shape = null,
                .screen_center = null,
                .screen_half_size = null,
                .color = color,
                .thickness = thickness,
            } });
        }
    }
};

var testing_shapes_instance = TestingShapes{};
pub const testing_shapes: *TestingShapes = &testing_shapes_instance;

pub const TestingShapes = struct {
    list: std.ArrayList(Shape) = .empty,
    allocator: ?std.mem.Allocator = null,

    comptime {
        if (!builtin.is_test) {
            @compileError("Testing shapes should only be used inside tests.");
        }
    }
    const Self = @This();
    pub const Shape = union(enum) {
        point: Point,
        line: Line,
        outline: Line,
        sphere: Sphere,
        cylinder: Cylinder,
    };
    pub const Point = struct {
        world_position: sdk.math.Vec3,
        screen_position: ?sdk.math.Vec2,
        color: sdk.math.Vec4,
        thickness: f32,
    };
    pub const Line = struct {
        world_line: sdk.math.LineSegment3,
        screen_line: ?sdk.math.LineSegment2,
        color: sdk.math.Vec4,
        thickness: f32,
    };
    pub const Sphere = struct {
        world_sphere: sdk.math.Sphere,
        screen_center: ?sdk.math.Vec2,
        screen_half_size: ?sdk.math.Vec2,
        color: sdk.math.Vec4,
        thickness: f32,
    };
    pub const Cylinder = struct {
        world_cylinder: sdk.math.Cylinder,
        screen_shape: ?ScreenShape,
        screen_center: ?sdk.math.Vec2,
        screen_half_size: ?sdk.math.Vec2,
        color: sdk.math.Vec4,
        thickness: f32,

        pub const ScreenShape = enum { rectangle, ellipse };
    };

    pub fn begin(self: *Self, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
    }

    pub fn end(self: *Self) void {
        const allocator = self.allocator orelse return;
        self.list.clearAndFree(allocator);
        self.allocator = null;
    }

    pub fn clear(self: *Self) void {
        const allocator = self.allocator orelse return;
        self.list.clearAndFree(allocator);
    }

    pub fn append(self: *Self, shape: Shape) void {
        const allocator = self.allocator orelse return;
        self.list.append(allocator, shape) catch @panic("Failed to append a testing shape.");
    }

    pub fn getAll(self: *const Self) []const Shape {
        return self.list.items;
    }

    pub fn findPointWithWorldPosition(self: *const Self, position: sdk.math.Vec3, tolerance: f32) ?*const Point {
        for (self.list.items) |*shape| {
            switch (shape.*) {
                .point => |*point| {
                    if (point.world_position.equals(position, tolerance)) {
                        return point;
                    }
                },
                else => continue,
            }
        }
        return null;
    }

    pub fn findLineWithWorldPoints(
        self: *const Self,
        point_1: sdk.math.Vec3,
        point_2: sdk.math.Vec3,
        tolerance: f32,
    ) ?*const Line {
        for (self.list.items) |*shape| {
            switch (shape.*) {
                .line => |*line| {
                    const l = &line.world_line;
                    const t = tolerance;
                    const is_equal = (l.point_1.equals(point_1, t) and l.point_2.equals(point_2, t)) or
                        (l.point_1.equals(point_2, t) and l.point_2.equals(point_1, t));
                    if (is_equal) {
                        return line;
                    }
                },
                else => continue,
            }
        }
        return null;
    }

    pub fn findLineWithScreenPoints(
        self: *const Self,
        point_1: sdk.math.Vec2,
        point_2: sdk.math.Vec2,
        tolerance: f32,
    ) ?*const Line {
        for (self.list.items) |*shape| {
            switch (shape.*) {
                .line => |*line| {
                    const l = if (line.screen_line) |*l| l else continue;
                    const t = tolerance;
                    const is_equal = (l.point_1.equals(point_1, t) and l.point_2.equals(point_2, t)) or
                        (l.point_1.equals(point_2, t) and l.point_2.equals(point_1, t));
                    if (is_equal) {
                        return line;
                    }
                },
                else => continue,
            }
        }
        return null;
    }

    pub fn findOutlineWithWorldPoints(
        self: *const Self,
        point_1: sdk.math.Vec3,
        point_2: sdk.math.Vec3,
        tolerance: f32,
    ) ?*const Line {
        for (self.list.items) |*shape| {
            switch (shape.*) {
                .outline => |*outline| {
                    const l = &outline.world_line;
                    const t = tolerance;
                    const is_equal = (l.point_1.equals(point_1, t) and l.point_2.equals(point_2, t)) or
                        (l.point_1.equals(point_2, t) and l.point_2.equals(point_1, t));
                    if (is_equal) {
                        return outline;
                    }
                },
                else => continue,
            }
        }
        return null;
    }

    pub fn findSphereWithWorldCenter(
        self: *const Self,
        center: sdk.math.Vec3,
        tolerance: f32,
    ) ?*const Sphere {
        for (self.list.items) |*shape| {
            switch (shape.*) {
                .sphere => |*sphere| {
                    const s = &sphere.world_sphere;
                    if (s.center.equals(center, tolerance)) {
                        return sphere;
                    }
                },
                else => continue,
            }
        }
        return null;
    }

    pub fn findCylinderWithWorldCenter(
        self: *const Self,
        center: sdk.math.Vec3,
        tolerance: f32,
    ) ?*const Cylinder {
        for (self.list.items) |*shape| {
            switch (shape.*) {
                .cylinder => |*cylinder| {
                    const c = &cylinder.world_cylinder;
                    if (c.center.equals(center, tolerance)) {
                        return cylinder;
                    }
                },
                else => continue,
            }
        }
        return null;
    }
};

const testing = std.testing;

test "should put correct shapes into testing shapes when 2D shapes" {
    const Test = struct {
        fn guiFunction(_: sdk.ui.TestContext) !void {
            testing_shapes.clear();

            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();

            const matrix = sdk.math.Mat4.identity
                .scale(.fromArray(.{ 1, 2, 3 }))
                .translate(.fromArray(.{ 4, 5, 6 }));
            const inverse_matrix = matrix.inverse() orelse return error.MatrixInverseFailed;

            var shapes = Shapes{ ._2d = .{
                .direction = .front,
                .matrix = matrix,
                .inverse_matrix = inverse_matrix,
                .thickness_scale = 2,
            } };
            shapes.drawPoint(
                .fromArray(.{ 1, 2, 3 }),
                .fromArray(.{ 4, 5, 6, 7 }),
                8,
            );
            shapes.drawLine(
                .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
                .fromArray(.{ 7, 8, 9, 10 }),
                11,
                0,
            );
            shapes.drawOutline(
                .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
                .fromArray(.{ 7, 8, 9, 10 }),
                11,
                0,
            );
            shapes.drawSphere(
                .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4 },
                .fromArray(.{ 5, 6, 7, 8 }),
                9,
            );
            shapes.drawCylinder(
                .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4, .half_height = 5 },
                .fromArray(.{ 6, 7, 8, 9 }),
                10,
            );
            shapes._2d.direction = .top;
            shapes.drawCylinder(
                .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4, .half_height = 5 },
                .fromArray(.{ 6, 7, 8, 9 }),
                10,
            );
        }

        fn testFunction(_: sdk.ui.TestContext) !void {
            const items = testing_shapes.getAll();
            try testing.expectEqual(items.len, 6);
            try testing.expectEqual(TestingShapes.Shape{ .point = .{
                .world_position = .fromArray(.{ 1, 2, 3 }),
                .screen_position = .fromArray(.{ 5, 9 }),
                .color = .fromArray(.{ 4, 5, 6, 7 }),
                .thickness = 16,
            } }, items[0]);
            try testing.expectEqual(TestingShapes.Shape{ .line = .{
                .world_line = .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
                .screen_line = .{ .point_1 = .fromArray(.{ 5, 9 }), .point_2 = .fromArray(.{ 8, 15 }) },
                .color = .fromArray(.{ 7, 8, 9, 10 }),
                .thickness = 22,
            } }, items[1]);
            try testing.expectEqual(TestingShapes.Shape{ .outline = .{
                .world_line = .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
                .screen_line = .{ .point_1 = .fromArray(.{ 5, 9 }), .point_2 = .fromArray(.{ 8, 15 }) },
                .color = .fromArray(.{ 7, 8, 9, 10 }),
                .thickness = 22,
            } }, items[2]);
            try testing.expectEqual(TestingShapes.Shape{ .sphere = .{
                .world_sphere = .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4 },
                .screen_center = .fromArray(.{ 5, 9 }),
                .screen_half_size = .fromArray(.{ 4, 8 }),
                .color = .fromArray(.{ 5, 6, 7, 8 }),
                .thickness = 18,
            } }, items[3]);
            try testing.expectEqual(TestingShapes.Shape{ .cylinder = .{
                .world_cylinder = .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4, .half_height = 5 },
                .screen_shape = .rectangle,
                .screen_center = .fromArray(.{ 5, 9 }),
                .screen_half_size = .fromArray(.{ 4, 10 }),
                .color = .fromArray(.{ 6, 7, 8, 9 }),
                .thickness = 20,
            } }, items[4]);
            try testing.expectEqual(TestingShapes.Shape{ .cylinder = .{
                .world_cylinder = .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4, .half_height = 5 },
                .screen_shape = .ellipse,
                .screen_center = .fromArray(.{ 5, 9 }),
                .screen_half_size = .fromArray(.{ 4, 8 }),
                .color = .fromArray(.{ 6, 7, 8, 9 }),
                .thickness = 20,
            } }, items[5]);
        }
    };
    testing_shapes.begin(testing.allocator);
    defer testing_shapes.end();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should put correct shapes into testing shapes when 3D shapes" {
    testing_shapes.begin(testing.allocator);
    defer testing_shapes.end();

    var renderer = rendering.Shapes.init(testing.allocator);
    defer renderer.deinit();

    const shapes = Shapes{ ._3d = .{
        .renderer = &renderer,
        .thickness_scale = 2,
    } };
    shapes.drawPoint(
        .fromArray(.{ 1, 2, 3 }),
        .fromArray(.{ 4, 5, 6, 7 }),
        8,
    );
    shapes.drawLine(
        .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
        .fromArray(.{ 7, 8, 9, 10 }),
        11,
        0,
    );
    shapes.drawOutline(
        .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
        .fromArray(.{ 7, 8, 9, 10 }),
        11,
        0,
    );
    shapes.drawSphere(
        .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4 },
        .fromArray(.{ 5, 6, 7, 8 }),
        9,
    );
    shapes.drawCylinder(
        .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4, .half_height = 5 },
        .fromArray(.{ 6, 7, 8, 9 }),
        10,
    );

    const items = testing_shapes.getAll();
    try testing.expectEqual(items.len, 5);
    try testing.expectEqual(TestingShapes.Shape{ .point = .{
        .world_position = .fromArray(.{ 1, 2, 3 }),
        .screen_position = null,
        .color = .fromArray(.{ 4, 5, 6, 7 }),
        .thickness = 16,
    } }, items[0]);
    try testing.expectEqual(TestingShapes.Shape{ .line = .{
        .world_line = .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
        .screen_line = null,
        .color = .fromArray(.{ 7, 8, 9, 10 }),
        .thickness = 22,
    } }, items[1]);
    try testing.expectEqual(TestingShapes.Shape{ .outline = .{
        .world_line = .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
        .screen_line = null,
        .color = .fromArray(.{ 7, 8, 9, 10 }),
        .thickness = 22,
    } }, items[2]);
    try testing.expectEqual(TestingShapes.Shape{ .sphere = .{
        .world_sphere = .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4 },
        .screen_center = null,
        .screen_half_size = null,
        .color = .fromArray(.{ 5, 6, 7, 8 }),
        .thickness = 18,
    } }, items[3]);
    try testing.expectEqual(TestingShapes.Shape{ .cylinder = .{
        .world_cylinder = .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4, .half_height = 5 },
        .screen_shape = null,
        .screen_center = null,
        .screen_half_size = null,
        .color = .fromArray(.{ 6, 7, 8, 9 }),
        .thickness = 20,
    } }, items[4]);
}

test "should put correct shapes into testing shapes when void shapes" {
    testing_shapes.begin(testing.allocator);
    defer testing_shapes.end();

    const shapes = Shapes{ ._void = .{} };
    shapes.drawPoint(
        .fromArray(.{ 1, 2, 3 }),
        .fromArray(.{ 4, 5, 6, 7 }),
        8,
    );
    shapes.drawLine(
        .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
        .fromArray(.{ 7, 8, 9, 10 }),
        11,
        0,
    );
    shapes.drawOutline(
        .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
        .fromArray(.{ 7, 8, 9, 10 }),
        11,
        0,
    );
    shapes.drawSphere(
        .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4 },
        .fromArray(.{ 5, 6, 7, 8 }),
        9,
    );
    shapes.drawCylinder(
        .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4, .half_height = 5 },
        .fromArray(.{ 6, 7, 8, 9 }),
        10,
    );

    const items = testing_shapes.getAll();
    try testing.expectEqual(items.len, 5);
    try testing.expectEqual(TestingShapes.Shape{ .point = .{
        .world_position = .fromArray(.{ 1, 2, 3 }),
        .screen_position = null,
        .color = .fromArray(.{ 4, 5, 6, 7 }),
        .thickness = 8,
    } }, items[0]);
    try testing.expectEqual(TestingShapes.Shape{ .line = .{
        .world_line = .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
        .screen_line = null,
        .color = .fromArray(.{ 7, 8, 9, 10 }),
        .thickness = 11,
    } }, items[1]);
    try testing.expectEqual(TestingShapes.Shape{ .outline = .{
        .world_line = .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
        .screen_line = null,
        .color = .fromArray(.{ 7, 8, 9, 10 }),
        .thickness = 11,
    } }, items[2]);
    try testing.expectEqual(TestingShapes.Shape{ .sphere = .{
        .world_sphere = .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4 },
        .screen_center = null,
        .screen_half_size = null,
        .color = .fromArray(.{ 5, 6, 7, 8 }),
        .thickness = 9,
    } }, items[3]);
    try testing.expectEqual(TestingShapes.Shape{ .cylinder = .{
        .world_cylinder = .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4, .half_height = 5 },
        .screen_shape = null,
        .screen_center = null,
        .screen_half_size = null,
        .color = .fromArray(.{ 6, 7, 8, 9 }),
        .thickness = 10,
    } }, items[4]);
}
