const model = @import("../../model/root.zig");
const t7 = @import("root.zig");

pub const FrameDetectCapturer = struct {
    detector: t7.FrameDetector = .{},

    const Self = @This();

    pub fn detectAndCaptureFrame(self: *Self, memory: *const t7.Memory) ?model.Frame {
        const player_1 = memory.player_1.takePartialCopy();
        const player_2 = memory.player_2.takePartialCopy();
        if (!self.detector.detect(&player_1, &player_2)) {
            return null;
        }
        return .{}; // TODO Capture frame.
    }
};
