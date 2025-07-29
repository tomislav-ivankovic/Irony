test {
    _ = @import("dll.zig");
    _ = @import("event_buss.zig");
    _ = @import("injector.zig");

    _ = @import("sdk/dx12/context.zig");
    _ = @import("sdk/dx12/descriptor_heap_allocator.zig");
    _ = @import("sdk/dx12/error.zig");
    _ = @import("sdk/dx12/functions.zig");
    _ = @import("sdk/dx12/misc.zig");
    _ = @import("sdk/dx12/testing_context.zig");

    _ = @import("sdk/hooking/hook.zig");
    _ = @import("sdk/hooking/main_hooks.zig");

    _ = @import("sdk/log/buffer.zig");
    _ = @import("sdk/log/composite.zig");
    _ = @import("sdk/log/console.zig");
    _ = @import("sdk/log/file.zig");

    _ = @import("sdk/math/intersection.zig");
    _ = @import("sdk/math/shapes.zig");
    _ = @import("sdk/math/vector.zig");
    _ = @import("sdk/math/matrix.zig");

    _ = @import("sdk/memory/bitfield.zig");
    _ = @import("sdk/memory/converted_value.zig");
    _ = @import("sdk/memory/misc.zig");
    _ = @import("sdk/memory/pattern.zig");
    _ = @import("sdk/memory/pattern_cache.zig");
    _ = @import("sdk/memory/pointer.zig");
    _ = @import("sdk/memory/pointer_trail.zig");
    _ = @import("sdk/memory/proxy.zig");
    _ = @import("sdk/memory/range.zig");
    _ = @import("sdk/memory/self_sortable_array.zig");
    _ = @import("sdk/memory/struct_proxy.zig");
    _ = @import("sdk/memory/struct_with_offsets.zig");

    _ = @import("sdk/misc/base_dir.zig");
    _ = @import("sdk/misc/circular_buffer.zig");
    _ = @import("sdk/misc/error_context.zig");
    _ = @import("sdk/misc/meta.zig");
    _ = @import("sdk/misc/misc.zig");
    _ = @import("sdk/misc/task.zig");
    _ = @import("sdk/misc/timer.zig");
    _ = @import("sdk/misc/timestamp.zig");

    _ = @import("sdk/os/error.zig");
    _ = @import("sdk/os/memory.zig");
    _ = @import("sdk/os/misc.zig");
    _ = @import("sdk/os/module.zig");
    _ = @import("sdk/os/process_id.zig");
    _ = @import("sdk/os/process.zig");
    _ = @import("sdk/os/remote_slice.zig");
    _ = @import("sdk/os/remote_thread.zig");
    _ = @import("sdk/os/shared_value.zig");
    _ = @import("sdk/os/window_procedure.zig");

    _ = @import("sdk/ui/allocator.zig");
    _ = @import("sdk/ui/context.zig"); // Make sure this test gets executed before UI testing context is initialized.
    _ = @import("sdk/ui/testing_context.zig"); // First test using UI testing context.
    _ = @import("sdk/ui/toasts.zig");

    _ = @import("injector/injected_module.zig");
    _ = @import("injector/process_loop.zig");

    _ = @import("components/data.zig");
    _ = @import("components/game_memory_window.zig");
    _ = @import("components/loading_window.zig");
    _ = @import("components/main_window.zig");
    _ = @import("components/quadrant-layout.zig");
    _ = @import("components/logs_window.zig");

    _ = @import("core/capturer.zig");
    _ = @import("core/frame_detector.zig");
    _ = @import("core/data.zig");
    _ = @import("core/hit_detector.zig");
    _ = @import("core/pause_detector.zig");

    _ = @import("game/conversions.zig");
    _ = @import("game/memory.zig");
    _ = @import("game/types.zig");

    _ = struct {
        test "should have no memory leaks after de-initializing UI testing context" {
            @import("sdk/ui/root.zig").deinitTestingContextAndDetectLeaks();
        }
    };
}
