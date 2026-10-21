const std = @import("std");
const build_info = @import("build_info");
const w32 = @import("win32").everything;
const imgui = @import("imgui");
const sdk = @import("../sdk/root.zig");
const core = @import("core/root.zig");
const model = @import("model/root.zig");
const ui = @import("ui/root.zig");
const rendering = @import("rendering/root.zig");
const game = @import("game/root.zig");

const rendering_api = build_info.rendering_api;
const dx = switch (rendering_api) {
    .dx11 => sdk.dx11,
    .dx12 => sdk.dx12,
};

pub const EventBuss = struct {
    timer: sdk.misc.Timer(.{}),
    managed_dx_context: ?dx.ManagedContext,
    ui_context: ?UiContext,
    settings_task: SettingsTask,
    latest_version_task: LatestVersionTask,
    core: core.Core,
    ui: ui.Ui,
    rendering: rendering.Rendering,

    const Self = @This();
    const SettingsTask = sdk.misc.Task(model.Settings);
    const LatestVersionTask = sdk.misc.Task(?sdk.misc.Version);
    const UiContext = sdk.ui.Context(rendering_api);

    pub fn init(
        allocator: std.mem.Allocator,
        base_dir: *const sdk.misc.BaseDir,
        host_dx_context: *const dx.HostContext,
    ) Self {
        std.log.debug("Initializing DirectX context...", .{});
        var managed_dx_context = if (dx.ManagedContext.init(allocator, host_dx_context)) |context| block: {
            std.log.info("DirectX context initialized.", .{});
            break :block context;
        } else |err| block: {
            sdk.misc.error_context.append("Failed to initialize DirectX context.", .{});
            sdk.misc.error_context.logError(err);
            break :block null;
        };

        const dx_context = if (managed_dx_context) |*mdxc| block: {
            break :block dx.Context.fromHostAndManaged(host_dx_context, mdxc);
        } else null;

        const ui_context = if (dx_context) |*dxc| block: {
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

        std.log.debug("Spawning latest version fetching task...", .{});
        const latest_version_task = LatestVersionTask.spawn(allocator, struct {
            fn call(alloc: std.mem.Allocator) ?sdk.misc.Version {
                std.log.info("Latest version fetching task spawned.", .{});
                std.log.debug("Fetching latest version...", .{});
                if (sdk.misc.Version.fetchLatest(alloc)) |latest_version| {
                    std.log.info("Latest version fetched: {f}", .{latest_version});
                    return latest_version;
                } else |err| {
                    sdk.misc.error_context.append("Failed to fetch latest version tag.", .{});
                    sdk.misc.error_context.logError(err);
                    return null;
                }
            }
        }.call, .{allocator}) catch |err| block: {
            sdk.misc.error_context.append("Failed to spawn latest version fetching task.", .{});
            sdk.misc.error_context.logError(err);
            break :block LatestVersionTask.createCompleted(null);
        };

        std.log.debug("Initializing core...", .{});
        const core_instance = core.Core.init(allocator);
        std.log.info("Core initialized.", .{});

        std.log.debug("Initializing UI...", .{});
        const ui_instance = ui.Ui.init(allocator);
        std.log.info("UI initialized.", .{});

        std.log.debug("Initializing rendering...", .{});
        const rendering_instance = rendering.Rendering.init(
            allocator,
            if (dx_context) |*dxc| dxc else null,
        );
        std.log.info("Rendering initialized.", .{});

        return .{
            .timer = .{},
            .managed_dx_context = managed_dx_context,
            .ui_context = ui_context,
            .settings_task = settings_task,
            .latest_version_task = latest_version_task,
            .core = core_instance,
            .ui = ui_instance,
            .rendering = rendering_instance,
        };
    }

    pub fn deinit(
        self: *Self,
        base_dir: *const sdk.misc.BaseDir,
        host_dx_context: *const dx.HostContext,
    ) void {
        _ = base_dir;
        const dx_context = if (self.managed_dx_context) |*mdxc| block: {
            break :block dx.Context.fromHostAndManaged(host_dx_context, mdxc);
        } else null;

        std.log.debug("De-initializing rendering...", .{});
        self.rendering.deinit(if (dx_context) |*dxc| dxc else null);
        std.log.info("Rendering de-initialized.", .{});

        std.log.debug("Deinitializing UI...", .{});
        self.ui.deinit();
        std.log.info("UI de-initialized.", .{});

        std.log.debug("Joining latest version fetching loading task...", .{});
        _ = self.latest_version_task.join();
        std.log.info("Latest version fetching task joined.", .{});

        std.log.debug("Joining settings loading task...", .{});
        _ = self.settings_task.join();
        std.log.info("Settings loading task joined.", .{});

        std.log.debug("De-initializing core...", .{});
        self.core.deinit();
        std.log.info("Core de-initialized.", .{});

        std.log.debug("De-initializing UI context...", .{});
        if (self.ui_context) |*context| {
            context.deinit(&dx_context.?);
            self.ui_context = null;
            std.log.info("UI context de-initialized.", .{});
        } else {
            std.log.debug("Nothing to de-initialize.", .{});
        }

        std.log.debug("De-initializing DirectX context...", .{});
        if (self.managed_dx_context) |*context| {
            context.deinit();
            self.managed_dx_context = null;
            std.log.info("DirectX context de-initialized.", .{});
        } else {
            std.log.debug("Nothing to de-initialize.", .{});
        }
    }

    fn processFrame(self: *Self, frame: *const model.Frame) void {
        const settings = self.settings_task.peek() orelse return;
        self.ui.processFrame(settings, frame);
    }

    pub fn tick(
        self: *Self,
        base_dir: *const sdk.misc.BaseDir,
        game_memory: *game.Memory(build_info.game),
        input_override: *game.InputOverride,
    ) void {
        game_memory.updateAddresses();
        const settings = self.settings_task.peek() orelse return;
        self.core.tick(base_dir, settings, game_memory, input_override, self, processFrame);
    }

    pub fn draw(
        self: *Self,
        base_dir: *const sdk.misc.BaseDir,
        host_dx_context: *const dx.HostContext,
        game_memory_maybe: ?*game.Memory(build_info.game),
        memory_usage: usize,
    ) void {
        const delta_time = self.timer.measureDeltaTime();
        self.core.update(delta_time, self, processFrame);
        self.ui.update(delta_time, &self.core.controller);

        const managed_dx_context = if (self.managed_dx_context) |*context| context else return;
        var dx_context = dx.Context.fromHostAndManaged(host_dx_context, managed_dx_context);
        const ui_context = if (self.ui_context) |*context| context else return;

        const settings_maybe = self.settings_task.peek();
        const latest_version = block: {
            const version_maybe = self.latest_version_task.peek() orelse break :block ui.LatestVersion.loading;
            const version = version_maybe.* orelse break :block ui.LatestVersion.err;
            break :block ui.LatestVersion{ .available = version };
        };

        ui_context.newFrame();
        imgui.igGetIO_Nil().*.MouseDrawCursor = true;
        self.ui.draw(
            base_dir,
            ui_context.file_dialog_context,
            settings_maybe,
            game_memory_maybe,
            &self.core.controller,
            &self.core.tool_assisted_input,
            &self.core.tai_recording_coordinator,
            latest_version,
            memory_usage,
        );
        if (settings_maybe) |settings| {
            self.ui.draw3D(&self.rendering.shapes, settings, &self.core.controller);
        }
        ui_context.endFrame();

        const buffer_context = dx_context.beforeRender() catch |err| {
            sdk.misc.error_context.append("Failed to execute DirectX before render code.", .{});
            sdk.misc.error_context.logError(err);
            return;
        };
        if (game_memory_maybe) |game_memory| {
            if (settings_maybe) |settings| {
                self.rendering.render(&dx_context, buffer_context, game_memory, &settings.general.rendering_3d);
            }
        }
        ui_context.render(buffer_context);
        dx_context.afterRender(buffer_context) catch |err| {
            sdk.misc.error_context.append("Failed to execute DirectX after render code.", .{});
            sdk.misc.error_context.logError(err);
            return;
        };
    }

    pub fn beforeResize(
        self: *Self,
        base_dir: *const sdk.misc.BaseDir,
        host_dx_context: *const dx.HostContext,
    ) void {
        _ = base_dir;
        _ = host_dx_context;
        std.log.debug("De-initializing DirectX buffer contexts...", .{});
        if (self.managed_dx_context) |*context| {
            context.deinitBufferContexts();
            std.log.info("DirectX buffer contexts de-initialized.", .{});
        } else {
            std.log.debug("Nothing to de-initialize.", .{});
        }
    }

    pub fn afterResize(
        self: *Self,
        base_dir: *const sdk.misc.BaseDir,
        host_dx_context: *const dx.HostContext,
    ) void {
        _ = base_dir;
        std.log.debug("Re-initializing DirectX buffer contexts...", .{});
        if (self.managed_dx_context) |*context| {
            if (context.reinitBufferContexts(host_dx_context)) {
                std.log.info("DirectX buffer contexts re-initialized.", .{});
            } else |err| {
                sdk.misc.error_context.append("Failed to re-initialize DirectX buffer contexts.", .{});
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
