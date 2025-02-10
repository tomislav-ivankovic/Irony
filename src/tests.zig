test {
    _ = @import("dll.zig");
    _ = @import("injector.zig");

    _ = @import("injector/injected_module.zig");
    _ = @import("injector/process_loop.zig");

    _ = @import("memory/converted_value.zig");
    _ = @import("memory/memory_pattern.zig");
    _ = @import("memory/memory_range.zig");
    _ = @import("memory/multilevel_pointer.zig");
    _ = @import("memory/pointer.zig");
    _ = @import("memory/self_sortable_array.zig");

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
}
