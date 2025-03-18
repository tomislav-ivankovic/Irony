const std = @import("std");
const w32 = @import("win32").everything;
const imgui = @import("imgui");
const imgui_backend = @import("gui/root.zig").backend;
const dx12 = @import("dx12/root.zig");
const misc = @import("misc/root.zig");

pub const EventBuss = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    dx12_context: ?dx12.Context(buffer_count, srv_heap_size),
    is_gui_initialized: bool,

    const Self = @This();
    const buffer_count = 3;
    const srv_heap_size = 64;

    pub fn init(
        window: w32.HWND,
        device: *const w32.ID3D12Device,
        command_queue: *const w32.ID3D12CommandQueue,
        swap_chain: *const w32.IDXGISwapChain,
    ) Self {
        const gpa = std.heap.GeneralPurposeAllocator(.{}){};

        std.log.debug("Initializing DX12 context...", .{});
        var dx12_context = if (dx12.Context(buffer_count, srv_heap_size).init(device, swap_chain)) |context| block: {
            std.log.info("DX12 context initialized.", .{});
            break :block context;
        } else |err| block: {
            misc.errorContext().append(err, "Failed to initialize DX12 context.");
            misc.errorContext().logError();
            break :block null;
        };

        const is_gui_initialized = if (dx12_context) |*context| block: {
            std.log.debug("Initializing GUI...", .{});
            _ = imgui.igCreateContext(null);
            imgui.igGetIO().*.MouseDrawCursor = true;
            imgui.igStyleColorsDark(null);
            _ = imgui_backend.ImGui_ImplWin32_Init(window);
            _ = imgui_backend.ImGui_ImplDX12_Init(&.{
                .device = device,
                .command_queue = command_queue,
                .num_frames_in_flight = buffer_count,
                .rtv_format = w32.DXGI_FORMAT_R8G8B8A8_UNORM,
                .dsv_format = w32.DXGI_FORMAT_UNKNOWN,
                .cbv_srv_heap = context.srv_descriptor_heap,
                .user_data = &context.srv_allocator,
                .srv_desc_alloc_fn = struct {
                    fn call(
                        info: *imgui_backend.ImGui_ImplDX12_InitInfo,
                        cpu_handle: *w32.D3D12_CPU_DESCRIPTOR_HANDLE,
                        gpu_handle: *w32.D3D12_GPU_DESCRIPTOR_HANDLE,
                    ) callconv(.C) void {
                        const allocator: *dx12.DescriptorHeapAllocator(srv_heap_size) = @alignCast(@ptrCast(info.user_data));
                        allocator.alloc(cpu_handle, gpu_handle) catch |err| {
                            misc.errorContext().append(err, "Failed to allocate memory on SRV heap.");
                            misc.errorContext().logError();
                        };
                    }
                }.call,
                .srv_desc_free_fn = struct {
                    fn call(
                        info: *imgui_backend.ImGui_ImplDX12_InitInfo,
                        cpu_handle: w32.D3D12_CPU_DESCRIPTOR_HANDLE,
                        gpu_handle: w32.D3D12_GPU_DESCRIPTOR_HANDLE,
                    ) callconv(.C) void {
                        const allocator: *dx12.DescriptorHeapAllocator(srv_heap_size) = @alignCast(@ptrCast(info.user_data));
                        allocator.free(cpu_handle, gpu_handle) catch |err| {
                            misc.errorContext().append(err, "Failed to free memory on SRV heap.");
                            misc.errorContext().logError();
                        };
                    }
                }.call,
                .font_srv_cpu_desc_handle = dx12.getCpuDescriptorHandleForHeapStart(context.srv_descriptor_heap),
                .font_srv_gpu_desc_handle = dx12.getGpuDescriptorHandleForHeapStart(context.srv_descriptor_heap),
            });
            _ = imgui_backend.ImGui_ImplDX12_CreateDeviceObjects();
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
            imgui_backend.ImGui_ImplDX12_Shutdown();
            imgui_backend.ImGui_ImplWin32_Shutdown();
            imgui.igDestroyContext(null);
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

        const dx12_context = if (self.dx12_context) |*context| context else return;

        imgui_backend.ImGui_ImplDX12_NewFrame();
        imgui_backend.ImGui_ImplWin32_NewFrame();
        imgui.igNewFrame();

        imgui.igGetIO().*.MouseDrawCursor = true;
        imgui.igShowDemoWindow(null);

        imgui.igEndFrame();

        const buffer_context = dx12.beforeRender(buffer_count, srv_heap_size, dx12_context, swap_chain) catch |err| {
            misc.errorContext().append(err, "Failed to execute DX12 before render code.");
            misc.errorContext().logError();
            return;
        };

        imgui.igRender();
        imgui_backend.ImGui_ImplDX12_RenderDrawData(imgui.igGetDrawData(), buffer_context.command_list);

        dx12.afterRender(buffer_context, command_queue) catch |err| {
            misc.errorContext().append(err, "Failed to execute DX12 after render code.");
            misc.errorContext().logError();
            return;
        };
    }

    pub fn processWindowMessage(
        self: *Self,
        window: w32.HWND,
        u_msg: u32,
        w_param: w32.WPARAM,
        l_param: w32.LPARAM,
    ) ?w32.LRESULT {
        if (self.is_gui_initialized) {
            const result = imgui_backend.ImGui_ImplWin32_WndProcHandler(window, u_msg, w_param, l_param);
            if (result != 0) {
                return result;
            }
        }
        return null;
    }
};
