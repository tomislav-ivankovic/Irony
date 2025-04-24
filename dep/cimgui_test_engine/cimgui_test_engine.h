#include "cimgui.h"

#ifdef CIMGUI_DEFINE_ENUMS_AND_STRUCTS

typedef int ImGuiTestFlags;
enum ImGuiTestFlags_ {
    ImGuiTestFlags_None = 0,
    ImGuiTestFlags_NoGuiWarmUp = 1 << 0,
    ImGuiTestFlags_NoAutoFinish = 1 << 1,
    ImGuiTestFlags_NoRecoveryWarnings = 1 << 2
};
typedef int ImGuiTestCheckFlags;
enum ImGuiTestCheckFlags_ { ImGuiTestCheckFlags_None = 0, ImGuiTestCheckFlags_SilentSuccess = 1 << 0 };
typedef int ImGuiTestLogFlags;
typedef enum ImGuiTestLogFlags_ { ImGuiTestLogFlags_None = 0, ImGuiTestLogFlags_NoHeader = 1 << 0 };
typedef int ImGuiTestRunFlags;
enum ImGuiTestRunFlags_ {
    ImGuiTestRunFlags_None = 0,
    ImGuiTestRunFlags_GuiFuncDisable = 1 << 0,
    ImGuiTestRunFlags_GuiFuncOnly = 1 << 1,
    ImGuiTestRunFlags_NoSuccessMsg = 1 << 2,
    ImGuiTestRunFlags_EnableRawInputs = 1 << 3,
    ImGuiTestRunFlags_RunFromGui = 1 << 4,
    ImGuiTestRunFlags_RunFromCommandLine = 1 << 5,
    ImGuiTestRunFlags_NoError = 1 << 10,
    ImGuiTestRunFlags_ShareVars = 1 << 11,
    ImGuiTestRunFlags_ShareTestContext = 1 << 12,
};
typedef int ImGuiTestActiveFunc;
typedef enum {
    ImGuiTestActiveFunc_None,
    ImGuiTestActiveFunc_GuiFunc,
    ImGuiTestActiveFunc_TestFunc
} ImGuiTestActiveFunc_;
typedef int ImGuiTestGroup;
typedef enum {
    ImGuiTestGroup_Unknown = -1,
    ImGuiTestGroup_Tests = 0,
    ImGuiTestGroup_Perfs = 1,
    ImGuiTestGroup_COUNT
} ImGuiTestGroup_;
typedef int ImGuiTestRunSpeed;
typedef enum {
    ImGuiTestRunSpeed_Fast = 0,
    ImGuiTestRunSpeed_Normal = 1,
    ImGuiTestRunSpeed_Cinematic = 2,
    ImGuiTestRunSpeed_COUNT
} ImGuiTestRunSpeed_;
typedef int ImGuiTestStatus;
typedef enum {
    ImGuiTestStatus_Unknown = 0,
    ImGuiTestStatus_Success = 1,
    ImGuiTestStatus_Queued = 2,
    ImGuiTestStatus_Running = 3,
    ImGuiTestStatus_Error = 4,
    ImGuiTestStatus_Suspended = 5,
    ImGuiTestStatus_COUNT
} ImGuiTestStatus_;
typedef int ImGuiTestVerboseLevel;
typedef enum {
    ImGuiTestVerboseLevel_Silent = 0,
    ImGuiTestVerboseLevel_Error = 1,
    ImGuiTestVerboseLevel_Warning = 2,
    ImGuiTestVerboseLevel_Info = 3,
    ImGuiTestVerboseLevel_Debug = 4,
    ImGuiTestVerboseLevel_Trace = 5,
    ImGuiTestVerboseLevel_COUNT
} ImGuiTestVerboseLevel_;
typedef int ImGuiTestOpFlags;
typedef enum {
    ImGuiTestOpFlags_None = 0,
    ImGuiTestOpFlags_NoCheckHoveredId = 1 << 1,
    ImGuiTestOpFlags_NoError = 1 << 2,
    ImGuiTestOpFlags_NoFocusWindow = 1 << 3,
    ImGuiTestOpFlags_NoAutoUncollapse = 1 << 4,
    ImGuiTestOpFlags_NoAutoOpenFullPath = 1 << 5,
    ImGuiTestOpFlags_NoYield = 1 << 6,
    ImGuiTestOpFlags_IsSecondAttempt = 1 << 7,
    ImGuiTestOpFlags_MoveToEdgeL = 1 << 8,
    ImGuiTestOpFlags_MoveToEdgeR = 1 << 9,
    ImGuiTestOpFlags_MoveToEdgeU = 1 << 10,
    ImGuiTestOpFlags_MoveToEdgeD = 1 << 11,
} ImGuiTestOpFlags_;
typedef char ImGuiTestAction;
typedef enum {
    ImGuiTestAction_Unknown = 0,
    ImGuiTestAction_Hover,
    ImGuiTestAction_Click,
    ImGuiTestAction_DoubleClick,
    ImGuiTestAction_Check,
    ImGuiTestAction_Uncheck,
    ImGuiTestAction_Open,
    ImGuiTestAction_Close,
    ImGuiTestAction_Input,
    ImGuiTestAction_NavActivate,
    ImGuiTestAction_COUNT
} ImGuiTestAction_;
typedef int ImGuiTestEngineExportFormat;

typedef struct ImGuiTestCoroutineInterface ImGuiTestCoroutineInterface;
typedef struct ImGuiTestEngine ImGuiTestEngine;
typedef struct ImGuiTestInputs ImGuiTestInputs;
typedef struct ImGuiCaptureArgs ImGuiCaptureArgs;

typedef struct ImGuiTestEngineIO ImGuiTestEngineIO;
typedef struct ImGuiTestItemInfo ImGuiTestItemInfo;
typedef struct ImGuiTestItemList ImGuiTestItemList;
typedef struct ImGuiTestLogLineInfo ImGuiTestLogLineInfo;
typedef struct ImGuiTestLog ImGuiTestLog;
typedef struct ImGuiTestOutput ImGuiTestOutput;
typedef struct ImGuiTest ImGuiTest;
typedef struct ImGuiTestRunTask ImGuiTestRunTask;
typedef struct ImGuiTestRef ImGuiTestRef;
typedef struct ImGuiTestRefDesc ImGuiTestRefDesc;
typedef struct ImGuiTestActionFilter ImGuiTestActionFilter;
typedef struct ImGuiTestGenericItemStatus ImGuiTestGenericItemStatus;
typedef struct ImGuiTestGenericVars ImGuiTestGenericVars;
typedef struct ImGuiTestContext ImGuiTestContext;

typedef struct ImVector_ImGuiTestPtr {
    int Size;
    int Capacity;
    ImGuiTest** Data;
} ImVector_ImGuiTestPtr;
typedef struct ImVector_ImGuiTestRunTask {
    int Size;
    int Capacity;
    ImGuiTestRunTask* Data;
} ImVector_ImGuiTestRunTask;
typedef struct ImVector_ImGuiTestItemInfo {
    int Size;
    int Capacity;
    ImGuiTestItemInfo* Data;
} ImVector_ImGuiTestItemInfo;
typedef struct ImVector_ImGuiTestLogLineInfo {
    int Size;
    int Capacity;
    ImGuiTestLogLineInfo* Data;
} ImVector_ImGuiTestLogLineInfo;
typedef struct ImPool_ImGuiTestItemInfo {
    ImVector_ImGuiTestItemInfo Buf;
    ImGuiStorage Map;
    ImPoolIdx FreeIdx;
    ImPoolIdx AliveCount;
} ImPool_ImGuiTestItemInfo;

typedef void(ImGuiTestEngineSrcFileOpenFunc)(const char* filename, int line_no, void* user_data);
typedef void(ImGuiTestGuiFunc)(ImGuiTestContext* ctx);
typedef void(ImGuiTestTestFunc)(ImGuiTestContext* ctx);
typedef void(ImGuiTestVarsConstructor)(void* buffer);
typedef void(ImGuiTestVarsPostConstructor)(ImGuiTestContext* ctx, void* ptr, void* fn);
typedef void(ImGuiTestVarsDestructor)(void* ptr);
typedef void(ImGuiTestEngineSrcFileOpenFunc)(const char* filename, int line_no, void* user_data);
typedef void(ImGuiTestGuiFunc)(ImGuiTestContext* ctx);
typedef void(ImGuiTestTestFunc)(ImGuiTestContext* ctx);
typedef void(ImGuiTestVarsConstructor)(void* buffer);
typedef void(ImGuiTestVarsPostConstructor)(ImGuiTestContext* ctx, void* ptr, void* fn);
typedef void(ImGuiTestVarsDestructor)(void* ptr);
typedef bool(ImGuiScreenCaptureFunc)(
    ImGuiID viewport_id,
    int x,
    int y,
    int w,
    int h,
    unsigned int* pixels,
    void* user_data
);

struct ImGuiTestEngineIO {
    ImGuiTestCoroutineInterface* CoroutineFuncs;
    ImGuiTestEngineSrcFileOpenFunc* SrcFileOpenFunc;
    ImGuiScreenCaptureFunc* ScreenCaptureFunc;
    void* SrcFileOpenUserData;
    void* ScreenCaptureUserData;
    bool ConfigSavedSettings;
    ImGuiTestRunSpeed ConfigRunSpeed;
    bool ConfigStopOnError;
    bool ConfigBreakOnError;
    bool ConfigKeepGuiFunc;
    ImGuiTestVerboseLevel ConfigVerboseLevel;
    ImGuiTestVerboseLevel ConfigVerboseLevelOnError;
    bool ConfigLogToTTY;
    bool ConfigLogToDebugger;
    bool ConfigRestoreFocusAfterTests;
    bool ConfigCaptureEnabled;
    bool ConfigCaptureOnError;
    bool ConfigNoThrottle;
    bool ConfigMouseDrawCursor;
    float ConfigFixedDeltaTime;
    int PerfStressAmount;
    char GitBranchName[64];
    float MouseSpeed;
    float MouseWobble;
    float ScrollSpeed;
    float TypingSpeed;
    float ActionDelayShort;
    float ActionDelayStandard;
    char VideoCaptureEncoderPath[256];
    char VideoCaptureEncoderParams[256];
    char GifCaptureEncoderParams[512];
    char VideoCaptureExtension[8];
    float ConfigWatchdogWarning;
    float ConfigWatchdogKillTest;
    float ConfigWatchdogKillApp;
    const char* ExportResultsFilename;
    ImGuiTestEngineExportFormat ExportResultsFormat;
    bool CheckDrawDataIntegrity;
    bool IsRunningTests;
    bool IsRequestingMaxAppSpeed;
    bool IsCapturing;
};
struct ImGuiTestItemInfo {
    ImGuiID ID;
    char DebugLabel[32];
    ImGuiWindow* Window;
    unsigned int NavLayer;
    int Depth;
    int TimestampMain;
    int TimestampStatus;
    ImGuiID ParentID;
    ImRect RectFull;
    ImRect RectClipped;
    ImGuiItemFlags ItemFlags;
    ImGuiItemStatusFlags StatusFlags;
};
struct ImGuiTestItemList {
    ImPool_ImGuiTestItemInfo Pool;
};
struct ImGuiTestLogLineInfo {
    ImGuiTestVerboseLevel Level;
    int LineOffset;
};
struct ImGuiTestLog {
    ImGuiTextBuffer Buffer;
    ImVector_ImGuiTestLogLineInfo LineInfo;
    int CountPerLevel[ImGuiTestVerboseLevel_COUNT];
};
struct ImGuiTestOutput {
    ImGuiTestStatus Status;
    ImGuiTestLog Log;
    ImU64 StartTime;
    ImU64 EndTime;
};
struct ImGuiTest {
    const char* Category;
    const char* Name;
    ImGuiTestGroup Group;
    bool NameOwned;
    int ArgVariant;
    ImGuiTestFlags Flags;
    ImGuiTestGuiFunc* GuiFunc;
    ImGuiTestTestFunc* TestFunc;
    void* UserData;
    const char* SourceFile;
    int SourceLine;
    int SourceLineEnd;
    ImGuiTestOutput Output;
    size_t VarsSize;
    ImGuiTestVarsConstructor* VarsConstructor;
    ImGuiTestVarsPostConstructor* VarsPostConstructor;
    void* VarsPostConstructorUserFn;
    ImGuiTestVarsDestructor* VarsDestructor;
};
struct ImGuiTestRunTask {
    ImGuiTest* Test;
    ImGuiTestRunFlags RunFlags;
};
struct ImGuiTestRef {
    ImGuiID ID;
    const char* Path;
};
struct ImGuiTestRefDesc {
    char Buf[80];
};
struct ImGuiTestActionFilter {
    int MaxDepth;
    int MaxPasses;
    const int* MaxItemCountPerDepth;
    ImGuiItemStatusFlags RequireAllStatusFlags;
    ImGuiItemStatusFlags RequireAnyStatusFlags;
};
struct ImGuiTestGenericItemStatus {
    int RetValue;
    int Hovered;
    int Active;
    int Focused;
    int Clicked;
    int Visible;
    int Edited;
    int Activated;
    int Deactivated;
    int DeactivatedAfterEdit;
};
struct ImGuiTestGenericVars {
    int Step;
    int Count;
    ImGuiID DockId;
    ImGuiID OwnerId;
    ImVec2 WindowSize;
    ImGuiWindowFlags WindowFlags;
    ImGuiTableFlags TableFlags;
    ImGuiPopupFlags PopupFlags;
    ImGuiTestGenericItemStatus Status;
    bool ShowWindow1, ShowWindow2;
    bool UseClipper;
    bool UseViewports;
    float Width;
    ImVec2 Pos;
    ImVec2 Pivot;
    ImVec2 ItemSize;
    ImVec4 Color1, Color2;
    int Int1, Int2, IntArray[10];
    float Float1, Float2, FloatArray[10];
    bool Bool1, Bool2, BoolArray[10];
    ImGuiID Id, IdArray[10];
    char Str1[256], Str2[256];
};
struct ImGuiTestContext {
    ImGuiTestGenericVars GenericVars;
    void* UserVars;
    ImGuiContext* UiContext;
    ImGuiTestEngineIO* EngineIO;
    ImGuiTest* Test;
    ImGuiTestOutput* TestOutput;
    ImGuiTestOpFlags OpFlags;
    int PerfStressAmount;
    int FrameCount;
    int FirstTestFrameCount;
    bool FirstGuiFrame;
    bool HasDock;
    ImGuiCaptureArgs* CaptureArgs;
    ImGuiTestEngine* Engine;
    ImGuiTestInputs* Inputs;
    ImGuiTestRunFlags RunFlags;
    ImGuiTestActiveFunc ActiveFunc;
    double RunningTime;
    int ActionDepth;
    int CaptureCounter;
    int ErrorCounter;
    bool Abort;
    double PerfRefDt;
    int PerfIterations;
    char RefStr[256];
    ImGuiID RefID;
    ImGuiID RefWindowID;
    ImGuiInputSource InputMode;
    ImVector_char TempString;
    ImVector_char Clipboard;
    ImVector_ImGuiWindowPtr ForeignWindowsToHide;
    ImGuiTestItemInfo DummyItemInfoNull;
    bool CachedLinesPrintedToTTY;
};

#endif  // CIMGUI_DEFINE_ENUMS_AND_STRUCTS

#ifndef CIMGUI_DEFINE_ENUMS_AND_STRUCTS

typedef ImVector<ImGuiTest*> ImVector_ImGuiTestPtr;
typedef ImVector<ImGuiTestRunTask> ImVector_ImGuiTestRunTask;
typedef ImVector<ImGuiTestItemInfo> ImVector_ImGuiTestItemInfo;
typedef ImVector<ImGuiTestLogLineInfo> ImVector_ImGuiTestLogLineInfo;
typedef ImPool<ImGuiTestItemInfo> ImPool_ImGuiTestItemInfo;

#endif  // CIMGUI_DEFINE_ENUMS_AND_STRUCTS

CIMGUI_API void teItemAdd(ImGuiContext* ui_ctx, ImGuiID id, const ImRect* bb, const ImGuiLastItemData* item_data);
CIMGUI_API void teItemInfo(ImGuiContext* ui_ctx, ImGuiID id, const char* label, ImGuiItemStatusFlags flags);
CIMGUI_API void teLog(ImGuiContext* ui_ctx, const char* fmt, ...);
CIMGUI_API const char* teFindItemDebugLabel(ImGuiContext* ui_ctx, ImGuiID id);
CIMGUI_API bool
teCheck(const char* file, const char* func, int line, ImGuiTestCheckFlags flags, bool result, const char* expr);
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
);
CIMGUI_API bool teError(const char* file, const char* func, int line, ImGuiTestCheckFlags flags, const char* fmt, ...);
CIMGUI_API void teAssertLog(const char* expr, const char* file, const char* function, int line);
CIMGUI_API ImGuiTextBuffer* teGetTempStringBuilder();
CIMGUI_API ImGuiTestEngine* teCreateContext();
CIMGUI_API void teDestroyContext(ImGuiTestEngine* engine);
CIMGUI_API void teStart(ImGuiTestEngine* engine, ImGuiContext* ui_ctx);
CIMGUI_API void teStop(ImGuiTestEngine* engine);
CIMGUI_API void tePostSwap(ImGuiTestEngine* engine);
CIMGUI_API ImGuiTestEngineIO* teGetIO(ImGuiTestEngine* engine);
CIMGUI_API ImGuiTest*
teRegisterTest(ImGuiTestEngine* engine, const char* category, const char* name, const char* src_file, int src_line);
CIMGUI_API void teUnregisterTest(ImGuiTestEngine* engine, ImGuiTest* test);
CIMGUI_API void teUnregisterAllTests(ImGuiTestEngine* engine);
CIMGUI_API void teQueueTest(ImGuiTestEngine* engine, ImGuiTest* test, ImGuiTestRunFlags run_flags);
CIMGUI_API void
teQueueTests(ImGuiTestEngine* engine, ImGuiTestGroup group, const char* filter, ImGuiTestRunFlags run_flags);
CIMGUI_API bool teTryAbortEngine(ImGuiTestEngine* engine);
CIMGUI_API void teAbortCurrentTest(ImGuiTestEngine* engine);
CIMGUI_API ImGuiTest* teFindTestByName(ImGuiTestEngine* engine, const char* category, const char* name);
CIMGUI_API bool teIsTestQueueEmpty(ImGuiTestEngine* engine);
CIMGUI_API bool teIsUsingSimulatedInputs(ImGuiTestEngine* engine);
CIMGUI_API void teGetResult(ImGuiTestEngine* engine, int* count_tested, int* success_count);
CIMGUI_API void teGetTestList(ImGuiTestEngine* engine, ImVector_ImGuiTestPtr* out_tests);
CIMGUI_API void teGetTestQueue(ImGuiTestEngine* engine, ImVector_ImGuiTestRunTask* out_tests);
CIMGUI_API void teInstallDefaultCrashHandler();
CIMGUI_API void teCrashHandler();
CIMGUI_API ImGuiTestEngineIO* ImGuiTestEngineIO_ImGuiTestEngineIO(void);
CIMGUI_API void ImGuiTestEngineIO_destroy(ImGuiTestEngineIO* self);
CIMGUI_API ImGuiTestItemInfo* ImGuiTestItemInfo_ImGuiTestItemInfo(void);
CIMGUI_API void ImGuiTestItemInfo_destroy(ImGuiTestItemInfo* self);
CIMGUI_API ImGuiTestItemList* ImGuiTestItemList_ImGuiTestItemList(void);
CIMGUI_API void ImGuiTestItemList_destroy(ImGuiTestItemList* self);
CIMGUI_API void ImGuiTestItemList_Clear(ImGuiTestItemList* self);
CIMGUI_API void ImGuiTestItemList_Reserve(ImGuiTestItemList* self, int capacity);
CIMGUI_API int ImGuiTestItemList_GetSize(const ImGuiTestItemList* self);
CIMGUI_API const ImGuiTestItemInfo* ImGuiTestItemList_GetByIndex(ImGuiTestItemList* self, int n);
CIMGUI_API const ImGuiTestItemInfo* ImGuiTestItemList_GetByID(ImGuiTestItemList* self, ImGuiID id);
CIMGUI_API size_t ImGuiTestItemList_size(const ImGuiTestItemList* self);
CIMGUI_API const ImGuiTestItemInfo* ImGuiTestItemList_begin(const ImGuiTestItemList* self);
CIMGUI_API const ImGuiTestItemInfo* ImGuiTestItemList_end(const ImGuiTestItemList* self);
CIMGUI_API const ImGuiTestItemInfo* ImGuiTestItemList_at(ImGuiTestItemList* self, size_t n);
CIMGUI_API ImGuiTestLogLineInfo* ImGuiTestLogLineInfo_ImGuiTestLogLineInfo(void);
CIMGUI_API void ImGuiTestLogLineInfo_destroy(ImGuiTestLogLineInfo* self);
CIMGUI_API ImGuiTestLog* ImGuiTestLog_ImGuiTestLog(void);
CIMGUI_API void ImGuiTestLog_destroy(ImGuiTestLog* self);
CIMGUI_API bool ImGuiTestLog_IsEmpty(const ImGuiTestLog* self);
CIMGUI_API void ImGuiTestLog_Clear(ImGuiTestLog* self);
CIMGUI_API int ImGuiTestLog_ExtractLinesForVerboseLevels(
    ImGuiTestLog* self,
    ImGuiTestVerboseLevel level_min,
    ImGuiTestVerboseLevel level_max,
    ImGuiTextBuffer* out_buffer
);
CIMGUI_API void ImGuiTestLog_UpdateLineOffsets(
    ImGuiTestLog* self,
    ImGuiTestEngineIO* engine_io,
    ImGuiTestVerboseLevel level,
    const char* start
);
CIMGUI_API ImGuiTestOutput* ImGuiTestOutput_ImGuiTestOutput(void);
CIMGUI_API void ImGuiTestOutput_destroy(ImGuiTestOutput* self);
CIMGUI_API ImGuiTest* ImGuiTest_ImGuiTest(void);
CIMGUI_API void ImGuiTest_destroy(ImGuiTest* self);
CIMGUI_API void ImGuiTest_SetOwnedName(ImGuiTest* self, const char* name);
// Skipped ImGuiTest_SetVarsDataType because it uses templates.
CIMGUI_API ImGuiTestRunTask* ImGuiTestRunTask_ImGuiTestRunTask(void);
CIMGUI_API void ImGuiTestRunTask_destroy(ImGuiTestRunTask* self);
CIMGUI_API ImGuiTestRef* ImGuiTestRef_ImGuiTestRef(void);
CIMGUI_API ImGuiTestRef* ImGuiTestRef_ImGuiTestRef1(ImGuiID id);
CIMGUI_API ImGuiTestRef* ImGuiTestRef_ImGuiTestRef2(const char* path);
CIMGUI_API void ImGuiTestRef_destroy(ImGuiTestRef* self);
CIMGUI_API bool ImGuiTestRef_IsEmpty(const ImGuiTestRef* self);
CIMGUI_API ImGuiTestRefDesc* ImGuiTestRefDesc_ImGuiTestRefDesc1(const ImGuiTestRef* ptr);
CIMGUI_API ImGuiTestRefDesc* ImGuiTestRefDesc2(const ImGuiTestRef* ref, const ImGuiTestItemInfo* item);
CIMGUI_API void ImGuiTestRefDesc_destroy(ImGuiTestRefDesc* self);
CIMGUI_API const char* ImGuiTestRefDesc_c_str(ImGuiTestRefDesc* self);
CIMGUI_API ImGuiTestActionFilter* ImGuiTestActionFilter_ImGuiTestActionFilter(void);
CIMGUI_API void ImGuiTestActionFilter_destroy(ImGuiTestActionFilter* self);
CIMGUI_API ImGuiTestGenericItemStatus* ImGuiTestGenericItemStatus_ImGuiTestGenericItemStatus(void);
CIMGUI_API void ImGuiTestGenericItemStatus_destroy(ImGuiTestGenericItemStatus* self);
CIMGUI_API void ImGuiTestGenericItemStatus_Clear(ImGuiTestGenericItemStatus* self);
CIMGUI_API void ImGuiTestGenericItemStatus_QuerySet(ImGuiTestGenericItemStatus* self, bool ret_val);
CIMGUI_API void ImGuiTestGenericItemStatus_QueryInc(ImGuiTestGenericItemStatus* self, bool ret_val);
CIMGUI_API void ImGuiTestGenericItemStatus_Draw(ImGuiTestGenericItemStatus* self);
CIMGUI_API ImGuiTestGenericVars* ImGuiTestGenericVars_ImGuiTestGenericVars(void);
CIMGUI_API void ImGuiTestGenericVars_destroy(ImGuiTestGenericVars* self);
CIMGUI_API void ImGuiTestGenericVars_Clear(ImGuiTestGenericVars* self);
CIMGUI_API ImGuiTestContext* ImGuiTestContext_ImGuiTestContext(void);
CIMGUI_API void ImGuiTestContext_destroy(ImGuiTestContext* self);
CIMGUI_API void ImGuiTestContext_Finish(ImGuiTestContext* self, ImGuiTestStatus status);
CIMGUI_API ImGuiTestStatus
ImGuiTestContext_RunChildTest(ImGuiTestContext* self, const char* test_name, ImGuiTestRunFlags flags);
// Skipped ImGuiTestStatus_GetVars because it uses templates.
CIMGUI_API bool ImGuiTestContext_IsError(const ImGuiTestContext* self);
CIMGUI_API bool ImGuiTestContext_IsWarmUpGuiFrame(const ImGuiTestContext* self);
CIMGUI_API bool ImGuiTestContext_IsFirstGuiFrame(const ImGuiTestContext* self);
CIMGUI_API bool ImGuiTestContext_IsFirstTestFrame(const ImGuiTestContext* self);
CIMGUI_API bool ImGuiTestContext_IsGuiFuncOnly(const ImGuiTestContext* self);
CIMGUI_API bool ImGuiTestContext_SuspendTestFunc(ImGuiTestContext* self, const char* file, int line);
CIMGUI_API void ImGuiTestContext_LogEx(
    ImGuiTestContext* self,
    ImGuiTestVerboseLevel level,
    ImGuiTestLogFlags flags,
    const char* fmt,
    ...
);
CIMGUI_API void ImGuiTestContext_LogExV(
    ImGuiTestContext* self,
    ImGuiTestVerboseLevel level,
    ImGuiTestLogFlags flags,
    const char* fmt,
    va_list args
);
CIMGUI_API void ImGuiTestContext_LogToTTY(
    ImGuiTestContext* self,
    ImGuiTestVerboseLevel level,
    const char* message,
    const char* message_end
);
CIMGUI_API void
ImGuiTestContext_LogToDebugger(ImGuiTestContext* self, ImGuiTestVerboseLevel level, const char* message);
CIMGUI_API void ImGuiTestContext_LogDebug(ImGuiTestContext* self, const char* fmt, ...);
CIMGUI_API void ImGuiTestContext_LogInfo(ImGuiTestContext* self, const char* fmt, ...);
CIMGUI_API void ImGuiTestContext_LogWarning(ImGuiTestContext* self, const char* fmt, ...);
CIMGUI_API void ImGuiTestContext_LogError(ImGuiTestContext* self, const char* fmt, ...);
CIMGUI_API void ImGuiTestContext_LogBasicUiState(ImGuiTestContext* self);
CIMGUI_API void ImGuiTestContext_LogItemList(ImGuiTestContext* self, ImGuiTestItemList* list);
CIMGUI_API void ImGuiTestContext_Yield(ImGuiTestContext* self, int count);
CIMGUI_API void ImGuiTestContext_Sleep(ImGuiTestContext* self, float time_in_second);
CIMGUI_API void ImGuiTestContext_SleepShort(ImGuiTestContext* self);
CIMGUI_API void ImGuiTestContext_SleepStandard(ImGuiTestContext* self);
CIMGUI_API void ImGuiTestContext_SleepNoSkip(ImGuiTestContext* self, float time_in_second, float framestep_in_second);
CIMGUI_API void ImGuiTestContext_SetRef1(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API void ImGuiTestContext_SetRef2(ImGuiTestContext* self, ImGuiWindow* window);
CIMGUI_API ImGuiTestRef ImGuiTestContext_GetRef(ImGuiTestContext* self);
CIMGUI_API ImGuiTestItemInfo
ImGuiTestContext_WindowInfo(ImGuiTestContext* self, ImGuiTestRef window_ref, ImGuiTestOpFlags flags);
CIMGUI_API void ImGuiTestContext_WindowClose(ImGuiTestContext* self, ImGuiTestRef window_ref);
CIMGUI_API void ImGuiTestContext_WindowCollapse(ImGuiTestContext* self, ImGuiTestRef window_ref, bool collapsed);
CIMGUI_API void ImGuiTestContext_WindowFocus(ImGuiTestContext* self, ImGuiTestRef window_ref, ImGuiTestOpFlags flags);
CIMGUI_API void
ImGuiTestContext_WindowBringToFront(ImGuiTestContext* self, ImGuiTestRef window_ref, ImGuiTestOpFlags flags);
CIMGUI_API void ImGuiTestContext_WindowMove(
    ImGuiTestContext* self,
    ImGuiTestRef window_ref,
    ImVec2 pos,
    ImVec2 pivot,
    ImGuiTestOpFlags flags
);
CIMGUI_API void ImGuiTestContext_WindowResize(ImGuiTestContext* self, ImGuiTestRef window_ref, ImVec2 sz);
CIMGUI_API bool
ImGuiTestContext_WindowTeleportToMakePosVisible(ImGuiTestContext* self, ImGuiTestRef window_ref, ImVec2 pos_in_window);
CIMGUI_API ImGuiWindow* ImGuiTestContext_GetWindowByRef(ImGuiTestContext* self, ImGuiTestRef window_ref);
CIMGUI_API void ImGuiTestContext_PopupCloseOne(ImGuiTestContext* self);
CIMGUI_API void ImGuiTestContext_PopupCloseAll(ImGuiTestContext* self);
CIMGUI_API ImGuiID ImGuiTestContext_PopupGetWindowID(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API ImGuiID ImGuiTestContext_GetID(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API ImGuiID ImGuiTestContext_GetID2(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestRef seed_ref);
CIMGUI_API ImVec2 ImGuiTestContext_GetPosOnVoid(ImGuiTestContext* self, ImGuiViewport* viewport);
CIMGUI_API ImVec2 ImGuiTestContext_GetWindowTitlebarPoint(ImGuiTestContext* self, ImGuiTestRef window_ref);
CIMGUI_API ImVec2 ImGuiTestContext_GetMainMonitorWorkPos(ImGuiTestContext* self);
CIMGUI_API ImVec2 ImGuiTestContext_GetMainMonitorWorkSize(ImGuiTestContext* self);
CIMGUI_API void ImGuiTestContext_CaptureReset(ImGuiTestContext* self);
CIMGUI_API void ImGuiTestContext_CaptureSetExtension(ImGuiTestContext* self, const char* ext);
CIMGUI_API bool ImGuiTestContext_CaptureAddWindow(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API void ImGuiTestContext_CaptureScreenshotWindow(ImGuiTestContext* self, ImGuiTestRef ref, int capture_flags);
CIMGUI_API bool ImGuiTestContext_CaptureScreenshot(ImGuiTestContext* self, int capture_flags);
CIMGUI_API bool ImGuiTestContext_CaptureBeginVideo(ImGuiTestContext* self);
CIMGUI_API bool ImGuiTestContext_CaptureEndVideo(ImGuiTestContext* self);
CIMGUI_API void ImGuiTestContext_MouseMove(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags);
CIMGUI_API void ImGuiTestContext_MouseMoveToPos(ImGuiTestContext* self, ImVec2 pos);
CIMGUI_API void ImGuiTestContext_MouseTeleportToPos(ImGuiTestContext* self, ImVec2 pos, ImGuiTestOpFlags flags);
CIMGUI_API void ImGuiTestContext_MouseClick(ImGuiTestContext* self, ImGuiMouseButton button);
CIMGUI_API void ImGuiTestContext_MouseClickMulti(ImGuiTestContext* self, ImGuiMouseButton button, int count);
CIMGUI_API void ImGuiTestContext_MouseDoubleClick(ImGuiTestContext* self, ImGuiMouseButton button);
CIMGUI_API void ImGuiTestContext_MouseDown(ImGuiTestContext* self, ImGuiMouseButton button);
CIMGUI_API void ImGuiTestContext_MouseUp(ImGuiTestContext* self, ImGuiMouseButton button);
CIMGUI_API void ImGuiTestContext_MouseLiftDragThreshold(ImGuiTestContext* self, ImGuiMouseButton button);
CIMGUI_API void ImGuiTestContext_MouseDragWithDelta(ImGuiTestContext* self, ImVec2 delta, ImGuiMouseButton button);
CIMGUI_API void ImGuiTestContext_MouseWheel(ImGuiTestContext* self, ImVec2 delta);
CIMGUI_API void ImGuiTestContext_MouseWheelX(ImGuiTestContext* self, float dx);
CIMGUI_API void ImGuiTestContext_MouseWheelY(ImGuiTestContext* self, float dy);
CIMGUI_API void ImGuiTestContext_MouseMoveToVoid(ImGuiTestContext* self, ImGuiViewport* viewport);
CIMGUI_API void
ImGuiTestContext_MouseClickOnVoid(ImGuiTestContext* self, ImGuiMouseButton button, ImGuiViewport* viewport);
CIMGUI_API ImGuiWindow* ImGuiTestContext_FindHoveredWindowAtPos(ImGuiTestContext* self, const ImVec2* pos);
CIMGUI_API bool
ImGuiTestContext_FindExistingVoidPosOnViewport(ImGuiTestContext* self, ImGuiViewport* viewport, ImVec2* out);
CIMGUI_API void ImGuiTestContext_MouseSetViewport(ImGuiTestContext* self, ImGuiWindow* window);
CIMGUI_API void ImGuiTestContext_MouseSetViewportID(ImGuiTestContext* self, ImGuiID viewport_id);
CIMGUI_API void ImGuiTestContext_KeyDown(ImGuiTestContext* self, ImGuiKeyChord key_chord);
CIMGUI_API void ImGuiTestContext_KeyUp(ImGuiTestContext* self, ImGuiKeyChord key_chord);
CIMGUI_API void ImGuiTestContext_KeyPress(ImGuiTestContext* self, ImGuiKeyChord key_chord, int count);
CIMGUI_API void ImGuiTestContext_KeyHold(ImGuiTestContext* self, ImGuiKeyChord key_chord, float time);
CIMGUI_API void ImGuiTestContext_KeySetEx(ImGuiTestContext* self, ImGuiKeyChord key_chord, bool is_down, float time);
CIMGUI_API void ImGuiTestContext_KeyChars(ImGuiTestContext* self, const char* chars);
CIMGUI_API void ImGuiTestContext_KeyCharsAppend(ImGuiTestContext* self, const char* chars);
CIMGUI_API void ImGuiTestContext_KeyCharsAppendEnter(ImGuiTestContext* self, const char* chars);
CIMGUI_API void ImGuiTestContext_KeyCharsReplace(ImGuiTestContext* self, const char* chars);
CIMGUI_API void ImGuiTestContext_KeyCharsReplaceEnter(ImGuiTestContext* self, const char* chars);
CIMGUI_API void ImGuiTestContext_SetInputMode(ImGuiTestContext* self, ImGuiInputSource input_mode);
CIMGUI_API void ImGuiTestContext_NavMoveTo(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API void ImGuiTestContext_NavActivate(ImGuiTestContext* self);
CIMGUI_API void ImGuiTestContext_NavInput(ImGuiTestContext* self);
CIMGUI_API void ImGuiTestContext_ScrollTo(
    ImGuiTestContext* self,
    ImGuiTestRef ref,
    ImGuiAxis axis,
    float scroll_v,
    ImGuiTestOpFlags flags
);
CIMGUI_API void ImGuiTestContext_ScrollToX(ImGuiTestContext* self, ImGuiTestRef ref, float scroll_x);
CIMGUI_API void ImGuiTestContext_ScrollToY(ImGuiTestContext* self, ImGuiTestRef ref, float scroll_y);
CIMGUI_API void ImGuiTestContext_ScrollToTop(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API void ImGuiTestContext_ScrollToBottom(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API void
ImGuiTestContext_ScrollToItem(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiAxis axis, ImGuiTestOpFlags flags);
CIMGUI_API void ImGuiTestContext_ScrollToItemX(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API void ImGuiTestContext_ScrollToItemY(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API void ImGuiTestContext_ScrollToTabItem(ImGuiTestContext* self, ImGuiTabBar* tab_bar, ImGuiID tab_id);
CIMGUI_API bool ImGuiTestContext_ScrollErrorCheck(
    ImGuiTestContext* self,
    ImGuiAxis axis,
    float expected,
    float actual,
    int* remaining_attempts
);
CIMGUI_API void ImGuiTestContext_ScrollVerifyScrollMax(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API ImGuiTestItemInfo
ImGuiTestContext_ItemInfo(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags);
CIMGUI_API ImGuiTestItemInfo
ImGuiTestContext_ItemInfoOpenFullPath(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags);
CIMGUI_API ImGuiID ImGuiTestContext_ItemInfoHandleWildcardSearch(
    ImGuiTestContext* self,
    const char* wildcard_prefix_start,
    const char* wildcard_prefix_end,
    const char* wildcard_suffix_start
);
CIMGUI_API ImGuiTestItemInfo ImGuiTestContext_ItemInfoNull(ImGuiTestContext* self);
CIMGUI_API void
ImGuiTestContext_GatherItems(ImGuiTestContext* self, ImGuiTestItemList* out_list, ImGuiTestRef parent, int depth);
CIMGUI_API void ImGuiTestContext_ItemAction(
    ImGuiTestContext* self,
    ImGuiTestAction action,
    ImGuiTestRef ref,
    ImGuiTestOpFlags flags,
    void* action_arg
);
CIMGUI_API void
ImGuiTestContext_ItemClick(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiMouseButton button, ImGuiTestOpFlags flags);
CIMGUI_API void ImGuiTestContext_ItemDoubleClick(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags);
CIMGUI_API void ImGuiTestContext_ItemCheck(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags);
CIMGUI_API void ImGuiTestContext_ItemUncheck(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags);
CIMGUI_API void ImGuiTestContext_ItemOpen(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags);
CIMGUI_API void ImGuiTestContext_ItemClose(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags);
CIMGUI_API void ImGuiTestContext_ItemInput(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags);
CIMGUI_API void ImGuiTestContext_ItemNavActivate(ImGuiTestContext* self, ImGuiTestRef ref, ImGuiTestOpFlags flags);
CIMGUI_API bool ImGuiTestContext_ItemOpenFullPath(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API void ImGuiTestContext_ItemActionAll(
    ImGuiTestContext* self,
    ImGuiTestAction action,
    ImGuiTestRef ref_parent,
    const ImGuiTestActionFilter* filter
);
CIMGUI_API void ImGuiTestContext_ItemOpenAll(ImGuiTestContext* self, ImGuiTestRef ref_parent, int depth, int passes);
CIMGUI_API void ImGuiTestContext_ItemCloseAll(ImGuiTestContext* self, ImGuiTestRef ref_parent, int depth, int passes);
CIMGUI_API void ImGuiTestContext_ItemInputValueInt(ImGuiTestContext* self, ImGuiTestRef ref, int v);
CIMGUI_API void ImGuiTestContext_ItemInputValueFloat(ImGuiTestContext* self, ImGuiTestRef ref, float f);
CIMGUI_API void ImGuiTestContext_ItemInputValueStr(ImGuiTestContext* self, ImGuiTestRef ref, const char* str);
CIMGUI_API int ImGuiTestContext_ItemReadAsInt(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API float ImGuiTestContext_ItemReadAsFloat(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API bool ImGuiTestContext_ItemReadAsScalar(
    ImGuiTestContext* self,
    ImGuiTestRef ref,
    ImGuiDataType data_type,
    void* out_data,
    ImGuiTestOpFlags flags
);
CIMGUI_API const char* ImGuiTestContext_ItemReadAsString(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API size_t
ImGuiTestContext_ItemReadAsStringBuff(ImGuiTestContext* self, ImGuiTestRef ref, char* out_buf, size_t out_buf_size);
CIMGUI_API bool ImGuiTestContext_ItemExists(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API bool ImGuiTestContext_ItemIsChecked(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API bool ImGuiTestContext_ItemIsOpened(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API void ImGuiTestContext_ItemVerifyCheckedIfAlive(ImGuiTestContext* self, ImGuiTestRef ref, bool checked);
CIMGUI_API void ImGuiTestContext_ItemHold(ImGuiTestContext* self, ImGuiTestRef ref, float time);
CIMGUI_API void ImGuiTestContext_ItemHoldForFrames(ImGuiTestContext* self, ImGuiTestRef ref, int frames);
CIMGUI_API void
ImGuiTestContext_ItemDragOverAndHold(ImGuiTestContext* self, ImGuiTestRef ref_src, ImGuiTestRef ref_dst);
CIMGUI_API void ImGuiTestContext_ItemDragAndDrop(
    ImGuiTestContext* self,
    ImGuiTestRef ref_src,
    ImGuiTestRef ref_dst,
    ImGuiMouseButton button
);
CIMGUI_API void ImGuiTestContext_ItemDragWithDelta(ImGuiTestContext* self, ImGuiTestRef ref_src, ImVec2 pos_delta);
CIMGUI_API void ImGuiTestContext_TabClose(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API bool
ImGuiTestContext_TabBarCompareOrder(ImGuiTestContext* self, ImGuiTabBar* tab_bar, const char** tab_order);
CIMGUI_API void ImGuiTestContext_MenuAction(ImGuiTestContext* self, ImGuiTestAction action, ImGuiTestRef ref);
CIMGUI_API void ImGuiTestContext_MenuActionAll(ImGuiTestContext* self, ImGuiTestAction action, ImGuiTestRef ref_parent);
CIMGUI_API void ImGuiTestContext_MenuClick(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API void ImGuiTestContext_MenuCheck(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API void ImGuiTestContext_MenuUncheck(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API void ImGuiTestContext_MenuCheckAll(ImGuiTestContext* self, ImGuiTestRef ref_parent);
CIMGUI_API void ImGuiTestContext_MenuUncheckAll(ImGuiTestContext* self, ImGuiTestRef ref_parent);
CIMGUI_API void ImGuiTestContext_ComboClick(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API void ImGuiTestContext_ComboClickAll(ImGuiTestContext* self, ImGuiTestRef ref);
CIMGUI_API void ImGuiTestContext_TableOpenContextMenu(ImGuiTestContext* self, ImGuiTestRef ref, int column_n);
CIMGUI_API ImGuiSortDirection
ImGuiTestContext_TableClickHeader(ImGuiTestContext* self, ImGuiTestRef ref, const char* label, ImGuiKeyChord key_mods);
CIMGUI_API void
ImGuiTestContext_TableSetColumnEnabled(ImGuiTestContext* self, ImGuiTestRef ref, const char* label, bool enabled);
CIMGUI_API void ImGuiTestContext_TableResizeColumn(ImGuiTestContext* self, ImGuiTestRef ref, int column_n, float width);
CIMGUI_API const ImGuiTableSortSpecs* ImGuiTestContext_TableGetSortSpecs(ImGuiTestContext* self, ImGuiTestRef ref);
#ifdef IMGUI_HAS_VIEWPORT
CIMGUI_API void
ImGuiTestContext_ViewportPlatform_SetWindowPos(ImGuiTestContext* self, ImGuiViewport* viewport, const ImVec2* pos);
CIMGUI_API void
ImGuiTestContext_ViewportPlatform_SetWindowSize(ImGuiTestContext* self, ImGuiViewport* viewport, const ImVec2* size);
CIMGUI_API void ImGuiTestContext_ViewportPlatform_SetWindowFocus(ImGuiTestContext* self, ImGuiViewport* viewport);
CIMGUI_API void ImGuiTestContext_ViewportPlatform_CloseWindow(ImGuiTestContext* self, ImGuiViewport* viewport);
#endif  // IMGUI_HAS_VIEWPORT
#ifdef IMGUI_HAS_DOCK
CIMGUI_API void ImGuiTestContext_DockClear(ImGuiTestContext* self, const char* window_name, ...);
CIMGUI_API void ImGuiTestContext_DockInto(
    ImGuiTestContext* self,
    ImGuiTestRef src_id,
    ImGuiTestRef dst_id,
    ImGuiDir split_dir,
    bool is_outer_docking,
    ImGuiTestOpFlags flags
);
CIMGUI_API void ImGuiTestContext_UndockNode(ImGuiTestContext* self, ImGuiID dock_id);
CIMGUI_API void ImGuiTestContext_UndockWindow(ImGuiTestContext* self, const char* window_name);
CIMGUI_API bool ImGuiTestContext_WindowIsUndockedOrStandalone(ImGuiTestContext* self, ImGuiWindow* window);
CIMGUI_API bool ImGuiTestContext_DockIdIsUndockedOrStandalone(ImGuiTestContext* self, ImGuiID dock_id);
CIMGUI_API void ImGuiTestContext_DockNodeHideTabBar(ImGuiTestContext* self, ImGuiDockNode* node, bool hidden);
#endif  // IMGUI_HAS_DOCK
CIMGUI_API void ImGuiTestContext_PerfCalcRef(ImGuiTestContext* self);
CIMGUI_API void
ImGuiTestContext_PerfCapture(ImGuiTestContext* self, const char* category, const char* test_name, const char* csv_file);
