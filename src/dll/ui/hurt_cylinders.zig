const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("../ui/root.zig");

pub const HurtCylinders = struct {
    connected_life_time: std.EnumArray(model.PlayerId, std.EnumArray(model.HurtCylinderId, f32)) = .initFill(
        .initFill(std.math.inf(f32)),
    ),
    lingering: sdk.misc.CircularBuffer(32, LingeringCylinder) = .{},

    const Self = @This();
    pub const LingeringCylinder = struct {
        cylinder: sdk.math.Cylinder,
        player_id: model.PlayerId,
        life_time: f32,
    };
    const config = struct {
        const normal = struct {
            const color = sdk.math.Vec4.fromArray(.{ 0.5, 0.5, 0.5, 0.5 });
            const thickness = 1.0;
        };
        const high_crushing = struct {
            const color = sdk.math.Vec4.fromArray(.{ 0.75, 0.0, 0.0, 0.5 });
            const thickness = 1.0;
        };
        const low_crushing = struct {
            const color = sdk.math.Vec4.fromArray(.{ 0.0, 0.375, 0.75, 0.5 });
            const thickness = 1.0;
        };
        const invincible = struct {
            const color = sdk.math.Vec4.fromArray(.{ 0.75, 0.0, 0.75, 0.5 });
            const thickness = 1.0;
        };
        const power_crushing = struct {
            const normal = struct {
                const color = sdk.math.Vec4.fromArray(.{ 1.0, 1.0, 1.0, 1.0 });
                const thickness = 1.0;
            };
            const high_crushing = struct {
                const color = sdk.math.Vec4.fromArray(.{ 1.0, 0.25, 0.25, 1.0 });
                const thickness = 1.0;
            };
            const low_crushing = struct {
                const color = sdk.math.Vec4.fromArray(.{ 0.0, 0.25, 1.0, 1.0 });
                const thickness = 1.0;
            };
            const invincible = struct {
                const color = sdk.math.Vec4.fromArray(.{ 1.0, 0.0, 1.0, 1.0 });
                const thickness = 1.0;
            };
        };
        const connected = struct {
            const color = sdk.math.Vec4.fromArray(.{ 1.0, 0.75, 0.25, 0.5 });
            const thickness = 1.0;
            const duration = 1.0;
        };
        const lingering = struct {
            const color = sdk.math.Vec4.fromArray(.{ 0.0, 0.75, 0.75, 0.5 });
            const thickness = 1.0;
            const duration = 1.0;
        };
    };

    pub fn processFrame(self: *Self, frame: *const model.Frame) void {
        for (model.PlayerId.all) |player_id| {
            const player = frame.getPlayerById(player_id);
            const cylinders: *const model.HurtCylinders = if (player.hurt_cylinders) |*c| c else return;
            for (&cylinders.values, 0..) |*hurt_cylinder, index| {
                if (!hurt_cylinder.flags.is_connected) {
                    continue;
                }
                const cylinder_id = model.HurtCylinders.Indexer.keyForIndex(index);
                self.connected_life_time.getPtr(player_id).getPtr(cylinder_id).* = 0;
                _ = self.lingering.addToBack(.{
                    .cylinder = hurt_cylinder.cylinder,
                    .player_id = player_id,
                    .life_time = 0,
                });
            }
        }
    }

    pub fn update(self: *Self, delta_time: f32) void {
        self.updateRegular(delta_time);
        self.updateLingering(delta_time);
    }

    fn updateRegular(self: *Self, delta_time: f32) void {
        for (&self.connected_life_time.values) |*player_cylinders| {
            for (&player_cylinders.values) |*life_time| {
                life_time.* += delta_time;
            }
        }
    }

    fn updateLingering(self: *Self, delta_time: f32) void {
        for (0..self.lingering.len) |index| {
            const line = self.lingering.getMut(index) catch unreachable;
            line.life_time += delta_time;
        }
        while (self.lingering.getFirst() catch null) |line| {
            if (line.life_time <= config.lingering.duration) {
                break;
            }
            _ = self.lingering.removeFirst() catch unreachable;
        }
    }

    pub fn draw(
        self: *const Self,
        frame: *const model.Frame,
        direction: ui.ViewDirection,
        matrix: sdk.math.Mat4,
        inverse_matrix: sdk.math.Mat4,
    ) void {
        self.drawLingering(direction, matrix, inverse_matrix);
        self.drawRegular(frame, direction, matrix, inverse_matrix);
    }

    fn drawRegular(
        self: *const Self,
        frame: *const model.Frame,
        direction: ui.ViewDirection,
        matrix: sdk.math.Mat4,
        inverse_matrix: sdk.math.Mat4,
    ) void {
        for (model.PlayerId.all) |player_id| {
            const player = frame.getPlayerById(player_id);

            const crushing = player.crushing orelse model.Crushing{};
            const base_color: sdk.math.Vec4, const base_thickness: f32 = if (crushing.power_crushing) block: {
                if (crushing.invincibility) {
                    break :block .{
                        config.power_crushing.invincible.color,
                        config.power_crushing.invincible.thickness,
                    };
                } else if (crushing.high_crushing) {
                    break :block .{
                        config.power_crushing.high_crushing.color,
                        config.power_crushing.high_crushing.thickness,
                    };
                } else if (crushing.low_crushing) {
                    break :block .{
                        config.power_crushing.low_crushing.color,
                        config.power_crushing.low_crushing.thickness,
                    };
                } else {
                    break :block .{
                        config.power_crushing.normal.color,
                        config.power_crushing.normal.thickness,
                    };
                }
            } else block: {
                if (crushing.invincibility) {
                    break :block .{
                        config.invincible.color,
                        config.invincible.thickness,
                    };
                } else if (crushing.high_crushing) {
                    break :block .{
                        config.high_crushing.color,
                        config.high_crushing.thickness,
                    };
                } else if (crushing.low_crushing) {
                    break :block .{
                        config.low_crushing.color,
                        config.low_crushing.thickness,
                    };
                } else {
                    break :block .{
                        config.normal.color,
                        config.normal.thickness,
                    };
                }
            };

            const cylinders: *const model.HurtCylinders = if (player.hurt_cylinders) |*c| c else continue;
            for (cylinders.values, 0..) |hurt_cylinder, index| {
                const cylinder = hurt_cylinder.cylinder;
                const cylinder_id = model.HurtCylinders.Indexer.keyForIndex(index);

                const life_time = self.connected_life_time.getPtrConst(player_id).get(cylinder_id);
                const duration = config.connected.duration;
                const completion: f32 = if (hurt_cylinder.flags.is_connected) 0.0 else block: {
                    break :block std.math.clamp(life_time / duration, 0.0, 1.0);
                };
                const t = completion * completion * completion * completion;
                const connected_color = config.connected.color;
                const color = sdk.math.Vec4.lerpElements(connected_color, base_color, t);
                const connected_thickness = config.connected.thickness;
                const thickness = std.math.lerp(connected_thickness, base_thickness, t);

                ui.drawCylinder(cylinder, color, thickness, direction, matrix, inverse_matrix);
            }
        }
    }

    fn drawLingering(
        self: *const Self,
        direction: ui.ViewDirection,
        matrix: sdk.math.Mat4,
        inverse_matrix: sdk.math.Mat4,
    ) void {
        for (0..self.lingering.len) |index| {
            const hurt_cylinder = self.lingering.get(index) catch unreachable;
            const cylinder = hurt_cylinder.cylinder;

            const duration = config.lingering.duration;
            const completion = hurt_cylinder.life_time / duration;
            var color = config.lingering.color;
            color.asColor().a *= 1.0 - (completion * completion * completion * completion);
            const thickness = config.lingering.thickness;

            ui.drawCylinder(cylinder, color, thickness, direction, matrix, inverse_matrix);
        }
    }
};
