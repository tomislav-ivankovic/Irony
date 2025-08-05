const std = @import("std");
const imgui = @import("imgui");

pub fn drawLoadingWindow(text: [:0]const u8) void {
    const display_size = imgui.igGetIO_Nil().*.DisplaySize;
    var text_size: imgui.ImVec2 = undefined;
    imgui.igCalcTextSize(&text_size, text, null, false, -1.0);
    const window_size = imgui.ImVec2{
        .x = text_size.x + (2 * imgui.igGetStyle().*.WindowPadding.x + imgui.igGetStyle().*.WindowBorderSize),
        .y = text_size.y + (2 * imgui.igGetStyle().*.WindowPadding.y + imgui.igGetStyle().*.WindowBorderSize),
    };
    const window_position = imgui.ImVec2{
        .x = 0.5 * display_size.x - 0.5 * window_size.x,
        .y = 0.5 * display_size.y - 0.5 * window_size.y,
    };

    const window_flags = imgui.ImGuiWindowFlags_AlwaysAutoResize |
        imgui.ImGuiWindowFlags_NoDecoration |
        imgui.ImGuiWindowFlags_NoInputs |
        imgui.ImGuiWindowFlags_NoSavedSettings;
    imgui.igSetNextWindowPos(window_position, imgui.ImGuiCond_Always, .{});
    imgui.igSetNextWindowSize(window_size, imgui.ImGuiCond_Always);

    const is_open = imgui.igBegin("Loading", null, window_flags);
    defer imgui.igEnd();
    if (!is_open) {
        return;
    }

    imgui.igText("%s", text.ptr);
}
