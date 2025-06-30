const w32 = @import("win32").everything;
const imgui = @import("imgui");

pub const ImGui_ImplDX12_InitInfo = extern struct {
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    num_frames_in_flight: u32,
    rtv_format: w32.DXGI_FORMAT,
    dsv_format: w32.DXGI_FORMAT,
    user_data: ?*anyopaque = null,
    cbv_srv_heap: *const w32.ID3D12DescriptorHeap,
    srv_desc_alloc_fn: ?*const fn (
        *ImGui_ImplDX12_InitInfo,
        *w32.D3D12_CPU_DESCRIPTOR_HANDLE,
        *w32.D3D12_GPU_DESCRIPTOR_HANDLE,
    ) callconv(.c) void = null,
    srv_desc_free_fn: ?*const fn (
        *ImGui_ImplDX12_InitInfo,
        w32.D3D12_CPU_DESCRIPTOR_HANDLE,
        w32.D3D12_GPU_DESCRIPTOR_HANDLE,
    ) callconv(.c) void = null,
    font_srv_cpu_desc_handle: w32.D3D12_CPU_DESCRIPTOR_HANDLE,
    font_srv_gpu_desc_handle: w32.D3D12_GPU_DESCRIPTOR_HANDLE,
};

pub extern fn ImGui_ImplDX12_Init(init_info: *const ImGui_ImplDX12_InitInfo) bool;
pub extern fn ImGui_ImplDX12_Shutdown() void;
pub extern fn ImGui_ImplDX12_NewFrame() void;
pub extern fn ImGui_ImplDX12_RenderDrawData(
    draw_data: *const imgui.ImDrawData,
    graphics_command_list: *const w32.ID3D12GraphicsCommandList,
) void;
pub extern fn ImGui_ImplDX12_CreateDeviceObjects() bool;
pub extern fn ImGui_ImplDX12_InvalidateDeviceObjects() void;

pub extern fn ImGui_ImplWin32_Init(window: w32.HWND) bool;
pub extern fn ImGui_ImplWin32_Shutdown() void;
pub extern fn ImGui_ImplWin32_NewFrame() void;
pub extern fn ImGui_ImplWin32_WndProcHandler(
    window: w32.HWND,
    u_msg: u32,
    w_param: w32.WPARAM,
    l_param: w32.LPARAM,
) w32.LRESULT;
