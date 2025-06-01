const std = @import("std");
const w32 = @import("win32").everything;
const imgui = @import("imgui");
const dll = @import("dll.zig");
const misc = @import("misc/root.zig");
const dx12 = @import("dx12/root.zig");
const ui = @import("ui/root.zig");
const components = @import("components/root.zig");
const game = @import("game/root.zig");

pub const EventBuss = struct {
    timer: misc.Timer(.{}),
    dx12_context: ?dx12.Context(buffer_count, srv_heap_size),
    ui_context: ?ui.Context,
    game_memory: ?game.Memory,

    const Self = @This();
    const buffer_count = 3;
    const srv_heap_size = 64;

    pub fn init(
        allocator: std.mem.Allocator,
        base_dir: *const misc.BaseDir,
        window: w32.HWND,
        device: *const w32.ID3D12Device,
        command_queue: *const w32.ID3D12CommandQueue,
        swap_chain: *const w32.IDXGISwapChain,
    ) Self {
        std.log.debug("Initializing DX12 context...", .{});
        const dx12_context = if (dx12.Context(buffer_count, srv_heap_size).init(
            allocator,
            device,
            swap_chain,
        )) |context| block: {
            std.log.info("DX12 context initialized.", .{});
            break :block context;
        } else |err| block: {
            misc.error_context.append("Failed to initialize DX12 context.", .{});
            misc.error_context.logError(err);
            break :block null;
        };

        const ui_context = if (dx12_context) |*dxc| block: {
            std.log.debug("Initializing UI context...", .{});
            if (ui.Context.init(
                buffer_count,
                srv_heap_size,
                allocator,
                base_dir,
                window,
                device,
                command_queue,
                dxc.srv_descriptor_heap,
                dxc.srv_allocator,
            )) |context| {
                std.log.info("UI context initialized.", .{});
                break :block context;
            } else |err| {
                misc.error_context.append("Failed to initialize UI context.", .{});
                misc.error_context.logError(err);
                break :block null;
            }
        } else null;

        std.log.debug("Initializing game memory...", .{});
        var game_memory: ?game.Memory = null;
        if (std.Thread.spawn(.{}, struct {
            fn call(out: *?game.Memory, alloc: std.mem.Allocator, dir: *const misc.BaseDir) void {
                out.* = game.Memory.init(alloc, dir);
            }
        }.call, .{ &game_memory, allocator, base_dir })) |thread| {
            thread.join();
            std.log.info("Game memory initialized.", .{});
        } else |err| {
            misc.error_context.new("Failed to spawn game memory thread.", .{});
            misc.error_context.append("Failed to initialize game memory.", .{});
            misc.error_context.logError(err);
        }

        return .{
            .timer = .{},
            .dx12_context = dx12_context,
            .ui_context = ui_context,
            .game_memory = game_memory,
        };
    }

    pub fn deinit(
        self: *Self,
        base_dir: *const misc.BaseDir,
        window: w32.HWND,
        device: *const w32.ID3D12Device,
        command_queue: *const w32.ID3D12CommandQueue,
        swap_chain: *const w32.IDXGISwapChain,
    ) void {
        _ = base_dir;
        _ = swap_chain;
        _ = window;
        _ = device;
        _ = command_queue;

        std.log.debug("De-initializing UI context...", .{});
        if (self.ui_context) |*context| {
            context.deinit();
            self.ui_context = null;
            std.log.info("UI context de-initialized.", .{});
        } else {
            std.log.debug("Nothing to de-initialize.", .{});
        }

        std.log.debug("De-initializing DX12 context...", .{});
        if (self.dx12_context) |*context| {
            context.deinit();
            self.dx12_context = null;
            std.log.info("DX12 context de-initialized.", .{});
        } else {
            std.log.debug("Nothing to de-initialize.", .{});
        }
    }

    pub fn update(
        self: *Self,
        base_dir: *const misc.BaseDir,
        window: w32.HWND,
        device: *const w32.ID3D12Device,
        command_queue: *const w32.ID3D12CommandQueue,
        swap_chain: *const w32.IDXGISwapChain,
    ) void {
        _ = base_dir;
        _ = window;
        _ = device;

        const delta_time = self.timer.measureDeltaTime();
        ui.toasts.update(delta_time);

        const dx12_context = if (self.dx12_context) |*context| context else return;
        const ui_context = if (self.ui_context) |*context| context else return;
        const game_memory = if (self.game_memory) |*memory| memory else return;

        ui_context.newFrame();
        imgui.igGetIO().*.MouseDrawCursor = true;
        ui.toasts.draw();
        components.drawLogsWindow(dll.buffer_logger, null);
        components.drawGameMemoryWindow(game_memory, null);
        hello_world: {
            const is_open = imgui.igBegin("Hello World", null, 0);
            defer imgui.igEnd();
            if (!is_open) break :hello_world;
            if (imgui.igButton("Send Toast", .{})) {
                ui.toasts.send(.info, null, "Toast sent. Delta time is: {}", .{delta_time});
            }
            if (imgui.igButton("Log Error", .{})) {
                misc.error_context.new("User clicked the log error button.", .{});
                misc.error_context.append("This is a test error.", .{});
                misc.error_context.logError(error.Test);
            }
        }
        ui_context.endFrame();

        const buffer_context = dx12.beforeRender(buffer_count, srv_heap_size, dx12_context, swap_chain) catch |err| {
            misc.error_context.append("Failed to execute DX12 before render code.", .{});
            misc.error_context.logError(err);
            return;
        };
        ui_context.render(buffer_context.command_list);
        dx12.afterRender(buffer_context, command_queue) catch |err| {
            misc.error_context.append("Failed to execute DX12 after render code.", .{});
            misc.error_context.logError(err);
            return;
        };
    }

    pub fn beforeResize(
        self: *Self,
        base_dir: *const misc.BaseDir,
        window: w32.HWND,
        device: *const w32.ID3D12Device,
        command_queue: *const w32.ID3D12CommandQueue,
        swap_chain: *const w32.IDXGISwapChain,
    ) void {
        _ = base_dir;
        _ = window;
        _ = device;
        _ = command_queue;
        _ = swap_chain;
        std.log.debug("De-initializing DX12 buffer contexts...", .{});
        if (self.dx12_context) |*context| {
            context.deinitBufferContexts();
            std.log.info("DX12 buffer contexts de-initialized.", .{});
        } else {
            std.log.debug("Nothing to de-initialize.", .{});
        }
    }

    pub fn afterResize(
        self: *Self,
        base_dir: *const misc.BaseDir,
        window: w32.HWND,
        device: *const w32.ID3D12Device,
        command_queue: *const w32.ID3D12CommandQueue,
        swap_chain: *const w32.IDXGISwapChain,
    ) void {
        _ = base_dir;
        _ = window;
        _ = command_queue;
        std.log.debug("Re-initializing DX12 buffer contexts...", .{});
        if (self.dx12_context) |*context| {
            if (context.reinitBufferContexts(device, swap_chain)) {
                std.log.info("DX12 buffer contexts re-initialized.", .{});
            } else |err| {
                misc.error_context.append("Failed to re-initialize DX12 buffer contexts.", .{});
                misc.error_context.logError(err);
            }
        } else {
            std.log.debug("Nothing to re-initialize.", .{});
        }
    }

    pub fn processWindowMessage(
        self: *Self,
        base_dir: *const misc.BaseDir,
        window: w32.HWND,
        u_msg: u32,
        w_param: w32.WPARAM,
        l_param: w32.LPARAM,
    ) ?w32.LRESULT {
        _ = base_dir;
        if (self.ui_context) |*context| {
            return context.processWindowMessage(window, u_msg, w_param, l_param);
        }
        return null;
    }
};
