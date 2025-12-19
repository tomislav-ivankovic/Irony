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
    managed_dx12_context: ?sdk.dx12.ManagedContext,
    ui_context: ?UiContext,
    settings_task: SettingsTask,
    core: core.Core,
    ui: ui.Ui,

    const Self = @This();
    const SettingsTask = sdk.misc.Task(model.Settings);
    const UiContext = sdk.ui.Context(.dx12);

    const buffer_count = 3;
    const srv_heap_size = 64;

    pub fn init(
        allocator: std.mem.Allocator,
        base_dir: *const sdk.misc.BaseDir,
        host_dx12_context: *const sdk.dx12.HostContext,
    ) Self {
        std.log.debug("Initializing DX12 context...", .{});
        var managed_dx12_context = if (sdk.dx12.ManagedContext.init(allocator, host_dx12_context)) |context| block: {
            std.log.info("DX12 context initialized.", .{});
            break :block context;
        } else |err| block: {
            sdk.misc.error_context.append("Failed to initialize DX12 context.", .{});
            sdk.misc.error_context.logError(err);
            break :block null;
        };

        const dx_12_context = if (managed_dx12_context) |*mdxc| block: {
            break :block sdk.dx12.Context.fromHostAndManaged(host_dx12_context, mdxc);
        } else null;

        const ui_context = if (dx_12_context) |*dxc| block: {
            std.log.debug("Initializing UI context...", .{});
            if (UiContext.init(allocator, base_dir, dxc)) |context| {
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
            fn call(dir: *const sdk.misc.BaseDir) model.Settings {
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

        std.log.debug("Initializing core...", .{});
        const c = core.Core.init(allocator);
        std.log.info("Core initialized.", .{});

        std.log.debug("Initializing UI...", .{});
        const ui_instance = ui.Ui.init(allocator);
        std.log.info("UI initialized.", .{});

        return .{
            .timer = .{},
            .managed_dx12_context = managed_dx12_context,
            .ui_context = ui_context,
            .settings_task = settings_task,
            .core = c,
            .ui = ui_instance,
        };
    }

    pub fn deinit(
        self: *Self,
        base_dir: *const sdk.misc.BaseDir,
        host_dx12_context: *const sdk.dx12.HostContext,
    ) void {
        _ = base_dir;
        _ = host_dx12_context;

        std.log.debug("Deinitializing UI...", .{});
        self.ui.deinit();
        std.log.info("UI deinitialized.", .{});

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
        if (self.managed_dx12_context) |*context| {
            context.deinit();
            self.managed_dx12_context = null;
            std.log.info("DX12 context de-initialized.", .{});
        } else {
            std.log.debug("Nothing to de-initialize.", .{});
        }
    }

    fn processFrame(self: *Self, frame: *const model.Frame) void {
        const settings = self.settings_task.peek() orelse return;
        self.ui.processFrame(settings, frame);
    }

    pub fn tick(self: *Self, game_memory: *const game.Memory) void {
        self.core.tick(game_memory, self, processFrame);
    }

    pub fn draw(
        self: *Self,
        base_dir: *const sdk.misc.BaseDir,
        host_dx12_context: *const sdk.dx12.HostContext,
        game_memory: ?*const game.Memory,
    ) void {
        const delta_time = self.timer.measureDeltaTime();
        self.core.update(delta_time, self, processFrame);
        self.ui.update(delta_time, &self.core.controller);

        const managed_dx12_context = if (self.managed_dx12_context) |*context| context else return;
        const dx12_context = sdk.dx12.Context.fromHostAndManaged(host_dx12_context, managed_dx12_context);
        const ui_context = if (self.ui_context) |*context| context else return;

        ui_context.newFrame();
        imgui.igGetIO_Nil().*.MouseDrawCursor = true;
        self.ui.draw(
            base_dir,
            ui_context.file_dialog_context,
            self.settings_task.peek(),
            game_memory,
            &self.core.controller,
        );
        ui_context.endFrame();

        const buffer_context = dx12_context.beforeRender() catch |err| {
            sdk.misc.error_context.append("Failed to execute DX12 before render code.", .{});
            sdk.misc.error_context.logError(err);
            return;
        };
        ui_context.render(buffer_context);
        dx12_context.afterRender(buffer_context) catch |err| {
            sdk.misc.error_context.append("Failed to execute DX12 after render code.", .{});
            sdk.misc.error_context.logError(err);
            return;
        };
    }

    pub fn beforeResize(
        self: *Self,
        base_dir: *const sdk.misc.BaseDir,
        host_dx12_context: *const sdk.dx12.HostContext,
    ) void {
        _ = base_dir;
        _ = host_dx12_context;
        std.log.debug("De-initializing DX12 buffer contexts...", .{});
        if (self.managed_dx12_context) |*context| {
            context.deinitBufferContexts();
            std.log.info("DX12 buffer contexts de-initialized.", .{});
        } else {
            std.log.debug("Nothing to de-initialize.", .{});
        }
    }

    pub fn afterResize(
        self: *Self,
        base_dir: *const sdk.misc.BaseDir,
        host_dx12_context: *const sdk.dx12.HostContext,
    ) void {
        _ = base_dir;
        std.log.debug("Re-initializing DX12 buffer contexts...", .{});
        if (self.managed_dx12_context) |*context| {
            if (context.reinitBufferContexts(host_dx12_context)) {
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
        window: w32.HWND,
        u_msg: u32,
        w_param: w32.WPARAM,
        l_param: w32.LPARAM,
    ) ?w32.LRESULT {
        if (self.ui_context) |*context| {
            return context.processWindowMessage(window, u_msg, w_param, l_param);
        }
        return null;
    }
};
