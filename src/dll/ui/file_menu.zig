const std = @import("std");
const imgui = @import("imgui");
const dll = @import("../../dll.zig");
const sdk = @import("../../sdk/root.zig");
const core = @import("../core/root.zig");
const model = @import("../model/root.zig");

pub const FileMenu = struct {
    action: Action = .idle,
    progress: Progress = .start,
    menu_bar: MenuBar = .{},
    unsaved_dialog: UnsavedDialog = .{},
    save_dialog: FileDialog = .{ .type = .save },
    open_dialog: FileDialog = .{ .type = .open },
    file_path_buffer: [sdk.os.max_file_path_length]u8 = undefined,
    file_path_len: usize = 0,

    const Self = @This();
    const Action = enum {
        idle,
        new,
        open,
        save,
        save_as,
        exit,
    };
    const Progress = enum {
        start,
        unsaved_dialog,
        save_dialog,
        save_in_progress,
        open_dialog,
        open_in_progress,
        finnish,
    };

    pub fn update(self: *Self, controller: *core.Controller) void {
        var action = self.action;
        defer self.action = action;
        var progress = self.progress;
        defer self.progress = progress;

        if (action == .idle) {
            switch (self.menu_bar.action) {
                .no_action, .close_ui => {},
                .new => action = .new,
                .open => action = .open,
                .save => action = .save,
                .save_as => action = .save_as,
                .exit => action = .exit,
            }
        }

        const unsaved_changes = controller.contains_unsaved_changes;
        if (action != .idle and progress == .start) {
            progress = switch (action) {
                .idle => unreachable,
                .new, .exit => if (unsaved_changes) .unsaved_dialog else .finnish,
                .open => if (unsaved_changes) .unsaved_dialog else .open_dialog,
                .save => if (self.file_path_len == 0) .save_dialog else .save_in_progress,
                .save_as => .save_dialog,
            };
        }

        if (progress == .unsaved_dialog) {
            switch (self.unsaved_dialog.action) {
                .no_action => {},
                .save => progress = if (self.file_path_len == 0) .save_dialog else .save_in_progress,
                .dont_save => switch (action) {
                    .idle, .save, .save_as => unreachable,
                    .new, .exit => progress = .finnish,
                    .open => progress = .open_dialog,
                },
                .cancel => {
                    action = .idle;
                    progress = .start;
                },
            }
        }

        if (progress == .save_dialog) {
            switch (self.save_dialog.action) {
                .no_action => {},
                .proceed => progress = .save_in_progress,
                .cancel => {
                    action = .idle;
                    progress = .start;
                },
            }
        }

        if (self.progress != .save_in_progress and progress == .save_in_progress) {
            const path = self.save_dialog.getLastSelectedPath() orelse self.getFilePath() orelse unreachable;
            controller.save(path);
        }

        if (progress == .save_in_progress and controller.mode != .save) {
            if (controller.did_last_save_or_load_succeed) {
                switch (action) {
                    .idle => unreachable,
                    .new, .save, .save_as, .exit => progress = .finnish,
                    .open => progress = .open_dialog,
                }
                if (self.save_dialog.last_selected_path_len > 0) {
                    self.file_path_buffer = self.save_dialog.last_selected_path_buffer;
                    self.file_path_len = self.save_dialog.last_selected_path_len;
                }
            } else {
                action = .idle;
                progress = .start;
            }
            self.save_dialog.last_selected_path_len = 0;
        }

        if (progress == .open_dialog) {
            switch (self.open_dialog.action) {
                .no_action => {},
                .proceed => progress = .open_in_progress,
                .cancel => {
                    action = .idle;
                    progress = .start;
                },
            }
        }

        if (self.progress != .open_in_progress and progress == .open_in_progress) {
            const path = self.open_dialog.getLastSelectedPath() orelse unreachable;
            controller.load(path);
        }

        if (progress == .open_in_progress and controller.mode != .load) {
            if (controller.did_last_save_or_load_succeed) {
                progress = .finnish;
                if (self.open_dialog.last_selected_path_len > 0) {
                    self.file_path_buffer = self.open_dialog.last_selected_path_buffer;
                    self.file_path_len = self.open_dialog.last_selected_path_len;
                }
            } else {
                action = .idle;
                progress = .start;
            }
            self.open_dialog.last_selected_path_len = 0;
        }

        if (progress == .finnish) {
            switch (action) {
                .idle => unreachable,
                .open, .save, .save_as => {},
                .new => {
                    controller.clear();
                    self.file_path_len = 0;
                },
                .exit => dll.selfEject(),
            }
            action = .idle;
            progress = .start;
        }
    }

    pub fn draw(
        self: *Self,
        base_dir: *const sdk.misc.BaseDir,
        file_dialog_context: *imgui.ImGuiFileDialog,
        controller: *core.Controller,
        is_ui_open: *bool,
    ) void {
        self.menu_bar.draw(self.action == .idle, controller.getTotalFrames() == 0);
        self.unsaved_dialog.draw(self.progress == .unsaved_dialog);
        self.save_dialog.draw(file_dialog_context, base_dir, self.getFilePath(), self.progress == .save_dialog);
        self.open_dialog.draw(file_dialog_context, base_dir, self.getFilePath(), self.progress == .open_dialog);

        if (self.menu_bar.action == .close_ui and is_ui_open.*) {
            is_ui_open.* = false;
            sdk.ui.toasts.send(.default, null, "UI closed. Press [Tab] to open it again.", .{});
        }
    }

    pub fn getFilePath(self: *const Self) ?[:0]const u8 {
        if (self.file_path_len == 0) {
            return null;
        }
        return self.file_path_buffer[0..self.file_path_len :0];
    }
};

const MenuBar = struct {
    action: Action = .no_action,

    const Self = @This();
    pub const Action = enum {
        no_action,
        new,
        open,
        save,
        save_as,
        close_ui,
        exit,
    };

    fn draw(self: *Self, is_idle: bool, is_recording_empty: bool) void {
        var action = Action.no_action;
        defer self.action = action;

        if (!imgui.igBeginMenu("File", true)) {
            return;
        }
        defer imgui.igEndMenu();

        imgui.igBeginDisabled(!is_idle);
        imgui.igBeginDisabled(is_recording_empty);
        if (imgui.igMenuItem_Bool("New", null, false, true)) {
            action = .new;
        }
        imgui.igEndDisabled();
        if (imgui.igMenuItem_Bool("Open", null, false, true)) {
            action = .open;
        }
        imgui.igBeginDisabled(is_recording_empty);
        if (imgui.igMenuItem_Bool("Save", null, false, true)) {
            action = .save;
        }
        if (imgui.igMenuItem_Bool("Save As", null, false, true)) {
            action = .save_as;
        }
        imgui.igEndDisabled();
        imgui.igEndDisabled();
        imgui.igSeparator();
        if (imgui.igMenuItem_Bool("Close UI", null, false, true)) {
            action = .close_ui;
        }
        imgui.igBeginDisabled(!is_idle);
        if (imgui.igMenuItem_Bool("Exit Irony", null, false, true)) {
            action = .exit;
        }
        imgui.igEndDisabled();
    }
};

const UnsavedDialog = struct {
    is_open: bool = false,
    action: Action = .no_action,

    const Self = @This();
    pub const Action = enum { no_action, save, dont_save, cancel };

    pub fn draw(self: *Self, is_open: bool) void {
        defer self.is_open = is_open;
        var action = Action.no_action;
        defer self.action = action;

        if (!self.is_open and is_open) {
            imgui.igOpenPopup_Str("Unsaved Changes", 0);
        }

        var remains_open = self.is_open or is_open;
        if (!imgui.igBeginPopupModal(
            "Unsaved Changes",
            &remains_open,
            imgui.ImGuiWindowFlags_AlwaysAutoResize,
        )) {
            return;
        }
        defer imgui.igEndPopup();

        imgui.igText("Do you want to save changes of current file before continuing?");
        imgui.igText("Any recorded data that is not saved will be lost.");
        imgui.igSeparator();
        if (imgui.igButton("Save", .{})) {
            action = .save;
        }
        imgui.igSameLine(0, -1);
        if (imgui.igButton("Don't Save", .{})) {
            action = .dont_save;
        }
        imgui.igSameLine(0, -1);
        if (imgui.igButton("Cancel", .{})) {
            action = .cancel;
        }
        imgui.igSetItemDefaultFocus();
        if (!remains_open) {
            action = .cancel;
        }
        if (!is_open) {
            imgui.igCloseCurrentPopup();
        }
    }
};

const FileDialog = struct {
    type: Type,
    is_open: bool = false,
    action: Action = .no_action,
    last_selected_path_buffer: [sdk.os.max_file_path_length]u8 = undefined,
    last_selected_path_len: usize = 0,

    const Self = @This();
    pub const Action = enum { no_action, proceed, cancel };
    pub const Type = enum { save, open };

    pub fn draw(
        self: *Self,
        context: *imgui.ImGuiFileDialog,
        base_dir: *const sdk.misc.BaseDir,
        current_path: ?[:0]const u8,
        is_open: bool,
    ) void {
        defer self.is_open = is_open;

        if (!self.is_open and is_open) {
            var buffer: [sdk.os.max_file_path_length]u8 = undefined;
            var config = imgui.IGFD_FileDialog_Config_Get();
            config.countSelectionMax = 1;
            config.flags = imgui.ImGuiFileDialogFlags_Modal;
            switch (self.type) {
                .save => {
                    if (current_path) |path| {
                        config.filePathName = path.ptr;
                    } else {
                        config.fileName = "recording.irony";
                        config.path = createAndGetRecordingsDirectory(&buffer, base_dir);
                    }
                    config.flags |= imgui.ImGuiFileDialogFlags_ConfirmOverwrite;
                },
                .open => {
                    config.path = createAndGetRecordingsDirectory(&buffer, base_dir);
                },
            }
            imgui.IGFD_OpenDialog(
                context,
                switch (self.type) {
                    .save => "save_dialog",
                    .open => "open_dialog",
                },
                switch (self.type) {
                    .save => "Save AS",
                    .open => "Open",
                },
                "irony recordings (*.irony){.irony}",
                config,
            );
        }
        if (self.is_open and !is_open) {
            defer imgui.IGFD_CloseDialog(context);
        }

        const display_size = imgui.igGetIO_Nil().*.DisplaySize;
        const has_action = imgui.IGFD_DisplayDialog(
            context,
            switch (self.type) {
                .save => "save_dialog",
                .open => "open_dialog",
            },
            imgui.ImGuiWindowFlags_NoCollapse,
            .{ .x = 0.5 * display_size.x, .y = 0.5 * display_size.y },
            .{ .x = display_size.x, .y = display_size.y },
        );
        if (!has_action or !is_open) {
            self.action = .no_action;
            return;
        }
        if (!imgui.IGFD_IsOk(context)) {
            self.action = .cancel;
            return;
        }

        const c_path = imgui.IGFD_GetFilePathName(context, imgui.IGFD_ResultMode_AddIfNoFileExt);
        defer std.c.free(c_path);
        const path = std.mem.sliceTo(c_path, 0);

        if (path.len + 1 >= self.last_selected_path_buffer.len) {
            std.log.err(
                "Selected path exceeded the path buffer size ({}): {s}",
                .{ self.last_selected_path_buffer.len, path },
            );
            self.action = .no_action;
            return;
        }

        for (0..path.len) |index| {
            self.last_selected_path_buffer[index] = path[index];
        }
        self.last_selected_path_buffer[path.len] = 0;
        self.last_selected_path_len = path.len;

        self.action = .proceed;
    }

    fn createAndGetRecordingsDirectory(
        buffer: *[sdk.os.max_file_path_length]u8,
        base_dir: *const sdk.misc.BaseDir,
    ) [:0]const u8 {
        const path = base_dir.getPath(buffer, "recordings") catch |err| {
            sdk.misc.error_context.append("Failed to construct recordings directory path.", .{});
            sdk.misc.error_context.logError(err);
            return base_dir.get();
        };

        var returned_error: ?anyerror = null;
        const thread = std.Thread.spawn(.{}, struct {
            fn call(in_path: []const u8, out_err: *?anyerror) void {
                std.fs.cwd().makePath(in_path) catch |err| {
                    out_err.* = err;
                };
            }
        }.call, .{ path, &returned_error }) catch |err| {
            sdk.misc.error_context.append("Failed to spawn directory make thread.", .{});
            sdk.misc.error_context.append("Failed to make directory: {s}", .{path});
            sdk.misc.error_context.logError(err);
            return base_dir.get();
        };
        thread.join();
        if (returned_error) |err| {
            sdk.misc.error_context.append("Failed to make directory: {s}", .{path});
            sdk.misc.error_context.logError(err);
            return base_dir.get();
        }

        return path;
    }

    fn getLastSelectedPath(self: *const Self) ?[:0]const u8 {
        if (self.last_selected_path_len == 0) {
            return null;
        }
        return self.last_selected_path_buffer[0..self.last_selected_path_len :0];
    }
};
