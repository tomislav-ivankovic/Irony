const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const core = @import("../core/root.zig");
const ui = @import("root.zig");

pub fn drawCameraMenu(camera_director: *core.CameraDirector) void {
    if (!imgui.igBeginMenu("Camera", true)) {
        return;
    }
    defer imgui.igEndMenu();
    if (imgui.igMenuItem_Bool("Live Camera", "Ctrl + 1", camera_director.mode == .live, true)) {
        camera_director.mode = .live;
    }
    if (imgui.igMenuItem_Bool("Recorded Camera", "Ctrl + 2", camera_director.mode == .recording, true)) {
        camera_director.mode = .recording;
    }
    if (imgui.igMenuItem_Bool("Free Look Camera", "Ctrl + 3", camera_director.mode == .free_look, true)) {
        camera_director.mode = .free_look;
    }
    if (imgui.igIsItemHovered(0)) {
        ui.FreeLookCamera.drawTooltip();
    }
}

pub fn handleCameraShortcuts(camera_director: *core.CameraDirector) void {
    if (imgui.igGetTopMostPopupModal() != null) {
        return;
    }
    const route = imgui.ImGuiInputFlags_RouteGlobal;
    if (imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_1, route)) {
        camera_director.mode = .live;
    }
    if (imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_2, route)) {
        camera_director.mode = .recording;
    }
    if (imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_3, route)) {
        camera_director.mode = .free_look;
    }
}

const testing = std.testing;

test "should change camera director mode when a camera is selected by clicking a menu bar button" {
    const Test = struct {
        var camera_director: core.CameraDirector = .{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            drawCameraMenu(&camera_director);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            try testing.expectEqual(core.CameraDirector.Mode.live, camera_director.mode);
            ctx.menuClick("Camera/Recorded Camera");
            try testing.expectEqual(core.CameraDirector.Mode.recording, camera_director.mode);
            ctx.menuClick("Camera/Free Look Camera");
            try testing.expectEqual(core.CameraDirector.Mode.free_look, camera_director.mode);
            ctx.menuClick("Camera/Live Camera");
            try testing.expectEqual(core.CameraDirector.Mode.live, camera_director.mode);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should change camera director mode when a camera keyboard shortcut is pressed" {
    const Test = struct {
        var camera_director: core.CameraDirector = .{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            handleCameraShortcuts(&camera_director);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try testing.expectEqual(core.CameraDirector.Mode.live, camera_director.mode);
            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_2, 1);
            try testing.expectEqual(core.CameraDirector.Mode.recording, camera_director.mode);
            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_3, 1);
            try testing.expectEqual(core.CameraDirector.Mode.free_look, camera_director.mode);
            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_1, 1);
            try testing.expectEqual(core.CameraDirector.Mode.live, camera_director.mode);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
