const std = @import("std");
const imgui = @import("imgui");
const dll = @import("../../dll.zig");
const sdk = @import("../../sdk/root.zig");
const core = @import("../core/root.zig");
const model = @import("../model/root.zig");

pub const FileMenu = struct {
    file_path_buffer: [sdk.os.max_file_path_length]u8 = undefined,
    file_path_len: usize = 0,
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
        confirm,
        file_picker,
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

        var next_action = self.action;
        var next_progress = self.progress;
        defer {
            self.action = if (next_progress == .no_progress) .no_action else next_action;
            self.progress = next_progress;
        }

        if (imgui.igBeginMenu("File", true)) {
            defer imgui.igEndMenu();
            imgui.igBeginDisabled(controller.getTotalFrames() == 0);
            if (imgui.igMenuItem_Bool("New", null, false, true)) {
                next_action = .new;
            }
            imgui.igEndDisabled();
            if (imgui.igMenuItem_Bool("Open", null, false, true)) {
                next_action = .open;
            }
            if (imgui.igMenuItem_Bool("Save", null, false, true)) {
                if (self.getFilePath() != null) {
                    next_action = .save;
                } else {
                    next_action = .save_as;
                }
            }
            if (imgui.igMenuItem_Bool("Save As", null, false, true)) {
                next_action = .save_as;
            }
            imgui.igSeparator();
            if (imgui.igMenuItem_Bool("Close Window", null, false, true)) {
                is_main_window_open.* = false;
                sdk.ui.toasts.send(.default, null, "Main window closed. Press [Tab] to open it again.", .{});
            }
            if (imgui.igMenuItem_Bool("Exit Irony", null, false, true)) {
                next_action = .exit;
            }
        }
        if (next_action != self.action) {
            if (self.unsaved_changes and next_action != .no_action) {
                next_progress = .confirm;
            } else switch (next_action) {
                .no_action => {},
                .open, .save_as => next_progress = .file_picker,
                .new => {
                    self.new(controller);
                    next_progress = .no_progress;
                },
                .save => {
                    if (self.getFilePath()) |path| {
                        self.save(controller, path) catch |err| {
                            sdk.misc.error_context.append("Failed to save.", .{});
                            sdk.misc.error_context.logError(err);
                        };
                        next_progress = .no_progress;
                    } else {
                        std.log.err("No file path to save to.", .{});
                    }
                },
                .exit => {
                    exit();
                    next_progress = .no_progress;
                },
            }
        }

        if (next_progress != self.progress and next_progress == .confirm) {
            imgui.igOpenPopup_Str("Unsaved Changes", 0);
        }
        var is_confirm_open = next_progress == .confirm;
        if (imgui.igBeginPopupModal(
            "Unsaved Changes",
            &is_confirm_open,
            imgui.ImGuiWindowFlags_AlwaysAutoResize,
        )) {
            defer imgui.igEndPopup();
            var progress = false;
            var regress = false;
            imgui.igText("Do you want to save changes of current file before continuing?");
            imgui.igText("Any recorded data that is not saved will be lost.");
            imgui.igSeparator();
            if (imgui.igButton("Save", .{})) {
                if (self.getFilePath()) |path| {
                    if (self.save(controller, path)) {
                        progress = true;
                    } else |err| {
                        sdk.misc.error_context.append("Failed to save.", .{});
                        sdk.misc.error_context.logError(err);
                        regress = true;
                    }
                } else {
                    std.log.err("No file path to save to.", .{});
                }
            }
            imgui.igSameLine(0, -1);
            imgui.igSetItemDefaultFocus();
            if (imgui.igButton("Don't Save", .{})) {
                progress = true;
            }
            imgui.igSameLine(0, -1);
            imgui.igSetItemDefaultFocus();
            if (imgui.igButton("Cancel", .{})) {
                regress = true;
            }
            if (!is_confirm_open) {
                regress = true;
            }
            if (progress) {
                switch (next_action) {
                    .no_action => {},
                    .open, .save_as => next_progress = .file_picker,
                    .new => {
                        self.new(controller);
                        next_progress = .no_progress;
                    },
                    .save => {
                        if (self.getFilePath()) |path| {
                            self.save(controller, path) catch |err| {
                                sdk.misc.error_context.append("Failed to save.", .{});
                                sdk.misc.error_context.logError(err);
                            };
                            next_progress = .no_progress;
                        } else {
                            std.log.err("No file path to save to.", .{});
                        }
                    },
                    .exit => {
                        exit();
                        next_progress = .no_progress;
                    },
                }
                imgui.igCloseCurrentPopup();
            } else if (regress) {
                next_progress = .no_progress;
                imgui.igCloseCurrentPopup();
            }
        }

        if (next_progress != self.progress and next_progress == .file_picker) {
            var config = imgui.IGFD_FileDialog_Config_Get();
            config.path = base_dir.get();
            config.countSelectionMax = 1;
            const title = switch (next_action) {
                .no_action, .new, .save, .exit => unreachable,
                .open => "Open",
                .save_as => "Save As",
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
                switch (next_action) {
                    .no_action, .new, .save, .exit => unreachable,
                    .open => self.open(controller, path) catch |err| {
                        sdk.misc.error_context.append("Failed to open: {s}", .{path});
                        sdk.misc.error_context.logError(err);
                    },
                    .save_as => self.save(controller, path) catch |err| {
                        sdk.misc.error_context.append("Failed to save: {s}", .{path});
                        sdk.misc.error_context.logError(err);
                    },
                }
            }
            imgui.IGFD_CloseDialog(file_dialog_context);
            next_progress = .no_progress;
        }
    }

    fn new(self: *Self, controller: *core.Controller) void {
        controller.clear();
        self.file_path_len = 0;
        self.unsaved_changes = false;
        self.saved_total_frames = controller.getTotalFrames();
        sdk.ui.toasts.send(.success, null, "New recording started.", .{});
    }

    fn open(self: *Self, controller: *core.Controller, file_path: []const u8) !void {
        const recording = sdk.fs.loadRecording(model.Frame, controller.allocator, file_path, &.{}) catch |err| {
            sdk.misc.error_context.append("Failed to load recording: {s}", .{file_path});
            return err;
        };
        self.setFilePath(file_path) catch |err| {
            sdk.misc.error_context.append("Failed to set file path: {s}", .{file_path});
            return err;
        };
        controller.clear();
        controller.recording = .fromOwnedSlice(recording);
        self.unsaved_changes = false;
        self.saved_total_frames = controller.getTotalFrames();
        sdk.ui.toasts.send(.success, null, "Recording opened.", .{});
    }

    fn save(self: *Self, controller: *core.Controller, file_path: []const u8) !void {
        controller.stop();
        sdk.fs.saveRecording(model.Frame, controller.recording.items, file_path, &.{}) catch |err| {
            sdk.misc.error_context.append("Failed to save recording: {s}", .{file_path});
            return err;
        };
        self.unsaved_changes = false;
        self.saved_total_frames = controller.getTotalFrames();
        sdk.ui.toasts.send(.success, null, "Recording saved.", .{});
    }

    fn exit() void {
        dll.selfEject();
    }

    fn setFilePath(self: *Self, path: []const u8) !void {
        if (path.len + 1 >= self.file_path_buffer.len) {
            sdk.misc.error_context.new(
                "Path exceeded the path buffer size ({}): {s}",
                .{ self.file_path_buffer.len, path },
            );
            return error.NoSpaceLeft;
        }
        for (0..path.len) |index| {
            self.file_path_buffer[index] = path[index];
        }
        self.file_path_buffer[path.len] = 0;
        self.file_path_len = path.len;
    }

    pub fn getFilePath(self: *const Self) ?[:0]const u8 {
        if (self.file_path_len == 0) {
            return null;
        }
        return self.file_path_buffer[0..self.file_path_len :0];
    }

    pub fn getFileName(self: *const Self) ?[:0]const u8 {
        const path = self.getFilePath() orelse return null;
        const index = std.mem.lastIndexOfAny(u8, path, &.{ '/', '\\' }) orelse return path;
        return path[(index + 1)..];
    }
};
