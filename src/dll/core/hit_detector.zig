const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");

pub const HitDetector = struct {
    player_1_move_already_connected: bool = false,
    player_2_move_already_connected: bool = false,

    const Self = @This();

    pub fn detect(self: *Self, frame: *model.Frame) void {
        detectHits(&frame.players[0], &frame.players[1], &self.player_1_move_already_connected);
        detectHits(&frame.players[1], &frame.players[0], &self.player_2_move_already_connected);
    }

    fn detectHits(attacker: *model.Player, defender: *model.Player, already_connected: *bool) void {
        if (attacker.current_move_frame == 1) {
            already_connected.* = false;
        }

        const inactive = already_connected.*;
        const crushes = checkCrushing(defender.crushing, attacker.attack_type);
        const is_power_crushing = if (defender.crushing) |c| c.power_crushing else false;
        const is_blocking_outcome = isBlockingHitOutcome(defender.hit_outcome);
        const is_hitting_outcome = isHittingHitOutcome(defender.hit_outcome);
        const is_counter_hitting_outcome = isCounterHittingHitOutcome(defender.hit_outcome);

        const cylinders: *model.HurtCylinders = if (defender.hurt_cylinders) |*c| c else return;
        for (&cylinders.values) |*cylinder| {
            for (attacker.hit_lines.asMutableSlice()) |*line| {
                const intersects = sdk.math.checkCylinderLineSegmentIntersection(cylinder.cylinder, line.line);
                const connects = intersects and !crushes and !inactive;
                const power_crushes = connects and is_power_crushing;
                const block = connects and is_blocking_outcome;
                const hit = connects and is_hitting_outcome;
                const counter_hit = connects and is_counter_hitting_outcome;

                cylinder.flags.is_intersecting = cylinder.flags.is_intersecting or intersects;
                cylinder.flags.is_crushing = cylinder.flags.is_crushing or crushes;
                cylinder.flags.is_power_crushing = cylinder.flags.is_power_crushing or power_crushes;
                cylinder.flags.is_connected = cylinder.flags.is_connected or connects;
                cylinder.flags.is_blocking = cylinder.flags.is_blocking or block;
                cylinder.flags.is_being_hit = cylinder.flags.is_being_hit or hit;
                cylinder.flags.is_being_counter_hit = cylinder.flags.is_being_counter_hit or counter_hit;

                line.flags.is_inactive = line.flags.is_inactive or inactive;
                line.flags.is_intersecting = line.flags.is_intersecting or intersects;
                line.flags.is_crushed = line.flags.is_crushed or crushes;
                line.flags.is_power_crushed = line.flags.is_power_crushed or power_crushes;
                line.flags.is_connected = line.flags.is_connected or connects;
                line.flags.is_blocked = line.flags.is_blocked or block;
                line.flags.is_hitting = line.flags.is_hitting or hit;
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
            .high_unblockable => c.invincibility or c.high_crushing,
            .mid_unblockable => c.invincibility,
            .low_unblockable => c.invincibility or c.low_crushing,
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

    fn isHittingHitOutcome(hit_outcome: ?model.HitOutcome) bool {
        const h = hit_outcome orelse return false;
        return switch (h) {
            .none => false,
            .blocked_standing => false,
            .blocked_crouching => false,
            .juggle => true,
            .screw => true,
            .grounded_face_down => true,
            .grounded_face_up => true,
            .counter_hit_standing => true,
            .counter_hit_crouching => true,
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

// TODO write tests for this.
