#include "./imgui/imgui.h"
#include "./imgui_test_engine/imgui_te_engine.h"

#include "cimgui_test_engine.h"

CIMGUI_API void teItemAdd(ImGuiContext* ui_ctx, ImGuiID id, const ImRect* bb, const ImGuiLastItemData* item_data) {
    return ImGuiTestEngineHook_ItemAdd(ui_ctx, id, *bb, item_data);
}

CIMGUI_API void teItemInfo(ImGuiContext* ui_ctx, ImGuiID id, const char* label, ImGuiItemStatusFlags flags) {
    return ImGuiTestEngineHook_ItemInfo(ui_ctx, id, label, flags);
}

CIMGUI_API void teLog(ImGuiContext* ui_ctx, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    ImGuiTestEngineHook_Log(ui_ctx, fmt, args);
    va_end(args);
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

CIMGUI_API bool teError(const char* file, const char* func, int line, ImGuiTestCheckFlags flags, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    auto return_value = ImGuiTestEngine_Error(file, func, line, line, fmt, args);
    va_end(args);
    return return_value;
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

CIMGUI_API void teGetResult(ImGuiTestEngine* engine, int* count_tested, int* success_count) {
    return ImGuiTestEngine_GetResult(engine, *count_tested, *success_count);
}

CIMGUI_API void teGetTestList(ImGuiTestEngine* engine, ImVector_ImGuiTestPtr* out_tests) {
    return ImGuiTestEngine_GetTestList(engine, out_tests);
}

CIMGUI_API void teGetTestQueue(ImGuiTestEngine* engine, ImVector_ImGuiTestRunTask* out_tests) {
    return ImGuiTestEngine_GetTestQueue(engine, out_tests);
}

CIMGUI_API void teInstallDefaultCrashHandler() { return ImGuiTestEngine_InstallDefaultCrashHandler(); }

CIMGUI_API void teCrashHandler() { return ImGuiTestEngine_CrashHandler(); }

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
