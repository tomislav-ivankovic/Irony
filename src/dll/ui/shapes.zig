const std = @import("std");
const builtin = @import("builtin");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const ui = @import("../ui/root.zig");

pub fn drawPoint(position: sdk.math.Vec3, color: sdk.math.Vec4, thickness: f32, matrix: sdk.math.Mat4) void {
    const draw_list = imgui.igGetWindowDrawList();
    const transformed = position.pointTransform(matrix).swizzle("xy");
    const u32_color = imgui.igGetColorU32_Vec4(color.toImVec());

    imgui.ImDrawList_AddCircleFilled(draw_list, transformed.toImVec(), 0.5 * thickness, u32_color, 16);

    if (builtin.is_test) {
        testing_shapes.append(.{ .point = .{
            .world_position = position,
            .screen_position = transformed,
            .color = color,
            .thickness = thickness,
        } });
    }
}

pub fn drawLine(line: sdk.math.LineSegment3, color: sdk.math.Vec4, thickness: f32, matrix: sdk.math.Mat4) void {
    const draw_list = imgui.igGetWindowDrawList();
    const point_1 = line.point_1.pointTransform(matrix).swizzle("xy");
    const point_2 = line.point_2.pointTransform(matrix).swizzle("xy");
    const u32_color = imgui.igGetColorU32_Vec4(color.toImVec());

    imgui.ImDrawList_AddLine(draw_list, point_1.toImVec(), point_2.toImVec(), u32_color, thickness);

    if (builtin.is_test) {
        testing_shapes.append(.{ .line = .{
            .world_line = line,
            .screen_line = .{ .point_1 = point_1, .point_2 = point_2 },
            .color = color,
            .thickness = thickness,
        } });
    }
}

pub fn drawSphere(
    sphere: sdk.math.Sphere,
    color: sdk.math.Vec4,
    thickness: f32,
    matrix: sdk.math.Mat4,
    inverse_matrix: sdk.math.Mat4,
) void {
    const world_right = sdk.math.Vec3.plus_x.directionTransform(inverse_matrix).normalize();
    const world_up = sdk.math.Vec3.plus_y.directionTransform(inverse_matrix).normalize();

    const draw_list = imgui.igGetWindowDrawList();
    const center = sphere.center.pointTransform(matrix).swizzle("xy");
    const radius = world_up.add(world_right).scale(sphere.radius).directionTransform(matrix).swizzle("xy");
    const u32_color = imgui.igGetColorU32_Vec4(color.toImVec());

    imgui.ImDrawList_AddEllipse(draw_list, center.toImVec(), radius.toImVec(), u32_color, 0, 32, thickness);

    if (builtin.is_test) {
        testing_shapes.append(.{ .sphere = .{
            .world_sphere = sphere,
            .screen_center = center,
            .screen_half_size = radius,
            .color = color,
            .thickness = thickness,
        } });
    }
}

pub fn drawCylinder(
    cylinder: sdk.math.Cylinder,
    color: sdk.math.Vec4,
    thickness: f32,
    direction: ui.ViewDirection,
    matrix: sdk.math.Mat4,
    inverse_matrix: sdk.math.Mat4,
) void {
    const world_right = sdk.math.Vec3.plus_x.directionTransform(inverse_matrix).normalize();
    const world_up = sdk.math.Vec3.plus_y.directionTransform(inverse_matrix).normalize();

    const draw_list = imgui.igGetWindowDrawList();
    const center = cylinder.center.pointTransform(matrix).swizzle("xy");
    const u32_color = imgui.igGetColorU32_Vec4(color.toImVec());

    switch (direction) {
        .front, .side => {
            const half_size = world_up.scale(cylinder.half_height)
                .add(world_right.scale(cylinder.radius))
                .directionTransform(matrix)
                .swizzle("xy");
            const min = center.subtract(half_size).toImVec();
            const max = center.add(half_size).toImVec();
            imgui.ImDrawList_AddRect(draw_list, min, max, u32_color, 0, 0, thickness);

            if (builtin.is_test) {
                testing_shapes.append(.{ .cylinder = .{
                    .world_cylinder = cylinder,
                    .screen_shape = .rectangle,
                    .screen_center = center,
                    .screen_half_size = half_size,
                    .color = color,
                    .thickness = thickness,
                } });
            }
        },
        .top => {
            const im_center = center.toImVec();
            const radius = world_up
                .add(world_right)
                .scale(cylinder.radius)
                .directionTransform(matrix)
                .swizzle("xy");
            imgui.ImDrawList_AddEllipse(draw_list, im_center, radius.toImVec(), u32_color, 0, 32, thickness);

            if (builtin.is_test) {
                testing_shapes.append(.{ .cylinder = .{
                    .world_cylinder = cylinder,
                    .screen_shape = .ellipse,
                    .screen_center = center,
                    .screen_half_size = radius,
                    .color = color,
                    .thickness = thickness,
                } });
            }
        },
    }
}

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

    pub const Shape = union(enum) {
        point: Point,
        line: Line,
        sphere: Sphere,
        cylinder: Cylinder,
    };
    pub const Point = struct {
        world_position: sdk.math.Vec3,
        screen_position: sdk.math.Vec2,
        color: sdk.math.Vec4,
        thickness: f32,
    };
    pub const Line = struct {
        world_line: sdk.math.LineSegment3,
        screen_line: sdk.math.LineSegment2,
        color: sdk.math.Vec4,
        thickness: f32,
    };
    pub const Sphere = struct {
        world_sphere: sdk.math.Sphere,
        screen_center: sdk.math.Vec2,
        screen_half_size: sdk.math.Vec2,
        color: sdk.math.Vec4,
        thickness: f32,
    };
    pub const Cylinder = struct {
        world_cylinder: sdk.math.Cylinder,
        screen_shape: ScreenShape,
        screen_center: sdk.math.Vec2,
        screen_half_size: sdk.math.Vec2,
        color: sdk.math.Vec4,
        thickness: f32,

        pub const ScreenShape = enum { rectangle, ellipse };
    };
};

const testing = std.testing;

test "should put correct shapes into testing shapes" {
    const Test = struct {
        fn guiFunction(_: sdk.ui.TestContext) !void {
            testing_shapes.clear();

            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();

            const matrix = sdk.math.Mat4.identity
                .scale(.fromArray(.{ 1, 2, 3 }))
                .translate(.fromArray(.{ 4, 5, 6 }));
            const inverse_matrix = matrix.inverse() orelse return error.MatrixInverseFailed;

            drawPoint(
                .fromArray(.{ 1, 2, 3 }),
                .fromArray(.{ 4, 5, 6, 7 }),
                8,
                matrix,
            );
            drawLine(
                .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
                .fromArray(.{ 7, 8, 9, 10 }),
                11,
                matrix,
            );
            drawSphere(
                .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4 },
                .fromArray(.{ 5, 6, 7, 8 }),
                9,
                matrix,
                inverse_matrix,
            );
            drawCylinder(
                .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4, .half_height = 5 },
                .fromArray(.{ 6, 7, 8, 9 }),
                10,
                .front,
                matrix,
                inverse_matrix,
            );
            drawCylinder(
                .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4, .half_height = 5 },
                .fromArray(.{ 6, 7, 8, 9 }),
                10,
                .top,
                matrix,
                inverse_matrix,
            );
        }

        fn testFunction(_: sdk.ui.TestContext) !void {
            const items = testing_shapes.getAll();
            try testing.expectEqual(items.len, 5);
            try testing.expectEqual(items[0], TestingShapes.Shape{ .point = .{
                .world_position = .fromArray(.{ 1, 2, 3 }),
                .screen_position = .fromArray(.{ 5, 9 }),
                .color = .fromArray(.{ 4, 5, 6, 7 }),
                .thickness = 8,
            } });
            try testing.expectEqual(items[1], TestingShapes.Shape{ .line = .{
                .world_line = .{ .point_1 = .fromArray(.{ 1, 2, 3 }), .point_2 = .fromArray(.{ 4, 5, 6 }) },
                .screen_line = .{ .point_1 = .fromArray(.{ 5, 9 }), .point_2 = .fromArray(.{ 8, 15 }) },
                .color = .fromArray(.{ 7, 8, 9, 10 }),
                .thickness = 11,
            } });
            try testing.expectEqual(items[2], TestingShapes.Shape{ .sphere = .{
                .world_sphere = .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4 },
                .screen_center = .fromArray(.{ 5, 9 }),
                .screen_half_size = .fromArray(.{ 4, 8 }),
                .color = .fromArray(.{ 5, 6, 7, 8 }),
                .thickness = 9,
            } });
            try testing.expectEqual(items[3], TestingShapes.Shape{ .cylinder = .{
                .world_cylinder = .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4, .half_height = 5 },
                .screen_shape = .rectangle,
                .screen_center = .fromArray(.{ 5, 9 }),
                .screen_half_size = .fromArray(.{ 4, 10 }),
                .color = .fromArray(.{ 6, 7, 8, 9 }),
                .thickness = 10,
            } });
            try testing.expectEqual(items[4], TestingShapes.Shape{ .cylinder = .{
                .world_cylinder = .{ .center = .fromArray(.{ 1, 2, 3 }), .radius = 4, .half_height = 5 },
                .screen_shape = .ellipse,
                .screen_center = .fromArray(.{ 5, 9 }),
                .screen_half_size = .fromArray(.{ 4, 8 }),
                .color = .fromArray(.{ 6, 7, 8, 9 }),
                .thickness = 10,
            } });
        }
    };
    testing_shapes.begin(testing.allocator);
    defer testing_shapes.end();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
