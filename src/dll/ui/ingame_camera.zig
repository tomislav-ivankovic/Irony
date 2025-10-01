const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const ui = @import("../ui/root.zig");

const color = sdk.math.Vec4.fromArray(.{ 1.0, 1.0, 1.0, 0.125 });
const length = 1000.0;
const thickness = 1.0;

pub fn drawIngameCamera(frame: *const model.Frame, direction: ui.ViewDirection, matrix: sdk.math.Mat4) void {
    if (direction != .top) {
        return;
    }
    const camera = if (frame.camera) |*c| c else return;
    const offset_1 = sdk.math.Vec3.plus_x.rotateZ(camera.yaw + (0.5 * camera.fov)).scale(length);
    const offset_2 = sdk.math.Vec3.plus_x.rotateZ(camera.yaw - (0.5 * camera.fov)).scale(length);
    const line_1 = sdk.math.LineSegment3{ .point_1 = camera.position, .point_2 = camera.position.add(offset_1) };
    const line_2 = sdk.math.LineSegment3{ .point_1 = camera.position, .point_2 = camera.position.add(offset_2) };
    ui.drawLine(line_1, color, thickness, matrix);
    ui.drawLine(line_2, color, thickness, matrix);
}
