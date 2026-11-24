const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("../ui/root.zig");

pub const Projectiles = struct {
    lingering: sdk.misc.CircularBuffer(128, LingeringProjectile) = .{},

    const Self = @This();
    const LingeringProjectile = struct {
        projectile: model.Projectile,
        player_id: model.PlayerId,
        remaining_time: f32,
    };
    const Pass = enum { volumes, outlines, lines };

    pub fn processFrame(
        self: *Self,
        settings: *const model.PlayerSettings(model.HitLinesSettings),
        frame: *const model.Frame,
    ) void {
        for (model.PlayerId.all) |player_id| {
            const player_settings = settings.getById(frame, player_id);
            if (!player_settings.enabled) {
                continue;
            }
            const player = frame.getPlayerById(player_id);
            const projectiles: []const model.Projectile = player.projectiles.asSlice();
            for (projectiles) |*projectile| {
                const lingers = switch (player_settings.projectile_lingering) {
                    .off => false,
                    .on_connect => projectile.flags.is_connected,
                    .always => true,
                };
                if (lingers) {
                    _ = self.lingering.addToBack(.{
                        .projectile = projectile.*,
                        .player_id = player_id,
                        .remaining_time = player_settings.duration,
                    });
                }
            }
        }
    }

    pub fn update(self: *Self, delta_time: f32) void {
        for (0..self.lingering.len) |index| {
            const lingering = self.lingering.get(index) catch unreachable;
            lingering.remaining_time -= delta_time;
        }
        while (self.lingering.getFirst() catch null) |lingering| {
            if (lingering.remaining_time > 0.0) {
                break;
            }
            _ = self.lingering.removeFirst() catch unreachable;
        }
    }

    pub fn draw(
        self: *const Self,
        shapes: *const ui.Shapes,
        settings: *const model.PlayerSettings(model.HitLinesSettings),
        frame: *const model.Frame,
    ) void {
        for (std.enums.values(Pass)) |pass| {
            for (0..self.lingering.len) |index| {
                const lingering = self.lingering.get(index) catch unreachable;
                const player_settings = settings.getById(frame, lingering.player_id);
                const completion = 1.0 - (lingering.remaining_time / player_settings.duration);
                const alpha = 1.0 - (completion * completion * completion * completion);
                drawProjectile(shapes, pass, player_settings, &lingering.projectile, alpha);
            }
            for (model.PlayerId.all) |player_id| {
                const player_settings = settings.getById(frame, player_id);
                const player = frame.getPlayerById(player_id);
                for (player.projectiles.asSlice()) |*projectile| {
                    drawProjectile(shapes, pass, player_settings, projectile, 1);
                }
            }
        }
    }

    fn drawProjectile(
        shapes: *const ui.Shapes,
        pass: Pass,
        player_settings: *const model.HitLinesSettings,
        projectile: *const model.Projectile,
        alpha: f32,
    ) void {
        if (!player_settings.enabled) {
            return;
        }
        const projectile_settings = switch (projectile.flags.is_inactive or projectile.flags.is_crushed) {
            true => &player_settings.inactive_or_crushed,
            false => &player_settings.normal,
        };
        if (!projectile_settings.enabled) {
            return;
        }
        const attack_type = projectile.attack_type orelse .not_attack;
        var fill_color = projectile_settings.fill.colors.get(attack_type);
        fill_color.asColor().a *= alpha;
        var outline_color = projectile_settings.outline.colors.get(attack_type);
        outline_color.asColor().a *= alpha;
        const thickness = projectile_settings.fill.thickness;
        switch (pass) {
            .volumes => switch (projectile.shape) {
                .line => |*swept_cylinder| {
                    const is_thick = swept_cylinder.radius > 0 or swept_cylinder.half_height > 0;
                    if (player_settings.volume.enabled and is_thick) {
                        shapes.drawSweptCylinder(swept_cylinder.*, fill_color, player_settings.volume.thickness);
                    }
                },
                .sphere => |*sphere| shapes.drawSphere(sphere.*, fill_color, thickness),
                .cylinder => |*cylinder| shapes.drawCylinder(cylinder.*, fill_color, thickness),
                .box => |*box| shapes.drawBox(box.*, fill_color, thickness),
            },
            .outlines => switch (projectile.shape) {
                .line => |*swept_cylinder| {
                    const outline_thickness = thickness + (2.0 * projectile_settings.outline.thickness);
                    shapes.drawOutline(swept_cylinder.line, outline_color, outline_thickness, 0);
                },
                else => {},
            },
            .lines => switch (projectile.shape) {
                .line => |*swept_cylinder| shapes.drawLine(swept_cylinder.line, fill_color, thickness, 0),
                else => {},
            },
        }
    }
};

const testing = std.testing;

test "should draw regular projectiles correctly" {
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();

    var projectiles: Projectiles = .{};
    const shapes = ui.Shapes{ ._void = .{} };
    const settings = model.PlayerSettings(model.HitLinesSettings){
        .mode = .id_separated,
        .players = .{
            .{
                .enabled = true,
                .normal = .{
                    .enabled = true,
                    .fill = .{ .colors = .initFill(.fill(0.1)), .thickness = 1 },
                    .outline = .{ .colors = .initFill(.fill(0.2)), .thickness = 2 },
                },
                .volume = .{ .enabled = true, .thickness = 3 },
            },
            .{
                .enabled = true,
                .normal = .{
                    .enabled = false,
                    .fill = .{ .colors = .initFill(.fill(0.3)), .thickness = 4 },
                    .outline = .{ .colors = .initFill(.fill(0.4)), .thickness = 5 },
                },
            },
        },
    };
    const frame = model.Frame{ .players = .{
        .{ .projectiles = .fromArray(.{
            model.Projectile{ .shape = .{ .line = .{
                .line = .{ .point_1 = .fill(1), .point_2 = .fill(2) },
                .radius = 0,
                .half_height = 0,
            } } },
            model.Projectile{ .shape = .{ .line = .{
                .line = .{ .point_1 = .fill(3), .point_2 = .fill(4) },
                .radius = 0.5,
                .half_height = 0.25,
            } } },
            model.Projectile{ .shape = .{ .sphere = .{ .center = .fill(5), .radius = 1 } } },
            model.Projectile{ .shape = .{ .cylinder = .{ .center = .fill(6), .radius = 1, .half_height = 2 } } },
            model.Projectile{ .shape = .{ .box = .{ .center = .fill(7), .half_size = .fill(1), .rotation = 0 } } },
        }) },
        .{ .projectiles = .fromArray(.{
            model.Projectile{ .shape = .{ .sphere = .{ .center = .fill(-1), .radius = 1 } } },
        }) },
    } };
    projectiles.draw(&shapes, &settings, &frame);

    try testing.expectEqual(8, ui.testing_shapes.getAll().len);
    for ([_][2]f32{ .{ 1, 2 }, .{ 3, 4 } }) |points| {
        const line = ui.testing_shapes.findLineWithWorldPoints(.fill(points[0]), .fill(points[1]), 0.0001);
        try testing.expect(line != null);
        try testing.expectEqual(sdk.math.Vec4.fill(0.1), line.?.color);
        try testing.expectEqual(1, line.?.thickness);
        const outline = ui.testing_shapes.findOutlineWithWorldPoints(.fill(points[0]), .fill(points[1]), 0.0001);
        try testing.expect(outline != null);
        try testing.expectEqual(sdk.math.Vec4.fill(0.2), outline.?.color);
        try testing.expectEqual(5, outline.?.thickness);
    }
    try testing.expectEqual(null, ui.testing_shapes.findSweptCylinderWithWorldPoints(.fill(1), .fill(2), 0.0001));
    const swept_cylinder = ui.testing_shapes.findSweptCylinderWithWorldPoints(.fill(3), .fill(4), 0.0001);
    try testing.expect(swept_cylinder != null);
    try testing.expectEqual(sdk.math.Vec4.fill(0.1), swept_cylinder.?.color);
    try testing.expectEqual(3, swept_cylinder.?.thickness);
    const sphere = ui.testing_shapes.findSphereWithWorldCenter(.fill(5), 0.0001);
    try testing.expect(sphere != null);
    try testing.expectEqual(sdk.math.Vec4.fill(0.1), sphere.?.color);
    try testing.expectEqual(1, sphere.?.thickness);
    const cylinder = ui.testing_shapes.findCylinderWithWorldCenter(.fill(6), 0.0001);
    try testing.expect(cylinder != null);
    try testing.expectEqual(sdk.math.Vec4.fill(0.1), cylinder.?.color);
    try testing.expectEqual(1, cylinder.?.thickness);
    const box = ui.testing_shapes.findBoxWithWorldCenter(.fill(7), 0.0001);
    try testing.expect(box != null);
    try testing.expectEqual(sdk.math.Vec4.fill(0.1), box.?.color);
    try testing.expectEqual(1, box.?.thickness);
    try testing.expectEqual(null, ui.testing_shapes.findSphereWithWorldCenter(.fill(-1), 0.0001));
}

test "should draw lingering projectiles correctly" {
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();

    var projectiles: Projectiles = .{};
    const shapes = ui.Shapes{ ._void = .{} };
    const settings = model.PlayerSettings(model.HitLinesSettings){
        .mode = .id_separated,
        .players = .{
            .{
                .enabled = true,
                .normal = .{
                    .enabled = true,
                    .fill = .{ .colors = .initFill(.fill(0.1)), .thickness = 1 },
                    .outline = .{ .colors = .initFill(.fill(0.2)), .thickness = 2 },
                },
                .projectile_lingering = .always,
                .duration = 10,
            },
            .{},
        },
    };
    var frame = model.Frame{ .players = .{
        .{ .projectiles = .fromArray(.{
            model.Projectile{ .shape = .{ .sphere = .{ .center = .fill(1), .radius = 1 } } },
        }) },
        .{},
    } };
    projectiles.processFrame(&settings, &frame);
    frame.players[0].projectiles = .empty;

    ui.testing_shapes.clear();
    projectiles.draw(&shapes, &settings, &frame);
    try testing.expectEqual(1, ui.testing_shapes.getAll().len);
    var sphere = ui.testing_shapes.findSphereWithWorldCenter(.fill(1), 0.0001);
    try testing.expect(sphere != null);
    try testing.expectApproxEqAbs(0.1, sphere.?.color.r(), 0.0001);
    try testing.expectApproxEqAbs(0.1, sphere.?.color.a(), 0.0001);
    try testing.expectEqual(1, sphere.?.thickness);

    ui.testing_shapes.clear();
    projectiles.update(8);
    projectiles.draw(&shapes, &settings, &frame);
    try testing.expectEqual(1, ui.testing_shapes.getAll().len);
    sphere = ui.testing_shapes.findSphereWithWorldCenter(.fill(1), 0.0001);
    try testing.expect(sphere != null);
    try testing.expectApproxEqAbs(0.1, sphere.?.color.r(), 0.0001);
    try testing.expectApproxEqAbs(0.05, sphere.?.color.a(), 0.04);

    ui.testing_shapes.clear();
    projectiles.update(3);
    projectiles.draw(&shapes, &settings, &frame);
    try testing.expectEqual(0, ui.testing_shapes.getAll().len);
}

test "should linger projectiles depending on projectile lingering setting" {
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();

    var projectiles: Projectiles = .{};
    const shapes = ui.Shapes{ ._void = .{} };
    const settings = model.PlayerSettings(model.HitLinesSettings){
        .mode = .id_separated,
        .players = .{
            .{ .projectile_lingering = .on_connect, .duration = 10 },
            .{ .projectile_lingering = .off, .duration = 10 },
        },
    };
    var frame = model.Frame{ .players = .{
        .{ .projectiles = .fromArray(.{
            model.Projectile{
                .shape = .{ .sphere = .{ .center = .fill(1), .radius = 1 } },
                .flags = .{ .is_intersecting = true, .is_connected = true },
            },
            model.Projectile{ .shape = .{ .sphere = .{ .center = .fill(2), .radius = 1 } } },
        }) },
        .{ .projectiles = .fromArray(.{
            model.Projectile{
                .shape = .{ .sphere = .{ .center = .fill(-1), .radius = 1 } },
                .flags = .{ .is_intersecting = true, .is_connected = true },
            },
        }) },
    } };
    projectiles.processFrame(&settings, &frame);
    frame.players[0].projectiles = .empty;
    frame.players[1].projectiles = .empty;

    ui.testing_shapes.clear();
    projectiles.draw(&shapes, &settings, &frame);
    try testing.expectEqual(1, ui.testing_shapes.getAll().len);
    try testing.expect(ui.testing_shapes.findSphereWithWorldCenter(.fill(1), 0.0001) != null);
    try testing.expectEqual(null, ui.testing_shapes.findSphereWithWorldCenter(.fill(2), 0.0001));
    try testing.expectEqual(null, ui.testing_shapes.findSphereWithWorldCenter(.fill(-1), 0.0001));
}

test "should not draw projectiles for the player disabled in settings" {
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();

    var projectiles: Projectiles = .{};
    const shapes = ui.Shapes{ ._void = .{} };
    const settings = model.PlayerSettings(model.HitLinesSettings){
        .mode = .id_separated,
        .players = .{
            .{ .enabled = true, .projectile_lingering = .always },
            .{ .enabled = false, .projectile_lingering = .always },
        },
    };
    var frame = model.Frame{ .players = .{
        .{ .projectiles = .fromArray(.{
            model.Projectile{ .shape = .{ .sphere = .{ .center = .fill(1), .radius = 1 } } },
            model.Projectile{ .shape = .{ .cylinder = .{ .center = .fill(2), .radius = 1, .half_height = 2 } } },
        }) },
        .{ .projectiles = .fromArray(.{
            model.Projectile{ .shape = .{ .sphere = .{ .center = .fill(-1), .radius = 1 } } },
            model.Projectile{ .shape = .{ .cylinder = .{ .center = .fill(-2), .radius = 1, .half_height = 2 } } },
        }) },
    } };

    ui.testing_shapes.clear();
    projectiles.draw(&shapes, &settings, &frame);
    try testing.expectEqual(2, ui.testing_shapes.getAll().len);
    try testing.expect(ui.testing_shapes.findSphereWithWorldCenter(.fill(1), 0.0001) != null);
    try testing.expect(ui.testing_shapes.findCylinderWithWorldCenter(.fill(2), 0.0001) != null);
    try testing.expectEqual(null, ui.testing_shapes.findSphereWithWorldCenter(.fill(-1), 0.0001));
    try testing.expectEqual(null, ui.testing_shapes.findCylinderWithWorldCenter(.fill(-2), 0.0001));

    ui.testing_shapes.clear();
    projectiles.processFrame(&settings, &frame);
    frame.players[0].projectiles = .empty;
    projectiles.draw(&shapes, &settings, &frame);
    try testing.expectEqual(2, ui.testing_shapes.getAll().len);
    try testing.expect(ui.testing_shapes.findSphereWithWorldCenter(.fill(1), 0.0001) != null);
    try testing.expect(ui.testing_shapes.findCylinderWithWorldCenter(.fill(2), 0.0001) != null);
    try testing.expectEqual(null, ui.testing_shapes.findSphereWithWorldCenter(.fill(-1), 0.0001));
    try testing.expectEqual(null, ui.testing_shapes.findCylinderWithWorldCenter(.fill(-2), 0.0001));
}

test "should draw with correct color and thickness depending on attack type, inactivity and crushing" {
    ui.testing_shapes.begin(testing.allocator);
    defer ui.testing_shapes.end();

    var projectiles: Projectiles = .{};
    const shapes = ui.Shapes{ ._void = .{} };
    const settings = model.PlayerSettings(model.HitLinesSettings){
        .mode = .id_separated,
        .players = .{
            .{
                .enabled = true,
                .normal = .{
                    .enabled = true,
                    .fill = .{
                        .colors = .init(.{
                            .not_attack = .fill(0.01),
                            .high = .fill(0.02),
                            .mid = .fill(0.03),
                            .low = .fill(0.04),
                            .special_low = .fill(0.05),
                            .unblockable_high = .fill(0.06),
                            .unblockable_mid = .fill(0.07),
                            .unblockable_low = .fill(0.08),
                            .throw = .fill(0.09),
                            .projectile = .fill(0.10),
                            .antiair_only = .fill(0.11),
                        }),
                        .thickness = 1,
                    },
                    .outline = .{
                        .colors = .init(.{
                            .not_attack = .fill(0.12),
                            .high = .fill(0.13),
                            .mid = .fill(0.14),
                            .low = .fill(0.15),
                            .special_low = .fill(0.16),
                            .unblockable_high = .fill(0.17),
                            .unblockable_mid = .fill(0.18),
                            .unblockable_low = .fill(0.19),
                            .throw = .fill(0.20),
                            .projectile = .fill(0.21),
                            .antiair_only = .fill(0.22),
                        }),
                        .thickness = 2,
                    },
                },
                .inactive_or_crushed = .{
                    .enabled = true,
                    .fill = .{
                        .colors = .init(.{
                            .not_attack = .fill(0.23),
                            .high = .fill(0.24),
                            .mid = .fill(0.25),
                            .low = .fill(0.26),
                            .special_low = .fill(0.27),
                            .unblockable_high = .fill(0.28),
                            .unblockable_mid = .fill(0.29),
                            .unblockable_low = .fill(0.30),
                            .throw = .fill(0.31),
                            .projectile = .fill(0.32),
                            .antiair_only = .fill(0.33),
                        }),
                        .thickness = 3,
                    },
                    .outline = .{
                        .colors = .init(.{
                            .not_attack = .fill(0.34),
                            .high = .fill(0.35),
                            .mid = .fill(0.36),
                            .low = .fill(0.37),
                            .special_low = .fill(0.38),
                            .unblockable_high = .fill(0.39),
                            .unblockable_mid = .fill(0.40),
                            .unblockable_low = .fill(0.41),
                            .throw = .fill(0.42),
                            .projectile = .fill(0.43),
                            .antiair_only = .fill(0.44),
                        }),
                        .thickness = 4,
                    },
                },
                .projectile_lingering = .always,
                .duration = 10,
            },
            .{},
        },
    };
    var frame = model.Frame{ .players = .{
        .{ .projectiles = .fromArray(.{
            model.Projectile{ .shape = .{ .line = .{
                .line = .{ .point_1 = .fill(1), .point_2 = .fill(2) },
                .radius = 0,
                .half_height = 0,
            } } },
        }) },
        .{},
    } };
    const projectile = &frame.players[0].projectiles.asSlice()[0];

    ui.testing_shapes.clear();
    projectiles.draw(&shapes, &settings, &frame);
    var line = ui.testing_shapes.findLineWithWorldPoints(.fill(1), .fill(2), 0.0001);
    var outline = ui.testing_shapes.findOutlineWithWorldPoints(.fill(1), .fill(2), 0.0001);
    try testing.expect(line != null);
    try testing.expectEqual(sdk.math.Vec4.fill(0.01), line.?.color);
    try testing.expectEqual(1, line.?.thickness);
    try testing.expect(outline != null);
    try testing.expectEqual(sdk.math.Vec4.fill(0.12), outline.?.color);
    try testing.expectEqual(5, outline.?.thickness);

    ui.testing_shapes.clear();
    projectile.attack_type = .mid;
    projectiles.draw(&shapes, &settings, &frame);
    line = ui.testing_shapes.findLineWithWorldPoints(.fill(1), .fill(2), 0.0001);
    outline = ui.testing_shapes.findOutlineWithWorldPoints(.fill(1), .fill(2), 0.0001);
    try testing.expect(line != null);
    try testing.expectEqual(sdk.math.Vec4.fill(0.03), line.?.color);
    try testing.expectEqual(1, line.?.thickness);
    try testing.expect(outline != null);
    try testing.expectEqual(sdk.math.Vec4.fill(0.14), outline.?.color);
    try testing.expectEqual(5, outline.?.thickness);

    ui.testing_shapes.clear();
    projectile.flags.is_inactive = true;
    projectiles.draw(&shapes, &settings, &frame);
    line = ui.testing_shapes.findLineWithWorldPoints(.fill(1), .fill(2), 0.0001);
    outline = ui.testing_shapes.findOutlineWithWorldPoints(.fill(1), .fill(2), 0.0001);
    try testing.expect(line != null);
    try testing.expectEqual(sdk.math.Vec4.fill(0.25), line.?.color);
    try testing.expectEqual(3, line.?.thickness);
    try testing.expect(outline != null);
    try testing.expectEqual(sdk.math.Vec4.fill(0.36), outline.?.color);
    try testing.expectEqual(11, outline.?.thickness);

    ui.testing_shapes.clear();
    projectile.attack_type = .high;
    projectiles.draw(&shapes, &settings, &frame);
    line = ui.testing_shapes.findLineWithWorldPoints(.fill(1), .fill(2), 0.0001);
    outline = ui.testing_shapes.findOutlineWithWorldPoints(.fill(1), .fill(2), 0.0001);
    try testing.expect(line != null);
    try testing.expectEqual(sdk.math.Vec4.fill(0.24), line.?.color);
    try testing.expectEqual(3, line.?.thickness);
    try testing.expect(outline != null);
    try testing.expectEqual(sdk.math.Vec4.fill(0.35), outline.?.color);
    try testing.expectEqual(11, outline.?.thickness);

    ui.testing_shapes.clear();
    projectile.flags.is_inactive = false;
    projectiles.draw(&shapes, &settings, &frame);
    line = ui.testing_shapes.findLineWithWorldPoints(.fill(1), .fill(2), 0.0001);
    outline = ui.testing_shapes.findOutlineWithWorldPoints(.fill(1), .fill(2), 0.0001);
    try testing.expect(line != null);
    try testing.expectEqual(sdk.math.Vec4.fill(0.02), line.?.color);
    try testing.expectEqual(1, line.?.thickness);
    try testing.expect(outline != null);
    try testing.expectEqual(sdk.math.Vec4.fill(0.13), outline.?.color);
    try testing.expectEqual(5, outline.?.thickness);

    ui.testing_shapes.clear();
    projectile.attack_type = .low;
    frame.players[0].projectiles.len = 1;
    projectiles.processFrame(&settings, &frame);
    frame.players[0].projectiles.len = 0;
    projectiles.draw(&shapes, &settings, &frame);
    line = ui.testing_shapes.findLineWithWorldPoints(.fill(1), .fill(2), 0.0001);
    outline = ui.testing_shapes.findOutlineWithWorldPoints(.fill(1), .fill(2), 0.0001);
    try testing.expect(line != null);
    try testing.expectEqual(sdk.math.Vec4.fill(0.04), line.?.color);
    try testing.expectEqual(1, line.?.thickness);
    try testing.expect(outline != null);
    try testing.expectEqual(sdk.math.Vec4.fill(0.15), outline.?.color);
    try testing.expectEqual(5, outline.?.thickness);

    ui.testing_shapes.clear();
    projectiles.update(100);
    projectile.flags.is_crushed = true;
    frame.players[0].projectiles.len = 1;
    projectiles.processFrame(&settings, &frame);
    frame.players[0].projectiles.len = 0;
    projectiles.draw(&shapes, &settings, &frame);
    line = ui.testing_shapes.findLineWithWorldPoints(.fill(1), .fill(2), 0.0001);
    outline = ui.testing_shapes.findOutlineWithWorldPoints(.fill(1), .fill(2), 0.0001);
    try testing.expect(line != null);
    try testing.expectEqual(sdk.math.Vec4.fill(0.26), line.?.color);
    try testing.expectEqual(3, line.?.thickness);
    try testing.expect(outline != null);
    try testing.expectEqual(sdk.math.Vec4.fill(0.37), outline.?.color);
    try testing.expectEqual(11, outline.?.thickness);
}
