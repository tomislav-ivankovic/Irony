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
typedef typedef int ImGuiTestRunFlags;
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
typedef typedef int ImGuiTestVerboseLevel;
typedef enum {
    ImGuiTestVerboseLevel_Silent = 0,
    ImGuiTestVerboseLevel_Error = 1,
    ImGuiTestVerboseLevel_Warning = 2,
    ImGuiTestVerboseLevel_Info = 3,
    ImGuiTestVerboseLevel_Debug = 4,
    ImGuiTestVerboseLevel_Trace = 5,
    ImGuiTestVerboseLevel_COUNT
} ImGuiTestVerboseLevel_;
typedef int ImGuiTestEngineExportFormat;

typedef struct ImGuiTestContext ImGuiTestContext;
typedef struct ImGuiTestCoroutineInterface ImGuiTestCoroutineInterface;
typedef struct ImGuiTestEngine ImGuiTestEngine;
typedef struct ImGuiTestInputs ImGuiTestInputs;

typedef struct ImGuiTestEngineIO ImGuiTestEngineIO;
typedef struct ImGuiTestItemInfo ImGuiTestItemInfo;
typedef struct ImGuiTestItemList ImGuiTestItemList;
typedef struct ImGuiTestLogLineInfo ImGuiTestLogLineInfo;
typedef struct ImGuiTestLog ImGuiTestLog;
typedef struct ImGuiTestOutput ImGuiTestOutput;
typedef struct ImGuiTest ImGuiTest;
typedef struct ImGuiTestRunTask ImGuiTestRunTask;

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
