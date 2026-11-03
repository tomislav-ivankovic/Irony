const std = @import("std");
const w32 = @import("win32").everything;
const imgui = @import("imgui");
const ui = @import("root.zig");

const routing_no_owner = std.math.maxInt(imgui.ImGuiID);

pub fn hasShortcutRoute(key_chord: imgui.ImGuiKeyChord) bool {
    const key = key_chord & ~@as(imgui.ImGuiKeyChord, imgui.ImGuiMod_Mask_);
    if (key < imgui.ImGuiKey_NamedKey_BEGIN or key >= imgui.ImGuiKey_NamedKey_END) {
        return false;
    }
    const routing_data = imgui.igGetShortcutRoutingData(key_chord) orelse return false;
    return routing_data.*.RoutingNext != routing_no_owner;
}

pub const KeyEvent = struct {
    w_param: w32.WPARAM,
    l_param: w32.LPARAM,
};

pub fn keyEventFromRawKeyboard(input: *const w32.RAWKEYBOARD) KeyEvent {
    const scan_code: w32.LPARAM = input.MakeCode & 0xFF;
    const extended: w32.LPARAM = if ((input.Flags & w32.RI_KEY_E0) != 0) 1 else 0;
    return .{
        .w_param = input.VKey,
        .l_param = (scan_code << 16) | (extended << 24),
    };
}

pub fn keyChordFromKeyEvent(w_param: w32.WPARAM, l_param: w32.LPARAM) ?imgui.ImGuiKeyChord {
    const key = keyFromKeyEvent(w_param, l_param) orelse return null;
    return key | getCurrentKeyMods();
}

fn getCurrentKeyMods() imgui.ImGuiKeyChord {
    const isDown = struct {
        fn call(key: w32.VIRTUAL_KEY) bool {
            return w32.GetAsyncKeyState(@backingInt(key)) < 0;
        }
    }.call;
    var mods: imgui.ImGuiKeyChord = 0;
    if (isDown(w32.VK_CONTROL)) mods |= imgui.ImGuiMod_Ctrl;
    if (isDown(w32.VK_SHIFT)) mods |= imgui.ImGuiMod_Shift;
    if (isDown(w32.VK_MENU)) mods |= imgui.ImGuiMod_Alt;
    if (isDown(w32.VK_LWIN) or isDown(w32.VK_RWIN)) mods |= imgui.ImGuiMod_Super;
    return mods;
}

fn keyFromKeyEvent(w_param: w32.WPARAM, l_param: w32.LPARAM) ?imgui.ImGuiKeyChord {
    const key = ui.backend.ImGui_ImplWin32_KeyEventToImGuiKey(w_param, l_param);
    if (key == imgui.ImGuiKey_None) {
        return null;
    }
    return @intCast(key);
}

const testing = std.testing;

fn keyFromRawKeyboard(input: *const w32.RAWKEYBOARD) ?imgui.ImGuiKeyChord {
    const event = keyEventFromRawKeyboard(input);
    return keyFromKeyEvent(event.w_param, event.l_param);
}

fn rawKeyboard(vk: w32.VIRTUAL_KEY, make_code: u16, flags: u16) w32.RAWKEYBOARD {
    return rawKeyboardFromInt(@backingInt(vk), make_code, flags);
}

fn rawKeyboardFromInt(vk: u16, make_code: u16, flags: u16) w32.RAWKEYBOARD {
    return .{
        .MakeCode = make_code,
        .Flags = flags,
        .Reserved = 0,
        .VKey = vk,
        .Message = w32.WM_KEYDOWN,
        .ExtraInformation = 0,
    };
}

test "keyFromRawKeyboard should map virtual keys to ImGui keys" {
    try testing.expectEqual(imgui.ImGuiKey_A, keyFromRawKeyboard(&rawKeyboard(.A, 30, 0)));
    try testing.expectEqual(imgui.ImGuiKey_Z, keyFromRawKeyboard(&rawKeyboard(.Z, 44, 0)));
    try testing.expectEqual(imgui.ImGuiKey_0, keyFromRawKeyboard(&rawKeyboard(.@"0", 11, 0)));
    try testing.expectEqual(imgui.ImGuiKey_9, keyFromRawKeyboard(&rawKeyboard(.@"9", 10, 0)));
    try testing.expectEqual(imgui.ImGuiKey_F1, keyFromRawKeyboard(&rawKeyboard(.F1, 59, 0)));
    try testing.expectEqual(imgui.ImGuiKey_F11, keyFromRawKeyboard(&rawKeyboard(.F11, 87, 0)));
    try testing.expectEqual(imgui.ImGuiKey_F24, keyFromRawKeyboard(&rawKeyboard(.F24, 0, 0)));
    try testing.expectEqual(imgui.ImGuiKey_Keypad0, keyFromRawKeyboard(&rawKeyboard(.NUMPAD0, 82, 0)));
    try testing.expectEqual(imgui.ImGuiKey_Keypad9, keyFromRawKeyboard(&rawKeyboard(.NUMPAD9, 73, 0)));
    try testing.expectEqual(imgui.ImGuiKey_Tab, keyFromRawKeyboard(&rawKeyboard(.TAB, 15, 0)));
    try testing.expectEqual(imgui.ImGuiKey_Escape, keyFromRawKeyboard(&rawKeyboard(.ESCAPE, 1, 0)));
    try testing.expectEqual(imgui.ImGuiKey_UpArrow, keyFromRawKeyboard(&rawKeyboard(.UP, 72, w32.RI_KEY_E0)));
    try testing.expectEqual(imgui.ImGuiKey_Delete, keyFromRawKeyboard(&rawKeyboard(.DELETE, 83, w32.RI_KEY_E0)));
}

test "keyFromRawKeyboard should map extended return key to keypad enter" {
    try testing.expectEqual(imgui.ImGuiKey_Enter, keyFromRawKeyboard(&rawKeyboard(.RETURN, 28, 0)));
    try testing.expectEqual(imgui.ImGuiKey_KeypadEnter, keyFromRawKeyboard(&rawKeyboard(.RETURN, 28, w32.RI_KEY_E0)));
}

test "keyFromRawKeyboard should fall back to scan code for layout dependent keys" {
    try testing.expectEqual(imgui.ImGuiKey_GraveAccent, keyFromRawKeyboard(&rawKeyboard(.OEM_3, 41, 0)));
    try testing.expectEqual(imgui.ImGuiKey_Minus, keyFromRawKeyboard(&rawKeyboard(.OEM_MINUS, 12, 0)));
    try testing.expectEqual(imgui.ImGuiKey_Slash, keyFromRawKeyboard(&rawKeyboard(.OEM_2, 53, 0)));
}

test "keyFromRawKeyboard should return null for generic modifier keys and unknown keys" {
    try testing.expectEqual(null, keyFromRawKeyboard(&rawKeyboard(.SHIFT, 42, 0)));
    try testing.expectEqual(null, keyFromRawKeyboard(&rawKeyboard(.CONTROL, 29, 0)));
    try testing.expectEqual(null, keyFromRawKeyboard(&rawKeyboard(.MENU, 56, 0)));
    try testing.expectEqual(null, keyFromRawKeyboard(&rawKeyboardFromInt(0xFF, 0, 0)));
}

test "hasShortcutRoute should return true exactly when a key press would trigger the shortcut" {
    const Test = struct {
        var enabled = false;
        var times_triggered: usize = 0;

        const chord = imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_A;

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            if (!enabled) {
                return;
            }
            if (imgui.igShortcut_Nil(chord, imgui.ImGuiInputFlags_RouteGlobal)) {
                times_triggered += 1;
            }
        }

        fn testFunction(ctx: ui.TestContext) !void {
            ctx.yield(1);
            try testing.expectEqual(false, hasShortcutRoute(chord));
            ctx.keyPress(chord, 1);
            try testing.expectEqual(0, times_triggered);

            enabled = true;
            try testing.expectEqual(false, hasShortcutRoute(chord));
            ctx.keyPress(chord, 1);
            try testing.expectEqual(0, times_triggered);

            try testing.expectEqual(true, hasShortcutRoute(chord));
            ctx.keyPress(chord, 1);
            try testing.expectEqual(1, times_triggered);

            enabled = false;
            ctx.yield(1);
            try testing.expect(!hasShortcutRoute(chord));
        }
    };
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "hasShortcutRoute should require the modifiers to match exactly" {
    const Test = struct {
        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            _ = imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_R, imgui.ImGuiInputFlags_RouteGlobal);
        }

        fn testFunction(ctx: ui.TestContext) !void {
            ctx.yield(1);
            try testing.expectEqual(true, hasShortcutRoute(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_R));
            try testing.expectEqual(false, hasShortcutRoute(imgui.ImGuiKey_R));
            try testing.expectEqual(false, hasShortcutRoute(imgui.ImGuiMod_Ctrl | imgui.ImGuiMod_Shift | imgui.ImGuiKey_R));
            try testing.expectEqual(false, hasShortcutRoute(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_T));
        }
    };
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
