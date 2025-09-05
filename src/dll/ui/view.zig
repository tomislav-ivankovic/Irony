const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("../ui/root.zig");

pub const ViewDirection = enum {
    front,
    side,
    top,
};

pub const View = struct {
    frame: model.Frame = .{},
    camera: ui.Camera = .{},
    hurt_cylinders: ui.HurtCylinders = .{},
    lingering_hit_lines: sdk.misc.CircularBuffer(128, LingeringLine) = .{},

    const Self = @This();

    const LingeringLine = struct {
        line: sdk.math.LineSegment3,
        player_id: model.PlayerId,
        life_time: f32,
        attack_type: ?model.AttackType,
        inactive_or_crushed: bool,
    };

    const config = .{
        .floor = .{
            .color = sdk.math.Vec4.fromArray(.{ 0.0, 1.0, 0.0, 1.0 }),
            .thickness = 1.0,
        },
        .hit_lines = .{
            .normal = .{
                .fill = .{
                    .colors = std.EnumArray(model.AttackType, sdk.math.Vec4).init(.{
                        .not_attack = .fromArray(.{ 0.5, 0.5, 0.5, 1.0 }),
                        .high = .fromArray(.{ 1.0, 0.0, 0.0, 1.0 }),
                        .mid = .fromArray(.{ 1.0, 1.0, 0.0, 1.0 }),
                        .low = .fromArray(.{ 0.0, 0.5, 1.0, 1.0 }),
                        .special_low = .fromArray(.{ 0.0, 1.0, 1.0, 1.0 }),
                        .unblockable_high = .fromArray(.{ 1.0, 0.0, 0.0, 1.0 }),
                        .unblockable_mid = .fromArray(.{ 1.0, 1.0, 0.0, 1.0 }),
                        .unblockable_low = .fromArray(.{ 0.0, 0.5, 1.0, 1.0 }),
                        .throw = .fromArray(.{ 1.0, 1.0, 1.0, 1.0 }),
                        .projectile = .fromArray(.{ 0.5, 1.0, 0.5, 1.0 }),
                        .antiair_only = .fromArray(.{ 1.0, 0.5, 0.0, 1.0 }),
                    }),
                    .thickness = 1.0,
                },
                .outline = .{
                    .colors = std.EnumArray(model.AttackType, sdk.math.Vec4).init(.{
                        .not_attack = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                        .high = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                        .mid = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                        .low = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                        .special_low = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                        .unblockable_high = .fromArray(.{ 0.75, 0.0, 0.75, 1.0 }),
                        .unblockable_mid = .fromArray(.{ 0.75, 0.0, 0.75, 1.0 }),
                        .unblockable_low = .fromArray(.{ 0.75, 0.0, 0.75, 1.0 }),
                        .throw = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                        .projectile = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                        .antiair_only = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                    }),
                    .thickness = 1.0,
                },
            },
            .inactive_or_crushed = .{
                .fill = .{
                    .colors = std.EnumArray(model.AttackType, sdk.math.Vec4).init(.{
                        .not_attack = .fromArray(.{ 0.5, 0.5, 0.5, 1.0 }),
                        .high = .fromArray(.{ 0.5, 0.3, 0.3, 1.0 }),
                        .mid = .fromArray(.{ 0.5, 0.5, 0.3, 1.0 }),
                        .low = .fromArray(.{ 0.3, 0.35, 0.5, 1.0 }),
                        .special_low = .fromArray(.{ 0.3, 0.5, 0.5, 1.0 }),
                        .unblockable_high = .fromArray(.{ 0.5, 0.3, 0.3, 1.0 }),
                        .unblockable_mid = .fromArray(.{ 0.5, 0.5, 0.3, 1.0 }),
                        .unblockable_low = .fromArray(.{ 0.3, 0.35, 0.5, 1.0 }),
                        .throw = .fromArray(.{ 0.5, 0.5, 0.5, 1.0 }),
                        .projectile = .fromArray(.{ 0.35, 0.5, 0.35, 1.0 }),
                        .antiair_only = .fromArray(.{ 0.5, 0.35, 0.3, 1.0 }),
                    }),
                    .thickness = 1.0,
                },
                .outline = .{
                    .colors = std.EnumArray(model.AttackType, sdk.math.Vec4).init(.{
                        .not_attack = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                        .high = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                        .mid = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                        .low = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                        .special_low = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                        .unblockable_high = .fromArray(.{ 0.4, 0.3, 0.4, 1.0 }),
                        .unblockable_mid = .fromArray(.{ 0.4, 0.3, 0.4, 1.0 }),
                        .unblockable_low = .fromArray(.{ 0.4, 0.3, 0.4, 1.0 }),
                        .throw = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                        .projectile = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                        .antiair_only = .fromArray(.{ 0.0, 0.0, 0.0, 0.0 }),
                    }),
                    .thickness = 1.0,
                },
            },
            .duration = 1.0,
        },
        .look_direction = .{
            .color = sdk.math.Vec4.fromArray(.{ 1.0, 0.0, 1.0, 1.0 }),
            .length = 100.0,
            .thickness = 1.0,
        },
    };

    pub fn processFrame(self: *Self, frame: *const model.Frame) void {
        self.hurt_cylinders.processFrame(frame);
        self.processHitLines(.player_1, frame);
        self.processHitLines(.player_2, frame);
        self.frame = frame.*;
    }

    fn processHitLines(self: *Self, player_id: model.PlayerId, frame: *const model.Frame) void {
        const player = frame.getPlayerById(player_id);
        for (player.hit_lines.asConstSlice()) |*hit_line| {
            _ = self.lingering_hit_lines.addToBack(.{
                .line = hit_line.line,
                .player_id = player_id,
                .life_time = 0,
                .attack_type = player.attack_type,
                .inactive_or_crushed = hit_line.flags.is_inactive or hit_line.flags.is_crushed,
            });
        }
    }

    pub fn update(self: *Self, delta_time: f32) void {
        self.hurt_cylinders.update(delta_time);
        self.updateLingeringHitLines(delta_time);
    }

    fn updateLingeringHitLines(self: *Self, delta_time: f32) void {
        for (0..self.lingering_hit_lines.len) |index| {
            const cylinder = self.lingering_hit_lines.getMut(index) catch unreachable;
            cylinder.life_time += delta_time;
        }
        while (self.lingering_hit_lines.getFirst() catch null) |cylinder| {
            if (cylinder.life_time <= config.hit_lines.duration) {
                break;
            }
            _ = self.lingering_hit_lines.removeFirst() catch unreachable;
        }
    }

    pub fn draw(self: *Self, direction: ViewDirection) void {
        self.camera.updateWindowState(direction);
        const matrix = self.camera.calculateMatrix(&self.frame, direction) orelse return;
        const inverse_matrix = matrix.inverse() orelse sdk.math.Mat4.identity;
        ui.drawCollisionSpheres(&self.frame, matrix, inverse_matrix);
        self.hurt_cylinders.draw(&self.frame, direction, matrix, inverse_matrix);
        if (self.frame.floor_z) |floor_z| {
            ui.drawFloor(floor_z, config.floor.color, config.floor.thickness, direction, matrix);
        }
        self.drawLookAtLines(direction, matrix);
        ui.drawSkeletons(&self.frame, matrix);
        self.drawLingeringHitLines(matrix);
        self.drawHitLines(matrix);
    }

    fn drawHitLines(self: *const Self, matrix: sdk.math.Mat4) void {
        for (&self.frame.players) |*player| {
            for (player.hit_lines.asConstSlice()) |hit_line| {
                const color = if (hit_line.flags.is_inactive or hit_line.flags.is_crushed) block: {
                    break :block config.hit_lines.inactive_or_crushed.outline.colors.get(player.attack_type orelse .not_attack);
                } else block: {
                    break :block config.hit_lines.normal.outline.colors.get(player.attack_type orelse .not_attack);
                };
                const thickness: f32 = if (hit_line.flags.is_inactive or hit_line.flags.is_crushed) block: {
                    break :block config.hit_lines.inactive_or_crushed.fill.thickness +
                        2.0 * config.hit_lines.inactive_or_crushed.outline.thickness;
                } else block: {
                    break :block config.hit_lines.normal.fill.thickness +
                        2.0 * config.hit_lines.normal.outline.thickness;
                };
                const line = hit_line.line;
                ui.drawLine(line, color, thickness, matrix);
            }
        }
        for (&self.frame.players) |*player| {
            for (player.hit_lines.asConstSlice()) |hit_line| {
                const color = if (hit_line.flags.is_inactive or hit_line.flags.is_crushed) block: {
                    break :block config.hit_lines.inactive_or_crushed.fill.colors.get(player.attack_type orelse .not_attack);
                } else block: {
                    break :block config.hit_lines.normal.fill.colors.get(player.attack_type orelse .not_attack);
                };
                const thickness: f32 = if (hit_line.flags.is_inactive or hit_line.flags.is_crushed) block: {
                    break :block config.hit_lines.inactive_or_crushed.fill.thickness;
                } else block: {
                    break :block config.hit_lines.normal.fill.thickness;
                };
                const line = hit_line.line;
                ui.drawLine(line, color, thickness, matrix);
            }
        }
    }

    fn drawLingeringHitLines(self: *const Self, matrix: sdk.math.Mat4) void {
        for (0..self.lingering_hit_lines.len) |index| {
            const hit_line = self.lingering_hit_lines.get(index) catch unreachable;
            const line = hit_line.line;

            const duration = config.hit_lines.duration;
            const completion = hit_line.life_time / duration;
            var color = if (hit_line.inactive_or_crushed) block: {
                break :block config.hit_lines.inactive_or_crushed.outline.colors.get(hit_line.attack_type orelse .not_attack);
            } else block: {
                break :block config.hit_lines.normal.outline.colors.get(hit_line.attack_type orelse .not_attack);
            };
            color.asColor().a *= 1.0 - (completion * completion * completion * completion);
            const thickness: f32 = if (hit_line.inactive_or_crushed) block: {
                break :block config.hit_lines.inactive_or_crushed.fill.thickness +
                    2.0 * config.hit_lines.inactive_or_crushed.outline.thickness;
            } else block: {
                break :block config.hit_lines.normal.fill.thickness +
                    2.0 * config.hit_lines.normal.outline.thickness;
            };

            ui.drawLine(line, color, thickness, matrix);
        }
        for (0..self.lingering_hit_lines.len) |index| {
            const hit_line = self.lingering_hit_lines.get(index) catch unreachable;
            const line = hit_line.line;

            const duration = config.hit_lines.duration;
            const completion = hit_line.life_time / duration;
            var color = if (hit_line.inactive_or_crushed) block: {
                break :block config.hit_lines.inactive_or_crushed.fill.colors.get(hit_line.attack_type orelse .not_attack);
            } else block: {
                break :block config.hit_lines.normal.fill.colors.get(hit_line.attack_type orelse .not_attack);
            };
            color.asColor().a *= 1.0 - (completion * completion * completion * completion);
            const thickness: f32 = if (hit_line.inactive_or_crushed) block: {
                break :block config.hit_lines.inactive_or_crushed.fill.thickness;
            } else block: {
                break :block config.hit_lines.normal.fill.thickness;
            };

            ui.drawLine(line, color, thickness, matrix);
        }
    }

    fn drawLookAtLines(self: *const Self, direction: ViewDirection, matrix: sdk.math.Mat4) void {
        if (direction != .top) {
            return;
        }
        for (&self.frame.players) |*player| {
            const position = player.position orelse continue;
            const rotation = player.rotation orelse continue;
            const length = config.look_direction.length;
            const delta = sdk.math.Vec3.plus_x.scale(length).rotateZ(rotation);
            const line = sdk.math.LineSegment3{
                .point_1 = position,
                .point_2 = position.add(delta),
            };
            const color = config.look_direction.color;
            const thickness = config.look_direction.thickness;
            ui.drawLine(line, color, thickness, matrix);
        }
    }
};
