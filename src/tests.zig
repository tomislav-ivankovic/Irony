test {
    _ = @import("dll.zig");
    _ = @import("event_buss.zig");
    _ = @import("injector.zig");

    _ = @import("dx12/context.zig");
    _ = @import("dx12/descriptor_heap_allocator.zig");
    _ = @import("dx12/error.zig");
    _ = @import("dx12/functions.zig");
    _ = @import("dx12/misc.zig");
    _ = @import("dx12/testing_context.zig");

    _ = @import("game/memory.zig");
    _ = @import("game/types.zig");

    _ = @import("hooking/hook.zig");
    _ = @import("hooking/main_hooks.zig");

    _ = @import("injector/injected_module.zig");
    _ = @import("injector/process_loop.zig");

    _ = @import("log/composite.zig");
    _ = @import("log/console.zig");
    _ = @import("log/file.zig");

    _ = @import("memory/converted_value.zig");
    _ = @import("memory/multilevel_pointer.zig");
    _ = @import("memory/pattern.zig");
    _ = @import("memory/pointer.zig");
    _ = @import("memory/range.zig");
    _ = @import("memory/relative_offset.zig");
    _ = @import("memory/self_sortable_array.zig");

    _ = @import("misc/base_dir.zig");
    _ = @import("misc/circular_buffer.zig");
    _ = @import("misc/error_context.zig");
    _ = @import("misc/timestamp.zig");

    _ = @import("os/error.zig");
    _ = @import("os/memory.zig");
    _ = @import("os/misc.zig");
    _ = @import("os/module.zig");
    _ = @import("os/process_id.zig");
    _ = @import("os/process.zig");
    _ = @import("os/remote_slice.zig");
    _ = @import("os/remote_thread.zig");
    _ = @import("os/shared_value.zig");
    _ = @import("os/window_procedure.zig");

    _ = @import("ui/context.zig");
}
