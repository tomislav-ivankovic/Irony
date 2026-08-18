const std = @import("std");
const build_info = @import("build_info");
const sdk = @import("../../sdk/root.zig");
const game = @import("../game/root.zig");
const model = @import("../model/root.zig");
const rendering = @import("root.zig");

const game_id = build_info.game;
const rendering_api = build_info.rendering_api;
const dx = switch (rendering_api) {
    .dx11 => sdk.dx11,
    .dx12 => sdk.dx12,
};

pub const Rendering = struct {
    lines: Lines,
    shapes: rendering.Shapes,

    const Self = @This();
    const Lines = rendering.Lines(rendering_api);

    pub fn init(allocator: std.mem.Allocator, context: ?*const dx.Context) Self {
        const lines = Lines.init(allocator, context);
        const shapes = rendering.Shapes.init(allocator);
        return .{
            .lines = lines,
            .shapes = shapes,
        };
    }

    pub fn deinit(self: *Self, context: ?*const dx.Context) void {
        self.shapes.deinit();
        self.lines.deinit(context);
    }

    pub fn render(
        self: *Self,
        context: *const dx.Context,
        buffer_context: *const dx.BufferContext,
        game_memory: *const game.Memory(game_id),
        settings: *const model.GeneralSettings.Rendering3D,
    ) void {
        defer self.lines.clear();
        defer self.shapes.clear();
        if (!settings.enabled or !isAllowedToRender(game_memory)) {
            return;
        }

        context.setDefaultViewportsAndScissors(buffer_context) catch |err| {
            sdk.misc.error_context.append("Failed to set default viewport and scissors.", .{});
            sdk.misc.error_context.logError(err);
            return;
        };
        const depth_buffer = switch (settings.enable_depth) {
            true => game_memory.depth_buffer.toMutablePointer(),
            false => null,
        };
        var is_depth_enabled = depth_buffer != null;
        context.setDepthBuffer(buffer_context, depth_buffer) catch |err_1| {
            is_depth_enabled = false;
            switch (err_1) {
                error.SizeMismatch => context.setDepthBuffer(buffer_context, null) catch |err_2| {
                    sdk.misc.error_context.append("Failed to unset depth buffer.", .{});
                    sdk.misc.error_context.logError(err_2);
                },
                else => {
                    sdk.misc.error_context.append("Failed to set depth buffer.", .{});
                    sdk.misc.error_context.logError(err_1);
                },
            }
        };

        const camera = game_memory.camera_manager.toConstPointer() orelse return;
        const world_to_clip = calculateWorldToClip(context, camera) orelse return;
        const clip_to_world = world_to_clip.inverse() orelse return;

        self.shapes.render(&self.lines, camera.position.convert());
        self.lines.render(
            context,
            buffer_context,
            camera.position.convert(),
            world_to_clip,
            clip_to_world,
            settings.occluded_alpha,
            settings.anti_aliasing,
            is_depth_enabled,
        );
    }

    fn calculateWorldToClip(context: *const dx.Context, camera: *const game.CameraManager(game_id)) ?sdk.math.Mat4 {
        const position: sdk.math.Vec3 = camera.position.convert();
        const rotation: sdk.math.Vec3 = camera.rotation.convert();
        const pitch = rotation.x();
        const yaw = rotation.y();
        const roll = rotation.z();
        const forward = sdk.math.Vec3.plus_x.rotateX(-roll).rotateY(pitch).rotateZ(yaw);
        const up = sdk.math.Vec3.plus_z.rotateX(-roll).rotateY(pitch).rotateZ(yaw);
        const view = sdk.math.Mat4.fromLookAt(position, position.add(forward), up);

        const aspect_ratio = block: {
            const size = context.getBackBufferSize() catch {
                std.log.warn(
                    "When calculating world to clip matrix, failed to get back buffer size." ++
                        "Defaulting to 16:9 aspect ratio.",
                    .{},
                );
                break :block 16.0 / 9.0;
            };
            if (size.x() <= 0 or size.y() <= 0) {
                std.log.warn(
                    "When calculating world to clip matrix, got invalid back buffer size {}x{}." ++
                        "Defaulting to 16:9 aspect ratio.",
                    .{ size.x(), size.y() },
                );
                break :block 16.0 / 9.0;
            }
            break :block @as(f32, @floatFromInt(size.x())) / @as(f32, @floatFromInt(size.y()));
        };
        const horizontal_fov: f32 = camera.horizontal_fov.convert();
        const vertical_fov = 2 * std.math.atan2(std.math.tan(0.5 * horizontal_fov), aspect_ratio);
        if (vertical_fov < 1 * std.math.rad_per_deg) {
            return null; // Camera not fully initialized.
        }
        const projection = sdk.math.Mat4.fromZInfinitePerspective(vertical_fov, aspect_ratio, 10);

        return view.multiply(projection);
    }

    fn isAllowedToRender(game_memory: *const game.Memory(game_id)) bool {
        const source = game.Capturer(game_id).captureSource(
            game_memory.match.toConstPointer(),
            game_memory.replay_mode.toConstPointer(),
            &game_memory.functions,
        ) orelse return false;
        return switch (source) {
            .practice, .replay_loading, .replay_playback => true,
            .live_game => false,
        };
    }
};
