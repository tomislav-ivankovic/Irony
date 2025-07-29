const std = @import("std");
const imgui = @import("imgui");

pub const TestContext = struct {
    raw: *imgui.ImGuiTestContext,

    const Self = @This();

    fn anyToRef(any: anytype) imgui.ImGuiTestRef {
        return switch (@TypeOf(any)) {
            imgui.ImGuiTestRef => any,
            imgui.ImGuiID => .{ .ID = any, .Path = null },
            comptime_int => .{ .ID = any, .Path = null },
            [:0]const u8 => .{ .ID = 0, .Path = any },
            else => anyToRef(@as([:0]const u8, any)),
        };
    }

    pub fn finish(self: Self, status: imgui.ImGuiTestStatus) void {
        return imgui.ImGuiTestContext_Finish(self.raw, status);
    }

    pub fn runChildTest(self: Self, test_name: [:0]const u8, flags: imgui.TestRunFlags) imgui.ImGuiTestStatus {
        return imgui.ImGuiTestContext_RunChildTest(self.raw, test_name, flags);
    }

    pub fn isError(self: Self) bool {
        return imgui.ImGuiTestContext_IsError(self.raw);
    }

    pub fn isWarmUpGuiFrame(self: Self) bool {
        return imgui.ImGuiTestContext_IsWarmUpGuiFrame(self.raw);
    }

    pub fn isFirstGuiFrame(self: Self) bool {
        return imgui.ImGuiTestContext_IsFirstGuiFrame(self.raw);
    }

    pub fn isFirstTestFrame(self: Self) bool {
        return imgui.ImGuiTestContext_IsFirstTestFrame(self.raw);
    }

    pub fn isGuiFuncOnly(self: Self) bool {
        return imgui.ImGuiTestContext_IsGuiFuncOnly(self.raw);
    }

    pub fn suspendTestFunc(self: Self, file: [:0]const u8, line: c_int) bool {
        return imgui.ImGuiTestContext_SuspendTestFunc(self.raw, file, line);
    }

    pub fn logEx(
        self: Self,
        level: imgui.ImGuiTestVerboseLevel,
        flags: imgui.ImGuiTestLogFlags,
        fmt: [:0]const u8,
        args: anytype,
    ) void {
        return @call(.auto, imgui.ImGuiTestContext_LogEx, .{ self.raw, level, flags, fmt } ++ args);
    }

    pub fn logToTTY(
        self: Self,
        level: imgui.ImGuiTestVerboseLevel,
        message: [:0]const u8,
        message_end: [:0]const u8,
    ) void {
        return imgui.ImGuiTestContext_LogToTTY(self.raw, level, message, message_end);
    }

    pub fn logToDebugger(self: Self, level: imgui.ImGuiTestVerboseLevel, message: [:0]const u8) void {
        return imgui.ImGuiTestContext_LogToDebugger(self.raw, level, message);
    }

    pub fn logDebug(self: Self, fmt: [:0]const u8, args: anytype) void {
        return @call(.auto, imgui.ImGuiTestContext_LogDebug, .{ self.raw, fmt } ++ args);
    }

    pub fn logInfo(self: Self, fmt: [:0]const u8, args: anytype) void {
        return @call(.auto, imgui.ImGuiTestContext_LogInfo, .{ self.raw, fmt } ++ args);
    }

    pub fn logWarning(self: Self, fmt: [:0]const u8, args: anytype) void {
        return @call(.auto, imgui.ImGuiTestContext_LogWarning, .{ self.raw, fmt } ++ args);
    }

    pub fn logError(self: Self, fmt: [:0]const u8, args: anytype) void {
        return @call(.auto, imgui.ImGuiTestContext_LogError, .{ self.raw, fmt } ++ args);
    }

    pub fn logBasicUiState(self: Self) void {
        return imgui.ImGuiTestContext_LogBasicUiState(self.raw);
    }

    pub fn logItemList(self: Self, list: *imgui.ImGuiTestItemList) void {
        return imgui.ImGuiTestContext_LogItemList(self.raw, list);
    }

    pub fn yield(self: Self, count: c_int) void {
        return imgui.ImGuiTestContext_Yield(self.raw, count);
    }

    pub fn sleep(self: Self, time_in_second: f32) void {
        return imgui.ImGuiTestContext_Sleep(self.raw, time_in_second);
    }

    pub fn sleepShort(self: Self) void {
        return imgui.ImGuiTestContext_SleepShort(self.raw);
    }

    pub fn sleepStandard(self: Self) void {
        return imgui.ImGuiTestContext_SleepStandard(self.raw);
    }

    pub fn sleepNoSkip(self: Self, time_in_second: f32, framestep_in_second: f32) void {
        return imgui.ImGuiTestContext_SleepNoSkip(self.raw, time_in_second, framestep_in_second);
    }

    pub fn setRef(self: Self, ref: anytype) void {
        if (@TypeOf(ref) == *imgui.ImGuiWindow) {
            return imgui.ImGuiTestContext_SetRef2(self.raw, ref);
        }
        return imgui.ImGuiTestContext_SetRef1(self.raw, anyToRef(ref));
    }

    pub fn getRef(self: Self) imgui.ImGuiTestRef {
        return imgui.ImGuiTestContext_GetRef(self.raw);
    }

    pub fn windowInfo(
        self: Self,
        window_ref: anytype,
        flags: imgui.ImGuiTestOpFlags,
    ) imgui.ImGuiTestItemInfo {
        return imgui.ImGuiTestContext_WindowInfo(self.raw, anyToRef(window_ref), flags);
    }

    pub fn windowClose(self: Self, window_ref: anytype) void {
        return imgui.ImGuiTestContext_WindowClose(self.raw, anyToRef(window_ref));
    }

    pub fn windowCollapse(self: Self, window_ref: anytype, collapsed: bool) void {
        return imgui.ImGuiTestContext_WindowCollapse(self.raw, anyToRef(window_ref), collapsed);
    }

    pub fn windowFocus(self: Self, window_ref: anytype, flags: imgui.ImGuiTestOpFlags) void {
        return imgui.ImGuiTestContext_WindowFocus(self.raw, anyToRef(window_ref), flags);
    }

    pub fn windowBringToFront(self: Self, window_ref: anytype, flags: imgui.ImGuiTestOpFlags) void {
        return imgui.ImGuiTestContext_WindowBringToFront(self.raw, anyToRef(window_ref), flags);
    }

    pub fn windowMove(
        self: Self,
        window_ref: anytype,
        pos: imgui.ImVec2,
        pivot: imgui.ImVec2,
        flags: imgui.ImGuiTestOpFlags,
    ) void {
        return imgui.ImGuiTestContext_WindowMove(self.raw, anyToRef(window_ref), pos, pivot, flags);
    }

    pub fn windowResize(self: Self, window_ref: anytype, sz: imgui.ImVec2) void {
        return imgui.ImGuiTestContext_WindowResize(self.raw, anyToRef(window_ref), sz);
    }

    pub fn windowTeleportToMakePosVisible(
        self: Self,
        window_ref: anytype,
        pos_in_window: imgui.ImVec2,
    ) bool {
        return imgui.ImGuiTestContext_WindowTeleportToMakePosVisible(self.raw, anyToRef(window_ref), pos_in_window);
    }

    pub fn getWindowByRef(self: Self, window_ref: anytype) ?*imgui.ImGuiWindow {
        return imgui.ImGuiTestContext_GetWindowByRef(self.raw, anyToRef(window_ref));
    }

    pub fn popupCloseOne(self: Self) void {
        return imgui.ImGuiTestContext_PopupCloseOne(self.raw);
    }

    pub fn popupCloseAll(self: Self) void {
        return imgui.ImGuiTestContext_PopupCloseAll(self.raw);
    }

    pub fn popupGetWindowID(self: Self, ref: anytype) imgui.ImGuiID {
        return imgui.ImGuiTestContext_PopupGetWindowID(self.raw, anyToRef(ref));
    }

    pub fn getID(self: Self, ref: anytype) imgui.ImGuiID {
        return imgui.ImGuiTestContext_GetID(self.raw, anyToRef(ref));
    }

    pub fn getID2(self: Self, ref: anytype, seed_ref: anytype) imgui.ImGuiID {
        return imgui.ImGuiTestContext_GetID2(self.raw, anyToRef(ref), anyToRef(seed_ref));
    }

    pub fn getPosOnVoid(self: Self, viewport: *imgui.ImGuiViewport) imgui.ImVec2 {
        return imgui.ImGuiTestContext_GetPosOnVoid(self.raw, viewport);
    }

    pub fn getWindowTitlebarPoint(self: Self, window_ref: anytype) imgui.ImVec2 {
        return imgui.ImGuiTestContext_GetWindowTitlebarPoint(self.raw, anyToRef(window_ref));
    }

    pub fn getMainMonitorWorkPos(self: Self) imgui.ImVec2 {
        return imgui.ImGuiTestContext_GetMainMonitorWorkPos(self.raw);
    }

    pub fn getMainMonitorWorkSize(self: Self) imgui.ImVec2 {
        return imgui.ImGuiTestContext_GetMainMonitorWorkSize(self.raw);
    }

    pub fn captureReset(self: Self) void {
        return imgui.ImGuiTestContext_CaptureReset(self.raw);
    }

    pub fn captureSetExtension(self: Self, ext: [:0]const u8) void {
        return imgui.ImGuiTestContext_CaptureSetExtension(self.raw, ext);
    }

    pub fn captureAddWindow(self: Self, ref: anytype) bool {
        return imgui.ImGuiTestContext_CaptureAddWindow(self.raw, anyToRef(ref));
    }

    pub fn captureScreenshotWindow(self: Self, ref: anytype, capture_flags: c_int) void {
        return imgui.ImGuiTestContext_CaptureScreenshotWindow(self.raw, anyToRef(ref), capture_flags);
    }

    pub fn captureScreenshot(self: Self, capture_flags: c_int) bool {
        return imgui.ImGuiTestContext_CaptureScreenshot(self.raw, capture_flags);
    }

    pub fn captureBeginVideo(self: Self) bool {
        return imgui.ImGuiTestContext_CaptureBeginVideo(self.raw);
    }

    pub fn captureEndVideo(self: Self) bool {
        return imgui.ImGuiTestContext_CaptureEndVideo(self.raw);
    }

    pub fn mouseMove(self: Self, ref: anytype, flags: imgui.ImGuiTestOpFlags) void {
        return imgui.ImGuiTestContext_MouseMove(self.raw, anyToRef(ref), flags);
    }

    pub fn mouseMoveToPos(self: Self, pos: imgui.ImVec2) void {
        return imgui.ImGuiTestContext_MouseMoveToPos(self.raw, pos);
    }

    pub fn mouseTeleportToPos(self: Self, pos: imgui.ImVec2, flags: imgui.ImGuiTestOpFlags) void {
        return imgui.ImGuiTestContext_MouseTeleportToPos(self.raw, pos, flags);
    }

    pub fn mouseClick(self: Self, button: imgui.ImGuiMouseButton) void {
        return imgui.ImGuiTestContext_MouseClick(self.raw, button);
    }

    pub fn mouseClickMulti(self: Self, button: imgui.ImGuiMouseButton, count: c_int) void {
        return imgui.ImGuiTestContext_MouseClickMulti(self.raw, button, count);
    }

    pub fn mouseDoubleClick(self: Self, button: imgui.ImGuiMouseButton) void {
        return imgui.ImGuiTestContext_MouseDoubleClick(self.raw, button);
    }

    pub fn mouseDown(self: Self, button: imgui.ImGuiMouseButton) void {
        return imgui.ImGuiTestContext_MouseDown(self.raw, button);
    }

    pub fn mouseUp(self: Self, button: imgui.ImGuiMouseButton) void {
        return imgui.ImGuiTestContext_MouseUp(self.raw, button);
    }

    pub fn mouseLiftDragThreshold(self: Self, button: imgui.ImGuiMouseButton) void {
        return imgui.ImGuiTestContext_MouseLiftDragThreshold(self.raw, button);
    }

    pub fn mouseDragWithDelta(self: Self, delta: imgui.ImVec2, button: imgui.ImGuiMouseButton) void {
        return imgui.ImGuiTestContext_MouseDragWithDelta(self.raw, delta, button);
    }

    pub fn mouseWheel(self: Self, delta: imgui.ImVec2) void {
        return imgui.ImGuiTestContext_MouseWheel(self.raw, delta);
    }

    pub fn mouseWheelX(self: Self, dx: f32) void {
        return imgui.ImGuiTestContext_MouseWheelX(self.raw, dx);
    }

    pub fn mouseWheelY(self: Self, dy: f32) void {
        return imgui.ImGuiTestContext_MouseWheelY(self.raw, dy);
    }

    pub fn mouseMoveToVoid(self: Self, viewport: ?*imgui.ImGuiViewport) void {
        return imgui.ImGuiTestContext_MouseMoveToVoid(self.raw, viewport);
    }

    pub fn mouseClickOnVoid(self: Self, button: imgui.ImGuiMouseButton, viewport: ?*imgui.ImGuiViewport) void {
        return imgui.ImGuiTestContext_MouseClickOnVoid(self.raw, button, viewport);
    }

    pub fn findHoveredWindowAtPos(self: Self, pos: *const imgui.ImVec2) ?*imgui.ImGuiWindow {
        return imgui.ImGuiTestContext_FindHoveredWindowAtPos(self.raw, pos);
    }

    pub fn findExistingVoidPosOnViewport(self: Self, viewport: *imgui.ImGuiViewport, out: *imgui.ImVec2) bool {
        return imgui.ImGuiTestContext_FindExistingVoidPosOnViewport(self.raw, viewport, out);
    }

    pub fn mouseSetViewport(self: Self, window: ?*imgui.ImGuiWindow) void {
        return imgui.ImGuiTestContext_MouseSetViewport(self.raw, window);
    }

    pub fn mouseSetViewportID(self: Self, viewport_id: imgui.ImGuiID) void {
        return imgui.ImGuiTestContext_MouseSetViewportID(self.raw, viewport_id);
    }

    pub fn keyDown(self: Self, key_chord: imgui.ImGuiKeyChord) void {
        return imgui.ImGuiTestContext_KeyDown(self.raw, key_chord);
    }

    pub fn keyUp(self: Self, key_chord: imgui.ImGuiKeyChord) void {
        return imgui.ImGuiTestContext_KeyUp(self.raw, key_chord);
    }

    pub fn keyPress(self: Self, key_chord: imgui.ImGuiKeyChord, count: c_int) void {
        return imgui.ImGuiTestContext_KeyPress(self.raw, key_chord, count);
    }

    pub fn keyHold(self: Self, key_chord: imgui.ImGuiKeyChord, time: f32) void {
        return imgui.ImGuiTestContext_KeyHold(self.raw, key_chord, time);
    }

    pub fn keySetEx(self: Self, key_chord: imgui.ImGuiKeyChord, is_down: bool, time: f32) void {
        return imgui.ImGuiTestContext_KeySetEx(self.raw, key_chord, is_down, time);
    }

    pub fn keyChars(self: Self, chars: [:0]const u8) void {
        return imgui.ImGuiTestContext_KeyChars(self.raw, chars);
    }

    pub fn keyCharsAppend(self: Self, chars: [:0]const u8) void {
        return imgui.ImGuiTestContext_KeyCharsAppend(self.raw, chars);
    }

    pub fn keyCharsAppendEnter(self: Self, chars: [:0]const u8) void {
        return imgui.ImGuiTestContext_KeyCharsAppendEnter(self.raw, chars);
    }

    pub fn keyCharsReplace(self: Self, chars: [:0]const u8) void {
        return imgui.ImGuiTestContext_KeyCharsReplace(self.raw, chars);
    }

    pub fn keyCharsReplaceEnter(self: Self, chars: [:0]const u8) void {
        return imgui.ImGuiTestContext_KeyCharsReplaceEnter(self.raw, chars);
    }

    pub fn setInputMode(self: Self, input_mode: imgui.ImGuiInputSource) void {
        return imgui.ImGuiTestContext_SetInputMode(self.raw, input_mode);
    }

    pub fn navMoveTo(self: Self, ref: anytype) void {
        return imgui.ImGuiTestContext_NavMoveTo(self.raw, anyToRef(ref));
    }

    pub fn navActivate(self: Self) void {
        return imgui.ImGuiTestContext_NavActivate(self.raw);
    }

    pub fn navInput(self: Self) void {
        return imgui.ImGuiTestContext_NavInput(self.raw);
    }

    pub fn scrollTo(
        self: Self,
        ref: anytype,
        axis: imgui.ImGuiAxis,
        scroll_v: f32,
        flags: imgui.ImGuiTestOpFlags,
    ) void {
        return imgui.ImGuiTestContext_ScrollTo(self.raw, anyToRef(ref), axis, scroll_v, flags);
    }

    pub fn scrollToX(self: Self, ref: anytype, scroll_x: f32) void {
        return imgui.ImGuiTestContext_ScrollToX(self.raw, anyToRef(ref), scroll_x);
    }

    pub fn scrollToY(self: Self, ref: anytype, scroll_y: f32) void {
        return imgui.ImGuiTestContext_ScrollToY(self.raw, anyToRef(ref), scroll_y);
    }

    pub fn scrollToTop(self: Self, ref: anytype) void {
        return imgui.ImGuiTestContext_ScrollToTop(self.raw, anyToRef(ref));
    }

    pub fn scrollToBottom(self: Self, ref: anytype) void {
        return imgui.ImGuiTestContext_ScrollToBottom(self.raw, anyToRef(ref));
    }

    pub fn scrollToItem(
        self: Self,
        ref: anytype,
        axis: imgui.ImGuiAxis,
        flags: imgui.ImGuiTestOpFlags,
    ) void {
        return imgui.ImGuiTestContext_ScrollToItem(self.raw, anyToRef(ref), axis, flags);
    }

    pub fn scrollToItemX(self: Self, ref: anytype) void {
        return imgui.ImGuiTestContext_ScrollToItemX(self.raw, anyToRef(ref));
    }

    pub fn scrollToItemY(self: Self, ref: anytype) void {
        return imgui.ImGuiTestContext_ScrollToItemY(self.raw, anyToRef(ref));
    }

    pub fn scrollToTabItem(self: Self, tab_bar: *imgui.ImGuiTabBar, tab_id: imgui.ImGuiID) void {
        return imgui.ImGuiTestContext_ScrollToTabItem(self.raw, tab_bar, tab_id);
    }

    pub fn scrollErrorCheck(
        self: Self,
        axis: imgui.ImGuiAxis,
        expected: f32,
        actual: f32,
        remaining_attempts: *c_int,
    ) bool {
        return imgui.ImGuiTestContext_ScrollErrorCheck(self.raw, axis, expected, actual, remaining_attempts);
    }

    pub fn scrollVerifyScrollMax(self: Self, ref: anytype) void {
        return imgui.ImGuiTestContext_ScrollVerifyScrollMax(self.raw, anyToRef(ref));
    }

    pub fn itemInfo(self: Self, ref: anytype, flags: imgui.ImGuiTestOpFlags) imgui.ImGuiTestItemInfo {
        return imgui.ImGuiTestContext_ItemInfo(self.raw, anyToRef(ref), flags);
    }

    pub fn itemInfoOpenFullPath(self: Self, ref: anytype, flags: imgui.ImGuiTestOpFlags) imgui.ImGuiTestItemInfo {
        return imgui.ImGuiTestContext_ItemInfoOpenFullPath(self.raw, anyToRef(ref), flags);
    }

    pub fn itemInfoHandleWildcardSearch(
        self: Self,
        wildcard_prefix_start: [:0]const u8,
        wildcard_prefix_end: [:0]const u8,
        wildcard_suffix_start: [:0]const u8,
    ) imgui.ImGuiID {
        return imgui.ImGuiTestContext_ItemInfoHandleWildcardSearch(
            self.raw,
            wildcard_prefix_start,
            wildcard_prefix_end,
            wildcard_suffix_start,
        );
    }

    pub fn itemInfoNull(self: Self) imgui.ImGuiTestItemInfo {
        return imgui.ImGuiTestContext_ItemInfoNull(self.raw);
    }

    pub fn gatherItems(self: Self, out_list: *imgui.ImGuiTestItemList, parent: anytype, depth: c_int) void {
        return imgui.ImGuiTestContext_GatherItems(self.raw, out_list, anyToRef(parent), depth);
    }

    pub fn itemAction(
        self: Self,
        action: imgui.ImGuiTestAction,
        ref: anytype,
        flags: imgui.ImGuiTestOpFlags,
        action_arg: ?*anyopaque,
    ) void {
        return imgui.ImGuiTestContext_ItemAction(self.raw, action, anyToRef(ref), flags, action_arg);
    }

    pub fn itemClick(
        self: Self,
        ref: anytype,
        button: imgui.ImGuiMouseButton,
        flags: imgui.ImGuiTestOpFlags,
    ) void {
        return imgui.ImGuiTestContext_ItemClick(self.raw, anyToRef(ref), button, flags);
    }

    pub fn itemDoubleClick(self: Self, ref: anytype, flags: imgui.ImGuiTestOpFlags) void {
        return imgui.ImGuiTestContext_ItemDoubleClick(self.raw, anyToRef(ref), flags);
    }

    pub fn itemCheck(self: Self, ref: anytype, flags: imgui.ImGuiTestOpFlags) void {
        return imgui.ImGuiTestContext_ItemCheck(self.raw, anyToRef(ref), flags);
    }

    pub fn itemUncheck(self: Self, ref: anytype, flags: imgui.ImGuiTestOpFlags) void {
        return imgui.ImGuiTestContext_ItemUncheck(self.raw, anyToRef(ref), flags);
    }

    pub fn itemOpen(self: Self, ref: anytype, flags: imgui.ImGuiTestOpFlags) void {
        return imgui.ImGuiTestContext_ItemOpen(self.raw, anyToRef(ref), flags);
    }

    pub fn itemClose(self: Self, ref: anytype, flags: imgui.ImGuiTestOpFlags) void {
        return imgui.ImGuiTestContext_ItemClose(self.raw, anyToRef(ref), flags);
    }

    pub fn itemInput(self: Self, ref: anytype, flags: imgui.ImGuiTestOpFlags) void {
        return imgui.ImGuiTestContext_ItemInput(self.raw, anyToRef(ref), flags);
    }

    pub fn itemNavActivate(self: Self, ref: anytype, flags: imgui.ImGuiTestOpFlags) void {
        return imgui.ImGuiTestContext_ItemNavActivate(self.raw, anyToRef(ref), flags);
    }

    pub fn itemActionAll(
        self: Self,
        action: imgui.ImGuiTestAction,
        ref_parent: anytype,
        filter: *const imgui.ImGuiTestActionFilter,
    ) void {
        return imgui.ImGuiTestContext_ItemActionAll(self.raw, action, anyToRef(ref_parent), filter);
    }

    pub fn itemOpenAll(self: Self, ref_parent: anytype, depth: c_int, passes: c_int) void {
        return imgui.ImGuiTestContext_ItemOpenAll(self.raw, anyToRef(ref_parent), depth, passes);
    }

    pub fn itemCloseAll(self: Self, ref_parent: anytype, depth: c_int, passes: c_int) void {
        return imgui.ImGuiTestContext_ItemCloseAll(self.raw, anyToRef(ref_parent), depth, passes);
    }

    pub fn itemInputValueInt(self: Self, ref: anytype, v: c_int) void {
        return imgui.ImGuiTestContext_ItemInputValueInt(self.raw, anyToRef(ref), v);
    }

    pub fn itemInputValueFloat(self: Self, ref: anytype, f: f32) void {
        return imgui.ImGuiTestContext_ItemInputValueFloat(self.raw, anyToRef(ref), f);
    }

    pub fn itemInputValueStr(self: Self, ref: anytype, str: [:0]const u8) void {
        return imgui.ImGuiTestContext_ItemInputValueStr(self.raw, anyToRef(ref), str);
    }

    pub fn itemReadAsInt(self: Self, ref: anytype) c_int {
        return imgui.ImGuiTestContext_ItemReadAsInt(self.raw, anyToRef(ref));
    }

    pub fn itemReadAsFloat(self: Self, ref: anytype) f32 {
        return imgui.ImGuiTestContext_ItemReadAsFloat(self.raw, anyToRef(ref));
    }

    pub fn itemReadAsScalar(
        self: Self,
        ref: anytype,
        data_type: imgui.ImGuiDataType,
        out_data: ?*anyopaque,
        flags: imgui.ImGuiTestOpFlags,
    ) bool {
        return imgui.ImGuiTestContext_ItemReadAsScalar(self.raw, anyToRef(ref), data_type, out_data, flags);
    }

    pub fn itemReadAsString(self: Self, ref: anytype) [:0]const u8 {
        return imgui.ImGuiTestContext_ItemReadAsString(self.raw, anyToRef(ref));
    }

    pub fn itemReadAsStringBuff(self: Self, ref: anytype, out_buf: [:0]u8, out_buf_size: usize) usize {
        return imgui.ImGuiTestContext_ItemReadAsStringBuff(self.raw, anyToRef(ref), out_buf, out_buf_size);
    }

    pub fn itemExists(self: Self, ref: anytype) bool {
        return imgui.ImGuiTestContext_ItemExists(self.raw, anyToRef(ref));
    }

    pub fn itemIsChecked(self: Self, ref: anytype) bool {
        return imgui.ImGuiTestContext_ItemIsChecked(self.raw, anyToRef(ref));
    }

    pub fn itemIsOpened(self: Self, ref: anytype) bool {
        return imgui.ImGuiTestContext_ItemIsOpened(self.raw, anyToRef(ref));
    }

    pub fn itemVerifyCheckedIfAlive(self: Self, ref: anytype, checked: bool) void {
        return imgui.ImGuiTestContext_ItemVerifyCheckedIfAlive(self.raw, anyToRef(ref), checked);
    }

    pub fn itemHold(self: Self, ref: anytype, time: f32) void {
        return imgui.ImGuiTestContext_ItemHold(self.raw, anyToRef(ref), time);
    }

    pub fn itemHoldForFrames(self: Self, ref: anytype, frames: c_int) void {
        return imgui.ImGuiTestContext_ItemHoldForFrames(self.raw, anyToRef(ref), frames);
    }

    pub fn itemDragOverAndHold(self: Self, ref_src: anytype, ref_dst: anytype) void {
        return imgui.ImGuiTestContext_ItemDragOverAndHold(self.raw, anyToRef(ref_src), anyToRef(ref_dst));
    }

    pub fn itemDragAndDrop(self: Self, ref_src: anytype, ref_dst: anytype, button: imgui.ImGuiMouseButton) void {
        return imgui.ImGuiTestContext_ItemDragAndDrop(self.raw, anyToRef(ref_src), anyToRef(ref_dst), button);
    }

    pub fn itemDragWithDelta(self: Self, ref_src: anytype, pos_delta: imgui.ImVec2) void {
        return imgui.ImGuiTestContext_ItemDragWithDelta(self.raw, anyToRef(ref_src), pos_delta);
    }

    pub fn tabClose(self: Self, ref: anytype) void {
        return imgui.ImGuiTestContext_TabClose(self.raw, anyToRef(ref));
    }

    pub fn tabBarCompareOrder(self: Self, tab_bar: *imgui.ImGuiTabBar, tab_order: [:0][:0]const u8) bool {
        return imgui.ImGuiTestContext_TabBarCompareOrder(self.raw, tab_bar, tab_order);
    }

    pub fn menuAction(self: Self, action: imgui.ImGuiTestAction, ref: anytype) void {
        return imgui.ImGuiTestContext_MenuAction(self.raw, action, anyToRef(ref));
    }

    pub fn menuActionAll(self: Self, action: imgui.ImGuiTestAction, ref_parent: anytype) void {
        return imgui.ImGuiTestContext_MenuActionAll(self.raw, action, anyToRef(ref_parent));
    }

    pub fn menuClick(self: Self, ref: anytype) void {
        return imgui.ImGuiTestContext_MenuClick(self.raw, anyToRef(ref));
    }

    pub fn menuCheck(self: Self, ref: anytype) void {
        return imgui.ImGuiTestContext_MenuCheck(self.raw, anyToRef(ref));
    }

    pub fn menuUncheck(self: Self, ref: anytype) void {
        return imgui.ImGuiTestContext_MenuUncheck(self.raw, anyToRef(ref));
    }

    pub fn menuCheckAll(self: Self, ref_parent: anytype) void {
        return imgui.ImGuiTestContext_MenuCheckAll(self.raw, anyToRef(ref_parent));
    }

    pub fn menuUncheckAll(self: Self, ref_parent: anytype) void {
        return imgui.ImGuiTestContext_MenuUncheckAll(self.raw, anyToRef(ref_parent));
    }

    pub fn comboClick(self: Self, ref: anytype) void {
        return imgui.ImGuiTestContext_ComboClick(self.raw, anyToRef(ref));
    }

    pub fn comboClickAll(self: Self, ref: anytype) void {
        return imgui.ImGuiTestContext_ComboClickAll(self.raw, anyToRef(ref));
    }

    pub fn tableOpenContextMenu(self: Self, ref: anytype, column_n: c_int) void {
        return imgui.ImGuiTestContext_TableOpenContextMenu(self.raw, anyToRef(ref), column_n);
    }

    pub fn tableClickHeader(
        self: Self,
        ref: anytype,
        label: [:0]const u8,
        key_mods: imgui.ImGuiKeyChord,
    ) imgui.ImGuiSortDirection {
        return imgui.ImGuiTestContext_TableClickHeader(self.raw, anyToRef(ref), label, key_mods);
    }

    pub fn tableSetColumnEnabled(self: Self, ref: anytype, label: [:0]const u8, enabled: bool) void {
        return imgui.ImGuiTestContext_TableSetColumnEnabled(self.raw, anyToRef(ref), label, enabled);
    }

    pub fn tableResizeColumn(self: Self, ref: anytype, column_n: c_int, width: f32) void {
        return imgui.ImGuiTestContext_TableResizeColumn(self.raw, anyToRef(ref), column_n, width);
    }

    pub fn tableGetSortSpecs(self: Self, ref: anytype) *const imgui.ImGuiTableSortSpecs {
        return imgui.ImGuiTestContext_TableGetSortSpecs(self.raw, anyToRef(ref));
    }

    pub fn perfCalcRef(self: Self) void {
        return imgui.ImGuiTestContext_PerfCalcRef(self.raw);
    }

    pub fn perfCapture(self: Self, category: [:0]const u8, test_name: [:0]const u8, csv_file: [:0]const u8) void {
        return imgui.ImGuiTestContext_PerfCapture(self.raw, category, test_name, csv_file);
    }

    // Custom functions:

    pub fn expectItemExists(self: Self, ref: anytype) !void {
        if (self.itemExists(ref)) {
            return;
        }
        const ref_object = anyToRef(ref);
        if (ref_object.Path != null) {
            self.logError("Failed to find item with ID: \"%s\"", .{ref_object.Path});
        } else {
            self.logError("Failed to find item with ID: %d", .{ref_object.ID});
        }
        return error.ExpectedItemNotFound;
    }

    pub fn expectItemExistsFmt(self: Self, comptime fmt: []const u8, args: anytype) !void {
        const ref = try std.fmt.allocPrintZ(std.testing.allocator, fmt, args);
        defer std.testing.allocator.free(ref);
        return self.expectItemExists(ref);
    }

    pub fn expectItemNotExists(self: Self, ref: anytype) !void {
        if (!self.itemExists(ref)) {
            return;
        }
        const ref_object = anyToRef(ref);
        if (ref_object.Path != null) {
            self.logError("Item was expected not to exist but was still found: \"%s\"", .{ref_object.Path});
        } else {
            self.logError("Item was expected not to exist but was still found: %d", .{ref_object.Path});
        }
        return error.UnexpectedItemFound;
    }

    pub fn expectItemNotExistsFmt(self: Self, comptime fmt: []const u8, args: anytype) !void {
        const ref = try std.fmt.allocPrintZ(std.testing.allocator, fmt, args);
        defer std.testing.allocator.free(ref);
        return self.expectItemNotExists(ref);
    }

    pub fn expectClipboardText(self: Self, expected: [:0]const u8) !void {
        const actual = std.mem.sliceTo(imgui.igGetClipboardText(), 0);
        if (std.mem.eql(u8, expected, actual)) {
            return;
        }
        self.logError("Incorrect clipboard text.\n\texpected: %s\n\t  actual: %s", .{ expected.ptr, actual.ptr });
        return error.IncorrectClipboardText;
    }

    pub fn expectClipboardTextFmt(self: Self, comptime fmt: []const u8, args: anytype) !void {
        const expected = try std.fmt.allocPrintZ(std.testing.allocator, fmt, args);
        defer std.testing.allocator.free(expected);
        return self.expectClipboardText(expected);
    }

    pub fn getScrollX(self: Self, window_ref: anytype) f32 {
        return imgui.ImGuiTestContext_GetScrollX(self.raw, anyToRef(window_ref));
    }

    pub fn getScrollY(self: Self, window_ref: anytype) f32 {
        return imgui.ImGuiTestContext_GetScrollY(self.raw, anyToRef(window_ref));
    }

    pub fn getScrollMaxX(self: Self, window_ref: anytype) f32 {
        return imgui.ImGuiTestContext_GetScrollMaxX(self.raw, anyToRef(window_ref));
    }

    pub fn getScrollMaxY(self: Self, window_ref: anytype) f32 {
        return imgui.ImGuiTestContext_GetScrollMaxY(self.raw, anyToRef(window_ref));
    }
};
