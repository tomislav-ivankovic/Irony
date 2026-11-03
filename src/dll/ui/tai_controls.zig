const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const core = @import("../core/root.zig");
const ui = @import("root.zig");

pub const TaiControls = struct {
    enable_player_1: bool = true,
    enable_player_2: bool = true,
    play_only_selection: bool = false,
    repeat: bool = false,
    record_mode: core.TaiRecordingCoordinator.Mode = .do_not_record,

    const Self = @This();
    const toggled_on_color = imgui.ImVec4{ .x = 0, .y = 0.4, .z = 0, .w = 1 };
    const window_route = imgui.ImGuiInputFlags_RouteFocused | imgui.ImGuiInputFlags_RouteFromRootWindow;

    pub fn handleKeybinds(tai: *core.ToolAssistedInput) void {
        handlePlayKey(tai);
        handleStopKey(tai);
    }

    pub fn draw(
        self: *Self,
        tai: *core.ToolAssistedInput,
        coordinator: *core.TaiRecordingCoordinator,
        selection: *const ui.TaiEditor.Selection,
    ) void {
        if (imgui.igIsWindowFocused(imgui.ImGuiFocusedFlags_RootAndChildWindows)) {
            self.handleRepeatShortcut();
            self.handleSelectionShortcut();
        }

        const spacing = imgui.igGetStyle().*.ItemSpacing.x;

        drawPlayButton(tai);
        imgui.igSameLine(0, spacing);
        drawStopButton(tai);
        imgui.igSameLine(0, 2 * spacing);
        self.drawRecordModeDropdown();
        imgui.igSameLine(0, 2 * spacing);
        drawInitialStateButton();
        imgui.igSameLine(0, spacing);
        self.drawRepeatButton();
        imgui.igSameLine(0, spacing);
        self.drawSelectionButton();

        self.updateCore(tai, coordinator, selection);
    }

    fn updateCore(
        self: *const Self,
        tai: *core.ToolAssistedInput,
        coordinator: *core.TaiRecordingCoordinator,
        selection: *const ui.TaiEditor.Selection,
    ) void {
        const tai_config = &tai.play_config;
        if (self.play_only_selection) {
            tai_config.enable_player_1 = selection.start.player_id == .player_1 or selection.end.player_id == .player_1;
            tai_config.enable_player_2 = selection.start.player_id == .player_2 or selection.end.player_id == .player_2;
            tai_config.start_index = selection.getMinIndex();
            tai_config.length = selection.getNumberOfRows();
        } else {
            tai_config.enable_player_1 = self.enable_player_1;
            tai_config.enable_player_2 = self.enable_player_2;
            tai_config.start_index = 0;
            tai_config.length = std.math.maxInt(usize);
        }
        tai_config.repeat = self.repeat;
        coordinator.mode = self.record_mode;
    }

    fn isPlayDisabled(tai: *const core.ToolAssistedInput) bool {
        return tai.mode == .play or tai.sequence.items.len == 0;
    }

    fn drawPlayButton(tai: *core.ToolAssistedInput) void {
        imgui.igBeginDisabled(isPlayDisabled(tai));
        defer imgui.igEndDisabled();
        if (imgui.igButton(" ▶ ###play", .{})) {
            tai.play();
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Play Inputs [F10]");
        }
    }

    fn handlePlayKey(tai: *core.ToolAssistedInput) void {
        if (isPlayDisabled(tai)) {
            return;
        }
        if (imgui.igShortcut_Nil(imgui.ImGuiKey_F10, imgui.ImGuiInputFlags_RouteGlobal)) {
            tai.play();
        }
    }

    fn isStopDisabled(tai: *const core.ToolAssistedInput) bool {
        return tai.mode == .idle;
    }

    fn drawStopButton(tai: *core.ToolAssistedInput) void {
        imgui.igBeginDisabled(isStopDisabled(tai));
        defer imgui.igEndDisabled();
        if (imgui.igButton(" ⏹ ###stop", .{})) {
            tai.stop();
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Stop Playing Inputs [F11]");
        }
    }

    fn handleStopKey(tai: *core.ToolAssistedInput) void {
        if (isStopDisabled(tai)) {
            return;
        }
        if (imgui.igShortcut_Nil(imgui.ImGuiKey_F11, imgui.ImGuiInputFlags_RouteGlobal)) {
            tai.stop();
        }
    }

    fn drawRecordModeDropdown(self: *Self) void {
        const Mode = core.TaiRecordingCoordinator.Mode;
        const labels = std.enums.EnumArray(Mode, [:0]const u8).init(.{
            .do_not_record = "Do Not Record",
            .only_record = "Only Record",
            .clear_and_record = "Clear And Record",
        });
        var max_label_width: f32 = 0.0;
        inline for (@typeInfo(Mode).@"enum".field_values) |field_value| {
            const value: Mode = @fromBackingInt(@intCast(field_value));
            var size: imgui.ImVec2 = undefined;
            imgui.igCalcTextSize(&size, labels.get(value), null, false, -1);
            max_label_width = @max(max_label_width, size.x);
        }
        const width = imgui.igGetFrameHeight() + max_label_width + (2.0 * imgui.igGetStyle().*.FramePadding.x);
        imgui.igSetNextItemWidth(width);
        if (imgui.igBeginCombo("###record_mode", labels.get(self.record_mode), 0)) {
            defer imgui.igEndCombo();
            inline for (@typeInfo(Mode).@"enum".field_values) |field_value| {
                const value: Mode = @fromBackingInt(@intCast(field_value));
                if (imgui.igSelectable_Bool(labels.get(value), self.record_mode == value, 0, .{})) {
                    self.record_mode = value;
                }
            }
        }
    }

    fn drawInitialStateButton() void {
        imgui.igBeginDisabled(true);
        defer imgui.igEndDisabled();
        _ = imgui.igButton(" 🯅 ###intial_state", .{});
        if (imgui.igIsItemHovered(imgui.ImGuiHoveredFlags_AllowWhenDisabled)) {
            imgui.igSetTooltip("Use Recorded Initial State (Not yet implemented.)");
        }
    }

    fn drawRepeatButton(self: *Self) void {
        const toggled_on = self.repeat;
        if (toggled_on) {
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, toggled_on_color);
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, toggled_on_color);
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, toggled_on_color);
        }
        defer if (toggled_on) {
            imgui.igPopStyleColor(3);
        };
        if (imgui.igButton(" 🔁 ###repeat", .{})) {
            self.repeat = !self.repeat;
        }
        if (imgui.igIsItemHovered(0)) {
            const tooltip = switch (self.repeat) {
                false => "Enable Repeat [Ctrl + R]",
                true => "Disable Repeat [Ctrl + R]",
            };
            imgui.igSetTooltip(tooltip);
        }
    }

    fn handleRepeatShortcut(self: *Self) void {
        if (!imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_R, window_route)) {
            return;
        }
        self.repeat = !self.repeat;
    }

    fn drawSelectionButton(self: *Self) void {
        const toggled_on = self.play_only_selection;
        if (toggled_on) {
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, toggled_on_color);
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, toggled_on_color);
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, toggled_on_color);
        }
        defer if (toggled_on) {
            imgui.igPopStyleColor(3);
        };
        if (imgui.igButton(" ⬚ ###selection", .{})) {
            self.play_only_selection = !self.play_only_selection;
        }
        if (imgui.igIsItemHovered(0)) {
            const tooltip = switch (self.play_only_selection) {
                false => "Play Only Selection [Ctrl + O]",
                true => "Play Entire Sequence [Ctrl + O]",
            };
            imgui.igSetTooltip(tooltip);
        }
    }

    fn handleSelectionShortcut(self: *Self) void {
        if (!imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_O, window_route)) {
            return;
        }
        self.play_only_selection = !self.play_only_selection;
    }
};

const testing = std.testing;

test "should put tai in play mode when play button is clicked or F10 key is pressed" {
    const Test = struct {
        var tai = core.ToolAssistedInput.init(testing.allocator);
        var coordinator = core.TaiRecordingCoordinator{};
        var controls = TaiControls{};
        var selection = ui.TaiEditor.Selection.initial;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            TaiControls.handleKeybinds(&tai);
            controls.draw(&tai, &coordinator, &selection);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try tai.sequence.append(tai.allocator, .{});
            ctx.setRef("Window");

            tai.stop();
            try testing.expect(tai.mode == .idle);
            ctx.itemClick("###play", 0, 0);
            try testing.expect(tai.mode == .play);

            tai.stop();
            try testing.expect(tai.mode == .idle);
            ctx.yield(1); // Shortcuts get routed one frame after they become enabled.
            ctx.keyPress(imgui.ImGuiKey_F10, 1);
            try testing.expect(tai.mode == .play);
        }
    };
    defer Test.tai.deinit();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should put tai in idle mode when stop button is clicked or F11 key is pressed" {
    const Test = struct {
        var tai = core.ToolAssistedInput.init(testing.allocator);
        var coordinator = core.TaiRecordingCoordinator{};
        var controls = TaiControls{};
        var selection = ui.TaiEditor.Selection.initial;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            TaiControls.handleKeybinds(&tai);
            controls.draw(&tai, &coordinator, &selection);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try tai.sequence.append(tai.allocator, .{});
            ctx.setRef("Window");

            tai.play();
            try testing.expect(tai.mode == .play);
            ctx.itemClick("###stop", imgui.ImGuiMouseButton_Left, 0);
            try testing.expect(tai.mode == .idle);

            tai.play();
            try testing.expect(tai.mode == .play);
            ctx.yield(1); // Shortcuts get routed one frame after they become enabled.
            ctx.keyPress(imgui.ImGuiKey_F11, 1);
            try testing.expect(tai.mode == .idle);
        }
    };
    defer Test.tai.deinit();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should put coordinator in selected mode when record mode dropdown is used" {
    const Test = struct {
        var tai = core.ToolAssistedInput.init(testing.allocator);
        var coordinator = core.TaiRecordingCoordinator{};
        var controls = TaiControls{};
        var selection = ui.TaiEditor.Selection.initial;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            TaiControls.handleKeybinds(&tai);
            controls.draw(&tai, &coordinator, &selection);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            const Mode = core.TaiRecordingCoordinator.Mode;
            try testing.expectEqual(Mode.do_not_record, coordinator.mode);

            ctx.itemClick("###record_mode", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("//$FOCUSED/Only Record", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(Mode.only_record, coordinator.mode);

            ctx.itemClick("###record_mode", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("//$FOCUSED/Clear And Record", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(Mode.clear_and_record, coordinator.mode);

            ctx.itemClick("###record_mode", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("//$FOCUSED/Do Not Record", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(Mode.do_not_record, coordinator.mode);
        }
    };
    defer Test.tai.deinit();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should toggle repeat when repeat button is clicked or Ctrl+R is pressed" {
    const Test = struct {
        var tai = core.ToolAssistedInput.init(testing.allocator);
        var coordinator = core.TaiRecordingCoordinator{};
        var controls = TaiControls{};
        var selection = ui.TaiEditor.Selection.initial;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            TaiControls.handleKeybinds(&tai);
            controls.draw(&tai, &coordinator, &selection);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");

            try testing.expectEqual(false, tai.play_config.repeat);
            ctx.itemClick("###repeat", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(true, tai.play_config.repeat);
            ctx.itemClick("###repeat", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(false, tai.play_config.repeat);

            ctx.keyDown(imgui.ImGuiKey_LeftCtrl);
            try testing.expectEqual(false, tai.play_config.repeat);
            ctx.keyPress(imgui.ImGuiKey_R, 1);
            try testing.expectEqual(true, tai.play_config.repeat);
            ctx.keyPress(imgui.ImGuiKey_R, 1);
            try testing.expectEqual(false, tai.play_config.repeat);
            ctx.keyUp(imgui.ImGuiKey_LeftCtrl);

            ctx.keyPress(imgui.ImGuiKey_R, 1);
            try testing.expectEqual(false, tai.play_config.repeat);
        }
    };
    defer Test.tai.deinit();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should toggle between selection and whole sequence when repeat button is clicked or Ctrl+O is pressed" {
    const Test = struct {
        var tai = core.ToolAssistedInput.init(testing.allocator);
        var coordinator = core.TaiRecordingCoordinator{};
        var controls = TaiControls{};
        var selection = ui.TaiEditor.Selection.initial;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            TaiControls.handleKeybinds(&tai);
            controls.draw(&tai, &coordinator, &selection);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");

            controls.enable_player_1 = true;
            controls.enable_player_2 = false;
            selection = .{
                .start = .{ .player_id = .player_2, .index = 1 },
                .end = .{ .player_id = .player_2, .index = 2 },
            };
            ctx.yield(1);

            try testing.expectEqual(true, tai.play_config.enable_player_1);
            try testing.expectEqual(false, tai.play_config.enable_player_2);
            try testing.expectEqual(0, tai.play_config.start_index);
            try testing.expectEqual(std.math.maxInt(usize), tai.play_config.length);
            ctx.itemClick("###selection", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(false, tai.play_config.enable_player_1);
            try testing.expectEqual(true, tai.play_config.enable_player_2);
            try testing.expectEqual(1, tai.play_config.start_index);
            try testing.expectEqual(2, tai.play_config.length);
            ctx.itemClick("###selection", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(true, tai.play_config.enable_player_1);
            try testing.expectEqual(false, tai.play_config.enable_player_2);
            try testing.expectEqual(0, tai.play_config.start_index);
            try testing.expectEqual(std.math.maxInt(usize), tai.play_config.length);

            ctx.keyDown(imgui.ImGuiKey_LeftCtrl);
            try testing.expectEqual(true, tai.play_config.enable_player_1);
            try testing.expectEqual(false, tai.play_config.enable_player_2);
            try testing.expectEqual(0, tai.play_config.start_index);
            try testing.expectEqual(std.math.maxInt(usize), tai.play_config.length);
            ctx.keyPress(imgui.ImGuiKey_O, 1);
            try testing.expectEqual(false, tai.play_config.enable_player_1);
            try testing.expectEqual(true, tai.play_config.enable_player_2);
            try testing.expectEqual(1, tai.play_config.start_index);
            try testing.expectEqual(2, tai.play_config.length);
            ctx.keyPress(imgui.ImGuiKey_O, 1);
            try testing.expectEqual(true, tai.play_config.enable_player_1);
            try testing.expectEqual(false, tai.play_config.enable_player_2);
            try testing.expectEqual(0, tai.play_config.start_index);
            try testing.expectEqual(std.math.maxInt(usize), tai.play_config.length);
            ctx.keyUp(imgui.ImGuiKey_LeftCtrl);

            ctx.keyPress(imgui.ImGuiKey_O, 1);
            try testing.expectEqual(true, tai.play_config.enable_player_1);
            try testing.expectEqual(false, tai.play_config.enable_player_2);
            try testing.expectEqual(0, tai.play_config.start_index);
            try testing.expectEqual(std.math.maxInt(usize), tai.play_config.length);
        }
    };
    defer Test.tai.deinit();
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
