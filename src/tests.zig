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

    _ = @import("log/buffer.zig");
    _ = @import("log/composite.zig");
    _ = @import("log/console.zig");
    _ = @import("log/file.zig");

    _ = @import("math/vector.zig");

    _ = @import("memory/bitfield.zig");
    _ = @import("memory/converted_value.zig");
    _ = @import("memory/misc.zig");
    _ = @import("memory/pattern.zig");
    _ = @import("memory/pattern_cache.zig");
    _ = @import("memory/pointer.zig");
    _ = @import("memory/pointer_trail.zig");
    _ = @import("memory/proxy.zig");
    _ = @import("memory/range.zig");
    _ = @import("memory/self_sortable_array.zig");
    _ = @import("memory/struct_proxy.zig");
    _ = @import("memory/struct_with_offsets.zig");

    _ = @import("misc/base_dir.zig");
    _ = @import("misc/circular_buffer.zig");
    _ = @import("misc/error_context.zig");
    _ = @import("misc/misc.zig");
    _ = @import("misc/task.zig");
    _ = @import("misc/timer.zig");
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

    _ = @import("ui/allocator.zig");
    _ = @import("ui/context.zig"); // Make sure this test gets executed before UI testing context is initialized.
    _ = @import("ui/testing_context.zig"); // First test using UI testing context.
    _ = @import("ui/toasts.zig");

    _ = @import("components/data.zig");
    _ = @import("components/game_memory_window.zig");
    _ = @import("components/loading_window.zig");
    _ = @import("components/main_window.zig");
    _ = @import("components/quadrant-layout.zig");
    _ = @import("components/logs_window.zig");

    _ = struct {
        test "should have no memory leaks after de-initializing UI testing context" {
            @import("ui/root.zig").deinitTestingContextAndDetectLeaks();
        }
    };
}
