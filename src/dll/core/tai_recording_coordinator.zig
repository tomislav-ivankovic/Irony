const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const core = @import("../core/root.zig");
const model = @import("../model/root.zig");

pub const TaiRecordingCoordinator = struct {
    mode: Mode = .do_not_record,
    previous_tai_mode: TaiMode = .idle,

    const Self = @This();
    pub const Mode = enum {
        do_not_record,
        only_record,
        clear_and_record,
    };
    const TaiMode = enum {
        idle,
        play,
    };

    pub fn processFrame(self: *Self, tai: *const core.ToolAssistedInput, controller: anytype) void {
        if (@typeInfo(@TypeOf(controller)) != .pointer) {
            @compileError(
                "Expecting the controller to be passed by reference but got type: " ++ @typeName(@TypeOf(controller)),
            );
        }
        const tai_mode: TaiMode = switch (tai.mode) {
            .idle => .idle,
            .play => .play,
        };
        defer self.previous_tai_mode = tai_mode;
        if (tai_mode == self.previous_tai_mode) {
            return;
        }
        switch (tai_mode) {
            .idle => {
                switch (self.mode) {
                    .do_not_record => {},
                    .only_record, .clear_and_record => {
                        if (controller.mode == .record) {
                            controller.pause();
                        }
                    },
                }
            },
            .play => {
                switch (self.mode) {
                    .do_not_record => {},
                    .only_record => {
                        controller.record();
                    },
                    .clear_and_record => {
                        controller.clear();
                        controller.record();
                    },
                }
            },
        }
    }
};

const testing = std.testing;

const MockController = struct {
    mode: Mode,
    clear_call_count: usize = 0,
    record_call_count: usize = 0,
    pause_call_count: usize = 0,

    const Self = @This();
    pub const Mode = enum {
        live,
        record,
        pause,
        playback,
        scrub,
        load,
        save,
    };

    pub fn clear(self: *Self) void {
        self.clear_call_count += 1;
    }

    pub fn record(self: *Self) void {
        self.record_call_count += 1;
        self.mode = .record;
    }

    pub fn pause(self: *Self) void {
        self.pause_call_count += 1;
        self.mode = .pause;
    }
};

test "should do nothing when in do not record mode" {
    var coordinator = TaiRecordingCoordinator{ .mode = .do_not_record };
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.append(tai.allocator, .{});
    var controller = MockController{ .mode = .pause };

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(0, controller.clear_call_count);
    try testing.expectEqual(0, controller.record_call_count);
    try testing.expectEqual(0, controller.pause_call_count);

    tai.play();

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(0, controller.clear_call_count);
    try testing.expectEqual(0, controller.record_call_count);
    try testing.expectEqual(0, controller.pause_call_count);

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(0, controller.clear_call_count);
    try testing.expectEqual(0, controller.record_call_count);
    try testing.expectEqual(0, controller.pause_call_count);

    tai.stop();

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(0, controller.clear_call_count);
    try testing.expectEqual(0, controller.record_call_count);
    try testing.expectEqual(0, controller.pause_call_count);

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(0, controller.clear_call_count);
    try testing.expectEqual(0, controller.record_call_count);
    try testing.expectEqual(0, controller.pause_call_count);
}

test "should start and stop recording when in only record mode" {
    var coordinator = TaiRecordingCoordinator{ .mode = .only_record };
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.append(tai.allocator, .{});
    var controller = MockController{ .mode = .pause };

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(0, controller.clear_call_count);
    try testing.expectEqual(0, controller.record_call_count);
    try testing.expectEqual(0, controller.pause_call_count);

    tai.play();

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(0, controller.clear_call_count);
    try testing.expectEqual(1, controller.record_call_count);
    try testing.expectEqual(0, controller.pause_call_count);

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(0, controller.clear_call_count);
    try testing.expectEqual(1, controller.record_call_count);
    try testing.expectEqual(0, controller.pause_call_count);

    tai.stop();

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(0, controller.clear_call_count);
    try testing.expectEqual(1, controller.record_call_count);
    try testing.expectEqual(1, controller.pause_call_count);

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(0, controller.clear_call_count);
    try testing.expectEqual(1, controller.record_call_count);
    try testing.expectEqual(1, controller.pause_call_count);
}

test "should clear, start and stop recording when in clear and record mode" {
    var coordinator = TaiRecordingCoordinator{ .mode = .clear_and_record };
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.append(tai.allocator, .{});
    var controller = MockController{ .mode = .pause };

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(0, controller.clear_call_count);
    try testing.expectEqual(0, controller.record_call_count);
    try testing.expectEqual(0, controller.pause_call_count);

    tai.play();

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(1, controller.clear_call_count);
    try testing.expectEqual(1, controller.record_call_count);
    try testing.expectEqual(0, controller.pause_call_count);

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(1, controller.clear_call_count);
    try testing.expectEqual(1, controller.record_call_count);
    try testing.expectEqual(0, controller.pause_call_count);

    tai.stop();

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(1, controller.clear_call_count);
    try testing.expectEqual(1, controller.record_call_count);
    try testing.expectEqual(1, controller.pause_call_count);

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(1, controller.clear_call_count);
    try testing.expectEqual(1, controller.record_call_count);
    try testing.expectEqual(1, controller.pause_call_count);
}

test "should not stop recording when controller is not in record mode" {
    var coordinator = TaiRecordingCoordinator{ .mode = .clear_and_record };
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.append(tai.allocator, .{});
    var controller = MockController{ .mode = .pause };

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(0, controller.clear_call_count);
    try testing.expectEqual(0, controller.record_call_count);
    try testing.expectEqual(0, controller.pause_call_count);

    tai.play();

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(1, controller.clear_call_count);
    try testing.expectEqual(1, controller.record_call_count);
    try testing.expectEqual(0, controller.pause_call_count);

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(1, controller.clear_call_count);
    try testing.expectEqual(1, controller.record_call_count);
    try testing.expectEqual(0, controller.pause_call_count);

    tai.stop();
    controller.mode = .pause;

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(1, controller.clear_call_count);
    try testing.expectEqual(1, controller.record_call_count);
    try testing.expectEqual(0, controller.pause_call_count);

    coordinator.processFrame(&tai, &controller);
    try testing.expectEqual(1, controller.clear_call_count);
    try testing.expectEqual(1, controller.record_call_count);
    try testing.expectEqual(0, controller.pause_call_count);
}
