const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

pub const MoveMeasurer = struct {
    player_1_state: PlayerState = .{},
    player_2_state: PlayerState = .{},

    const Self = @This();
    pub const PlayerState = struct {
        previous_frame_hurt_projection: ?sdk.math.Vec2 = null,
        previous_frame_rotation: ?f32 = null,
        before_move_hurt_projection: ?sdk.math.Vec2 = null,
        before_move_rotation: ?f32 = null,
        min_hit_lines_z: ?f32 = null,
        max_hit_lines_z: ?f32 = null,
        attack_range: ?f32 = null,
        recovery_range: ?f32 = null,
    };

    pub fn measure(self: *Self, frame: *model.Frame) void {
        measureSide(&self.player_1_state, &frame.players[0]);
        measureSide(&self.player_2_state, &frame.players[1]);
    }

    fn measureSide(state: *PlayerState, player: *model.Player) void {
        updateFirstFrameState(state, player);
        updateMoveState(state, player);
        updatePreviousFrameState(state, player);
        player.min_hit_lines_z = state.min_hit_lines_z;
        player.max_hit_lines_z = state.max_hit_lines_z;
        player.attack_range = state.attack_range;
        player.recovery_range = state.recovery_range;
    }

    fn updateFirstFrameState(state: *PlayerState, player: *model.Player) void {
        if (player.move_frame != 1) {
            return;
        }
        state.* = .{
            .before_move_hurt_projection = state.previous_frame_hurt_projection,
            .before_move_rotation = state.previous_frame_rotation,
            .recovery_range = if (state.attack_range != null) state.recovery_range else null,
        };
    }

    fn updateMoveState(state: *PlayerState, player: *model.Player) void {
        const lines = player.hit_lines.asConstSlice();
        for (lines) |*hit_line| {
            if (findHitLineRange(state, hit_line)) |line_range| {
                if (state.attack_range) |state_range| {
                    state.attack_range = @max(state_range, line_range);
                } else {
                    state.attack_range = line_range;
                }
            }
            const line = &hit_line.line;
            const line_min_z = @min(line.point_1.z(), line.point_2.z());
            if (state.min_hit_lines_z) |state_z| {
                state.min_hit_lines_z = @min(state_z, line_min_z);
            } else {
                state.min_hit_lines_z = line_min_z;
            }
            const line_max_z = @max(line.point_1.z(), line.point_2.z());
            if (state.max_hit_lines_z) |state_z| {
                state.max_hit_lines_z = @max(state_z, line_max_z);
            } else {
                state.max_hit_lines_z = line_max_z;
            }
        }
        if (player.move_frame != null and player.move_frame == player.move_total_frames) {
            state.recovery_range = findHurtRange(state, player);
        }
    }

    fn updatePreviousFrameState(state: *PlayerState, player: *model.Player) void {
        state.previous_frame_hurt_projection = findHurtProjection(player);
        state.previous_frame_rotation = player.rotation;
    }

    fn findHitLineRange(state: *const PlayerState, hit_line: *const model.HitLine) ?f32 {
        const hurt_projection = state.before_move_hurt_projection orelse return null;
        const rotation = state.before_move_rotation orelse return null;
        const direction = sdk.math.Vec2.plus_x.rotateZ(rotation);
        const line = &hit_line.line;
        const range_1 = line.point_1.swizzle("xy").subtract(hurt_projection).dot(direction);
        const range_2 = line.point_2.swizzle("xy").subtract(hurt_projection).dot(direction);
        return @max(range_1, range_2);
    }

    fn findHurtRange(state: *const PlayerState, player: *const model.Player) ?f32 {
        const cylinders = player.hurt_cylinders orelse return null;
        const hurt_projection = state.before_move_hurt_projection orelse return null;
        const rotation = state.before_move_rotation orelse return null;
        const attack_range = state.attack_range orelse return null;
        const direction = sdk.math.Vec2.plus_x.rotateZ(rotation);
        var max_projection = -std.math.inf(f32);
        for (&cylinders.values) |*hurt_cylinder| {
            const cylinder = hurt_cylinder.cylinder;
            const center = cylinder.center.swizzle("xy");
            const projection = center.subtract(hurt_projection).dot(direction) + cylinder.radius;
            if (projection > max_projection) {
                max_projection = projection;
            }
        }
        return attack_range - max_projection;
    }

    fn findHurtProjection(player: *model.Player) ?sdk.math.Vec2 {
        const position = if (player.position) |p| p.swizzle("xy") else return null;
        const rotation = player.rotation orelse return null;
        const cylinders = player.hurt_cylinders orelse return null;
        const direction = sdk.math.Vec2.plus_x.rotateZ(rotation);
        var max_projection = -std.math.inf(f32);
        for (&cylinders.values) |*hurt_cylinder| {
            const cylinder = hurt_cylinder.cylinder;
            const center = cylinder.center.swizzle("xy");
            const projection = center.subtract(position).dot(direction) + cylinder.radius;
            if (projection > max_projection) {
                max_projection = projection;
            }
        }
        return position.add(direction.scale(max_projection));
    }
};
