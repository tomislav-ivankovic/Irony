const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("../ui/root.zig");

pub const HitLines = struct {
    lingering: sdk.misc.CircularBuffer(128, LingeringLine) = .{},

    const Self = @This();
    const LingeringLine = struct {
        line: sdk.math.LineSegment3,
        player_id: model.PlayerId,
        life_time: f32,
        attack_type: ?model.AttackType,
        inactive_or_crushed: bool,
    };
    const config = struct {
        const normal = struct {
            const fill = struct {
                const colors = std.EnumArray(model.AttackType, sdk.math.Vec4).init(.{
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
                });
                const thickness = 1.0;
            };
            const outline = struct {
                const colors = std.EnumArray(model.AttackType, sdk.math.Vec4).init(.{
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
                });
                const thickness = 1.0;
            };
        };
        const inactive_or_crushed = struct {
            const fill = struct {
                const colors = std.EnumArray(model.AttackType, sdk.math.Vec4).init(.{
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
                });
                const thickness = 1.0;
            };
            const outline = struct {
                const colors = std.EnumArray(model.AttackType, sdk.math.Vec4).init(.{
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
                });
                const thickness = 1.0;
            };
        };
        const duration = 1.0;
    };

    pub fn processFrame(self: *Self, frame: *const model.Frame) void {
        for (model.PlayerId.all) |player_id| {
            const player = frame.getPlayerById(player_id);
            for (player.hit_lines.asConstSlice()) |*hit_line| {
                _ = self.lingering.addToBack(.{
                    .line = hit_line.line,
                    .player_id = player_id,
                    .life_time = 0,
                    .attack_type = player.attack_type,
                    .inactive_or_crushed = hit_line.flags.is_inactive or hit_line.flags.is_crushed,
                });
            }
        }
    }

    pub fn update(self: *Self, delta_time: f32) void {
        for (0..self.lingering.len) |index| {
            const cylinder = self.lingering.getMut(index) catch unreachable;
            cylinder.life_time += delta_time;
        }
        while (self.lingering.getFirst() catch null) |cylinder| {
            if (cylinder.life_time <= config.duration) {
                break;
            }
            _ = self.lingering.removeFirst() catch unreachable;
        }
    }

    pub fn draw(self: *Self, frame: *const model.Frame, matrix: sdk.math.Mat4) void {
        self.drawLingering(matrix);
        drawRegular(frame, matrix);
    }

    fn drawRegular(frame: *const model.Frame, matrix: sdk.math.Mat4) void {
        for (&frame.players) |*player| {
            for (player.hit_lines.asConstSlice()) |hit_line| {
                const color = if (hit_line.flags.is_inactive or hit_line.flags.is_crushed) block: {
                    break :block config.inactive_or_crushed.outline.colors.get(player.attack_type orelse .not_attack);
                } else block: {
                    break :block config.normal.outline.colors.get(player.attack_type orelse .not_attack);
                };
                const thickness: f32 = if (hit_line.flags.is_inactive or hit_line.flags.is_crushed) block: {
                    break :block config.inactive_or_crushed.fill.thickness +
                        2.0 * config.inactive_or_crushed.outline.thickness;
                } else block: {
                    break :block config.normal.fill.thickness +
                        2.0 * config.normal.outline.thickness;
                };
                const line = hit_line.line;
                ui.drawLine(line, color, thickness, matrix);
            }
        }
        for (&frame.players) |*player| {
            for (player.hit_lines.asConstSlice()) |hit_line| {
                const color = if (hit_line.flags.is_inactive or hit_line.flags.is_crushed) block: {
                    break :block config.inactive_or_crushed.fill.colors.get(player.attack_type orelse .not_attack);
                } else block: {
                    break :block config.normal.fill.colors.get(player.attack_type orelse .not_attack);
                };
                const thickness: f32 = if (hit_line.flags.is_inactive or hit_line.flags.is_crushed) block: {
                    break :block config.inactive_or_crushed.fill.thickness;
                } else block: {
                    break :block config.normal.fill.thickness;
                };
                const line = hit_line.line;
                ui.drawLine(line, color, thickness, matrix);
            }
        }
    }

    fn drawLingering(self: *const Self, matrix: sdk.math.Mat4) void {
        for (0..self.lingering.len) |index| {
            const hit_line = self.lingering.get(index) catch unreachable;
            const line = hit_line.line;

            const duration = config.duration;
            const completion = hit_line.life_time / duration;
            var color = if (hit_line.inactive_or_crushed) block: {
                break :block config.inactive_or_crushed.outline.colors.get(hit_line.attack_type orelse .not_attack);
            } else block: {
                break :block config.normal.outline.colors.get(hit_line.attack_type orelse .not_attack);
            };
            color.asColor().a *= 1.0 - (completion * completion * completion * completion);
            const thickness: f32 = if (hit_line.inactive_or_crushed) block: {
                break :block config.inactive_or_crushed.fill.thickness +
                    2.0 * config.inactive_or_crushed.outline.thickness;
            } else block: {
                break :block config.normal.fill.thickness +
                    2.0 * config.normal.outline.thickness;
            };

            ui.drawLine(line, color, thickness, matrix);
        }
        for (0..self.lingering.len) |index| {
            const hit_line = self.lingering.get(index) catch unreachable;
            const line = hit_line.line;

            const duration = config.duration;
            const completion = hit_line.life_time / duration;
            var color = if (hit_line.inactive_or_crushed) block: {
                break :block config.inactive_or_crushed.fill.colors.get(hit_line.attack_type orelse .not_attack);
            } else block: {
                break :block config.normal.fill.colors.get(hit_line.attack_type orelse .not_attack);
            };
            color.asColor().a *= 1.0 - (completion * completion * completion * completion);
            const thickness: f32 = if (hit_line.inactive_or_crushed) block: {
                break :block config.inactive_or_crushed.fill.thickness;
            } else block: {
                break :block config.normal.fill.thickness;
            };

            ui.drawLine(line, color, thickness, matrix);
        }
    }
};
