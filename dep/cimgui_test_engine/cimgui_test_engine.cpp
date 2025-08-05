#include "./imgui/imgui.h"
#include "./imgui_test_engine/imgui_te_context.h"
#include "./imgui_test_engine/imgui_te_engine.h"
#include "./imgui_test_engine/imgui_te_exporters.h"

#include "cimgui_test_engine.h"

CIMGUI_API void teItemAdd(ImGuiContext* ui_ctx, ImGuiID id, const ImRect* bb, const ImGuiLastItemData* item_data) {
    return ImGuiTestEngineHook_ItemAdd(ui_ctx, id, *bb, item_data);
}

CIMGUI_API void teItemInfo(ImGuiContext* ui_ctx, ImGuiID id, const char* label, ImGuiItemStatusFlags flags) {
    return ImGuiTestEngineHook_ItemInfo(ui_ctx, id, label, flags);
}

CIMGUI_API void teLog(ImGuiContext* ui_ctx, const char* message) {
    return ImGuiTestEngineHook_Log(ui_ctx, "%s", message);
}

CIMGUI_API const char* teFindItemDebugLabel(ImGuiContext* ui_ctx, ImGuiID id) {
    return ImGuiTestEngine_FindItemDebugLabel(ui_ctx, id);
}

CIMGUI_API bool
teCheck(const char* file, const char* func, int line, ImGuiTestCheckFlags flags, bool result, const char* expr) {
    return ImGuiTestEngine_Check(file, func, line, flags, result, expr);
}

CIMGUI_API bool teCheckStrOp(
    const char* file,
    const char* func,
    int line,
    ImGuiTestCheckFlags flags,
    const char* op,
    const char* lhs_var,
    const char* lhs_value,
    const char* rhs_var,
    const char* rhs_value,
    bool* out_result
) {
    return ImGuiTestEngine_CheckStrOp(file, func, line, flags, op, lhs_var, lhs_value, rhs_var, rhs_value, out_result);
}

CIMGUI_API bool teError(const char* file, const char* func, int line, ImGuiTestCheckFlags flags, const char* message) {
    return ImGuiTestEngine_Error(file, func, line, flags, "%s", message);
}

CIMGUI_API void teAssertLog(const char* expr, const char* file, const char* function, int line) {
    return ImGuiTestEngine_AssertLog(expr, file, function, line);
}

CIMGUI_API ImGuiTextBuffer* teGetTempStringBuilder() { return ImGuiTestEngine_GetTempStringBuilder(); }

CIMGUI_API ImGuiTestEngine* teCreateContext() { return ImGuiTestEngine_CreateContext(); }

CIMGUI_API void teDestroyContext(ImGuiTestEngine* engine) { return ImGuiTestEngine_DestroyContext(engine); }

CIMGUI_API void teStart(ImGuiTestEngine* engine, ImGuiContext* ui_ctx) { return ImGuiTestEngine_Start(engine, ui_ctx); }

CIMGUI_API void teStop(ImGuiTestEngine* engine) { return ImGuiTestEngine_Stop(engine); }

CIMGUI_API void tePostSwap(ImGuiTestEngine* engine) { return ImGuiTestEngine_PostSwap(engine); }

CIMGUI_API ImGuiTestEngineIO* teGetIO(ImGuiTestEngine* engine) { return &ImGuiTestEngine_GetIO(engine); }

CIMGUI_API ImGuiTest*
teRegisterTest(ImGuiTestEngine* engine, const char* category, const char* name, const char* src_file, int src_line) {
    return ImGuiTestEngine_RegisterTest(engine, category, name, src_file, src_line);
}

CIMGUI_API void teUnregisterTest(ImGuiTestEngine* engine, ImGuiTest* test) {
    return ImGuiTestEngine_UnregisterTest(engine, test);
}

void teUnregisterAllTests(ImGuiTestEngine* engine) { return ImGuiTestEngine_UnregisterAllTests(engine); }

CIMGUI_API void teQueueTest(ImGuiTestEngine* engine, ImGuiTest* test, ImGuiTestRunFlags run_flags) {
    return ImGuiTestEngine_QueueTest(engine, test, run_flags);
}

CIMGUI_API void
teQueueTests(ImGuiTestEngine* engine, ImGuiTestGroup group, const char* filter, ImGuiTestRunFlags run_flags) {
    return ImGuiTestEngine_QueueTests(engine, group, filter, run_flags);
}

CIMGUI_API bool teTryAbortEngine(ImGuiTestEngine* engine) { return ImGuiTestEngine_TryAbortEngine(engine); }

CIMGUI_API void teAbortCurrentTest(ImGuiTestEngine* engine) { return ImGuiTestEngine_AbortCurrentTest(engine); }

CIMGUI_API ImGuiTest* teFindTestByName(ImGuiTestEngine* engine, const char* category, const char* name) {
    return ImGuiTestEngine_FindTestByName(engine, category, name);
}

CIMGUI_API bool teIsTestQueueEmpty(ImGuiTestEngine* engine) { return ImGuiTestEngine_IsTestQueueEmpty(engine); }

CIMGUI_API bool teIsUsingSimulatedInputs(ImGuiTestEngine* engine) {
    return ImGuiTestEngine_IsUsingSimulatedInputs(engine);
}

CIMGUI_API void teGetResultSummary(ImGuiTestEngine* engine, ImGuiTestEngineResultSummary* out_results) {
    return ImGuiTestEngine_GetResultSummary(engine, out_results);
}

CIMGUI_API void teGetTestList(ImGuiTestEngine* engine, ImVector_ImGuiTestPtr* out_tests) {
    return ImGuiTestEngine_GetTestList(engine, out_tests);
}

CIMGUI_API void teGetTestQueue(ImGuiTestEngine* engine, ImVector_ImGuiTestRunTask* out_tests) {
    return ImGuiTestEngine_GetTestQueue(engine, out_tests);
}

CIMGUI_API void teInstallDefaultCrashHandler() { return ImGuiTestEngine_InstallDefaultCrashHandler(); }

CIMGUI_API void teCrashHandler() { return ImGuiTestEngine_CrashHandler(); }

CIMGUI_API void tePrintResultSummary(ImGuiTestEngine* engine) { return ImGuiTestEngine_PrintResultSummary(engine); }

CIMGUI_API void teExport(ImGuiTestEngine* engine) { return ImGuiTestEngine_Export(engine); }

CIMGUI_API void teExportEx(ImGuiTestEngine* engine, ImGuiTestEngineExportFormat format, const char* filename) {
    return ImGuiTestEngine_ExportEx(engine, format, filename);
}

CIMGUI_API ImGuiTestEngineIO* ImGuiTestEngineIO_ImGuiTestEngineIO(void) { return IM_NEW(ImGuiTestEngineIO)(); }

CIMGUI_API void ImGuiTestEngineIO_destroy(ImGuiTestEngineIO* self) { IM_DELETE(self); }

CIMGUI_API ImGuiTestItemInfo* ImGuiTestItemInfo_ImGuiTestItemInfo(void) { return IM_NEW(ImGuiTestItemInfo)(); }

CIMGUI_API void ImGuiTestItemInfo_destroy(ImGuiTestItemInfo* self) { IM_DELETE(self); }

CIMGUI_API ImGuiTestItemList* ImGuiTestItemList_ImGuiTestItemList(void) { return IM_NEW(ImGuiTestItemList)(); }

CIMGUI_API void ImGuiTestItemList_destroy(ImGuiTestItemList* self) { IM_DELETE(self); }

CIMGUI_API void ImGuiTestItemList_Clear(ImGuiTestItemList* self) { return self->Clear(); }

CIMGUI_API void ImGuiTestItemList_Reserve(ImGuiTestItemList* self, int capacity) { return self->Reserve(capacity); }

CIMGUI_API int ImGuiTestItemList_GetSize(const ImGuiTestItemList* self) { return self->GetSize(); }

CIMGUI_API const ImGuiTestItemInfo* ImGuiTestItemList_GetByIndex(ImGuiTestItemList* self, int n) {
    return self->GetByIndex(n);
}

CIMGUI_API const ImGuiTestItemInfo* ImGuiTestItemList_GetByID(ImGuiTestItemList* self, ImGuiID id) {
    return self->GetByID(id);
}

CIMGUI_API size_t ImGuiTestItemList_size(const ImGuiTestItemList* self) { return self->size(); }

CIMGUI_API const ImGuiTestItemInfo* ImGuiTestItemList_begin(const ImGuiTestItemList* self) { return self->begin(); }

CIMGUI_API const ImGuiTestItemInfo* ImGuiTestItemList_end(const ImGuiTestItemList* self) { return self->end(); }

CIMGUI_API const ImGuiTestItemInfo* ImGuiTestItemList_at(ImGuiTestItemList* self, size_t n) { return (*self)[n]; }

CIMGUI_API ImGuiTestLogLineInfo* ImGuiTestLogLineInfo_ImGuiTestLogLineInfo(void) {
    return IM_NEW(ImGuiTestLogLineInfo)();
}

CIMGUI_API void ImGuiTestLogLineInfo_destroy(ImGuiTestLogLineInfo* self) { IM_DELETE(self); }

CIMGUI_API ImGuiTestLog* ImGuiTestLog_ImGuiTestLog(void) { return IM_NEW(ImGuiTestLog)(); }

CIMGUI_API void ImGuiTestLog_destroy(ImGuiTestLog* self) { IM_DELETE(self); }

CIMGUI_API bool ImGuiTestLog_IsEmpty(const ImGuiTestLog* self) { return self->IsEmpty(); }

CIMGUI_API void ImGuiTestLog_Clear(ImGuiTestLog* self) { return self->Clear(); };

CIMGUI_API int ImGuiTestLog_ExtractLinesForVerboseLevels(
    ImGuiTestLog* self,
    ImGuiTestVerboseLevel level_min,
    ImGuiTestVerboseLevel level_max,
    ImGuiTextBuffer* out_buffer
) {
    return self->ExtractLinesForVerboseLevels(level_min, level_max, out_buffer);
};

CIMGUI_API void ImGuiTestLog_UpdateLineOffsets(
    ImGuiTestLog* self,
    ImGuiTestEngineIO* engine_io,
    ImGuiTestVerboseLevel level,
    const char* start
) {
    return self->UpdateLineOffsets(engine_io, level, start);
}

CIMGUI_API ImGuiTestOutput* ImGuiTestOutput_ImGuiTestOutput(void) { return IM_NEW(ImGuiTestOutput)(); }

CIMGUI_API void ImGuiTestOutput_destroy(ImGuiTestOutput* self) { IM_DELETE(self); }

CIMGUI_API ImGuiTest* ImGuiTest_ImGuiTest(void) { return IM_NEW(ImGuiTest)(); }

CIMGUI_API void ImGuiTest_destroy(ImGuiTest* self) { IM_DELETE(self); }

CIMGUI_API void ImGuiTest_SetOwnedName(ImGuiTest* self, const char* name) { self->SetOwnedName(name); };

// Skipped ImGuiTest_SetVarsDataType because it uses templates.

CIMGUI_API ImGuiTestRunTask* ImGuiTestRunTask_ImGuiTestRunTask(void) { return IM_NEW(ImGuiTestRunTask)(); }

CIMGUI_API void ImGuiTestRunTask_destroy(ImGuiTestRunTask* self) { IM_DELETE(self); }

CIMGUI_API ImGuiTestRef* ImGuiTestRef_ImGuiTestRef(void) { return IM_NEW(ImGuiTestRef)(); }

CIMGUI_API ImGuiTestRef* ImGuiTestRef_ImGuiTestRef1(ImGuiID id) { return IM_NEW(ImGuiTestRef)(id); }

CIMGUI_API ImGuiTestRef* ImGuiTestRef_ImGuiTestRef2(const char* path) { return IM_NEW(ImGuiTestRef)(path); }

CIMGUI_API void ImGuiTestRef_destroy(ImGuiTestRef* self) { IM_DELETE(self); }

CIMGUI_API bool ImGuiTestRef_IsEmpty(const ImGuiTestRef* self) { return self->IsEmpty(); }

CIMGUI_API ImGuiTestRefDesc* ImGuiTestRefDesc_ImGuiTestRefDesc1(const ImGuiTestRef* ref) {
    return IM_NEW(ImGuiTestRefDesc)(*ref);
}

CIMGUI_API ImGuiTestRefDesc* ImGuiTestRefDesc2(const ImGuiTestRef* ref, const ImGuiTestItemInfo* item) {
    return IM_NEW(ImGuiTestRefDesc)(*ref, *item);
}

CIMGUI_API void ImGuiTestRefDesc_destroy(ImGuiTestRefDesc* self) { IM_DELETE(self); }

CIMGUI_API const char* ImGuiTestRefDesc_c_str(ImGuiTestRefDesc* self) { return self->c_str(); }

CIMGUI_API ImGuiTestActionFilter* ImGuiTestActionFilter_ImGuiTestActionFilter(void) {
    return IM_NEW(ImGuiTestActionFilter)();
}

CIMGUI_API void ImGuiTestActionFilter_destroy(ImGuiTestActionFilter* self) { IM_DELETE(self); }

CIMGUI_API ImGuiTestGenericItemStatus* ImGuiTestGenericItemStatus_ImGuiTestGenericItemStatus(void) {
    return IM_NEW(ImGuiTestGenericItemStatus)();
}

CIMGUI_API void ImGuiTestGenericItemStatus_destroy(ImGuiTestGenericItemStatus* self) { IM_DELETE(self); }

CIMGUI_API void ImGuiTestGenericItemStatus_Clear(ImGuiTestGenericItemStatus* self) { return self->Clear(); }

CIMGUI_API void ImGuiTestGenericItemStatus_QuerySet(ImGuiTestGenericItemStatus* self, bool ret_val) {
    return self->QuerySet(ret_val);
}

CIMGUI_API void ImGuiTestGenericItemStatus_QueryInc(ImGuiTestGenericItemStatus* self, bool ret_val) {
    return self->QueryInc(ret_val);
}

CIMGUI_API void ImGuiTestGenericItemStatus_Draw(ImGuiTestGenericItemStatus* self) { return self->Draw(); }

CIMGUI_API ImGuiTestGenericVars* ImGuiTestGenericVars_ImGuiTestGenericVars(void) {
    return IM_NEW(ImGuiTestGenericVars)();
}

CIMGUI_API void ImGuiTestGenericVars_destroy(ImGuiTestGenericVars* self) { IM_DELETE(self); }

CIMGUI_API void ImGuiTestGenericVars_Clear(ImGuiTestGenericVars* self) { return self->Clear(); }

CIMGUI_API ImGuiTestContext* ImGuiTestContext_ImGuiTestContext(void) { return IM_NEW(ImGuiTestContext)(); }

CIMGUI_API void ImGuiTestContext_destroy(ImGuiTestContext* self) { IM_DELETE(self); }

CIMGUI_API void ImGuiTestContext_Finish(ImGuiTestContext* self, ImGuiTestStatus status) {
    return self->Finish(status);
};

CIMGUI_API ImGuiTestStatus
ImGuiTestContext_RunChildTest(ImGuiTestContext* self, const char* test_name, ImGuiTestRunFlags flags) {
    return self->RunChildTest(test_name, flags);
};

// Skipped ImGuiTestStatus_GetVars because it uses templates.

CIMGUI_API bool ImGuiTestContext_IsError(const ImGuiTestContext* self) { return self->IsError(); }

CIMGUI_API bool ImGuiTestContext_IsWarmUpGuiFrame(const ImGuiTestContext* self) { return self->IsWarmUpGuiFrame(); }

CIMGUI_API bool ImGuiTestContext_IsFirstGuiFrame(const ImGuiTestContext* self) { return self->IsFirstGuiFrame(); }

CIMGUI_API bool ImGuiTestContext_IsFirstTestFrame(const ImGuiTestContext* self) { return self->IsFirstTestFrame(); }

CIMGUI_API bool ImGuiTestContext_IsGuiFuncOnly(const ImGuiTestContext* self) { return self->IsGuiFuncOnly(); }

CIMGUI_API bool ImGuiTestContext_SuspendTestFunc(ImGuiTestContext* self, const char* file, int line) {
    return self->SuspendTestFunc(file, line);
}

CIMGUI_API void ImGuiTestContext_LogEx(
    ImGuiTestContext* self,
    ImGuiTestVerboseLevel level,
    ImGuiTestLogFlags flags,
    const char* fmt,
    ...
) {
    va_list args;
    va_start(args, fmt);
    self->LogExV(level, flags, fmt, args);
    va_end(args);
};

CIMGUI_API void ImGuiTestContext_LogExV(
    ImGuiTestContext* self,
    ImGuiTestVerboseLevel level,
    ImGuiTestLogFlags flags,
    const char* fmt,
    va_list args
) {
    return self->LogExV(level, flags, fmt, args);
}

CIMGUI_API void ImGuiTestContext_LogToTTY(
    ImGuiTestContext* self,
    ImGuiTestVerboseLevel level,
    const char* message,
    const char* message_end
) {
    return self->LogToTTY(level, message, message_end);
}

CIMGUI_API void
ImGuiTestContext_LogToDebugger(ImGuiTestContext* self, ImGuiTestVerboseLevel level, const char* message) {
    return self->LogToDebugger(level, message);
}

CIMGUI_API void ImGuiTestContext_LogDebug(ImGuiTestContext* self, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    self->LogExV(ImGuiTestVerboseLevel_Debug, ImGuiTestLogFlags_None, fmt, args);
    va_end(args);
};

CIMGUI_API void ImGuiTestContext_LogInfo(ImGuiTestContext* self, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    self->LogExV(ImGuiTestVerboseLevel_Info, ImGuiTestLogFlags_None, fmt, args);
    va_end(args);
};

CIMGUI_API void ImGuiTestContext_LogWarning(ImGuiTestContext* self, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    self->LogExV(ImGuiTestVerboseLevel_Warning, ImGuiTestLogFlags_None, fmt, args);
    va_end(args);
};

CIMGUI_API void ImGuiTestContext_LogError(ImGuiTestContext* self, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    self->LogExV(ImGuiTestVerboseLevel_Error, ImGuiTestLogFlags_None, fmt, args);
    va_end(args);
};

CIMGUI_API void ImGuiTestContext_LogBasicUiState(ImGuiTestContext* self) { return self->LogBasicUiState(); };

CIMGUI_API void ImGuiTestContext_LogItemList(ImGuiTestContext* self, ImGuiTestItemList* list) {
    return self->LogItemList(list);
};

CIMGUI_API void ImGuiTestContext_Yield(ImGuiTestContext* self, int count) { return self->Yield(count); }

CIMGUI_API void ImGuiTestContext_Sleep(ImGuiTestContext* self, float time_in_second) {
    return self->Sleep(time_in_second);
}

CIMGUI_API void ImGuiTestContext_SleepShort(ImGuiTestContext* self) { return self->SleepShort(); }

CIMGUI_API void ImGuiTestContext_SleepStandard(ImGuiTestContext* self) { return self->SleepStandard(); }

CIMGUI_API void ImGuiTestContext_SleepNoSkip(ImGuiTestContext* self, float time_in_second, float framestep_in_second) {
    return self->SleepNoSkip(time_in_second, framestep_in_second);
}

CIMGUI_API void ImGuiTestContext_SetRef1(ImGuiTestContext* self, ImGuiTestRef ref) { return self->SetRef(ref); }

CIMGUI_API void ImGuiTestContext_SetRef2(ImGuiTestContext* self, ImGuiWindow* window) { return self->SetRef(window); }

CIMGUI_API ImGuiTestRef ImGuiTestContext_GetRef(ImGuiTestContext* self) { return self->GetRef(); }

CIMGUI_API ImGuiTestItemInfo
ImGuiTestContext_WindowInfo(ImGuiTestContext* self, ImGuiTestRef window_ref, ImGuiTestOpFlags flags) {
    return self->WindowInfo(window_ref, flags);
}

CIMGUI_API void ImGuiTestContext_WindowClose(ImGuiTestContext* self, ImGuiTestRef window_ref) {
    return self->WindowClose(window_ref);
}

CIMGUI_API void ImGuiTestContext_WindowCollapse(ImGuiTestContext* self, ImGuiTestRef window_ref, bool collapsed) {
    return self->WindowCollapse(window_ref, collapsed);
}

CIMGUI_API void ImGuiTestContext_WindowFocus(ImGuiTestContext* self, ImGuiTestRef window_ref, ImGuiTestOpFlags flags) {
    return self->WindowFocus(window_ref, flags);
}

CIMGUI_API void
ImGuiTestContext_WindowBringToFront(ImGuiTestContext* self, ImGuiTestRef window_ref, ImGuiTestOpFlags flags) {
    return self->WindowBringToFront(window_ref, flags);
}

CIMGUI_API void ImGuiTestContext_WindowMove(
    ImGuiTestContext* self,
    ImGuiTestRef window_ref,
    ImVec2 pos,
    ImVec2 pivot,
    ImGuiTestOpFlags flags
) {
    return self->WindowMove(window_ref, pos, pivot, flags);
}

CIMGUI_API void ImGuiTestContext_WindowResize(ImGuiTestContext* self, ImGuiTestRef window_ref, ImVec2 sz) {
    return self->WindowResize(window_ref, sz);
}

CIMGUI_API bool
ImGuiTestContext_WindowTeleportToMakePosVisible(ImGuiTestContext* self, ImGuiTestRef window_ref, ImVec2 pos_in_window) {
    return self->WindowTeleportToMakePosVisible(window_ref, pos_in_window);
}

CIMGUI_API ImGuiWindow* ImGuiTestContext_GetWindowByRef(ImGuiTestContext* self, ImGuiTestRef window_ref) {
    return self->GetWindowByRef(window_ref);
}

CIMGUI_API void ImGuiTestContext_PopupCloseOne(ImGuiTestContext* self) { return self->PopupCloseOne(); }

CIMGUI_API void ImGuiTestContext_PopupCloseAll(ImGuiTestContext* self) { return self->PopupCloseAll(); }

CIMGUI_API ImGuiID ImGuiTestContext_PopupGetWindowID(ImGuiTestContext* self, ImGuiTestRef ref) {
    return self->PopupGetWindowID(ref);
}

CIMGUI_API ImGuiID ImGuiTestContext_GetID(ImGuiTestContext* self, ImGuiTestRef ref) { return self->GetID(ref); }

CIMGUI_API ImGuiID ImGuiTestContext_GetID2(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestRef seed_ref) {
    return self->GetID(ref, seed_ref);
}

CIMGUI_API ImVec2 ImGuiTestContext_GetPosOnVoid(ImGuiTestContext* self, ImGuiViewport* viewport) {
    return self->GetPosOnVoid(viewport);
}

CIMGUI_API ImVec2 ImGuiTestContext_GetWindowTitlebarPoint(ImGuiTestContext* self, ImGuiTestRef window_ref) {
    return self->GetWindowTitlebarPoint(window_ref);
}

CIMGUI_API ImVec2 ImGuiTestContext_GetMainMonitorWorkPos(ImGuiTestContext* self) {
    return self->GetMainMonitorWorkPos();
}

CIMGUI_API ImVec2 ImGuiTestContext_GetMainMonitorWorkSize(ImGuiTestContext* self) {
    return self->GetMainMonitorWorkSize();
}

CIMGUI_API void ImGuiTestContext_CaptureReset(ImGuiTestContext* self) { return self->CaptureReset(); }

CIMGUI_API void ImGuiTestContext_CaptureSetExtension(ImGuiTestContext* self, const char* ext) {
    return self->CaptureSetExtension(ext);
}

CIMGUI_API bool ImGuiTestContext_CaptureAddWindow(ImGuiTestContext* self, ImGuiTestRef ref) {
    return self->CaptureAddWindow(ref);
}

CIMGUI_API void ImGuiTestContext_CaptureScreenshotWindow(ImGuiTestContext* self, ImGuiTestRef ref, int capture_flags) {
    return self->CaptureScreenshotWindow(ref, capture_flags);
}

CIMGUI_API bool ImGuiTestContext_CaptureScreenshot(ImGuiTestContext* self, int capture_flags) {
    return self->CaptureScreenshot(capture_flags);
}

CIMGUI_API bool ImGuiTestContext_CaptureBeginVideo(ImGuiTestContext* self) { return self->CaptureBeginVideo(); }

CIMGUI_API bool ImGuiTestContext_CaptureEndVideo(ImGuiTestContext* self) { return self->CaptureEndVideo(); }

CIMGUI_API void ImGuiTestContext_MouseMove(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags) {
    return self->MouseMove(ref, flags);
}

CIMGUI_API void ImGuiTestContext_MouseMoveToPos(ImGuiTestContext* self, ImVec2 pos) {
    return self->MouseMoveToPos(pos);
}

CIMGUI_API void ImGuiTestContext_MouseTeleportToPos(ImGuiTestContext* self, ImVec2 pos, ImGuiTestOpFlags flags) {
    return self->MouseTeleportToPos(pos, flags);
}

CIMGUI_API void ImGuiTestContext_MouseClick(ImGuiTestContext* self, ImGuiMouseButton button) {
    return self->MouseClick(button);
}

CIMGUI_API void ImGuiTestContext_MouseClickMulti(ImGuiTestContext* self, ImGuiMouseButton button, int count) {
    return self->MouseClickMulti(button, count);
}

CIMGUI_API void ImGuiTestContext_MouseDoubleClick(ImGuiTestContext* self, ImGuiMouseButton button) {
    return self->MouseDoubleClick(button);
}

CIMGUI_API void ImGuiTestContext_MouseDown(ImGuiTestContext* self, ImGuiMouseButton button) {
    return self->MouseDown(button);
}

CIMGUI_API void ImGuiTestContext_MouseUp(ImGuiTestContext* self, ImGuiMouseButton button) {
    return self->MouseUp(button);
}

CIMGUI_API void ImGuiTestContext_MouseLiftDragThreshold(ImGuiTestContext* self, ImGuiMouseButton button) {
    return self->MouseLiftDragThreshold(button);
}

CIMGUI_API void ImGuiTestContext_MouseDragWithDelta(ImGuiTestContext* self, ImVec2 delta, ImGuiMouseButton button) {
    return self->MouseDragWithDelta(delta, button);
}

CIMGUI_API void ImGuiTestContext_MouseWheel(ImGuiTestContext* self, ImVec2 delta) { return self->MouseWheel(delta); }

CIMGUI_API void ImGuiTestContext_MouseWheelX(ImGuiTestContext* self, float dx) { return self->MouseWheelX(dx); }

CIMGUI_API void ImGuiTestContext_MouseWheelY(ImGuiTestContext* self, float dy) { return self->MouseWheelY(dy); }

CIMGUI_API void ImGuiTestContext_MouseMoveToVoid(ImGuiTestContext* self, ImGuiViewport* viewport) {
    return self->MouseMoveToVoid(viewport);
}

CIMGUI_API void
ImGuiTestContext_MouseClickOnVoid(ImGuiTestContext* self, ImGuiMouseButton button, ImGuiViewport* viewport) {
    return self->MouseClickOnVoid(button, viewport);
}

CIMGUI_API ImGuiWindow* ImGuiTestContext_FindHoveredWindowAtPos(ImGuiTestContext* self, const ImVec2* pos) {
    return self->FindHoveredWindowAtPos(*pos);
}

CIMGUI_API bool
ImGuiTestContext_FindExistingVoidPosOnViewport(ImGuiTestContext* self, ImGuiViewport* viewport, ImVec2* out) {
    return self->FindExistingVoidPosOnViewport(viewport, out);
}

CIMGUI_API void ImGuiTestContext_MouseSetViewport(ImGuiTestContext* self, ImGuiWindow* window) {
    return self->MouseSetViewport(window);
}

CIMGUI_API void ImGuiTestContext_MouseSetViewportID(ImGuiTestContext* self, ImGuiID viewport_id) {
    return self->MouseSetViewportID(viewport_id);
}

CIMGUI_API void ImGuiTestContext_KeyDown(ImGuiTestContext* self, ImGuiKeyChord key_chord) {
    return self->KeyDown(key_chord);
}

CIMGUI_API void ImGuiTestContext_KeyUp(ImGuiTestContext* self, ImGuiKeyChord key_chord) {
    return self->KeyUp(key_chord);
}

CIMGUI_API void ImGuiTestContext_KeyPress(ImGuiTestContext* self, ImGuiKeyChord key_chord, int count) {
    return self->KeyPress(key_chord, count);
}

CIMGUI_API void ImGuiTestContext_KeyHold(ImGuiTestContext* self, ImGuiKeyChord key_chord, float time) {
    return self->KeyHold(key_chord, time);
}

CIMGUI_API void ImGuiTestContext_KeySetEx(ImGuiTestContext* self, ImGuiKeyChord key_chord, bool is_down, float time) {
    return self->KeySetEx(key_chord, is_down, time);
}

CIMGUI_API void ImGuiTestContext_KeyChars(ImGuiTestContext* self, const char* chars) { return self->KeyChars(chars); }

CIMGUI_API void ImGuiTestContext_KeyCharsAppend(ImGuiTestContext* self, const char* chars) {
    return self->KeyCharsAppend(chars);
}

CIMGUI_API void ImGuiTestContext_KeyCharsAppendEnter(ImGuiTestContext* self, const char* chars) {
    return self->KeyCharsAppendEnter(chars);
}

CIMGUI_API void ImGuiTestContext_KeyCharsReplace(ImGuiTestContext* self, const char* chars) {
    return self->KeyCharsReplace(chars);
}

CIMGUI_API void ImGuiTestContext_KeyCharsReplaceEnter(ImGuiTestContext* self, const char* chars) {
    return self->KeyCharsReplaceEnter(chars);
}

CIMGUI_API void ImGuiTestContext_SetInputMode(ImGuiTestContext* self, ImGuiInputSource input_mode) {
    return self->SetInputMode(input_mode);
}

CIMGUI_API void ImGuiTestContext_NavMoveTo(ImGuiTestContext* self, ImGuiTestRef ref) { return self->NavMoveTo(ref); }

CIMGUI_API void ImGuiTestContext_NavActivate(ImGuiTestContext* self) { return self->NavActivate(); }

CIMGUI_API void ImGuiTestContext_NavInput(ImGuiTestContext* self) { return self->NavInput(); }

CIMGUI_API void ImGuiTestContext_ScrollTo(
    ImGuiTestContext* self,
    ImGuiTestRef ref,
    ImGuiAxis axis,
    float scroll_v,
    ImGuiTestOpFlags flags
) {
    return self->ScrollTo(ref, axis, scroll_v, flags);
}

CIMGUI_API void ImGuiTestContext_ScrollToX(ImGuiTestContext* self, ImGuiTestRef ref, float scroll_x) {
    return self->ScrollToX(ref, scroll_x);
}

CIMGUI_API void ImGuiTestContext_ScrollToY(ImGuiTestContext* self, ImGuiTestRef ref, float scroll_y) {
    return self->ScrollToY(ref, scroll_y);
}

CIMGUI_API void ImGuiTestContext_ScrollToTop(ImGuiTestContext* self, ImGuiTestRef ref) {
    return self->ScrollToTop(ref);
}

CIMGUI_API void ImGuiTestContext_ScrollToBottom(ImGuiTestContext* self, ImGuiTestRef ref) {
    return self->ScrollToBottom(ref);
}

CIMGUI_API void
ImGuiTestContext_ScrollToItem(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiAxis axis, ImGuiTestOpFlags flags) {
    return self->ScrollToItem(ref, axis, flags);
}

CIMGUI_API void ImGuiTestContext_ScrollToItemX(ImGuiTestContext* self, ImGuiTestRef ref) {
    return self->ScrollToItemX(ref);
}

CIMGUI_API void ImGuiTestContext_ScrollToItemY(ImGuiTestContext* self, ImGuiTestRef ref) {
    return self->ScrollToItemY(ref);
}

CIMGUI_API void ImGuiTestContext_ScrollToTabItem(ImGuiTestContext* self, ImGuiTabBar* tab_bar, ImGuiID tab_id) {
    return self->ScrollToTabItem(tab_bar, tab_id);
}

CIMGUI_API bool ImGuiTestContext_ScrollErrorCheck(
    ImGuiTestContext* self,
    ImGuiAxis axis,
    float expected,
    float actual,
    int* remaining_attempts
) {
    return self->ScrollErrorCheck(axis, expected, actual, remaining_attempts);
}

CIMGUI_API void ImGuiTestContext_ScrollVerifyScrollMax(ImGuiTestContext* self, ImGuiTestRef ref) {
    return self->ScrollVerifyScrollMax(ref);
}

CIMGUI_API ImGuiTestItemInfo
ImGuiTestContext_ItemInfo(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags) {
    return self->ItemInfo(ref, flags);
}

CIMGUI_API ImGuiTestItemInfo
ImGuiTestContext_ItemInfoOpenFullPath(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags) {
    return self->ItemInfoOpenFullPath(ref, flags);
}

CIMGUI_API ImGuiID ImGuiTestContext_ItemInfoHandleWildcardSearch(
    ImGuiTestContext* self,
    const char* wildcard_prefix_start,
    const char* wildcard_prefix_end,
    const char* wildcard_suffix_start
) {
    return self->ItemInfoHandleWildcardSearch(wildcard_prefix_start, wildcard_prefix_end, wildcard_suffix_start);
}

CIMGUI_API ImGuiTestItemInfo ImGuiTestContext_ItemInfoNull(ImGuiTestContext* self) { return self->ItemInfoNull(); }

CIMGUI_API void
ImGuiTestContext_GatherItems(ImGuiTestContext* self, ImGuiTestItemList* out_list, ImGuiTestRef parent, int depth) {
    return self->GatherItems(out_list, parent, depth);
}

CIMGUI_API void ImGuiTestContext_ItemAction(
    ImGuiTestContext* self,
    ImGuiTestAction action,
    ImGuiTestRef ref,
    ImGuiTestOpFlags flags,
    void* action_arg
) {
    return self->ItemAction(action, ref, flags, action_arg);
}

CIMGUI_API void
ImGuiTestContext_ItemClick(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiMouseButton button, ImGuiTestOpFlags flags) {
    return self->ItemClick(ref, button, flags);
}

CIMGUI_API void ImGuiTestContext_ItemDoubleClick(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags) {
    return self->ItemDoubleClick(ref, flags);
}

CIMGUI_API void ImGuiTestContext_ItemCheck(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags) {
    return self->ItemCheck(ref, flags);
}

CIMGUI_API void ImGuiTestContext_ItemUncheck(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags) {
    return self->ItemUncheck(ref, flags);
}

CIMGUI_API void ImGuiTestContext_ItemOpen(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags) {
    return self->ItemOpen(ref, flags);
}

CIMGUI_API void ImGuiTestContext_ItemClose(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags) {
    return self->ItemClose(ref, flags);
}

CIMGUI_API void ImGuiTestContext_ItemInput(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags) {
    return self->ItemInput(ref, flags);
}

CIMGUI_API void ImGuiTestContext_ItemNavActivate(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags) {
    return self->ItemNavActivate(ref, flags);
}

// Not implemented in imgui_te_context.cpp
// CIMGUI_API bool ImGuiTestContext_ItemOpenFullPath(ImGuiTestContext* self, ImGuiTestRef ref) {
//     return self->ItemOpenFullPath(ref);
// }

CIMGUI_API void ImGuiTestContext_ItemActionAll(
    ImGuiTestContext* self,
    ImGuiTestAction action,
    ImGuiTestRef ref_parent,
    const ImGuiTestActionFilter* filter
) {
    return self->ItemActionAll(action, ref_parent, filter);
}

CIMGUI_API void ImGuiTestContext_ItemOpenAll(ImGuiTestContext* self, ImGuiTestRef ref_parent, int depth, int passes) {
    return self->ItemOpenAll(ref_parent, depth, passes);
}

CIMGUI_API void ImGuiTestContext_ItemCloseAll(ImGuiTestContext* self, ImGuiTestRef ref_parent, int depth, int passes) {
    return self->ItemCloseAll(ref_parent, depth, passes);
}

CIMGUI_API void ImGuiTestContext_ItemInputValueInt(ImGuiTestContext* self, ImGuiTestRef ref, int v) {
    return self->ItemInputValue(ref, v);
}

CIMGUI_API void ImGuiTestContext_ItemInputValueFloat(ImGuiTestContext* self, ImGuiTestRef ref, float f) {
    return self->ItemInputValue(ref, f);
}

CIMGUI_API void ImGuiTestContext_ItemInputValueStr(ImGuiTestContext* self, ImGuiTestRef ref, const char* str) {
    return self->ItemInputValue(ref, str);
}

CIMGUI_API int ImGuiTestContext_ItemReadAsInt(ImGuiTestContext* self, ImGuiTestRef ref) {
    return self->ItemReadAsInt(ref);
}

CIMGUI_API float ImGuiTestContext_ItemReadAsFloat(ImGuiTestContext* self, ImGuiTestRef ref) {
    return self->ItemReadAsFloat(ref);
}

CIMGUI_API bool ImGuiTestContext_ItemReadAsScalar(
    ImGuiTestContext* self,
    ImGuiTestRef ref,
    ImGuiDataType data_type,
    void* out_data,
    ImGuiTestOpFlags flags
) {
    return self->ItemReadAsScalar(ref, data_type, out_data, flags);
}

CIMGUI_API const char* ImGuiTestContext_ItemReadAsString(ImGuiTestContext* self, ImGuiTestRef ref) {
    return self->ItemReadAsString(ref);
}

CIMGUI_API size_t
ImGuiTestContext_ItemReadAsStringBuff(ImGuiTestContext* self, ImGuiTestRef ref, char* out_buf, size_t out_buf_size) {
    return self->ItemReadAsString(ref, out_buf, out_buf_size);
}

CIMGUI_API bool ImGuiTestContext_ItemExists(ImGuiTestContext* self, ImGuiTestRef ref) { return self->ItemExists(ref); }

CIMGUI_API bool ImGuiTestContext_ItemIsChecked(ImGuiTestContext* self, ImGuiTestRef ref) {
    return self->ItemIsChecked(ref);
}

CIMGUI_API bool ImGuiTestContext_ItemIsOpened(ImGuiTestContext* self, ImGuiTestRef ref) {
    return self->ItemIsOpened(ref);
}

CIMGUI_API void ImGuiTestContext_ItemVerifyCheckedIfAlive(ImGuiTestContext* self, ImGuiTestRef ref, bool checked) {
    return self->ItemVerifyCheckedIfAlive(ref, checked);
}

CIMGUI_API void ImGuiTestContext_ItemHold(ImGuiTestContext* self, ImGuiTestRef ref, float time) {
    return self->ItemHold(ref, time);
}

CIMGUI_API void ImGuiTestContext_ItemHoldForFrames(ImGuiTestContext* self, ImGuiTestRef ref, int frames) {
    return self->ItemHoldForFrames(ref, frames);
}

CIMGUI_API void
ImGuiTestContext_ItemDragOverAndHold(ImGuiTestContext* self, ImGuiTestRef ref_src, ImGuiTestRef ref_dst) {
    return self->ItemDragOverAndHold(ref_src, ref_dst);
}

CIMGUI_API void ImGuiTestContext_ItemDragAndDrop(
    ImGuiTestContext* self,
    ImGuiTestRef ref_src,
    ImGuiTestRef ref_dst,
    ImGuiMouseButton button
) {
    return self->ItemDragAndDrop(ref_src, ref_dst, button);
}

CIMGUI_API void ImGuiTestContext_ItemDragWithDelta(ImGuiTestContext* self, ImGuiTestRef ref_src, ImVec2 pos_delta) {
    return self->ItemDragWithDelta(ref_src, pos_delta);
}

CIMGUI_API void ImGuiTestContext_TabClose(ImGuiTestContext* self, ImGuiTestRef ref) { return self->TabClose(ref); }

CIMGUI_API bool
ImGuiTestContext_TabBarCompareOrder(ImGuiTestContext* self, ImGuiTabBar* tab_bar, const char** tab_order) {
    return self->TabBarCompareOrder(tab_bar, tab_order);
}

CIMGUI_API void ImGuiTestContext_MenuAction(ImGuiTestContext* self, ImGuiTestAction action, ImGuiTestRef ref) {
    return self->MenuAction(action, ref);
}

CIMGUI_API void
ImGuiTestContext_MenuActionAll(ImGuiTestContext* self, ImGuiTestAction action, ImGuiTestRef ref_parent) {
    return self->MenuActionAll(action, ref_parent);
}

CIMGUI_API void ImGuiTestContext_MenuClick(ImGuiTestContext* self, ImGuiTestRef ref) { return self->MenuClick(ref); }

CIMGUI_API void ImGuiTestContext_MenuCheck(ImGuiTestContext* self, ImGuiTestRef ref) { return self->MenuCheck(ref); }

CIMGUI_API void ImGuiTestContext_MenuUncheck(ImGuiTestContext* self, ImGuiTestRef ref) {
    return self->MenuUncheck(ref);
}

CIMGUI_API void ImGuiTestContext_MenuCheckAll(ImGuiTestContext* self, ImGuiTestRef ref_parent) {
    return self->MenuCheckAll(ref_parent);
}

CIMGUI_API void ImGuiTestContext_MenuUncheckAll(ImGuiTestContext* self, ImGuiTestRef ref_parent) {
    return self->MenuUncheckAll(ref_parent);
}

CIMGUI_API void ImGuiTestContext_ComboClick(ImGuiTestContext* self, ImGuiTestRef ref) { return self->ComboClick(ref); }

CIMGUI_API void ImGuiTestContext_ComboClickAll(ImGuiTestContext* self, ImGuiTestRef ref) {
    return self->ComboClickAll(ref);
}

CIMGUI_API void ImGuiTestContext_TableOpenContextMenu(ImGuiTestContext* self, ImGuiTestRef ref, int column_n) {
    return self->TableOpenContextMenu(ref, column_n);
}

CIMGUI_API ImGuiSortDirection
ImGuiTestContext_TableClickHeader(ImGuiTestContext* self, ImGuiTestRef ref, const char* label, ImGuiKeyChord key_mods) {
    return self->TableClickHeader(ref, label, key_mods);
}

CIMGUI_API void
ImGuiTestContext_TableSetColumnEnabled(ImGuiTestContext* self, ImGuiTestRef ref, const char* label, bool enabled) {
    return self->TableSetColumnEnabled(ref, label, enabled);
}

CIMGUI_API void
ImGuiTestContext_TableResizeColumn(ImGuiTestContext* self, ImGuiTestRef ref, int column_n, float width) {
    return self->TableResizeColumn(ref, column_n, width);
}

CIMGUI_API const ImGuiTableSortSpecs* ImGuiTestContext_TableGetSortSpecs(ImGuiTestContext* self, ImGuiTestRef ref) {
    return self->TableGetSortSpecs(ref);
}

#ifdef IMGUI_HAS_VIEWPORT

CIMGUI_API void
ImGuiTestContext_ViewportPlatform_SetWindowPos(ImGuiTestContext* self, ImGuiViewport* viewport, const ImVec2* pos) {
    return self->ViewportPlatform_SetWindowPos(viewport, *pos);
}

CIMGUI_API void
ImGuiTestContext_ViewportPlatform_SetWindowSize(ImGuiTestContext* self, ImGuiViewport* viewport, const ImVec2* size) {
    return self->ViewportPlatform_SetWindowSize(viewport, *size);
}

CIMGUI_API void ImGuiTestContext_ViewportPlatform_SetWindowFocus(ImGuiTestContext* self, ImGuiViewport* viewport) {
    return self->ViewportPlatform_SetWindowFocus(viewport);
}

CIMGUI_API void ImGuiTestContext_ViewportPlatform_CloseWindow(ImGuiTestContext* self, ImGuiViewport* viewport) {
    return self->ViewportPlatform_CloseWindow(viewport);
}

#endif  // IMGUI_HAS_VIEWPORT

#ifdef IMGUI_HAS_DOCK

CIMGUI_API void ImGuiTestContext_DockClear(ImGuiTestContext* self, const char* window_name) {
    va_list args;
    va_start(args, fmt);
    self->DockClear("%s", window_name);
    va_end(args);
}
CIMGUI_API void ImGuiTestContext_DockInto(
    ImGuiTestContext* self,
    ImGuiTestRef src_id,
    ImGuiTestRef dst_id,
    ImGuiDir split_dir,
    bool is_outer_docking,
    ImGuiTestOpFlags flags
) {
    return self->DockInto(src_id, dst_id, split_dir, is_outer_docking, flags);
}
CIMGUI_API void ImGuiTestContext_UndockNode(ImGuiTestContext* self, ImGuiID dock_id) {
    return self->UndockNode(dock_id);
}
CIMGUI_API void ImGuiTestContext_UndockWindow(ImGuiTestContext* self, const char* window_name) {
    return self->UndockWindow(window_name);
}
CIMGUI_API bool ImGuiTestContext_WindowIsUndockedOrStandalone(ImGuiTestContext* self, ImGuiWindow* window) {
    return self->WindowIsUndockedOrStandalone(window);
}
CIMGUI_API bool ImGuiTestContext_DockIdIsUndockedOrStandalone(ImGuiTestContext* self, ImGuiID dock_id) {
    return self->DockIdIsUndockedOrStandalone(dock_id);
}
CIMGUI_API void ImGuiTestContext_DockNodeHideTabBar(ImGuiTestContext* self, ImGuiDockNode* node, bool hidden) {
    return self->DockNodeHideTabBar(node, hidden);
}

#endif  // IMGUI_HAS_DOCK

CIMGUI_API void ImGuiTestContext_PerfCalcRef(ImGuiTestContext* self) { return self->PerfCalcRef(); }

CIMGUI_API void ImGuiTestContext_PerfCapture(
    ImGuiTestContext* self,
    const char* category,
    const char* test_name,
    const char* csv_file
) {
    return self->PerfCapture(category, test_name, csv_file);
}

// Custom functions:

CIMGUI_API void teClearUiState() {
    ImGuiContext& context = *ImGui::GetCurrentContext();
    for (ImGuiWindow* window : context.Windows) {
        window->StateStorage.Clear();
    }
}

CIMGUI_API float ImGuiTestContext_GetScrollX(ImGuiTestContext* self, ImGuiTestRef window_ref) {
    return self->GetWindowByRef(window_ref)->Scroll.x;
}

CIMGUI_API float ImGuiTestContext_GetScrollY(ImGuiTestContext* self, ImGuiTestRef window_ref) {
    return self->GetWindowByRef(window_ref)->Scroll.y;
}

CIMGUI_API float ImGuiTestContext_GetScrollMaxX(ImGuiTestContext* self, ImGuiTestRef window_ref) {
    return self->GetWindowByRef(window_ref)->ScrollMax.x;
}

CIMGUI_API float ImGuiTestContext_GetScrollMaxY(ImGuiTestContext* self, ImGuiTestRef window_ref) {
    return self->GetWindowByRef(window_ref)->ScrollMax.y;
}
