const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const build_info = @import("build_info");

const source_code = @embedFile("triangles.hlsl");

pub fn Triangles(comptime rendering_api: build_info.RenderingApi) type {
    const dx = switch (rendering_api) {
        .dx11 => sdk.dx11,
        .dx12 => sdk.dx12,
    };
    return struct {
        allocator: std.mem.Allocator,
        shader: ?Shader,
        vertices: std.ArrayList(Vertex),
        indices: std.ArrayList(Index),

        const Self = @This();
        const Vertex = extern struct {
            position: sdk.math.Vec3,
            _padding: f32 = 0.0,
            color: sdk.math.Vec4,
        };
        const Index = u16;
        const Constants = extern struct {
            world_to_clip: sdk.math.Mat4,
        };
        const Shader = dx.Shader(Vertex, Index, Constants);

        pub fn init(allocator: std.mem.Allocator, context_maybe: ?*const dx.Context) Self {
            const shader = if (context_maybe) |context| Shader.init(context, &.{
                .source_code = source_code,
                .blend = .{ .mode = .{ .shared = .{
                    .src = .src_alpha,
                    .dest = .one,
                    .op = .add,
                    .src_alpha = .src_alpha,
                    .dest_alpha = .one,
                    .op_alpha = .add,
                } } },
                .depth = .{
                    .enable_testing = true,
                    .testing_function = .greater_equal,
                    .enable_writing = false,
                },
            }) catch |err| block: {
                sdk.misc.error_context.append("Failed to initialize triangle rendering shader.", .{});
                sdk.misc.error_context.logError(err);
                break :block null;
            } else null;
            return .{
                .allocator = allocator,
                .shader = shader,
                .vertices = .empty,
                .indices = .empty,
            };
        }

        pub fn deinit(self: *Self, context_maybe: ?*const dx.Context) void {
            self.indices.deinit(self.allocator);
            self.vertices.deinit(self.allocator);
            if (context_maybe) |context| {
                if (self.shader) |*shader| {
                    shader.deinit(context);
                }
            }
        }

        pub fn addVertex(self: *Self, position: sdk.math.Vec3, color: sdk.math.Vec4) void {
            self.vertices.append(self.allocator, .{ .position = position, .color = color }) catch |err| {
                sdk.misc.error_context.append("Failed to append vertex to vertex list.", .{});
                sdk.misc.error_context.append("Failed to add a vertex to triangle renderer.", .{});
                sdk.misc.error_context.logError(err);
            };
        }

        pub fn addTriangle(self: *Self, index_1: Index, index_2: Index, index_3: Index) void {
            self.indices.appendSlice(self.allocator, &.{ index_1, index_2, index_3 }) catch |err| {
                sdk.misc.error_context.append("Failed to append indices to index list.", .{});
                sdk.misc.error_context.append("Failed to add a triangle to triangle renderer.", .{});
                sdk.misc.error_context.logError(err);
            };
        }

        pub fn getNextIndex(self: *const Self) ?Index {
            return std.math.cast(Index, self.vertices.items.len);
        }

        pub fn clear(self: *Self) void {
            self.vertices.clearRetainingCapacity();
            self.indices.clearRetainingCapacity();
        }

        pub fn render(
            self: *Self,
            context: *const dx.Context,
            buffer_context: *const dx.BufferContext,
            world_to_clip: sdk.math.Mat4,
        ) void {
            const shader = if (self.shader) |*s| s else return;
            shader.setVertices(context, self.vertices.items) catch |err| {
                sdk.misc.error_context.append("Failed to set shader vertices.", .{});
                sdk.misc.error_context.append("Failed to render triangles.", .{});
                sdk.misc.error_context.logError(err);
                return;
            };
            shader.setIndices(context, self.indices.items) catch |err| {
                sdk.misc.error_context.append("Failed to set shader indices.", .{});
                sdk.misc.error_context.append("Failed to render triangles.", .{});
                sdk.misc.error_context.logError(err);
                return;
            };
            shader.setConstants(context, &.{ .world_to_clip = world_to_clip }) catch |err| {
                sdk.misc.error_context.append("Failed to set shader constants.", .{});
                sdk.misc.error_context.append("Failed to render triangles.", .{});
                sdk.misc.error_context.logError(err);
                return;
            };
            shader.draw(context, buffer_context) catch |err| {
                sdk.misc.error_context.append("Failed to execute shader draw.", .{});
                sdk.misc.error_context.append("Failed to render triangles.", .{});
                sdk.misc.error_context.logError(err);
                return;
            };
        }
    };
}

const testing = std.testing;

test "should render without errors when rendering api is DX11" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try sdk.dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try sdk.dx11.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = sdk.dx11.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    var triangles = Triangles(.dx11).init(testing.allocator, &context);
    defer triangles.deinit(&context);

    for (0..10) |index| {
        triangles.clear();

        try testing.expectEqual(0, triangles.getNextIndex());
        triangles.addVertex(.plus_x, .fromArray(.{ 1, 0, 0, 1 }));
        try testing.expectEqual(1, triangles.getNextIndex());
        triangles.addVertex(.plus_y, .fromArray(.{ 0, 1, 0, 1 }));
        try testing.expectEqual(2, triangles.getNextIndex());
        triangles.addVertex(.plus_z, .fromArray(.{ 0, 0, 1, 1 }));
        try testing.expectEqual(3, triangles.getNextIndex());
        triangles.addTriangle(0, 1, 2);

        const camera_position = sdk.math.Vec3.fromArray(.{ @floatFromInt(index), 1, 1 });
        const world_to_clip = sdk.math.Mat4.identity
            .lookAt(camera_position, .zero, .plus_z)
            .perspective(0.25 * std.math.pi, 16.0 / 9.0, 1, 1000);
        const buffer_context = try context.beforeRender();
        triangles.render(&context, buffer_context, world_to_clip);
        try context.afterRender(buffer_context);
        try testing_context.present();
    }
}

test "should render without errors when rendering api is DX12" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try sdk.dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try sdk.dx12.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = sdk.dx12.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    var triangles = Triangles(.dx12).init(testing.allocator, &context);
    defer triangles.deinit(&context);

    for (0..10) |index| {
        triangles.clear();

        try testing.expectEqual(0, triangles.getNextIndex());
        triangles.addVertex(.plus_x, .fromArray(.{ 1, 0, 0, 1 }));
        try testing.expectEqual(1, triangles.getNextIndex());
        triangles.addVertex(.plus_y, .fromArray(.{ 0, 1, 0, 1 }));
        try testing.expectEqual(2, triangles.getNextIndex());
        triangles.addVertex(.plus_z, .fromArray(.{ 0, 0, 1, 1 }));
        try testing.expectEqual(3, triangles.getNextIndex());
        triangles.addTriangle(0, 1, 2);

        const camera_position = sdk.math.Vec3.fromArray(.{ @floatFromInt(index), 1, 1 });
        const world_to_clip = sdk.math.Mat4.identity
            .lookAt(camera_position, .zero, .plus_z)
            .perspective(0.25 * std.math.pi, 16.0 / 9.0, 1, 1000);
        const buffer_context = try context.beforeRender();
        triangles.render(&context, buffer_context, world_to_clip);
        try context.afterRender(buffer_context);
        try testing_context.present();
    }
}
