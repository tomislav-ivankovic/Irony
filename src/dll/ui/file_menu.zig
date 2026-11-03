const std = @import("std");
const imgui = @import("imgui");
const build_info = @import("build_info");
const dll = @import("../../dll.zig");
const sdk = @import("../../sdk/root.zig");
const core = @import("../core/root.zig");
const model = @import("../model/root.zig");
const ui = @import("root.zig");

pub const FileMenuConfig = struct {
    Controller: type = core.Controller,
    selfShutDown: *const fn () void = dll.selfShutDown,
};

pub fn FileMenu(comptime config: FileMenuConfig) type {
    return struct {
        action: Action = .idle,
        progress: Progress = .start,
        menu_bar: MenuBar = .{},
        unsaved_dialog: UnsavedDialog = .{},
        save_dialog: FileDialog = .{ .type = .save },
        confirm_overwrite_dialog: ConfirmOverwriteDialog = .{},
        open_dialog: FileDialog = .{ .type = .open },

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
            confirm_overwrite,
            save_in_progress,
            open_dialog,
            open_in_progress,
            finish,
        };

        pub fn update(self: *Self, io: std.Io, controller: *config.Controller) void {
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
            const file_path = controller.getFilePath();
            if (action != .idle and progress == .start) {
                progress = switch (action) {
                    .idle => unreachable,
                    .new, .exit => if (unsaved_changes) .unsaved_dialog else .finish,
                    .open => if (unsaved_changes) .unsaved_dialog else .open_dialog,
                    .save => if (file_path == null) .save_dialog else .save_in_progress,
                    .save_as => .save_dialog,
                };
            }

            if (progress == .unsaved_dialog) {
                switch (self.unsaved_dialog.action) {
                    .no_action => {},
                    .save => progress = if (file_path == null) .save_dialog else .save_in_progress,
                    .dont_save => switch (action) {
                        .idle, .save, .save_as => unreachable,
                        .new, .exit => progress = .finish,
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
                    .proceed => {
                        const path = self.save_dialog.getLastSelectedPath() orelse unreachable;
                        progress = if (fileExists(io, path)) .confirm_overwrite else .save_in_progress;
                    },
                    .cancel => {
                        action = .idle;
                        progress = .start;
                        self.save_dialog.last_selected_path = .empty;
                    },
                }
            }

            if (progress == .confirm_overwrite) {
                switch (self.confirm_overwrite_dialog.action) {
                    .no_action => {},
                    .confirm => progress = .save_in_progress,
                    .cancel => progress = .save_dialog,
                }
            }

            if (self.progress != .save_in_progress and progress == .save_in_progress) {
                const path = self.save_dialog.getLastSelectedPath() orelse file_path orelse unreachable;
                controller.save(io, path);
            }

            if (progress == .save_in_progress and controller.mode != .save) {
                if (controller.did_last_save_or_load_succeed) {
                    switch (action) {
                        .idle => unreachable,
                        .new, .save, .save_as, .exit => progress = .finish,
                        .open => progress = .open_dialog,
                    }
                } else {
                    action = .idle;
                    progress = .start;
                }
                self.save_dialog.last_selected_path = .empty;
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
                controller.load(io, path);
            }

            if (progress == .open_in_progress and controller.mode != .load) {
                if (controller.did_last_save_or_load_succeed) {
                    progress = .finish;
                } else {
                    action = .idle;
                    progress = .start;
                }
                self.open_dialog.last_selected_path = .empty;
            }

            if (progress == .finish) {
                switch (action) {
                    .idle => unreachable,
                    .open, .save, .save_as => {},
                    .new => controller.clear(),
                    .exit => config.selfShutDown(),
                }
                action = .idle;
                progress = .start;
            }
        }

        pub fn draw(
            self: *Self,
            io: std.Io,
            file_dialog_context: *imgui.ImGuiFileDialog,
            controller: *config.Controller,
            is_ui_open: *bool,
        ) void {
            self.menu_bar.draw(self.action == .idle, controller.getTotalFrames() == 0);
            self.unsaved_dialog.draw(self.progress == .unsaved_dialog);
            self.save_dialog.draw(
                file_dialog_context,
                io,
                self.save_dialog.getLastSelectedPath() orelse controller.getFilePath(),
                self.progress == .save_dialog,
            );
            self.confirm_overwrite_dialog.draw(self.progress == .confirm_overwrite);
            self.open_dialog.draw(file_dialog_context, io, controller.getFilePath(), self.progress == .open_dialog);

            if (self.menu_bar.action == .close_ui and is_ui_open.*) {
                is_ui_open.* = false;
                sdk.ui.toasts.send(.default, null, "UI closed. Press [Tab] to open it again.", .{});
            }
        }

        fn fileExists(io: std.Io, path: []const u8) bool {
            std.Io.Dir.cwd().access(io, path, .{}) catch |err| switch (err) {
                error.FileNotFound => return false,
                else => {
                    // Assuming the file exists, so that the user gets asked before anything gets overwritten.
                    sdk.misc.error_context.append("Failed to check if file exists: {s}", .{path});
                    sdk.misc.error_context.logError(err);
                    return true;
                },
            };
            return true;
        }
    };
}

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

        const can_new = is_idle and !is_recording_empty;
        const can_open = is_idle;
        const can_save = is_idle and !is_recording_empty;
        const can_exit = is_idle;

        if (imgui.igGetTopMostPopupModal() == null) {
            const route = imgui.ImGuiInputFlags_RouteGlobal;
            if (can_new and imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_N, route)) {
                action = .new;
            }
            if (can_open and imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_O, route)) {
                action = .open;
            }
            if (can_save and imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_S, route)) {
                action = .save;
            }
            if (can_save and imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiMod_Shift | imgui.ImGuiKey_S, route)) {
                action = .save_as;
            }
            if (can_exit and imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_Q, route)) {
                action = .exit;
            }
        }

        if (!imgui.igBeginMenu("File", true)) {
            return;
        }
        defer imgui.igEndMenu();

        if (imgui.igMenuItem_Bool("New", "Ctrl + N", false, can_new)) {
            action = .new;
        }
        if (imgui.igMenuItem_Bool("Open", "Ctrl + O", false, can_open)) {
            action = .open;
        }
        if (imgui.igMenuItem_Bool("Save", "Ctrl + S", false, can_save)) {
            action = .save;
        }
        if (imgui.igMenuItem_Bool("Save As", "Ctrl + Shift + S", false, can_save)) {
            action = .save_as;
        }
        imgui.igSeparator();
        if (imgui.igMenuItem_Bool("Close UI", "Tab", false, true)) {
            action = .close_ui;
        }
        if (imgui.igMenuItem_Bool("Exit " ++ build_info.display_name, "Ctrl + Q", false, can_exit)) {
            action = .exit;
        }
    }
};

const UnsavedDialog = struct {
    action: Action = .no_action,

    const Self = @This();
    pub const Action = enum { no_action, save, dont_save, cancel };

    pub fn draw(self: *Self, is_open: bool) void {
        var action = Action.no_action;
        defer self.action = action;

        var next_open = is_open;
        if (!ui.beginDialog(&next_open, "Unsaved Changes")) {
            if (is_open and !next_open) {
                action = .cancel;
            }
            return;
        }
        defer ui.endDialog();

        const s_pressed = imgui.igShortcut_Nil(imgui.ImGuiKey_S, imgui.ImGuiInputFlags_RouteFocused);
        const d_pressed = imgui.igShortcut_Nil(imgui.ImGuiKey_D, imgui.ImGuiInputFlags_RouteFocused);
        const escape_pressed = imgui.igShortcut_Nil(imgui.ImGuiKey_Escape, imgui.ImGuiInputFlags_RouteFocused);

        imgui.igText("Do you want to save changes of current file before continuing?");
        imgui.igText("Any recorded data that is not saved will be lost.");
        imgui.igSeparator();
        if (imgui.igButton("Save", .{}) or s_pressed) {
            action = .save;
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("[S]");
        }
        imgui.igSameLine(0, -1);
        if (imgui.igButton("Don't Save", .{}) or d_pressed) {
            action = .dont_save;
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("[D]");
        }
        imgui.igSameLine(0, -1);
        if (imgui.igButton("Cancel", .{}) or escape_pressed) {
            action = .cancel;
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("[Esc]");
        }
        imgui.igSetItemDefaultFocus();
    }
};

const ConfirmOverwriteDialog = struct {
    action: Action = .no_action,

    const Self = @This();
    pub const Action = enum { no_action, confirm, cancel };

    pub fn draw(self: *Self, is_open: bool) void {
        var open = is_open;
        self.action = switch (ui.drawConfirmDialog(
            &open,
            "File Already Exists",
            "The selected file already exists. Do you want to overwrite it?",
            "Overwrite",
            "Cancel",
        )) {
            .none => .no_action,
            .confirm => .confirm,
            .abort => .cancel,
        };
    }
};

const FileDialog = struct {
    type: Type,
    is_open: bool = false,
    action: Action = .no_action,
    last_selected_path: FilePath = .empty,

    const Self = @This();
    pub const Type = enum { save, open };
    pub const Action = enum { no_action, proceed, cancel };
    const FilePath = sdk.misc.BoundedArray(sdk.os.max_file_path_length, u8, 0, true);

    const directory_name = "recordings";
    const save_filters = block: {
        var buffer: [256]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        const formats = model.RecordingFormat.all;
        for (formats, 0..) |format, index| {
            const name = getFormatDisplayName(format);
            const extension = format.getFileExtension();
            writer.writeAll(name) catch unreachable;
            writer.writeAll(" (") catch unreachable;
            writer.writeAll(extension) catch unreachable;
            writer.writeAll("){") catch unreachable;
            writer.writeAll(extension) catch unreachable;
            writer.writeByte('}') catch unreachable;
            if (index < formats.len - 1) {
                writer.writeByte(',') catch unreachable;
            }
        }
        writer.writeByte(0) catch unreachable;
        const result = buffer[0..(writer.end - 1) :0].*;
        break :block &result;
    };
    const open_filters = block: {
        var buffer: [256]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        const formats = model.RecordingFormat.all;
        writer.writeAll(save_filters) catch unreachable;
        writer.writeAll(",All files (") catch unreachable;
        for (formats, 0..) |format, index| {
            const extension = format.getFileExtension();
            writer.writeAll(extension) catch unreachable;
            if (index < formats.len - 1) {
                writer.writeAll(", ") catch unreachable;
            }
        }
        writer.writeAll("){") catch unreachable;
        for (formats, 0..) |format, index| {
            const extension = format.getFileExtension();
            writer.writeAll(extension) catch unreachable;
            if (index < formats.len - 1) {
                writer.writeByte(',') catch unreachable;
            }
        }
        writer.writeByte('}') catch unreachable;
        writer.writeByte(0) catch unreachable;
        const result = buffer[0..(writer.end - 1) :0].*;
        break :block &result;
    };

    fn getFormatDisplayName(format: model.RecordingFormat) [:0]const u8 {
        return switch (format) {
            .irony => "Irony recordings",
            .json => "JSON files",
            .json_zstd => "Compressed JSON files",
        };
    }

    pub fn draw(
        self: *Self,
        context: *imgui.ImGuiFileDialog,
        io: std.Io,
        current_path: ?[:0]const u8,
        is_open: bool,
    ) void {
        defer self.is_open = is_open;

        if (!self.is_open and is_open) {
            var buffer_1: [sdk.os.max_file_path_length]u8 = undefined;
            var buffer_2: [sdk.os.max_file_path_length]u8 = undefined;
            var config = imgui.IGFD_FileDialog_Config_Get();
            config.countSelectionMax = 1;
            config.flags = imgui.ImGuiFileDialogFlags_Modal;
            switch (self.type) {
                .save => {
                    if (current_path) |path| {
                        config.fileName = filePathToFileNameWithoutExtension(&buffer_1, path) catch |err| block: {
                            sdk.misc.error_context.append("Failed to construct file name from path: {s}", .{path});
                            sdk.misc.error_context.logError(err);
                            break :block "untitled";
                        };
                        config.path = filePathToDirectoryPath(&buffer_2, path) catch |err| block: {
                            sdk.misc.error_context.append(
                                "Failed to construct directory path from file path: {s}",
                                .{path},
                            );
                            sdk.misc.error_context.logError(err);
                            break :block getBaseDirectory(&buffer_2, io);
                        };
                    } else {
                        config.fileName = getTimestampFileName(&buffer_1, io) catch |err| block: {
                            sdk.misc.error_context.append("Failed to construct a timestamp based file name.", .{});
                            sdk.misc.error_context.logError(err);
                            break :block "untitled";
                        };
                        config.path = createAndGetRecordingsDirectory(&buffer_2, io) catch |err_1| block: {
                            sdk.misc.error_context.append("Failed to create \"{s}\" directory.", .{directory_name});
                            sdk.misc.error_context.logError(err_1);
                            break :block getBaseDirectory(&buffer_2, io);
                        };
                    }
                    config.flags |= imgui.ImGuiFileDialogFlags_CaseInsensitiveExtentionFiltering;
                },
                .open => {
                    config.path = createAndGetRecordingsDirectory(&buffer_1, io) catch |err| block: {
                        sdk.misc.error_context.append("Failed to create \"{s}\" directory.", .{directory_name});
                        sdk.misc.error_context.logError(err);
                        break :block getBaseDirectory(&buffer_2, io);
                    };
                },
            }
            imgui.IGFD_OpenDialog(
                context,
                getKey(self.type),
                getTitle(self.type),
                switch (self.type) {
                    .save => save_filters,
                    .open => open_filters,
                },
                config,
            );
        }
        if (self.is_open and !is_open) {
            imgui.IGFD_CloseDialog(context);
        }

        const display_size = imgui.igGetIO_Nil().*.DisplaySize;
        const has_action = imgui.IGFD_DisplayDialog(
            context,
            getKey(self.type),
            imgui.ImGuiWindowFlags_NoCollapse,
            .{ .x = 0.5 * display_size.x, .y = 0.5 * display_size.y },
            .{ .x = display_size.x, .y = display_size.y },
        );
        if (self.is_open and is_open and imgui.igShortcut_Nil(
            imgui.ImGuiKey_Escape,
            imgui.ImGuiInputFlags_RouteGlobal | imgui.ImGuiInputFlags_RouteOverActive,
        )) {
            self.action = .cancel;
            return;
        }
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

        self.last_selected_path = FilePath.fromSlice(path) catch {
            std.log.err(
                "Selected path exceeds the maximum allowed file path size ({}): {s}",
                .{ FilePath.max_len, path },
            );
            self.action = .no_action;
            return;
        };

        self.action = .proceed;
    }

    fn getKey(dialog_type: Type) [:0]const u8 {
        return switch (dialog_type) {
            .save => "save_dialog",
            .open => "open_dialog",
        };
    }

    fn getTitle(dialog_type: Type) [:0]const u8 {
        return switch (dialog_type) {
            .save => "Save As",
            .open => "Open",
        };
    }

    fn getBaseDirectory(buffer: *[sdk.os.max_file_path_length]u8, io: std.Io) [:0]const u8 {
        const len = std.Io.Dir.cwd().realPath(io, buffer[0..(buffer.len - 1)]) catch |err| {
            sdk.misc.error_context.append("Failed to construct base directory path.", .{});
            sdk.misc.error_context.logError(err);
            return ".";
        };
        buffer[len] = 0;
        return buffer[0..len :0];
    }

    fn createAndGetRecordingsDirectory(buffer: *[sdk.os.max_file_path_length]u8, io: std.Io) ![:0]const u8 {
        std.Io.Dir.cwd().createDirPath(io, directory_name) catch |err| {
            sdk.misc.error_context.append("Failed to make directory: {s}", .{directory_name});
            return err;
        };
        const len = std.Io.Dir.cwd().realPathFile(io, directory_name, buffer[0..(buffer.len - 1)]) catch |err| {
            sdk.misc.error_context.append("Failed to construct \"{s}\" directory path.", .{directory_name});
            return err;
        };
        buffer[len] = 0;
        return buffer[0..len :0];
    }

    fn getTimestampFileName(buffer: []u8, io: std.Io) ![:0]const u8 {
        const nano = std.Io.Clock.real.now(io).nanoseconds;
        const ts = sdk.misc.Timestamp.fromNano(nano, .local) catch |err| {
            sdk.misc.error_context.append("Failed to construct timestamp structure for nano timestamp: {}", .{nano});
            return err;
        };
        return std.fmt.bufPrintSentinel(
            buffer,
            "{:0>4}-{:0>2}-{:0>2}T{:0>2}-{:0>2}-{:0>2}",
            .{ @abs(ts.year), ts.month, ts.day, ts.hour, ts.minute, ts.second },
            0,
        ) catch |err| {
            sdk.misc.error_context.append("Failed to construct timestamp string for nano time: {}", .{nano});
            return err;
        };
    }

    fn filePathToDirectoryPath(buffer: []u8, file_path: []const u8) ![:0]const u8 {
        const directory_path = sdk.os.filePathToDirectoryPath(file_path);
        return std.fmt.bufPrintSentinel(buffer, "{s}", .{directory_path}, 0) catch |err| {
            sdk.misc.error_context.new("Failed to put the result string into buffer: {s}", .{directory_path});
            return err;
        };
    }

    fn filePathToFileNameWithoutExtension(buffer: []u8, file_path: []const u8) ![:0]const u8 {
        const extension = block: {
            const format = model.RecordingFormat.fromFilePath(file_path) orelse break :block "";
            break :block format.getFileExtension();
        };
        const file_name = sdk.os.pathToFileName(file_path);
        const result = file_name[0..(file_name.len - extension.len)];
        return std.fmt.bufPrintSentinel(buffer, "{s}", .{result}, 0) catch |err| {
            sdk.misc.error_context.new("Failed to put the result string into buffer: {s}", .{result});
            return err;
        };
    }

    pub fn getLastSelectedPath(self: *const Self) ?[:0]const u8 {
        if (self.last_selected_path.len == 0) {
            return null;
        }
        return self.last_selected_path.asSlice();
    }
};

const testing = std.testing;

const MockController = struct {
    mode: Mode = .live,
    file_path: FilePath = .empty,
    contains_unsaved_changes: bool = false,
    did_last_save_or_load_succeed: bool = false,
    total_frames: usize = 100,
    clear_call_count: usize = 0,
    save_call_count: usize = 0,
    last_save_io: ?std.Io = null,
    last_save_path: ?FilePath = null,
    load_call_count: usize = 0,
    last_load_io: ?std.Io = null,
    last_load_path: ?FilePath = null,

    const Self = @This();
    pub const Mode = enum {
        live,
        record,
        pause,
        playback,
        scrub,
        load,
        save,
    };
    pub const FilePath = sdk.misc.BoundedArray(sdk.os.max_file_path_length, u8, 0, true);

    pub fn clear(self: *Self) void {
        self.clear_call_count += 1;
        self.mode = .live;
    }

    pub fn save(self: *Self, io: std.Io, path: []const u8) void {
        self.save_call_count += 1;
        self.last_save_io = io;
        self.last_save_path = .fromSliceTrimmed(path);
        self.mode = .save;
    }

    pub fn load(self: *Self, io: std.Io, path: []const u8) void {
        self.load_call_count += 1;
        self.last_load_io = io;
        self.last_load_path = .fromSliceTrimmed(path);
        self.mode = .load;
    }

    pub fn getTotalFrames(self: *const Self) usize {
        return self.total_frames;
    }

    pub fn getFilePath(self: *const Self) ?[:0]const u8 {
        if (self.file_path.len == 0) {
            return null;
        }
        return self.file_path.asSlice();
    }
};

test "should call clear on controller when new is clicked without unsaved changes" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{
            .contains_unsaved_changes = false,
            .file_path = .fromArray("./test.irony".*),
        };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try testing.expectEqual(0, controller.clear_call_count);
            ctx.setRef("Window");
            ctx.menuClick("File/New");
            try testing.expectEqual(1, controller.clear_call_count);
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "new should be disabled when total frames is zero" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{ .total_frames = 0 };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try testing.expectEqual(0, controller.clear_call_count);
            ctx.setRef("Window");
            ctx.menuClick("File/New");
            try testing.expectEqual(0, controller.clear_call_count);
            ctx.setRef("//$FOCUSED");
            try ctx.expectItemNotExists("Cancel");
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should show correctly working unsaved changes dialog when new is clicked with unsaved changes" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{
            .contains_unsaved_changes = true,
            .file_path = .empty,
        };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(0, controller.clear_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/New");
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(0, controller.clear_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("Cancel", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(0, controller.clear_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/New");
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(0, controller.clear_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("Don't Save", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, controller.clear_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/New");
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, controller.clear_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("Save", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, controller.clear_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("**/Cancel##validationdialog", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, controller.clear_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/New");
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, controller.clear_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("Save", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, controller.clear_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemInputValueStr("**/##FileName", "test"); // Presses enter so no need to click OK.
            try testing.expectEqual(1, controller.save_call_count);
            try testing.expectEqual(1, controller.clear_call_count);
            try testing.expectStringEndsWith(controller.last_save_path.?.asSlice(), "test.irony");
            try testing.expectEqual(testing.io, controller.last_save_io);
            controller.mode = .live;
            controller.did_last_save_or_load_succeed = true;
            ctx.yield(1);
            try testing.expectEqual(1, controller.save_call_count);
            try testing.expectEqual(2, controller.clear_call_count);
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "unsaved changes dialog should react to keyboard shortcuts" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{
            .contains_unsaved_changes = true,
            .file_path = .fromArray("./test.irony".*),
        };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            ctx.menuClick("File/New");
            ctx.keyPress(imgui.ImGuiKey_Escape, 1);
            ctx.yield(3); // Test engine caches item lookups for 2 frames.
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(0, controller.clear_call_count);
            try ctx.expectItemNotExists("//Unsaved Changes/Cancel");

            ctx.setRef("Window");
            ctx.menuClick("File/New");
            ctx.keyPress(imgui.ImGuiKey_D, 1);
            ctx.yield(3); // Test engine caches item lookups for 2 frames.
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, controller.clear_call_count);
            try ctx.expectItemNotExists("//Unsaved Changes/Cancel");

            ctx.setRef("Window");
            ctx.menuClick("File/New");
            ctx.keyPress(imgui.ImGuiKey_S, 1);
            try testing.expectEqual(1, controller.save_call_count);
            try testing.expectEqual(1, controller.clear_call_count);
            try testing.expectStringEndsWith(controller.last_save_path.?.asSlice(), "test.irony");
            controller.mode = .live;
            controller.did_last_save_or_load_succeed = true;
            ctx.yield(3); // Test engine caches item lookups for 2 frames.
            try testing.expectEqual(1, controller.save_call_count);
            try testing.expectEqual(2, controller.clear_call_count);
            try ctx.expectItemNotExists("//Unsaved Changes/Cancel");
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "unsaved changes dialog shortcuts should do nothing when dialog is closed" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{
            .contains_unsaved_changes = true,
            .file_path = .fromArray("./test.irony".*),
        };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.keyPress(imgui.ImGuiKey_S, 1);
            ctx.keyPress(imgui.ImGuiKey_D, 1);
            ctx.keyPress(imgui.ImGuiKey_Escape, 1);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(0, controller.clear_call_count);
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call load on controller when open is clicked without unsaved changes and file is selected" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{
            .contains_unsaved_changes = false,
            .file_path = .fromArray("./test.irony".*),
        };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try testing.expectEqual(0, controller.load_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/Open");
            try testing.expectEqual(0, controller.load_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("**/Cancel##validationdialog", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.load_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/Open");
            try testing.expectEqual(0, controller.load_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemInputValueStr("**/##FileName", "test"); // Presses enter so no need to click OK.
            try testing.expectEqual(1, controller.load_call_count);
            try testing.expectStringEndsWith(controller.last_load_path.?.asSlice(), "test.irony");
            try testing.expectEqual(testing.io, controller.last_load_io);
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "open dialog should focus file name input when opened" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{ .contains_unsaved_changes = false };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            for (0..2) |_| { // Second iteration checks that focus is requested again when the dialog is reopened.
                ctx.setRef("Window");
                ctx.menuClick("File/Open");
                ctx.yield(1);
                ctx.keyChars("test");
                ctx.keyPress(imgui.ImGuiKey_Enter, 1);
                controller.mode = .live;
                controller.did_last_save_or_load_succeed = true;
                ctx.yield(1);
            }
            try testing.expectEqual(2, controller.load_call_count);
            try testing.expectEqualStrings("test.irony", sdk.os.pathToFileName(controller.last_load_path.?.asSlice()));
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "save dialog should focus file name input and select its content when opened" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{ .file_path = .empty };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            ctx.menuClick("File/Save As");
            ctx.yield(1);
            ctx.keyChars("test");
            ctx.keyPress(imgui.ImGuiKey_Enter, 1);
            ctx.yield(1);
            try testing.expectEqual(1, controller.save_call_count);
            try testing.expectEqualStrings("test.irony", sdk.os.pathToFileName(controller.last_save_path.?.asSlice()));
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "escape should cancel open dialog" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{ .contains_unsaved_changes = false };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            ctx.menuClick("File/Open");
            ctx.yield(1);
            ctx.keyChars("test"); // Makes sure the file name input is active and handling keys.
            ctx.yield(10);
            ctx.keyPress(imgui.ImGuiKey_Escape, 1);
            ctx.yield(3); // Test engine caches item lookups for 2 frames.
            try ctx.expectItemNotExists("//Open##open_dialog/**/##FileName");
            try testing.expectEqual(0, controller.load_call_count);

            // Dialog should be usable again after being cancelled.
            ctx.setRef("Window");
            ctx.menuClick("File/Open");
            ctx.yield(1);
            ctx.keyChars("test");
            ctx.keyPress(imgui.ImGuiKey_Enter, 1);
            try testing.expectEqual(1, controller.load_call_count);
            try testing.expectEqualStrings("test.irony", sdk.os.pathToFileName(controller.last_load_path.?.asSlice()));
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "escape should cancel save dialog" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{ .file_path = .empty };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            ctx.menuClick("File/Save As");
            ctx.yield(1);
            ctx.keyChars("test"); // Makes sure the file name input is active and handling keys.
            ctx.yield(10);
            ctx.keyPress(imgui.ImGuiKey_Escape, 1);
            ctx.yield(3); // Test engine caches item lookups for 2 frames.
            try ctx.expectItemNotExists("//Save As##save_dialog/**/##FileName");
            try testing.expectEqual(0, controller.save_call_count);
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

const existing_recording_path = "recordings/existing.irony";

fn createExistingRecording() !void {
    try std.Io.Dir.cwd().createDirPath(testing.io, "recordings");
    const file = try std.Io.Dir.cwd().createFile(testing.io, existing_recording_path, .{});
    file.close(testing.io);
}

fn deleteExistingRecording() void {
    std.Io.Dir.cwd().deleteFile(testing.io, existing_recording_path) catch {
        @panic("Failed to clean up file: " ++ existing_recording_path);
    };
}

test "should ask for overwrite confirmation when saving over an existing file" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{ .file_path = .empty };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            ctx.menuClick("File/Save As");
            ctx.yield(1);
            ctx.keyChars("existing");
            ctx.keyPress(imgui.ImGuiKey_Enter, 1);
            ctx.yield(3); // Test engine caches item lookups for 2 frames.
            try ctx.expectItemNotExists("//Save As##save_dialog/**/##FileName");
            try ctx.expectItemExists("//File Already Exists/Overwrite");
            try testing.expectEqual(0, controller.save_call_count);

            ctx.setRef("//File Already Exists");
            ctx.itemClick("Overwrite", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(1, controller.save_call_count);
            try testing.expectEqualStrings("existing.irony", sdk.os.pathToFileName(controller.last_save_path.?.asSlice()));
            ctx.yield(3); // Test engine caches item lookups for 2 frames.
            try ctx.expectItemNotExists("//File Already Exists/Overwrite");
        }
    };
    try createExistingRecording();
    defer deleteExistingRecording();
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "cancelling overwrite confirmation should reopen save dialog with the same file name" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{ .file_path = .empty };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            ctx.menuClick("File/Save As");
            ctx.yield(1);
            ctx.keyChars("existing");
            ctx.keyPress(imgui.ImGuiKey_Enter, 1);
            ctx.yield(1);
            try ctx.expectItemExists("//File Already Exists/Cancel");

            ctx.setRef("//File Already Exists");
            ctx.itemClick("Cancel", imgui.ImGuiMouseButton_Left, 0);
            ctx.yield(3); // Test engine caches item lookups for 2 frames.
            try ctx.expectItemNotExists("//File Already Exists/Cancel");
            try ctx.expectItemExists("//Save As##save_dialog/**/##FileName");
            try testing.expectEqual(0, controller.save_call_count);

            // File name input is focused and contains the previously selected name, so enter selects the same file.
            ctx.keyPress(imgui.ImGuiKey_Enter, 1);
            ctx.yield(1);
            try ctx.expectItemExists("//File Already Exists/Overwrite");
            ctx.setRef("//File Already Exists");
            ctx.itemClick("Overwrite", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(1, controller.save_call_count);
            try testing.expectEqualStrings("existing.irony", sdk.os.pathToFileName(controller.last_save_path.?.asSlice()));
        }
    };
    try createExistingRecording();
    defer deleteExistingRecording();
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "overwrite confirmation should react to keyboard shortcuts" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{ .file_path = .empty };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            ctx.menuClick("File/Save As");
            ctx.yield(1);
            ctx.keyChars("existing");
            ctx.keyPress(imgui.ImGuiKey_Enter, 1);
            ctx.yield(1);
            try ctx.expectItemExists("//File Already Exists/Cancel");

            ctx.keyPress(imgui.ImGuiKey_Escape, 1);
            ctx.yield(3); // Test engine caches item lookups for 2 frames.
            try ctx.expectItemNotExists("//File Already Exists/Cancel");
            try ctx.expectItemExists("//Save As##save_dialog/**/##FileName");
            try testing.expectEqual(0, controller.save_call_count);

            ctx.keyPress(imgui.ImGuiKey_Enter, 1);
            ctx.yield(1);
            try ctx.expectItemExists("//File Already Exists/Overwrite");
            ctx.keyPress(imgui.ImGuiKey_Enter, 1);
            try testing.expectEqual(1, controller.save_call_count);
            try testing.expectEqualStrings("existing.irony", sdk.os.pathToFileName(controller.last_save_path.?.asSlice()));
        }
    };
    try createExistingRecording();
    defer deleteExistingRecording();
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "save dialog should not reuse file name from a cancelled save" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{ .file_path = .empty };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.setRef("Window");
            ctx.menuClick("File/Save As");
            ctx.yield(1);
            ctx.keyChars("existing");
            ctx.keyPress(imgui.ImGuiKey_Enter, 1);
            ctx.yield(1);
            ctx.keyPress(imgui.ImGuiKey_Escape, 1); // Cancels overwrite confirmation.
            ctx.yield(10);
            ctx.keyPress(imgui.ImGuiKey_Escape, 1); // Cancels save dialog.
            ctx.yield(3); // Test engine caches item lookups for 2 frames.
            try ctx.expectItemNotExists("//Save As##save_dialog/**/##FileName");

            // Reopened dialog has the default timestamp name, so enter saves without overwrite confirmation.
            ctx.setRef("Window");
            ctx.menuClick("File/Save As");
            ctx.yield(1);
            ctx.keyPress(imgui.ImGuiKey_Enter, 1);
            try testing.expectEqual(1, controller.save_call_count);
            const file_name = sdk.os.pathToFileName(controller.last_save_path.?.asSlice());
            try testing.expect(!std.mem.eql(u8, file_name, "existing.irony"));
        }
    };
    try createExistingRecording();
    defer deleteExistingRecording();
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should show correctly working unsaved changes dialog when open is clicked with unsaved changes" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{
            .contains_unsaved_changes = true,
            .file_path = .empty,
        };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(0, controller.load_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/Open");
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(0, controller.load_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("Cancel", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(0, controller.load_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/Open");
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(0, controller.load_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("Don't Save", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(0, controller.load_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("**/Cancel##validationdialog", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(0, controller.load_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/Open");
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(0, controller.load_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("Don't Save", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(0, controller.load_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemInputValueStr("**/##FileName", "test"); // Presses enter so no need to click OK.
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, controller.load_call_count);
            try testing.expectStringEndsWith(controller.last_load_path.?.asSlice(), "test.irony");
            try testing.expectEqual(testing.io, controller.last_load_io);
            controller.mode = .live;
            controller.did_last_save_or_load_succeed = false;
            ctx.yield(1);

            ctx.setRef("Window");
            ctx.menuClick("File/Open");
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, controller.load_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("Save", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, controller.load_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("**/Cancel##validationdialog", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, controller.load_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/Open");
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, controller.load_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("Save", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, controller.load_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemInputValueStr("**/##FileName", "test1"); // Presses enter so no need to click OK.
            try testing.expectEqual(1, controller.save_call_count);
            try testing.expectEqual(1, controller.load_call_count);
            try testing.expectStringEndsWith(controller.last_save_path.?.asSlice(), "test1.irony");
            try testing.expectEqual(testing.io, controller.last_save_io);
            controller.mode = .live;
            controller.did_last_save_or_load_succeed = true;
            controller.file_path = .fromArray("./test.irony".*); // Makes the next save without a file dialog.
            ctx.yield(1);
            try testing.expectEqual(1, controller.save_call_count);
            try testing.expectEqual(1, controller.load_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("**/Cancel##validationdialog", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(1, controller.save_call_count);
            try testing.expectEqual(1, controller.load_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/Open");
            try testing.expectEqual(1, controller.save_call_count);
            try testing.expectEqual(1, controller.load_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("Save", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(2, controller.save_call_count); // No file dialog for saving this time.
            try testing.expectEqual(1, controller.load_call_count);
            controller.mode = .live;
            controller.did_last_save_or_load_succeed = true;
            ctx.yield(1);
            try testing.expectEqual(2, controller.save_call_count);
            try testing.expectEqual(1, controller.load_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemInputValueStr("**/##FileName", "test2"); // Presses enter so no need to click OK.
            try testing.expectEqual(2, controller.save_call_count);
            try testing.expectEqual(2, controller.load_call_count);
            try testing.expectStringEndsWith(controller.last_load_path.?.asSlice(), "test2.irony");
            try testing.expectEqual(testing.io, controller.last_load_io);
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call save on controller when save is clicked and file is selected" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{
            .file_path = .empty,
        };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try testing.expectEqual(0, controller.save_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/Save");
            try testing.expectEqual(0, controller.save_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("**/Cancel##validationdialog", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/Save");
            try testing.expectEqual(0, controller.save_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemInputValueStr("**/##FileName", "test"); // Presses enter so no need to click OK.
            try testing.expectEqual(1, controller.save_call_count);
            try testing.expectStringEndsWith(controller.last_save_path.?.asSlice(), "test.irony");
            try testing.expectEqual(testing.io, controller.last_save_io);
            controller.mode = .live;
            controller.did_last_save_or_load_succeed = true;
            controller.file_path = .fromArray("./test.irony".*); // Makes the next save without a file dialog.
            ctx.yield(1);

            ctx.setRef("Window");
            ctx.menuClick("File/Save");
            try testing.expectEqual(2, controller.save_call_count);
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "save should be disabled when total frames is zero" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{ .total_frames = 0 };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try testing.expectEqual(0, controller.save_call_count);
            ctx.setRef("Window");
            ctx.menuClick("File/Save");
            try testing.expectEqual(0, controller.save_call_count);
            ctx.setRef("//$FOCUSED");
            try ctx.expectItemNotExists("**/##FileName");
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call save on controller when save as is clicked and file is selected" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{};
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try testing.expectEqual(0, controller.save_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/Save As");
            try testing.expectEqual(0, controller.save_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("**/Cancel##validationdialog", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/Save As");
            try testing.expectEqual(0, controller.save_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemInputValueStr("**/##FileName", "test1"); // Presses enter so no need to click OK.
            try testing.expectEqual(1, controller.save_call_count);
            try testing.expectStringEndsWith(controller.last_save_path.?.asSlice(), "test1.irony");
            try testing.expectEqual(testing.io, controller.last_save_io);
            controller.mode = .live;
            controller.did_last_save_or_load_succeed = true;
            controller.file_path = .fromArray("./test.irony".*); // Would make the next save without a file dialog.
            ctx.yield(1);

            ctx.setRef("Window");
            ctx.menuClick("File/Save As"); // Since its save "as" it has to show file dialog every time.
            try testing.expectEqual(1, controller.save_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemInputValueStr("**/##FileName", "test2"); // Presses enter so no need to click OK.
            try testing.expectEqual(2, controller.save_call_count);
            try testing.expectStringEndsWith(controller.last_save_path.?.asSlice(), "test2.irony");
            try testing.expectEqual(testing.io, controller.last_save_io);
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "save as should be disabled when total frames is zero" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{ .total_frames = 0 };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try testing.expectEqual(0, controller.save_call_count);
            ctx.setRef("Window");
            ctx.menuClick("File/Save As");
            try testing.expectEqual(0, controller.save_call_count);
            ctx.setRef("//$FOCUSED");
            try ctx.expectItemNotExists("**/##FileName");
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should set is_ui_open to false when close ui button is clicked" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{};
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try testing.expectEqual(true, is_ui_open);
            ctx.setRef("Window");
            ctx.menuClick("File/Close UI");
            try testing.expectEqual(false, is_ui_open);
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should trigger file menu actions with keyboard shortcuts while menu is closed" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{
            .contains_unsaved_changes = false,
            .file_path = .fromArray("./test.irony".*),
        };
        var is_ui_open: bool = true;
        var shutdown_call_count: usize = 0;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {
            shutdown_call_count += 1;
        }

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_N, 1);
            try testing.expectEqual(1, controller.clear_call_count);

            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_S, 1);
            try testing.expectEqual(1, controller.save_call_count);
            try testing.expectEqualStrings("./test.irony", controller.last_save_path.?.asSlice());
            controller.mode = .live;
            controller.did_last_save_or_load_succeed = true;
            // Frame 1: file menu becomes idle. Frame 2: shortcut routes get registered again.
            // Routes only take effect on the frame after they get registered, so the key press comes on frame 3.
            ctx.yield(2);

            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiMod_Shift | imgui.ImGuiKey_S, 1);
            ctx.yield(1);
            try ctx.expectItemExists("//Save As##save_dialog/**/##FileName");
            try testing.expectEqual(1, controller.save_call_count);
            ctx.keyPress(imgui.ImGuiKey_Escape, 1);
            ctx.yield(3); // Test engine caches item lookups for 2 frames.
            try ctx.expectItemNotExists("//Save As##save_dialog/**/##FileName");

            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_O, 1);
            ctx.yield(1);
            try ctx.expectItemExists("//Open##open_dialog/**/##FileName");
            ctx.keyPress(imgui.ImGuiKey_Escape, 1);
            ctx.yield(3); // Test engine caches item lookups for 2 frames.
            try ctx.expectItemNotExists("//Open##open_dialog/**/##FileName");

            try testing.expectEqual(0, shutdown_call_count);
            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_Q, 1);
            try testing.expectEqual(1, shutdown_call_count);

            try testing.expectEqual(1, controller.clear_call_count);
            try testing.expectEqual(1, controller.save_call_count);
            try testing.expectEqual(0, controller.load_call_count);
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "keyboard shortcuts should not trigger disabled file menu actions" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{ .total_frames = 0, .file_path = .fromArray("./test.irony".*) };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {}

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_N, 1);
            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_S, 1);
            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiMod_Shift | imgui.ImGuiKey_S, 1);
            ctx.yield(3); // Test engine caches item lookups for 2 frames.
            try testing.expectEqual(0, controller.clear_call_count);
            try testing.expectEqual(0, controller.save_call_count);
            try ctx.expectItemNotExists("//Save As##save_dialog/**/##FileName");
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "file menu keyboard shortcuts should be ignored while another modal dialog is open" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{ .contains_unsaved_changes = false };
        var is_ui_open: bool = true;
        var is_other_dialog_open: bool = true;
        var shutdown_call_count: usize = 0;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};

        fn selfShutdown() void {
            shutdown_call_count += 1;
        }

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (ui.beginDialog(&is_other_dialog_open, "Other Dialog")) {
                defer ui.endDialog();
                _ = imgui.igButton("Content", .{});
            }
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try ctx.expectItemExists("//Other Dialog/Content");
            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_N, 1);
            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_Q, 1);
            try testing.expectEqual(0, controller.clear_call_count);
            try testing.expectEqual(0, shutdown_call_count);

            is_other_dialog_open = false;
            ctx.yield(1);
            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_N, 1);
            ctx.keyPress(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_Q, 1);
            try testing.expectEqual(1, controller.clear_call_count);
            try testing.expectEqual(1, shutdown_call_count);
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should call self shutdown when exit is clicked without unsaved changes" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{
            .contains_unsaved_changes = false,
            .file_path = .fromArray("./test.irony".*),
        };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};
        var shutdown_call_count: usize = 0;

        fn selfShutdown() void {
            shutdown_call_count += 1;
        }

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try testing.expectEqual(0, shutdown_call_count);
            ctx.setRef("Window");
            ctx.menuClick("File/Exit " ++ build_info.display_name);
            try testing.expectEqual(1, shutdown_call_count);
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should show correctly working unsaved changes dialog when exit is clicked with unsaved changes" {
    const Test = struct {
        var file_dialog_context: *imgui.ImGuiFileDialog = undefined;
        var controller: MockController = .{
            .contains_unsaved_changes = true,
            .file_path = .empty,
        };
        var is_ui_open: bool = true;
        var file_menu: FileMenu(.{ .Controller = MockController, .selfShutDown = selfShutdown }) = .{};
        var shutdown_call_count: usize = 0;

        fn selfShutdown() void {
            shutdown_call_count += 1;
        }

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, imgui.ImGuiWindowFlags_MenuBar);
            defer imgui.igEnd();
            if (!imgui.igBeginMenuBar()) return;
            defer imgui.igEndMenuBar();
            file_menu.draw(testing.io, file_dialog_context, &controller, &is_ui_open);
            file_menu.update(testing.io, &controller);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(0, shutdown_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/Exit " ++ build_info.display_name);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(0, shutdown_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("Cancel", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(0, shutdown_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/Exit " ++ build_info.display_name);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(0, shutdown_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("Don't Save", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, shutdown_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/Exit " ++ build_info.display_name);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, shutdown_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("Save", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, shutdown_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("**/Cancel##validationdialog", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, shutdown_call_count);

            ctx.setRef("Window");
            ctx.menuClick("File/Exit " ++ build_info.display_name);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, shutdown_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("Save", imgui.ImGuiMouseButton_Left, 0);
            try testing.expectEqual(0, controller.save_call_count);
            try testing.expectEqual(1, shutdown_call_count);
            ctx.setRef("//$FOCUSED");
            ctx.itemInputValueStr("**/##FileName", "test"); // Presses enter so no need to click OK.
            try testing.expectEqual(1, controller.save_call_count);
            try testing.expectEqual(1, shutdown_call_count);
            try testing.expectStringEndsWith(controller.last_save_path.?.asSlice(), "test.irony");
            try testing.expectEqual(testing.io, controller.last_save_io);
            controller.mode = .live;
            controller.did_last_save_or_load_succeed = true;
            ctx.yield(1);
            try testing.expectEqual(1, controller.save_call_count);
            try testing.expectEqual(2, shutdown_call_count);
        }
    };
    Test.file_dialog_context = imgui.IGFD_Create() orelse @panic("Failed to create file dialog context.");
    defer imgui.IGFD_Destroy(Test.file_dialog_context);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
