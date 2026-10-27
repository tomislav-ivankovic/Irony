//! `std.Io` implementation for Windows built only on the documented Win32 API,
//! so that it keeps working under Wine. Behavior follows `std.Io.Threaded`.
const WinIo = @This();

const builtin = @import("builtin");
const is_debug = builtin.mode == .debug;

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const assert = std.debug.assert;
const w32 = @import("win32").everything;

/// Thread-safe. Used for allocating `Io.Future` and `Io.Group` closures, for
/// spawning child processes and for the memory mapping fallback.
allocator: Allocator,
mutex: Io.Mutex = .init,
cond: Io.Condition = .init,
run_queue: std.SinglyLinkedList = .{},
join_requested: bool = false,
stack_size: usize,
/// All threads are spawned detached; this is how we wait until they all exit.
wait_group: WaitGroup = .init,
async_limit: Io.Limit,
concurrent_limit: Io.Limit = .unlimited,
/// Number of threads that are unavailable to take tasks. To calculate
/// available count, subtract this from either `async_limit` or
/// `concurrent_limit`.
busy_count: usize = 0,
worker_threads: std.atomic.Value(?*Thread),

csprng: Csprng = .uninitialized,

disable_memory_mapping: bool,

/// From `InitOptions.environ`. On Windows this only says whether the process
/// environment may be used.
process_environ: std.process.Environ,

stderr_writer: File.Writer = .{
    .io = undefined,
    .interface = File.Writer.initInterface(&.{}),
    .file = undefined,
    .mode = .streaming,
},
stderr_mode: Io.Terminal.Mode = .no_color,
stderr_writer_initialized: bool = false,
stderr_mutex: Io.Mutex = .init,
/// Thread ID of the thread holding `stderr_mutex`, or 0.
stderr_mutex_locker: u32 = 0,
stderr_mutex_lock_count: usize = 0,

/// Serializes spawning child processes, since handle inheritance is process-wide.
process_spawn_mutex: Io.Mutex = .init,
/// The NUL device, opened when first needed. Protected by `mutex`.
null_handle: ?w32.HANDLE = null,

/// Whether `WSAStartup` was called. Protected by `mutex`.
wsa_started: std.atomic.Value(bool) = .init(false),
dl: Dl = .{},

pub const InitOptions = Io.Threaded.InitOptions;
const Csprng = Io.Threaded.Csprng;

pub fn init(
    /// Must be threadsafe. Only used for `async`, `concurrent`, `groupAsync`,
    /// `groupConcurrent`, spawning child processes and the memory mapping
    /// fallback.
    gpa: Allocator,
    options: InitOptions,
) WinIo {
    if (builtin.single_threaded) return .{
        .allocator = gpa,
        .stack_size = options.stack_size,
        .async_limit = options.async_limit orelse .nothing,
        .concurrent_limit = options.concurrent_limit,
        .worker_threads = .init(null),
        .disable_memory_mapping = options.disable_memory_mapping,
        .process_environ = options.environ,
    };

    const cpu_count = w32.GetActiveProcessorCount(w32.ALL_PROCESSOR_GROUPS);

    return .{
        .allocator = gpa,
        .stack_size = options.stack_size,
        .async_limit = options.async_limit orelse if (cpu_count != 0) .limited(cpu_count - 1) else .nothing,
        .concurrent_limit = options.concurrent_limit,
        .worker_threads = .init(null),
        .disable_memory_mapping = options.disable_memory_mapping,
        .process_environ = options.environ,
    };
}

/// A `WinIo` that never spawns threads: `async` and `groupAsync` run the task
/// inline, and `concurrent` and `groupConcurrent` fail with
/// `error.ConcurrencyUnavailable`. It needs no allocator and no call to
/// `init`, so it can be used before an allocator exists, such as in
/// `DllMain`. Spawning child processes and the memory mapping fallback need
/// an allocator, and fail with `error.OutOfMemory`. Uses the process
/// environment. `deinit` may be skipped.
pub const init_single_threaded: WinIo = .{
    .allocator = .failing,
    .stack_size = std.Thread.SpawnConfig.default_stack_size,
    .async_limit = .nothing,
    .concurrent_limit = .nothing,
    .worker_threads = .init(null),
    .disable_memory_mapping = false,
    .process_environ = .{ .block = .global },
};

var global_single_threaded_instance: WinIo = .init_single_threaded;

/// A process-wide `init_single_threaded` instance. Like
/// `std.Io.Threaded.global_single_threaded`, it is never deinitialized.
pub const global_single_threaded: *WinIo = &global_single_threaded_instance;

pub fn setAsyncLimit(w: *WinIo, new_limit: Io.Limit) void {
    mutexLockUncancelable(&w.mutex);
    defer mutexUnlock(&w.mutex);
    w.async_limit = new_limit;
}

pub fn deinit(w: *WinIo) void {
    w.join();
    if (w.wsa_started.load(.monotonic)) _ = w32.WSACleanup();
    w.dl.deinit();
    if (w.null_handle) |handle| _ = w32.CloseHandle(handle);
    w.* = undefined;
}

fn join(w: *WinIo) void {
    if (builtin.single_threaded) return;
    {
        mutexLockUncancelable(&w.mutex);
        defer mutexUnlock(&w.mutex);
        w.join_requested = true;
    }
    condBroadcast(&w.cond);
    w.wait_group.wait();
}

/// Must stay comptime-callable: `std.testing.io` is a `const` computed from it.
pub fn io(w: *WinIo) Io {
    return .{ .userdata = w, .vtable = &vtable };
}

fn fromUserdata(userdata: ?*anyopaque) *WinIo {
    return @ptrCast(@alignCast(userdata));
}

const vtable: Io.VTable = .{
    .crashHandler = crashHandler,

    .async = async,
    .concurrent = concurrent,
    .await = await,
    .cancel = cancel,

    .groupAsync = groupAsync,
    .groupConcurrent = groupConcurrent,
    .groupAwait = groupAwait,
    .groupCancel = groupCancel,

    .recancel = recancel,
    .swapCancelProtection = swapCancelProtection,
    .checkCancel = checkCancel,

    .futexWait = futexWait,
    .futexWaitUncancelable = futexWaitUncancelable,
    .futexWake = futexWake,

    .now = now,
    .clockResolution = clockResolution,
    .sleep = sleep,

    .random = random,
    .randomSecure = randomSecure,

    .operate = operate,
    .batchAwaitAsync = batchAwaitAsync,
    .batchAwaitConcurrent = batchAwaitConcurrent,
    .batchCancel = batchCancel,

    .fileClose = fileClose,
    .fileReadPositional = fileReadPositional,
    .fileWritePositional = fileWritePositional,
    .fileWriteFileStreaming = fileWriteFileStreaming,
    .fileWriteFilePositional = fileWriteFilePositional,
    .fileSeekBy = fileSeekBy,
    .fileSeekTo = fileSeekTo,

    .dirCreateDir = dirCreateDir,
    .dirCreateDirPath = dirCreateDirPath,
    .dirCreateDirPathOpen = dirCreateDirPathOpen,
    .dirOpenDir = dirOpenDir,
    .dirStat = dirStat,
    .dirStatFile = dirStatFile,
    .dirAccess = dirAccess,
    .dirCreateFile = dirCreateFile,
    .dirCreateFileAtomic = dirCreateFileAtomic,
    .dirOpenFile = dirOpenFile,
    .dirClose = dirClose,
    .dirRead = dirRead,
    .dirRealPath = dirRealPath,
    .dirRealPathFile = dirRealPathFile,
    .dirDeleteFile = dirDeleteFile,
    .dirDeleteDir = dirDeleteDir,
    .dirRename = dirRename,
    .dirRenamePreserve = dirRenamePreserve,
    .dirSymLink = dirSymLink,
    .dirReadLink = dirReadLink,
    .dirSetOwner = dirSetOwner,
    .dirSetFileOwner = dirSetFileOwner,
    .dirSetPermissions = dirSetPermissions,
    .dirSetFilePermissions = dirSetFilePermissions,
    .dirSetTimestamps = dirSetTimestamps,
    .dirHardLink = dirHardLink,

    .fileStat = fileStat,
    .fileLength = fileLength,
    .fileSync = fileSync,
    .fileIsTty = fileIsTty,
    .fileEnableAnsiEscapeCodes = fileEnableAnsiEscapeCodes,
    .fileSupportsAnsiEscapeCodes = fileSupportsAnsiEscapeCodes,
    .fileSetLength = fileSetLength,
    .fileSetOwner = fileSetOwner,
    .fileSetPermissions = fileSetPermissions,
    .fileSetTimestamps = fileSetTimestamps,
    .fileLock = fileLock,
    .fileTryLock = fileTryLock,
    .fileUnlock = fileUnlock,
    .fileDowngradeLock = fileDowngradeLock,
    .fileRealPath = fileRealPath,
    .fileHardLink = fileHardLink,

    .fileMemoryMapCreate = fileMemoryMapCreate,
    .fileMemoryMapDestroy = fileMemoryMapDestroy,
    .fileMemoryMapSetLength = fileMemoryMapSetLength,
    .fileMemoryMapRead = fileMemoryMapRead,
    .fileMemoryMapWrite = fileMemoryMapWrite,

    .netListenIp = netListenIp,
    .netAccept = netAccept,
    .netBindIp = netBindIp,
    .netConnectIp = netConnectIp,
    .netListenUnix = netListenUnix,
    .netConnectUnix = netConnectUnix,
    .netSocketCreatePair = netSocketCreatePair,
    .netWriteFile = netWriteFile,
    .netClose = netClose,
    .netShutdown = netShutdown,
    .netInterfaceNameResolve = netInterfaceNameResolve,
    .netInterfaceName = netInterfaceName,
    .netLookup = netLookup,

    .processExecutableOpen = processExecutableOpen,
    .processExecutablePath = processExecutablePath,
    .lockStderr = lockStderr,
    .tryLockStderr = tryLockStderr,
    .unlockStderr = unlockStderr,
    .processCurrentPath = processCurrentPath,
    .processSetCurrentDir = processSetCurrentDir,
    .processSetCurrentPath = processSetCurrentPath,
    .processReplace = processReplace,
    .processSpawn = processSpawn,
    .childWait = childWait,
    .childKill = childKill,

    .progressParentFile = progressParentFile,
    .inheritParentDir = inheritParentDir,
    .inheritParentFile = inheritParentFile,
};

// ---------------------------------------------------------------------------
// Win32 functions missing from (or misdeclared in) zigwin32.

/// zigwin32 declares these in "vertdll" (VBS enclaves). Desktop applications
/// get them from the API set documented for `Synchronization.lib`.
const synch = struct {
    extern "api-ms-win-core-synch-l1-2-0" fn WaitOnAddress(
        Address: *const volatile anyopaque,
        CompareAddress: *const anyopaque,
        AddressSize: usize,
        dwMilliseconds: u32,
    ) callconv(.winapi) w32.BOOL;
    extern "api-ms-win-core-synch-l1-2-0" fn WakeByAddressSingle(Address: *const anyopaque) callconv(.winapi) void;
    extern "api-ms-win-core-synch-l1-2-0" fn WakeByAddressAll(Address: *const anyopaque) callconv(.winapi) void;
};

/// zigwin32's `GetLastError` returns an exhaustive enum, which would make an
/// error code missing from the enum illegal.
const kernel32 = struct {
    extern "kernel32" fn GetLastError() callconv(.winapi) u32;
};

fn getLastError() w32.WIN32_ERROR {
    return win32Error(kernel32.GetLastError());
}

/// Converts a raw Win32 error code, mapping codes unknown to zigwin32 to
/// `ERROR_UNIDENTIFIED_ERROR`.
fn win32Error(code: u32) w32.WIN32_ERROR {
    return std.enums.fromInt(w32.WIN32_ERROR, code) orelse .ERROR_UNIDENTIFIED_ERROR;
}

const INFINITE: u32 = std.math.maxInt(u32);
const WAIT_IO_COMPLETION: u32 = 0xC0;
const WAIT_TIMEOUT: u32 = 0x102;
const FILE_TYPE_DISK: u32 = 1;

/// Call when a Win32 function failed with an error code that is not handled.
fn unexpectedError(err: w32.WIN32_ERROR) Io.UnexpectedError {
    @branchHint(.cold);
    if (std.options.unexpected_error_tracing) {
        std.debug.print("error.Unexpected: GetLastError({d}): {s}\n", .{
            @backingInt(err),
            std.enums.tagName(w32.WIN32_ERROR, err) orelse "<unnamed>",
        });
        std.debug.dumpCurrentStackTrace(.{ .first_address = @returnAddress() });
    }
    return error.Unexpected;
}

/// Call when a Win32 function failed with an error code that indicates a
/// programmer mistake.
fn errorBug(err: w32.WIN32_ERROR) Io.UnexpectedError {
    @branchHint(.cold);
    switch (builtin.mode) {
        .debug => std.debug.panic("programmer bug caused syscall error: {d} ({s})", .{
            @backingInt(err),
            std.enums.tagName(w32.WIN32_ERROR, err) orelse "<unnamed>",
        }),
        else => return error.Unexpected,
    }
}

fn recoverableOsBugDetected() void {
    if (is_debug) unreachable;
}

// ---------------------------------------------------------------------------
// Threads, futures, groups and cancelation. Ported from `std.Io.Threaded`.

const Runnable = struct {
    node: std.SinglyLinkedList.Node,
    startFn: *const fn (*Runnable, *Thread, *WinIo) void,
};

const Group = struct {
    ptr: *Io.Group,

    /// Returns a correctly-typed pointer to the `Io.Group.token` field.
    ///
    /// The status indicates how many pending tasks are in the group, whether the group has been
    /// canceled, and whether the group has been awaited.
    ///
    /// Note that the zero value of `Status` intentionally represents the initial group state (empty
    /// with no awaiters). This is a requirement of `Io.Group`.
    fn status(g: Group) *std.atomic.Value(Status) {
        return @ptrCast(&g.ptr.token);
    }
    /// Returns a correctly-typed pointer to the `Io.Group.state` field.
    ///
    /// On completion of the whole group, if `status` indicates that there is an awaiter, the last
    /// task must increment this `u32` and do a futex wake on it to signal that awaiter.
    fn awaiter(g: Group) **std.atomic.Value(u32) {
        return @ptrCast(&g.ptr.state);
    }

    const Status = packed struct(usize) {
        num_running: @Int(.unsigned, @bitSizeOf(usize) - 2),
        have_awaiter: bool,
        canceled: bool,
    };

    const Task = struct {
        runnable: Runnable,
        group: *Io.Group,
        func: *const fn (context: *const anyopaque) void,
        context_alignment: Alignment,
        alloc_len: usize,

        /// `Task.runnable.node` is `undefined` in the created `Task`.
        fn create(
            gpa: Allocator,
            group: Group,
            context: []const u8,
            context_alignment: Alignment,
            func: *const fn (context: *const anyopaque) void,
        ) Allocator.Error!*Task {
            const max_context_misalignment = context_alignment.toByteUnits() -| @alignOf(Task);
            const worst_case_context_offset = context_alignment.forward(@sizeOf(Task) + max_context_misalignment);
            const alloc_len = worst_case_context_offset + context.len;

            const task: *Task = @ptrCast(@alignCast(try gpa.alignedAlloc(u8, .of(Task), alloc_len)));
            errdefer comptime unreachable;

            task.* = .{
                .runnable = .{
                    .node = undefined,
                    .startFn = &start,
                },
                .group = group.ptr,
                .func = func,
                .context_alignment = context_alignment,
                .alloc_len = alloc_len,
            };
            @memcpy(task.contextPointer()[0..context.len], context);
            return task;
        }

        fn destroy(task: *Task, gpa: Allocator) void {
            const base: [*]align(@alignOf(Task)) u8 = @ptrCast(task);
            gpa.free(base[0..task.alloc_len]);
        }

        fn contextPointer(task: *Task) [*]u8 {
            const base: [*]u8 = @ptrCast(task);
            const offset = task.context_alignment.forward(@intFromPtr(base) + @sizeOf(Task)) - @intFromPtr(base);
            return base + offset;
        }

        fn start(r: *Runnable, thread: *Thread, w: *WinIo) void {
            const task: *Task = @fieldParentPtr("runnable", r);
            const group: Group = .{ .ptr = task.group };

            // This would be a simple store, but it's upgraded to an RMW so we can use `.acquire` to
            // enforce the ordering between this and the `group.status().load` below. Paired with
            // the `.release` rmw on `Thread.status` in `cancelThreads`, this creates a StoreLoad
            // barrier which guarantees that when a group is canceled, either we see the cancelation
            // in the group status, or the canceler sees our thread status so can directly notify us
            // of the cancelation.
            _ = thread.status.swap(.{
                .cancelation = .none,
                .awaitable = .fromGroup(group.ptr),
            }, .acquire);
            if (group.status().load(.monotonic).canceled) {
                thread.status.store(.{
                    .cancelation = .canceling,
                    .awaitable = .fromGroup(group.ptr),
                }, .monotonic);
            }

            task.func(task.contextPointer());

            thread.status.store(.{ .cancelation = .none, .awaitable = .null }, .monotonic);
            const old_status = group.status().fetchSub(.{
                .num_running = 1,
                .have_awaiter = false,
                .canceled = false,
            }, .acq_rel); // acquire `group.awaiter()`, release task results
            assert(old_status.num_running > 0);
            if (old_status.have_awaiter and old_status.num_running == 1) {
                const to_signal = group.awaiter().*;
                // `awaiter` should only be modified by us. For another thread to see `num_running`
                // drop to 0 after this point would indicate that another task started up, meaning
                // `async`/`cancel` was racing with awaited group completion.
                group.awaiter().* = undefined;
                _ = to_signal.fetchAdd(1, .release); // release results
                Thread.futexWake(&to_signal.raw, 1);
            }

            // Task completed. Self-destruct sequence initiated.
            task.destroy(w.allocator);
        }
    };

    /// Assumes the caller has already atomically updated the group status to indicate cancelation,
    /// and notifies any already-running threads of this cancelation.
    fn cancelThreads(g: Group, w: *WinIo) bool {
        var any_blocked = false;
        var it = w.worker_threads.load(.acquire); // acquire `Thread` values
        while (it) |thread| : (it = thread.next) {
            // This non-mutating RMW exists for ordering reasons: see comment in `Group.Task.start` for reasons.
            _ = thread.status.fetchOr(.{ .cancelation = @fromBackingInt(@intCast(0)), .awaitable = .null }, .release);
            if (thread.cancelAwaitable(.fromGroup(g.ptr))) any_blocked = true;
        }
        return any_blocked;
    }

    /// Uses `Thread.signalCanceledSyscall` to signal any threads which are still blocked in a
    /// syscall for this group and have not observed a cancelation request yet. Returns `true` if
    /// more signals may be necessary, in which case the caller must call this again after a delay.
    fn signalAllCanceledSyscalls(g: Group, w: *WinIo) bool {
        var any_signaled = false;
        var it = w.worker_threads.load(.acquire); // acquire `Thread` values
        while (it) |thread| : (it = thread.next) {
            if (thread.signalCanceledSyscall(.fromGroup(g.ptr))) any_signaled = true;
        }
        return any_signaled;
    }

    /// The caller has canceled `g`. Inform any threads working on that group of the cancelation if
    /// necessary, and wait for `g` to finish (indicated by `num_completed` being incremented from 0
    /// to 1), while sending regular signals to threads if necessary for them to unblock from any
    /// cancelable syscalls.
    ///
    /// `skip_signals` means it is already known that no threads are currently working on the group
    /// so no notifications or signals are necessary.
    fn waitForCancelWithSignaling(
        g: Group,
        w: *WinIo,
        num_completed: *std.atomic.Value(u32),
        skip_signals: bool,
    ) void {
        var need_signal: bool = !skip_signals and g.cancelThreads(w);
        var timeout_ns: u64 = 1 << 10;
        while (true) {
            need_signal = need_signal and g.signalAllCanceledSyscalls(w);
            Thread.futexWaitUncancelable(&num_completed.raw, 0, if (need_signal) timeout_ns else null);
            switch (num_completed.load(.acquire)) { // acquire task results
                0 => {},
                1 => break,
                else => unreachable,
            }
            timeout_ns <<|= 1;
        }
    }
};

/// Trailing data:
/// 1. context
/// 2. result
const Future = struct {
    runnable: Runnable,
    func: *const fn (context: *const anyopaque, result: *anyopaque) void,
    status: std.atomic.Value(Status),
    /// On completion, increment this `u32` and do a futex wake on it.
    awaiter: *std.atomic.Value(u32),
    context_alignment: Alignment,
    result_offset: usize,
    alloc_len: usize,

    const Status = packed struct(usize) {
        /// The values of this enum are chosen so that await/cancel can just OR with 0b01 and 0b11
        /// respectively. That *does* clobber `.done`, but that's actually fine, because if the tag
        /// is `.done` then only the awaiter is referencing this `Future` anyway.
        tag: enum(u2) {
            /// The future is queued or running (depending on whether `thread` is set).
            pending = 0b00,
            /// Like `pending`, but the future is being awaited. `Future.awaiter` is populated.
            pending_awaited = 0b01,
            /// Like `pending`, but the future is being canceled. `Future.awaiter` is populated.
            pending_canceled = 0b11,
            /// The future has already completed. `thread` is `.null`, unless the future terminated
            /// with an acknowledged cancel request, in which case `thread` is `.all_ones`.
            done = 0b10,
        },
        /// When the future begins execution, this is atomically updated from `null` to the thread running the
        /// `Future`, so that cancelation knows which thread to cancel.
        thread: Thread.PackedPtr,
    };

    /// `Future.runnable.node` is `undefined` in the created `Future`.
    fn create(
        gpa: Allocator,
        result_len: usize,
        result_alignment: Alignment,
        context: []const u8,
        context_alignment: Alignment,
        func: *const fn (context: *const anyopaque, result: *anyopaque) void,
    ) Allocator.Error!*Future {
        const max_context_misalignment = context_alignment.toByteUnits() -| @alignOf(Future);
        const worst_case_context_offset = context_alignment.forward(@sizeOf(Future) + max_context_misalignment);
        const worst_case_result_offset = result_alignment.forward(worst_case_context_offset + context.len);
        const alloc_len = worst_case_result_offset + result_len;

        const future: *Future = @ptrCast(@alignCast(try gpa.alignedAlloc(u8, .of(Future), alloc_len)));
        errdefer comptime unreachable;

        const actual_context_addr = context_alignment.forward(@intFromPtr(future) + @sizeOf(Future));
        const actual_result_addr = result_alignment.forward(actual_context_addr + context.len);
        const actual_result_offset = actual_result_addr - @intFromPtr(future);
        future.* = .{
            .runnable = .{
                .node = undefined,
                .startFn = &start,
            },
            .func = func,
            .status = .init(.{
                .tag = .pending,
                .thread = .null,
            }),
            .awaiter = undefined,
            .context_alignment = context_alignment,
            .result_offset = actual_result_offset,
            .alloc_len = alloc_len,
        };
        @memcpy(future.contextPointer()[0..context.len], context);
        return future;
    }

    fn destroy(future: *Future, gpa: Allocator) void {
        const base: [*]align(@alignOf(Future)) u8 = @ptrCast(future);
        gpa.free(base[0..future.alloc_len]);
    }

    fn resultPointer(future: *Future) [*]u8 {
        const base: [*]u8 = @ptrCast(future);
        return base + future.result_offset;
    }

    fn contextPointer(future: *Future) [*]u8 {
        const base: [*]u8 = @ptrCast(future);
        const context_offset = future.context_alignment.forward(@intFromPtr(future) + @sizeOf(Future)) - @intFromPtr(future);
        return base + context_offset;
    }

    fn start(r: *Runnable, thread: *Thread, w: *WinIo) void {
        _ = w;
        const future: *Future = @fieldParentPtr("runnable", r);

        thread.status.store(.{
            .cancelation = .none,
            .awaitable = .fromFuture(future),
        }, .monotonic);
        {
            const old_status = future.status.fetchOr(.{
                .tag = .pending,
                .thread = .pack(thread),
            }, .release);
            assert(old_status.thread == .null);
            switch (old_status.tag) {
                .pending, .pending_awaited => {},
                .pending_canceled => thread.status.store(.{
                    .cancelation = .canceling,
                    .awaitable = .fromFuture(future),
                }, .monotonic),
                .done => unreachable,
            }
        }

        future.func(future.contextPointer(), future.resultPointer());

        const had_acknowledged_cancel = switch (thread.status.load(.monotonic).cancelation) {
            .none, .canceling => false,
            .canceled => true,
            .blocked => unreachable,
            .blocked_alertable => unreachable,
            .unused => unreachable,
            .blocked_alertable_canceling => unreachable,
            .blocked_canceling => unreachable,
        };
        thread.status.store(.{ .cancelation = .none, .awaitable = .null }, .monotonic);
        const old_status = future.status.swap(.{
            .tag = .done,
            .thread = if (had_acknowledged_cancel) .all_ones else .null,
        }, .acq_rel); // acquire `future.awaiter`, release results
        switch (old_status.tag) {
            .pending => {},
            .pending_awaited, .pending_canceled => {
                const to_signal = future.awaiter;
                _ = to_signal.fetchAdd(1, .release); // release results
                Thread.futexWake(&to_signal.raw, 1);
            },
            .done => unreachable,
        }
    }

    /// The caller has canceled `future`. `thread` is the thread currently running that future.
    /// Inform `thread` of the cancelation if necessary, and wait for `future` to finish (indicated
    /// by `num_completed` being incremented from 0 to 1), while sending regular signals to `thread`
    /// if necessary for it to unblock from a cancelable syscall.
    fn waitForCancelWithSignaling(
        future: *Future,
        num_completed: *std.atomic.Value(u32),
        thread: ?*Thread,
    ) void {
        var need_signal: bool = if (thread) |th| th.cancelAwaitable(.fromFuture(future)) else false;
        var timeout_ns: u64 = 1 << 10;
        while (true) {
            need_signal = need_signal and thread.?.signalCanceledSyscall(.fromFuture(future));
            Thread.futexWaitUncancelable(&num_completed.raw, 0, if (need_signal) timeout_ns else null);
            switch (num_completed.load(.acquire)) { // acquire task results
                0 => {},
                1 => break,
                else => unreachable,
            }
            timeout_ns <<|= 1;
        }
    }
};

/// A sequence of (ptr_bit_width - 3) bits which uniquely identifies a group or future. The bits are
/// the MSBs of the `*Io.Group` or `*Future`. Both have a size of at least 8 bytes, so no two
/// groups/futures in memory at the same time will have the same value for all of these bits.
const AwaitableId = enum(@Int(.unsigned, @bitSizeOf(usize) - 3)) {
    comptime {
        assert(@sizeOf(Future) >= 8);
        assert(@sizeOf(Io.Group) >= 8);
    }
    null = 0,
    all_ones = std.math.maxInt(@Int(.unsigned, @bitSizeOf(usize) - 3)),
    _,
    const Split = packed struct(usize) { low: u3, high: AwaitableId };
    fn fromGroup(g: *Io.Group) AwaitableId {
        const split: Split = @bitCast(@intFromPtr(g));
        return split.high;
    }
    fn fromFuture(f: *Future) AwaitableId {
        const split: Split = @bitCast(@intFromPtr(f));
        return split.high;
    }
};

const Thread = struct {
    next: ?*Thread,

    /// Opened with `THREAD_TERMINATE` (for `CancelSynchronousIo`) and
    /// `THREAD_SET_CONTEXT` (for `QueueUserAPC`).
    handle: w32.HANDLE,

    status: std.atomic.Value(Status),

    cancel_protection: Io.CancelProtection,
    /// While blocked in a cancelable `WaitOnAddress`, the address being waited
    /// on, so that a canceler can wake this thread with `WakeByAddressAll`.
    wait_address: std.atomic.Value(?*const u32),

    csprng: Csprng,

    const Status = packed struct(usize) {
        /// The specific values of these enum fields are chosen to simplify the implementation of
        /// the transformations we need to apply to this state.
        cancelation: enum(u3) {
            /// The thread has not yet been canceled, and is not in a cancelable operation.
            /// To request cancelation, just set the status to `.canceling`.
            none = 0b000,

            /// `std.Io.Threaded` uses this value for parked threads. Never set here, but needed
            /// so that the XOR in `recancelInner` maps `.canceled` to `.canceling`.
            unused = 0b001,

            /// The thread is blocked in a cancelable system call or futex wait.
            /// To request cancelation, set the status to `.blocked_canceling` and repeatedly
            /// interrupt the call (`CancelSynchronousIo` or `WakeByAddressAll`) until the status
            /// changes.
            blocked = 0b011,

            /// The thread is blocked in an alertable wait. To request cancelation, set the status
            /// to `blocked_alertable_canceling` and repeatedly queue an APC to the thread until
            /// the status changes.
            blocked_alertable = 0b010,

            /// The thread has an outstanding cancelation request but is not in a cancelable operation.
            /// When it acknowledges the cancelation, it will set the status to `.canceled`.
            canceling = 0b110,

            /// The thread has received and acknowledged a cancelation request.
            /// If `recancel` is called, the status will revert to `.canceling`, but otherwise, the status
            /// will not change for the remainder of this task's execution.
            canceled = 0b111,

            /// The thread is blocked in a cancelable system call or futex wait, and is being
            /// canceled. The thread which triggered the cancelation will signal this thread until
            /// its status changes.
            blocked_canceling = 0b101,

            /// The thread is blocked in an alertable wait, and is being canceled. The thread which
            /// triggered the cancelation will queue APCs to this thread until its status changes.
            blocked_alertable_canceling = 0b100,
        },

        /// We cannot turn this value back into a pointer. Instead, it exists so that a task can be
        /// canceled by a cmpxchg on thread status: if it is running the task we want to cancel,
        /// then update the `cancelation` field.
        awaitable: AwaitableId,
    };

    threadlocal var current: ?*Thread = null;

    /// The thread is neither in a syscall nor entering one, but we want to check for cancelation
    /// anyway. If there is a pending cancel request, acknowledge it and return `error.Canceled`.
    fn checkCancel() Io.Cancelable!void {
        const thread = Thread.current orelse return;
        switch (thread.cancel_protection) {
            .blocked => return,
            .unblocked => {},
        }
        const status = thread.status.load(.monotonic);
        switch (status.cancelation) {
            .blocked => unreachable,
            .blocked_alertable => unreachable,
            .unused => unreachable,
            .blocked_alertable_canceling => unreachable,
            .blocked_canceling => unreachable,
            .none, .canceled => {},
            .canceling => {
                thread.status.store(.{
                    .cancelation = .canceled,
                    .awaitable = status.awaitable,
                }, .monotonic);
                return error.Canceled;
            },
        }
    }

    fn futexWaitUncancelable(ptr: *const u32, expect: u32, timeout_ns: ?u64) void {
        return Thread.futexWaitInner(ptr, expect, true, timeout_ns) catch unreachable;
    }

    fn futexWait(ptr: *const u32, expect: u32, timeout_ns: ?u64) Io.Cancelable!void {
        return Thread.futexWaitInner(ptr, expect, false, timeout_ns);
    }

    fn futexWaitInner(ptr: *const u32, expect: u32, uncancelable: bool, timeout_ns: ?u64) Io.Cancelable!void {
        @branchHint(.cold);

        if (builtin.single_threaded) unreachable; // nobody would ever wake us

        const syscall: Syscall = if (uncancelable) .{ .thread = null } else try .start();
        if (syscall.thread) |thread| thread.wait_address.store(ptr, .release);
        const expect_copy = expect;
        // Returns FALSE on timeout; wakeups may be spurious, which is fine for a futex.
        _ = synch.WaitOnAddress(ptr, &expect_copy, @sizeOf(u32), nanosecondsToMilliseconds(timeout_ns));
        if (syscall.thread) |thread| thread.wait_address.store(null, .monotonic);
        syscall.finish();
    }

    fn futexWake(ptr: *const u32, max_waiters: u32) void {
        @branchHint(.cold);
        assert(max_waiters != 0);

        if (builtin.single_threaded) return; // nothing to wake up

        if (max_waiters == 1) {
            synch.WakeByAddressSingle(ptr);
        } else {
            synch.WakeByAddressAll(ptr);
        }
    }

    /// Cancels `thread` if it is working on `awaitable`.
    ///
    /// It is possible that `thread` gets canceled by this function, but is blocked in a syscall. In
    /// that case, the thread may need to be signaled to interrupt the call. This function will
    /// return `true` to indicate this, in which case the caller must call `signalCanceledSyscall`.
    fn cancelAwaitable(thread: *Thread, awaitable: AwaitableId) bool {
        var status = thread.status.load(.monotonic);
        while (true) {
            if (status.awaitable != awaitable) return false; // thread is working on something else
            status = switch (status.cancelation) {
                .none => thread.status.cmpxchgWeak(
                    .{ .cancelation = .none, .awaitable = awaitable },
                    .{ .cancelation = .canceling, .awaitable = awaitable },
                    .monotonic,
                    .monotonic,
                ) orelse return false,

                .blocked => thread.status.cmpxchgWeak(
                    .{ .cancelation = .blocked, .awaitable = awaitable },
                    .{ .cancelation = .blocked_canceling, .awaitable = awaitable },
                    .monotonic,
                    .monotonic,
                ) orelse return true,

                .blocked_alertable => thread.status.cmpxchgWeak(
                    .{ .cancelation = .blocked_alertable, .awaitable = awaitable },
                    .{ .cancelation = .blocked_alertable_canceling, .awaitable = awaitable },
                    .monotonic,
                    .monotonic,
                ) orelse return true,

                .canceling, .canceled => {
                    // This can happen when the task start raced with the cancelation, so the thread
                    // saw the cancelation on the future/group *and* we are trying to signal the
                    // thread here.
                    return false;
                },

                .blocked_canceling => unreachable, // `awaitable` has not been canceled before now
                .unused => unreachable,
                .blocked_alertable_canceling => unreachable, // `awaitable` has not been canceled before now
            };
        }
    }

    /// Interrupts `thread` if it is still blocked in a syscall (i.e. has not yet observed the
    /// cancelation request from `cancelAwaitable`).
    ///
    /// The interrupt could arrive before the syscall actually starts, so it may be missed. If this
    /// function returns `true`, then it should be called again after a short delay to interrupt
    /// again if the thread is still blocked.
    fn signalCanceledSyscall(thread: *Thread, awaitable: AwaitableId) bool {
        const status = thread.status.load(.monotonic);
        if (status.awaitable != awaitable) {
            // The thread has moved on and is working on something totally different.
            return false;
        }

        switch (status.cancelation) {
            .blocked_canceling => {
                if (thread.wait_address.load(.acquire)) |address| {
                    // Spurious wakeups of other waiters on this address are harmless.
                    synch.WakeByAddressAll(address);
                    return true;
                }
                if (w32.CancelSynchronousIo(thread.handle) != 0) {
                    return false; // the OS confirmed that our cancelation worked
                }
                return switch (getLastError()) {
                    .ERROR_NOT_FOUND => true, // this might mean the operation hasn't started yet
                    else => false,
                };
            },
            .unused => unreachable,
            .blocked_alertable_canceling => {
                return w32.QueueUserAPC(noopApc, thread.handle, 0) != 0;
            },
            else => {
                // The thread is working on `awaitable`, but no longer needs signaling (they already
                // woke up and saw the cancelation).
                return false;
            },
        }
    }

    fn noopApc(_: usize) callconv(.winapi) void {}

    /// Like a `*Thread`, but 2 bits smaller than a pointer (because the LSBs are always 0 due to
    /// alignment) so that those two bits can be used in a `packed struct`.
    const PackedPtr = enum(@Int(.unsigned, @bitSizeOf(usize) - 2)) {
        null = 0,
        all_ones = std.math.maxInt(@Int(.unsigned, @bitSizeOf(usize) - 2)),
        _,

        const Split = packed struct(usize) { low: u2, high: PackedPtr };
        fn pack(ptr: *Thread) PackedPtr {
            const split: Split = @bitCast(@intFromPtr(ptr));
            assert(split.low == 0);
            return split.high;
        }
        fn unpack(ptr: PackedPtr) ?*Thread {
            const split: Split = .{ .low = 0, .high = ptr };
            return @ptrFromInt(@as(usize, @bitCast(split)));
        }
    };
};

/// Converts an optional relative timeout in nanoseconds to the milliseconds
/// expected by Win32 wait functions, rounding up so that the wait is never
/// shorter than requested.
fn nanosecondsToMilliseconds(timeout_ns: ?u64) u32 {
    const ns = timeout_ns orelse return INFINITE;
    const ms = std.math.divCeil(u64, ns, std.time.ns_per_ms) catch unreachable;
    return std.math.cast(u32, ms) orelse INFINITE - 1;
}

const Syscall = struct {
    thread: ?*Thread,
    /// Marks entry to a syscall region. This should be tightly scoped around the actual syscall
    /// to minimize races. The syscall must be marked as "finished" by `checkCancel`, `finish`,
    /// or one of the wrappers of `finish`.
    fn start() Io.Cancelable!Syscall {
        const thread = Thread.current orelse return .{ .thread = null };
        switch (thread.cancel_protection) {
            .blocked => return .{ .thread = null },
            .unblocked => {},
        }
        switch (thread.status.fetchOr(.{
            .cancelation = @fromBackingInt(@intCast(0b011)),
            .awaitable = .null,
        }, .monotonic).cancelation) {
            .blocked => unreachable,
            .blocked_alertable => unreachable,
            .unused => unreachable,
            .blocked_alertable_canceling => unreachable,
            .blocked_canceling => unreachable,
            .none => return .{ .thread = thread }, // new status is `.blocked`
            .canceling => return error.Canceled, // new status is `.canceled`
            .canceled => return .{ .thread = null }, // new status is `.canceled` (unchanged)
        }
    }
    /// Checks whether this syscall has been canceled. This should be called when a syscall is
    /// interrupted through a mechanism which may indicate cancelation, or may be spurious. If
    /// the syscall was canceled, it is finished and `error.Canceled` is returned. Otherwise,
    /// the syscall is not marked finished, and the caller should retry.
    fn checkCancel(s: Syscall) Io.Cancelable!void {
        const thread = s.thread orelse return;
        switch (thread.status.fetchOr(.{
            .cancelation = @fromBackingInt(@intCast(0b010)),
            .awaitable = .null,
        }, .monotonic).cancelation) {
            .none => unreachable,
            .blocked_alertable => unreachable,
            .unused => unreachable,
            .blocked_alertable_canceling => unreachable,
            .canceling => unreachable,
            .canceled => unreachable,
            .blocked => {}, // new status is `.blocked` (unchanged)
            .blocked_canceling => return error.Canceled, // new status is `.canceled`
        }
    }
    /// Marks this syscall as finished.
    fn finish(s: Syscall) void {
        const thread = s.thread orelse return;
        switch (thread.status.fetchXor(.{
            .cancelation = @fromBackingInt(@intCast(0b011)),
            .awaitable = .null,
        }, .monotonic).cancelation) {
            .none => unreachable,
            .blocked_alertable => unreachable,
            .unused => unreachable,
            .blocked_alertable_canceling => unreachable,
            .canceling => unreachable,
            .canceled => unreachable,
            .blocked => {}, // new status is `.none`
            .blocked_canceling => {}, // new status is `.canceling`
        }
    }
    /// Convenience wrapper which calls `finish`, then returns `err`.
    fn fail(s: Syscall, err: anytype) @TypeOf(err) {
        s.finish();
        return err;
    }
    /// Convenience wrapper which calls `finish`, then calls `unexpectedError`.
    fn unexpectedError(s: Syscall, err: w32.WIN32_ERROR) Io.UnexpectedError {
        @branchHint(.cold);
        s.finish();
        return WinIo.unexpectedError(err);
    }
    /// Convenience wrapper which calls `finish`, then calls `errorBug`.
    fn errorBug(s: Syscall, err: w32.WIN32_ERROR) Io.UnexpectedError {
        @branchHint(.cold);
        s.finish();
        return WinIo.errorBug(err);
    }
};

/// Like `Syscall`, but for alertable waits, which are interrupted by queueing
/// an APC to the thread instead of with `CancelSynchronousIo`.
const AlertableSyscall = struct {
    thread: ?*Thread,

    fn start() Io.Cancelable!AlertableSyscall {
        const thread = Thread.current orelse return .{ .thread = null };
        switch (thread.cancel_protection) {
            .blocked => return .{ .thread = null },
            .unblocked => {},
        }
        const old_status = thread.status.fetchOr(.{
            .cancelation = @fromBackingInt(@intCast(0b010)),
            .awaitable = .null,
        }, .monotonic);
        switch (old_status.cancelation) {
            .blocked => unreachable,
            .blocked_alertable => unreachable,
            .blocked_canceling => unreachable,
            .unused => unreachable,
            .blocked_alertable_canceling => unreachable,
            .none => return .{ .thread = thread }, // new status is `.blocked_alertable`
            .canceling => {
                // Status is unchanged (still `.canceling`)---change to `.canceled` before return.
                thread.status.store(.{ .cancelation = .canceled, .awaitable = old_status.awaitable }, .monotonic);
                return error.Canceled;
            },
            .canceled => return .{ .thread = null }, // new status is `.canceled` (unchanged)
        }
    }

    fn checkCancel(s: AlertableSyscall) Io.Cancelable!void {
        const thread = s.thread orelse return;
        const old_status = thread.status.fetchOr(.{
            .cancelation = @fromBackingInt(@intCast(0b010)),
            .awaitable = .null,
        }, .monotonic);
        switch (old_status.cancelation) {
            .none => unreachable,
            .blocked => unreachable,
            .blocked_canceling => unreachable,
            .canceling => unreachable,
            .canceled => unreachable,
            .blocked_alertable => {}, // new status is `.blocked_alertable` (unchanged)
            .unused => unreachable,
            .blocked_alertable_canceling => {
                // New status is `.canceling`---change to `.canceled` before return.
                thread.status.store(.{ .cancelation = .canceled, .awaitable = old_status.awaitable }, .monotonic);
                return error.Canceled;
            },
        }
    }

    fn finish(s: AlertableSyscall) void {
        const thread = s.thread orelse return;
        switch (thread.status.fetchXor(.{
            .cancelation = @fromBackingInt(@intCast(0b010)),
            .awaitable = .null,
        }, .monotonic).cancelation) {
            .none => unreachable,
            .blocked => unreachable,
            .blocked_canceling => unreachable,
            .canceling => unreachable,
            .canceled => unreachable,
            .blocked_alertable => {}, // new status is `.none`
            .unused => unreachable,
            .blocked_alertable_canceling => {}, // new status is `.canceling`
        }
    }

    fn fail(s: AlertableSyscall, err: anytype) @TypeOf(err) {
        s.finish();
        return err;
    }
};

fn workerEntry(param: ?*anyopaque) callconv(.winapi) u32 {
    const w: *WinIo = @ptrCast(@alignCast(param));
    worker(w);
    return 0;
}

fn worker(w: *WinIo) void {
    var thread: Thread = .{
        .next = undefined,
        .handle = w32.OpenThread(
            .{ .TERMINATE = 1, .SET_CONTEXT = 1 },
            w32.FALSE,
            w32.GetCurrentThreadId(),
        ) orelse @panic("OpenThread failed on the current thread"),
        .status = .init(.{
            .cancelation = .none,
            .awaitable = .null,
        }),
        .cancel_protection = .unblocked,
        .wait_address = .init(null),
        .csprng = .uninitialized,
    };
    Thread.current = &thread;
    defer _ = w32.CloseHandle(thread.handle);

    {
        var head = w.worker_threads.load(.monotonic);
        while (true) {
            thread.next = head;
            head = w.worker_threads.cmpxchgWeak(
                head,
                &thread,
                .release,
                .monotonic,
            ) orelse break;
        }
    }

    defer w.wait_group.finish();

    mutexLockUncancelable(&w.mutex);
    defer mutexUnlock(&w.mutex);

    while (true) {
        while (w.run_queue.popFirst()) |runnable_node| {
            mutexUnlock(&w.mutex);
            thread.cancel_protection = .unblocked;
            const runnable: *Runnable = @fieldParentPtr("node", runnable_node);
            runnable.startFn(runnable, &thread, w);
            mutexLockUncancelable(&w.mutex);
            w.busy_count -= 1;
        }
        if (w.join_requested) break;
        condWait(&w.cond, &w.mutex);
    }
}

/// Spawns a detached worker thread. The caller must hold `w.mutex`.
fn spawnWorker(w: *WinIo) error{SystemResources}!void {
    const handle = w32.CreateThread(
        null,
        w.stack_size,
        workerEntry,
        w,
        w32.STACK_SIZE_PARAM_IS_A_RESERVATION,
        null,
    ) orelse return error.SystemResources;
    _ = w32.CloseHandle(handle);
}

fn crashHandler(userdata: ?*anyopaque) void {
    _ = userdata;
    const thread = Thread.current orelse return;
    thread.status.store(.{ .cancelation = .canceled, .awaitable = .null }, .monotonic);
    thread.cancel_protection = .blocked;
}

fn async(
    userdata: ?*anyopaque,
    result: []u8,
    result_alignment: Alignment,
    context: []const u8,
    context_alignment: Alignment,
    start: *const fn (context: *const anyopaque, result: *anyopaque) void,
) ?*Io.AnyFuture {
    const w = fromUserdata(userdata);
    if (builtin.single_threaded) {
        start(context.ptr, result.ptr);
        return null;
    }

    const gpa = w.allocator;
    const future = Future.create(gpa, result.len, result_alignment, context, context_alignment, start) catch |err| switch (err) {
        error.OutOfMemory => {
            start(context.ptr, result.ptr);
            return null;
        },
    };

    mutexLockUncancelable(&w.mutex);

    const busy_count = w.busy_count;

    if (busy_count >= @backingInt(w.async_limit)) {
        mutexUnlock(&w.mutex);
        future.destroy(gpa);
        start(context.ptr, result.ptr);
        return null;
    }

    w.busy_count = busy_count + 1;

    const pool_size = w.wait_group.value();
    if (pool_size - busy_count == 0) {
        w.wait_group.start();
        w.spawnWorker() catch {
            w.wait_group.finish();
            w.busy_count = busy_count;
            mutexUnlock(&w.mutex);
            future.destroy(gpa);
            start(context.ptr, result.ptr);
            return null;
        };
    }

    w.run_queue.prepend(&future.runnable.node);

    mutexUnlock(&w.mutex);
    condSignal(&w.cond);
    return @ptrCast(future);
}

fn concurrent(
    userdata: ?*anyopaque,
    result_len: usize,
    result_alignment: Alignment,
    context: []const u8,
    context_alignment: Alignment,
    start: *const fn (context: *const anyopaque, result: *anyopaque) void,
) Io.ConcurrentError!*Io.AnyFuture {
    if (builtin.single_threaded) return error.ConcurrencyUnavailable;

    const w = fromUserdata(userdata);

    const gpa = w.allocator;
    const future = Future.create(gpa, result_len, result_alignment, context, context_alignment, start) catch |err| switch (err) {
        error.OutOfMemory => return error.ConcurrencyUnavailable,
    };
    errdefer future.destroy(gpa);

    mutexLockUncancelable(&w.mutex);
    defer mutexUnlock(&w.mutex);

    const busy_count = w.busy_count;

    if (busy_count >= @backingInt(w.concurrent_limit))
        return error.ConcurrencyUnavailable;

    w.busy_count = busy_count + 1;
    errdefer w.busy_count = busy_count;

    const pool_size = w.wait_group.value();
    if (pool_size - busy_count == 0) {
        w.wait_group.start();
        errdefer w.wait_group.finish();

        w.spawnWorker() catch return error.ConcurrencyUnavailable;
    }

    w.run_queue.prepend(&future.runnable.node);

    condSignal(&w.cond);
    return @ptrCast(future);
}

fn groupAsync(
    userdata: ?*anyopaque,
    type_erased: *Io.Group,
    context: []const u8,
    context_alignment: Alignment,
    start: *const fn (context: *const anyopaque) void,
) void {
    const w = fromUserdata(userdata);
    const g: Group = .{ .ptr = type_erased };

    if (builtin.single_threaded) return start(context.ptr);

    const gpa = w.allocator;
    const task = Group.Task.create(gpa, g, context, context_alignment, start) catch |err| switch (err) {
        error.OutOfMemory => return start(context.ptr),
    };

    mutexLockUncancelable(&w.mutex);

    const busy_count = w.busy_count;

    if (busy_count >= @backingInt(w.async_limit)) {
        mutexUnlock(&w.mutex);
        task.destroy(gpa);
        return start(context.ptr);
    }

    w.busy_count = busy_count + 1;

    const pool_size = w.wait_group.value();
    if (pool_size - busy_count == 0) {
        w.wait_group.start();
        w.spawnWorker() catch {
            w.wait_group.finish();
            w.busy_count = busy_count;
            mutexUnlock(&w.mutex);
            task.destroy(gpa);
            return start(context.ptr);
        };
    }

    // TODO: if this logic is changed to be lock-free, this `fetchAdd` must be released by the queue
    // prepend so that the task doesn't finish without observing this and try to decrement the count
    // below zero.
    _ = g.status().fetchAdd(.{
        .num_running = 1,
        .have_awaiter = false,
        .canceled = false,
    }, .monotonic);
    w.run_queue.prepend(&task.runnable.node);

    mutexUnlock(&w.mutex);
    condSignal(&w.cond);
}

fn groupConcurrent(
    userdata: ?*anyopaque,
    type_erased: *Io.Group,
    context: []const u8,
    context_alignment: Alignment,
    start: *const fn (context: *const anyopaque) void,
) Io.ConcurrentError!void {
    if (builtin.single_threaded) return error.ConcurrencyUnavailable;

    const w = fromUserdata(userdata);
    const g: Group = .{ .ptr = type_erased };

    const gpa = w.allocator;
    const task = Group.Task.create(gpa, g, context, context_alignment, start) catch |err| switch (err) {
        error.OutOfMemory => return error.ConcurrencyUnavailable,
    };
    errdefer task.destroy(gpa);

    mutexLockUncancelable(&w.mutex);
    defer mutexUnlock(&w.mutex);

    const busy_count = w.busy_count;

    if (busy_count >= @backingInt(w.concurrent_limit))
        return error.ConcurrencyUnavailable;

    w.busy_count = busy_count + 1;
    errdefer w.busy_count = busy_count;

    const pool_size = w.wait_group.value();
    if (pool_size - busy_count == 0) {
        w.wait_group.start();
        errdefer w.wait_group.finish();

        w.spawnWorker() catch return error.ConcurrencyUnavailable;
    }

    // TODO: if this logic is changed to be lock-free, this `fetchAdd` must be released by the queue
    // prepend so that the task doesn't finish without observing this and try to decrement the count
    // below zero.
    _ = g.status().fetchAdd(.{
        .num_running = 1,
        .have_awaiter = false,
        .canceled = false,
    }, .monotonic);
    w.run_queue.prepend(&task.runnable.node);

    condSignal(&w.cond);
}

fn groupAwait(userdata: ?*anyopaque, type_erased: *Io.Group, initial_token: *anyopaque) Io.Cancelable!void {
    _ = initial_token; // we need to load `token` *after* the group finishes
    if (builtin.single_threaded) unreachable; // nothing to await
    const w = fromUserdata(userdata);
    const g: Group = .{ .ptr = type_erased };

    var num_completed: std.atomic.Value(u32) = .init(0);
    g.awaiter().* = &num_completed;

    const pre_await_status = g.status().fetchOr(.{
        .num_running = 0,
        .have_awaiter = true,
        .canceled = false,
    }, .acq_rel); // acquire results if complete; release `g.awaiter()`

    assert(!pre_await_status.have_awaiter);
    assert(!pre_await_status.canceled);
    if (pre_await_status.num_running == 0) {
        // Already done. Since the group is finished, it's illegal to spawn more tasks in it
        // until we return, so we can access `g.status()` non-atomically.
        g.status().raw.have_awaiter = false;
        return;
    }

    while (Thread.futexWait(&num_completed.raw, 0, null)) {
        switch (num_completed.load(.acquire)) { // acquire task results
            0 => continue,
            1 => break,
            else => unreachable, // group was reused before `await` returned
        }
    } else |err| switch (err) {
        error.Canceled => {
            const pre_cancel_status = g.status().fetchOr(.{
                .num_running = 0,
                .have_awaiter = false,
                .canceled = true,
            }, .acq_rel); // acquire results if complete; release `g.awaiter()`
            assert(pre_cancel_status.have_awaiter);
            assert(!pre_cancel_status.canceled);

            // Even if `pre_cancel_status.num_running == 0`, we still need to wait for the signal,
            // because in that case the last member of the group is already trying to modify it.
            // However, if we know everything is done, we *can* skip signaling blocked threads.
            const skip_signals = pre_cancel_status.num_running == 0;
            g.waitForCancelWithSignaling(w, &num_completed, skip_signals);

            // The group is finished, so it's illegal to spawn more tasks in it until we return, so
            // we can access `g.status()` non-atomically.
            g.status().raw.canceled = false;
            g.status().raw.have_awaiter = false;
            return error.Canceled;
        },
    }

    // The group is finished, so it's illegal to spawn more tasks in it until we return, so
    // we can access `g.status()` non-atomically.
    g.status().raw.have_awaiter = false;
}

fn groupCancel(userdata: ?*anyopaque, type_erased: *Io.Group, initial_token: *anyopaque) void {
    _ = initial_token;
    if (builtin.single_threaded) unreachable; // nothing to cancel
    const w = fromUserdata(userdata);
    const g: Group = .{ .ptr = type_erased };

    var num_completed: std.atomic.Value(u32) = .init(0);
    g.awaiter().* = &num_completed;

    const pre_cancel_status = g.status().fetchOr(.{
        .num_running = 0,
        .have_awaiter = true,
        .canceled = true,
    }, .acq_rel); // acquire results if complete; release `g.awaiter()`

    assert(!pre_cancel_status.have_awaiter);
    assert(!pre_cancel_status.canceled);
    if (pre_cancel_status.num_running == 0) {
        // Already done. Since the group is finished, it's illegal to spawn more tasks in it
        // until we return, so we can access `g.status()` non-atomically.
        g.status().raw.have_awaiter = false;
        g.status().raw.canceled = false;
        return;
    }

    g.waitForCancelWithSignaling(w, &num_completed, false);

    g.status().raw = .{ .num_running = 0, .have_awaiter = false, .canceled = false };
}

fn recancel(userdata: ?*anyopaque) void {
    _ = userdata;
    recancelInner();
}

fn recancelInner() void {
    const thread = Thread.current.?; // called `recancel` but was not canceled
    switch (thread.status.fetchXor(.{
        .cancelation = @fromBackingInt(@intCast(0b001)),
        .awaitable = .null,
    }, .monotonic).cancelation) {
        .canceled => {},
        .none => unreachable, // called `recancel` but was not canceled
        .canceling => unreachable, // called `recancel` but cancelation was already pending
        .blocked => unreachable,
        .blocked_alertable => unreachable,
        .unused => unreachable,
        .blocked_alertable_canceling => unreachable,
        .blocked_canceling => unreachable,
    }
}

fn swapCancelProtection(userdata: ?*anyopaque, new: Io.CancelProtection) Io.CancelProtection {
    _ = userdata;
    const thread = Thread.current orelse return .unblocked;
    const old = thread.cancel_protection;
    thread.cancel_protection = new;
    return old;
}

fn checkCancel(userdata: ?*anyopaque) Io.Cancelable!void {
    _ = userdata;
    return Thread.checkCancel();
}

fn await(
    userdata: ?*anyopaque,
    any_future: *Io.AnyFuture,
    result: []u8,
    result_alignment: Alignment,
) void {
    _ = result_alignment;
    if (builtin.single_threaded) unreachable; // nothing to await
    const w = fromUserdata(userdata);
    const future: *Future = @ptrCast(@alignCast(any_future));

    var num_completed: std.atomic.Value(u32) = .init(0);
    future.awaiter = &num_completed;

    const pre_await_status = future.status.fetchOr(.{
        .tag = .pending_awaited,
        .thread = .null,
    }, .acq_rel); // acquire results if complete; release `future.awaiter`
    switch (pre_await_status.tag) {
        .pending => while (Thread.futexWait(&num_completed.raw, 0, null)) {
            switch (num_completed.load(.acquire)) { // acquire task results
                0 => continue,
                1 => break,
                else => unreachable, // group was reused before `await` returned
            }
        } else |err| switch (err) {
            error.Canceled => {
                const pre_cancel_status = future.status.fetchOr(.{
                    .tag = .pending_canceled,
                    .thread = .null,
                }, .acq_rel); // acquire results if complete; release `future.awaiter`
                const done_status = switch (pre_cancel_status.tag) {
                    .pending => unreachable, // invalid state: we already awaited
                    .pending_awaited => done_status: {
                        const working_thread = pre_cancel_status.thread.unpack();
                        future.waitForCancelWithSignaling(&num_completed, @alignCast(working_thread));
                        break :done_status future.status.load(.monotonic);
                    },
                    .pending_canceled => unreachable, // `await` raced with `cancel`
                    .done => done_status: {
                        // The task just finished, but we still need to wait for the signal, because the
                        // task thread already figured out that they need to update `future.awaiter`.
                        future.waitForCancelWithSignaling(&num_completed, null);
                        // Also, we have clobbered `future.status.tag` to `.pending_canceled`, but that's
                        // not actually a problem for the logic below.
                        break :done_status pre_cancel_status;
                    },
                };
                // If the future did not acknowledge the cancelation, we need to mark it outstanding
                // for us. Because `done_status.tag == .done`, the information about whether there
                // was an acknowledged cancelation is encoded in `done_status.thread`.
                assert(done_status.tag == .done);
                switch (done_status.thread) {
                    .null => recancelInner(), // cancelation was not acknowledged, so it's ours
                    .all_ones => {}, // cancelation was acknowledged, so it was this task's job to propagate it
                    _ => unreachable,
                }
            },
        },
        .pending_awaited => unreachable, // `await` raced with `await`
        .pending_canceled => unreachable, // `await` raced with `cancel`
        .done => {},
    }
    @memcpy(result, future.resultPointer());
    future.destroy(w.allocator);
}

fn cancel(
    userdata: ?*anyopaque,
    any_future: *Io.AnyFuture,
    result: []u8,
    result_alignment: Alignment,
) void {
    _ = result_alignment;
    if (builtin.single_threaded) unreachable; // nothing to cancel
    const w = fromUserdata(userdata);
    const future: *Future = @ptrCast(@alignCast(any_future));

    var num_completed: std.atomic.Value(u32) = .init(0);
    future.awaiter = &num_completed;

    const pre_cancel_status = future.status.fetchOr(.{
        .tag = .pending_canceled,
        .thread = .null,
    }, .acq_rel); // acquire results if complete; release `future.awaiter`
    switch (pre_cancel_status.tag) {
        .pending => {
            const working_thread = pre_cancel_status.thread.unpack();
            future.waitForCancelWithSignaling(&num_completed, @alignCast(working_thread));
        },
        .pending_awaited => unreachable, // `await` raced with `await`
        .pending_canceled => unreachable, // `await` raced with `cancel`
        .done => {},
    }
    @memcpy(result, future.resultPointer());
    future.destroy(w.allocator);
}

fn futexWait(userdata: ?*anyopaque, ptr: *const u32, expected: u32, timeout: Io.Timeout) Io.Cancelable!void {
    if (builtin.single_threaded) {
        assert(timeout != .none); // Deadlock.
        return;
    }
    const w = fromUserdata(userdata);
    const timeout_ns: ?u64 = ns: {
        const d = timeout.toDurationFromNow(w.io()) orelse break :ns null;
        break :ns std.math.lossyCast(u64, d.raw.toNanoseconds());
    };
    return Thread.futexWait(ptr, expected, timeout_ns);
}

fn futexWaitUncancelable(userdata: ?*anyopaque, ptr: *const u32, expected: u32) void {
    if (builtin.single_threaded) unreachable; // Deadlock.
    _ = userdata;
    Thread.futexWaitUncancelable(ptr, expected, null);
}

fn futexWake(userdata: ?*anyopaque, ptr: *const u32, max_waiters: u32) void {
    if (builtin.single_threaded) return; // Nothing to wake up.
    _ = userdata;
    Thread.futexWake(ptr, max_waiters);
}

const WaitGroup = struct {
    state: std.atomic.Value(usize),
    event: Io.Event,

    const init: WaitGroup = .{ .state = .{ .raw = 0 }, .event = .unset };

    const is_waiting: usize = 1 << 0;
    const one_pending: usize = 1 << 1;

    fn start(wg: *WaitGroup) void {
        const prev_state = wg.state.fetchAdd(one_pending, .monotonic);
        assert((prev_state / one_pending) < (std.math.maxInt(usize) / one_pending));
    }

    fn value(wg: *WaitGroup) usize {
        return wg.state.load(.monotonic) / one_pending;
    }

    fn wait(wg: *WaitGroup) void {
        const prev_state = wg.state.fetchAdd(is_waiting, .acquire);
        assert(prev_state & is_waiting == 0);
        if ((prev_state / one_pending) > 0) eventWait(&wg.event);
    }

    fn finish(wg: *WaitGroup) void {
        const state = wg.state.fetchSub(one_pending, .acq_rel);
        assert((state / one_pending) > 0);

        if (state == (one_pending | is_waiting)) {
            eventSet(&wg.event);
        }
    }
};

/// Same as `Io.Event.wait` but avoids the VTable.
fn eventWait(event: *Io.Event) void {
    if (@cmpxchgStrong(Io.Event, event, .unset, .waiting, .acquire, .acquire)) |prev| switch (prev) {
        .unset => unreachable,
        .waiting => {},
        .is_set => return,
    };
    while (true) {
        Thread.futexWaitUncancelable(@ptrCast(event), @backingInt(Io.Event.waiting), null);
        switch (@atomicLoad(Io.Event, event, .acquire)) {
            .unset => unreachable, // `reset` called before pending `wait` returned
            .waiting => continue,
            .is_set => return,
        }
    }
}

/// Same as `Io.Event.set` but avoids the VTable.
fn eventSet(event: *Io.Event) void {
    switch (@atomicRmw(Io.Event, event, .Xchg, .is_set, .release)) {
        .unset, .is_set => {},
        .waiting => Thread.futexWake(@ptrCast(event), std.math.maxInt(u32)),
    }
}

/// Same as `Io.Condition.broadcast` but avoids the VTable.
fn condBroadcast(cond: *Io.Condition) void {
    var prev_state = cond.state.load(.monotonic);
    while (prev_state.waiters > prev_state.signals) {
        @branchHint(.unlikely);
        prev_state = cond.state.cmpxchgWeak(prev_state, .{
            .waiters = prev_state.waiters,
            .signals = prev_state.waiters,
        }, .release, .monotonic) orelse {
            // Update the epoch to tell the waiting threads that there are new signals for them.
            _ = cond.epoch.fetchAdd(1, .release); // `.release` to ensure ordered after `state` update
            Thread.futexWake(&cond.epoch.raw, prev_state.waiters - prev_state.signals);
            return;
        };
    }
}

/// Same as `Io.Condition.signal` but avoids the VTable.
fn condSignal(cond: *Io.Condition) void {
    var prev_state = cond.state.load(.monotonic);
    while (prev_state.waiters > prev_state.signals) {
        @branchHint(.unlikely);
        prev_state = cond.state.cmpxchgWeak(prev_state, .{
            .waiters = prev_state.waiters,
            .signals = prev_state.signals + 1,
        }, .release, .monotonic) orelse {
            // Update the epoch to tell the waiting threads that there are new signals for them.
            _ = cond.epoch.fetchAdd(1, .release); // `.release` to ensure ordered after `state` update
            Thread.futexWake(&cond.epoch.raw, 1);
            return;
        };
    }
}

/// Same as `Io.Condition.waitUncancelable` but avoids the VTable.
fn condWait(cond: *Io.Condition, mutex: *Io.Mutex) void {
    var epoch = cond.epoch.load(.acquire); // `.acquire` to ensure ordered before state load

    {
        const prev_state = cond.state.fetchAdd(.{ .waiters = 1, .signals = 0 }, .monotonic);
        assert(prev_state.waiters < std.math.maxInt(u16)); // overflow caused by too many waiters
    }

    mutexUnlock(mutex);
    defer mutexLockUncancelable(mutex);

    while (true) {
        Thread.futexWaitUncancelable(&cond.epoch.raw, epoch, null);

        epoch = cond.epoch.load(.acquire); // `.acquire` to ensure ordered before `state` laod

        var prev_state = cond.state.load(.monotonic);
        while (prev_state.signals > 0) {
            prev_state = cond.state.cmpxchgWeak(prev_state, .{
                .waiters = prev_state.waiters - 1,
                .signals = prev_state.signals - 1,
            }, .acquire, .monotonic) orelse {
                // We successfully consumed a signal.
                return;
            };
        }
    }
}

/// Same as `Io.Mutex.lock` but avoids the VTable.
fn mutexLock(m: *Io.Mutex) Io.Cancelable!void {
    const initial_state = m.state.cmpxchgStrong(
        .unlocked,
        .locked_once,
        .acquire,
        .monotonic,
    ) orelse {
        @branchHint(.likely);
        return;
    };
    if (initial_state == .contended) {
        try Thread.futexWait(@ptrCast(&m.state.raw), @backingInt(Io.Mutex.State.contended), null);
    }
    while (m.state.swap(.contended, .acquire) != .unlocked) {
        try Thread.futexWait(@ptrCast(&m.state.raw), @backingInt(Io.Mutex.State.contended), null);
    }
}

/// Same as `Io.Mutex.lockUncancelable` but avoids the VTable.
fn mutexLockUncancelable(m: *Io.Mutex) void {
    const initial_state = m.state.cmpxchgStrong(
        .unlocked,
        .locked_once,
        .acquire,
        .monotonic,
    ) orelse {
        @branchHint(.likely);
        return;
    };
    if (initial_state == .contended) {
        Thread.futexWaitUncancelable(@ptrCast(&m.state.raw), @backingInt(Io.Mutex.State.contended), null);
    }
    while (m.state.swap(.contended, .acquire) != .unlocked) {
        Thread.futexWaitUncancelable(@ptrCast(&m.state.raw), @backingInt(Io.Mutex.State.contended), null);
    }
}

/// Same as `Io.Mutex.unlock` but avoids the VTable.
fn mutexUnlock(m: *Io.Mutex) void {
    switch (m.state.swap(.unlocked, .release)) {
        .unlocked => unreachable,
        .locked_once => {},
        .contended => {
            @branchHint(.unlikely);
            Thread.futexWake(@ptrCast(&m.state.raw), 1);
        },
    }
}

// ---------------------------------------------------------------------------
// Time

/// Number of 100ns intervals between 1601-01-01 and 1970-01-01.
const windows_epoch_ns: i96 = std.time.epoch.windows * std.time.ns_per_s;

fn fileTimeToInt(ft: w32.FILETIME) u64 {
    return (@as(u64, ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
}

fn queryPerformanceFrequency() u64 {
    // Cannot fail on Windows XP and later.
    var qpf: w32.LARGE_INTEGER = undefined;
    assert(w32.QueryPerformanceFrequency(&qpf) != 0);
    return @bitCast(qpf.QuadPart);
}

fn queryPerformanceCounter() u64 {
    // Cannot fail on Windows XP and later.
    var qpc: w32.LARGE_INTEGER = undefined;
    assert(w32.QueryPerformanceCounter(&qpc) != 0);
    return @bitCast(qpc.QuadPart);
}

fn nowWindows(clock: Io.Clock) Io.Timestamp {
    switch (clock) {
        .real => {
            // 100ns granularity, counted from the Windows epoch (1601-01-01).
            var ft: w32.FILETIME = undefined;
            w32.GetSystemTimePreciseAsFileTime(&ft);
            return .{ .nanoseconds = @as(i96, fileTimeToInt(ft)) * 100 + windows_epoch_ns };
        },
        .awake, .boot => {
            const qpf = queryPerformanceFrequency();
            // QPC includes time suspended.
            const qpc = queryPerformanceCounter();

            // 10Mhz (1 qpc tick every 100ns) is a common enough QPF value that we can optimize on it.
            const common_qpf = 10_000_000;
            if (qpf == common_qpf) return .{ .nanoseconds = qpc * (std.time.ns_per_s / common_qpf) };

            // Convert to ns using fixed point.
            const scale = @as(u64, std.time.ns_per_s << 32) / @as(u32, @intCast(qpf));
            const result = (@as(u96, qpc) * scale) >> 32;
            return .{ .nanoseconds = @intCast(result) };
        },
        .cpu_process => {
            var creation: w32.FILETIME = undefined;
            var exit: w32.FILETIME = undefined;
            var kernel: w32.FILETIME = undefined;
            var user: w32.FILETIME = undefined;
            if (w32.GetProcessTimes(w32.GetCurrentProcess(), &creation, &exit, &kernel, &user) == 0) return .zero;
            const sum = @as(i96, fileTimeToInt(user)) + @as(i96, fileTimeToInt(kernel));
            return .{ .nanoseconds = sum * 100 };
        },
        .cpu_thread => {
            var creation: w32.FILETIME = undefined;
            var exit: w32.FILETIME = undefined;
            var kernel: w32.FILETIME = undefined;
            var user: w32.FILETIME = undefined;
            if (w32.GetThreadTimes(w32.GetCurrentThread(), &creation, &exit, &kernel, &user) == 0) return .zero;
            const sum = @as(i96, fileTimeToInt(user)) + @as(i96, fileTimeToInt(kernel));
            return .{ .nanoseconds = sum * 100 };
        },
    }
}

fn now(userdata: ?*anyopaque, clock: Io.Clock) Io.Timestamp {
    _ = userdata;
    return nowWindows(clock);
}

fn clockResolution(userdata: ?*anyopaque, clock: Io.Clock) Io.Clock.ResolutionError!Io.Duration {
    _ = userdata;
    return switch (clock) {
        .awake, .boot, .real => {
            const qpf = queryPerformanceFrequency();
            // 10Mhz (1 qpc tick every 100ns) is a common enough QPF value that we can optimize on it.
            const common_qpf = 10_000_000;
            if (qpf == common_qpf) return .fromNanoseconds(std.time.ns_per_s / common_qpf);

            // Convert to ns using fixed point.
            const scale = @as(u64, std.time.ns_per_s << 32) / @as(u32, @intCast(qpf));
            const result = scale >> 32;
            return .fromNanoseconds(result);
        },
        .cpu_process, .cpu_thread => return error.ClockUnavailable,
    };
}

/// Returns the milliseconds remaining until `deadline`, rounded up, or `null`
/// if the deadline has passed.
fn millisecondsUntil(deadline: Io.Clock.Timestamp) ?u32 {
    const remaining_ns = nowWindows(deadline.clock).durationTo(deadline.raw).nanoseconds;
    if (remaining_ns <= 0) return null;
    return nanosecondsToMilliseconds(std.math.lossyCast(u64, remaining_ns));
}

fn sleep(userdata: ?*anyopaque, timeout: Io.Timeout) Io.Cancelable!void {
    _ = userdata;
    return sleepInternal(timeout);
}

fn sleepInternal(timeout: Io.Timeout) Io.Cancelable!void {
    const deadline: ?Io.Clock.Timestamp = switch (timeout) {
        .none => null,
        .duration => |d| switch (d.clock) {
            .cpu_process, .cpu_thread => unreachable, // cannot sleep for CPU time
            else => .{ .raw = nowWindows(d.clock).addDuration(d.raw), .clock = d.clock },
        },
        .deadline => |d| switch (d.clock) {
            .cpu_process, .cpu_thread => unreachable, // cannot sleep for CPU time
            else => d,
        },
    };

    const syscall: AlertableSyscall = try .start();
    // Only cancelable sleeps are alertable, so that uncancelable ones are not
    // cut short by APCs queued for other reasons.
    const alertable: w32.BOOL = @intFromBool(syscall.thread != null);
    while (true) {
        const ms: u32 = if (deadline) |d| millisecondsUntil(d) orelse break else INFINITE;
        switch (w32.SleepEx(ms, alertable)) {
            WAIT_IO_COMPLETION => try syscall.checkCancel(),
            else => {}, // re-check the deadline; the clock may have advanced less than expected
        }
    }
    syscall.finish();
}

// ---------------------------------------------------------------------------
// Randomness

fn random(userdata: ?*anyopaque, buffer: []u8) void {
    const w = fromUserdata(userdata);
    const thread = Thread.current orelse return randomMainThread(w, buffer);
    if (!thread.csprng.isInitialized()) {
        @branchHint(.unlikely);
        var seed: [Csprng.seed_len]u8 = undefined;
        randomMainThread(w, &seed);
        thread.csprng.rng = .init(seed);
    }
    thread.csprng.rng.fill(buffer);
}

fn randomMainThread(w: *WinIo, buffer: []u8) void {
    mutexLockUncancelable(&w.mutex);
    defer mutexUnlock(&w.mutex);

    if (!w.csprng.isInitialized()) {
        @branchHint(.unlikely);
        var seed: [Csprng.seed_len]u8 = undefined;
        {
            mutexUnlock(&w.mutex);
            defer mutexLockUncancelable(&w.mutex);

            const prev = swapCancelProtection(w, .blocked);
            defer _ = swapCancelProtection(w, prev);

            randomSecure(w, &seed) catch |err| switch (err) {
                error.Canceled => unreachable,
                error.EntropyUnavailable => fallbackSeed(w, &seed),
            };
        }
        w.csprng.rng = .init(seed);
    }

    w.csprng.rng.fill(buffer);
}

fn fallbackSeed(aslr_addr: ?*anyopaque, seed: *[Csprng.seed_len]u8) void {
    @memset(seed, 0);
    std.mem.writeInt(usize, seed[seed.len - @sizeOf(usize) ..][0..@sizeOf(usize)], @intFromPtr(aslr_addr), .native);
    std.mem.writeInt(u64, seed[0..@sizeOf(u64)], queryPerformanceCounter(), .native);
}

fn randomSecure(userdata: ?*anyopaque, buffer: []u8) Io.RandomSecureError!void {
    _ = userdata;
    if (buffer.len == 0) return;
    var i: usize = 0;
    const syscall: Syscall = try .start();
    while (true) {
        const chunk_len = std.math.lossyCast(u32, buffer.len - i);
        if (w32.BCryptGenRandom(0, &buffer[i], chunk_len, w32.BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0) {
            return syscall.fail(error.EntropyUnavailable);
        }
        i += chunk_len;
        if (buffer.len - i == 0) return syscall.finish();
        try syscall.checkCancel();
    }
}

// ---------------------------------------------------------------------------
// File I/O

/// Waits until an APC (such as an I/O completion routine) runs on this thread.
fn waitForApc() void {
    _ = w32.SleepEx(INFINITE, w32.TRUE);
}

/// State of one overlapped `ReadFileEx`/`WriteFileEx` call, completed by
/// `overlappedCompletion` during an alertable wait.
const OverlappedOperation = struct {
    overlapped: w32.OVERLAPPED,
    done: bool = false,
    err: w32.WIN32_ERROR = .NO_ERROR,
    bytes: u32 = 0,

    fn init(offset: ?u64) OverlappedOperation {
        const o = offset orelse 0;
        return .{ .overlapped = .{
            .Internal = 0,
            .InternalHigh = 0,
            .Anonymous = .{ .Anonymous = .{
                .Offset = @truncate(o),
                .OffsetHigh = @truncate(o >> 32),
            } },
            .hEvent = null,
        } };
    }

    fn completion(err: u32, bytes: u32, overlapped: ?*w32.OVERLAPPED) callconv(.winapi) void {
        const op: *OverlappedOperation = @fieldParentPtr("overlapped", overlapped.?);
        op.err = win32Error(err);
        op.bytes = bytes;
        op.done = true;
    }

    /// Waits for the completion routine to run. Once the operation is issued,
    /// this must be called before `op` goes out of scope.
    fn wait(op: *OverlappedOperation, handle: w32.HANDLE) Io.Cancelable!void {
        while (!op.done) {
            const alertable_syscall = AlertableSyscall.start() catch |err| switch (err) {
                error.Canceled => |e| {
                    _ = w32.CancelIoEx(handle, &op.overlapped);
                    while (!op.done) waitForApc();
                    return e;
                },
            };
            waitForApc();
            alertable_syscall.finish();
        }
    }
};

const ReadResult = struct { w32.WIN32_ERROR, u32 };

/// Reads from `file` into `buffer`, at `offset` if not null. Returns the error
/// code (`.NO_ERROR` on success) and the number of bytes read.
fn readFileWindows(file: Io.File, buffer: []u8, offset: ?u64) Io.Cancelable!ReadResult {
    const len = std.math.lossyCast(u32, buffer.len);
    if (file.flags.nonblocking) {
        var op: OverlappedOperation = .init(offset);
        if (w32.ReadFileEx(file.handle, buffer.ptr, len, &op.overlapped, OverlappedOperation.completion) == 0) {
            return .{ getLastError(), 0 };
        }
        try op.wait(file.handle);
        return .{ op.err, op.bytes };
    }
    // For a synchronous handle, `ReadFile` reads at the offset in the
    // `OVERLAPPED` and blocks until done.
    var op: OverlappedOperation = .init(offset);
    const syscall: Syscall = try .start();
    while (true) {
        var n: u32 = 0;
        if (w32.ReadFile(file.handle, buffer.ptr, len, &n, if (offset != null) &op.overlapped else null) != 0) {
            syscall.finish();
            return .{ .NO_ERROR, n };
        }
        switch (getLastError()) {
            .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
            else => |err| {
                syscall.finish();
                return .{ err, 0 };
            },
        }
    }
}

/// Writes `buffer` to `file`, at `offset` if not null. Returns the error code
/// (`.NO_ERROR` on success) and the number of bytes written.
fn writeFileWindows(file: Io.File, buffer: []const u8, offset: ?u64) Io.Cancelable!ReadResult {
    const len = std.math.lossyCast(u32, buffer.len);
    if (file.flags.nonblocking) {
        var op: OverlappedOperation = .init(offset);
        if (w32.WriteFileEx(file.handle, buffer.ptr, len, &op.overlapped, OverlappedOperation.completion) == 0) {
            return .{ getLastError(), 0 };
        }
        try op.wait(file.handle);
        return .{ op.err, op.bytes };
    }
    var op: OverlappedOperation = .init(offset);
    const syscall: Syscall = try .start();
    while (true) {
        var n: u32 = 0;
        if (w32.WriteFile(file.handle, buffer.ptr, len, &n, if (offset != null) &op.overlapped else null) != 0) {
            syscall.finish();
            return .{ .NO_ERROR, n };
        }
        switch (getLastError()) {
            .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
            else => |err| {
                syscall.finish();
                return .{ err, 0 };
            },
        }
    }
}

/// Maps the result of a streaming read. A successful read of 0 bytes into a
/// non-empty buffer means end of file, since `ReadFile` reports
/// `STATUS_END_OF_FILE` that way.
fn readFileResult(err: w32.WIN32_ERROR, n: u32) !usize {
    switch (err) {
        .NO_ERROR => return if (n == 0) error.EndOfStream else n,
        .ERROR_HANDLE_EOF, .ERROR_BROKEN_PIPE, .ERROR_NO_DATA, .ERROR_PIPE_NOT_CONNECTED => return error.EndOfStream,
        .ERROR_INVALID_HANDLE => return error.NotOpenForReading,
        .ERROR_INVALID_FUNCTION => return error.IsDir,
        .ERROR_LOCK_VIOLATION => return error.LockViolation,
        .ERROR_ACCESS_DENIED => return error.AccessDenied,
        .ERROR_NOT_ENOUGH_MEMORY, .ERROR_NOT_ENOUGH_QUOTA, .ERROR_WORKING_SET_QUOTA => return error.SystemResources,
        .ERROR_OPERATION_ABORTED => unreachable,
        else => return unexpectedError(err),
    }
}

fn writeFileResult(err: w32.WIN32_ERROR, n: u32) !usize {
    switch (err) {
        .NO_ERROR => return n,
        .ERROR_INVALID_USER_BUFFER,
        .ERROR_NOT_ENOUGH_MEMORY,
        .ERROR_NOT_ENOUGH_QUOTA,
        .ERROR_WORKING_SET_QUOTA,
        => return error.SystemResources,
        .ERROR_BROKEN_PIPE, .ERROR_NO_DATA, .ERROR_PIPE_NOT_CONNECTED => return error.BrokenPipe,
        .ERROR_INVALID_HANDLE => return error.NotOpenForWriting,
        .ERROR_LOCK_VIOLATION => return error.LockViolation,
        .ERROR_ACCESS_DENIED => return error.AccessDenied,
        .ERROR_DISK_FULL, .ERROR_HANDLE_DISK_FULL => return error.NoSpaceLeft,
        .ERROR_OPERATION_ABORTED => unreachable,
        else => return unexpectedError(err),
    }
}

fn fileReadStreaming(file: Io.File, data: []const []u8) Io.File.ReadStreamingError!usize {
    var index: usize = 0;
    while (data.len - index != 0 and data[index].len == 0) index += 1;
    if (data.len - index == 0) return 0;
    const err, const n = try readFileWindows(file, data[index], null);
    return readFileResult(err, n);
}

fn fileReadPositional(userdata: ?*anyopaque, file: Io.File, data: []const []u8, offset: u64) Io.File.ReadPositionalError!usize {
    _ = userdata;
    var index: usize = 0;
    while (index < data.len and data[index].len == 0) index += 1;
    if (index == data.len) return 0;
    const err, const n = try readFileWindows(file, data[index], offset);
    return readFileResult(err, n) catch |e| switch (e) {
        error.EndOfStream => 0,
        else => |other| other,
    };
}

/// Since Windows only supports writing one contiguous buffer, returns the
/// first one, while also limiting it to a length representable by 32-bit
/// unsigned integer.
fn windowsWriteBuffer(header: []const u8, data: []const []const u8, splat: usize) []const u8 {
    const buffer = b: {
        if (header.len != 0) break :b header;
        for (data[0 .. data.len - 1]) |buffer| {
            if (buffer.len != 0) break :b buffer;
        }
        if (splat == 0) return &.{};
        break :b data[data.len - 1];
    };
    return buffer[0..std.math.lossyCast(u32, buffer.len)];
}

fn fileWriteStreaming(
    file: Io.File,
    header: []const u8,
    data: []const []const u8,
    splat: usize,
) Io.File.Writer.Error!usize {
    const buffer = windowsWriteBuffer(header, data, splat);
    if (buffer.len == 0) return 0;
    const err, const n = try writeFileWindows(file, buffer, null);
    return writeFileResult(err, n);
}

fn fileWritePositional(
    userdata: ?*anyopaque,
    file: Io.File,
    header: []const u8,
    data: []const []const u8,
    splat: usize,
    offset: u64,
) Io.File.WritePositionalError!usize {
    _ = userdata;
    const buffer = windowsWriteBuffer(header, data, splat);
    if (buffer.len == 0) return 0;
    const err, const n = try writeFileWindows(file, buffer, offset);
    return writeFileResult(err, n);
}

fn fileWriteFileStreaming(
    userdata: ?*anyopaque,
    file: Io.File,
    header: []const u8,
    file_reader: *Io.File.Reader,
    limit: Io.Limit,
) Io.File.Writer.WriteFileError!usize {
    _ = userdata;
    const reader_buffered = file_reader.interface.buffered();
    if (reader_buffered.len >= @backingInt(limit)) {
        const n = try fileWriteStreaming(file, header, &.{limit.slice(reader_buffered)}, 1);
        file_reader.interface.toss(n -| header.len);
        return n;
    }
    if (file_reader.size) |size| {
        if (size - file_reader.pos == 0) {
            if (reader_buffered.len != 0) {
                const n = try fileWriteStreaming(file, header, &.{limit.slice(reader_buffered)}, 1);
                file_reader.interface.toss(n -| header.len);
                return n;
            } else {
                return error.EndOfStream;
            }
        }
    }
    return error.Unimplemented;
}

fn fileWriteFilePositional(
    userdata: ?*anyopaque,
    file: Io.File,
    header: []const u8,
    file_reader: *Io.File.Reader,
    limit: Io.Limit,
    offset: u64,
) Io.File.WriteFilePositionalError!usize {
    const reader_buffered = file_reader.interface.buffered();
    if (reader_buffered.len >= @backingInt(limit)) {
        const n = try fileWritePositional(userdata, file, header, &.{limit.slice(reader_buffered)}, 1, offset);
        file_reader.interface.toss(n -| header.len);
        return n;
    }
    if (file_reader.size) |size| {
        if (size - file_reader.pos == 0) {
            if (reader_buffered.len != 0) {
                const n = try fileWritePositional(userdata, file, header, &.{limit.slice(reader_buffered)}, 1, offset);
                file_reader.interface.toss(n -| header.len);
                return n;
            } else {
                return error.EndOfStream;
            }
        }
    }
    return error.Unimplemented;
}

fn fileClose(userdata: ?*anyopaque, files: []const Io.File) void {
    _ = userdata;
    for (files) |file| _ = w32.CloseHandle(file.handle);
}

/// Moves the file pointer. Pipes and character devices have no file pointer,
/// so they are reported as unseekable.
fn setFilePointer(handle: w32.HANDLE, distance: i64, method: w32.SET_FILE_POINTER_MOVE_METHOD) Io.File.SeekError!void {
    const syscall: Syscall = try .start();
    if (w32.GetFileType(handle) != FILE_TYPE_DISK) return syscall.fail(error.Unseekable);
    while (true) {
        if (w32.SetFilePointerEx(handle, .{ .QuadPart = distance }, null, method) != 0) return syscall.finish();
        switch (getLastError()) {
            .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
            .ERROR_ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            .ERROR_NEGATIVE_SEEK, .ERROR_SEEK, .ERROR_INVALID_PARAMETER => return syscall.fail(error.Unseekable),
            else => |err| return syscall.unexpectedError(err),
        }
    }
}

fn fileSeekBy(userdata: ?*anyopaque, file: Io.File, offset: i64) Io.File.SeekError!void {
    _ = userdata;
    return setFilePointer(file.handle, offset, .CURRENT);
}

fn fileSeekTo(userdata: ?*anyopaque, file: Io.File, offset: u64) Io.File.SeekError!void {
    _ = userdata;
    return setFilePointer(file.handle, std.math.cast(i64, offset) orelse return error.Unseekable, .BEGIN);
}

// ---------------------------------------------------------------------------
// Device I/O control

/// Converts the most common Win32 error codes back to the NTSTATUS that
/// `Io.Operation.DeviceIoControl.Result` reports. Used only for synchronous
/// handles, where `DeviceIoControl` does not expose the original status.
fn ntstatusFromError(err: w32.WIN32_ERROR) std.os.windows.NTSTATUS {
    return switch (err) {
        .NO_ERROR => .SUCCESS,
        .ERROR_MORE_DATA => .BUFFER_OVERFLOW,
        .ERROR_INSUFFICIENT_BUFFER => .BUFFER_TOO_SMALL,
        .ERROR_ACCESS_DENIED => .ACCESS_DENIED,
        .ERROR_INVALID_HANDLE => .INVALID_HANDLE,
        .ERROR_INVALID_PARAMETER => .INVALID_PARAMETER,
        .ERROR_INVALID_FUNCTION => .INVALID_DEVICE_REQUEST,
        .ERROR_NOT_SUPPORTED => .NOT_SUPPORTED,
        .ERROR_NOT_FOUND => .NOT_FOUND,
        .ERROR_OPERATION_ABORTED => .CANCELLED,
        .ERROR_NOT_ENOUGH_MEMORY => .NO_MEMORY,
        .ERROR_BROKEN_PIPE => .PIPE_BROKEN,
        .ERROR_IO_PENDING => .PENDING,
        else => .UNSUCCESSFUL,
    };
}

fn deviceIoControl(o: *const Io.Operation.DeviceIoControl) Io.Cancelable!std.os.windows.IO_STATUS_BLOCK {
    const code: u32 = @bitCast(o.code);
    const in_ptr: ?*anyopaque = if (o.in.len > 0) @constCast(o.in.ptr) else null;
    const out_ptr: ?*anyopaque = if (o.out.len > 0) o.out.ptr else null;
    if (o.file.flags.nonblocking) {
        // `OVERLAPPED.Internal` and `InternalHigh` hold the status code and
        // the number of bytes transferred once the request completes.
        const event = w32.CreateEventW(null, w32.TRUE, w32.FALSE, null) orelse return .{
            .u = .{ .Status = .INSUFFICIENT_RESOURCES },
            .Information = 0,
        };
        defer _ = w32.CloseHandle(event);
        var overlapped: w32.OVERLAPPED = .{
            .Internal = 0,
            .InternalHigh = 0,
            .Anonymous = .{ .Anonymous = .{ .Offset = 0, .OffsetHigh = 0 } },
            .hEvent = event,
        };
        var returned: u32 = 0;
        if (w32.DeviceIoControl(o.file.handle, code, in_ptr, @intCast(o.in.len), out_ptr, @intCast(o.out.len), &returned, &overlapped) == 0) {
            switch (getLastError()) {
                .ERROR_IO_PENDING => {},
                else => |err| return .{ .u = .{ .Status = ntstatusFromError(err) }, .Information = 0 },
            }
        }
        while (true) {
            const alertable_syscall = AlertableSyscall.start() catch |err| switch (err) {
                error.Canceled => |e| {
                    _ = w32.CancelIoEx(o.file.handle, &overlapped);
                    _ = w32.WaitForSingleObjectEx(event, INFINITE, w32.FALSE);
                    return e;
                },
            };
            const rc = w32.WaitForSingleObjectEx(event, INFINITE, w32.TRUE);
            alertable_syscall.finish();
            if (@backingInt(rc) != WAIT_IO_COMPLETION) break;
        }
        return .{
            .u = .{ .Status = @fromBackingInt(@intCast(@as(u32, @truncate(overlapped.Internal)))) },
            .Information = overlapped.InternalHigh,
        };
    }
    const syscall: Syscall = try .start();
    while (true) {
        var returned: u32 = 0;
        if (w32.DeviceIoControl(o.file.handle, code, in_ptr, @intCast(o.in.len), out_ptr, @intCast(o.out.len), &returned, null) != 0) {
            syscall.finish();
            return .{ .u = .{ .Status = .SUCCESS }, .Information = returned };
        }
        switch (getLastError()) {
            .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
            .ERROR_MORE_DATA => {
                syscall.finish();
                return .{ .u = .{ .Status = .BUFFER_OVERFLOW }, .Information = returned };
            },
            else => |err| {
                syscall.finish();
                return .{ .u = .{ .Status = ntstatusFromError(err) }, .Information = 0 };
            },
        }
    }
}

// ---------------------------------------------------------------------------
// Operations and batches

fn operate(userdata: ?*anyopaque, operation: Io.Operation) Io.Cancelable!Io.Operation.Result {
    const w = fromUserdata(userdata);
    switch (operation) {
        .file_read_streaming => |o| return .{
            .file_read_streaming = fileReadStreaming(o.file, o.data) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| e,
            },
        },
        .file_write_streaming => |o| return .{
            .file_write_streaming = fileWriteStreaming(o.file, o.header, o.data, o.splat) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| e,
            },
        },
        .device_io_control => |*o| return .{ .device_io_control = try deviceIoControl(o) },
        .net_receive => |*o| return .{ .net_receive = r: {
            ensureWinsock(w) catch |err| break :r .{ err, 0 };
            break :r try netReceive(o.socket_handle, o.message_buffer, o.data_buffer, o.flags);
        } },
        .net_send => |*o| return .{
            .net_send = r: {
                ensureWinsock(w) catch |err| break :r .{ err, 0 };
                const send_err, const sent = netSend(o.socket_handle, o.messages, o.flags);
                if (send_err) |err| switch (err) {
                    error.Canceled => |e| if (sent == 0) {
                        return e;
                    } else {
                        // Leave the `error.Canceled` for later, but don't try to send any more messages.
                        recancelInner();
                        break :r .{ null, sent };
                    },
                    else => break :r .{ err, sent },
                };
                break :r .{ null, sent };
            },
        },
        .net_read => |o| return .{
            .net_read = netRead(o.socket_handle, o.data) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| e,
            },
        },
        .net_write => |o| return .{
            // Windows doesn't have the concept of control/ancillary data.
            .net_write = netWrite(o.socket_handle, o.header, o.data, o.splat) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| e,
            },
        },
    }
}

/// Per-operation state stored in `Io.Operation.Storage.Pending.userdata`.
///
/// Batch operations do not use completion routines: an APC only runs on the
/// thread that issued the I/O, but a batch may be awaited or canceled from
/// another thread. Instead, `overlapped.hEvent` is the batch's event (see
/// `batchEvent`), completion is detected with `HasOverlappedIoCompleted`, and
/// results are collected with `GetOverlappedResult`/`WSAGetOverlappedResult`,
/// all of which work from any thread.
const BatchOperationUserdata = extern struct {
    overlapped: w32.OVERLAPPED,
    handle: w32.HANDLE,
    /// For `net_receive`: the message to populate. For `net_read`: the flags.
    a: usize,
    /// For `net_receive`: the data buffer.
    b: usize,

    const Erased = Io.Operation.Storage.Pending.Userdata;

    comptime {
        assert(@sizeOf(BatchOperationUserdata) <= @sizeOf(Erased));
    }

    fn toErased(userdata: *BatchOperationUserdata) *Erased {
        return @ptrCast(userdata);
    }

    fn fromErased(erased: *Erased) *BatchOperationUserdata {
        return @ptrCast(erased);
    }

    fn init(userdata: *BatchOperationUserdata, event: w32.HANDLE, handle: w32.HANDLE) void {
        userdata.overlapped = emptyOverlapped(event);
        userdata.handle = handle;
    }

    /// `HasOverlappedIoCompleted`.
    fn hasCompleted(userdata: *const BatchOperationUserdata) bool {
        const STATUS_PENDING = 0x103;
        return @atomicLoad(usize, &userdata.overlapped.Internal, .acquire) != STATUS_PENDING;
    }
};

/// While a `net_receive` is pending in a batch, the sender address is
/// received into the memory of the message that will hold the result, since
/// `Pending.userdata` has no room for it.
const ReceiveScratch = extern struct {
    from: PosixAddress,
    from_len: i32,
    flags: u32,

    comptime {
        assert(@sizeOf(ReceiveScratch) <= @sizeOf(net.IncomingMessage));
        assert(@alignOf(ReceiveScratch) <= @alignOf(net.IncomingMessage));
    }

    fn of(message: *net.IncomingMessage) *ReceiveScratch {
        return @ptrCast(message);
    }
};

/// Returns the manual-reset event that the overlapped operations of `b`
/// signal, creating it if needed. It is kept in `b.userdata` while operations
/// are pending, and closed by `batchReleaseEvent`.
fn batchEvent(b: *Io.Batch) ?w32.HANDLE {
    if (b.userdata) |event| return @ptrCast(event);
    const event = w32.CreateEventW(null, w32.TRUE, w32.FALSE, null) orelse return null;
    b.userdata = @ptrCast(event);
    return event;
}

/// Closes the event of `b` if no operations are pending.
fn batchReleaseEvent(b: *Io.Batch) void {
    if (b.pending.head != .none) return;
    const event = b.userdata orelse return;
    _ = w32.CloseHandle(@ptrCast(event));
    b.userdata = null;
}

/// Moves the pending operation to the completed list with `result`.
fn batchComplete(b: *Io.Batch, operation_userdata: *BatchOperationUserdata, result: Io.Operation.Result) void {
    const pending = batchRemovePending(b, operation_userdata);
    const storage: *Io.Operation.Storage = @fieldParentPtr("pending", pending);
    const index: Io.Operation.OptionalIndex = .fromIndex(storage - b.storage.ptr);
    switch (b.completed.tail) {
        .none => b.completed.head = index,
        else => |tail_index| b.storage[tail_index.toIndex()].completion.node.next = index,
    }
    b.completed.tail = index;
    storage.* = .{ .completion = .{ .node = .{ .next = .none }, .result = result } };
}

/// Moves the pending operation back to the unused list.
fn batchDiscard(b: *Io.Batch, operation_userdata: *BatchOperationUserdata) void {
    const pending = batchRemovePending(b, operation_userdata);
    const storage: *Io.Operation.Storage = @fieldParentPtr("pending", pending);
    const index: Io.Operation.OptionalIndex = .fromIndex(storage - b.storage.ptr);
    const tail_index = b.unused.tail;
    switch (tail_index) {
        .none => b.unused.head = index,
        else => b.storage[tail_index.toIndex()].unused.next = index,
    }
    storage.* = .{ .unused = .{ .prev = tail_index, .next = .none } };
    b.unused.tail = index;
}

fn batchRemovePending(b: *Io.Batch, operation_userdata: *BatchOperationUserdata) *Io.Operation.Storage.Pending {
    const pending: *Io.Operation.Storage.Pending = @fieldParentPtr("userdata", operation_userdata.toErased());
    switch (pending.node.prev) {
        .none => b.pending.head = pending.node.next,
        else => |prev_index| b.storage[prev_index.toIndex()].pending.node.next = pending.node.next,
    }
    switch (pending.node.next) {
        .none => b.pending.tail = pending.node.prev,
        else => |next_index| b.storage[next_index.toIndex()].pending.node.prev = pending.node.prev,
    }
    return pending;
}

/// Moves the pending operations whose I/O has finished to the completed list,
/// or to the unused list if they were canceled.
fn batchCollect(b: *Io.Batch) void {
    var index = b.pending.head;
    while (index != .none) {
        const pending = &b.storage[index.toIndex()].pending;
        index = pending.node.next;
        const operation_userdata: *BatchOperationUserdata = .fromErased(&pending.userdata);
        if (!operation_userdata.hasCompleted()) continue;
        const overlapped = &operation_userdata.overlapped;
        var bytes: u32 = 0;
        switch (pending.tag) {
            inline .file_read_streaming, .file_write_streaming => |tag| {
                const err: w32.WIN32_ERROR = if (w32.GetOverlappedResult(operation_userdata.handle, overlapped, &bytes, w32.FALSE) != 0)
                    .NO_ERROR
                else
                    getLastError();
                if (err == .ERROR_OPERATION_ABORTED) {
                    batchDiscard(b, operation_userdata);
                    continue;
                }
                batchComplete(b, operation_userdata, switch (tag) {
                    .file_read_streaming => .{ .file_read_streaming = readFileResult(err, bytes) },
                    .file_write_streaming => .{ .file_write_streaming = writeFileResult(err, bytes) },
                    else => comptime unreachable,
                });
            },
            inline .net_receive, .net_read => |tag| {
                var flags: u32 = 0;
                const code: ?w32.WSA_ERROR = if (w32.WSAGetOverlappedResult(toSocket(operation_userdata.handle), overlapped, &bytes, w32.FALSE, &flags) != 0)
                    null
                else
                    wsaGetLastError();
                if (code == ._OPERATION_ABORTED) {
                    batchDiscard(b, operation_userdata);
                    continue;
                }
                batchComplete(b, operation_userdata, switch (tag) {
                    .net_receive => r: {
                        const message: *net.IncomingMessage = @ptrFromInt(operation_userdata.a);
                        if (code) |e| break :r .{ .net_receive = .{ receiveError(e), 0 } };
                        const from = ReceiveScratch.of(message).from;
                        const data: [*]u8 = @ptrFromInt(operation_userdata.b);
                        message.* = receivedMessage(&from, data[0..bytes], flags);
                        break :r .{ .net_receive = .{ null, 1 } };
                    },
                    .net_read => .{ .net_read = if (code) |e| switch (e) {
                        .EDISCON => .{ .data_len = 0 },
                        else => readError(e),
                    } else .{ .data_len = bytes } },
                    else => comptime unreachable,
                });
            },
            // Completed before `batchDrainSubmitted` returns.
            .device_io_control, .net_send, .net_write => unreachable,
        }
    }
}

/// Collects finished operations. Returns whether the caller has to wait on
/// the batch's event: operations are pending and none has completed.
fn batchMustWait(b: *Io.Batch) bool {
    if (b.pending.head == .none) return false;
    // Reset before collecting, so that an operation finishing in the meantime
    // leaves the event signaled for the next wait.
    _ = w32.ResetEvent(@ptrCast(b.userdata.?));
    batchCollect(b);
    return b.pending.head != .none and b.completed.head == .none;
}

/// If `concurrency` is false, `error.ConcurrencyUnavailable` is unreachable.
fn batchDrainSubmitted(userdata: ?*anyopaque, b: *Io.Batch, concurrency: bool) (Io.ConcurrentError || Io.Cancelable)!void {
    const w = fromUserdata(userdata);
    var index = b.submitted.head;
    errdefer b.submitted.head = index;
    while (index != .none) {
        const storage = &b.storage[index.toIndex()];
        const submission = storage.submission;
        storage.* = .{ .pending = .{
            .node = .{ .prev = b.pending.tail, .next = .none },
            .tag = submission.operation,
            .userdata = undefined,
        } };
        switch (b.pending.tail) {
            .none => b.pending.head = index,
            else => |tail_index| b.storage[tail_index.toIndex()].pending.node.next = index,
        }
        b.pending.tail = index;
        const operation_userdata: *BatchOperationUserdata = .fromErased(&storage.pending.userdata);
        errdefer batchDiscard(b, operation_userdata);
        switch (submission.operation) {
            .file_read_streaming => |o| o: {
                var data_index: usize = 0;
                while (o.data.len - data_index != 0 and o.data[data_index].len == 0) data_index += 1;
                if (o.data.len - data_index == 0) {
                    batchComplete(b, operation_userdata, .{ .file_read_streaming = 0 });
                    break :o;
                }
                const buffer = o.data[data_index];
                if (o.file.flags.nonblocking) {
                    const event = batchEvent(b) orelse {
                        batchComplete(b, operation_userdata, .{ .file_read_streaming = error.SystemResources });
                        break :o;
                    };
                    operation_userdata.init(event, o.file.handle);
                    if (w32.ReadFile(
                        o.file.handle,
                        buffer.ptr,
                        std.math.lossyCast(u32, buffer.len),
                        null,
                        &operation_userdata.overlapped,
                    ) == 0) switch (getLastError()) {
                        .ERROR_IO_PENDING => {},
                        else => |err| batchComplete(b, operation_userdata, .{ .file_read_streaming = readFileResult(err, 0) }),
                    };
                } else {
                    if (concurrency) return error.ConcurrencyUnavailable;
                    const err, const n = try readFileWindows(o.file, buffer, null);
                    batchComplete(b, operation_userdata, .{ .file_read_streaming = readFileResult(err, n) });
                }
            },
            .file_write_streaming => |o| o: {
                const buffer = windowsWriteBuffer(o.header, o.data, o.splat);
                if (buffer.len == 0) {
                    batchComplete(b, operation_userdata, .{ .file_write_streaming = 0 });
                    break :o;
                }
                if (o.file.flags.nonblocking) {
                    const event = batchEvent(b) orelse {
                        batchComplete(b, operation_userdata, .{ .file_write_streaming = error.SystemResources });
                        break :o;
                    };
                    operation_userdata.init(event, o.file.handle);
                    if (w32.WriteFile(
                        o.file.handle,
                        buffer.ptr,
                        @intCast(buffer.len),
                        null,
                        &operation_userdata.overlapped,
                    ) == 0) switch (getLastError()) {
                        .ERROR_IO_PENDING => {},
                        else => |err| batchComplete(b, operation_userdata, .{ .file_write_streaming = writeFileResult(err, 0) }),
                    };
                } else {
                    if (concurrency) return error.ConcurrencyUnavailable;
                    const err, const n = try writeFileWindows(o.file, buffer, null);
                    batchComplete(b, operation_userdata, .{ .file_write_streaming = writeFileResult(err, n) });
                }
            },
            .device_io_control => |*o| {
                // TODO integrate with overlapped I/O to avoid this error
                if (concurrency) return error.ConcurrencyUnavailable;
                batchComplete(b, operation_userdata, .{ .device_io_control = try deviceIoControl(o) });
            },
            .net_receive => |*o| o: {
                ensureWinsock(w) catch |err| {
                    batchComplete(b, operation_userdata, .{ .net_receive = .{ err, 0 } });
                    break :o;
                };
                var bufs: [1]w32.WSABUF = .{.{
                    .buf = @ptrCast(o.data_buffer.ptr),
                    .len = std.math.cast(u32, o.data_buffer.len) orelse {
                        batchComplete(b, operation_userdata, .{ .net_receive = .{ error.MessageOversize, 0 } });
                        break :o;
                    },
                }};
                const event = batchEvent(b) orelse {
                    batchComplete(b, operation_userdata, .{ .net_receive = .{ error.SystemResources, 0 } });
                    break :o;
                };
                const message = &o.message_buffer[0];
                const scratch = ReceiveScratch.of(message);
                scratch.* = .{ .from = undefined, .from_len = @sizeOf(PosixAddress), .flags = receiveFlags(o.flags) };
                operation_userdata.init(event, o.socket_handle);
                operation_userdata.a = @intFromPtr(message);
                operation_userdata.b = @intFromPtr(o.data_buffer.ptr);
                if (w32.WSARecvFrom(
                    toSocket(o.socket_handle),
                    &bufs,
                    bufs.len,
                    null,
                    &scratch.flags,
                    @ptrCast(&scratch.from),
                    &scratch.from_len,
                    &operation_userdata.overlapped,
                    null,
                ) != 0) switch (wsaGetLastError()) {
                    ._IO_PENDING => {},
                    else => |err| batchComplete(b, operation_userdata, .{ .net_receive = .{ receiveError(err), 0 } }),
                };
            },
            .net_read => |*o| o: {
                var bufs: [max_iovecs_len]w32.WSABUF = undefined;
                var len: u32 = 0;
                for (o.data) |buf| addWsaBuf(&bufs, &len, buf);
                if (len == 0) {
                    batchComplete(b, operation_userdata, .{ .net_read = .{ .data_len = 0 } });
                    break :o;
                }
                const event = batchEvent(b) orelse {
                    batchComplete(b, operation_userdata, .{ .net_read = error.SystemResources });
                    break :o;
                };
                operation_userdata.init(event, o.socket_handle);
                operation_userdata.a = 0; // flags
                const flags: *u32 = @ptrCast(&operation_userdata.a);
                if (w32.WSARecv(
                    toSocket(o.socket_handle),
                    &bufs,
                    len,
                    null,
                    flags,
                    &operation_userdata.overlapped,
                    null,
                ) != 0) switch (wsaGetLastError()) {
                    ._IO_PENDING => {},
                    else => |err| batchComplete(b, operation_userdata, .{ .net_read = readError(err) }),
                };
            },
            // Sending rarely blocks for long, so it is done before returning.
            .net_send, .net_write => batchComplete(b, operation_userdata, try operate(userdata, submission.operation)),
        }
        index = submission.node.next;
    }
    b.submitted = .{ .head = .none, .tail = .none };
}

fn batchAwaitAsync(userdata: ?*anyopaque, b: *Io.Batch) Io.Cancelable!void {
    defer batchReleaseEvent(b);
    batchDrainSubmitted(userdata, b, false) catch |err| switch (err) {
        error.ConcurrencyUnavailable => unreachable, // passed concurrency=false
        else => |e| {
            cancelPending(b);
            return e;
        },
    };
    while (batchMustWait(b)) {
        // A canceler interrupts the wait with an APC, so cancelation must be
        // checked after every wakeup, not only before the first wait.
        const alertable_syscall = AlertableSyscall.start() catch |err| {
            cancelPending(b);
            return err;
        };
        _ = w32.WaitForSingleObjectEx(@ptrCast(b.userdata.?), INFINITE, w32.TRUE);
        alertable_syscall.finish();
    }
}

fn batchAwaitConcurrent(userdata: ?*anyopaque, b: *Io.Batch, timeout: Io.Timeout) Io.Batch.AwaitConcurrentError!void {
    const w = fromUserdata(userdata);
    const deadline: ?Io.Clock.Timestamp = timeout.toTimestamp(w.io());
    defer batchReleaseEvent(b);
    batchDrainSubmitted(userdata, b, true) catch |err| {
        cancelPending(b);
        return err;
    };
    while (batchMustWait(b)) {
        const ms: u32 = if (deadline) |d| millisecondsUntil(d) orelse 0 else INFINITE;
        const alertable_syscall = AlertableSyscall.start() catch |err| {
            cancelPending(b);
            return err;
        };
        const rc = w32.WaitForSingleObjectEx(@ptrCast(b.userdata.?), ms, w32.TRUE);
        alertable_syscall.finish();
        if (@backingInt(rc) == WAIT_TIMEOUT) {
            // Although spurious timeouts are OK, when no deadline is passed
            // we must not return `error.Timeout`.
            if (timeout != .none and batchMustWait(b)) {
                cancelPending(b);
                if (b.completed.head == .none) return error.Timeout;
            }
        }
    }
}

/// Cancels the pending operations and waits for them to finish.
///
/// Unlike with poll-based implementations, a pending operation here has the
/// OS writing into the batch storage, and callers such as `Io.operateTimeout`
/// abandon the batch after `error.Timeout` or `error.Canceled` without
/// calling `Batch.cancel`. Canceled operations are dropped from the batch;
/// ones that completed in the meantime remain available via `Batch.next`.
fn cancelPending(b: *Io.Batch) void {
    defer batchReleaseEvent(b);
    if (b.pending.head == .none) return;
    var index = b.pending.head;
    while (index != .none) {
        const pending = &b.storage[index.toIndex()].pending;
        const operation_userdata: *BatchOperationUserdata = .fromErased(&pending.userdata);
        _ = w32.CancelIoEx(operation_userdata.handle, &operation_userdata.overlapped);
        index = pending.node.next;
    }
    const event: w32.HANDLE = @ptrCast(b.userdata.?);
    while (true) {
        _ = w32.ResetEvent(event);
        batchCollect(b);
        if (b.pending.head == .none) break;
        _ = w32.WaitForSingleObjectEx(event, INFINITE, w32.FALSE);
    }
}

fn batchCancel(userdata: ?*anyopaque, b: *Io.Batch) void {
    _ = userdata;
    cancelPending(b);
}

// ---------------------------------------------------------------------------
// Paths
//
// `std.Io.Threaded` opens paths relative to a directory handle with
// `NtCreateFile`. Win32 has no equivalent, so paths are resolved to absolute
// paths: relative paths are appended to the directory's path from
// `GetFinalPathNameByHandleW` (or `GetCurrentDirectoryW` for the cwd), other
// paths go through `GetFullPathNameW`. The result uses the `\\?\` prefix so
// that it may exceed `MAX_PATH` and is not normalized again by Win32.

const windows = std.os.windows;
const Dir = Io.Dir;
const File = Io.File;
const PATH_MAX_WIDE = windows.PATH_MAX_WIDE;

const WindowsPath = struct {
    data: [PATH_MAX_WIDE:0]u16,
    len: usize,

    fn span(p: *const WindowsPath) [:0]const u16 {
        return p.data[0..p.len :0];
    }

    fn set(p: *WindowsPath, parts: []const []const u16) Dir.PathNameError!void {
        var len: usize = 0;
        for (parts) |part| len += part.len;
        if (len > PATH_MAX_WIDE) return error.NameTooLong;
        var i: usize = 0;
        for (parts) |part| {
            @memmove(p.data[i..][0..part.len], part);
            i += part.len;
        }
        p.len = len;
        p.data[len] = 0;
    }
};

const PathError = Dir.PathNameError || error{ FileNotFound, AccessDenied } || Io.UnexpectedError;

const L = std.unicode.wtf8ToWtf16LeStringLiteral;
const verbatim_prefix = L("\\\\?\\");
const verbatim_unc_prefix = L("\\\\?\\UNC\\");

fn wtf8ToWindowsPath(path: []const u8, out: *WindowsPath) Dir.PathNameError!void {
    const len = std.unicode.calcWtf16LeLen(path) catch return error.BadPathName;
    if (len > PATH_MAX_WIDE) return error.NameTooLong;
    out.len = std.unicode.wtf8ToWtf16Le(&out.data, path) catch return error.BadPathName;
    out.data[out.len] = 0;
}

/// Stores the full Win32 path `full` (`C:\foo` or `\\server\share\foo`) with
/// the `\\?\` prefix.
fn setVerbatim(out: *WindowsPath, full: []const u16) Dir.PathNameError!void {
    if (std.mem.startsWith(u16, full, L("\\\\"))) {
        if (std.mem.startsWith(u16, full, L("\\\\?\\")) or std.mem.startsWith(u16, full, L("\\\\.\\"))) {
            return out.set(&.{full});
        }
        return out.set(&.{ verbatim_unc_prefix, full[2..] });
    }
    return out.set(&.{ verbatim_prefix, full });
}

/// Converts a `\\?\` prefixed path back to a regular Win32 path.
fn stripVerbatim(path: []const u16, out: []u16) error{NameTooLong}![]u16 {
    if (std.mem.startsWith(u16, path, verbatim_unc_prefix)) {
        const rest = path[verbatim_unc_prefix.len..];
        if (out.len < rest.len + 2) return error.NameTooLong;
        @memmove(out[2..][0..rest.len], rest);
        out[0] = '\\';
        out[1] = '\\';
        return out[0 .. rest.len + 2];
    }
    const rest = if (std.mem.startsWith(u16, path, verbatim_prefix)) path[verbatim_prefix.len..] else path;
    if (out.len < rest.len) return error.NameTooLong;
    @memmove(out[0..rest.len], rest);
    return out[0..rest.len];
}

fn getFullPathName(path: [:0]const u16, out: *WindowsPath) PathError!void {
    const n = w32.GetFullPathNameW(path.ptr, out.data.len, &out.data, null);
    if (n == 0) switch (getLastError()) {
        .ERROR_INVALID_NAME, .ERROR_BAD_PATHNAME, .ERROR_INVALID_PARAMETER => return error.BadPathName,
        .ERROR_FILENAME_EXCED_RANGE => return error.NameTooLong,
        else => |err| return unexpectedError(err),
    };
    if (n >= out.data.len) return error.NameTooLong;
    out.len = n;
    out.data[n] = 0;
}

/// Stores the `\\?\` prefixed path of the directory `dir` in `out`.
fn dirPath(dir: Dir, out: *WindowsPath) PathError!void {
    if (dir.handle == Dir.cwd().handle) {
        var cwd: WindowsPath = undefined;
        const n = w32.GetCurrentDirectoryW(cwd.data.len, &cwd.data);
        if (n == 0) return unexpectedError(getLastError());
        if (n >= cwd.data.len) return error.NameTooLong;
        return setVerbatim(out, cwd.data[0..n]);
    }
    const n = w32.GetFinalPathNameByHandleW(dir.handle, &out.data, out.data.len, .NORMALIZED);
    if (n == 0) switch (getLastError()) {
        .ERROR_FILE_NOT_FOUND, .ERROR_PATH_NOT_FOUND => return error.FileNotFound,
        .ERROR_ACCESS_DENIED => return error.AccessDenied,
        .ERROR_NOT_ENOUGH_MEMORY => return error.NameTooLong,
        else => |err| return unexpectedError(err),
    };
    if (n >= out.data.len) return error.NameTooLong;
    out.len = n;
    out.data[n] = 0;
}

/// Converts `sub_path` (WTF-8), relative to `dir` unless absolute, to a path
/// suitable for Win32 file functions.
fn toWindowsPath(dir: Dir, sub_path: []const u8, out: *WindowsPath) PathError!void {
    var path: WindowsPath = undefined;
    try wtf8ToWindowsPath(sub_path, &path);
    return resolveWindowsPath(dir, path.span(), out);
}

fn resolveWindowsPath(dir: Dir, path: [:0]const u16, out: *WindowsPath) PathError!void {
    // `\??\` is the NT namespace equivalent of `\\?\`.
    if (windows.hasCommonNtPrefix(u16, path)) return out.set(&.{ verbatim_prefix, path[4..] });
    switch (Dir.path.getWin32PathType(u16, path)) {
        .relative => {
            try dirPath(dir, out);
            const base_len = out.len;
            const sep_len: usize = if (out.data[base_len - 1] == '\\') 0 else 1;
            if (base_len + sep_len + path.len > PATH_MAX_WIDE) return error.NameTooLong;
            out.data[base_len] = '\\';
            @memcpy(out.data[base_len + sep_len ..][0..path.len], path);
            const rel = out.data[base_len + sep_len ..][0..path.len];
            if (windows.normalizePath(u16, rel)) |rel_len| {
                out.len = if (rel_len == 0) base_len else base_len + sep_len + rel_len;
                out.data[out.len] = 0;
                return;
            } else |err| switch (err) {
                // Let `GetFullPathNameW` resolve the `..` components that go
                // above `dir`.
                error.TooManyParentDirs => {
                    var joined: WindowsPath = undefined;
                    const base = stripVerbatim(out.data[0..base_len], &joined.data) catch return error.NameTooLong;
                    try joined.set(&.{ base, L("\\"), path });
                    var full: WindowsPath = undefined;
                    try getFullPathName(joined.span(), &full);
                    return setVerbatim(out, full.data[0..full.len]);
                },
            }
        },
        .local_device => {
            if (std.mem.startsWith(u16, path, verbatim_prefix)) return out.set(&.{path});
            return getFullPathName(path, out);
        },
        .root_local_device => return out.set(&.{path}),
        .drive_absolute, .drive_relative, .rooted, .unc_absolute => {
            var full: WindowsPath = undefined;
            try getFullPathName(path, &full);
            return setVerbatim(out, full.data[0..full.len]);
        },
    }
}

// ---------------------------------------------------------------------------
// Opening files and directories

const GENERIC_READ: u32 = 0x80000000;
const GENERIC_WRITE: u32 = 0x40000000;
const DELETE: u32 = 0x00010000;
const READ_CONTROL: u32 = 0x00020000;
const SYNCHRONIZE: u32 = 0x00100000;
const FILE_LIST_DIRECTORY: u32 = 0x0001;
const FILE_READ_EA: u32 = 0x0008;
const FILE_TRAVERSE: u32 = 0x0020;
const FILE_READ_ATTRIBUTES: u32 = 0x0080;
const FILE_WRITE_ATTRIBUTES: u32 = 0x0100;

const FILE_SHARE_ALL: u32 = 0x1 | 0x2 | 0x4; // read, write, delete

const FILE_ATTRIBUTE_READONLY: u32 = 0x1;
const FILE_ATTRIBUTE_DIRECTORY: u32 = 0x10;
const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;
const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
const INVALID_FILE_ATTRIBUTES: u32 = 0xFFFFFFFF;
const FILE_FLAG_BACKUP_SEMANTICS: u32 = 0x02000000;
const FILE_FLAG_OPEN_REPARSE_POINT: u32 = 0x00200000;

const FILE_TYPE_PIPE: u32 = 3;

/// There are multiple kernel bugs being worked around with retries.
const max_windows_kernel_bug_retries = 13;

fn isInvalidHandle(handle: w32.HANDLE) bool {
    return @intFromPtr(handle) == std.math.maxInt(usize);
}

const OpenFilter = enum {
    /// Fail with `error.IsDir` if the path is a directory.
    file_only,
    /// Fail with `error.NotDir` if the path is not a directory.
    dir_only,
    any,
};

const CreateFileOptions = struct {
    access: u32,
    share: u32 = FILE_SHARE_ALL,
    creation: w32.FILE_CREATION_DISPOSITION,
    attributes: u32 = FILE_ATTRIBUTE_NORMAL,
    follow_symlinks: bool = true,
    filter: OpenFilter = .any,
};

fn sleepForRetry(attempt: u5) Io.Cancelable!void {
    try sleepInternal(.{ .duration = .{
        .raw = .fromMilliseconds((@as(u32, 1) << attempt) >> 1),
        .clock = .awake,
    } });
}

/// Equivalent of `NtCreateFile` with a path from `toWindowsPath`. Directories
/// can always be opened (`FILE_FLAG_BACKUP_SEMANTICS`), so `filter` is
/// enforced by checking the attributes of the opened handle.
fn createFile(path: [:0]const u16, options: CreateFileOptions) File.OpenError!w32.HANDLE {
    var flags = options.attributes | FILE_FLAG_BACKUP_SEMANTICS;
    if (!options.follow_symlinks) flags |= FILE_FLAG_OPEN_REPARSE_POINT;
    const access = options.access | if (options.filter != .any) FILE_READ_ATTRIBUTES else 0;

    var attempt: u5 = 0;
    var syscall: Syscall = try .start();
    const handle = while (true) {
        const handle = w32.CreateFileW(path.ptr, @bitCast(access), @bitCast(options.share), null, options.creation, @bitCast(flags), null);
        if (!isInvalidHandle(handle)) {
            syscall.finish();
            break handle;
        }
        switch (getLastError()) {
            .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
            .ERROR_SHARING_VIOLATION => {
                // This occurs if the file attempting to be opened is a running
                // executable. However, there's a kernel bug: the error may be
                // incorrectly returned for an indeterminate amount of time
                // after an executable file is closed. Here we work around the
                // kernel bug with retry attempts.
                syscall.finish();
                if (max_windows_kernel_bug_retries - attempt == 0) return error.FileBusy;
                try sleepForRetry(attempt);
                attempt += 1;
                syscall = try .start();
            },
            .ERROR_ACCESS_DENIED => {
                syscall.finish();
                // Creating or truncating a directory fails this way; report it
                // like `NtCreateFile` with `FILE_NON_DIRECTORY_FILE` does.
                if (options.filter == .file_only and isDirectoryPath(path)) return error.IsDir;
                return error.AccessDenied;
            },
            .ERROR_FILE_NOT_FOUND, .ERROR_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
            .ERROR_INVALID_NAME, .ERROR_BAD_PATHNAME => return syscall.fail(error.BadPathName),
            .ERROR_FILENAME_EXCED_RANGE => return syscall.fail(error.NameTooLong),
            .ERROR_DIRECTORY => return syscall.fail(error.NotDir),
            .ERROR_BAD_NETPATH, .ERROR_BAD_NET_NAME => return syscall.fail(error.NetworkNotFound),
            .ERROR_NOT_READY => return syscall.fail(error.NoDevice),
            .ERROR_PIPE_BUSY => return syscall.fail(error.PipeBusy),
            .ERROR_FILE_EXISTS, .ERROR_ALREADY_EXISTS => {
                syscall.finish();
                // `NtCreateFile` with `FILE_NON_DIRECTORY_FILE` checks for a
                // directory before checking for a collision.
                if (options.filter == .file_only and isDirectoryPath(path)) return error.IsDir;
                return error.PathAlreadyExists;
            },
            .ERROR_USER_MAPPED_FILE => return syscall.fail(error.AccessDenied),
            .ERROR_VIRUS_INFECTED, .ERROR_VIRUS_DELETED => return syscall.fail(error.AntivirusInterference),
            .ERROR_DISK_FULL, .ERROR_HANDLE_DISK_FULL => return syscall.fail(error.NoSpaceLeft),
            .ERROR_CANT_RESOLVE_FILENAME => return syscall.fail(error.SymLinkLoop),
            .ERROR_TOO_MANY_OPEN_FILES => return syscall.fail(error.ProcessFdQuotaExceeded),
            .ERROR_NOT_ENOUGH_MEMORY, .ERROR_NO_SYSTEM_RESOURCES => return syscall.fail(error.SystemResources),
            .ERROR_WRITE_PROTECT => return syscall.fail(error.ReadOnlyFileSystem),
            .ERROR_INVALID_PARAMETER => |err| return syscall.errorBug(err),
            else => |err| return syscall.unexpectedError(err),
        }
    };
    errdefer _ = w32.CloseHandle(handle);

    if (options.filter != .any) {
        var info: FILE_BASIC_INFO = undefined;
        if (w32.GetFileInformationByHandleEx(handle, .FileBasicInfo, &info, @sizeOf(FILE_BASIC_INFO)) == 0) {
            return unexpectedError(getLastError());
        }
        const is_dir = info.FileAttributes & FILE_ATTRIBUTE_DIRECTORY != 0;
        switch (options.filter) {
            .file_only => if (is_dir) return error.IsDir,
            .dir_only => if (!is_dir) return error.NotDir,
            .any => unreachable,
        }
    }
    return handle;
}

fn isDirectoryPath(path: [:0]const u16) bool {
    const attributes = w32.GetFileAttributesW(path.ptr);
    return attributes != INVALID_FILE_ATTRIBUTES and attributes & FILE_ATTRIBUTE_DIRECTORY != 0;
}

const FILE_BASIC_INFO = extern struct {
    CreationTime: i64,
    LastAccessTime: i64,
    LastWriteTime: i64,
    ChangeTime: i64,
    FileAttributes: u32,
};

const FILE_DISPOSITION_INFO = extern struct {
    DeleteFile: u8,
};

const FILE_DISPOSITION_INFO_EX = extern struct {
    Flags: u32,
};
const FILE_DISPOSITION_FLAG_DELETE: u32 = 0x1;
const FILE_DISPOSITION_FLAG_POSIX_SEMANTICS: u32 = 0x2;
const FILE_DISPOSITION_FLAG_IGNORE_READONLY_ATTRIBUTE: u32 = 0x10;

const FILE_END_OF_FILE_INFO = extern struct {
    EndOfFile: i64,
};

/// Locks byte 0 of the file, like `std.Io.Threaded` does with `NtLockFile`.
/// Locks the first byte of the file. Waiting for the lock is done by polling,
/// since a blocking `LockFileEx` cannot be canceled under Wine: it waits in a
/// non-alertable `NtWaitForSingleObject`, which `CancelSynchronousIo` does not
/// interrupt (and Wine does not implement lock waits on overlapped handles).
fn lockFileRange(handle: w32.HANDLE, exclusive: bool, fail_immediately: bool) (Io.Cancelable || Io.UnexpectedError || error{ SystemResources, WouldBlock })!void {
    const max_delay_ms = 16;
    var delay_ms: i64 = 1;
    while (true) {
        if (tryLockFileRange(handle, exclusive)) |_| {
            return;
        } else |err| switch (err) {
            error.WouldBlock => if (fail_immediately) return err,
            else => |e| return e,
        }
        try sleepInternal(.{ .duration = .{ .raw = .fromMilliseconds(delay_ms), .clock = .awake } });
        delay_ms = @min(delay_ms * 2, max_delay_ms);
    }
}

fn tryLockFileRange(handle: w32.HANDLE, exclusive: bool) (Io.UnexpectedError || error{ SystemResources, WouldBlock })!void {
    var flags: u32 = 0x1; // LOCKFILE_FAIL_IMMEDIATELY
    if (exclusive) flags |= 0x2; // LOCKFILE_EXCLUSIVE_LOCK
    var overlapped = OverlappedOperation.init(0).overlapped;
    if (w32.LockFileEx(handle, @bitCast(flags), 0, 1, 0, &overlapped) != 0) return;
    return switch (getLastError()) {
        .ERROR_LOCK_VIOLATION, .ERROR_LOCK_FAILED => error.WouldBlock,
        .ERROR_NOT_ENOUGH_MEMORY, .ERROR_NO_SYSTEM_RESOURCES => error.SystemResources,
        else => |err| unexpectedError(err),
    };
}

/// Returns whether the range was locked.
fn unlockFileRange(handle: w32.HANDLE) Io.UnexpectedError!bool {
    var overlapped = OverlappedOperation.init(0).overlapped;
    if (w32.UnlockFileEx(handle, 0, 1, 0, &overlapped) != 0) return true;
    return switch (getLastError()) {
        .ERROR_NOT_LOCKED => false,
        else => |err| unexpectedError(err),
    };
}

fn lockOpenedFile(handle: w32.HANDLE, lock: File.Lock, nonblocking: bool) File.OpenError!void {
    const exclusive = switch (lock) {
        .none => return,
        .shared => false,
        .exclusive => true,
    };
    return lockFileRange(handle, exclusive, nonblocking);
}

fn dirOpenFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, flags: Dir.OpenFileOptions) File.OpenError!File {
    _ = userdata;
    const allow_directory = flags.allow_directory and !flags.isWrite();
    if (!allow_directory and (std.mem.eql(u8, sub_path, ".") or std.mem.eql(u8, sub_path, ".."))) return error.IsDir;
    var path: WindowsPath = undefined;
    try toWindowsPath(dir, sub_path, &path);
    return openFileWindows(path.span(), flags);
}

fn openFileWindows(path: [:0]const u16, flags: Dir.OpenFileOptions) File.OpenError!File {
    const allow_directory = flags.allow_directory and !flags.isWrite();
    var access: u32 = SYNCHRONIZE;
    if (flags.isRead()) access |= GENERIC_READ;
    if (flags.isWrite()) access |= GENERIC_WRITE;
    const handle = try createFile(path, .{
        .access = access,
        .creation = .OPEN_EXISTING,
        .follow_symlinks = flags.follow_symlinks,
        .filter = if (allow_directory) .any else .file_only,
    });
    errdefer _ = w32.CloseHandle(handle);
    try lockOpenedFile(handle, flags.lock, flags.lock_nonblocking);
    return .{ .handle = handle, .flags = .{ .nonblocking = false } };
}

fn dirCreateFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, flags: Dir.CreateFileOptions) File.OpenError!File {
    _ = userdata;
    if (std.mem.eql(u8, sub_path, ".") or std.mem.eql(u8, sub_path, "..")) return error.IsDir;
    var path: WindowsPath = undefined;
    try toWindowsPath(dir, sub_path, &path);
    var access: u32 = SYNCHRONIZE | GENERIC_WRITE;
    if (flags.read) access |= GENERIC_READ;
    const handle = try createFile(path.span(), .{
        .access = access,
        .creation = if (flags.exclusive) .CREATE_NEW else if (flags.truncate) .CREATE_ALWAYS else .OPEN_ALWAYS,
        .filter = .file_only,
    });
    errdefer _ = w32.CloseHandle(handle);
    try lockOpenedFile(handle, flags.lock, flags.lock_nonblocking);
    return .{ .handle = handle, .flags = .{ .nonblocking = false } };
}

fn openDirWindows(path: [:0]const u16, options: Dir.OpenOptions) Dir.OpenError!Dir {
    var access: u32 = FILE_READ_EA | FILE_TRAVERSE | FILE_READ_ATTRIBUTES | READ_CONTROL | SYNCHRONIZE;
    if (options.iterate) access |= FILE_LIST_DIRECTORY;
    const handle = createFile(path, .{
        .access = access,
        .creation = .OPEN_EXISTING,
        .follow_symlinks = options.follow_symlinks,
        .filter = .dir_only,
    }) catch |err| switch (err) {
        error.FileNotFound,
        error.NotDir,
        error.AccessDenied,
        error.SymLinkLoop,
        error.ProcessFdQuotaExceeded,
        error.NoDevice,
        error.SystemResources,
        error.NetworkNotFound,
        error.NameTooLong,
        error.BadPathName,
        error.Canceled,
        error.Unexpected,
        => |e| return e,
        error.FileBusy, error.PipeBusy => return error.AccessDenied,
        else => return error.Unexpected,
    };
    return .{ .handle = handle };
}

fn dirOpenDir(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, options: Dir.OpenOptions) Dir.OpenError!Dir {
    _ = userdata;
    var path: WindowsPath = undefined;
    try toWindowsPath(dir, sub_path, &path);
    return openDirWindows(path.span(), options);
}

fn dirClose(userdata: ?*anyopaque, dirs: []const Dir) void {
    _ = userdata;
    for (dirs) |dir| _ = w32.CloseHandle(dir.handle);
}

fn dirCreateDir(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, permissions: Dir.Permissions) Dir.CreateDirError!void {
    _ = userdata;
    _ = permissions; // TODO use this value
    var path: WindowsPath = undefined;
    try toWindowsPath(dir, sub_path, &path);
    const syscall: Syscall = try .start();
    while (true) {
        if (w32.CreateDirectoryW(path.span().ptr, null) != 0) return syscall.finish();
        switch (getLastError()) {
            .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
            .ERROR_ALREADY_EXISTS, .ERROR_FILE_EXISTS => return syscall.fail(error.PathAlreadyExists),
            .ERROR_FILE_NOT_FOUND, .ERROR_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
            .ERROR_ACCESS_DENIED, .ERROR_USER_MAPPED_FILE => return syscall.fail(error.AccessDenied),
            .ERROR_INVALID_NAME, .ERROR_BAD_PATHNAME => return syscall.fail(error.BadPathName),
            .ERROR_FILENAME_EXCED_RANGE => return syscall.fail(error.NameTooLong),
            .ERROR_DIRECTORY => return syscall.fail(error.NotDir),
            .ERROR_BAD_NETPATH, .ERROR_BAD_NET_NAME => return syscall.fail(error.NetworkNotFound),
            .ERROR_DISK_FULL, .ERROR_HANDLE_DISK_FULL => return syscall.fail(error.NoSpaceLeft),
            .ERROR_WRITE_PROTECT => return syscall.fail(error.ReadOnlyFileSystem),
            .ERROR_NOT_READY => return syscall.fail(error.NoDevice),
            else => |err| return syscall.unexpectedError(err),
        }
    }
}

fn dirCreateDirPath(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    permissions: Dir.Permissions,
) Dir.CreateDirPathError!Dir.CreatePathStatus {
    var it = Dir.path.componentIterator(sub_path);
    var status: Dir.CreatePathStatus = .existed;
    var component = it.last() orelse return error.BadPathName;
    while (true) {
        if (dirCreateDir(userdata, dir, component.path, permissions)) |_| {
            status = .created;
        } else |err| switch (err) {
            error.PathAlreadyExists => {
                // It is important to return an error if it's not a directory
                // because otherwise a dangling symlink could cause an infinite
                // loop.
                const stat = try dirStatFile(userdata, dir, component.path, .{ .follow_symlinks = false });
                if (stat.kind != .directory) return error.NotDir;
            },
            error.FileNotFound => |e| {
                component = it.previous() orelse return e;
                continue;
            },
            else => |e| return e,
        }
        component = it.next() orelse return status;
    }
}

fn dirCreateDirPathOpen(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    permissions: Dir.Permissions,
    options: Dir.OpenOptions,
) Dir.CreateDirPathOpenError!Dir {
    return dirOpenDir(userdata, dir, sub_path, options) catch |err| switch (err) {
        error.FileNotFound => {
            _ = try dirCreateDirPath(userdata, dir, sub_path, permissions);
            return dirOpenDir(userdata, dir, sub_path, options);
        },
        else => |e| return e,
    };
}

// ---------------------------------------------------------------------------
// Metadata

fn fileStatWindows(handle: w32.HANDLE) File.StatError!File.Stat {
    var info: w32.BY_HANDLE_FILE_INFORMATION = undefined;
    var basic: FILE_BASIC_INFO = undefined;
    {
        const syscall: Syscall = try .start();
        while (w32.GetFileInformationByHandle(handle, &info) == 0) switch (getLastError()) {
            .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
            .ERROR_ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            .ERROR_INVALID_FUNCTION => return syscall.fail(error.Streaming),
            else => |err| return syscall.unexpectedError(err),
        };
        while (w32.GetFileInformationByHandleEx(handle, .FileBasicInfo, &basic, @sizeOf(FILE_BASIC_INFO)) == 0) switch (getLastError()) {
            .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
            .ERROR_ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            else => |err| return syscall.unexpectedError(err),
        };
        syscall.finish();
    }
    const kind: File.Kind = if (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT != 0) kind: {
        var tag_info: w32.FILE_ATTRIBUTE_TAG_INFO = undefined;
        const syscall: Syscall = try .start();
        while (w32.GetFileInformationByHandleEx(handle, .FileAttributeTagInfo, &tag_info, @sizeOf(w32.FILE_ATTRIBUTE_TAG_INFO)) == 0) switch (getLastError()) {
            .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
            .ERROR_ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            else => |err| return syscall.unexpectedError(err),
        };
        syscall.finish();
        const is_surrogate = tag_info.ReparseTag & 0x20000000 != 0;
        break :kind if (is_surrogate) .sym_link else .unknown;
    } else if (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY != 0)
        .directory
    else
        .file;

    var system_info: w32.SYSTEM_INFO = undefined;
    w32.GetSystemInfo(&system_info);

    return .{
        .inode = @bitCast((@as(u64, info.nFileIndexHigh) << 32) | info.nFileIndexLow),
        .size = (@as(u64, info.nFileSizeHigh) << 32) | info.nFileSizeLow,
        .permissions = .default_file,
        .kind = kind,
        .atime = windows.fromSysTime(basic.LastAccessTime),
        .mtime = windows.fromSysTime(basic.LastWriteTime),
        .ctime = windows.fromSysTime(basic.ChangeTime),
        .nlink = info.nNumberOfLinks,
        .block_size = @max(system_info.dwPageSize, system_info.dwAllocationGranularity),
    };
}

fn fileStat(userdata: ?*anyopaque, file: File) File.StatError!File.Stat {
    _ = userdata;
    return fileStatWindows(file.handle);
}

fn dirStat(userdata: ?*anyopaque, dir: Dir) Dir.StatError!Dir.Stat {
    _ = userdata;
    return fileStatWindows(dir.handle);
}

fn fileLength(userdata: ?*anyopaque, file: File) File.LengthError!u64 {
    _ = userdata;
    var size: w32.LARGE_INTEGER = undefined;
    const syscall: Syscall = try .start();
    while (w32.GetFileSizeEx(file.handle, &size) == 0) switch (getLastError()) {
        .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
        .ERROR_ACCESS_DENIED => return syscall.fail(error.AccessDenied),
        .ERROR_INVALID_FUNCTION => return syscall.fail(error.Streaming),
        else => |err| return syscall.unexpectedError(err),
    };
    syscall.finish();
    return @bitCast(size.QuadPart);
}

fn dirStatFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, options: Dir.StatFileOptions) Dir.StatFileError!File.Stat {
    _ = userdata;
    var path: WindowsPath = undefined;
    try toWindowsPath(dir, sub_path, &path);
    const handle = try createFile(path.span(), .{
        .access = FILE_READ_ATTRIBUTES | SYNCHRONIZE,
        .creation = .OPEN_EXISTING,
        .follow_symlinks = options.follow_symlinks,
    });
    defer _ = w32.CloseHandle(handle);
    return fileStatWindows(handle);
}

fn dirAccess(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, options: Dir.AccessOptions) Dir.AccessError!void {
    _ = userdata;
    _ = options; // TODO
    if (std.mem.eql(u8, sub_path, ".") or std.mem.eql(u8, sub_path, "..")) return;
    var path: WindowsPath = undefined;
    try toWindowsPath(dir, sub_path, &path);
    const syscall: Syscall = try .start();
    while (w32.GetFileAttributesW(path.span().ptr) == INVALID_FILE_ATTRIBUTES) switch (getLastError()) {
        .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
        .ERROR_FILE_NOT_FOUND, .ERROR_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
        .ERROR_ACCESS_DENIED => return syscall.fail(error.AccessDenied),
        .ERROR_INVALID_NAME, .ERROR_BAD_PATHNAME, .ERROR_DIRECTORY => return syscall.fail(error.BadPathName),
        .ERROR_FILENAME_EXCED_RANGE => return syscall.fail(error.NameTooLong),
        .ERROR_SHARING_VIOLATION => return syscall.fail(error.FileBusy),
        else => |err| return syscall.unexpectedError(err),
    };
    syscall.finish();
}

fn dirRead(userdata: ?*anyopaque, dr: *Dir.Reader, buffer: []Dir.Entry) Dir.Reader.Error!usize {
    _ = userdata;
    // See `std.Io.Threaded.dirReadWindows` for how `dr.buffer` is shared between
    // the directory records and the WTF-8 names returned in `Dir.Entry.name`:
    // enough space is reserved at the start so that a name never overwrites
    // records that have not been processed yet.
    const Info = w32.FILE_ID_BOTH_DIR_INFO;
    const max_info_len = @sizeOf(Info) + windows.NAME_MAX * 2;
    const info_align = @alignOf(Info);
    const reserve_needed = comptime std.mem.alignForward(usize, Dir.max_name_bytes, info_align) - max_info_len;
    const unreserved_start = comptime std.mem.alignForward(usize, reserve_needed, info_align);
    const unreserved_buffer = dr.buffer[unreserved_start..];
    // `Dir.Reader.min_buffer_len` is computed for `std.os.windows.FILE_BOTH_DIR_INFORMATION`.
    comptime assert(Dir.Reader.min_buffer_len - unreserved_start >= max_info_len);

    var name_index: usize = 0;
    var buffer_index: usize = 0;
    while (buffer.len - buffer_index != 0) {
        if (dr.end - dr.index == 0) {
            // Refill the buffer, unless we've already created references to
            // buffered data.
            if (buffer_index != 0) break;
            if (dr.state == .finished) return 0;

            const class: w32.FILE_INFO_BY_HANDLE_CLASS = if (dr.state == .reset) .FileIdBothDirectoryRestartInfo else .FileIdBothDirectoryInfo;
            const syscall: Syscall = try .start();
            while (w32.GetFileInformationByHandleEx(
                dr.dir.handle,
                class,
                unreserved_buffer.ptr,
                std.math.lossyCast(u32, unreserved_buffer.len),
            ) == 0) switch (getLastError()) {
                .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
                .ERROR_NO_MORE_FILES => {
                    syscall.finish();
                    dr.state = .finished;
                    return 0;
                },
                .ERROR_ACCESS_DENIED => return syscall.fail(error.AccessDenied), // Double-check that the Dir was opened with iteration ability
                else => |err| return syscall.unexpectedError(err),
            };
            syscall.finish();
            dr.state = .reading;
            dr.index = 0;
            // The records are chained by `NextEntryOffset`; the last one has 0.
            var end: usize = 0;
            while (true) {
                const info: *align(2) const Info = @ptrCast(@alignCast(&unreserved_buffer[end]));
                if (info.NextEntryOffset == 0) {
                    end += @offsetOf(Info, "FileName") + info.FileNameLength;
                    break;
                }
                end += info.NextEntryOffset;
            }
            dr.end = end;
        }

        const dir_info: *align(2) const Info = @ptrCast(@alignCast(&unreserved_buffer[dr.index]));
        const backtrack_index = dr.index;
        if (dir_info.NextEntryOffset != 0) {
            dr.index += dir_info.NextEntryOffset;
        } else {
            dr.index = dr.end;
        }

        const name_wtf16le = @as([*]const u16, @ptrCast(&dir_info.FileName))[0 .. dir_info.FileNameLength / 2];

        if (std.mem.eql(u16, name_wtf16le, &[_]u16{'.'}) or std.mem.eql(u16, name_wtf16le, &[_]u16{ '.', '.' })) {
            continue;
        }

        // Read any relevant information from `dir_info` now since it's possible the WTF-8
        // name will overwrite it.
        const kind: File.Kind = blk: {
            const attrs = dir_info.FileAttributes;
            if (attrs & FILE_ATTRIBUTE_REPARSE_POINT != 0) break :blk .sym_link;
            if (attrs & FILE_ATTRIBUTE_DIRECTORY != 0) break :blk .directory;
            break :blk .file;
        };
        const inode: File.INode = @bitCast(dir_info.FileId.QuadPart);

        // If there's no more space for WTF-8 names without bleeding over into
        // the remaining unprocessed entries, then backtrack and return what we have so far.
        if (name_index + std.unicode.calcWtf8Len(name_wtf16le) > unreserved_start + dr.index) {
            // We should always be able to fit at least one entry into the buffer no matter what
            assert(buffer_index != 0);
            dr.index = backtrack_index;
            break;
        }

        const name_buf = dr.buffer[name_index..];
        const name_wtf8_len = std.unicode.wtf16LeToWtf8(name_buf, name_wtf16le);
        const name_wtf8 = name_buf[0..name_wtf8_len];
        name_index += name_wtf8_len;

        buffer[buffer_index] = .{
            .name = name_wtf8,
            .kind = kind,
            .inode = inode,
        };
        buffer_index += 1;
    }

    return buffer_index;
}

// ---------------------------------------------------------------------------
// Real paths

/// Writes the path of `handle` as WTF-8 into `out_buffer`.
fn realPathWindows(handle: w32.HANDLE, out_buffer: []u8) File.RealPathError!usize {
    var path: WindowsPath = undefined;
    const syscall: Syscall = try .start();
    const n = while (true) {
        const n = w32.GetFinalPathNameByHandleW(handle, &path.data, path.data.len, .NORMALIZED);
        if (n != 0) break n;
        switch (getLastError()) {
            .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
            .ERROR_FILE_NOT_FOUND, .ERROR_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
            .ERROR_ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            .ERROR_NOT_ENOUGH_MEMORY => return syscall.fail(error.NameTooLong),
            .ERROR_UNRECOGNIZED_VOLUME => return syscall.fail(error.UnrecognizedVolume),
            else => |err| return syscall.unexpectedError(err),
        }
    };
    syscall.finish();
    if (n >= path.data.len) return error.NameTooLong;
    const wide = stripVerbatim(path.data[0..n], &path.data) catch unreachable; // only gets shorter
    const len = std.unicode.calcWtf8Len(wide);
    if (len > out_buffer.len) return error.NameTooLong;
    return std.unicode.wtf16LeToWtf8(out_buffer, wide);
}

fn dirRealPath(userdata: ?*anyopaque, dir: Dir, out_buffer: []u8) Dir.RealPathError!usize {
    _ = userdata;
    return realPathWindows(dir.handle, out_buffer);
}

fn fileRealPath(userdata: ?*anyopaque, file: File, out_buffer: []u8) File.RealPathError!usize {
    _ = userdata;
    return realPathWindows(file.handle, out_buffer);
}

fn dirRealPathFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, out_buffer: []u8) Dir.RealPathFileError!usize {
    _ = userdata;
    var path: WindowsPath = undefined;
    try toWindowsPath(dir, sub_path, &path);
    const handle = createFile(path.span(), .{
        .access = FILE_READ_ATTRIBUTES | SYNCHRONIZE,
        .creation = .OPEN_EXISTING,
    }) catch |err| switch (err) {
        error.WouldBlock, error.FileLocksUnsupported => unreachable,
        error.ReadOnlyFileSystem => return error.Unexpected,
        else => |e| return e,
    };
    defer _ = w32.CloseHandle(handle);
    return realPathWindows(handle, out_buffer);
}

// ---------------------------------------------------------------------------
// Deleting and renaming

fn dirDeleteWindows(dir: Dir, sub_path: []const u8, remove_dir: bool) (Dir.DeleteDirError || Dir.DeleteFileError)!void {
    if (std.mem.eql(u8, sub_path, "..")) {
        // Can't remove the parent directory with an open handle.
        return error.FileBusy;
    }
    var path: WindowsPath = undefined;
    try toWindowsPath(dir, sub_path, &path);
    const handle = createFile(path.span(), .{
        .access = DELETE | SYNCHRONIZE,
        .creation = .OPEN_EXISTING,
        .follow_symlinks = false, // would we ever want to delete the target instead?
        .filter = if (remove_dir) .dir_only else .file_only,
    }) catch |err| switch (err) {
        error.FileNotFound,
        error.AccessDenied,
        error.FileBusy,
        error.IsDir,
        error.NotDir,
        error.SymLinkLoop,
        error.SystemResources,
        error.ReadOnlyFileSystem,
        error.NetworkNotFound,
        error.NameTooLong,
        error.BadPathName,
        error.Canceled,
        error.Unexpected,
        => |e| return e,
        error.PipeBusy, error.AntivirusInterference => return error.AccessDenied,
        else => return error.Unexpected,
    };
    defer _ = w32.CloseHandle(handle);

    // FileDispositionInfoEx requires Windows 10 1607 and a file system that
    // supports it, so fall back to FileDispositionInfo if it is rejected.
    const syscall: Syscall = try .start();
    var info_ex: FILE_DISPOSITION_INFO_EX = .{ .Flags = FILE_DISPOSITION_FLAG_DELETE |
        FILE_DISPOSITION_FLAG_POSIX_SEMANTICS |
        FILE_DISPOSITION_FLAG_IGNORE_READONLY_ATTRIBUTE };
    const err: w32.WIN32_ERROR = err: while (true) {
        if (w32.SetFileInformationByHandle(handle, .FileDispositionInfoEx, &info_ex, @sizeOf(FILE_DISPOSITION_INFO_EX)) != 0) {
            return syscall.finish();
        }
        switch (getLastError()) {
            .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
            .ERROR_INVALID_PARAMETER, .ERROR_INVALID_FUNCTION, .ERROR_NOT_SUPPORTED => break :err fallback: {
                var info: FILE_DISPOSITION_INFO = .{ .DeleteFile = 1 };
                while (true) {
                    if (w32.SetFileInformationByHandle(handle, .FileDispositionInfo, &info, @sizeOf(FILE_DISPOSITION_INFO)) != 0) {
                        return syscall.finish();
                    }
                    switch (getLastError()) {
                        .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
                        else => |e| break :fallback e,
                    }
                }
            },
            else => |e| break :err e,
        }
    };
    syscall.finish();
    switch (err) {
        .ERROR_DIR_NOT_EMPTY => return error.DirNotEmpty,
        .ERROR_ACCESS_DENIED, .ERROR_WRITE_PROTECT => return error.AccessDenied,
        .ERROR_INVALID_PARAMETER => return errorBug(err),
        else => return unexpectedError(err),
    }
}

fn dirDeleteFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8) Dir.DeleteFileError!void {
    _ = userdata;
    return dirDeleteWindows(dir, sub_path, false) catch |err| switch (err) {
        error.DirNotEmpty => unreachable,
        else => |e| return e,
    };
}

fn dirDeleteDir(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8) Dir.DeleteDirError!void {
    _ = userdata;
    return dirDeleteWindows(dir, sub_path, true) catch |err| switch (err) {
        error.IsDir => unreachable,
        else => |e| return e,
    };
}

fn renameWindows(
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
    replace_if_exists: bool,
) Dir.RenamePreserveError!void {
    var old_path: WindowsPath = undefined;
    try toWindowsPath(old_dir, old_sub_path, &old_path);
    var new_path: WindowsPath = undefined;
    try toWindowsPath(new_dir, new_sub_path, &new_path);
    const flags: u32 = if (replace_if_exists) 0x1 else 0; // MOVEFILE_REPLACE_EXISTING
    const syscall: Syscall = try .start();
    while (w32.MoveFileExW(old_path.span().ptr, new_path.span().ptr, @bitCast(flags)) == 0) switch (getLastError()) {
        .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
        .ERROR_FILE_NOT_FOUND, .ERROR_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
        .ERROR_ALREADY_EXISTS, .ERROR_FILE_EXISTS => return syscall.fail(error.PathAlreadyExists),
        .ERROR_NOT_SAME_DEVICE => return syscall.fail(error.CrossDevice),
        .ERROR_DIR_NOT_EMPTY => return syscall.fail(error.DirNotEmpty),
        .ERROR_SHARING_VIOLATION => return syscall.fail(error.FileBusy),
        .ERROR_INVALID_NAME, .ERROR_BAD_PATHNAME => return syscall.fail(error.BadPathName),
        .ERROR_FILENAME_EXCED_RANGE => return syscall.fail(error.NameTooLong),
        .ERROR_DIRECTORY => return syscall.fail(error.NotDir),
        .ERROR_DISK_FULL, .ERROR_HANDLE_DISK_FULL => return syscall.fail(error.NoSpaceLeft),
        .ERROR_WRITE_PROTECT => return syscall.fail(error.ReadOnlyFileSystem),
        .ERROR_BAD_NETPATH, .ERROR_BAD_NET_NAME => return syscall.fail(error.NetworkNotFound),
        .ERROR_ACCESS_DENIED => {
            syscall.finish();
            // Replacing a directory with a file or vice versa fails this way.
            const old_attributes = w32.GetFileAttributesW(old_path.span().ptr);
            const new_attributes = w32.GetFileAttributesW(new_path.span().ptr);
            if (old_attributes != INVALID_FILE_ATTRIBUTES and new_attributes != INVALID_FILE_ATTRIBUTES) {
                const old_is_dir = old_attributes & FILE_ATTRIBUTE_DIRECTORY != 0;
                const new_is_dir = new_attributes & FILE_ATTRIBUTE_DIRECTORY != 0;
                if (!old_is_dir and new_is_dir) return error.IsDir;
                if (old_is_dir and !new_is_dir) return error.NotDir;
            }
            return error.AccessDenied;
        },
        else => |err| return syscall.unexpectedError(err),
    };
    syscall.finish();
}

fn dirRename(
    userdata: ?*anyopaque,
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
) Dir.RenameError!void {
    _ = userdata;
    return renameWindows(old_dir, old_sub_path, new_dir, new_sub_path, true) catch |err| switch (err) {
        error.PathAlreadyExists => return error.Unexpected,
        error.OperationUnsupported => return error.Unexpected,
        else => |e| return e,
    };
}

fn dirRenamePreserve(
    userdata: ?*anyopaque,
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
) Dir.RenamePreserveError!void {
    _ = userdata;
    return renameWindows(old_dir, old_sub_path, new_dir, new_sub_path, false);
}

fn dirHardLink(
    userdata: ?*anyopaque,
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
    options: Dir.HardLinkOptions,
) Dir.HardLinkError!void {
    _ = userdata;
    _ = old_dir;
    _ = old_sub_path;
    _ = new_dir;
    _ = new_sub_path;
    _ = options;
    return error.OperationUnsupported;
}

fn fileHardLink(
    userdata: ?*anyopaque,
    file: File,
    new_dir: Dir,
    new_sub_path: []const u8,
    options: File.HardLinkOptions,
) File.HardLinkError!void {
    _ = userdata;
    _ = file;
    _ = new_dir;
    _ = new_sub_path;
    _ = options;
    return error.OperationUnsupported;
}

// ---------------------------------------------------------------------------
// Symbolic links

fn dirSymLink(
    userdata: ?*anyopaque,
    dir: Dir,
    target_path: []const u8,
    sym_link_path: []const u8,
    flags: Dir.SymLinkFlags,
) Dir.SymLinkError!void {
    _ = userdata;
    // The target is stored as given (`CreateSymbolicLinkW` handles absolute
    // targets), except that relative targets must use `\` as separator.
    var target: WindowsPath = undefined;
    try wtf8ToWindowsPath(target_path, &target);
    std.mem.replaceScalar(u16, target.data[0..target.len], '/', '\\');

    var link: WindowsPath = undefined;
    toWindowsPath(dir, sym_link_path, &link) catch |err| switch (err) {
        error.AccessDenied, error.FileNotFound, error.NameTooLong, error.BadPathName, error.Unexpected => |e| return e,
    };

    var link_flags: u32 = 0x2; // SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE
    if (flags.is_directory) link_flags |= 0x1; // SYMBOLIC_LINK_FLAG_DIRECTORY
    const syscall: Syscall = try .start();
    while (w32.CreateSymbolicLinkW(link.span().ptr, target.span().ptr, @bitCast(link_flags)) == 0) switch (getLastError()) {
        .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
        // Windows versions before 10 1703 do not know the unprivileged flag.
        .ERROR_INVALID_PARAMETER => |err| {
            if (link_flags & 0x2 == 0) return syscall.errorBug(err);
            link_flags &= ~@as(u32, 0x2);
        },
        .ERROR_ALREADY_EXISTS, .ERROR_FILE_EXISTS => return syscall.fail(error.PathAlreadyExists),
        .ERROR_PRIVILEGE_NOT_HELD => return syscall.fail(error.PermissionDenied),
        .ERROR_ACCESS_DENIED => return syscall.fail(error.AccessDenied),
        .ERROR_FILE_NOT_FOUND, .ERROR_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
        .ERROR_INVALID_FUNCTION, .ERROR_NOT_SUPPORTED => return syscall.fail(error.FileSystem),
        .ERROR_DISK_FULL, .ERROR_HANDLE_DISK_FULL => return syscall.fail(error.NoSpaceLeft),
        .ERROR_DIRECTORY => return syscall.fail(error.NotDir),
        .ERROR_INVALID_NAME, .ERROR_BAD_PATHNAME => return syscall.fail(error.BadPathName),
        .ERROR_FILENAME_EXCED_RANGE => return syscall.fail(error.NameTooLong),
        .ERROR_BAD_NETPATH, .ERROR_BAD_NET_NAME => return syscall.fail(error.NetworkNotFound),
        .ERROR_WRITE_PROTECT => return syscall.fail(error.ReadOnlyFileSystem),
        else => |err| return syscall.unexpectedError(err),
    };
    syscall.finish();
}

const FSCTL_GET_REPARSE_POINT: u32 = 0x000900A8;

fn dirReadLink(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, buffer: []u8) Dir.ReadLinkError!usize {
    _ = userdata;
    var path: WindowsPath = undefined;
    try toWindowsPath(dir, sub_path, &path);
    const handle = createFile(path.span(), .{
        .access = FILE_READ_ATTRIBUTES | SYNCHRONIZE,
        .creation = .OPEN_EXISTING,
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.AccessDenied,
        error.FileNotFound,
        error.SymLinkLoop,
        error.SystemResources,
        error.NotDir,
        error.NetworkNotFound,
        error.AntivirusInterference,
        error.FileBusy,
        error.NameTooLong,
        error.BadPathName,
        error.Canceled,
        error.Unexpected,
        => |e| return e,
        error.PipeBusy => return error.AccessDenied,
        error.NoDevice => return error.FileNotFound,
        else => return error.Unexpected,
    };
    defer _ = w32.CloseHandle(handle);

    var reparse_buf: [windows.MAXIMUM_REPARSE_DATA_BUFFER_SIZE]u8 align(@alignOf(windows.REPARSE_DATA_BUFFER)) = undefined;
    var returned: u32 = 0;
    {
        const syscall: Syscall = try .start();
        while (w32.DeviceIoControl(handle, FSCTL_GET_REPARSE_POINT, null, 0, &reparse_buf, reparse_buf.len, &returned, null) == 0) switch (getLastError()) {
            .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
            .ERROR_NOT_A_REPARSE_POINT => return syscall.fail(error.NotLink),
            .ERROR_ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            else => |err| return syscall.unexpectedError(err),
        };
        syscall.finish();
    }

    const reparse_struct: *const windows.REPARSE_DATA_BUFFER = @ptrCast(@alignCast(&reparse_buf));
    const tag: u32 = @bitCast(reparse_struct.ReparseTag);
    const IO_REPARSE_TAG_SYMLINK: u32 = 0xA000000C;
    const IO_REPARSE_TAG_MOUNT_POINT: u32 = 0xA0000003;
    const target_w, const is_relative = switch (tag) {
        IO_REPARSE_TAG_SYMLINK => r: {
            const buf: *const windows.SYMBOLIC_LINK_REPARSE_BUFFER = @ptrCast(@alignCast(&reparse_struct.DataBuffer[0]));
            const path_buf = @as([*]const u16, &buf.PathBuffer);
            break :r .{
                path_buf[buf.SubstituteNameOffset >> 1 ..][0 .. buf.SubstituteNameLength >> 1],
                buf.Flags & windows.SYMLINK_FLAG_RELATIVE != 0,
            };
        },
        IO_REPARSE_TAG_MOUNT_POINT => r: {
            const buf: *const windows.MOUNT_POINT_REPARSE_BUFFER = @ptrCast(@alignCast(&reparse_struct.DataBuffer[0]));
            const path_buf = @as([*]const u16, &buf.PathBuffer);
            break :r .{ path_buf[buf.SubstituteNameOffset >> 1 ..][0 .. buf.SubstituteNameLength >> 1], false };
        },
        else => return error.UnsupportedReparsePointType,
    };
    // Absolute targets are stored as NT paths (`\??\C:\foo`).
    const result_w = if (is_relative) target_w else windows.ntToWin32Namespace(target_w, &path.data) catch |err| switch (err) {
        error.NameTooLong => |e| return e,
        error.NotNtPath => target_w,
    };
    const len = std.unicode.calcWtf8Len(result_w);
    if (len > buffer.len) return error.NameTooLong;
    return std.unicode.wtf16LeToWtf8(buffer, result_w);
}

// ---------------------------------------------------------------------------
// Other file operations

fn fileSync(userdata: ?*anyopaque, file: File) File.SyncError!void {
    _ = userdata;
    const syscall: Syscall = try .start();
    while (w32.FlushFileBuffers(file.handle) == 0) switch (getLastError()) {
        .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
        .ERROR_ACCESS_DENIED => return syscall.fail(error.AccessDenied),
        .ERROR_UNEXP_NET_ERR => return syscall.fail(error.InputOutput),
        .ERROR_DISK_FULL, .ERROR_HANDLE_DISK_FULL => return syscall.fail(error.NoSpaceLeft),
        // Flushing a console or pipe has nothing to do.
        .ERROR_INVALID_HANDLE, .ERROR_INVALID_FUNCTION => return syscall.finish(),
        else => |err| return syscall.unexpectedError(err),
    };
    syscall.finish();
}

fn fileSetLength(userdata: ?*anyopaque, file: File, length: u64) File.SetLengthError!void {
    _ = userdata;
    const signed_len: i64 = @bitCast(length);
    if (signed_len < 0) return error.FileTooBig; // Avoid ambiguous EINVAL errors.
    var info: FILE_END_OF_FILE_INFO = .{ .EndOfFile = signed_len };
    const syscall: Syscall = try .start();
    while (w32.SetFileInformationByHandle(file.handle, .FileEndOfFileInfo, &info, @sizeOf(FILE_END_OF_FILE_INFO)) == 0) switch (getLastError()) {
        .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
        .ERROR_ACCESS_DENIED, .ERROR_USER_MAPPED_FILE => return syscall.fail(error.AccessDenied),
        .ERROR_INVALID_PARAMETER, .ERROR_DISK_FULL, .ERROR_HANDLE_DISK_FULL => return syscall.fail(error.FileTooBig),
        .ERROR_INVALID_HANDLE => |err| return syscall.errorBug(err), // Handle not open for writing.
        else => |err| return syscall.unexpectedError(err),
    };
    syscall.finish();
}

/// Sets attributes and/or times; zero values are left unchanged.
fn setBasicInfo(handle: w32.HANDLE, info: *FILE_BASIC_INFO) (Io.Cancelable || Io.UnexpectedError || error{AccessDenied})!void {
    const syscall: Syscall = try .start();
    while (w32.SetFileInformationByHandle(handle, .FileBasicInfo, info, @sizeOf(FILE_BASIC_INFO)) == 0) switch (getLastError()) {
        .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
        .ERROR_ACCESS_DENIED, .ERROR_WRITE_PROTECT => return syscall.fail(error.AccessDenied),
        else => |err| return syscall.unexpectedError(err),
    };
    syscall.finish();
}

fn permissionsInfo(permissions: File.Permissions) FILE_BASIC_INFO {
    // An attribute value of 0 means "unchanged", so clearing all attributes
    // (such as read-only) requires FILE_ATTRIBUTE_NORMAL.
    const attributes: u32 = @backingInt(permissions);
    return .{
        .CreationTime = 0,
        .LastAccessTime = 0,
        .LastWriteTime = 0,
        .ChangeTime = 0,
        .FileAttributes = if (attributes == 0) FILE_ATTRIBUTE_NORMAL else attributes,
    };
}

fn fileSetPermissions(userdata: ?*anyopaque, file: File, permissions: File.Permissions) File.SetPermissionsError!void {
    _ = userdata;
    var info = permissionsInfo(permissions);
    return setBasicInfo(file.handle, &info);
}

fn dirSetPermissions(userdata: ?*anyopaque, dir: Dir, permissions: Dir.Permissions) Dir.SetPermissionsError!void {
    _ = userdata;
    var info = permissionsInfo(permissions);
    info.FileAttributes |= FILE_ATTRIBUTE_DIRECTORY;
    return setBasicInfo(dir.handle, &info);
}

fn dirSetFilePermissions(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    permissions: Dir.Permissions,
    options: Dir.SetFilePermissionsOptions,
) Dir.SetFilePermissionsError!void {
    _ = userdata;
    var path: WindowsPath = undefined;
    try toWindowsPath(dir, sub_path, &path);
    const handle = createFile(path.span(), .{
        .access = FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES | SYNCHRONIZE,
        .creation = .OPEN_EXISTING,
        .follow_symlinks = options.follow_symlinks,
    }) catch |err| switch (err) {
        error.AccessDenied,
        error.FileNotFound,
        error.SymLinkLoop,
        error.SystemResources,
        error.ReadOnlyFileSystem,
        error.ProcessFdQuotaExceeded,
        error.NameTooLong,
        error.BadPathName,
        error.Canceled,
        error.Unexpected,
        => |e| return e,
        else => return error.Unexpected,
    };
    defer _ = w32.CloseHandle(handle);
    var info = permissionsInfo(permissions);
    var current: FILE_BASIC_INFO = undefined;
    if (w32.GetFileInformationByHandleEx(handle, .FileBasicInfo, &current, @sizeOf(FILE_BASIC_INFO)) != 0) {
        info.FileAttributes |= current.FileAttributes & FILE_ATTRIBUTE_DIRECTORY;
    }
    return setBasicInfo(handle, &info);
}

fn dirSetOwner(userdata: ?*anyopaque, dir: Dir, owner: ?File.Uid, group: ?File.Gid) Dir.SetOwnerError!void {
    _ = userdata;
    _ = dir;
    _ = owner;
    _ = group;
    return error.Unexpected; // Unsupported OS.
}

fn dirSetFileOwner(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    owner: ?File.Uid,
    group: ?File.Gid,
    options: Dir.SetFileOwnerOptions,
) Dir.SetFileOwnerError!void {
    _ = userdata;
    _ = dir;
    _ = sub_path;
    _ = owner;
    _ = group;
    _ = options;
    return error.Unexpected; // Unsupported OS.
}

fn fileSetOwner(userdata: ?*anyopaque, file: File, owner: ?File.Uid, group: ?File.Gid) File.SetOwnerError!void {
    _ = userdata;
    _ = file;
    _ = owner;
    _ = group;
    return error.Unexpected; // Unsupported OS.
}

fn timestampsInfo(access: File.SetTimestamp, modify: File.SetTimestamp) FILE_BASIC_INFO {
    const now_sys: i64 = if (access == .now or modify == .now) now: {
        var ft: w32.FILETIME = undefined;
        w32.GetSystemTimePreciseAsFileTime(&ft);
        break :now @bitCast(fileTimeToInt(ft));
    } else undefined;
    return .{
        .CreationTime = 0,
        .LastAccessTime = switch (access) {
            .unchanged => 0,
            .now => now_sys,
            .new => |ts| windows.toSysTime(ts),
        },
        .LastWriteTime = switch (modify) {
            .unchanged => 0,
            .now => now_sys,
            .new => |ts| windows.toSysTime(ts),
        },
        .ChangeTime = 0,
        .FileAttributes = 0,
    };
}

fn fileSetTimestamps(userdata: ?*anyopaque, file: File, options: File.SetTimestampsOptions) File.SetTimestampsError!void {
    _ = userdata;
    var info = timestampsInfo(options.access_timestamp, options.modify_timestamp);
    return setBasicInfo(file.handle, &info);
}

fn dirSetTimestamps(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, options: Dir.SetTimestampsOptions) Dir.SetTimestampsError!void {
    _ = userdata;
    var path: WindowsPath = undefined;
    toWindowsPath(dir, sub_path, &path) catch |err| switch (err) {
        error.FileNotFound => return error.Unexpected,
        else => |e| return e,
    };
    const handle = createFile(path.span(), .{
        .access = FILE_WRITE_ATTRIBUTES | SYNCHRONIZE,
        .creation = .OPEN_EXISTING,
        .follow_symlinks = options.follow_symlinks,
    }) catch |err| switch (err) {
        error.AccessDenied,
        error.PermissionDenied,
        error.ReadOnlyFileSystem,
        error.NameTooLong,
        error.BadPathName,
        error.Canceled,
        error.Unexpected,
        => |e| return e,
        else => return error.Unexpected,
    };
    defer _ = w32.CloseHandle(handle);
    var info = timestampsInfo(options.access_timestamp, options.modify_timestamp);
    return setBasicInfo(handle, &info);
}

fn fileLock(userdata: ?*anyopaque, file: File, lock: File.Lock) File.LockError!void {
    _ = userdata;
    const exclusive = switch (lock) {
        .none => {
            // To match the non-Windows behavior, unlock
            _ = try unlockFileRange(file.handle);
            return;
        },
        .shared => false,
        .exclusive => true,
    };
    return lockFileRange(file.handle, exclusive, false) catch |err| switch (err) {
        error.WouldBlock => unreachable, // did not pass fail_immediately
        else => |e| return e,
    };
}

fn fileTryLock(userdata: ?*anyopaque, file: File, lock: File.Lock) File.LockError!bool {
    _ = userdata;
    const exclusive = switch (lock) {
        .none => return unlockFileRange(file.handle),
        .shared => false,
        .exclusive => true,
    };
    lockFileRange(file.handle, exclusive, true) catch |err| switch (err) {
        error.WouldBlock => return false,
        else => |e| return e,
    };
    return true;
}

fn fileUnlock(userdata: ?*anyopaque, file: File) void {
    _ = userdata;
    const was_locked = unlockFileRange(file.handle) catch return assert(!is_debug);
    if (!was_locked) assert(!is_debug); // Function asserts unlocked.
}

fn fileDowngradeLock(userdata: ?*anyopaque, file: File) File.DowngradeLockError!void {
    _ = userdata;
    // Windows locks work like a semaphore + exclusivity flag. Obtaining a
    // shared lock on top of the exclusive one changes the exclusivity flag, and
    // unlocking once then drops the count back to 1 without changing the flag.
    lockFileRange(file.handle, false, true) catch |err| switch (err) {
        error.WouldBlock, error.SystemResources => return error.Unexpected, // File was not locked in exclusive mode.
        else => |e| return e,
    };
    _ = unlockFileRange(file.handle) catch {};
}

// ---------------------------------------------------------------------------
// Terminals

const ENABLE_VIRTUAL_TERMINAL_PROCESSING: u32 = 0x4;

fn getConsoleMode(handle: w32.HANDLE) ?u32 {
    var mode: w32.CONSOLE_MODE = undefined;
    if (w32.GetConsoleMode(handle, &mode) == 0) return null;
    return @bitCast(mode);
}

fn fileIsTty(userdata: ?*anyopaque, file: File) Io.Cancelable!bool {
    _ = userdata;
    if (getConsoleMode(file.handle) != null) return true;
    return isCygwinPty(file);
}

fn fileEnableAnsiEscapeCodes(userdata: ?*anyopaque, file: File) File.EnableAnsiEscapeCodesError!void {
    _ = userdata;
    // For Windows Terminal, VT Sequences processing is enabled by default.
    const mode = getConsoleMode(file.handle) orelse
        return if (!try isCygwinPty(file)) error.NotTerminalDevice;
    if (mode & ENABLE_VIRTUAL_TERMINAL_PROCESSING != 0) return;
    // For Windows Console, VT Sequences processing support was added in
    // Windows 10 build 14361, but disabled by default. `DISABLE_NEWLINE_AUTO_RETURN`
    // is intentionally not set; see `std.Io.Threaded.fileEnableAnsiEscapeCodes`.
    if (w32.SetConsoleMode(file.handle, @bitCast(mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING)) == 0) {
        return unexpectedError(getLastError());
    }
}

fn fileSupportsAnsiEscapeCodes(userdata: ?*anyopaque, file: File) Io.Cancelable!bool {
    _ = userdata;
    if (getConsoleMode(file.handle)) |mode| return mode & ENABLE_VIRTUAL_TERMINAL_PROCESSING != 0;
    return isCygwinPty(file);
}

/// MSYS2/cygwin ptys are named pipes named like `msys-[...]-ptyN-[...]` or
/// `cygwin-[...]-ptyN-[...]`, for example `msys-1888ae32e00d56aa-pty0-to-master`.
fn isCygwinPty(file: File) Io.Cancelable!bool {
    if (w32.GetFileType(file.handle) != FILE_TYPE_PIPE) return false;

    const name_bytes_offset = @offsetOf(w32.FILE_NAME_INFO, "FileName");
    // The names we care about are short, so a buffer of `MAX_PATH` is enough;
    // any failure means it is not a pty.
    const num_name_bytes = windows.MAX_PATH * 2;
    var name_info_bytes: [name_bytes_offset + num_name_bytes]u8 align(@alignOf(w32.FILE_NAME_INFO)) = @splat(0);
    const syscall: Syscall = try .start();
    if (w32.GetFileInformationByHandleEx(file.handle, .FileNameInfo, &name_info_bytes, name_info_bytes.len) == 0) {
        syscall.finish();
        return false;
    }
    syscall.finish();

    const name_info: *const w32.FILE_NAME_INFO = @ptrCast(&name_info_bytes);
    const name_bytes = name_info_bytes[name_bytes_offset .. name_bytes_offset + name_info.FileNameLength];
    const name_wide = std.mem.bytesAsSlice(u16, name_bytes);
    // The name will be prefixed with a '\', e.g. \msys-1888ae32e00d56aa-pty0-to-master
    return (std.mem.startsWith(u16, name_wide, &[_]u16{ '\\', 'm', 's', 'y', 's', '-' }) or
        std.mem.startsWith(u16, name_wide, &[_]u16{ '\\', 'c', 'y', 'g', 'w', 'i', 'n', '-' })) and
        std.mem.find(u16, name_wide, &[_]u16{ '-', 'p', 't', 'y' }) != null;
}

// ---------------------------------------------------------------------------
// Atomic files

fn dirCreateFileAtomic(
    userdata: ?*anyopaque,
    dir: Dir,
    dest_path: []const u8,
    options: Dir.CreateFileAtomicOptions,
) Dir.CreateFileAtomicError!File.Atomic {
    const w = fromUserdata(userdata);
    const w_io = w.io();
    if (Dir.path.dirname(dest_path)) |dirname| {
        const new_dir = if (options.make_path)
            dir.createDirPathOpen(w_io, dirname, .{}) catch |err| switch (err) {
                // None of these make sense in this context.
                error.IsDir,
                error.Streaming,
                error.DiskQuota,
                error.PathAlreadyExists,
                error.LinkQuotaExceeded,
                error.PipeBusy,
                error.FileTooBig,
                error.FileLocksUnsupported,
                error.DeviceBusy,
                => return error.Unexpected,

                else => |e| return e,
            }
        else
            try dir.openDir(w_io, dirname, .{});

        return atomicFileInit(w_io, Dir.path.basename(dest_path), options.permissions, new_dir, true);
    }

    return atomicFileInit(w_io, dest_path, options.permissions, dir, false);
}

fn atomicFileInit(
    w_io: Io,
    dest_basename: []const u8,
    permissions: File.Permissions,
    dir: Dir,
    close_dir_on_deinit: bool,
) Dir.CreateFileAtomicError!File.Atomic {
    while (true) {
        var random_integer: u64 = undefined;
        w_io.random(@ptrCast(&random_integer));
        const tmp_sub_path = std.fmt.hex(random_integer);
        const file = dir.createFile(w_io, &tmp_sub_path, .{
            .permissions = permissions,
            .exclusive = true,
        }) catch |err| switch (err) {
            error.PathAlreadyExists => continue,
            error.DeviceBusy => continue,
            error.FileBusy => continue,

            error.IsDir => return error.Unexpected, // No path components.
            error.FileTooBig => return error.Unexpected, // Creating, not opening.
            error.FileLocksUnsupported => return error.Unexpected, // Not asking for locks.
            error.PipeBusy => return error.Unexpected, // Not opening a pipe.

            else => |e| return e,
        };
        return .{
            .file = file,
            .file_basename_hex = random_integer,
            .dest_sub_path = dest_basename,
            .file_open = true,
            .file_exists = true,
            .close_dir_on_deinit = close_dir_on_deinit,
            .dir = dir,
        };
    }
}

// ---------------------------------------------------------------------------
// Memory mapping

fn allocationGranularity() usize {
    var system_info: w32.SYSTEM_INFO = undefined;
    w32.GetSystemInfo(&system_info);
    return system_info.dwAllocationGranularity;
}

fn fileMemoryMapCreate(
    userdata: ?*anyopaque,
    file: File,
    options: File.MemoryMap.CreateOptions,
) File.MemoryMap.CreateError!File.MemoryMap {
    const w = fromUserdata(userdata);
    const offset = options.offset;
    const len = options.len;

    if (!w.disable_memory_mapping) {
        if (createFileMap(file, options.protection, offset, options.populate, len)) |result| {
            return result;
        } else |err| switch (err) {
            error.Unseekable, error.Canceled, error.AccessDenied => |e| return e,
            error.OperationUnsupported => {},
            else => {
                if (builtin.mode == .debug)
                    std.log.warn("memory mapping failed with {t}, falling back to file operations", .{err});
            },
        }
    }

    const gpa = w.allocator;
    const page_size = std.heap.pageSize();
    const alignment: Alignment = .fromByteUnits(page_size);
    const memory = m: {
        const ptr = gpa.rawAlloc(len, alignment, @returnAddress()) orelse return error.OutOfMemory;
        break :m ptr[0..len];
    };
    errdefer gpa.rawFree(memory, alignment, @returnAddress());

    if (!options.undefined_contents) try mmSyncRead(file, memory, offset);

    return .{
        .file = file,
        .offset = offset,
        .memory = @alignCast(memory),
        .section = null,
    };
}

const CreateFileMapError = error{
    AccessDenied,
    PermissionDenied,
    OperationUnsupported,
    OutOfMemory,
    Unseekable,
    LockViolation,
    SectionOversize,
} || Io.Cancelable || Io.UnexpectedError;

fn createFileMap(
    file: File,
    protection: std.process.MemoryProtection,
    offset: u64,
    populate: bool,
    len: usize,
) CreateFileMapError!File.MemoryMap {
    try Thread.checkCancel();

    // `MapViewOfFile` requires the offset to be a multiple of the allocation
    // granularity, so map from there and skip the extra pages.
    const granularity = allocationGranularity();
    const view_offset = std.mem.alignBackward(u64, offset, granularity);
    const skip: usize = @intCast(offset - view_offset);
    const section_size = std.math.add(u64, offset, len) catch return error.Unseekable;

    const page: u32, const map_access: u32 = switch (@as(u3, @bitCast(protection))) {
        0b001 => .{ 0x02, 0x4 }, // PAGE_READONLY, FILE_MAP_READ
        0b011 => .{ 0x04, 0x2 }, // PAGE_READWRITE, FILE_MAP_WRITE
        0b101 => .{ 0x20, 0x4 | 0x20 }, // PAGE_EXECUTE_READ, FILE_MAP_READ | FILE_MAP_EXECUTE
        0b111 => .{ 0x40, 0x2 | 0x20 }, // PAGE_EXECUTE_READWRITE, FILE_MAP_WRITE | FILE_MAP_EXECUTE
        else => return error.AccessDenied,
    };
    const section = w32.CreateFileMappingW(
        file.handle,
        null,
        @bitCast(page),
        @truncate(section_size >> 32),
        @truncate(section_size),
        null,
    ) orelse return switch (getLastError()) {
        .ERROR_LOCK_VIOLATION => error.LockViolation,
        .ERROR_BAD_EXE_FORMAT, .ERROR_INVALID_HANDLE, .ERROR_INVALID_FUNCTION => error.OperationUnsupported,
        .ERROR_ACCESS_DENIED => error.AccessDenied,
        .ERROR_NOT_ENOUGH_MEMORY, .ERROR_COMMITMENT_LIMIT => error.OutOfMemory,
        .ERROR_DISK_FULL, .ERROR_FILE_INVALID => error.SectionOversize,
        else => |err| unexpectedError(err),
    };
    errdefer _ = w32.CloseHandle(section);

    const base = w32.MapViewOfFile(
        section,
        @bitCast(map_access),
        @truncate(view_offset >> 32),
        @truncate(view_offset),
        skip + len,
    ) orelse return switch (getLastError()) {
        .ERROR_ACCESS_DENIED => error.AccessDenied,
        .ERROR_NOT_ENOUGH_MEMORY => error.OutOfMemory,
        else => |err| unexpectedError(err),
    };
    const contents: [*]align(std.heap.page_size_min) u8 = @alignCast(@as([*]u8, @ptrCast(base)) + skip);

    if (populate and len != 0) {
        var ranges = [_]w32.WIN32_MEMORY_RANGE_ENTRY{.{ .VirtualAddress = contents, .NumberOfBytes = len }};
        // Only a hint, so failure is not an error.
        _ = w32.PrefetchVirtualMemory(w32.GetCurrentProcess(), ranges.len, &ranges, 0);
    }
    return .{
        .file = file,
        .offset = offset,
        .memory = contents[0..len],
        .section = section,
    };
}

fn fileMemoryMapDestroy(userdata: ?*anyopaque, mm: *File.MemoryMap) void {
    const w = fromUserdata(userdata);
    const memory = mm.memory;
    if (mm.section) |section| {
        const base = std.mem.alignBackward(usize, @intFromPtr(memory.ptr), allocationGranularity());
        _ = w32.UnmapViewOfFile(@ptrFromInt(base));
        _ = w32.CloseHandle(section);
    } else {
        w.allocator.rawFree(memory, .fromByteUnits(std.heap.pageSize()), @returnAddress());
    }
    mm.* = undefined;
}

fn fileMemoryMapSetLength(
    userdata: ?*anyopaque,
    mm: *File.MemoryMap,
    new_len: usize,
) File.MemoryMap.SetLengthError!void {
    const w = fromUserdata(userdata);
    const page_size = std.heap.pageSize();
    const alignment: Alignment = .fromByteUnits(page_size);
    const page_align = std.heap.page_size_min;
    const old_memory = mm.memory;

    if (mm.section != null) {
        if (alignment.forward(new_len) == alignment.forward(old_memory.len)) {
            mm.memory.len = new_len;
            return;
        }
        return error.OperationUnsupported;
    }
    const gpa = w.allocator;
    if (gpa.rawRemap(old_memory, alignment, new_len, @returnAddress())) |new_ptr| {
        mm.memory = @alignCast(new_ptr[0..new_len]);
    } else {
        const new_ptr: [*]align(page_align) u8 = @alignCast(
            gpa.rawAlloc(new_len, alignment, @returnAddress()) orelse return error.OutOfMemory,
        );
        const copy_len = @min(new_len, old_memory.len);
        @memcpy(new_ptr[0..copy_len], old_memory[0..copy_len]);
        mm.memory = new_ptr[0..new_len];
        gpa.rawFree(old_memory, alignment, @returnAddress());
    }
}

fn fileMemoryMapRead(userdata: ?*anyopaque, mm: *File.MemoryMap) File.ReadPositionalError!void {
    _ = userdata;
    if (mm.section == null) return mmSyncRead(mm.file, mm.memory, mm.offset);
}

fn fileMemoryMapWrite(userdata: ?*anyopaque, mm: *File.MemoryMap) File.WritePositionalError!void {
    _ = userdata;
    if (mm.section == null) return mmSyncWrite(mm.file, mm.memory, mm.offset);
}

fn mmSyncRead(file: File, memory: []u8, offset: u64) File.ReadPositionalError!void {
    var i: usize = 0;
    while (true) {
        const buf = memory[i..];
        if (buf.len == 0) break;
        const n = try fileReadPositional(null, file, &.{buf}, offset + i);
        if (n == 0) {
            @memset(memory[i..], 0);
            break;
        }
        i += n;
    }
}

fn mmSyncWrite(file: File, memory: []u8, offset: u64) File.WritePositionalError!void {
    var i: usize = 0;
    while (true) {
        const buf = memory[i..];
        if (buf.len == 0) break;
        i += try fileWritePositional(null, file, &.{}, &.{buf}, 1, offset + i);
    }
}

// ---------------------------------------------------------------------------
// Networking
//
// `std.Io.Threaded` talks to the AFD driver directly. Here sockets are created
// with Winsock as overlapped sockets, and every potentially blocking operation
// is overlapped with an alertable wait, so that cancelation works the same way
// as for nonblocking files (`CancelIoEx`).

const net = Io.net;
const PosixAddress = Io.Threaded.PosixAddress;
const addressToPosix = Io.Threaded.addressToPosix;
const addressFromPosix = Io.Threaded.addressFromPosix;

const AF_UNIX: i32 = 1;
const AF_INET: i32 = 2;
const AF_INET6: i32 = 23;
const SOL_SOCKET: i32 = 0xffff;
const SO_REUSEADDR: i32 = 0x0004;
const SO_BROADCAST: i32 = 0x0020;
const SO_UPDATE_ACCEPT_CONTEXT: i32 = 0x700B;
const SO_UPDATE_CONNECT_CONTEXT: i32 = 0x7010;
const IPPROTO_IPV6: i32 = 41;
const IPV6_V6ONLY: i32 = 27;
const WSA_FLAG_OVERLAPPED: u32 = 0x01;
const WSA_FLAG_NO_HANDLE_INHERIT: u32 = 0x80;
const MSG_OOB: u32 = 0x1;
const MSG_PEEK: u32 = 0x2;
const INVALID_SOCKET: usize = std.math.maxInt(usize);
const WAIT_OBJECT_0: u32 = 0;

const ws2 = struct {
    extern "ws2_32" fn WSAGetLastError() callconv(.winapi) i32;
};

fn wsaError(code: anytype) w32.WSA_ERROR {
    return std.enums.fromInt(w32.WSA_ERROR, code) orelse .SYSCALLFAILURE;
}

fn wsaGetLastError() w32.WSA_ERROR {
    return wsaError(ws2.WSAGetLastError());
}

fn unexpectedWsaError(err: w32.WSA_ERROR) Io.UnexpectedError {
    @branchHint(.cold);
    if (std.options.unexpected_error_tracing) {
        std.debug.print("error.Unexpected: WSAGetLastError({d}): {t}\n", .{ @backingInt(err), err });
        std.debug.dumpCurrentStackTrace(.{ .first_address = @returnAddress() });
    }
    return error.Unexpected;
}

fn toSocket(handle: net.Socket.Handle) w32.SOCKET {
    return @ptrCast(handle);
}

fn fromSocket(socket: w32.SOCKET) net.Socket.Handle {
    return @ptrCast(socket);
}

fn ensureWinsock(w: *WinIo) error{ NetworkDown, SystemResources, Unexpected }!void {
    if (w.wsa_started.load(.acquire)) return;
    mutexLockUncancelable(&w.mutex);
    defer mutexUnlock(&w.mutex);
    if (w.wsa_started.load(.monotonic)) return;
    var data: w32.WSAData = undefined;
    switch (w32.WSAStartup(0x0202, &data)) {
        0 => {},
        @backingInt(w32.WSA_ERROR.SYSNOTREADY) => return error.NetworkDown,
        @backingInt(w32.WSA_ERROR.EPROCLIM) => return error.SystemResources,
        else => |code| return unexpectedWsaError(wsaError(code)),
    }
    w.wsa_started.store(true, .release);
}

const OpenSocketError = error{
    AddressFamilyUnsupported,
    ProtocolUnsupportedBySystem,
    ProtocolUnsupportedByAddressFamily,
    SocketModeUnsupported,
    OptionUnsupported,
    ProcessFdQuotaExceeded,
    SystemResources,
    NetworkDown,
    Unexpected,
    Canceled,
};

fn openSocket(w: *WinIo, family: i32, mode: net.Socket.Mode, protocol: ?net.Protocol) OpenSocketError!w32.SOCKET {
    try ensureWinsock(w);
    try Thread.checkCancel();
    const sock_type, const proto = try Io.Threaded.posixSocketModeProtocol(@intCast(family), mode, protocol);
    var flags = WSA_FLAG_OVERLAPPED | WSA_FLAG_NO_HANDLE_INHERIT;
    while (true) {
        const socket = w32.WSASocketW(family, @intCast(sock_type), @intCast(proto), null, 0, flags);
        if (@intFromPtr(socket) != INVALID_SOCKET) return socket;
        switch (wsaGetLastError()) {
            // `WSA_FLAG_NO_HANDLE_INHERIT` requires Windows 7 SP1.
            .EINVAL => if (flags & WSA_FLAG_NO_HANDLE_INHERIT != 0) {
                flags &= ~WSA_FLAG_NO_HANDLE_INHERIT;
            } else return error.ProtocolUnsupportedBySystem,
            .EAFNOSUPPORT => return error.AddressFamilyUnsupported,
            .EPROTONOSUPPORT => return error.ProtocolUnsupportedByAddressFamily,
            .ESOCKTNOSUPPORT, .EPROTOTYPE => return error.SocketModeUnsupported,
            .EMFILE => return error.ProcessFdQuotaExceeded,
            .ENOBUFS => return error.SystemResources,
            .ENETDOWN => return error.NetworkDown,
            else => |err| return unexpectedWsaError(err),
        }
    }
}

fn closeSocket(socket: w32.SOCKET) void {
    _ = w32.closesocket(socket);
}

fn setSocketOption(socket: w32.SOCKET, level: i32, name: i32, value: u32) error{ OptionUnsupported, SystemResources, Unexpected }!void {
    const bytes = std.mem.asBytes(&value);
    if (w32.setsockopt(socket, level, name, @ptrCast(bytes), bytes.len) == 0) return;
    switch (wsaGetLastError()) {
        .ENOPROTOOPT, .EINVAL => return error.OptionUnsupported,
        .ENOBUFS => return error.SystemResources,
        else => |err| return unexpectedWsaError(err),
    }
}

fn getSockName(socket: w32.SOCKET) Io.UnexpectedError!net.IpAddress {
    var storage: PosixAddress = undefined;
    var len: i32 = @sizeOf(PosixAddress);
    if (w32.getsockname(socket, @ptrCast(&storage), &len) != 0) return unexpectedWsaError(wsaGetLastError());
    return addressFromPosix(&storage);
}

fn bindSocket(socket: w32.SOCKET, storage: *const anyopaque, len: i32) error{
    AddressInUse,
    AddressUnavailable,
    AccessDenied,
    AddressFamilyUnsupported,
    SystemResources,
    NetworkDown,
    Unexpected,
}!void {
    if (w32.bind(socket, @ptrCast(@alignCast(storage)), len) == 0) return;
    switch (wsaGetLastError()) {
        .EADDRINUSE => return error.AddressInUse,
        .EADDRNOTAVAIL => return error.AddressUnavailable,
        .EACCES => return error.AccessDenied,
        .EAFNOSUPPORT, .EFAULT => return error.AddressFamilyUnsupported,
        .ENOBUFS => return error.SystemResources,
        .ENETDOWN => return error.NetworkDown,
        else => |err| return unexpectedWsaError(err),
    }
}

fn bindIp(socket: w32.SOCKET, address: *const net.IpAddress) !void {
    var storage: PosixAddress = undefined;
    const len = addressToPosix(address, &storage);
    return bindSocket(socket, &storage, @intCast(len));
}

fn ipFamily(address: *const net.IpAddress) i32 {
    return switch (address.*) {
        .ip4 => AF_INET,
        .ip6 => AF_INET6,
    };
}

fn listenSocket(socket: w32.SOCKET, backlog: u31) error{ AddressInUse, SystemResources, NetworkDown, Unexpected }!void {
    if (w32.listen(socket, backlog) == 0) return;
    switch (wsaGetLastError()) {
        .EADDRINUSE => return error.AddressInUse,
        .ENOBUFS, .EMFILE => return error.SystemResources,
        .ENETDOWN => return error.NetworkDown,
        else => |err| return unexpectedWsaError(err),
    }
}

fn netListenIp(
    userdata: ?*anyopaque,
    address: *const net.IpAddress,
    options: net.IpAddress.ListenOptions,
) net.IpAddress.ListenError!net.Socket {
    const w = fromUserdata(userdata);
    const socket = try openSocket(w, ipFamily(address), options.mode, options.protocol);
    errdefer closeSocket(socket);
    if (options.reuse_address) try setSocketOption(socket, SOL_SOCKET, SO_REUSEADDR, 1);
    try bindIp(socket, address);
    try listenSocket(socket, options.kernel_backlog);
    return .{ .handle = fromSocket(socket), .address = try getSockName(socket) };
}

fn netBindIp(
    userdata: ?*anyopaque,
    address: *const net.IpAddress,
    options: net.IpAddress.BindOptions,
) net.IpAddress.BindError!net.Socket {
    const w = fromUserdata(userdata);
    const socket = try openSocket(w, ipFamily(address), options.mode, options.protocol);
    errdefer closeSocket(socket);
    if (options.ip6_only) |ip6_only| try setSocketOption(socket, IPPROTO_IPV6, IPV6_V6ONLY, @intFromBool(ip6_only));
    try bindIp(socket, address);
    if (options.allow_broadcast) try setSocketOption(socket, SOL_SOCKET, SO_BROADCAST, 1);
    return .{ .handle = fromSocket(socket), .address = try getSockName(socket) };
}

/// Waits until the event in `overlapped.hEvent` is signaled, while allowing
/// cancelation (which cancels the I/O on `handle`) and an optional deadline.
fn waitOverlappedEvent(
    handle: w32.HANDLE,
    overlapped: *w32.OVERLAPPED,
    deadline: ?Io.Clock.Timestamp,
) (Io.Cancelable || Io.Timeout.Error)!void {
    const event = overlapped.hEvent.?;
    while (true) {
        const ms: u32 = if (deadline) |d| millisecondsUntil(d) orelse {
            _ = w32.CancelIoEx(handle, overlapped);
            _ = w32.WaitForSingleObjectEx(event, INFINITE, w32.FALSE);
            return error.Timeout;
        } else INFINITE;
        const alertable_syscall = AlertableSyscall.start() catch |err| switch (err) {
            error.Canceled => |e| {
                _ = w32.CancelIoEx(handle, overlapped);
                _ = w32.WaitForSingleObjectEx(event, INFINITE, w32.FALSE);
                return e;
            },
        };
        const rc = w32.WaitForSingleObjectEx(event, ms, w32.TRUE);
        alertable_syscall.finish();
        if (@backingInt(rc) == WAIT_OBJECT_0) return;
        // `WAIT_IO_COMPLETION` or `WAIT_TIMEOUT`: check for cancelation and the deadline again.
    }
}

fn createManualEvent() error{SystemResources}!w32.HANDLE {
    return w32.CreateEventW(null, w32.TRUE, w32.FALSE, null) orelse error.SystemResources;
}

fn emptyOverlapped(event: ?w32.HANDLE) w32.OVERLAPPED {
    return .{
        .Internal = 0,
        .InternalHigh = 0,
        .Anonymous = .{ .Anonymous = .{ .Offset = 0, .OffsetHigh = 0 } },
        .hEvent = event,
    };
}

/// Looks up a Winsock extension function such as `AcceptEx` or `ConnectEx`.
fn getExtensionFunction(comptime T: type, socket: w32.SOCKET, guid: w32.Guid) Io.UnexpectedError!T {
    var function: ?T = null;
    var guid_copy = guid;
    var bytes: u32 = 0;
    if (w32.WSAIoctl(
        socket,
        w32.SIO_GET_EXTENSION_FUNCTION_POINTER,
        &guid_copy,
        @sizeOf(w32.Guid),
        @ptrCast(&function),
        @sizeOf(T),
        &bytes,
        null,
        null,
    ) != 0) return unexpectedWsaError(wsaGetLastError());
    return function orelse error.Unexpected;
}

const WSAID_ACCEPTEX: w32.Guid = .initString("b5367df1-cbac-11cf-95ca-00805f48a192");
const WSAID_CONNECTEX: w32.Guid = .initString("25a207b9-ddf3-4660-8ee9-76e58c74063e");

fn netAccept(userdata: ?*anyopaque, listen_handle: net.Socket.Handle, options: net.Server.AcceptOptions) net.Server.AcceptError!net.Socket {
    const w = fromUserdata(userdata);
    const listen_socket = toSocket(listen_handle);
    var local: PosixAddress = undefined;
    var local_len: i32 = @sizeOf(PosixAddress);
    if (w32.getsockname(listen_socket, @ptrCast(&local), &local_len) != 0) switch (wsaGetLastError()) {
        .EINVAL => return error.SocketNotListening,
        else => |err| return unexpectedWsaError(err),
    };
    const accept_socket = openSocket(w, local.any.family, options.mode, options.protocol) catch |err| switch (err) {
        error.AddressFamilyUnsupported,
        error.ProtocolUnsupportedBySystem,
        error.ProtocolUnsupportedByAddressFamily,
        error.SocketModeUnsupported,
        error.OptionUnsupported,
        => return error.Unexpected,
        else => |e| return e,
    };
    errdefer closeSocket(accept_socket);

    const acceptEx = try getExtensionFunction(w32.LPFN_ACCEPTEX, listen_socket, WSAID_ACCEPTEX);
    // AcceptEx requires room for both addresses plus 16 bytes each.
    const addr_space = @sizeOf(PosixAddress) + 16;
    var addresses: [2 * addr_space]u8 align(8) = undefined;
    const event = try createManualEvent();
    defer _ = w32.CloseHandle(event);
    var overlapped = emptyOverlapped(event);
    var received: u32 = 0;
    if (acceptEx(listen_socket, accept_socket, &addresses, 0, addr_space, addr_space, &received, &overlapped) == 0) {
        switch (wsaGetLastError()) {
            ._IO_PENDING => {},
            else => |err| return acceptError(err),
        }
    }
    waitOverlappedEvent(fromSocket(listen_socket), &overlapped, null) catch |err| switch (err) {
        error.Timeout => unreachable, // no deadline
        error.Canceled => |e| return e,
    };
    var flags: u32 = 0;
    if (w32.WSAGetOverlappedResult(listen_socket, &overlapped, &received, w32.FALSE, &flags) == 0) {
        return acceptError(wsaGetLastError());
    }
    const listen_value = @intFromPtr(listen_socket);
    const listen_bytes = std.mem.asBytes(&listen_value);
    _ = w32.setsockopt(accept_socket, SOL_SOCKET, SO_UPDATE_ACCEPT_CONTEXT, @ptrCast(listen_bytes), listen_bytes.len);

    var remote: PosixAddress = undefined;
    var remote_len: i32 = @sizeOf(PosixAddress);
    if (w32.getpeername(accept_socket, @ptrCast(&remote), &remote_len) != 0) {
        return acceptError(wsaGetLastError());
    }
    return .{ .handle = fromSocket(accept_socket), .address = addressFromPosix(&remote) };
}

fn acceptError(err: w32.WSA_ERROR) net.Server.AcceptError {
    return switch (err) {
        .EINVAL => error.SocketNotListening,
        .ECONNRESET, .ECONNABORTED, .ENOTCONN => error.ConnectionAborted,
        .EMFILE => error.ProcessFdQuotaExceeded,
        .ENOBUFS => error.SystemResources,
        .ENETDOWN => error.NetworkDown,
        .EACCES => error.BlockedByFirewall,
        else => unexpectedWsaError(err),
    };
}

fn connectError(err: w32.WSA_ERROR) net.IpAddress.ConnectError {
    return switch (err) {
        .ECONNREFUSED => error.ConnectionRefused,
        .ECONNRESET => error.ConnectionResetByPeer,
        .ENETUNREACH => error.NetworkUnreachable,
        .EHOSTUNREACH => error.HostUnreachable,
        .ETIMEDOUT => error.Timeout,
        .EADDRNOTAVAIL => error.AddressUnavailable,
        .EAFNOSUPPORT => error.AddressFamilyUnsupported,
        .EACCES => error.AccessDenied,
        .ENOBUFS => error.SystemResources,
        .ENETDOWN => error.NetworkDown,
        .EALREADY, .EINPROGRESS => error.ConnectionPending,
        .EWOULDBLOCK => error.WouldBlock,
        else => unexpectedWsaError(err),
    };
}

fn netConnectIp(
    userdata: ?*anyopaque,
    address: *const net.IpAddress,
    options: net.IpAddress.ConnectOptions,
) net.IpAddress.ConnectError!net.Socket {
    const w = fromUserdata(userdata);
    const deadline = options.timeout.toTimestamp(w.io());
    const socket = try openSocket(w, ipFamily(address), options.mode, options.protocol);
    errdefer closeSocket(socket);
    var storage: PosixAddress = undefined;
    const addr_len = addressToPosix(address, &storage);

    switch (options.mode) {
        .stream, .seqpacket => {
            // ConnectEx requires a bound socket.
            bindIp(socket, &switch (address.*) {
                .ip4 => .{ .ip4 = .unspecified(0) },
                .ip6 => .{ .ip6 = .unspecified(0) },
            }) catch |err| switch (err) {
                error.AddressInUse => return error.Unexpected,
                else => |e| return e,
            };
            const connectEx = try getExtensionFunction(w32.LPFN_CONNECTEX, socket, WSAID_CONNECTEX);
            const event = try createManualEvent();
            defer _ = w32.CloseHandle(event);
            var overlapped = emptyOverlapped(event);
            if (connectEx(socket, @ptrCast(&storage), @intCast(addr_len), null, 0, null, &overlapped) == 0) {
                switch (wsaGetLastError()) {
                    ._IO_PENDING => {},
                    else => |err| return connectError(err),
                }
            }
            try waitOverlappedEvent(fromSocket(socket), &overlapped, deadline);
            var transferred: u32 = 0;
            var flags: u32 = 0;
            if (w32.WSAGetOverlappedResult(socket, &overlapped, &transferred, w32.FALSE, &flags) == 0) {
                return connectError(wsaGetLastError());
            }
            _ = w32.setsockopt(socket, SOL_SOCKET, SO_UPDATE_CONNECT_CONTEXT, null, 0);
        },
        else => {
            // Connectionless sockets only record the peer, which does not block.
            try Thread.checkCancel();
            if (w32.connect(socket, @ptrCast(&storage), @intCast(addr_len)) != 0) return connectError(wsaGetLastError());
        },
    }
    return .{ .handle = fromSocket(socket), .address = try getSockName(socket) };
}

/// `sockaddr_un` for Windows.
const UnixSockaddr = extern struct {
    family: u16 = AF_UNIX,
    path: [108]u8,
};

fn unixSockaddr(address: *const net.UnixAddress) UnixSockaddr {
    var result: UnixSockaddr = .{ .path = @splat(0) };
    const len = @min(address.path.len, result.path.len - 1);
    @memcpy(result.path[0..len], address.path[0..len]);
    return result;
}

fn netListenUnix(
    userdata: ?*anyopaque,
    address: *const net.UnixAddress,
    options: net.UnixAddress.ListenOptions,
) net.UnixAddress.ListenError!net.Socket.Handle {
    if (!net.has_unix_sockets) return error.AddressFamilyUnsupported;
    const w = fromUserdata(userdata);
    const socket = openSocket(w, AF_UNIX, .stream, null) catch |err| switch (err) {
        error.ProtocolUnsupportedBySystem,
        error.ProtocolUnsupportedByAddressFamily,
        error.SocketModeUnsupported,
        error.OptionUnsupported,
        => return error.AddressFamilyUnsupported,
        else => |e| return e,
    };
    errdefer closeSocket(socket);
    const storage = unixSockaddr(address);
    bindSocket(socket, &storage, @sizeOf(UnixSockaddr)) catch |err| switch (err) {
        error.AddressUnavailable => return error.FileNotFound,
        else => |e| return e,
    };
    try listenSocket(socket, options.kernel_backlog);
    return fromSocket(socket);
}

fn netConnectUnix(
    userdata: ?*anyopaque,
    address: *const net.UnixAddress,
) net.UnixAddress.ConnectError!net.Socket.Handle {
    if (!net.has_unix_sockets) return error.AddressFamilyUnsupported;
    const w = fromUserdata(userdata);
    const socket = openSocket(w, AF_UNIX, .stream, null) catch |err| switch (err) {
        error.ProtocolUnsupportedByAddressFamily, error.OptionUnsupported => return error.AddressFamilyUnsupported,
        else => |e| return e,
    };
    errdefer closeSocket(socket);
    const storage = unixSockaddr(address);
    try Thread.checkCancel();
    if (w32.connect(socket, @ptrCast(&storage), @sizeOf(UnixSockaddr)) != 0) return switch (wsaGetLastError()) {
        .ECONNREFUSED => error.ConnectionRefused,
        .EACCES => error.AccessDenied,
        .ENOBUFS => error.SystemResources,
        .ENETDOWN => error.NetworkDown,
        .EADDRNOTAVAIL, .ENOENT => error.FileNotFound,
        else => |err| unexpectedWsaError(err),
    };
    return fromSocket(socket);
}

fn netSocketCreatePair(userdata: ?*anyopaque, options: net.Socket.CreatePairOptions) net.Socket.CreatePairError![2]net.Socket {
    _ = userdata;
    _ = options;
    return error.OperationUnsupported;
}

fn netClose(userdata: ?*anyopaque, sockets: []const net.Socket) void {
    _ = userdata;
    for (sockets) |socket| closeSocket(toSocket(socket.handle));
}

fn netShutdown(userdata: ?*anyopaque, handle: net.Socket.Handle, how: net.ShutdownHow) net.ShutdownError!void {
    _ = userdata;
    try Thread.checkCancel();
    const sd: i32 = switch (how) {
        .recv => 0, // SD_RECEIVE
        .send => 1, // SD_SEND
        .both => 2, // SD_BOTH
    };
    if (w32.shutdown(toSocket(handle), sd) == 0) return;
    switch (wsaGetLastError()) {
        .ENOTCONN => return error.SocketUnconnected,
        .ECONNABORTED => return error.ConnectionAborted,
        .ECONNRESET => return error.ConnectionResetByPeer,
        .ENETDOWN => return error.NetworkDown,
        .ENOBUFS => return error.SystemResources,
        else => |err| return unexpectedWsaError(err),
    }
}

fn netWriteFile(
    userdata: ?*anyopaque,
    socket_handle: net.Socket.Handle,
    header: []const u8,
    file_reader: *File.Reader,
    limit: Io.Limit,
) net.Stream.Writer.WriteFileError!usize {
    _ = userdata;
    _ = socket_handle;
    _ = header;
    _ = file_reader;
    _ = limit;
    // TODO implement netWriteFile
    return error.Unimplemented;
}

/// State of one overlapped Winsock call made with a completion routine,
/// completed during an alertable wait.
const SocketOperation = struct {
    overlapped: w32.OVERLAPPED = emptyOverlapped(null),
    done: bool = false,
    err: u32 = 0,
    bytes: u32 = 0,
    flags: u32 = 0,

    fn completion(err: u32, bytes: u32, overlapped: ?*w32.OVERLAPPED, flags: u32) callconv(.winapi) void {
        const op: *SocketOperation = @fieldParentPtr("overlapped", overlapped.?);
        op.err = err;
        op.bytes = bytes;
        op.flags = flags;
        op.done = true;
    }

    /// `rc` is the return value of the Winsock call that was given
    /// `op.overlapped` and `completion`. Returns `null` on success.
    fn finish(op: *SocketOperation, socket: w32.SOCKET, rc: i32) Io.Cancelable!?w32.WSA_ERROR {
        if (rc != 0) switch (wsaGetLastError()) {
            ._IO_PENDING => {},
            else => |err| return err,
        };
        // Even on immediate success, the completion routine is queued.
        while (!op.done) {
            const alertable_syscall = AlertableSyscall.start() catch |err| switch (err) {
                error.Canceled => |e| {
                    _ = w32.CancelIoEx(fromSocket(socket), &op.overlapped);
                    while (!op.done) waitForApc();
                    return e;
                },
            };
            waitForApc();
            alertable_syscall.finish();
        }
        return if (op.err == 0) null else wsaError(op.err);
    }
};

const max_iovecs_len = 8;

fn addWsaBuf(bufs: []w32.WSABUF, len: *u32, bytes: []const u8) void {
    if (bytes.len == 0) return;
    const cap = std.math.maxInt(u32);
    var remaining = bytes;
    while (remaining.len > cap) {
        if (bufs.len - len.* == 0) return;
        bufs[len.*] = .{ .buf = @ptrCast(@constCast(remaining.ptr)), .len = cap };
        len.* += 1;
        remaining = remaining[cap..];
    } else {
        if (bufs.len - len.* == 0) return;
        bufs[len.*] = .{ .buf = @ptrCast(@constCast(remaining.ptr)), .len = @intCast(remaining.len) };
        len.* += 1;
    }
}

fn readError(err: w32.WSA_ERROR) Io.Operation.NetRead.Error {
    return switch (err) {
        .ECONNRESET, .ECONNABORTED, .ENETRESET => error.ConnectionResetByPeer,
        .ETIMEDOUT => error.ConnectionTimedOut,
        .ENOTCONN, .ESHUTDOWN => error.SocketUnconnected,
        .ENOBUFS => error.SystemResources,
        .ENETDOWN => error.NetworkDown,
        .EACCES => error.AccessDenied,
        else => unexpectedWsaError(err),
    };
}

fn netRead(socket_handle: net.Socket.Handle, data: [][]u8) net.Stream.Reader.Error!net.Stream.ReadResult {
    var bufs: [max_iovecs_len]w32.WSABUF = undefined;
    var len: u32 = 0;
    for (data) |buf| addWsaBuf(&bufs, &len, buf);
    if (len == 0) return .{ .data_len = 0 };
    const socket = toSocket(socket_handle);
    var op: SocketOperation = .{};
    var flags: u32 = 0;
    const rc = w32.WSARecv(socket, &bufs, len, null, &flags, &op.overlapped, SocketOperation.completion);
    if (try op.finish(socket, rc)) |err| switch (err) {
        // The connection was closed gracefully.
        .EDISCON => return .{ .data_len = 0 },
        else => return readError(err),
    };
    return .{ .data_len = op.bytes };
}

fn writeError(err: w32.WSA_ERROR) Io.Operation.NetWrite.Error {
    return switch (err) {
        .ECONNRESET, .ECONNABORTED, .ENETRESET => error.ConnectionResetByPeer,
        .ENOBUFS => error.SystemResources,
        .ENETUNREACH => error.NetworkUnreachable,
        .EHOSTUNREACH => error.HostUnreachable,
        .ECONNREFUSED => error.ConnectionRefused,
        .ENOTCONN, .ESHUTDOWN => error.SocketUnconnected,
        .ETIMEDOUT => error.ConnectionTimedOut,
        .EAFNOSUPPORT => error.AddressFamilyUnsupported,
        .ENETDOWN => error.NetworkDown,
        else => unexpectedWsaError(err),
    };
}

fn netWrite(
    handle: net.Socket.Handle,
    header: []const u8,
    data: []const []const u8,
    splat: usize,
) net.Stream.Writer.Error!usize {
    var bufs: [max_iovecs_len]w32.WSABUF = undefined;
    var len: u32 = 0;
    addWsaBuf(&bufs, &len, header);
    for (data[0 .. data.len - 1]) |bytes| addWsaBuf(&bufs, &len, bytes);
    const pattern = data[data.len - 1];
    var backup_buffer: [64]u8 = undefined;
    if (bufs.len - len != 0) switch (splat) {
        0 => {},
        1 => addWsaBuf(&bufs, &len, pattern),
        else => switch (pattern.len) {
            0 => {},
            1 => {
                const splat_buffer = &backup_buffer;
                const memset_len = @min(splat_buffer.len, splat);
                const buf = splat_buffer[0..memset_len];
                @memset(buf, pattern[0]);
                addWsaBuf(&bufs, &len, buf);
                var remaining_splat = splat - buf.len;
                while (remaining_splat > splat_buffer.len and len < bufs.len) {
                    addWsaBuf(&bufs, &len, splat_buffer);
                    remaining_splat -= splat_buffer.len;
                }
                addWsaBuf(&bufs, &len, splat_buffer[0..@min(remaining_splat, splat_buffer.len)]);
            },
            else => for (0..@min(splat, bufs.len - len)) |_| {
                addWsaBuf(&bufs, &len, pattern);
            },
        },
    };
    if (len == 0) return 0;
    const socket = toSocket(handle);
    var op: SocketOperation = .{};
    const rc = w32.WSASend(socket, &bufs, len, null, 0, &op.overlapped, SocketOperation.completion);
    if (try op.finish(socket, rc)) |err| return writeError(err);
    return op.bytes;
}

fn sendError(err: w32.WSA_ERROR) net.Socket.SendError {
    return switch (err) {
        .EMSGSIZE => error.MessageOversize,
        .ENOBUFS => error.SystemResources,
        .ENETUNREACH => error.NetworkUnreachable,
        .EHOSTUNREACH => error.HostUnreachable,
        .ECONNREFUSED => error.ConnectionRefused,
        .EAFNOSUPPORT, .EFAULT => error.AddressFamilyUnsupported,
        .ECONNRESET, .ECONNABORTED, .ENETRESET => error.ConnectionResetByPeer,
        .ENOTCONN, .ESHUTDOWN => error.SocketUnconnected,
        .EACCES => error.AccessDenied,
        .ETIMEDOUT => error.ConnectionTimedOut,
        .ENETDOWN => error.NetworkDown,
        else => unexpectedWsaError(err),
    };
}

fn netSendOne(socket_handle: net.Socket.Handle, message: *net.OutgoingMessage, flags: net.SendFlags) net.Socket.SendError!void {
    var bufs: [1]w32.WSABUF = .{.{
        .buf = @ptrCast(@constCast(message.data_ptr)),
        .len = std.math.cast(u32, message.data_len) orelse return error.MessageOversize,
    }};
    var storage: PosixAddress = undefined;
    const addr_len = addressToPosix(message.address, &storage);
    const send_flags: u32 = if (flags.oob) MSG_OOB else 0;
    const socket = toSocket(socket_handle);
    var op: SocketOperation = .{};
    const rc = w32.WSASendTo(socket, &bufs, bufs.len, null, send_flags, @ptrCast(&storage), @intCast(addr_len), &op.overlapped, SocketOperation.completion);
    if (try op.finish(socket, rc)) |err| return sendError(err);
    message.data_len = op.bytes;
}

fn netSend(
    socket_handle: net.Socket.Handle,
    messages: []net.OutgoingMessage,
    flags: net.SendFlags,
) struct { ?net.Socket.SendError, usize } {
    for (messages, 0..) |*m, i| {
        netSendOne(socket_handle, m, flags) catch |err| return .{ err, i };
    }
    return .{ null, messages.len };
}

fn receiveError(err: w32.WSA_ERROR) net.Socket.ReceiveError {
    return switch (err) {
        .EMSGSIZE => error.MessageOversize,
        // For datagram sockets, an ICMP "port unreachable" response.
        .ECONNRESET => error.PortUnreachable,
        .ECONNABORTED, .ENETRESET => error.ConnectionResetByPeer,
        .ENOTCONN, .ESHUTDOWN => error.SocketUnconnected,
        .ETIMEDOUT => error.ConnectionTimedOut,
        .ENOBUFS => error.SystemResources,
        .ENETDOWN => error.NetworkDown,
        else => unexpectedWsaError(err),
    };
}

fn receiveFlags(flags: net.ReceiveFlags) u32 {
    return (if (flags.oob) MSG_OOB else 0) | (if (flags.peek) MSG_PEEK else 0);
}

fn receivedMessage(from: *const PosixAddress, data: []u8, flags: u32) net.IncomingMessage {
    return .{
        .from = addressFromPosix(from),
        .data = data,
        .control = &.{},
        .flags = .{
            .eor = false,
            .trunc = false,
            .ctrunc = false,
            .oob = flags & MSG_OOB != 0,
            .errqueue = false,
        },
    };
}

/// Receives one message, like `std.Io.Threaded` does on Windows.
fn netReceive(
    socket_handle: net.Socket.Handle,
    message_buffer: []net.IncomingMessage,
    data_buffer: []u8,
    flags: net.ReceiveFlags,
) Io.Cancelable!struct { ?net.Socket.ReceiveError, usize } {
    var bufs: [1]w32.WSABUF = .{.{
        .buf = @ptrCast(data_buffer.ptr),
        .len = std.math.cast(u32, data_buffer.len) orelse return .{ error.MessageOversize, 0 },
    }};
    var from: PosixAddress = undefined;
    var from_len: i32 = @sizeOf(PosixAddress);
    var recv_flags = receiveFlags(flags);
    const socket = toSocket(socket_handle);
    var op: SocketOperation = .{};
    const rc = w32.WSARecvFrom(socket, &bufs, bufs.len, null, &recv_flags, @ptrCast(&from), &from_len, &op.overlapped, SocketOperation.completion);
    if (try op.finish(socket, rc)) |err| return .{ receiveError(err), 0 };
    message_buffer[0] = receivedMessage(&from, data_buffer[0..op.bytes], op.flags);
    return .{ null, 1 };
}

fn netInterfaceNameResolve(
    userdata: ?*anyopaque,
    name: *const net.Interface.Name,
) net.Interface.Name.ResolveError!net.Interface {
    const w = fromUserdata(userdata);
    try Thread.checkCancel();
    const iphlpapi = w.dl.iphlpapi() orelse return error.Unexpected;
    var name_w: [net.Interface.Name.max_len:0]u16 = undefined;
    name_w[
        std.unicode.wtf8ToWtf16Le(&name_w, name.toSlice()) catch |err| switch (err) {
            error.InvalidWtf8 => return error.InterfaceNotFound,
        }
    ] = 0;
    var luid: u64 = undefined;
    switch (win32Error(iphlpapi.ConvertInterfaceNameToLuidW(&name_w, &luid))) {
        .NO_ERROR => {},
        .ERROR_INVALID_NAME => return error.InterfaceNotFound,
        else => |err| return unexpectedError(err),
    }
    var index: u32 = undefined;
    switch (win32Error(iphlpapi.ConvertInterfaceLuidToIndex(&luid, &index))) {
        .NO_ERROR => {},
        else => |err| return unexpectedError(err),
    }
    return .{ .index = index };
}

fn netInterfaceName(userdata: ?*anyopaque, interface: net.Interface) net.Interface.NameError!net.Interface.Name {
    const w = fromUserdata(userdata);
    try Thread.checkCancel();
    const iphlpapi = w.dl.iphlpapi() orelse return error.Unexpected;
    var luid: u64 = undefined;
    switch (win32Error(iphlpapi.ConvertInterfaceIndexToLuid(interface.index, &luid))) {
        .NO_ERROR => {},
        .ERROR_FILE_NOT_FOUND => return error.InterfaceNotFound,
        else => |err| return unexpectedError(err),
    }
    var name_w: [net.Interface.Name.max_len:0]u16 = undefined;
    switch (win32Error(iphlpapi.ConvertInterfaceLuidToNameW(&luid, &name_w, name_w.len))) {
        .NO_ERROR => {},
        .ERROR_NOT_ENOUGH_MEMORY => return error.NameTooLong,
        else => |err| return unexpectedError(err),
    }
    var name: [3 * net.Interface.Name.max_len]u8 = undefined;
    return .fromSlice(name[0..std.unicode.wtf16LeToWtf8(&name, std.mem.sliceTo(&name_w, 0))]);
}

/// Functions from DLLs that are loaded only when needed, like `std.Io.Threaded` does.
const Dl = struct {
    mutex: Io.Mutex = .init,
    iphlpapi_module: ?w32.HINSTANCE = null,
    iphlpapi_functions: ?Iphlpapi = null,
    dnsapi_module: ?w32.HINSTANCE = null,
    dnsapi_functions: ?Dnsapi = null,

    const Iphlpapi = struct {
        ConvertInterfaceNameToLuidW: *const fn (name: [*:0]const u16, luid: *u64) callconv(.winapi) u32,
        ConvertInterfaceLuidToIndex: *const fn (luid: *const u64, index: *u32) callconv(.winapi) u32,
        ConvertInterfaceIndexToLuid: *const fn (index: u32, luid: *u64) callconv(.winapi) u32,
        ConvertInterfaceLuidToNameW: *const fn (luid: *const u64, name: [*]u16, len: usize) callconv(.winapi) u32,
    };

    const Dnsapi = struct {
        DnsQueryEx: *const fn (
            request: *const windows.DNS.QUERY.REQUEST,
            result: *windows.DNS.QUERY.RESULT,
            cancel: ?*windows.DNS.QUERY.CANCEL,
        ) callconv(.winapi) windows.DNS.STATUS,
        DnsFree: *const fn (data: ?*anyopaque, free_type: windows.DNS.FREE_TYPE) callconv(.winapi) void,
        DnsQuery_W: *const fn (
            name: [*:0]const u16,
            record_type: windows.DNS.TYPE,
            options: windows.DNS.QUERY,
            extra: ?*anyopaque,
            results: *?*windows.DNS.RECORD,
            reserved: ?*anyopaque,
        ) callconv(.winapi) windows.DNS.STATUS,
    };

    fn deinit(dl: *Dl) void {
        if (dl.iphlpapi_module) |module| _ = w32.FreeLibrary(module);
        if (dl.dnsapi_module) |module| _ = w32.FreeLibrary(module);
        dl.* = .{};
    }

    fn load(comptime Functions: type, module_out: *?w32.HINSTANCE, comptime dll_name: []const u8) ?Functions {
        const LOAD_LIBRARY_SEARCH_SYSTEM32: u32 = 0x800;
        const module = w32.LoadLibraryExW(L(dll_name), null, @bitCast(LOAD_LIBRARY_SEARCH_SYSTEM32)) orelse return null;
        var functions: Functions = undefined;
        inline for (@typeInfo(Functions).@"struct".field_names) |name| {
            const proc = w32.GetProcAddress(module, name) orelse {
                _ = w32.FreeLibrary(module);
                return null;
            };
            @field(functions, name) = @ptrCast(proc);
        }
        module_out.* = module;
        return functions;
    }

    fn iphlpapi(dl: *Dl) ?Iphlpapi {
        mutexLockUncancelable(&dl.mutex);
        defer mutexUnlock(&dl.mutex);
        if (dl.iphlpapi_functions == null) dl.iphlpapi_functions = load(Iphlpapi, &dl.iphlpapi_module, "iphlpapi.dll");
        return dl.iphlpapi_functions;
    }

    fn dnsapi(dl: *Dl) ?Dnsapi {
        mutexLockUncancelable(&dl.mutex);
        defer mutexUnlock(&dl.mutex);
        if (dl.dnsapi_functions == null) dl.dnsapi_functions = load(Dnsapi, &dl.dnsapi_module, "dnsapi.dll");
        return dl.dnsapi_functions;
    }
};

// ---------------------------------------------------------------------------
// Host name lookup

const HostName = net.HostName;

fn netLookup(
    userdata: ?*anyopaque,
    host_name: HostName,
    resolved: *Io.Queue(HostName.LookupResult),
    options: HostName.LookupOptions,
) HostName.LookupError!void {
    const w = fromUserdata(userdata);
    defer resolved.close(w.io());
    netLookupFallible(w, host_name, resolved, options) catch |err| switch (err) {
        error.Closed => unreachable, // `resolved` must not be closed until `netLookup` returns
        else => |e| return e,
    };
}

fn copyCanon(canonical_name_buffer: ?*[HostName.max_len]u8, name: []const u8) ?HostName {
    const buf = canonical_name_buffer orelse return null;
    const dest = buf[0..name.len];
    @memcpy(dest, name);
    return .{ .bytes = dest };
}

fn netLookupFallible(
    w: *WinIo,
    host_name: HostName,
    resolved: *Io.Queue(HostName.LookupResult),
    options: HostName.LookupOptions,
) (HostName.LookupError || Io.QueueClosedError)!void {
    const w_io = w.io();
    const name = host_name.bytes;
    assert(name.len <= HostName.max_len);

    if (net.IpAddress.parseIp6(name, options.port)) |addr| {
        if (options.family == .ip4) return error.UnknownHostName;
        if (copyCanon(options.canonical_name_buffer, name)) |canon| {
            try resolved.putAll(w_io, &.{
                .{ .address = addr },
                .{ .canonical_name = canon },
            });
        } else {
            try resolved.putOne(w_io, .{ .address = addr });
        }
        return;
    } else |_| {}

    if (net.IpAddress.parseIp4(name, options.port)) |addr| {
        if (options.family == .ip6) return error.UnknownHostName;
        if (copyCanon(options.canonical_name_buffer, name)) |canon| {
            try resolved.putAll(w_io, &.{
                .{ .address = addr },
                .{ .canonical_name = canon },
            });
        } else {
            try resolved.putOne(w_io, .{ .address = addr });
        }
        return;
    } else |_| {}

    if (lookupHosts(w, host_name, resolved, options)) return else |err| switch (err) {
        error.UnknownHostName => {},
        else => |e| return e,
    }

    // RFC 6761 Section 6.3.3
    // Name resolution APIs and libraries SHOULD recognize
    // localhost names as special and SHOULD always return the IP
    // loopback address for address queries and negative responses
    // for all other query types.

    // Check for equal to "localhost(.)" or ends in ".localhost(.)"
    const localhost = if (name[name.len - 1] == '.') "localhost." else "localhost";
    if (std.mem.endsWith(u8, name, localhost) and
        (name.len == localhost.len or name[name.len - localhost.len - 1] == '.'))
    {
        var results_buffer: [3]HostName.LookupResult = undefined;
        var results_index: usize = 0;
        if (options.family != .ip4) {
            results_buffer[results_index] = .{ .address = .{ .ip6 = .loopback(options.port) } };
            results_index += 1;
        }
        if (options.family != .ip6) {
            results_buffer[results_index] = .{ .address = .{ .ip4 = .loopback(options.port) } };
            results_index += 1;
        }
        if (options.canonical_name_buffer) |buf| {
            const canon_name = "localhost";
            const canon_name_dest = buf[0..canon_name.len];
            canon_name_dest.* = canon_name.*;
            results_buffer[results_index] = .{ .canonical_name = .{ .bytes = canon_name_dest } };
            results_index += 1;
        }
        try resolved.putAll(w_io, results_buffer[0..results_index]);
        return;
    }

    try Thread.checkCancel();
    const dnsapi = w.dl.dnsapi() orelse return error.DetectingNetworkConfigurationFailed;
    const current_thread = Thread.current;
    var lookup_dns: LookupDns = .{
        .win_io = w,
        .dnsapi = dnsapi,
        .thread = if (current_thread) |thread| thread.handle else undefined,
        .resolved = resolved,
        .options = options,
        .results = .{
            .Version = 1,
            .QueryStatus = undefined,
            .QueryOptions = undefined,
            .pQueryRecords = undefined,
            .Reserved = undefined,
        },
        .done = false,
    };
    var host_name_w: [HostName.max_len:0]u16 = undefined;
    host_name_w[
        std.unicode.wtf8ToWtf16Le(&host_name_w, name) catch |err| switch (err) {
            error.InvalidWtf8 => return error.UnknownHostName,
        }
    ] = 0;
    // Workaround various bugs by attempting a synchronous non-wire query first
    switch (dnsapi.DnsQueryEx(&.{
        .Version = 1,
        .QueryName = &host_name_w,
        .QueryType = if (options.family == .ip4) .A else .AAAA,
        .QueryOptions = .{
            .NO_WIRE_QUERY = true,
            .NO_HOSTS_FILE = true, // handled above
            .ADDRCONFIG = true,
            .DUAL_ADDR = options.family == null,
        },
    }, &lookup_dns.results, null)) {
        .SUCCESS => try lookup_dns.completedFallible(),
        .DNS_REQUEST_PENDING => unreachable, // `pQueryCompletionCallback` was `null`
        // `DnsQueryEx` is not implemented by Wine.
        .DNS_ERROR_RCODE_NOT_IMPLEMENTED, .CALL_NOT_IMPLEMENTED => return lookupDnsQuery(w, dnsapi, &host_name_w, resolved, options),
        .DNS_ERROR_RECORD_DOES_NOT_EXIST => switch (dnsapi.DnsQueryEx(&.{
            .Version = 1,
            .QueryName = &host_name_w,
            .QueryType = if (options.family == .ip4) .A else .AAAA,
            .QueryOptions = .{
                .NO_HOSTS_FILE = true, // handled above
                .ADDRCONFIG = true,
                .DUAL_ADDR = options.family == null,
                .MULTICAST_WAIT = true,
            },
            .pQueryCompletionCallback = if (current_thread) |_| &LookupDns.completed else null,
        }, &lookup_dns.results, null)) {
            .SUCCESS => try lookup_dns.completedFallible(),
            // We must wait for the completion callback.
            .DNS_REQUEST_PENDING => {
                assert(current_thread != null); // `pQueryCompletionCallback` was `null`
                while (!@atomicLoad(bool, &lookup_dns.done, .acquire)) {
                    // Once we get here we must not return from the function until the
                    // operation completes, thereby releasing references to `host_name_w`
                    // and `lookup_dns.results`.
                    const alertable_syscall = AlertableSyscall.start() catch |err| switch (err) {
                        error.Canceled => |e| {
                            while (!@atomicLoad(bool, &lookup_dns.done, .acquire)) waitForApc();
                            return e;
                        },
                    };
                    waitForApc();
                    alertable_syscall.finish();
                }
            },
            else => |status| lookup_dns.results.QueryStatus = status,
        },
        else => |status| lookup_dns.results.QueryStatus = status,
    }
    switch (lookup_dns.results.QueryStatus) {
        .SUCCESS => return,
        .DNS_REQUEST_PENDING => unreachable, // already handled
        .INVALID_NAME,
        .DNS_ERROR_RCODE_NAME_ERROR,
        .DNS_INFO_NO_RECORDS,
        .DNS_ERROR_INVALID_NAME_CHAR,
        .DNS_ERROR_RECORD_DOES_NOT_EXIST,
        => return error.UnknownHostName,
        .TIMEOUT,
        .DNS_ERROR_RCODE_FORMAT_ERROR,
        .DNS_ERROR_RCODE_SERVER_FAILURE,
        .DNS_ERROR_RCODE_NOT_IMPLEMENTED,
        .DNS_ERROR_RCODE_REFUSED,
        .DNS_ERROR_NO_DNS_SERVERS,
        => return error.NameServerFailure,
        else => |err| return windows.unexpectedError(err),
    }
}

/// Synchronous lookup with `DnsQuery_W`, for when `DnsQueryEx` is unavailable.
fn lookupDnsQuery(
    w: *WinIo,
    dnsapi: Dl.Dnsapi,
    host_name_w: [*:0]const u16,
    resolved: *Io.Queue(HostName.LookupResult),
    options: HostName.LookupOptions,
) (HostName.LookupError || Io.QueueClosedError)!void {
    const w_io = w.io();
    const types: []const windows.DNS.TYPE = if (options.family) |family| switch (family) {
        .ip4 => &.{.A},
        .ip6 => &.{.AAAA},
    } else &.{ .AAAA, .A };
    var addresses_len: usize = 0;
    var canonical_name: ?HostName = null;
    for (types) |record_type| {
        var records: ?*windows.DNS.RECORD = null;
        const syscall: Syscall = try .start();
        const status = dnsapi.DnsQuery_W(host_name_w, record_type, .{ .NO_HOSTS_FILE = true }, null, &records, null);
        syscall.finish();
        defer if (records) |r| dnsapi.DnsFree(r, .RecordList);
        switch (status) {
            .SUCCESS => {},
            .INVALID_NAME,
            .DNS_ERROR_RCODE_NAME_ERROR,
            .DNS_INFO_NO_RECORDS,
            .DNS_ERROR_INVALID_NAME_CHAR,
            .DNS_ERROR_RECORD_DOES_NOT_EXIST,
            => continue,
            .TIMEOUT,
            .DNS_ERROR_RCODE_FORMAT_ERROR,
            .DNS_ERROR_RCODE_SERVER_FAILURE,
            .DNS_ERROR_RCODE_NOT_IMPLEMENTED,
            .DNS_ERROR_RCODE_REFUSED,
            .DNS_ERROR_NO_DNS_SERVERS,
            => return error.NameServerFailure,
            else => |err| return windows.unexpectedError(err),
        }
        var record_it = records;
        while (record_it) |record| : (record_it = record.pNext) {
            if (record.wType != record_type) continue;
            try resolved.putOne(w_io, .{ .address = switch (record_type) {
                .A => .{ .ip4 = .{ .bytes = record.Data.A, .port = options.port } },
                .AAAA => r: {
                    const ip6: net.Ip6Address = .{ .bytes = record.Data.AAAA, .port = options.port };
                    break :r if (options.family) |_| .{ .ip6 = ip6 } else .fromIp6(ip6);
                },
                else => unreachable,
            } });
            addresses_len += 1;
        }
        if (canonical_name == null) if (records) |record| if (options.canonical_name_buffer) |buf| {
            const name_wtf16 = std.mem.span(@as([*:0]const u16, @ptrCast(@alignCast(record.pName))));
            const len = std.unicode.wtf16LeToWtf8(buf, name_wtf16);
            canonical_name = .{ .bytes = buf[0..len] };
        };
    }
    if (canonical_name) |name| try resolved.putOne(w_io, .{ .canonical_name = name });
    if (addresses_len == 0) return error.UnknownHostName;
}

const LookupDns = struct {
    win_io: *WinIo,
    dnsapi: Dl.Dnsapi,
    thread: w32.HANDLE,
    resolved: *Io.Queue(HostName.LookupResult),
    options: HostName.LookupOptions,
    results: windows.DNS.QUERY.RESULT,
    done: bool,

    fn completed(
        pQueryContext: ?*anyopaque,
        pQueryResults: *windows.DNS.QUERY.RESULT,
    ) callconv(.winapi) void {
        _ = pQueryContext;
        const lookup_dns: *LookupDns = @fieldParentPtr("results", pQueryResults);
        lookup_dns.completedFallible() catch |err| switch (err) {
            error.Closed => unreachable, // `resolved` must not be closed until `netLookup` returns
            error.Canceled => unreachable, // called from an uncancelable thread
        };
        const thread = lookup_dns.thread;
        @atomicStore(bool, &lookup_dns.done, true, .release);
        // Wake the waiting thread from its alertable wait.
        _ = w32.QueueUserAPC(Thread.noopApc, thread, 0);
    }

    fn completedFallible(lookup_dns: *LookupDns) (Io.QueueClosedError || Io.Cancelable)!void {
        assert(!lookup_dns.done);
        defer lookup_dns.dnsapi.DnsFree(lookup_dns.results.pQueryRecords, .RecordList);
        if (lookup_dns.results.QueryStatus != .SUCCESS) return;
        const w_io = lookup_dns.win_io.io();
        var record_it = lookup_dns.results.pQueryRecords;
        while (record_it) |record| : (record_it = record.pNext) switch (record.wType) {
            else => {},
            .A => try lookup_dns.resolved.putOne(w_io, .{
                .address = .{ .ip4 = .{ .bytes = record.Data.A, .port = lookup_dns.options.port } },
            }),
            .AAAA => {
                const ip6: net.Ip6Address = .{
                    .bytes = record.Data.AAAA,
                    .port = lookup_dns.options.port,
                };
                try lookup_dns.resolved.putOne(w_io, .{
                    .address = if (lookup_dns.options.family) |_| .{ .ip6 = ip6 } else .fromIp6(ip6),
                });
            },
        };
        if (lookup_dns.results.pQueryRecords) |record| {
            if (lookup_dns.options.canonical_name_buffer) |buf| {
                const name_wtf16 = std.mem.span(@as([*:0]const u16, @ptrCast(@alignCast(record.pName))));
                const len = std.unicode.wtf16LeToWtf8(buf, name_wtf16);
                try lookup_dns.resolved.putOne(w_io, .{
                    .canonical_name = .{ .bytes = buf[0..len] },
                });
            }
        }
    }
};

fn lookupHosts(
    w: *WinIo,
    host_name: HostName,
    resolved: *Io.Queue(HostName.LookupResult),
    options: HostName.LookupOptions,
) !void {
    var path: WindowsPath = undefined;
    const n = w32.GetSystemDirectoryW(&path.data, path.data.len);
    if (n == 0 or n >= path.data.len) return error.DetectingNetworkConfigurationFailed;
    path.len = n;
    path.set(&.{ path.data[0..n], L("\\drivers\\etc\\hosts") }) catch return error.DetectingNetworkConfigurationFailed;
    var full: WindowsPath = undefined;
    setVerbatim(&full, path.data[0..path.len]) catch return error.DetectingNetworkConfigurationFailed;
    const handle = createFile(full.span(), .{
        .access = GENERIC_READ | SYNCHRONIZE,
        .creation = .OPEN_EXISTING,
        .filter = .file_only,
    }) catch |err| switch (err) {
        error.FileNotFound,
        error.NotDir,
        error.AccessDenied,
        => return error.UnknownHostName,

        error.Canceled => |e| return e,

        else => {
            // Here we could add more detailed diagnostics to the results queue.
            return error.DetectingNetworkConfigurationFailed;
        },
    };
    const file: File = .{ .handle = handle, .flags = .{ .nonblocking = false } };
    defer _ = w32.CloseHandle(handle);

    var line_buf: [512]u8 = undefined;
    var file_reader = file.reader(w.io(), &line_buf);
    return lookupHostsReader(w, host_name, resolved, options, &file_reader.interface) catch |err| switch (err) {
        error.ReadFailed => switch (file_reader.err.?) {
            error.Canceled => |e| return e,
            else => {
                // Here we could add more detailed diagnostics to the results queue.
                return error.DetectingNetworkConfigurationFailed;
            },
        },
        error.Canceled,
        error.Closed,
        error.UnknownHostName,
        => |e| return e,
    };
}

fn lookupHostsReader(
    w: *WinIo,
    host_name: HostName,
    resolved: *Io.Queue(HostName.LookupResult),
    options: HostName.LookupOptions,
    reader: *Io.Reader,
) error{ ReadFailed, Canceled, UnknownHostName, Closed }!void {
    const w_io = w.io();
    var addresses_len: usize = 0;
    var canonical_name: ?HostName = null;
    while (true) {
        const line = reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                // Skip lines that are too long.
                _ = reader.discardDelimiterInclusive('\n') catch |er| switch (er) {
                    error.EndOfStream => break,
                    error.ReadFailed => |e| return e,
                };
                continue;
            },
            error.ReadFailed => |e| return e,
            error.EndOfStream => break,
        };
        reader.toss(@min(1, reader.bufferedLen()));
        var split_it = std.mem.splitScalar(u8, if (std.mem.endsWith(u8, line, "\r"))
            line[0 .. line.len - 1]
        else
            line, '#');
        const no_comment_line = split_it.first();

        var line_it = std.mem.tokenizeAny(u8, no_comment_line, " \t");
        const ip_text = line_it.next() orelse continue;
        var first_name_text: ?[]const u8 = null;
        while (line_it.next()) |name_text| {
            if (std.ascii.eqlIgnoreCase(name_text, host_name.bytes)) {
                if (first_name_text == null) first_name_text = name_text;
                break;
            }
        } else continue;

        if (canonical_name == null) {
            if (options.canonical_name_buffer) |buf| {
                if (HostName.init(first_name_text.?)) |name_text| {
                    if (name_text.bytes.len <= buf.len) {
                        const canonical_name_dest = buf[0..name_text.bytes.len];
                        @memcpy(canonical_name_dest, name_text.bytes);
                        canonical_name = .{ .bytes = canonical_name_dest };
                    }
                } else |_| {}
            }
        }

        if (options.family != .ip6) {
            if (net.IpAddress.parseIp4(ip_text, options.port)) |addr| {
                try resolved.putOne(w_io, .{ .address = addr });
                addresses_len += 1;
            } else |_| {}
        }
        if (options.family != .ip4) {
            if (net.IpAddress.parseIp6(ip_text, options.port)) |addr| {
                try resolved.putOne(w_io, .{ .address = addr });
                addresses_len += 1;
            } else |_| {}
        }
    }

    if (canonical_name) |canon_name| try resolved.putOne(w_io, .{ .canonical_name = canon_name });
    if (addresses_len == 0) return error.UnknownHostName;
}

// ---------------------------------------------------------------------------
// Process

const process = std.process;

fn getStdHandle(which: w32.STD_HANDLE) ?w32.HANDLE {
    const handle = w32.GetStdHandle(which);
    if (isInvalidHandle(handle)) return null;
    return handle;
}

/// Reads an environment variable of this process into `buffer`.
fn getEnvironmentVariable(comptime name: []const u8, buffer: []u16) ?[:0]u16 {
    const n = w32.GetEnvironmentVariableW(L(name), @ptrCast(buffer.ptr), @intCast(buffer.len));
    if (n == 0 or n >= buffer.len) return null;
    buffer[n] = 0;
    return buffer[0..n :0];
}

/// Whether an environment variable of this process exists, if the `Io` was
/// given the process environment (like `std.Io.Threaded` scanning
/// `process_environ`).
fn environExists(w: *WinIo, comptime name: []const u8) bool {
    if (!w.process_environ.block.use_global) return false;
    var buffer: [1]u16 = undefined;
    _ = w32.GetEnvironmentVariableW(L(name), @ptrCast(&buffer), buffer.len);
    return getLastError() != .ERROR_ENVVAR_NOT_FOUND;
}

/// Returns the path of the executable from `GetModuleFileNameW`.
fn moduleFileName(out: *WindowsPath) error{NameTooLong}!void {
    const n = w32.GetModuleFileNameW(null, &out.data, out.data.len);
    if (n == 0 or n >= out.data.len) return error.NameTooLong;
    out.len = n;
    out.data[n] = 0;
}

fn processExecutableOpen(userdata: ?*anyopaque, flags: Dir.OpenFileOptions) process.OpenExecutableError!File {
    _ = userdata;
    // If the module path is a symlink, it contains the path of the symlink,
    // but opening the file follows it.
    var module: WindowsPath = undefined;
    try moduleFileName(&module);
    var path: WindowsPath = undefined;
    try resolveWindowsPath(.cwd(), module.span(), &path);
    return openFileWindows(path.span(), flags);
}

fn processExecutablePath(userdata: ?*anyopaque, out_buffer: []u8) process.ExecutablePathError!usize {
    _ = userdata;
    // If the module path is a symlink, it contains the path of the symlink,
    // but we want the path that the symlink points to.
    var module: WindowsPath = undefined;
    try moduleFileName(&module);
    var path: WindowsPath = undefined;
    try resolveWindowsPath(.cwd(), module.span(), &path);
    const handle = createFile(path.span(), .{
        .access = FILE_READ_ATTRIBUTES | SYNCHRONIZE,
        .creation = .OPEN_EXISTING,
    }) catch |err| switch (err) {
        error.WouldBlock, error.FileLocksUnsupported => unreachable,
        error.ReadOnlyFileSystem, error.FileBusy => return error.Unexpected,
        else => |e| return e,
    };
    defer _ = w32.CloseHandle(handle);
    return realPathWindows(handle, out_buffer) catch |err| switch (err) {
        error.FileBusy => return error.Unexpected,
        else => |e| return e,
    };
}

fn processCurrentPath(userdata: ?*anyopaque, buffer: []u8) process.CurrentPathError!usize {
    _ = userdata;
    var cwd: WindowsPath = undefined;
    const n = w32.GetCurrentDirectoryW(cwd.data.len, &cwd.data);
    if (n == 0 or n >= cwd.data.len) return error.Unexpected;
    var end_index: usize = 0;
    var it = std.unicode.Wtf16LeIterator.init(cwd.data[0..n]);
    while (it.nextCodepoint()) |codepoint| {
        const seq_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
        if (end_index + seq_len >= buffer.len)
            return error.NameTooLong;
        end_index += std.unicode.wtf8Encode(codepoint, buffer[end_index..]) catch unreachable;
    }
    return end_index;
}

fn setCurrentDirectory(path: [:0]const u16) (Io.Cancelable || Io.UnexpectedError || error{
    BadPathName,
    FileNotFound,
    NoDevice,
    AccessDenied,
    NotDir,
    NameTooLong,
})!void {
    const syscall: Syscall = try .start();
    while (w32.SetCurrentDirectoryW(path.ptr) == 0) switch (getLastError()) {
        .ERROR_OPERATION_ABORTED => try syscall.checkCancel(),
        .ERROR_INVALID_NAME, .ERROR_BAD_PATHNAME => return syscall.fail(error.BadPathName),
        .ERROR_FILE_NOT_FOUND, .ERROR_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
        .ERROR_NOT_READY => return syscall.fail(error.NoDevice),
        .ERROR_ACCESS_DENIED => return syscall.fail(error.AccessDenied),
        .ERROR_DIRECTORY => return syscall.fail(error.NotDir),
        .ERROR_FILENAME_EXCED_RANGE => return syscall.fail(error.NameTooLong),
        else => |err| return syscall.unexpectedError(err),
    };
    syscall.finish();
}

fn processSetCurrentDir(userdata: ?*anyopaque, dir: Dir) process.SetCurrentDirError!void {
    _ = userdata;
    var path: WindowsPath = undefined;
    dirPath(dir, &path) catch |err| switch (err) {
        error.AccessDenied, error.FileNotFound, error.NameTooLong, error.BadPathName, error.Unexpected => |e| return e,
    };
    // `SetCurrentDirectoryW` does not take `\\?\` paths.
    path.len = (stripVerbatim(path.data[0..path.len], &path.data) catch unreachable).len;
    path.data[path.len] = 0;
    return setCurrentDirectory(path.span());
}

fn processSetCurrentPath(userdata: ?*anyopaque, path: []const u8) process.SetCurrentPathError!void {
    _ = userdata;
    var path_w: WindowsPath = undefined;
    const len = std.unicode.calcWtf16LeLen(path) catch return error.InvalidWtf8;
    if (len > PATH_MAX_WIDE) return error.NameTooLong;
    path_w.len = std.unicode.wtf8ToWtf16Le(&path_w.data, path) catch |err| switch (err) {
        error.InvalidWtf8 => unreachable, // already validated
    };
    path_w.data[path_w.len] = 0;
    return setCurrentDirectory(path_w.span());
}

fn processReplace(userdata: ?*anyopaque, options: process.ReplaceOptions) process.ReplaceError {
    _ = userdata;
    _ = options;
    return error.OperationUnsupported; // `process.can_replace` is false on Windows.
}

fn lockStderr(userdata: ?*anyopaque, terminal_mode: ?Io.Terminal.Mode) Io.Cancelable!Io.LockedStderr {
    const w = fromUserdata(userdata);
    const current_thread_id = w32.GetCurrentThreadId();

    if (@atomicLoad(u32, &w.stderr_mutex_locker, .unordered) != current_thread_id) {
        try mutexLock(&w.stderr_mutex);
        assert(w.stderr_mutex_lock_count == 0);
        @atomicStore(u32, &w.stderr_mutex_locker, current_thread_id, .unordered);
    }
    w.stderr_mutex_lock_count += 1;

    return initLockedStderr(w, terminal_mode);
}

fn tryLockStderr(userdata: ?*anyopaque, terminal_mode: ?Io.Terminal.Mode) Io.Cancelable!?Io.LockedStderr {
    const w = fromUserdata(userdata);
    const current_thread_id = w32.GetCurrentThreadId();

    if (@atomicLoad(u32, &w.stderr_mutex_locker, .unordered) != current_thread_id) {
        if (!w.stderr_mutex.tryLock()) return null;
        assert(w.stderr_mutex_lock_count == 0);
        @atomicStore(u32, &w.stderr_mutex_locker, current_thread_id, .unordered);
    }
    w.stderr_mutex_lock_count += 1;

    return try initLockedStderr(w, terminal_mode);
}

fn initLockedStderr(w: *WinIo, terminal_mode: ?Io.Terminal.Mode) Io.Cancelable!Io.LockedStderr {
    if (!w.stderr_writer_initialized) {
        const w_io = w.io();
        w.stderr_writer.file = .{
            .handle = getStdHandle(w32.STD_ERROR_HANDLE) orelse undefined,
            .flags = .{ .nonblocking = false },
        };
        w.stderr_writer.io = w_io;
        w.stderr_writer_initialized = true;
        const NO_COLOR = environExists(w, "NO_COLOR");
        const CLICOLOR_FORCE = environExists(w, "CLICOLOR_FORCE");
        w.stderr_mode = terminal_mode orelse try .detect(w_io, w.stderr_writer.file, NO_COLOR, CLICOLOR_FORCE);
    }
    return .{
        .file_writer = &w.stderr_writer,
        .terminal_mode = terminal_mode orelse w.stderr_mode,
    };
}

fn unlockStderr(userdata: ?*anyopaque) void {
    const w = fromUserdata(userdata);
    if (w.stderr_writer.err == null) w.stderr_writer.interface.flush() catch {};
    if (w.stderr_writer.err) |err| {
        switch (err) {
            error.Canceled => recancelInner(),
            else => {},
        }
        w.stderr_writer.err = null;
    }
    w.stderr_writer.interface.end = 0;
    w.stderr_writer.interface.buffer = &.{};

    w.stderr_mutex_lock_count -= 1;
    if (w.stderr_mutex_lock_count == 0) {
        @atomicStore(u32, &w.stderr_mutex_locker, 0, .unordered);
        mutexUnlock(&w.stderr_mutex);
    }
}

fn progressParentFile(userdata: ?*anyopaque) std.Progress.ParentFileError!File {
    const w = fromUserdata(userdata);
    if (!w.process_environ.block.use_global) return error.EnvironmentVariableMissing;
    var value_w: [32]u16 = undefined;
    const value = getEnvironmentVariable("ZIG_PROGRESS", &value_w) orelse return error.EnvironmentVariableMissing;
    var value_buf: [std.fmt.count("{d}", .{std.math.maxInt(usize)})]u8 = undefined;
    if (std.unicode.calcWtf8Len(value) > value_buf.len) return error.UnrecognizedFormat;
    const len = std.unicode.wtf16LeToWtf8(&value_buf, value);
    return .{
        .handle = @ptrFromInt(std.fmt.parseInt(usize, value_buf[0..len], 10) catch return error.UnrecognizedFormat),
        .flags = .{ .nonblocking = true },
    };
}

const HANDLE_FLAG_INHERIT: u32 = 0x1;

fn setInheritable(handle: w32.HANDLE, inherit: bool) Io.UnexpectedError!void {
    if (w32.SetHandleInformation(handle, HANDLE_FLAG_INHERIT, @bitCast(@as(u32, @intFromBool(inherit)))) == 0) {
        return unexpectedError(getLastError());
    }
}

fn inheritParentDir(userdata: ?*anyopaque, handle: Dir.Handle) Io.InheritParentHandleError!Dir {
    _ = userdata;
    try setInheritable(handle, false);
    return .{ .handle = handle };
}

fn inheritParentFile(userdata: ?*anyopaque, handle: File.Handle, flags: File.Flags) Io.InheritParentHandleError!File {
    _ = userdata;
    try setInheritable(handle, false);
    return .{ .handle = handle, .flags = flags };
}

// ---------------------------------------------------------------------------
// Child processes

const STARTUPINFOW = extern struct {
    cb: u32,
    lpReserved: ?[*:0]u16 = null,
    lpDesktop: ?[*:0]u16 = null,
    lpTitle: ?[*:0]u16 = null,
    dwX: u32 = 0,
    dwY: u32 = 0,
    dwXSize: u32 = 0,
    dwYSize: u32 = 0,
    dwXCountChars: u32 = 0,
    dwYCountChars: u32 = 0,
    dwFillAttribute: u32 = 0,
    dwFlags: u32,
    wShowWindow: u16 = 0,
    cbReserved2: u16 = 0,
    lpReserved2: ?*u8 = null,
    hStdInput: ?w32.HANDLE,
    hStdOutput: ?w32.HANDLE,
    hStdError: ?w32.HANDLE,
};

const PROCESS_INFORMATION = extern struct {
    hProcess: w32.HANDLE,
    hThread: w32.HANDLE,
    dwProcessId: u32,
    dwThreadId: u32,
};

const STARTF_USESTDHANDLES: u32 = 0x100;
const CREATE_SUSPENDED: u32 = 0x4;
const CREATE_UNICODE_ENVIRONMENT: u32 = 0x400;
const CREATE_NO_WINDOW: u32 = 0x08000000;

const process_externs = struct {
    extern "kernel32" fn CreateProcessW(
        lpApplicationName: ?[*:0]const u16,
        lpCommandLine: ?[*:0]u16,
        lpProcessAttributes: ?*anyopaque,
        lpThreadAttributes: ?*anyopaque,
        bInheritHandles: w32.BOOL,
        dwCreationFlags: u32,
        lpEnvironment: ?*const anyopaque,
        lpCurrentDirectory: ?[*:0]const u16,
        lpStartupInfo: *STARTUPINFOW,
        lpProcessInformation: *PROCESS_INFORMATION,
    ) callconv(.winapi) w32.BOOL;
};

/// Returns a handle to the NUL device, opened once and inheritable.
fn getNulDevice(w: *WinIo) !w32.HANDLE {
    {
        try mutexLock(&w.mutex);
        defer mutexUnlock(&w.mutex);
        if (w.null_handle) |handle| return handle;
    }
    var sa: w32.SECURITY_ATTRIBUTES = .{ .nLength = @sizeOf(w32.SECURITY_ATTRIBUTES), .lpSecurityDescriptor = null, .bInheritHandle = w32.TRUE };
    const syscall: Syscall = try .start();
    const fresh_handle = w32.CreateFileW(L("\\\\.\\NUL"), @bitCast(GENERIC_READ | GENERIC_WRITE), @bitCast(FILE_SHARE_ALL), &sa, .OPEN_EXISTING, @bitCast(FILE_ATTRIBUTE_NORMAL), null);
    syscall.finish();
    if (isInvalidHandle(fresh_handle)) return switch (getLastError()) {
        .ERROR_FILE_NOT_FOUND, .ERROR_PATH_NOT_FOUND => error.FileNotFound,
        .ERROR_ACCESS_DENIED => error.AccessDenied,
        else => |err| unexpectedError(err),
    };
    mutexLockUncancelable(&w.mutex); // Another thread might have won the race.
    defer mutexUnlock(&w.mutex);
    if (w.null_handle) |prev_handle| {
        _ = w32.CloseHandle(fresh_handle);
        return prev_handle;
    }
    w.null_handle = fresh_handle;
    return fresh_handle;
}

const CreatePipeOptions = struct {
    /// The server end is overlapped (`File.Flags.nonblocking`).
    server_overlapped: bool,
    /// The client end is overlapped.
    client_overlapped: bool = false,
    /// Data flows from the client to the server.
    inbound: bool,
    quota: u32 = 4096,
};

/// Creates a pipe with a unique name. Returns the server and client ends;
/// only the client end is inheritable.
fn createPipe(options: CreatePipeOptions) ![2]w32.HANDLE {
    const global = struct {
        var counter: std.atomic.Value(u32) = .init(0);
    };
    var name_buf: [64]u8 = undefined;
    const name = std.fmt.bufPrint(&name_buf, "\\\\.\\pipe\\zig-io-{d}-{d}", .{
        w32.GetCurrentProcessId(),
        global.counter.fetchAdd(1, .monotonic),
    }) catch unreachable;
    var name_w: [64:0]u16 = undefined;
    name_w[std.unicode.wtf8ToWtf16Le(&name_w, name) catch unreachable] = 0;

    const PIPE_ACCESS_INBOUND: u32 = 0x1;
    const PIPE_ACCESS_OUTBOUND: u32 = 0x2;
    const FILE_FLAG_FIRST_PIPE_INSTANCE: u32 = 0x00080000;
    const FILE_FLAG_OVERLAPPED: u32 = 0x40000000;
    const open_mode = (if (options.inbound) PIPE_ACCESS_INBOUND else PIPE_ACCESS_OUTBOUND) |
        FILE_FLAG_FIRST_PIPE_INSTANCE |
        if (options.server_overlapped) FILE_FLAG_OVERLAPPED else 0;
    const syscall: Syscall = try .start();
    const server = w32.CreateNamedPipeW(
        &name_w,
        @bitCast(open_mode),
        @bitCast(@as(u32, 0)), // PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT
        1,
        if (options.inbound) 0 else options.quota,
        if (options.inbound) options.quota else 0,
        120 * std.time.ms_per_s,
        null,
    );
    syscall.finish();
    if (isInvalidHandle(server)) return switch (getLastError()) {
        .ERROR_NOT_ENOUGH_MEMORY, .ERROR_NO_SYSTEM_RESOURCES => error.SystemResources,
        else => |err| unexpectedError(err),
    };
    errdefer _ = w32.CloseHandle(server);

    var sa: w32.SECURITY_ATTRIBUTES = .{ .nLength = @sizeOf(w32.SECURITY_ATTRIBUTES), .lpSecurityDescriptor = null, .bInheritHandle = w32.TRUE };
    const client_access = (if (options.inbound) GENERIC_WRITE else GENERIC_READ) | FILE_WRITE_ATTRIBUTES | SYNCHRONIZE;
    const client_flags: u32 = if (options.client_overlapped) FILE_FLAG_OVERLAPPED else FILE_ATTRIBUTE_NORMAL;
    const client = w32.CreateFileW(&name_w, @bitCast(client_access), @bitCast(@as(u32, 0)), &sa, .OPEN_EXISTING, @bitCast(client_flags), null);
    if (isInvalidHandle(client)) return switch (getLastError()) {
        .ERROR_NOT_ENOUGH_MEMORY, .ERROR_NO_SYSTEM_RESOURCES => error.SystemResources,
        else => |err| unexpectedError(err),
    };
    return .{ server, client };
}

/// Creates an inheritable duplicate of `handle` for a child process.
fn duplicateInheritable(handle: w32.HANDLE) Io.UnexpectedError!w32.HANDLE {
    var result: ?w32.HANDLE = null;
    const process_handle = w32.GetCurrentProcess();
    const DUPLICATE_SAME_ACCESS: u32 = 0x2;
    if (w32.DuplicateHandle(process_handle, handle, process_handle, &result, 0, w32.TRUE, @bitCast(DUPLICATE_SAME_ACCESS)) == 0) {
        return unexpectedError(getLastError());
    }
    return result.?;
}

/// Builds the environment block for a child from this process's environment,
/// replacing `ZIG_PROGRESS` like `std.process.Environ.createWindowsBlock`.
fn createEnvironmentBlock(
    w: *WinIo,
    arena: Allocator,
    zig_progress_handle: ?w32.HANDLE,
) Allocator.Error!process.Environ.WindowsBlock {
    if (!w.process_environ.block.use_global) return .{
        .slice = try arena.dupeSentinel(u16, process.Environ.WindowsBlock.empty.slice, 0),
    };
    const strings = w32.GetEnvironmentStringsW() orelse return error.OutOfMemory;
    defer _ = w32.FreeEnvironmentStringsW(@ptrCast(strings));
    const existing: [*:0]const u16 = @ptrCast(strings);
    const zig_progress_key = L("ZIG_PROGRESS=");

    var list: std.ArrayList(u16) = .empty;
    if (zig_progress_handle) |handle| {
        var value_buf: [std.fmt.count("ZIG_PROGRESS={d}", .{std.math.maxInt(usize)})]u8 = undefined;
        const entry = std.fmt.bufPrint(&value_buf, "ZIG_PROGRESS={d}", .{@intFromPtr(handle)}) catch unreachable;
        for (entry) |c| try list.append(arena, c);
        try list.append(arena, 0);
    }
    var i: usize = 0;
    while (existing[i] != 0) {
        const entry = std.mem.sliceTo(existing[i..], 0);
        i += entry.len + 1;
        const is_zig_progress = entry.len >= zig_progress_key.len and
            windows.eqlIgnoreCaseWtf16(entry[0..zig_progress_key.len], zig_progress_key);
        if (zig_progress_handle != null and is_zig_progress) continue;
        try list.appendSlice(arena, entry);
        try list.append(arena, 0);
    }
    // An empty environment requires a redundant NUL terminator.
    if (list.items.len == 0) try list.append(arena, 0);
    try list.append(arena, 0);
    return .{ .slice = list.items[0 .. list.items.len - 1 :0] };
}

fn processSpawn(userdata: ?*anyopaque, options: process.SpawnOptions) process.SpawnError!process.Child {
    const w = fromUserdata(userdata);

    var arena_allocator = std.heap.ArenaAllocator.init(w.allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    const cwd_w: ?[:0]u16 = cwd_w: switch (options.cwd) {
        .inherit => null,
        .dir => |cwd_dir| {
            var dir_path: WindowsPath = undefined;
            dirPath(cwd_dir, &dir_path) catch |err| switch (err) {
                error.AccessDenied, error.FileNotFound, error.NameTooLong, error.BadPathName, error.Unexpected => |e| return e,
            };
            const stripped = stripVerbatim(dir_path.data[0..dir_path.len], &dir_path.data) catch unreachable;
            break :cwd_w try arena.dupeSentinel(u16, stripped, 0);
        },
        .path => |cwd| try std.unicode.wtf8ToWtf16LeAllocZ(arena, cwd),
    };
    const cwd_w_ptr = if (cwd_w) |cwd| cwd.ptr else null;

    // If the app name has more than just a filename, then we need to separate
    // that into the basename and dirname and use the dirname as an addition to
    // the cwd path, because the search uses `FindFirstFileExW` with a wildcard
    // appended to the file name.
    var app_path_buf: WindowsPath = undefined;
    const app_path_w: ?[]const u16, const app_dir_w: ?[]const u16, const app_name_w: []const u16 = app: {
        const path = switch (options.exe) {
            .detect, .search, .path => options.argv[0],
            .file => |file| {
                var file_path: WindowsPath = undefined;
                dirPath(.{ .handle = file.handle }, &file_path) catch |err| switch (err) {
                    error.AccessDenied, error.FileNotFound, error.NameTooLong, error.BadPathName, error.Unexpected => |e| return e,
                };
                const path_w = try arena.dupe(u16, stripVerbatim(file_path.data[0..file_path.len], &file_path.data) catch unreachable);
                var path_it: Dir.path.ComponentIterator(.windows, u16) = .init(path_w);
                const base = path_it.last().?;
                break :app .{
                    null,
                    if (path_it.previous()) |dir| dir.path else path_it.root(),
                    base.name,
                };
            },
            .explicit => |explicit| explicit.path,
        };
        const base_dir: ?Dir = if (Dir.path.isAbsolute(path)) null else switch (options.exe) {
            // The cwd provided by options is in effect when choosing the executable
            // path to match POSIX semantics.
            .detect, .search => null,
            .path => |dir| dir,
            .file => unreachable,
            .explicit => |explicit| explicit.dir,
        };
        const app_path: ?[]const u16 = if (Dir.path.isAbsolute(path)) null else if (base_dir) |dir| p: {
            dirPath(dir, &app_path_buf) catch |err| switch (err) {
                error.AccessDenied, error.FileNotFound, error.NameTooLong, error.BadPathName, error.Unexpected => |e| return e,
            };
            break :p stripVerbatim(app_path_buf.data[0..app_path_buf.len], &app_path_buf.data) catch unreachable;
        } else cwd_w;
        break :app .{
            app_path,
            if (Dir.path.dirname(path)) |app_dir| try std.unicode.wtf8ToWtf16LeAllocZ(arena, app_dir) else null,
            try std.unicode.wtf8ToWtf16LeAllocZ(arena, Dir.path.basename(path)),
        };
    };

    var flags: u32 = CREATE_UNICODE_ENVIRONMENT;
    if (options.start_suspended) flags |= CREATE_SUSPENDED;
    if (options.create_no_window) flags |= CREATE_NO_WINDOW;

    // Handle inheritance is process-wide, so serialize spawning.
    try mutexLock(&w.process_spawn_mutex);
    defer mutexUnlock(&w.process_spawn_mutex);

    const any_ignore = options.stdin == .ignore or options.stdout == .ignore or options.stderr == .ignore;
    const nul_handle = if (any_ignore) getNulDevice(w) catch |err| switch (err) {
        error.Canceled => |e| return e,
        error.FileNotFound => return error.NoDevice,
        error.AccessDenied => return error.AccessDenied,
        error.Unexpected => return error.Unexpected,
    } else undefined;

    const stdin_pipe = if (options.stdin == .pipe) try createPipe(.{ .server_overlapped = false, .inbound = false }) else undefined;
    errdefer if (options.stdin == .pipe) for (stdin_pipe) |handle| {
        _ = w32.CloseHandle(handle);
    };
    const stdout_pipe = if (options.stdout == .pipe) try createPipe(.{ .server_overlapped = true, .inbound = true }) else undefined;
    errdefer if (options.stdout == .pipe) for (stdout_pipe) |handle| {
        _ = w32.CloseHandle(handle);
    };
    const stderr_pipe = if (options.stderr == .pipe) try createPipe(.{ .server_overlapped = true, .inbound = true }) else undefined;
    errdefer if (options.stderr == .pipe) for (stderr_pipe) |handle| {
        _ = w32.CloseHandle(handle);
    };
    const prog_pipe = if (options.progress_node.index != .none) try createPipe(.{
        .server_overlapped = true,
        .client_overlapped = true,
        .inbound = true,
        .quota = std.Progress.max_packet_len * 2,
    }) else undefined;
    errdefer if (options.progress_node.index != .none) for (prog_pipe) |handle| {
        _ = w32.CloseHandle(handle);
    };

    defer for (options.inherit_dirs) |inherit_dir| setInheritable(inherit_dir.handle, false) catch {};
    for (options.inherit_dirs) |inherit_dir| try setInheritable(inherit_dir.handle, true);
    defer for (options.inherit_files) |inherit_file| setInheritable(inherit_file.handle, false) catch {};
    for (options.inherit_files) |inherit_file| try setInheritable(inherit_file.handle, true);

    const std_handles = [3]w32.STD_HANDLE{ w32.STD_INPUT_HANDLE, w32.STD_OUTPUT_HANDLE, w32.STD_ERROR_HANDLE };
    const stdios = [3]process.SpawnOptions.StdIo{ options.stdin, options.stdout, options.stderr };
    const pipe_ends = [3]?w32.HANDLE{
        if (options.stdin == .pipe) stdin_pipe[1] else null,
        if (options.stdout == .pipe) stdout_pipe[1] else null,
        if (options.stderr == .pipe) stderr_pipe[1] else null,
    };
    var child_handles: [3]?w32.HANDLE = undefined;
    var duplicated: [3]?w32.HANDLE = @splat(null);
    defer for (duplicated) |handle| if (handle) |h| {
        _ = w32.CloseHandle(h);
    };
    for (stdios, &child_handles, &duplicated, std_handles, pipe_ends) |stdio, *child_handle, *dup, std_handle, pipe_end| {
        child_handle.* = switch (stdio) {
            .inherit => getStdHandle(std_handle),
            .file => |file| h: {
                dup.* = try duplicateInheritable(file.handle);
                break :h dup.*;
            },
            .ignore => nul_handle,
            .pipe => pipe_end,
            .close => null,
        };
    }

    var startup_info: STARTUPINFOW = .{
        .cb = @sizeOf(STARTUPINFOW),
        .dwFlags = STARTF_USESTDHANDLES,
        .hStdInput = child_handles[0],
        .hStdOutput = child_handles[1],
        .hStdError = child_handles[2],
    };
    var process_info: PROCESS_INFORMATION = undefined;

    const prog_handle: ?w32.HANDLE = if (options.progress_node.index != .none) prog_pipe[1] else null;
    const env_block = if (options.environ_map) |environ_map|
        try environ_map.createWindowsBlock(arena, .{ .zig_progress_handle = prog_handle orelse windows.INVALID_HANDLE_VALUE })
    else
        try createEnvironmentBlock(w, arena, prog_handle);

    run: {
        // PATH and PATHEXT always come from the parent environment.
        var path_buf: [32767]u16 = undefined;
        const PATH = getEnvironmentVariable("PATH", &path_buf) orelse &[_:0]u16{};
        var pathext_buf: [2048]u16 = undefined;
        const PATHEXT = getEnvironmentVariable("PATHEXT", &pathext_buf) orelse &[_:0]u16{};

        // In case the command ends up being a .bat/.cmd script, we need to escape things using the cmd.exe rules
        // and invoke cmd.exe ourselves in order to mitigate arbitrary command execution from maliciously
        // constructed arguments.
        var cmd_line_cache = WindowsCommandLineCache.init(arena, options.argv);

        var app_buf: std.ArrayList(u16) = .empty;
        try app_buf.appendSlice(arena, app_name_w);

        var dir_buf: std.ArrayList(u16) = .empty;

        if (app_path_w) |app_path| try dir_buf.appendSlice(arena, app_path);
        if (app_dir_w) |app_dir| {
            if (dir_buf.items.len > 0) try dir_buf.append(arena, Dir.path.sep);
            try dir_buf.appendSlice(arena, app_dir);
        }

        windowsCreateProcessPathExt(
            arena,
            &dir_buf,
            &app_buf,
            PATHEXT,
            &cmd_line_cache,
            env_block,
            cwd_w_ptr,
            flags,
            &startup_info,
            &process_info,
        ) catch |no_path_err| {
            const original_err = switch (no_path_err) {
                // argv[0] contains unsupported characters that will never resolve to a valid exe.
                error.InvalidArg0 => return error.FileNotFound,
                error.FileNotFound, error.InvalidExe, error.AccessDenied => |e| e,
                error.UnrecoverableInvalidExe => return error.InvalidExe,
                else => |e| return e,
            };

            // We still search the path if the cwd is absolute because of the
            // "cwd provided by options is in effect when choosing the executable path
            // to match posix semantics" behavior--we don't want to skip searching
            // the PATH just because we were trying to set the cwd of the child process.
            if (switch (options.exe) {
                // If the app name had path separators, that disallows PATH searching.
                .detect => app_dir_w != null,
                // There's no need to search the PATH if the app name is absolute.
                .search => app_path_w == null,
                // PATH searching is disallowed.
                .path, .file, .explicit => true,
            }) return original_err;

            var it = std.mem.tokenizeScalar(u16, PATH, ';');
            while (it.next()) |search_path| {
                dir_buf.clearRetainingCapacity();
                try dir_buf.appendSlice(arena, search_path);

                if (windowsCreateProcessPathExt(
                    arena,
                    &dir_buf,
                    &app_buf,
                    PATHEXT,
                    &cmd_line_cache,
                    env_block,
                    cwd_w_ptr,
                    flags,
                    &startup_info,
                    &process_info,
                )) {
                    break :run;
                } else |err| switch (err) {
                    // argv[0] contains unsupported characters that will never resolve to a valid exe.
                    error.InvalidArg0 => return error.FileNotFound,
                    error.FileNotFound, error.AccessDenied, error.InvalidExe => continue,
                    error.UnrecoverableInvalidExe => return error.InvalidExe,
                    else => |e| return e,
                }
            } else {
                return original_err;
            }
        };
    }

    if (options.progress_node.index != .none) {
        _ = w32.CloseHandle(prog_pipe[1]);
        options.progress_node.setIpcFile(userdata, .{ .handle = prog_pipe[0], .flags = .{ .nonblocking = true } });
    }

    return .{
        .id = process_info.hProcess,
        .thread_handle = process_info.hThread,
        .stdin = if (options.stdin == .pipe) stdin: {
            _ = w32.CloseHandle(stdin_pipe[1]);
            break :stdin .{ .handle = stdin_pipe[0], .flags = .{ .nonblocking = false } };
        } else null,
        .stdout = if (options.stdout == .pipe) stdout: {
            _ = w32.CloseHandle(stdout_pipe[1]);
            break :stdout .{ .handle = stdout_pipe[0], .flags = .{ .nonblocking = true } };
        } else null,
        .stderr = if (options.stderr == .pipe) stderr: {
            _ = w32.CloseHandle(stderr_pipe[1]);
            break :stderr .{ .handle = stderr_pipe[0], .flags = .{ .nonblocking = true } };
        } else null,
        .request_resource_usage_statistics = options.request_resource_usage_statistics,
    };
}

fn windowsCreateProcessPathExt(
    arena: Allocator,
    dir_buf: *std.ArrayList(u16),
    app_buf: *std.ArrayList(u16),
    pathext: [:0]const u16,
    cmd_line_cache: *WindowsCommandLineCache,
    env_block: ?process.Environ.WindowsBlock,
    cwd_ptr: ?[*:0]u16,
    flags: u32,
    startup_info: *STARTUPINFOW,
    process_info: *PROCESS_INFORMATION,
) !void {
    const app_name_len = app_buf.items.len;
    const dir_path_len = dir_buf.items.len;

    if (app_name_len == 0) return error.FileNotFound;

    defer app_buf.shrinkRetainingCapacity(app_name_len);
    defer dir_buf.shrinkRetainingCapacity(dir_path_len);

    // The name of the game here is to avoid CreateProcessW calls at all costs,
    // and only ever try calling it when we have a real candidate for execution.
    // A single wildcard search for `<dir>\<app name>*` finds the unappended
    // version of the app name and all PATHEXT-appended versions at once.
    var pathext_seen: [@typeInfo(process.WindowsExtension).@"enum".field_names.len]bool = @splat(false);
    var any_pathext_seen = false;
    var unappended_exists = false;
    {
        var pattern: std.ArrayList(u16) = .empty;
        try pattern.appendSlice(arena, dir_buf.items);
        if (dir_path_len != 0) switch (dir_buf.items[dir_path_len - 1]) {
            '/', '\\' => {},
            else => try pattern.append(arena, Dir.path.sep),
        };
        try pattern.appendSlice(arena, app_buf.items);
        try pattern.append(arena, '*');
        try pattern.append(arena, 0);
        const pattern_z = pattern.items[0 .. pattern.items.len - 1 :0];

        var find_data: w32.WIN32_FIND_DATAW = undefined;
        const syscall: Syscall = try .start();
        const find_handle = w32.FindFirstFileExW(pattern_z.ptr, .Basic, &find_data, .NameMatch, null, .{ .LARGE_FETCH = 1 });
        syscall.finish();
        if (find_handle == -1) switch (getLastError()) {
            .ERROR_ACCESS_DENIED => return error.AccessDenied,
            // `ERROR_DIRECTORY` and similar mean the directory is not usable,
            // which must not affect which file is chosen to execute.
            else => return error.FileNotFound,
        };
        defer _ = w32.FindClose(find_handle);

        // Note: All matches are iterated because the order of the files returned
        // is filesystem-dependent: on FAT32, `blah.exe.obj` may come before `blah.exe`.
        while (true) {
            if (find_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY == 0) {
                const filename = std.mem.sliceTo(&find_data.cFileName, 0);
                // Because all results start with the app_name since we're using the wildcard `app_name*`,
                // if the length is equal to app_name then this is an exact match
                if (filename.len == app_name_len) {
                    // Note: We can't break early here because it's possible that the unappended version
                    //       fails to spawn, in which case we still want to try the PATHEXT appended versions.
                    unappended_exists = true;
                } else if (filename.len > app_name_len) {
                    if (windowsCreateProcessSupportsExtension(filename[app_name_len..])) |pathext_ext| {
                        pathext_seen[@backingInt(pathext_ext)] = true;
                        any_pathext_seen = true;
                    }
                }
            }
            if (w32.FindNextFileW(find_handle, &find_data) == 0) break;
        }
    }

    const unappended_err = unappended: {
        if (unappended_exists) {
            if (dir_path_len != 0) switch (dir_buf.items[dir_buf.items.len - 1]) {
                '/', '\\' => {},
                else => try dir_buf.append(arena, Dir.path.sep),
            };
            try dir_buf.appendSlice(arena, app_buf.items[0..app_name_len]);
            try dir_buf.append(arena, 0);
            const full_app_name = dir_buf.items[0 .. dir_buf.items.len - 1 :0];

            const is_bat_or_cmd = bat_or_cmd: {
                const app_name = app_buf.items[0..app_name_len];
                const ext_start = std.mem.findScalarLast(u16, app_name, '.') orelse break :bat_or_cmd false;
                const ext = app_name[ext_start..];
                const ext_enum = windowsCreateProcessSupportsExtension(ext) orelse break :bat_or_cmd false;
                switch (ext_enum) {
                    .cmd, .bat => break :bat_or_cmd true,
                    else => break :bat_or_cmd false,
                }
            };
            const cmd_line_w = if (is_bat_or_cmd)
                try cmd_line_cache.scriptCommandLine(full_app_name)
            else
                try cmd_line_cache.commandLine();
            const app_name_w = if (is_bat_or_cmd)
                try cmd_line_cache.cmdExePath()
            else
                full_app_name;

            if (windowsCreateProcess(app_name_w.ptr, cmd_line_w.ptr, env_block, cwd_ptr, flags, startup_info, process_info)) |_| {
                return;
            } else |err| switch (err) {
                error.FileNotFound,
                error.AccessDenied,
                => break :unappended err,
                error.InvalidExe => {
                    // On InvalidExe, if the extension of the app name is .exe then
                    // it's treated as an unrecoverable error. Otherwise, it'll be
                    // skipped as normal.
                    const app_name = app_buf.items[0..app_name_len];
                    const ext_start = std.mem.findScalarLast(u16, app_name, '.') orelse break :unappended err;
                    const ext = app_name[ext_start..];
                    if (windows.eqlIgnoreCaseWtf16(ext, L(".EXE"))) {
                        return error.UnrecoverableInvalidExe;
                    }
                    break :unappended err;
                },
                else => return err,
            }
        }
        break :unappended error.FileNotFound;
    };

    if (!any_pathext_seen) return unappended_err;

    // Now try any PATHEXT appended versions that we've seen
    var ext_it = std.mem.tokenizeScalar(u16, pathext, ';');
    while (ext_it.next()) |ext| {
        const ext_enum = windowsCreateProcessSupportsExtension(ext) orelse continue;
        if (!pathext_seen[@backingInt(ext_enum)]) continue;

        dir_buf.shrinkRetainingCapacity(dir_path_len);
        if (dir_path_len != 0) switch (dir_buf.items[dir_buf.items.len - 1]) {
            '/', '\\' => {},
            else => try dir_buf.append(arena, Dir.path.sep),
        };
        try dir_buf.appendSlice(arena, app_buf.items[0..app_name_len]);
        try dir_buf.appendSlice(arena, ext);
        try dir_buf.append(arena, 0);
        const full_app_name = dir_buf.items[0 .. dir_buf.items.len - 1 :0];

        const is_bat_or_cmd = switch (ext_enum) {
            .cmd, .bat => true,
            else => false,
        };
        const cmd_line_w = if (is_bat_or_cmd)
            try cmd_line_cache.scriptCommandLine(full_app_name)
        else
            try cmd_line_cache.commandLine();
        const app_name_w = if (is_bat_or_cmd)
            try cmd_line_cache.cmdExePath()
        else
            full_app_name;

        if (windowsCreateProcess(app_name_w.ptr, cmd_line_w.ptr, env_block, cwd_ptr, flags, startup_info, process_info)) |_| {
            return;
        } else |err| switch (err) {
            error.FileNotFound => continue,
            error.AccessDenied => continue,
            error.InvalidExe => {
                // On InvalidExe, if the extension of the app name is .exe then
                // it's treated as an unrecoverable error. Otherwise, it'll be
                // skipped as normal.
                if (windows.eqlIgnoreCaseWtf16(ext, L(".EXE"))) {
                    return error.UnrecoverableInvalidExe;
                }
                continue;
            },
            else => return err,
        }
    }

    return unappended_err;
}

fn windowsCreateProcess(
    app_name: [*:0]u16,
    cmd_line: [*:0]u16,
    env_block: ?process.Environ.WindowsBlock,
    cwd_ptr: ?[*:0]u16,
    flags: u32,
    startup_info: *STARTUPINFOW,
    process_info: *PROCESS_INFORMATION,
) !void {
    const syscall: Syscall = try .start();
    while (true) {
        if (process_externs.CreateProcessW(
            app_name,
            cmd_line,
            null,
            null,
            w32.TRUE,
            flags,
            if (env_block) |block| block.slice.ptr else null,
            cwd_ptr,
            startup_info,
            process_info,
        ) != 0) {
            return syscall.finish();
        } else switch (getLastError()) {
            .ERROR_INVALID_PARAMETER => unreachable,
            .ERROR_OPERATION_ABORTED => {
                try syscall.checkCancel();
                continue;
            },
            .ERROR_FILE_NOT_FOUND => return syscall.fail(error.FileNotFound),
            .ERROR_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
            .ERROR_DIRECTORY => return syscall.fail(error.FileNotFound),
            .ERROR_ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            .ERROR_INVALID_NAME => return syscall.fail(error.InvalidName),
            .ERROR_FILENAME_EXCED_RANGE => return syscall.fail(error.NameTooLong),
            .ERROR_SHARING_VIOLATION => return syscall.fail(error.FileBusy),
            .ERROR_COMMITMENT_LIMIT => return syscall.fail(error.SystemResources),

            // These are all the system errors that are mapped to ENOEXEC by
            // the undocumented _dosmaperr (old CRT) or __acrt_errno_map_os_error
            // (newer CRT) functions. Their code can be found in crt/src/dosmap.c (old SDK)
            // or urt/misc/errno.cpp (newer SDK) in the Windows SDK.
            .ERROR_BAD_FORMAT,
            .ERROR_INVALID_STARTING_CODESEG, // MIN_EXEC_ERROR in errno.cpp
            .ERROR_INVALID_STACKSEG,
            .ERROR_INVALID_MODULETYPE,
            .ERROR_INVALID_EXE_SIGNATURE,
            .ERROR_EXE_MARKED_INVALID,
            .ERROR_BAD_EXE_FORMAT,
            .ERROR_ITERATED_DATA_EXCEEDS_64k,
            .ERROR_INVALID_MINALLOCSIZE,
            .ERROR_DYNLINK_FROM_INVALID_RING,
            .ERROR_IOPL_NOT_ENABLED,
            .ERROR_INVALID_SEGDPL,
            .ERROR_AUTODATASEG_EXCEEDS_64k,
            .ERROR_RING2SEG_MUST_BE_MOVABLE,
            .ERROR_RELOC_CHAIN_XEEDS_SEGLIM,
            .ERROR_INFLOOP_IN_RELOC_CHAIN, // MAX_EXEC_ERROR in errno.cpp
            // This one is not mapped to ENOEXEC but it is possible, for example
            // when calling CreateProcessW on a plain text file with a .exe extension
            .ERROR_EXE_MACHINE_TYPE_MISMATCH,
            => return syscall.fail(error.InvalidExe),

            else => |err| return syscall.unexpectedError(err),
        }
    }
}

/// Case-insensitive WTF-16 lookup
fn windowsCreateProcessSupportsExtension(ext: []const u16) ?process.WindowsExtension {
    if (ext.len != 4 or ext[0] != '.') return null;
    inline for (@typeInfo(process.WindowsExtension).@"enum".field_names) |name| {
        if (windows.eqlIgnoreCaseWtf16(ext[1..], L(name))) return @field(process.WindowsExtension, name);
    }
    return null;
}

/// Serializes argv into a WTF-16 encoded command-line string for use with
/// CreateProcessW, on demand and cached. Ported from `std.Io.Threaded`.
const WindowsCommandLineCache = struct {
    cmd_line: ?[:0]u16 = null,
    script_cmd_line: ?[:0]u16 = null,
    cmd_exe_path: ?[:0]u16 = null,
    argv: []const []const u8,
    allocator: Allocator,

    fn init(allocator: Allocator, argv: []const []const u8) WindowsCommandLineCache {
        return .{
            .allocator = allocator,
            .argv = argv,
        };
    }

    fn commandLine(self: *WindowsCommandLineCache) ![:0]u16 {
        if (self.cmd_line == null) {
            self.cmd_line = try argvToCommandLineWindows(self.allocator, self.argv);
        }
        return self.cmd_line.?;
    }

    /// Not cached, since the path to the batch script will change during PATH searching.
    fn scriptCommandLine(self: *WindowsCommandLineCache, script_path: []const u16) ![:0]u16 {
        if (self.script_cmd_line) |v| self.allocator.free(v);
        self.script_cmd_line = try argvToScriptCommandLineWindows(
            self.allocator,
            script_path,
            self.argv[1..],
        );
        return self.script_cmd_line.?;
    }

    fn cmdExePath(self: *WindowsCommandLineCache) Allocator.Error![:0]u16 {
        if (self.cmd_exe_path == null) {
            var system_dir_buf: [PATH_MAX_WIDE]u16 = undefined;
            const n = w32.GetSystemDirectoryW(@ptrCast(&system_dir_buf), system_dir_buf.len);
            // Remove trailing slash from system directory path; we'll re-add it below
            const system_dir = std.mem.trimEnd(u16, system_dir_buf[0..@min(n, system_dir_buf.len)], &.{ '/', '\\' });
            const suffix = L("\\cmd.exe");
            const buf = try self.allocator.allocSentinel(u16, system_dir.len + suffix.len, 0);
            @memcpy(buf[0..system_dir.len], system_dir);
            @memcpy(buf[system_dir.len..], suffix);
            self.cmd_exe_path = buf;
        }
        return self.cmd_exe_path.?;
    }
};

const ArgvToScriptCommandLineError = error{
    OutOfMemory,
    InvalidWtf8,
    /// NUL (U+0000), LF (U+000A), CR (U+000D) are not allowed
    /// within arguments when executing a `.bat`/`.cmd` script.
    InvalidBatchScriptArg,
};

/// Serializes `argv` to a Windows command-line string that uses `cmd.exe /c` and `cmd.exe`-specific
/// escaping rules. Ported from `std.Io.Threaded`, see there for details.
fn argvToScriptCommandLineWindows(
    allocator: Allocator,
    script_path: []const u16,
    script_args: []const []const u8,
) ArgvToScriptCommandLineError![:0]u16 {
    var buf = try std.array_list.Managed(u8).initCapacity(allocator, 64);
    defer buf.deinit();

    // `/d` disables execution of AutoRun commands.
    // `/e:ON` and `/v:OFF` are needed for BatBadBut mitigation:
    // https://flatt.tech/research/posts/batbadbut-you-cant-securely-execute-commands-on-windows/
    buf.appendSliceAssumeCapacity("cmd.exe /d /e:ON /v:OFF /c \"");

    // Always quote the path to the script arg
    buf.appendAssumeCapacity('"');
    // Avoid cmd.exe searching the PATH for the script.
    if (std.mem.findAny(u16, script_path, &[_]u16{ '\\', '/' }) == null) {
        try buf.appendSlice(".\\");
    }
    try std.unicode.wtf16LeToWtf8ArrayList(&buf, script_path);
    buf.appendAssumeCapacity('"');

    for (script_args) |arg| {
        // Literal carriage returns get stripped when run through cmd.exe
        // and NUL/newlines act as 'end of command.'
        if (std.mem.findAny(u8, arg, "\x00\r\n") != null) {
            return error.InvalidBatchScriptArg;
        }

        // Separate args with a space.
        try buf.append(' ');

        // Need to quote if the argument is empty (otherwise the arg would just be lost)
        // or if the last character is a `\`, since then something like "%~2" in a .bat
        // script would cause the closing " to be escaped which we don't want.
        var needs_quotes = arg.len == 0 or arg[arg.len - 1] == '\\';
        if (!needs_quotes) {
            for (arg) |c| {
                switch (c) {
                    // Known good characters that don't need to be quoted
                    'A'...'Z', 'a'...'z', '0'...'9', '#', '$', '*', '+', '-', '.', '/', ':', '?', '@', '\\', '_' => {},
                    // When in doubt, quote
                    else => {
                        needs_quotes = true;
                        break;
                    },
                }
            }
        }
        if (needs_quotes) {
            try buf.append('"');
        }
        var backslashes: usize = 0;
        for (arg) |c| {
            switch (c) {
                '\\' => {
                    backslashes += 1;
                },
                '"' => {
                    try buf.appendNTimes('\\', backslashes);
                    try buf.append('"');
                    backslashes = 0;
                },
                // Replace `%` with `%%cd:~,%`, which expands to an empty
                // string, to stop `%foo%` from being expanded.
                '%' => {
                    // the trailing `%` is appended outside the switch
                    try buf.appendSlice("%%cd:~,");
                    backslashes = 0;
                },
                else => {
                    backslashes = 0;
                },
            }
            try buf.append(c);
        }
        if (needs_quotes) {
            try buf.appendNTimes('\\', backslashes);
            try buf.append('"');
        }
    }

    try buf.append('"');

    return try std.unicode.wtf8ToWtf16LeAllocZ(allocator, buf.items);
}

const ArgvToCommandLineError = error{ OutOfMemory, InvalidWtf8, InvalidArg0 };

/// Serializes `argv` to a Windows command-line string suitable for passing to a child process and
/// parsing by the `CommandLineToArgvW` algorithm. Ported from `std.Io.Threaded`.
fn argvToCommandLineWindows(
    allocator: Allocator,
    argv: []const []const u8,
) ArgvToCommandLineError![:0]u16 {
    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    if (argv.len != 0) {
        const arg0 = argv[0];

        // The first argument must be quoted if it contains spaces or ASCII control characters
        // (excluding DEL). Backslashes have no special meaning in it, so double quotes cannot be
        // represented; they are illegal in paths anyway.
        var needs_quotes = arg0.len == 0;
        for (arg0) |c| {
            if (c <= ' ') {
                needs_quotes = true;
            } else if (c == '"') {
                return error.InvalidArg0;
            }
        }
        if (needs_quotes) {
            try buf.append('"');
            try buf.appendSlice(arg0);
            try buf.append('"');
        } else {
            try buf.appendSlice(arg0);
        }

        for (argv[1..]) |arg| {
            try buf.append(' ');

            // Subsequent arguments must be quoted if they contain spaces, tabs or double quotes,
            // or if they are empty. ASCII control characters are quoted too.
            needs_quotes = for (arg) |c| {
                if (c <= ' ' or c == '"') {
                    break true;
                }
            } else arg.len == 0;
            if (!needs_quotes) {
                try buf.appendSlice(arg);
                continue;
            }

            try buf.append('"');
            var backslash_count: usize = 0;
            for (arg) |byte| {
                switch (byte) {
                    '\\' => {
                        backslash_count += 1;
                    },
                    '"' => {
                        try buf.appendNTimes('\\', backslash_count * 2 + 1);
                        try buf.append('"');
                        backslash_count = 0;
                    },
                    else => {
                        try buf.appendNTimes('\\', backslash_count);
                        try buf.append(byte);
                        backslash_count = 0;
                    },
                }
            }
            try buf.appendNTimes('\\', backslash_count * 2);
            try buf.append('"');
        }
    }

    return try std.unicode.wtf8ToWtf16LeAllocZ(allocator, buf.items);
}

fn childWait(userdata: ?*anyopaque, child: *process.Child) process.Child.WaitError!process.Child.Term {
    _ = userdata;
    const handle = child.id.?;

    const alertable_syscall: AlertableSyscall = try .start();
    while (true) {
        const rc = w32.WaitForSingleObjectEx(handle, INFINITE, w32.TRUE);
        switch (@backingInt(rc)) {
            WAIT_OBJECT_0 => break alertable_syscall.finish(),
            WAIT_IO_COMPLETION => try alertable_syscall.checkCancel(),
            else => {
                alertable_syscall.finish();
                return unexpectedError(getLastError());
            },
        }
    }

    var exit_code: u32 = undefined;
    const term: process.Child.Term = if (w32.GetExitCodeProcess(handle, &exit_code) != 0)
        .{ .exited = @truncate(exit_code) }
    else
        .{ .unknown = 0 };

    childCleanup(child);
    return term;
}

fn childKill(userdata: ?*anyopaque, child: *process.Child) void {
    _ = userdata;
    childTerminate(child, 1) catch childCleanup(child);
}

fn childTerminate(child: *process.Child, exit_code: u32) !void {
    const handle = child.id.?;
    if (w32.TerminateProcess(handle, exit_code) != 0) {
        _ = w32.WaitForSingleObjectEx(handle, INFINITE, w32.FALSE);
        childCleanup(child);
        return;
    }
    switch (getLastError()) {
        .ERROR_ACCESS_DENIED => {
            // Usually when TerminateProcess triggers a ACCESS_DENIED error, it
            // indicates that the process has already exited, but there may be
            // some rare edge cases where our process handle no longer has the
            // PROCESS_TERMINATE access right, so let's do another check to make
            // sure the process is really no longer running:
            return switch (@backingInt(w32.WaitForSingleObjectEx(handle, 0, w32.FALSE))) {
                WAIT_OBJECT_0 => error.AlreadyTerminated,
                else => error.AccessDenied,
            };
        },
        else => |err| return unexpectedError(err),
    }
}

fn childCleanup(child: *process.Child) void {
    const handle = child.id orelse return;

    if (child.request_resource_usage_statistics) {
        var counters: w32.PROCESS_MEMORY_COUNTERS = undefined;
        counters.cb = @sizeOf(w32.PROCESS_MEMORY_COUNTERS);
        child.resource_usage_statistics.rusage = if (w32.K32GetProcessMemoryInfo(handle, &counters, counters.cb) != 0) .{
            .PeakVirtualSize = 0,
            .VirtualSize = 0,
            .PageFaultCount = counters.PageFaultCount,
            .PeakWorkingSetSize = counters.PeakWorkingSetSize,
            .WorkingSetSize = counters.WorkingSetSize,
            .QuotaPeakPagedPoolUsage = counters.QuotaPeakPagedPoolUsage,
            .QuotaPagedPoolUsage = counters.QuotaPagedPoolUsage,
            .QuotaPeakNonPagedPoolUsage = counters.QuotaPeakNonPagedPoolUsage,
            .QuotaNonPagedPoolUsage = counters.QuotaNonPagedPoolUsage,
            .PagefileUsage = counters.PagefileUsage,
            .PeakPagefileUsage = counters.PeakPagefileUsage,
        } else null;
    }

    _ = w32.CloseHandle(handle);
    child.id = null;

    _ = w32.CloseHandle(child.thread_handle);
    child.thread_handle = undefined;

    if (child.stdin) |stdin| {
        _ = w32.CloseHandle(stdin.handle);
        child.stdin = null;
    }
    if (child.stdout) |stdout| {
        _ = w32.CloseHandle(stdout.handle);
        child.stdout = null;
    }
    if (child.stderr) |stderr| {
        _ = w32.CloseHandle(stderr.handle);
        child.stderr = null;
    }
}
