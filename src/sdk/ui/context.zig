const std = @import("std");
const builtin = @import("builtin");
const build_info = @import("build_info");
const w32 = @import("win32").everything;
const imgui = @import("imgui");
const misc = @import("../misc/root.zig");
const dx11 = @import("../dx11/root.zig");
const dx12 = @import("../dx12/root.zig");
const ui = @import("root.zig");

const font_file = @embedFile("font.ttf");
pub const default_font_size = 18;

pub fn Context(comptime rendering_api: build_info.RenderingApi) type {
    const dx = switch (rendering_api) {
        .dx11 => dx11,
        .dx12 => dx12,
    };
    return struct {
        allocator: std.mem.Allocator,
        old_allocator: ?std.mem.Allocator,
        imgui_context: *imgui.ImGuiContext,
        file_dialog_context: *imgui.ImGuiFileDialog,
        ini_file_path: ?[:0]const u8,
        test_allocation: if (builtin.is_test) *u8 else void,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, base_dir: ?*const misc.BaseDir, dx_context: *const dx.Context) !Self {
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

            imgui.igGetIO_Nil().*.IniFilename = ini_file_path orelse null;
            errdefer imgui.igGetIO_Nil().*.IniFilename = null;

            imgui.igStyleColorsDark(null);

            imgui.igGetIO_Nil().*.ConfigInputTrickleEventQueue = false;
            errdefer imgui.igGetIO_Nil().*.ConfigInputTrickleEventQueue = true;

            const font_config = imgui.ImFontConfig_ImFontConfig();
            defer imgui.ImFontConfig_destroy(font_config);
            font_config.*.FontDataOwnedByAtlas = false;
            if (imgui.ImFontAtlas_AddFontFromMemoryTTF(
                imgui.igGetIO_Nil().*.Fonts,
                @constCast(font_file.ptr),
                font_file.len,
                default_font_size,
                font_config,
                null,
            )) |font| {
                imgui.igGetIO_Nil().*.FontDefault = font;
            } else {
                misc.error_context.new("ImFontAtlas_AddFontFromMemoryTTF returned null.", .{});
                misc.error_context.append("Failed to load UI font. Falling back to default font.", .{});
                misc.error_context.logError(error.ImguiError);
            }

            const win32_success = ui.backend.ImGui_ImplWin32_Init(dx_context.window);
            if (!win32_success) {
                misc.error_context.new("ImGui_ImplWin32_Init returned false.", .{});
                return error.ImguiError;
            }
            errdefer ui.backend.ImGui_ImplWin32_Shutdown();

            switch (rendering_api) {
                .dx11 => {
                    const success = ui.backend.ImGui_ImplDX11_Init(dx_context.device, dx_context.device_context);
                    if (!success) {
                        misc.error_context.new("ImGui_ImplDX11_Init returned false.", .{});
                        return error.ImguiError;
                    }
                },
                .dx12 => {
                    const init_info = ui.backend.ImGui_ImplDX12_InitInfo{
                        .device = dx_context.device,
                        .command_queue = dx_context.command_queue,
                        .num_frames_in_flight = @intCast(dx_context.buffer_contexts.len),
                        .rtv_format = w32.DXGI_FORMAT_R8G8B8A8_UNORM,
                        .dsv_format = w32.DXGI_FORMAT_UNKNOWN,
                        .cbv_srv_heap = dx_context.srv_descriptor_heap,
                        .user_data = dx_context.srv_allocator,
                        .srv_desc_alloc_fn = struct {
                            fn call(
                                info: *ui.backend.ImGui_ImplDX12_InitInfo,
                                cpu_handle: *w32.D3D12_CPU_DESCRIPTOR_HANDLE,
                                gpu_handle: *w32.D3D12_GPU_DESCRIPTOR_HANDLE,
                            ) callconv(.c) void {
                                const a: @TypeOf(dx_context.srv_allocator) = @ptrCast(@alignCast(info.user_data));
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
                                const a: @TypeOf(dx_context.srv_allocator) = @ptrCast(@alignCast(info.user_data));
                                a.free(cpu_handle, gpu_handle) catch |err| {
                                    misc.error_context.append("Failed to free memory on SRV heap.", .{});
                                    misc.error_context.logError(err);
                                };
                            }
                        }.call,
                        .font_srv_cpu_desc_handle = dx12.getCpuDescriptorHandleForHeapStart(dx_context.srv_descriptor_heap),
                        .font_srv_gpu_desc_handle = dx12.getGpuDescriptorHandleForHeapStart(dx_context.srv_descriptor_heap),
                    };
                    const success = ui.backend.ImGui_ImplDX12_Init(&init_info);
                    if (!success) {
                        misc.error_context.new("ImGui_ImplDX12_Init returned false.", .{});
                        return error.ImguiError;
                    }
                },
            }
            errdefer switch (rendering_api) {
                .dx11 => ui.backend.ImGui_ImplDX11_Shutdown(),
                .dx12 => ui.backend.ImGui_ImplDX12_Shutdown(),
            };

            const file_dialog_context = imgui.IGFD_Create() orelse {
                misc.error_context.new("IGFD_Create returned null.", .{});
                return error.ImguiError;
            };

            const test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {};

            return .{
                .allocator = allocator,
                .old_allocator = old_allocator,
                .imgui_context = imgui_context,
                .file_dialog_context = file_dialog_context,
                .ini_file_path = ini_file_path,
                .test_allocation = test_allocation,
            };
        }

        pub fn deinit(self: *const Self) void {
            imgui.igSetCurrentContext(self.imgui_context);
            imgui.IGFD_Destroy(self.file_dialog_context);
            switch (rendering_api) {
                .dx11 => ui.backend.ImGui_ImplDX11_Shutdown(),
                .dx12 => ui.backend.ImGui_ImplDX12_Shutdown(),
            }
            ui.backend.ImGui_ImplWin32_Shutdown();
            imgui.igGetIO_Nil().*.ConfigInputTrickleEventQueue = true;
            imgui.igGetIO_Nil().*.IniFilename = null;
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
            switch (rendering_api) {
                .dx11 => ui.backend.ImGui_ImplDX11_NewFrame(),
                .dx12 => ui.backend.ImGui_ImplDX12_NewFrame(),
            }
            ui.backend.ImGui_ImplWin32_NewFrame();
            imgui.igNewFrame();
        }

        pub fn endFrame(self: *const Self) void {
            imgui.igSetCurrentContext(self.imgui_context);
            imgui.igEndFrame();
        }

        pub fn render(self: *const Self, buffer_context: *const dx.BufferContext) void {
            imgui.igSetCurrentContext(self.imgui_context);
            imgui.igRender();
            const draw_data = imgui.igGetDrawData();
            switch (rendering_api) {
                .dx11 => ui.backend.ImGui_ImplDX11_RenderDrawData(draw_data),
                .dx12 => ui.backend.ImGui_ImplDX12_RenderDrawData(draw_data, buffer_context.command_list),
            }
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
            if (is_mouse_event and imgui.igGetIO_Nil().*.WantCaptureMouse) {
                return 1;
            }
            const is_keyboard_event = u_msg >= w32.WM_KEYFIRST and u_msg <= w32.WM_KEYLAST;
            if (is_keyboard_event and imgui.igGetIO_Nil().*.WantCaptureKeyboard) {
                return 1;
            }
            return null;
        }
    };
}

const testing = std.testing;

test "should render hello world successfully when rendering api is dx11" {
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx11.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    const dx11_context = dx11.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    const ui_context = try Context(.dx11).init(testing.allocator, null, &dx11_context);
    defer ui_context.deinit();

    ui_context.newFrame();
    if (imgui.igBegin("Hello world.", null, 0)) {
        imgui.igText("Hello world.", .{});
    }
    imgui.igEnd();
    ui_context.endFrame();

    const buffer_context = try dx11_context.beforeRender();
    ui_context.render(buffer_context);
    try dx11_context.afterRender(buffer_context);
}

test "should render hello world successfully when rendering api is dx12" {
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx12.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    const dx12_context = dx12.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    const ui_context = try Context(.dx12).init(testing.allocator, null, &dx12_context);
    defer ui_context.deinit();

    ui_context.newFrame();
    if (imgui.igBegin("Hello world.", null, 0)) {
        imgui.igText("Hello world.", .{});
    }
    imgui.igEnd();
    ui_context.endFrame();

    const buffer_context = try dx12_context.beforeRender();
    ui_context.render(buffer_context);
    try dx12_context.afterRender(buffer_context);
}
