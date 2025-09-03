const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

pub const MoveMeasurer = struct {
    player_1_state: PlayerState = .{},
    player_2_state: PlayerState = .{},

    const Self = @This();
    pub const PlayerState = struct {
        previous_frame_hurt_cylinders: ?model.HurtCylinders = null,
        range_reference_point: ?sdk.math.Vec2 = null,
        range_reference_rotation: ?f32 = null,
        min_attack_z: ?f32 = null,
        max_attack_z: ?f32 = null,
        attack_range: ?f32 = null,
        recovery_range: ?f32 = null,
    };

    pub fn measure(self: *Self, frame: *model.Frame) void {
        measureSide(&self.player_1_state, &frame.players[0]);
        measureSide(&self.player_2_state, &frame.players[1]);
    }

    fn measureSide(state: *PlayerState, player: *model.Player) void {
        updateReferenceState(state, player);
        updateMoveState(state, player);
        updatePreviousFrameState(state, player);
        player.min_attack_z = state.min_attack_z;
        player.max_attack_z = state.max_attack_z;
        player.attack_range = state.attack_range;
        player.recovery_range = state.recovery_range;
    }

    fn updatePreviousFrameState(state: *PlayerState, player: *model.Player) void {
        state.previous_frame_hurt_cylinders = player.hurt_cylinders;
    }

    fn updateReferenceState(state: *PlayerState, player: *model.Player) void {
        if (player.move_frame != 1) {
            return;
        }
        state.* = .{
            .range_reference_point = findReferencePoint(state, player),
            .range_reference_rotation = player.rotation,
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
            if (state.min_attack_z) |state_z| {
                state.min_attack_z = @min(state_z, line_min_z);
            } else {
                state.min_attack_z = line_min_z;
            }
            const line_max_z = @max(line.point_1.z(), line.point_2.z());
            if (state.max_attack_z) |state_z| {
                state.max_attack_z = @max(state_z, line_max_z);
            } else {
                state.max_attack_z = line_max_z;
            }
        }
        if (player.move_frame != null and player.move_frame == player.move_total_frames) {
            state.recovery_range = findHurtRange(state, player);
        }
    }

    fn findReferencePoint(state: *const PlayerState, player: *const model.Player) ?sdk.math.Vec2 {
        const position = if (player.position) |p| p.swizzle("xy") else return null;
        const rotation = player.rotation orelse return null;
        const cylinders = state.previous_frame_hurt_cylinders orelse return null;
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

    fn findHitLineRange(state: *const PlayerState, hit_line: *const model.HitLine) ?f32 {
        const reference_point = state.range_reference_point orelse return null;
        const rotation = state.range_reference_rotation orelse return null;
        const direction = sdk.math.Vec2.plus_x.rotateZ(rotation);
        const line = &hit_line.line;
        const range_1 = line.point_1.swizzle("xy").subtract(reference_point).dot(direction);
        const range_2 = line.point_2.swizzle("xy").subtract(reference_point).dot(direction);
        return @max(range_1, range_2);
    }

    fn findHurtRange(state: *const PlayerState, player: *const model.Player) ?f32 {
        const cylinders = player.hurt_cylinders orelse return null;
        const reference_point = state.range_reference_point orelse return null;
        const rotation = state.range_reference_rotation orelse return null;
        const attack_range = state.attack_range orelse return null;
        const direction = sdk.math.Vec2.plus_x.rotateZ(rotation);
        var max_projection = -std.math.inf(f32);
        for (&cylinders.values) |*hurt_cylinder| {
            const cylinder = hurt_cylinder.cylinder;
            const center = cylinder.center.swizzle("xy");
            const projection = center.subtract(reference_point).dot(direction) + cylinder.radius;
            if (projection > max_projection) {
                max_projection = projection;
            }
        }
        return attack_range - max_projection;
    }
};

const testing = std.testing;

test "should set min_attack_z, max_attack_z, attack_range, recovery_range to correct value at correct time" {
    const hurtCylinders = struct {
        fn call(y: f32) model.HurtCylinders {
            return model.HurtCylinders.init(.{
                .left_ankle = .{ .cylinder = .{ .center = .fromArray(.{ -1, y, 0 }), .radius = 1, .half_height = 1 } },
                .right_ankle = .{ .cylinder = .{ .center = .fromArray(.{ 1, y, 0 }), .radius = 1, .half_height = 3 } },
                .left_hand = .{ .cylinder = .{ .center = .fromArray(.{ -1, y, 2 }), .radius = 1, .half_height = 1 } },
                .right_hand = .{ .cylinder = .{ .center = .fromArray(.{ 1, y, 2 }), .radius = 1, .half_height = 1 } },
                .left_knee = .{ .cylinder = .{ .center = .fromArray(.{ -1, y, 1 }), .radius = 1, .half_height = 1 } },
                .right_knee = .{ .cylinder = .{ .center = .fromArray(.{ 1, y, 1 }), .radius = 1, .half_height = 1 } },
                .left_elbow = .{ .cylinder = .{ .center = .fromArray(.{ -1, y, 4 }), .radius = 1, .half_height = 1 } },
                .right_elbow = .{ .cylinder = .{ .center = .fromArray(.{ 1, y, 4 }), .radius = 1, .half_height = 1 } },
                .head = .{ .cylinder = .{ .center = .fromArray(.{ 0, y, 7 }), .radius = 1, .half_height = 1 } },
                .left_shoulder = .{ .cylinder = .{ .center = .fromArray(.{ -1, y, 6 }), .radius = 1, .half_height = 1 } },
                .right_shoulder = .{ .cylinder = .{ .center = .fromArray(.{ 1, y, 6 }), .radius = 1, .half_height = 1 } },
                .upper_torso = .{ .cylinder = .{ .center = .fromArray(.{ 0, y - 1, 5 }), .radius = 3, .half_height = 1 } },
                .left_pelvis = .{ .cylinder = .{ .center = .fromArray(.{ -1, y, 3 }), .radius = 1, .half_height = 3 } },
                .right_pelvis = .{ .cylinder = .{ .center = .fromArray(.{ 1, y, 3 }), .radius = 1, .half_height = 1 } },
            });
        }
    }.call;
    const hitLines = struct {
        fn call(array: anytype) model.HitLines {
            if (@typeInfo(@TypeOf(array)) != .array) {
                const coerced: [array.len]sdk.math.LineSegment3 = array;
                return call(coerced);
            }
            if (array.len > model.HitLines.max_len) {
                @compileError("Array length exceeds maximum allowed number of lines.");
            }
            var buffer: [model.HitLines.max_len]model.HitLine = undefined;
            for (array, 0..) |line, index| {
                buffer[index] = .{ .line = line, .flags = .{} };
            }
            return .{ .buffer = buffer, .len = array.len };
        }
    }.call;
    var frames = [_]model.Frame{
        .{ .players = .{ .{
            .move_frame = 99,
            .move_total_frames = 99,
            .position = sdk.math.Vec3.fromArray(.{ 0, 0, 0 }),
            .rotation = std.math.pi,
            .hurt_cylinders = hurtCylinders(0),
            .hit_lines = hitLines(.{}),
        }, .{} } },
        .{ .players = .{ .{
            .move_frame = 1,
            .move_total_frames = 5,
            .position = sdk.math.Vec3.fromArray(.{ 0, 1, 0 }),
            .rotation = 0.5 * std.math.pi,
            .hurt_cylinders = hurtCylinders(1),
            .hit_lines = hitLines(.{}),
        }, .{} } },
        .{ .players = .{ .{
            .move_frame = 2,
            .move_total_frames = 5,
            .position = sdk.math.Vec3.fromArray(.{ 0, 2, 0 }),
            .rotation = 0.5 * std.math.pi,
            .hurt_cylinders = hurtCylinders(2),
            .hit_lines = hitLines(.{
                sdk.math.LineSegment3{ .point_1 = .fromArray(.{ 0, 4, 1 }), .point_2 = .fromArray(.{ 1, 5, 2 }) },
                sdk.math.LineSegment3{ .point_1 = .fromArray(.{ 0, 0, 2 }), .point_2 = .fromArray(.{ -1, 0, 1 }) },
            }),
        }, .{} } },
        .{ .players = .{ .{
            .move_frame = 3,
            .move_total_frames = 5,
            .position = sdk.math.Vec3.fromArray(.{ 0, 3, 0 }),
            .rotation = 0.5 * std.math.pi,
            .hurt_cylinders = hurtCylinders(3),
            .hit_lines = hitLines(.{
                sdk.math.LineSegment3{ .point_1 = .fromArray(.{ 0, 5, 2 }), .point_2 = .fromArray(.{ 0, 6, 3 }) },
            }),
        }, .{} } },
        .{ .players = .{ .{
            .move_frame = 4,
            .move_total_frames = 5,
            .position = sdk.math.Vec3.fromArray(.{ 0, 2, 0 }),
            .rotation = 0.5 * std.math.pi,
            .hurt_cylinders = hurtCylinders(2),
            .hit_lines = hitLines(.{}),
        }, .{} } },
        .{ .players = .{ .{
            .move_frame = 5,
            .move_total_frames = 5,
            .position = sdk.math.Vec3.fromArray(.{ 0, 1, 0 }),
            .rotation = 0.5 * std.math.pi,
            .hurt_cylinders = hurtCylinders(1),
            .hit_lines = hitLines(.{}),
        }, .{} } },
        .{ .players = .{ .{
            .move_frame = 1,
            .move_total_frames = 2,
            .position = sdk.math.Vec3.fromArray(.{ 0, 1, 0 }),
            .rotation = 0.5 * std.math.pi,
            .hurt_cylinders = hurtCylinders(1),
            .hit_lines = hitLines(.{}),
        }, .{} } },
        .{ .players = .{ .{
            .move_frame = 2,
            .move_total_frames = 2,
            .position = sdk.math.Vec3.fromArray(.{ 0, 1, 0 }),
            .rotation = 0.5 * std.math.pi,
            .hurt_cylinders = hurtCylinders(1),
            .hit_lines = hitLines(.{}),
        }, .{} } },
        .{ .players = .{ .{
            .move_frame = 1,
            .move_total_frames = 99,
            .position = sdk.math.Vec3.fromArray(.{ 0, 1, 0 }),
            .rotation = 0.5 * std.math.pi,
            .hurt_cylinders = hurtCylinders(1),
            .hit_lines = hitLines(.{}),
        }, .{} } },
    };

    var measurer = MoveMeasurer{};
    for (&frames, 0..) |*frame, index| {
        measurer.measure(frame);
        switch (index) {
            2 => {
                try testing.expectEqual(1, frame.players[0].min_attack_z);
                try testing.expectEqual(2, frame.players[0].max_attack_z);
                try testing.expectEqual(3, frame.players[0].attack_range);
                try testing.expectEqual(null, frame.players[0].recovery_range);
            },
            3, 4 => {
                try testing.expectEqual(1, frame.players[0].min_attack_z);
                try testing.expectEqual(3, frame.players[0].max_attack_z);
                try testing.expectEqual(4, frame.players[0].attack_range);
                try testing.expectEqual(null, frame.players[0].recovery_range);
            },
            5 => {
                try testing.expectEqual(1, frame.players[0].min_attack_z);
                try testing.expectEqual(3, frame.players[0].max_attack_z);
                try testing.expectEqual(4, frame.players[0].attack_range);
                try testing.expectEqual(3, frame.players[0].recovery_range);
            },
            6 => {
                try testing.expectEqual(null, frame.players[0].min_attack_z);
                try testing.expectEqual(null, frame.players[0].max_attack_z);
                try testing.expectEqual(null, frame.players[0].attack_range);
                try testing.expectEqual(3, frame.players[0].recovery_range);
            },
            else => {
                try testing.expectEqual(null, frame.players[0].min_attack_z);
                try testing.expectEqual(null, frame.players[0].max_attack_z);
                try testing.expectEqual(null, frame.players[0].attack_range);
                try testing.expectEqual(null, frame.players[0].recovery_range);
            },
        }
    }
}
