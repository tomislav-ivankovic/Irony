test {
    _ = @import("sdk/dx11/context.zig");
    _ = @import("sdk/dx11/error.zig");
    _ = @import("sdk/dx11/functions.zig");
    _ = @import("sdk/dx11/hooks.zig");
    _ = @import("sdk/dx11/misc.zig");
    _ = @import("sdk/dx11/testing_context.zig");

    _ = @import("sdk/dx12/context.zig");
    _ = @import("sdk/dx12/descriptor_heap_allocator.zig");
    _ = @import("sdk/dx12/error.zig");
    _ = @import("sdk/dx12/functions.zig");
    _ = @import("sdk/dx12/hooks.zig");
    _ = @import("sdk/dx12/misc.zig");
    _ = @import("sdk/dx12/testing_context.zig");

    _ = @import("sdk/io/bit.zig");
    _ = @import("sdk/io/byte.zig");
    _ = @import("sdk/io/recording.zig");
    _ = @import("sdk/io/settings.zig");
    _ = @import("sdk/io/xz.zig");

    _ = @import("sdk/log/buffer.zig");
    _ = @import("sdk/log/composite.zig");
    _ = @import("sdk/log/console.zig");
    _ = @import("sdk/log/file.zig");

    _ = @import("sdk/math/easing.zig");
    _ = @import("sdk/math/intersection.zig");
    _ = @import("sdk/math/shapes.zig");
    _ = @import("sdk/math/vector.zig");
    _ = @import("sdk/math/matrix.zig");

    _ = @import("sdk/memory/bitfield.zig");
    _ = @import("sdk/memory/boolean.zig");
    _ = @import("sdk/memory/converted_value.zig");
    _ = @import("sdk/memory/hooking.zig");
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

    _ = @import("injector.zig");
    _ = @import("injector/injected_module.zig");
    _ = @import("injector/process_loop.zig");

    _ = @import("dll.zig");
    _ = @import("dll/event_buss.zig");

    _ = @import("dll/core/controller.zig");
    _ = @import("dll/core/core.zig");
    _ = @import("dll/core/hit_detector.zig");
    _ = @import("dll/core/move_detector.zig");
    _ = @import("dll/core/move_measurer.zig");
    _ = @import("dll/core/pause_detector.zig");

    _ = @import("dll/game/t7/conversions.zig");
    _ = @import("dll/game/t7/frame_detect_capturer.zig");
    _ = @import("dll/game/t7/hooks.zig");
    _ = @import("dll/game/t7/memory.zig");
    _ = @import("dll/game/t7/types.zig");

    _ = @import("dll/game/t8/capturer.zig");
    _ = @import("dll/game/t8/conversions.zig");
    _ = @import("dll/game/t8/frame_detect_capturer.zig");
    _ = @import("dll/game/t8/frame_detector.zig");
    _ = @import("dll/game/t8/hooks.zig");
    _ = @import("dll/game/t8/memory.zig");
    _ = @import("dll/game/t8/types.zig");

    _ = @import("dll/model/collision_sphere.zig");
    _ = @import("dll/model/frame.zig");
    _ = @import("dll/model/hit_lines.zig");
    _ = @import("dll/model/hurt_cylinders.zig");
    _ = @import("dll/model/misc.zig");
    _ = @import("dll/model/player.zig");
    _ = @import("dll/model/settings.zig");
    _ = @import("dll/model/skeleton.zig");

    _ = @import("dll/ui/about_window.zig");
    _ = @import("dll/ui/camera.zig");
    _ = @import("dll/ui/collision_spheres.zig");
    _ = @import("dll/ui/controls.zig");
    _ = @import("dll/ui/data.zig");
    _ = @import("dll/ui/details.zig");
    _ = @import("dll/ui/file_menu.zig");
    _ = @import("dll/ui/floor.zig");
    _ = @import("dll/ui/forward_directions.zig");
    _ = @import("dll/ui/frame_window.zig");
    _ = @import("dll/ui/game_memory_window.zig");
    _ = @import("dll/ui/hit_lines.zig");
    _ = @import("dll/ui/hurt_cylinders.zig");
    _ = @import("dll/ui/ingame_camera.zig");
    _ = @import("dll/ui/logs_window.zig");
    _ = @import("dll/ui/main_window.zig");
    _ = @import("dll/ui/measure_tool.zig");
    _ = @import("dll/ui/message_window.zig");
    _ = @import("dll/ui/navigation_layout.zig");
    _ = @import("dll/ui/quadrant_layout.zig");
    _ = @import("dll/ui/settings_window.zig");
    _ = @import("dll/ui/shapes.zig");
    _ = @import("dll/ui/skeletons.zig");
    _ = @import("dll/ui/ui.zig");
    _ = @import("dll/ui/view.zig");

    _ = struct {
        test "should have no memory leaks after de-initializing UI testing context" {
            @import("sdk/ui/root.zig").deinitTestingContextAndDetectLeaks();
        }
    };
}
