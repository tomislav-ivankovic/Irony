const std = @import("std");
const w32 = @import("win32").everything;
const imgui = @import("imgui");
const misc = @import("misc/root.zig");
const dx12 = @import("dx12/root.zig");
const ui = @import("ui/root.zig");
const game = @import("game/root.zig");

pub const EventBuss = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    dx12_context: ?dx12.Context(buffer_count, srv_heap_size),
    ui_context: ?ui.Context,
    game_memory: game.Memory,

    const Self = @This();
    const buffer_count = 3;
    const srv_heap_size = 64;

    pub fn init(
        base_dir: *const misc.BaseDir,
        window: w32.HWND,
        device: *const w32.ID3D12Device,
        command_queue: *const w32.ID3D12CommandQueue,
        swap_chain: *const w32.IDXGISwapChain,
    ) Self {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};

        std.log.debug("Initializing DX12 context...", .{});
        const dx12_context = if (dx12.Context(buffer_count, srv_heap_size).init(
            gpa.allocator(),
            device,
            swap_chain,
        )) |context| block: {
            std.log.info("DX12 context initialized.", .{});
            break :block context;
        } else |err| block: {
            misc.errorContext().append(err, "Failed to initialize DX12 context.");
            misc.errorContext().logError();
            break :block null;
        };

        const ui_context = if (dx12_context) |*dxc| block: {
            std.log.debug("Initializing UI context...", .{});
            if (ui.Context.init(
                buffer_count,
                srv_heap_size,
                gpa.allocator(),
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
                misc.errorContext().append(err, "Failed to initialize UI context.");
                misc.errorContext().logError();
                break :block null;
            }
        } else null;

        std.log.debug("Initializing game memory...", .{});
        const game_memory = game.Memory.init();
        std.log.info("Game memory initialized.", .{});

        return .{
            .gpa = gpa,
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
            context.deinit(self.gpa.allocator());
            self.ui_context = null;
            std.log.info("UI context de-initialized.", .{});
        } else {
            std.log.debug("Nothing to de-initialize.", .{});
        }

        std.log.debug("De-initializing DX12 context...", .{});
        if (self.dx12_context) |*context| {
            context.deinit(self.gpa.allocator());
            self.dx12_context = null;
            std.log.info("DX12 context de-initialized.", .{});
        } else {
            std.log.debug("Nothing to de-initialize.", .{});
        }

        switch (self.gpa.deinit()) {
            .ok => {},
            .leak => std.log.err("GPA detected a memory leak.", .{}),
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

        const dx12_context = if (self.dx12_context) |*context| context else return;
        const ui_context = if (self.ui_context) |*context| context else return;

        ui_context.newFrame();
        imgui.igGetIO().*.MouseDrawCursor = true;
        // imgui.igShowDemoWindow(null);
        if (imgui.igBegin("Hello world.", null, imgui.ImGuiWindowFlags_NoCollapse)) {
            imgui.igText("Hello world.");
            if (self.game_memory.player_1.toConstPointer()) |player_1| {
                imgui.igText("Player 1 health: %d", player_1.health);
            } else {
                imgui.igText("Player 1 not found.");
            }
            if (self.game_memory.player_2.toConstPointer()) |player_2| {
                imgui.igText("Player 2 health: %d", player_2.health);
            } else {
                imgui.igText("Player 2 not found.");
            }
            imgui.igEnd();
        }
        ui_context.endFrame();

        const buffer_context = dx12.beforeRender(buffer_count, srv_heap_size, dx12_context, swap_chain) catch |err| {
            misc.errorContext().append(err, "Failed to execute DX12 before render code.");
            misc.errorContext().logError();
            return;
        };
        ui_context.render(buffer_context.command_list);
        dx12.afterRender(buffer_context, command_queue) catch |err| {
            misc.errorContext().append(err, "Failed to execute DX12 after render code.");
            misc.errorContext().logError();
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
                misc.errorContext().append(err, "Failed to re-initialize DX12 buffer contexts.");
                misc.errorContext().logError();
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
