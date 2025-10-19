const std = @import("std");
const w32 = @import("win32").everything;
const imgui = @import("imgui");
const sdk = @import("../sdk/root.zig");
const core = @import("core/root.zig");
const model = @import("model/root.zig");
const ui = @import("ui/root.zig");
const game = @import("game/root.zig");

pub const EventBuss = struct {
    timer: sdk.misc.Timer(.{}),
    dx12_context: ?Dx12Context,
    ui_context: ?sdk.ui.Context,
    settings_task: SettingsTask,
    core: core.Core,
    main_window: ui.MainWindow,

    const Self = @This();
    const Dx12Context = sdk.dx12.Context(buffer_count, srv_heap_size);
    const SettingsTask = sdk.misc.Task(model.Settings);

    const buffer_count = 3;
    const srv_heap_size = 64;

    pub fn init(
        allocator: std.mem.Allocator,
        base_dir: *const sdk.fs.BaseDir,
        window: w32.HWND,
        device: *const w32.ID3D12Device,
        command_queue: *const w32.ID3D12CommandQueue,
        swap_chain: *const w32.IDXGISwapChain,
    ) Self {
        std.log.debug("Initializing DX12 context...", .{});
        const dx12_context = if (Dx12Context.init(
            allocator,
            device,
            swap_chain,
        )) |context| block: {
            std.log.info("DX12 context initialized.", .{});
            break :block context;
        } else |err| block: {
            sdk.misc.error_context.append("Failed to initialize DX12 context.", .{});
            sdk.misc.error_context.logError(err);
            break :block null;
        };

        const ui_context = if (dx12_context) |*dxc| block: {
            std.log.debug("Initializing UI context...", .{});
            if (sdk.ui.Context.init(
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
                sdk.misc.error_context.append("Failed to initialize UI context.", .{});
                sdk.misc.error_context.logError(err);
                break :block null;
            }
        } else null;

        std.log.debug("Spawning settings loading task...", .{});
        const settings_task = SettingsTask.spawn(allocator, struct {
            fn call(dir: *const sdk.fs.BaseDir) model.Settings {
                std.log.info("Settings loading task spawned.", .{});
                std.log.debug("Loading settings...", .{});
                if (model.Settings.load(dir)) |settings| {
                    std.log.info("Settings loaded.", .{});
                    return settings;
                } else |err_1| {
                    sdk.misc.error_context.append("Failed to load settings. Using default settings.", .{});
                    sdk.misc.error_context.logWarning(err_1);
                    const default_settings = model.Settings{};
                    if (err_1 == error.FileNotFound) {
                        std.log.info("Saving default settings...", .{});
                        if (default_settings.save(dir)) {
                            std.log.info("Default settings saved.", .{});
                        } else |err_2| {
                            sdk.misc.error_context.append("Failed to save default settings.", .{});
                            sdk.misc.error_context.logError(err_2);
                        }
                    }
                    return default_settings;
                }
            }
        }.call, .{base_dir}) catch |err| block: {
            sdk.misc.error_context.append("Failed to spawn settings loading task. Using default settings.", .{});
            sdk.misc.error_context.logWarning(err);
            break :block SettingsTask.createCompleted(.{});
        };
        errdefer _ = settings_task.join();

        std.log.debug("Initializing core...", .{});
        const c = core.Core.init(allocator);
        std.log.info("Core initialized.", .{});

        return .{
            .timer = .{},
            .dx12_context = dx12_context,
            .ui_context = ui_context,
            .settings_task = settings_task,
            .core = c,
            .main_window = .{},
        };
    }

    pub fn deinit(
        self: *Self,
        base_dir: *const sdk.fs.BaseDir,
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

        std.log.debug("Joining settings loading task...", .{});
        _ = self.settings_task.join();
        std.log.info("Settings loading task joined.", .{});

        std.log.debug("De-initializing core...", .{});
        self.core.deinit();
        std.log.info("Core de-initialized.", .{});

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

    fn processFrame(self: *Self, frame: *const model.Frame) void {
        const settings = self.settings_task.peek() orelse return;
        self.main_window.processFrame(settings, frame);
    }

    pub fn tick(self: *Self, game_memory: *const game.Memory) void {
        self.core.tick(game_memory, self, processFrame);
    }

    pub fn draw(
        self: *Self,
        base_dir: *const sdk.fs.BaseDir,
        window: w32.HWND,
        device: *const w32.ID3D12Device,
        command_queue: *const w32.ID3D12CommandQueue,
        swap_chain: *const w32.IDXGISwapChain,
        game_memory: ?*const game.Memory,
    ) void {
        _ = window;
        _ = device;

        const delta_time = self.timer.measureDeltaTime();
        self.core.update(delta_time, self, processFrame);
        sdk.ui.toasts.update(delta_time);
        self.main_window.update(delta_time);

        const dx12_context = if (self.dx12_context) |*context| context else return;
        const ui_context = if (self.ui_context) |*context| context else return;

        ui_context.newFrame();
        imgui.igGetIO_Nil().*.MouseDrawCursor = true;
        sdk.ui.toasts.draw();
        if (game_memory) |memory| {
            if (self.settings_task.peek()) |settings| {
                self.main_window.draw(base_dir, settings, memory, &self.core.controller);
            } else {
                ui.drawMessageWindow("Loading", "Loading settings...", .center);
            }
        } else {
            ui.drawMessageWindow("Loading", "Searching for memory addresses and offsets...", .center);
        }
        if (self.core.controller.mode == .record) {
            ui.drawMessageWindow("Recording", "⏺ Recording...", .top);
        }
        ui_context.endFrame();

        const buffer_context = sdk.dx12.beforeRender(buffer_count, srv_heap_size, dx12_context, swap_chain) catch |err| {
            sdk.misc.error_context.append("Failed to execute DX12 before render code.", .{});
            sdk.misc.error_context.logError(err);
            return;
        };
        ui_context.render(buffer_context.command_list);
        sdk.dx12.afterRender(buffer_context, command_queue) catch |err| {
            sdk.misc.error_context.append("Failed to execute DX12 after render code.", .{});
            sdk.misc.error_context.logError(err);
            return;
        };
    }

    pub fn beforeResize(
        self: *Self,
        base_dir: *const sdk.fs.BaseDir,
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
        base_dir: *const sdk.fs.BaseDir,
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
                sdk.misc.error_context.append("Failed to re-initialize DX12 buffer contexts.", .{});
                sdk.misc.error_context.logError(err);
            }
        } else {
            std.log.debug("Nothing to re-initialize.", .{});
        }
    }

    pub fn processWindowMessage(
        self: *Self,
        base_dir: *const sdk.fs.BaseDir,
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
