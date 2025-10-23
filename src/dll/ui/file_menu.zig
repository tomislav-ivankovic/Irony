const std = @import("std");
const imgui = @import("imgui");
const dll = @import("../../dll.zig");
const sdk = @import("../../sdk/root.zig");
const core = @import("../core/root.zig");
const model = @import("../model/root.zig");

pub const FileMenu = struct {
    current_file_path_buffer: [sdk.os.max_file_path_length]u8 = undefined,
    current_file_path_len: usize = 0,
    selected_file_path_buffer: [sdk.os.max_file_path_length]u8 = undefined,
    selected_file_path_len: usize = 0,
    unsaved_changes: bool = false,
    saved_total_frames: usize = 0,
    action: Action = .no_action,
    progress: Progress = .no_progress,

    const Self = @This();
    const Action = enum {
        no_action,
        new,
        open,
        save,
        save_as,
        exit,
    };
    const Progress = enum {
        no_progress,
        unsaved_dialog,
        save_in_progress,
        file_picker,
        ready,
        action_in_progress,
    };

    pub fn draw(
        self: *Self,
        base_dir: *const sdk.fs.BaseDir,
        is_main_window_open: *bool,
        file_dialog_context: *imgui.ImGuiFileDialog,
        controller: *core.Controller,
    ) void {
        if (controller.getTotalFrames() != self.saved_total_frames) {
            self.unsaved_changes = true;
        }

        var action = self.action;
        var progress = self.progress;
        defer {
            self.action = if (progress == .no_progress) .no_action else action;
            self.progress = progress;
        }

        if (imgui.igBeginMenu("File", true)) {
            defer imgui.igEndMenu();

            imgui.igBeginDisabled(action != .no_action);

            imgui.igBeginDisabled(controller.getTotalFrames() == 0);
            if (imgui.igMenuItem_Bool("New", null, false, true)) {
                action = .new;
            }
            imgui.igEndDisabled();

            if (imgui.igMenuItem_Bool("Open", null, false, true)) {
                action = .open;
            }

            imgui.igBeginDisabled(controller.getTotalFrames() == 0);
            if (imgui.igMenuItem_Bool("Save", null, false, true)) {
                action = .save;
            }
            if (imgui.igMenuItem_Bool("Save As", null, false, true)) {
                action = .save_as;
            }
            imgui.igEndDisabled();

            imgui.igEndDisabled();

            imgui.igSeparator();

            if (imgui.igMenuItem_Bool("Close Window", null, false, true)) {
                is_main_window_open.* = false;
                sdk.ui.toasts.send(.default, null, "Main window closed. Press [Tab] to open it again.", .{});
            }

            imgui.igBeginDisabled(action != .no_action);
            if (imgui.igMenuItem_Bool("Exit Irony", null, false, true)) {
                action = .exit;
            }
            imgui.igEndDisabled();
        }
        if (action != self.action) {
            switch (self.unsaved_changes) {
                true => switch (action) {
                    .no_action => {},
                    .new, .open, .exit => progress = .unsaved_dialog,
                    .save_as => progress = .file_picker,
                    .save => progress = if (self.getCurrentFilePath() == null) .file_picker else .ready,
                },
                false => switch (action) {
                    .no_action => {},
                    .new, .exit => progress = .ready,
                    .open, .save_as => progress = .file_picker,
                    .save => progress = if (self.getCurrentFilePath() == null) .file_picker else .ready,
                },
            }
        }

        if (progress != self.progress and progress == .unsaved_dialog) {
            imgui.igOpenPopup_Str("Unsaved Changes", 0);
        }
        var is_unsaved_dialog_open = progress == .unsaved_dialog;
        if (imgui.igBeginPopupModal(
            "Unsaved Changes",
            &is_unsaved_dialog_open,
            imgui.ImGuiWindowFlags_AlwaysAutoResize,
        )) {
            const ConfirmChoice = enum {
                no_choice,
                save,
                dont_save,
                cancel,
            };
            var choice = ConfirmChoice.no_choice;
            defer imgui.igEndPopup();
            imgui.igText("Do you want to save changes of current file before continuing?");
            imgui.igText("Any recorded data that is not saved will be lost.");
            imgui.igSeparator();
            if (imgui.igButton("Save", .{})) {
                choice = .save;
            }
            imgui.igSameLine(0, -1);
            imgui.igSetItemDefaultFocus();
            if (imgui.igButton("Don't Save", .{})) {
                choice = .dont_save;
            }
            imgui.igSameLine(0, -1);
            imgui.igSetItemDefaultFocus();
            if (imgui.igButton("Cancel", .{})) {
                choice = .cancel;
            }
            if (!is_unsaved_dialog_open) {
                choice = .cancel;
            }
            switch (choice) {
                .no_choice => {},
                .save => if (self.getCurrentFilePath()) |path| {
                    controller.save(path);
                    progress = .save_in_progress;
                } else {
                    // TODO Here one would need to display save as.
                    progress = .no_progress;
                },
                .dont_save => switch (action) {
                    .no_action, .save, .save_as => unreachable,
                    .new, .exit => progress = .ready,
                    .open => progress = .file_picker,
                },
                .cancel => progress = .no_progress,
            }
            if (choice != .no_choice) {
                imgui.igCloseCurrentPopup();
            }
        }

        if (progress == .save_in_progress and controller.mode != .save) {
            switch (action) {
                .no_action, .save => unreachable,
                .new, .exit => progress = .ready,
                .open, .save_as => progress = .file_picker,
            }
        }

        if (progress != self.progress and progress == .file_picker) {
            var config = imgui.IGFD_FileDialog_Config_Get();
            config.path = base_dir.get();
            config.countSelectionMax = 1;
            const title = switch (action) {
                .no_action, .new, .exit => unreachable,
                .open => block: {
                    config.path = base_dir.get().ptr;
                    config.flags = imgui.ImGuiFileDialogFlags_None;
                    break :block "Open";
                },
                .save_as, .save => block: {
                    if (self.getCurrentFilePath()) |path| {
                        config.filePathName = path.ptr;
                    } else {
                        config.fileName = "recording.irony";
                        config.path = base_dir.get();
                    }
                    config.flags = imgui.ImGuiFileDialogFlags_ConfirmOverwrite;
                    break :block "Save As";
                },
            };
            imgui.IGFD_OpenDialog(
                file_dialog_context,
                "dialog",
                title,
                "irony recordings (*.irony){.irony}",
                config,
            );
        }
        const display_size = imgui.igGetIO_Nil().*.DisplaySize;
        if (imgui.IGFD_DisplayDialog(
            file_dialog_context,
            "dialog",
            imgui.ImGuiWindowFlags_NoCollapse,
            .{ .x = 0.5 * display_size.x, .y = 0.5 * display_size.y },
            .{ .x = 0.5 * display_size.x, .y = 0.5 * display_size.y },
        )) {
            if (imgui.IGFD_IsOk(file_dialog_context)) {
                const c_path = imgui.IGFD_GetFilePathName(file_dialog_context, imgui.IGFD_ResultMode_AddIfNoFileExt);
                defer std.c.free(c_path);
                const path = std.mem.sliceTo(c_path, 0);
                if (self.setSelectedFilePath(path)) {
                    progress = .ready;
                } else |err| {
                    sdk.misc.error_context.append("Failed to set selected path to: {s}", .{path});
                    sdk.misc.error_context.logError(err);
                    progress = .no_progress;
                }
            } else {
                progress = .no_progress;
            }
            imgui.IGFD_CloseDialog(file_dialog_context);
        }

        if (progress == .ready) {
            switch (action) {
                .no_action => unreachable,
                .new => {
                    controller.clear();
                    self.current_file_path_len = 0;
                    progress = .no_progress;
                },
                .open => {
                    if (self.getSelectedFilePath()) |path| {
                        controller.load(path);
                        progress = .action_in_progress;
                    } else {
                        std.log.err("No selected file to open from.", .{});
                        progress = .no_progress;
                    }
                },
                .save => {
                    if (self.getSelectedFilePath()) |path| {
                        controller.save(path);
                        progress = .action_in_progress;
                    } else if (self.getCurrentFilePath()) |path| {
                        controller.save(path);
                        progress = .action_in_progress;
                    } else {
                        std.log.err("No file path to save to.", .{});
                        progress = .no_progress;
                    }
                },
                .save_as => {
                    if (self.getSelectedFilePath()) |path| {
                        controller.save(path);
                        progress = .action_in_progress;
                    } else {
                        std.log.err("No file path to save to.", .{});
                        progress = .no_progress;
                    }
                },
                .exit => {
                    dll.selfEject();
                    progress = .no_progress;
                },
            }
        }

        if (progress == .action_in_progress and controller.mode != .save and controller.mode != .load) {
            progress = .no_progress;
        }

        if (progress != self.progress and progress == .no_progress) {
            if (self.getSelectedFilePath()) |selected_path| {
                self.setCurrentFilePath(selected_path) catch |err| {
                    sdk.misc.error_context.append("Failed to set current file path to: {s}", .{selected_path});
                    sdk.misc.error_context.logError(err);
                };
                self.selected_file_path_len = 0;
            }
            self.unsaved_changes = false;
            self.saved_total_frames = controller.getTotalFrames();
        }
    }

    fn setCurrentFilePath(self: *Self, new_path: []const u8) !void {
        if (new_path.len + 1 >= self.current_file_path_buffer.len) {
            sdk.misc.error_context.new(
                "Path exceeded the path buffer size ({}): {s}",
                .{ self.current_file_path_buffer.len, new_path },
            );
            return error.NoSpaceLeft;
        }
        for (0..new_path.len) |index| {
            self.current_file_path_buffer[index] = new_path[index];
        }
        self.current_file_path_buffer[new_path.len] = 0;
        self.current_file_path_len = new_path.len;
    }

    pub fn getCurrentFilePath(self: *const Self) ?[:0]const u8 {
        if (self.current_file_path_len == 0) {
            return null;
        }
        return self.current_file_path_buffer[0..self.current_file_path_len :0];
    }

    pub fn getCurrentFileName(self: *const Self) ?[:0]const u8 {
        const path = self.getCurrentFilePath() orelse return null;
        const index = std.mem.lastIndexOfAny(u8, path, &.{ '/', '\\' }) orelse return path;
        return path[(index + 1)..];
    }

    fn setSelectedFilePath(self: *Self, new_path: []const u8) !void {
        if (new_path.len + 1 >= self.selected_file_path_buffer.len) {
            sdk.misc.error_context.new(
                "Path exceeded the path buffer size ({}): {s}",
                .{ self.selected_file_path_buffer.len, new_path },
            );
            return error.NoSpaceLeft;
        }
        for (0..new_path.len) |index| {
            self.selected_file_path_buffer[index] = new_path[index];
        }
        self.selected_file_path_buffer[new_path.len] = 0;
        self.selected_file_path_len = new_path.len;
    }

    fn getSelectedFilePath(self: *const Self) ?[:0]const u8 {
        if (self.selected_file_path_len == 0) {
            return null;
        }
        return self.selected_file_path_buffer[0..self.selected_file_path_len :0];
    }

    fn getSelectedFileName(self: *const Self) ?[:0]const u8 {
        const path = self.getSelectedFilePath() orelse return null;
        const index = std.mem.lastIndexOfAny(u8, path, &.{ '/', '\\' }) orelse return path;
        return path[(index + 1)..];
    }
};
