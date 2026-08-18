const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const build_info = @import("build_info");

const source_code = @embedFile("lines.hlsl");

pub fn Lines(comptime rendering_api: build_info.RenderingApi) type {
    const dx = switch (rendering_api) {
        .dx11 => sdk.dx11,
        .dx12 => sdk.dx12,
    };
    return struct {
        allocator: std.mem.Allocator,
        visible_shader: ?Shader,
        occluded_shader: ?Shader,
        current_index: Index,
        vertices: std.ArrayList(Vertex),
        indices: std.ArrayList(Index),

        const Self = @This();
        const Vertex = extern struct {
            start: sdk.math.Vec3,
            thickness: f32,
            end: sdk.math.Vec3,
            t: f16,
            depth_factor: f16,
            color: sdk.math.Vec4,
        };
        const Index = u16;
        const Constants = extern struct {
            world_to_clip: sdk.math.Mat4,
            clip_to_world: sdk.math.Mat4,
            viewport_size: sdk.math.Vec2,
            anti_aliasing: f32,
            global_alpha: f32,
        };
        const Shader = dx.Shader(Vertex, Index, Constants);

        pub fn init(allocator: std.mem.Allocator, context_maybe: ?*const dx.Context) Self {
            const visible_shader = if (context_maybe) |context| Shader.init(context, &.{
                .source_code = source_code,
                .depth = .{
                    .enable_testing = true,
                    .testing_function = .greater_equal,
                    .enable_writing = true,
                },
            }) catch |err| block: {
                sdk.misc.error_context.append("Failed to initialize visible line rendering shader.", .{});
                sdk.misc.error_context.logError(err);
                break :block null;
            } else null;
            const occluded_shader = if (context_maybe) |context| Shader.init(context, &.{
                .source_code = source_code,
                .depth = .{
                    .enable_testing = true,
                    .testing_function = .less,
                    .enable_writing = false,
                },
            }) catch |err| block: {
                sdk.misc.error_context.append("Failed to initialize occluded line rendering shader.", .{});
                sdk.misc.error_context.logError(err);
                break :block null;
            } else null;
            return .{
                .allocator = allocator,
                .visible_shader = visible_shader,
                .occluded_shader = occluded_shader,
                .current_index = 0,
                .vertices = .empty,
                .indices = .empty,
            };
        }

        pub fn deinit(self: *Self, context_maybe: ?*const dx.Context) void {
            self.indices.deinit(self.allocator);
            self.vertices.deinit(self.allocator);
            if (context_maybe) |context| {
                if (self.occluded_shader) |*shader| {
                    shader.deinit(context);
                }
                if (self.visible_shader) |*shader| {
                    shader.deinit(context);
                }
            }
        }

        pub fn add(
            self: *Self,
            line: sdk.math.LineSegment3,
            color: sdk.math.Vec4,
            thickness: f32,
            depth_factor: f16,
        ) void {
            self.vertices.appendSlice(self.allocator, &.{
                .{
                    .start = line.point_1,
                    .end = line.point_2,
                    .color = color,
                    .thickness = thickness,
                    .t = 0,
                    .depth_factor = depth_factor,
                },
                .{
                    .start = line.point_1,
                    .end = line.point_2,
                    .color = color,
                    .thickness = -thickness,
                    .t = 0,
                    .depth_factor = depth_factor,
                },
                .{
                    .start = line.point_1,
                    .end = line.point_2,
                    .color = color,
                    .thickness = thickness,
                    .t = 1,
                    .depth_factor = depth_factor,
                },
                .{
                    .start = line.point_1,
                    .end = line.point_2,
                    .color = color,
                    .thickness = -thickness,
                    .t = 1,
                    .depth_factor = depth_factor,
                },
            }) catch |err| {
                sdk.misc.error_context.append("Failed to add vertices to vertex to list.", .{});
                sdk.misc.error_context.append("Failed to add a line to line renderer.", .{});
                sdk.misc.error_context.logError(err);
                return;
            };
            self.indices.appendSlice(self.allocator, &.{
                self.current_index,
                self.current_index + 1,
                self.current_index + 2,
                self.current_index + 1,
                self.current_index + 2,
                self.current_index + 3,
            }) catch |err| {
                sdk.misc.error_context.append("Failed to add indices to index to list.", .{});
                sdk.misc.error_context.append("Failed to add a line to line renderer.", .{});
                sdk.misc.error_context.logError(err);
                return;
            };
            self.current_index += 4;
        }

        pub fn clear(self: *Self) void {
            self.vertices.clearRetainingCapacity();
            self.indices.clearRetainingCapacity();
            self.current_index = 0;
        }

        pub fn render(
            self: *Self,
            context: *const dx.Context,
            buffer_context: *const dx.BufferContext,
            camera_position: sdk.math.Vec3,
            world_to_clip: sdk.math.Mat4,
            clip_to_world: sdk.math.Mat4,
            occluded_alpha: f32,
            anti_aliasing: f32,
            is_depth_enabled: bool,
        ) void {
            const back_buffer_size = context.getBackBufferSize() catch return;
            const viewport_size = sdk.math.Vec2.fromArray(.{
                @floatFromInt(back_buffer_size.x()),
                @floatFromInt(back_buffer_size.y()),
            });
            if (is_depth_enabled) {
                self.sortByDepth(camera_position);
            }
            if (is_depth_enabled and occluded_alpha > 0) {
                if (self.occluded_shader) |*shader| {
                    drawShader(
                        context,
                        buffer_context,
                        shader,
                        self.vertices.items,
                        self.indices.items,
                        &.{
                            .world_to_clip = world_to_clip,
                            .clip_to_world = clip_to_world,
                            .viewport_size = viewport_size,
                            .anti_aliasing = anti_aliasing,
                            .global_alpha = occluded_alpha,
                        },
                    ) catch |err| {
                        sdk.misc.error_context.append("Failed to render occluded lines.", .{});
                        sdk.misc.error_context.logError(err);
                    };
                }
            }
            if (self.visible_shader) |*shader| {
                drawShader(
                    context,
                    buffer_context,
                    shader,
                    self.vertices.items,
                    self.indices.items,
                    &.{
                        .world_to_clip = world_to_clip,
                        .clip_to_world = clip_to_world,
                        .viewport_size = viewport_size,
                        .anti_aliasing = anti_aliasing,
                        .global_alpha = 1,
                    },
                ) catch |err| {
                    sdk.misc.error_context.append("Failed to render visible lines.", .{});
                    sdk.misc.error_context.logError(err);
                };
            }
        }

        fn drawShader(
            context: *const dx.Context,
            buffer_context: *const dx.BufferContext,
            shader: *Shader,
            vetices: []const Vertex,
            indices: []const Index,
            constants: *const Constants,
        ) !void {
            shader.setVertices(context, vetices) catch |err| {
                sdk.misc.error_context.append("Failed to set shader vertices.", .{});
                return err;
            };
            shader.setIndices(context, indices) catch |err| {
                sdk.misc.error_context.append("Failed to set shader indices.", .{});
                return err;
            };
            shader.setConstants(context, constants) catch |err| {
                sdk.misc.error_context.append("Failed to set shader constants.", .{});
                return err;
            };
            shader.draw(context, buffer_context) catch |err| {
                sdk.misc.error_context.append("Failed to execute shader draw.", .{});
                return err;
            };
        }

        fn sortByDepth(self: *Self, camera_position: sdk.math.Vec3) void {
            const Context = struct {
                vertices: []const Vertex,
                camera_position: sdk.math.Vec3,
            };
            const group6 = struct {
                fn call(indices: []Index) [][6]Index {
                    std.debug.assert(indices.len % 6 == 0);
                    const ptr: [*][6]Index = @ptrCast(indices.ptr);
                    return ptr[0 .. indices.len / 6];
                }
            }.call;
            const lessThanFn = struct {
                fn call(context: Context, lhs: [6]Index, rhs: [6]Index) bool {
                    const lhs_vertex = context.vertices[lhs[0]];
                    const rhs_vertex = context.vertices[rhs[0]];
                    const lhs_depth = lhs_vertex.start.add(lhs_vertex.end).scale(0.5)
                        .distanceSquaredTo(context.camera_position);
                    const rhs_depth = rhs_vertex.start.add(rhs_vertex.end).scale(0.5)
                        .distanceSquaredTo(context.camera_position);
                    if (lhs_depth != rhs_depth) {
                        return lhs_depth > rhs_depth;
                    } else {
                        return lhs_vertex.depth_factor < rhs_vertex.depth_factor;
                    }
                }
            }.call;
            std.mem.sort(
                [6]Index,
                group6(self.indices.items),
                Context{
                    .vertices = self.vertices.items,
                    .camera_position = camera_position,
                },
                lessThanFn,
            );
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

    var lines = Lines(.dx11).init(testing.allocator, &context);
    defer lines.deinit(&context);

    for (0..10) |index| {
        lines.clear();
        lines.add(
            .{ .point_1 = .zero, .point_2 = sdk.math.Vec3.plus_x.scale(@floatFromInt(index + 1)) },
            .fromArray(.{ 1, 0, 0, 1 }),
            10,
            1,
        );
        lines.add(
            .{ .point_1 = .zero, .point_2 = sdk.math.Vec3.plus_y.scale(@floatFromInt(index + 1)) },
            .fromArray(.{ 0, 1, 0, 1 }),
            10,
            0,
        );
        lines.add(
            .{ .point_1 = .zero, .point_2 = sdk.math.Vec3.plus_z.scale(@floatFromInt(index + 1)) },
            .fromArray(.{ 0, 0, 1, 1 }),
            10,
            -1,
        );

        const camera_position = sdk.math.Vec3.fromArray(.{ @floatFromInt(index), 1, 1 });
        const world_to_clip = sdk.math.Mat4.identity
            .lookAt(camera_position, .zero, .plus_z)
            .perspective(0.25 * std.math.pi, 16.0 / 9.0, 1, 1000);
        const clip_to_world = world_to_clip.inverse() orelse return error.InverseFailed;
        const buffer_context = try context.beforeRender();
        lines.render(&context, buffer_context, camera_position, world_to_clip, clip_to_world, 0.1, 1.8, true);
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

    var lines = Lines(.dx12).init(testing.allocator, &context);
    defer lines.deinit(&context);

    for (0..10) |index| {
        lines.clear();
        lines.add(
            .{ .point_1 = .zero, .point_2 = sdk.math.Vec3.plus_x.scale(@floatFromInt(index + 1)) },
            .fromArray(.{ 1, 0, 0, 1 }),
            10,
            1,
        );
        lines.add(
            .{ .point_1 = .zero, .point_2 = sdk.math.Vec3.plus_y.scale(@floatFromInt(index + 1)) },
            .fromArray(.{ 0, 1, 0, 1 }),
            10,
            0,
        );
        lines.add(
            .{ .point_1 = .zero, .point_2 = sdk.math.Vec3.plus_z.scale(@floatFromInt(index + 1)) },
            .fromArray(.{ 0, 0, 1, 1 }),
            10,
            -1,
        );

        const camera_position = sdk.math.Vec3.fromArray(.{ @floatFromInt(index), 1, 1 });
        const world_to_clip = sdk.math.Mat4.identity
            .lookAt(camera_position, .zero, .plus_z)
            .perspective(0.25 * std.math.pi, 16.0 / 9.0, 1, 1000);
        const clip_to_world = world_to_clip.inverse() orelse return error.InverseFailed;
        const buffer_context = try context.beforeRender();
        lines.render(&context, buffer_context, camera_position, world_to_clip, clip_to_world, 0.1, 1.8, true);
        try context.afterRender(buffer_context);
        try testing_context.present();
    }
}
