const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

pub const HitDetector = struct {
    player_1_move_already_connected: bool = false,
    player_2_move_already_connected: bool = false,

    const Self = @This();

    pub fn detect(self: *Self, frame: *model.Frame) void {
        detectSide(&frame.players[0], &frame.players[1], &self.player_1_move_already_connected);
        detectSide(&frame.players[1], &frame.players[0], &self.player_2_move_already_connected);
    }

    fn detectSide(attacker: *model.Player, defender: *model.Player, already_connected: *bool) void {
        const lines = attacker.hit_lines.asSlice();
        if (lines.len == 0) {
            already_connected.* = false;
            return;
        }

        const inactive = already_connected.*;
        const crushes = checkCrushing(defender.crushing, attacker.attack_type);
        const is_power_crushing = if (defender.crushing) |c| c.power_crushing else false;
        const is_blocking_outcome = isBlockingHitOutcome(defender.hit_outcome);
        const is_normal_hitting_outcome = isNormalHittingHitOutcome(defender.hit_outcome);
        const is_counter_hitting_outcome = isCounterHittingHitOutcome(defender.hit_outcome);

        const cylinders: *model.HurtCylinders = if (defender.hurt_cylinders) |*c| c else return;
        for (&cylinders.values) |*cylinder| {
            for (lines) |*line| {
                const intersects = sdk.math.checkCylinderLineSegmentIntersection(cylinder.cylinder, line.line);
                const connects = intersects and !crushes and !inactive;
                const power_crushes = connects and is_power_crushing;
                const block = connects and is_blocking_outcome;
                const normal_hit = connects and is_normal_hitting_outcome;
                const counter_hit = connects and is_counter_hitting_outcome;

                cylinder.flags.is_intersecting = cylinder.flags.is_intersecting or intersects;
                cylinder.flags.is_crushing = cylinder.flags.is_crushing or crushes;
                cylinder.flags.is_power_crushing = cylinder.flags.is_power_crushing or power_crushes;
                cylinder.flags.is_connected = cylinder.flags.is_connected or connects;
                cylinder.flags.is_blocking = cylinder.flags.is_blocking or block;
                cylinder.flags.is_being_normal_hit = cylinder.flags.is_being_normal_hit or normal_hit;
                cylinder.flags.is_being_counter_hit = cylinder.flags.is_being_counter_hit or counter_hit;

                line.flags.is_inactive = line.flags.is_inactive or inactive;
                line.flags.is_intersecting = line.flags.is_intersecting or intersects;
                line.flags.is_crushed = line.flags.is_crushed or crushes;
                line.flags.is_power_crushed = line.flags.is_power_crushed or power_crushes;
                line.flags.is_connected = line.flags.is_connected or connects;
                line.flags.is_blocked = line.flags.is_blocked or block;
                line.flags.is_normal_hitting = line.flags.is_normal_hitting or normal_hit;
                line.flags.is_counter_hitting = line.flags.is_counter_hitting or counter_hit;

                if (connects) {
                    already_connected.* = true;
                }
            }
        }
    }

    fn checkCrushing(crushing: ?model.Crushing, attack_type: ?model.AttackType) bool {
        const c = crushing orelse return false;
        const a = attack_type orelse return false;
        return switch (a) {
            .not_attack => false,
            .high => c.invincibility or c.high_crushing,
            .mid => c.invincibility,
            .low => c.invincibility or c.low_crushing,
            .special_low => c.invincibility or c.low_crushing,
            .unblockable_high => c.invincibility or c.high_crushing,
            .unblockable_mid => c.invincibility,
            .unblockable_low => c.invincibility or c.low_crushing,
            .throw => false,
            .projectile => c.invincibility,
            .antiair_only => c.invincibility or c.anti_air_only_crushing,
        };
    }

    fn isBlockingHitOutcome(hit_outcome: ?model.HitOutcome) bool {
        const h = hit_outcome orelse return false;
        return switch (h) {
            .none => false,
            .blocked_standing => true,
            .blocked_crouching => true,
            .juggle => false,
            .screw => false,
            .grounded_face_down => false,
            .grounded_face_up => false,
            .counter_hit_standing => false,
            .counter_hit_crouching => false,
            .normal_hit_standing => false,
            .normal_hit_crouching => false,
            .normal_hit_standing_left => false,
            .normal_hit_crouching_left => false,
            .normal_hit_standing_back => false,
            .normal_hit_crouching_back => false,
            .normal_hit_standing_right => false,
            .normal_hit_crouching_right => false,
        };
    }

    fn isNormalHittingHitOutcome(hit_outcome: ?model.HitOutcome) bool {
        const h = hit_outcome orelse return false;
        return switch (h) {
            .none => false,
            .blocked_standing => false,
            .blocked_crouching => false,
            .juggle => true,
            .screw => true,
            .grounded_face_down => true,
            .grounded_face_up => true,
            .counter_hit_standing => false,
            .counter_hit_crouching => false,
            .normal_hit_standing => true,
            .normal_hit_crouching => true,
            .normal_hit_standing_left => true,
            .normal_hit_crouching_left => true,
            .normal_hit_standing_back => true,
            .normal_hit_crouching_back => true,
            .normal_hit_standing_right => true,
            .normal_hit_crouching_right => true,
        };
    }

    fn isCounterHittingHitOutcome(hit_outcome: ?model.HitOutcome) bool {
        const h = hit_outcome orelse return false;
        return switch (h) {
            .none => false,
            .blocked_standing => false,
            .blocked_crouching => false,
            .juggle => false,
            .screw => false,
            .grounded_face_down => false,
            .grounded_face_up => false,
            .counter_hit_standing => true,
            .counter_hit_crouching => true,
            .normal_hit_standing => false,
            .normal_hit_crouching => false,
            .normal_hit_standing_left => false,
            .normal_hit_crouching_left => false,
            .normal_hit_standing_back => false,
            .normal_hit_crouching_back => false,
            .normal_hit_standing_right => false,
            .normal_hit_crouching_right => false,
        };
    }
};

const testing = std.testing;

fn hitLines(array: anytype) model.HitLines {
    if (@typeInfo(@TypeOf(array)) != .array) {
        const coerced: [array.len]sdk.math.LineSegment3 = array;
        return hitLines(coerced);
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

fn hurtCylinders(array: [model.HurtCylinders.len]sdk.math.Cylinder) model.HurtCylinders {
    var values: [model.HurtCylinders.len]model.HurtCylinder = undefined;
    for (array, 0..) |cylinder, index| {
        values[index] = .{ .cylinder = cylinder, .flags = .{} };
    }
    return .{ .values = values };
}

test "should detect a whiff correctly" {
    const hit_line = sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ 0, 0, 0 }),
        .point_2 = .fromArray(.{ 1, 0, 0 }),
    };
    const hurt_cylinder = sdk.math.Cylinder{
        .center = .fromArray(.{ 3, 0, 0 }),
        .radius = 1,
        .half_height = 1,
    };
    var frame = model.Frame{ .players = .{
        .{
            .attack_type = .unblockable_mid,
            .hit_lines = hitLines(.{ hit_line, hit_line }),
        },
        .{
            .crushing = .{},
            .hit_outcome = .none,
            .hurt_cylinders = hurtCylinders(@splat(hurt_cylinder)),
        },
    } };
    var hit_detector = HitDetector{};
    hit_detector.detect(&frame);

    try testing.expectEqual(2, frame.players[0].hit_lines.asSlice().len);
    try testing.expectEqual(model.HitLineFlags{}, frame.players[0].hit_lines.asSlice()[0].flags);
    try testing.expectEqual(model.HitLineFlags{}, frame.players[0].hit_lines.asSlice()[1].flags);

    try testing.expect(frame.players[1].hurt_cylinders != null);
    for (&frame.players[1].hurt_cylinders.?.values) |*cylinder| {
        try testing.expectEqual(model.HurtCylinderFlags{}, cylinder.flags);
    }
}

test "should detect a high crush correctly" {
    const whiffed_line = sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ -2, 0, 0 }),
        .point_2 = .fromArray(.{ -1, 0, 0 }),
    };
    const connected_line = sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ -1, 0, 0 }),
        .point_2 = .fromArray(.{ 0, 0, 0 }),
    };
    const whiffed_cylinder = sdk.math.Cylinder{
        .center = .fromArray(.{ 1, 0, 0 }),
        .radius = 0.5,
        .half_height = 0.5,
    };
    const connected_cylinder = sdk.math.Cylinder{
        .center = .fromArray(.{ 0, 0, 0 }),
        .radius = 0.5,
        .half_height = 0.5,
    };
    var frame = model.Frame{ .players = .{
        .{
            .attack_type = .high,
            .hit_lines = hitLines(.{ whiffed_line, connected_line }),
        },
        .{
            .crushing = .{ .high_crushing = true },
            .hit_outcome = .none,
            .hurt_cylinders = hurtCylinders(
            	@as([7]sdk.math.Cylinder, @splat(whiffed_cylinder)) ++
             	@as([7]sdk.math.Cylinder, @splat(connected_cylinder))
            ),
        },
    } };
    var hit_detector = HitDetector{};
    hit_detector.detect(&frame);

    try testing.expectEqual(2, frame.players[0].hit_lines.asSlice().len);
    try testing.expectEqual(model.HitLineFlags{
        .is_intersecting = false,
        .is_crushed = true,
    }, frame.players[0].hit_lines.asSlice()[0].flags);
    try testing.expectEqual(model.HitLineFlags{
        .is_intersecting = true,
        .is_crushed = true,
    }, frame.players[0].hit_lines.asSlice()[1].flags);

    try testing.expect(frame.players[1].hurt_cylinders != null);
    for (&frame.players[1].hurt_cylinders.?.values, 0..) |*cylinder, index| {
        try testing.expectEqual(model.HurtCylinderFlags{
            .is_intersecting = index >= 7,
            .is_crushing = true,
        }, cylinder.flags);
    }
}

test "should detect a low crush correctly" {
    const whiffed_line = sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ -2, 0, 0 }),
        .point_2 = .fromArray(.{ -1, 0, 0 }),
    };
    const connected_line = sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ -1, 0, 0 }),
        .point_2 = .fromArray(.{ 0, 0, 0 }),
    };
    const whiffed_cylinder = sdk.math.Cylinder{
        .center = .fromArray(.{ 1, 0, 0 }),
        .radius = 0.5,
        .half_height = 0.5,
    };
    const connected_cylinder = sdk.math.Cylinder{
        .center = .fromArray(.{ 0, 0, 0 }),
        .radius = 0.5,
        .half_height = 0.5,
    };
    var frame = model.Frame{ .players = .{
        .{
            .attack_type = .low,
            .hit_lines = hitLines(.{ whiffed_line, connected_line }),
        },
        .{
            .crushing = .{ .low_crushing = true },
            .hit_outcome = .none,
            .hurt_cylinders = hurtCylinders(
            	@as([7]sdk.math.Cylinder, @splat(whiffed_cylinder)) ++
             	@as([7]sdk.math.Cylinder, @splat(connected_cylinder))
            ),
        },
    } };
    var hit_detector = HitDetector{};
    hit_detector.detect(&frame);

    try testing.expectEqual(2, frame.players[0].hit_lines.asSlice().len);
    try testing.expectEqual(model.HitLineFlags{
        .is_intersecting = false,
        .is_crushed = true,
    }, frame.players[0].hit_lines.asSlice()[0].flags);
    try testing.expectEqual(model.HitLineFlags{
        .is_intersecting = true,
        .is_crushed = true,
    }, frame.players[0].hit_lines.asSlice()[1].flags);

    try testing.expect(frame.players[1].hurt_cylinders != null);
    for (&frame.players[1].hurt_cylinders.?.values, 0..) |*cylinder, index| {
        try testing.expectEqual(model.HurtCylinderFlags{
            .is_intersecting = index >= 7,
            .is_crushing = true,
        }, cylinder.flags);
    }
}

test "should detect a mid crush correctly" {
    const whiffed_line = sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ -2, 0, 0 }),
        .point_2 = .fromArray(.{ -1, 0, 0 }),
    };
    const connected_line = sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ -1, 0, 0 }),
        .point_2 = .fromArray(.{ 0, 0, 0 }),
    };
    const whiffed_cylinder = sdk.math.Cylinder{
        .center = .fromArray(.{ 1, 0, 0 }),
        .radius = 0.5,
        .half_height = 0.5,
    };
    const connected_cylinder = sdk.math.Cylinder{
        .center = .fromArray(.{ 0, 0, 0 }),
        .radius = 0.5,
        .half_height = 0.5,
    };
    var frame = model.Frame{ .players = .{
        .{
            .attack_type = .mid,
            .hit_lines = hitLines(.{ whiffed_line, connected_line }),
        },
        .{
            .crushing = .{ .invincibility = true },
            .hit_outcome = .none,
            .hurt_cylinders = hurtCylinders(
            	@as([7]sdk.math.Cylinder, @splat(whiffed_cylinder)) ++
             	@as([7]sdk.math.Cylinder, @splat(connected_cylinder))
            ),
        },
    } };
    var hit_detector = HitDetector{};
    hit_detector.detect(&frame);

    try testing.expectEqual(2, frame.players[0].hit_lines.asSlice().len);
    try testing.expectEqual(model.HitLineFlags{
        .is_intersecting = false,
        .is_crushed = true,
    }, frame.players[0].hit_lines.asSlice()[0].flags);
    try testing.expectEqual(model.HitLineFlags{
        .is_intersecting = true,
        .is_crushed = true,
    }, frame.players[0].hit_lines.asSlice()[1].flags);

    try testing.expect(frame.players[1].hurt_cylinders != null);
    for (&frame.players[1].hurt_cylinders.?.values, 0..) |*cylinder, index| {
        try testing.expectEqual(model.HurtCylinderFlags{
            .is_intersecting = index >= 7,
            .is_crushing = true,
        }, cylinder.flags);
    }
}

test "should detect a anti air only crush correctly" {
    const whiffed_line = sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ -2, 0, 0 }),
        .point_2 = .fromArray(.{ -1, 0, 0 }),
    };
    const connected_line = sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ -1, 0, 0 }),
        .point_2 = .fromArray(.{ 0, 0, 0 }),
    };
    const whiffed_cylinder = sdk.math.Cylinder{
        .center = .fromArray(.{ 1, 0, 0 }),
        .radius = 0.5,
        .half_height = 0.5,
    };
    const connected_cylinder = sdk.math.Cylinder{
        .center = .fromArray(.{ 0, 0, 0 }),
        .radius = 0.5,
        .half_height = 0.5,
    };
    var frame = model.Frame{ .players = .{
        .{
            .attack_type = .antiair_only,
            .hit_lines = hitLines(.{ whiffed_line, connected_line }),
        },
        .{
            .crushing = .{ .anti_air_only_crushing = true },
            .hit_outcome = .none,
            .hurt_cylinders = hurtCylinders(
            	@as([7]sdk.math.Cylinder, @splat(whiffed_cylinder)) ++
             	@as([7]sdk.math.Cylinder, @splat(connected_cylinder))
            ),
        },
    } };
    var hit_detector = HitDetector{};
    hit_detector.detect(&frame);

    try testing.expectEqual(2, frame.players[0].hit_lines.asSlice().len);
    try testing.expectEqual(model.HitLineFlags{
        .is_intersecting = false,
        .is_crushed = true,
    }, frame.players[0].hit_lines.asSlice()[0].flags);
    try testing.expectEqual(model.HitLineFlags{
        .is_intersecting = true,
        .is_crushed = true,
    }, frame.players[0].hit_lines.asSlice()[1].flags);

    try testing.expect(frame.players[1].hurt_cylinders != null);
    for (&frame.players[1].hurt_cylinders.?.values, 0..) |*cylinder, index| {
        try testing.expectEqual(model.HurtCylinderFlags{
            .is_intersecting = index >= 7,
            .is_crushing = true,
        }, cylinder.flags);
    }
}

test "should detect a power crush correctly" {
    const whiffed_line = sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ -2, 0, 0 }),
        .point_2 = .fromArray(.{ -1, 0, 0 }),
    };
    const connected_line = sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ -1, 0, 0 }),
        .point_2 = .fromArray(.{ 0, 0, 0 }),
    };
    const whiffed_cylinder = sdk.math.Cylinder{
        .center = .fromArray(.{ 1, 0, 0 }),
        .radius = 0.5,
        .half_height = 0.5,
    };
    const connected_cylinder = sdk.math.Cylinder{
        .center = .fromArray(.{ 0, 0, 0 }),
        .radius = 0.5,
        .half_height = 0.5,
    };
    var frame = model.Frame{ .players = .{
        .{
            .attack_type = .mid,
            .hit_lines = hitLines(.{ whiffed_line, connected_line }),
        },
        .{
            .crushing = .{ .power_crushing = true },
            .hit_outcome = .none,
            .hurt_cylinders = hurtCylinders(
            	@as([7]sdk.math.Cylinder, @splat(whiffed_cylinder)) ++
             	@as([7]sdk.math.Cylinder, @splat(connected_cylinder))
            ),
        },
    } };
    var hit_detector = HitDetector{};
    hit_detector.detect(&frame);

    try testing.expectEqual(2, frame.players[0].hit_lines.asSlice().len);
    try testing.expectEqual(model.HitLineFlags{
        .is_intersecting = false,
        .is_connected = false,
        .is_power_crushed = false,
    }, frame.players[0].hit_lines.asSlice()[0].flags);
    try testing.expectEqual(model.HitLineFlags{
        .is_intersecting = true,
        .is_connected = true,
        .is_power_crushed = true,
    }, frame.players[0].hit_lines.asSlice()[1].flags);

    try testing.expect(frame.players[1].hurt_cylinders != null);
    for (&frame.players[1].hurt_cylinders.?.values, 0..) |*cylinder, index| {
        try testing.expectEqual(model.HurtCylinderFlags{
            .is_intersecting = index >= 7,
            .is_connected = index >= 7,
            .is_power_crushing = index >= 7,
        }, cylinder.flags);
    }
}

test "should detect a block correctly" {
    const whiffed_line = sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ -2, 0, 0 }),
        .point_2 = .fromArray(.{ -1, 0, 0 }),
    };
    const connected_line = sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ -1, 0, 0 }),
        .point_2 = .fromArray(.{ 0, 0, 0 }),
    };
    const whiffed_cylinder = sdk.math.Cylinder{
        .center = .fromArray(.{ 1, 0, 0 }),
        .radius = 0.5,
        .half_height = 0.5,
    };
    const connected_cylinder = sdk.math.Cylinder{
        .center = .fromArray(.{ 0, 0, 0 }),
        .radius = 0.5,
        .half_height = 0.5,
    };
    var frame = model.Frame{ .players = .{
        .{
            .attack_type = .mid,
            .hit_lines = hitLines(.{ whiffed_line, connected_line }),
        },
        .{
            .crushing = .{},
            .hit_outcome = .blocked_standing,
            .hurt_cylinders = hurtCylinders(
            	@as([7]sdk.math.Cylinder, @splat(whiffed_cylinder)) ++
             	@as([7]sdk.math.Cylinder, @splat(connected_cylinder))
            ),
        },
    } };
    var hit_detector = HitDetector{};
    hit_detector.detect(&frame);

    try testing.expectEqual(2, frame.players[0].hit_lines.asSlice().len);
    try testing.expectEqual(model.HitLineFlags{
        .is_intersecting = false,
        .is_connected = false,
        .is_blocked = false,
    }, frame.players[0].hit_lines.asSlice()[0].flags);
    try testing.expectEqual(model.HitLineFlags{
        .is_intersecting = true,
        .is_connected = true,
        .is_blocked = true,
    }, frame.players[0].hit_lines.asSlice()[1].flags);

    try testing.expect(frame.players[1].hurt_cylinders != null);
    for (&frame.players[1].hurt_cylinders.?.values, 0..) |*cylinder, index| {
        try testing.expectEqual(model.HurtCylinderFlags{
            .is_intersecting = index >= 7,
            .is_connected = index >= 7,
            .is_blocking = index >= 7,
        }, cylinder.flags);
    }
}

test "should detect a normal hit correctly" {
    const whiffed_line = sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ -2, 0, 0 }),
        .point_2 = .fromArray(.{ -1, 0, 0 }),
    };
    const connected_line = sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ -1, 0, 0 }),
        .point_2 = .fromArray(.{ 0, 0, 0 }),
    };
    const whiffed_cylinder = sdk.math.Cylinder{
        .center = .fromArray(.{ 1, 0, 0 }),
        .radius = 0.5,
        .half_height = 0.5,
    };
    const connected_cylinder = sdk.math.Cylinder{
        .center = .fromArray(.{ 0, 0, 0 }),
        .radius = 0.5,
        .half_height = 0.5,
    };
    var frame = model.Frame{ .players = .{
        .{
            .attack_type = .mid,
            .hit_lines = hitLines(.{ whiffed_line, connected_line }),
        },
        .{
            .crushing = .{},
            .hit_outcome = .normal_hit_standing,
            .hurt_cylinders = hurtCylinders(
            	@as([7]sdk.math.Cylinder, @splat(whiffed_cylinder)) ++
             	@as([7]sdk.math.Cylinder, @splat(connected_cylinder))
            ),
        },
    } };
    var hit_detector = HitDetector{};
    hit_detector.detect(&frame);

    try testing.expectEqual(2, frame.players[0].hit_lines.asSlice().len);
    try testing.expectEqual(model.HitLineFlags{
        .is_intersecting = false,
        .is_connected = false,
        .is_normal_hitting = false,
    }, frame.players[0].hit_lines.asSlice()[0].flags);
    try testing.expectEqual(model.HitLineFlags{
        .is_intersecting = true,
        .is_connected = true,
        .is_normal_hitting = true,
    }, frame.players[0].hit_lines.asSlice()[1].flags);

    try testing.expect(frame.players[1].hurt_cylinders != null);
    for (&frame.players[1].hurt_cylinders.?.values, 0..) |*cylinder, index| {
        try testing.expectEqual(model.HurtCylinderFlags{
            .is_intersecting = index >= 7,
            .is_connected = index >= 7,
            .is_being_normal_hit = index >= 7,
        }, cylinder.flags);
    }
}

test "should detect a counter hit correctly" {
    const whiffed_line = sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ -2, 0, 0 }),
        .point_2 = .fromArray(.{ -1, 0, 0 }),
    };
    const connected_line = sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ -1, 0, 0 }),
        .point_2 = .fromArray(.{ 0, 0, 0 }),
    };
    const whiffed_cylinder = sdk.math.Cylinder{
        .center = .fromArray(.{ 1, 0, 0 }),
        .radius = 0.5,
        .half_height = 0.5,
    };
    const connected_cylinder = sdk.math.Cylinder{
        .center = .fromArray(.{ 0, 0, 0 }),
        .radius = 0.5,
        .half_height = 0.5,
    };
    var frame = model.Frame{ .players = .{
        .{
            .attack_type = .mid,
            .hit_lines = hitLines(.{ whiffed_line, connected_line }),
        },
        .{
            .crushing = .{},
            .hit_outcome = .counter_hit_standing,
            .hurt_cylinders = hurtCylinders(
            	@as([7]sdk.math.Cylinder, @splat(whiffed_cylinder)) ++
             	@as([7]sdk.math.Cylinder, @splat(connected_cylinder))
            ),
        },
    } };
    var hit_detector = HitDetector{};
    hit_detector.detect(&frame);

    try testing.expectEqual(2, frame.players[0].hit_lines.asSlice().len);
    try testing.expectEqual(model.HitLineFlags{
        .is_intersecting = false,
        .is_connected = false,
        .is_counter_hitting = false,
    }, frame.players[0].hit_lines.asSlice()[0].flags);
    try testing.expectEqual(model.HitLineFlags{
        .is_intersecting = true,
        .is_connected = true,
        .is_counter_hitting = true,
    }, frame.players[0].hit_lines.asSlice()[1].flags);

    try testing.expect(frame.players[1].hurt_cylinders != null);
    for (&frame.players[1].hurt_cylinders.?.values, 0..) |*cylinder, index| {
        try testing.expectEqual(model.HurtCylinderFlags{
            .is_intersecting = index >= 7,
            .is_connected = index >= 7,
            .is_being_counter_hit = index >= 7,
        }, cylinder.flags);
    }
}

test "should detect inactive lines correctly" {
    const hit_line = sdk.math.LineSegment3{
        .point_1 = .fromArray(.{ -1, 0, 0 }),
        .point_2 = .fromArray(.{ 1, 0, 0 }),
    };
    const hurt_cylinder = sdk.math.Cylinder{
        .center = .fromArray(.{ 0, 0, 0 }),
        .radius = 1,
        .half_height = 1,
    };
    const frame = model.Frame{ .players = .{
        .{
            .attack_type = .mid,
            .hit_lines = hitLines(.{hit_line}),
        },
        .{
            .crushing = .{},
            .hit_outcome = .blocked_standing,
            .hurt_cylinders = hurtCylinders(@splat(hurt_cylinder)),
        },
    } };

    var hit_detector = HitDetector{};
    var frame_1 = frame;
    hit_detector.detect(&frame_1);

    try testing.expectEqual(1, frame_1.players[0].hit_lines.asSlice().len);
    try testing.expectEqual(model.HitLineFlags{
        .is_inactive = false,
        .is_intersecting = true,
        .is_connected = true,
        .is_blocked = true,
    }, frame_1.players[0].hit_lines.asSlice()[0].flags);

    var frame_2 = frame;
    hit_detector.detect(&frame_2);

    try testing.expectEqual(1, frame_2.players[0].hit_lines.asSlice().len);
    try testing.expectEqual(model.HitLineFlags{
        .is_inactive = true,
        .is_intersecting = true,
        .is_connected = false,
        .is_blocked = false,
    }, frame_2.players[0].hit_lines.asSlice()[0].flags);

    var frame_3 = frame;
    frame_3.players[0].hit_lines = hitLines(.{});
    hit_detector.detect(&frame_3);

    try testing.expectEqual(0, frame_3.players[0].hit_lines.asSlice().len);

    var frame_4 = frame;
    hit_detector.detect(&frame_4);

    try testing.expectEqual(1, frame_4.players[0].hit_lines.asSlice().len);
    try testing.expectEqual(model.HitLineFlags{
        .is_inactive = false,
        .is_intersecting = true,
        .is_connected = true,
        .is_blocked = true,
    }, frame_4.players[0].hit_lines.asSlice()[0].flags);
}
