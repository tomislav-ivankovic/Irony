const std = @import("std");
const w32 = @import("win32").everything;
const gui = @import("gui/root.zig");
const dx12 = @import("dx12/root.zig");
const misc = @import("misc/root.zig");

pub const EventBuss = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    dx12_context: ?dx12.Context(buffer_count),
    is_gui_initialized: bool,

    const Self = @This();
    const buffer_count = 3;

    pub fn init(
        window: w32.HWND,
        device: *const w32.ID3D12Device,
        command_queue: *const w32.ID3D12CommandQueue,
        swap_chain: *const w32.IDXGISwapChain,
    ) Self {
        _ = swap_chain;

        const gpa = std.heap.GeneralPurposeAllocator(.{}){};

        std.log.debug("Initializing DX12 context...", .{});
        const dx12_context = if (dx12.Context(buffer_count).init(device)) |leftovers| block: {
            std.log.info("DX12 context initialized.", .{});
            break :block leftovers;
        } else |err| block: {
            misc.errorContext().append(err, "Failed to initialize DX12 context.");
            misc.errorContext().logError();
            break :block null;
        };

        const is_gui_initialized = if (dx12_context) |context| block: {
            std.log.debug("Initializing GUI...", .{});
            _ = gui.imgui.igCreateContext(null);
            _ = window;
            _ = gui.dx12.ImGui_ImplDX12_Init(&.{
                .device = device,
                .command_queue = command_queue,
                .num_frames_in_flight = buffer_count,
                .rtv_format = w32.DXGI_FORMAT_R8G8B8A8_UNORM,
                .dsv_format = w32.DXGI_FORMAT_UNKNOWN,
                .cbv_srv_heap = context.srv_descriptor_heap,
                .font_srv_cpu_desc_handle = dx12.getCpuDescriptorHandleForHeapStart(context.srv_descriptor_heap),
                .font_srv_gpu_desc_handle = dx12.getGpuDescriptorHandleForHeapStart(context.srv_descriptor_heap),
            });
            std.log.info("GUI initialized.", .{});
            break :block true;
        } else false;

        return .{
            .gpa = gpa,
            .dx12_context = dx12_context,
            .is_gui_initialized = is_gui_initialized,
        };
    }

    pub fn deinit(
        self: *Self,
        window: w32.HWND,
        device: *const w32.ID3D12Device,
        command_queue: *const w32.ID3D12CommandQueue,
        swap_chain: *const w32.IDXGISwapChain,
    ) void {
        _ = swap_chain;
        _ = window;
        _ = device;
        _ = command_queue;

        std.log.debug("De-initializing GUI...", .{});
        if (self.is_gui_initialized) {
            gui.dx12.ImGui_ImplDX12_Shutdown();
            gui.imgui.igDestroyContext(null);
            self.is_gui_initialized = false;
            std.log.info("GUI de-initialized.", .{});
        } else {
            std.log.debug("Nothing to de-initialize.", .{});
        }

        std.log.debug("De-initializing DX12 context...", .{});
        if (self.dx12_context) |context| {
            context.deinit();
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
        window: w32.HWND,
        device: *const w32.ID3D12Device,
        command_queue: *const w32.ID3D12CommandQueue,
        swap_chain: *const w32.IDXGISwapChain,
    ) void {
        _ = window;
        _ = device;

        const dx12_context = self.dx12_context orelse return;

        const swap_chain_3: *const w32.IDXGISwapChain3 = @ptrCast(swap_chain);
        var frame_buffer_width: u32 = undefined;
        var frame_buffer_height: u32 = undefined;
        const size_return_code = swap_chain_3.IDXGISwapChain2_GetSourceSize(&frame_buffer_width, &frame_buffer_height);
        if (size_return_code != w32.S_OK) {
            misc.errorContext().newFmt(
                error.Dx12Error,
                "IDXGISwapChain2.GetSourceSize returned: {}",
                .{size_return_code},
            );
            misc.errorContext().append(error.Dx12Error, "Failed to get frame buffer width and height.");
            misc.errorContext().logError();
        }

        gui.dx12.ImGui_ImplDX12_NewFrame();
        gui.imgui.igNewFrame();
        gui.imgui.igText("Hello World!", .{});
        gui.imgui.igEndFrame();

        const frame_index = swap_chain_3.IDXGISwapChain3_GetCurrentBackBufferIndex();
        if (frame_index >= buffer_count) {
            std.log.err("IDXGISwapChain3.GetCurrentBackBufferIndex returned: {}", .{frame_index});
            return;
        }
        const frame_context = dx12_context.frame_contexts[frame_index];

        var return_code = w32.S_OK;
        var buffer: *w32.ID3D12Resource = undefined;
        return_code = swap_chain.IDXGISwapChain_GetBuffer(frame_index, w32.IID_ID3D12Resource, @ptrCast(&buffer));
        if (return_code != w32.S_OK) {
            std.log.err("IDXGISwapChain_GetBuffer returned: {}", .{return_code});
        }

        return_code = frame_context.command_allocator.ID3D12CommandAllocator_Reset();
        if (return_code != w32.S_OK) {
            std.log.err("ID3D12CommandAllocator_Reset returned: {}", .{return_code});
        }
        return_code = frame_context.command_list.ID3D12GraphicsCommandList_Reset(frame_context.command_allocator, null);
        if (return_code != w32.S_OK) {
            std.log.err("ID3D12GraphicsCommandList_Reset returned: {}", .{return_code});
        }
        frame_context.command_list.ID3D12GraphicsCommandList_ResourceBarrier(1, &.{.{
            .Type = .TRANSITION,
            .Flags = .{},
            .Anonymous = .{ .Transition = .{
                .pResource = buffer,
                .Subresource = w32.D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                .StateBefore = w32.D3D12_RESOURCE_STATE_PRESENT,
                .StateAfter = w32.D3D12_RESOURCE_STATE_RENDER_TARGET,
            } },
        }});
        frame_context.command_list.ID3D12GraphicsCommandList_OMSetRenderTargets(
            1,
            &frame_context.rtv_descriptor_handle,
            0,
            null,
        );
        var heaps = [1](?*w32.ID3D12DescriptorHeap){dx12_context.rtv_descriptor_heap};
        frame_context.command_list.ID3D12GraphicsCommandList_SetDescriptorHeaps(1, &heaps);

        gui.imgui.igRender();
        gui.dx12.ImGui_ImplDX12_RenderDrawData(gui.imgui.igGetDrawData(), frame_context.command_list);

        frame_context.command_list.ID3D12GraphicsCommandList_ResourceBarrier(1, &.{.{
            .Type = .TRANSITION,
            .Flags = .{},
            .Anonymous = .{ .Transition = .{
                .pResource = buffer,
                .Subresource = w32.D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                .StateBefore = w32.D3D12_RESOURCE_STATE_RENDER_TARGET,
                .StateAfter = w32.D3D12_RESOURCE_STATE_PRESENT,
            } },
        }});
        return_code = frame_context.command_list.ID3D12GraphicsCommandList_Close();
        if (return_code != w32.S_OK) {
            std.log.err("ID3D12GraphicsCommandList_Close returned: {}", .{return_code});
        }

        var lists = [1](?*w32.ID3D12CommandList){@ptrCast(frame_context.command_list)};
        command_queue.ID3D12CommandQueue_ExecuteCommandLists(1, &lists);
    }

    pub fn processWindowMessage(
        self: *Self,
        window: w32.HWND,
        u_msg: u32,
        w_param: w32.WPARAM,
        l_param: w32.LPARAM,
    ) ?w32.LRESULT {
        if (self.is_gui_initialized) {
            _ = window;
            _ = u_msg;
            _ = w_param;
            _ = l_param;
            // _ = ImGui_ImplWin32_WndProcHandler.?(window, u_msg, w_param, l_param);
        }
        return null;
    }
};

// Bypass for issue: https://github.com/zig-gamedev/zgui/issues/23
// const ImGui_ImplWin32_WndProcHandler = @extern(
//     *const fn (hwnd: *const anyopaque, u_msg: u32, w_param: usize, l_param: isize) callconv(.C) isize,
//     .{
//         .name = "_Z30ImGui_ImplWin32_WndProcHandlerP6HWND__jyx",
//         .linkage = .weak,
//     },
// );
