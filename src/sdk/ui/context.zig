const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const imgui = @import("imgui");
const misc = @import("../misc/root.zig");
const dx12 = @import("../dx12/root.zig");
const ui = @import("root.zig");

pub const Context = struct {
    allocator: std.mem.Allocator,
    old_allocator: ?std.mem.Allocator,
    imgui_context: *imgui.ImGuiContext,
    ini_file_path: ?[:0]const u8,
    test_allocation: if (builtin.is_test) *u8 else void,

    const Self = @This();

    pub fn init(
        comptime buffer_count: usize,
        comptime srv_heap_size: usize,
        allocator: std.mem.Allocator,
        base_dir: ?*const misc.BaseDir,
        window: w32.HWND,
        device: *const w32.ID3D12Device,
        command_queue: *const w32.ID3D12CommandQueue,
        srv_descriptor_heap: *const w32.ID3D12DescriptorHeap,
        srv_heap_allocator: *dx12.DescriptorHeapAllocator(srv_heap_size),
    ) !Self {
        const old_allocator = ui.getAllocator();
        ui.setAllocator(allocator);
        errdefer ui.setAllocator(old_allocator);

        const imgui_context = imgui.igCreateContext(null) orelse {
            misc.error_context.new("igCreateContext returned null.", .{});
            return error.ImguiError;
        };
        errdefer imgui.igDestroyContext(imgui_context);

        const ini_file_path = if (base_dir) |dir| (dir.allocPath(allocator, "imgui.ini") catch |err| b: {
            misc.error_context.append("Failed to allocate imgui.ini file path.", .{});
            misc.error_context.logError(err);
            break :b null;
        }) else null;
        errdefer if (ini_file_path) |path| {
            allocator.free(path);
        };

        imgui.igGetIO().*.IniFilename = ini_file_path orelse null;
        errdefer imgui.igGetIO().*.IniFilename = null;

        imgui.igStyleColorsDark(null);

        const win32_success = ui.backend.ImGui_ImplWin32_Init(window);
        if (!win32_success) {
            misc.error_context.new("ImGui_ImplWin32_Init returned false.", .{});
            return error.ImguiError;
        }
        errdefer ui.backend.ImGui_ImplWin32_Shutdown();

        const dx12_success = ui.backend.ImGui_ImplDX12_Init(&.{
            .device = device,
            .command_queue = command_queue,
            .num_frames_in_flight = buffer_count,
            .rtv_format = w32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .dsv_format = w32.DXGI_FORMAT_UNKNOWN,
            .cbv_srv_heap = srv_descriptor_heap,
            .user_data = srv_heap_allocator,
            .srv_desc_alloc_fn = struct {
                fn call(
                    info: *ui.backend.ImGui_ImplDX12_InitInfo,
                    cpu_handle: *w32.D3D12_CPU_DESCRIPTOR_HANDLE,
                    gpu_handle: *w32.D3D12_GPU_DESCRIPTOR_HANDLE,
                ) callconv(.c) void {
                    const a: *dx12.DescriptorHeapAllocator(srv_heap_size) = @alignCast(@ptrCast(info.user_data));
                    a.alloc(cpu_handle, gpu_handle) catch |err| {
                        misc.error_context.append("Failed to allocate memory on SRV heap.", .{});
                        misc.error_context.logError(err);
                    };
                }
            }.call,
            .srv_desc_free_fn = struct {
                fn call(
                    info: *ui.backend.ImGui_ImplDX12_InitInfo,
                    cpu_handle: w32.D3D12_CPU_DESCRIPTOR_HANDLE,
                    gpu_handle: w32.D3D12_GPU_DESCRIPTOR_HANDLE,
                ) callconv(.c) void {
                    const a: *dx12.DescriptorHeapAllocator(srv_heap_size) = @alignCast(@ptrCast(info.user_data));
                    a.free(cpu_handle, gpu_handle) catch |err| {
                        misc.error_context.append("Failed to free memory on SRV heap.", .{});
                        misc.error_context.logError(err);
                    };
                }
            }.call,
            .font_srv_cpu_desc_handle = dx12.getCpuDescriptorHandleForHeapStart(srv_descriptor_heap),
            .font_srv_gpu_desc_handle = dx12.getGpuDescriptorHandleForHeapStart(srv_descriptor_heap),
        });
        if (!dx12_success) {
            misc.error_context.new("ImGui_ImplDX12_Init returned false.", .{});
            return error.ImguiError;
        }
        errdefer ui.backend.ImGui_ImplDX12_Shutdown();

        const test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {};

        return .{
            .allocator = allocator,
            .old_allocator = old_allocator,
            .imgui_context = imgui_context,
            .ini_file_path = ini_file_path,
            .test_allocation = test_allocation,
        };
    }

    pub fn deinit(self: *const Self) void {
        imgui.igSetCurrentContext(self.imgui_context);
        ui.backend.ImGui_ImplDX12_Shutdown();
        ui.backend.ImGui_ImplWin32_Shutdown();
        imgui.igGetIO().*.IniFilename = null;
        if (self.ini_file_path) |path| {
            self.allocator.free(path);
        }
        imgui.igDestroyContext(self.imgui_context);
        ui.setAllocator(self.old_allocator);

        if (builtin.is_test) {
            std.testing.allocator.destroy(self.test_allocation);
        }
    }

    pub fn newFrame(self: *const Self) void {
        imgui.igSetCurrentContext(self.imgui_context);
        ui.backend.ImGui_ImplDX12_NewFrame();
        ui.backend.ImGui_ImplWin32_NewFrame();
        imgui.igNewFrame();
    }

    pub fn endFrame(self: *const Self) void {
        imgui.igSetCurrentContext(self.imgui_context);
        imgui.igEndFrame();
    }

    pub fn render(self: *const Self, command_list: *const w32.ID3D12GraphicsCommandList) void {
        imgui.igSetCurrentContext(self.imgui_context);
        imgui.igRender();
        ui.backend.ImGui_ImplDX12_RenderDrawData(imgui.igGetDrawData(), command_list);
    }

    pub fn processWindowMessage(
        self: *Self,
        window: w32.HWND,
        u_msg: u32,
        w_param: w32.WPARAM,
        l_param: w32.LPARAM,
    ) ?w32.LRESULT {
        imgui.igSetCurrentContext(self.imgui_context);
        const result = ui.backend.ImGui_ImplWin32_WndProcHandler(window, u_msg, w_param, l_param);
        if (result != 0) {
            return result;
        }
        const is_mouse_event = u_msg >= w32.WM_MOUSEFIRST and u_msg <= w32.WM_MOUSELAST;
        if (is_mouse_event and imgui.igGetIO().*.WantCaptureMouse) {
            return 1;
        }
        const is_keyboard_event = u_msg >= w32.WM_KEYFIRST and u_msg <= w32.WM_KEYLAST;
        if (is_keyboard_event and imgui.igGetIO().*.WantCaptureKeyboard) {
            return 1;
        }
        return null;
    }
};

const testing = std.testing;

test "should render hello world successfully" {
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();

    var dx12_context = try dx12.Context(3, 64).init(
        testing.allocator,
        testing_context.device,
        testing_context.swap_chain,
    );
    defer dx12_context.deinit();

    const ui_context = try Context.init(
        3,
        64,
        testing.allocator,
        null,
        testing_context.window,
        testing_context.device,
        testing_context.command_queue,
        dx12_context.srv_descriptor_heap,
        dx12_context.srv_allocator,
    );
    defer ui_context.deinit();

    ui_context.newFrame();
    if (imgui.igBegin("Hello world.", null, 0)) {
        imgui.igText("Hello world.", .{});
    }
    imgui.igEnd();
    ui_context.endFrame();

    const buffer_context = try dx12.beforeRender(3, 64, &dx12_context, testing_context.swap_chain);
    ui_context.render(buffer_context.command_list);
    try dx12.afterRender(buffer_context, testing_context.command_queue);
}
