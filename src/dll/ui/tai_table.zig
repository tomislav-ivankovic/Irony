const std = @import("std");
const imgui = @import("imgui");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const core = @import("../core/root.zig");
const ui = @import("root.zig");

pub const TaiTable = struct {
    editor: ui.TaiEditor,
    state: State,
    previous_selection: ui.TaiEditor.Selection,
    previous_frame_index: ?usize,
    previous_tai_mode: TaiMode,
    previous_hovered_index: ?usize,
    frame_index_before_hover: ?usize,
    scroll_area_visible_height: f32,

    const Self = @This();
    const State = union(enum) {
        idle: void,
        confirming: Confirming,
        selecting: void,
        moving: Moving,
        editing: Editing,

        pub const Confirming = enum {
            import,
            clear,
        };
        pub const Moving = struct {
            handle_index: usize,
        };
        pub const Editing = struct {
            text_buffer: [buffer_size]u8,
            select_all: bool,
            input_activated: bool = false,

            pub const buffer_size = 32;
            pub const empty_buffer: [buffer_size]u8 = @splat(0);
        };
    };
    const Dimensions = struct {
        scroll_area_screen_top: f32,
        scroll_area_visible_height: f32,
        player_divide_screen_x: f32,
    };
    const TaiMode = enum {
        idle,
        play,
    };
    const table_route = imgui.ImGuiInputFlags_RouteFocused;
    const window_route = imgui.ImGuiInputFlags_RouteFocused | imgui.ImGuiInputFlags_RouteFromRootWindow;

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .editor = .init(allocator),
            .state = .idle,
            .previous_selection = .initial,
            .previous_tai_mode = .idle,
            .previous_frame_index = null,
            .previous_hovered_index = null,
            .frame_index_before_hover = null,
            .scroll_area_visible_height = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.editor.deinit();
    }

    pub fn draw(
        self: *Self,
        tai: *core.ToolAssistedInput,
        controller: *core.Controller,
        enable_player_1: *bool,
        enable_player_2: *bool,
    ) void {
        defer self.previous_frame_index = controller.getCurrentFrameIndex();
        defer self.previous_selection = self.editor.selection;

        const frame_padding = imgui.igGetStyle().*.FramePadding.y;
        const scroll_area_screen_top = block: {
            var vec: imgui.ImVec2 = undefined;
            imgui.igGetCursorScreenPos(&vec);
            const row_height = imgui.igGetTextLineHeightWithSpacing();
            break :block vec.y + row_height + frame_padding;
        };
        defer {
            var vec: imgui.ImVec2 = undefined;
            imgui.igGetCursorScreenPos(&vec);
            self.scroll_area_visible_height = vec.y - scroll_area_screen_top - frame_padding;
        }

        const table_flags = imgui.ImGuiTableFlags_ScrollY | imgui.ImGuiTableFlags_Borders;
        const is_rendered = imgui.igBeginTable("table", 7, table_flags, .{}, 0);
        if (!is_rendered) {
            return;
        }
        defer imgui.igEndTable();

        const frame_start_selection = self.editor.selection;

        if (imgui.igIsWindowFocused(imgui.ImGuiFocusedFlags_ChildWindows)) {
            self.handleKeyboardSelect(tai.sequence.items.len);
            self.handleSelectAllShortcut(tai.sequence.items.len);
            self.handleClearValuesShortcut(tai.sequence.items.len);
            self.handleEditShortcut(tai);
            self.handleConfirmEditShortcut(tai.sequence.items.len);
            self.handleMoveShortcut(tai.sequence.items.len);
            self.handleSwapShortcut(tai.sequence.items.len);
        }
        if (imgui.igIsWindowFocused(imgui.ImGuiFocusedFlags_RootAndChildWindows)) {
            handleEnabledShortcut(enable_player_1, .player_1);
            handleEnabledShortcut(enable_player_2, .player_2);
            self.handleCancelShortcut();
            self.handleUndoShortcut(tai);
            self.handleRedoShortcut(tai);
            self.handleImportShortcut(tai, controller);
            self.handleClearShortcut(tai);
            self.handleInsertShortcut();
            self.handleDeleteShortcut(tai.sequence.items.len);
            self.handleCopyShortcut(tai);
            self.handlePasteShortcut(tai.sequence.items.len);
        }

        imgui.igTableSetupScrollFreeze(0, 1);
        imgui.igTableSetupColumn("move", imgui.ImGuiTableColumnFlags_WidthFixed, 0, 0);
        imgui.igTableSetupColumn("player_1_input", imgui.ImGuiTableColumnFlags_WidthStretch, 0, 0);
        imgui.igTableSetupColumn("player_1_animation_frame", imgui.ImGuiTableColumnFlags_WidthFixed, 0, 0);
        imgui.igTableSetupColumn("swap", imgui.ImGuiTableColumnFlags_WidthFixed, 0, 0);
        imgui.igTableSetupColumn("player_2_animation_frame", imgui.ImGuiTableColumnFlags_WidthFixed, 0, 0);
        imgui.igTableSetupColumn("player_2_input", imgui.ImGuiTableColumnFlags_WidthStretch, 0, 0);
        imgui.igTableSetupColumn("buttons", imgui.ImGuiTableColumnFlags_WidthFixed, 0, 0);

        const header_color = imgui.igGetStyle().*.Colors[imgui.ImGuiCol_TableHeaderBg];

        var player_divide_screen_x: f32 = 0;
        if (imgui.igTableNextColumn()) {
            imgui.igPushID_Str("move");
            defer imgui.igPopID();
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_HeaderHovered, header_color);
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_HeaderActive, header_color);
            defer imgui.igPopStyleColor(2);

            self.drawCancelButton();
            imgui.igSameLine(0, 0);
            imgui.igTableHeader("");
        }
        if (imgui.igTableNextColumn()) {
            imgui.igPushID_Str("player_1_input");
            defer imgui.igPopID();

            drawEnabledCheckbox(enable_player_1, .player_1);
            imgui.igSameLine(0, imgui.igGetStyle().*.ItemInnerSpacing.x);
            imgui.igTableHeader("Player 1");
        }
        if (imgui.igTableNextColumn()) {
            imgui.igPushID_Str("player_1_animation_frame");
            defer imgui.igPopID();
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_HeaderHovered, header_color);
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_HeaderActive, header_color);
            defer imgui.igPopStyleColor(2);

            self.drawUndoButton(tai);
            imgui.igSameLine(0, 0);
            imgui.igTableHeader("");
        }
        if (imgui.igTableNextColumn()) {
            var start: imgui.ImVec2 = undefined;
            imgui.igGetCursorScreenPos(&start);
            var size: imgui.ImVec2 = undefined;
            imgui.igGetContentRegionAvail(&size);
            player_divide_screen_x = start.x + 0.5 * size.x;

            imgui.igPushID_Str("swap");
            defer imgui.igPopID();
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_HeaderHovered, header_color);
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_HeaderActive, header_color);
            defer imgui.igPopStyleColor(2);

            self.drawSwapButton(null, tai.sequence.items.len);
            imgui.igSameLine(0, 0);
            imgui.igTableHeader("");
        }
        if (imgui.igTableNextColumn()) {
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_HeaderHovered, header_color);
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_HeaderActive, header_color);
            defer imgui.igPopStyleColor(2);

            imgui.igPushID_Str("player_2_animation_frame");
            defer imgui.igPopID();
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_HeaderHovered, header_color);
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_HeaderActive, header_color);
            defer imgui.igPopStyleColor(2);

            self.drawRedoButton(tai);
            imgui.igSameLine(0, 0);
            imgui.igTableHeader("");
        }
        if (imgui.igTableNextColumn()) {
            imgui.igPushID_Str("player_2_input");
            defer imgui.igPopID();

            drawEnabledCheckbox(enable_player_2, .player_2);
            imgui.igSameLine(0, imgui.igGetStyle().*.ItemInnerSpacing.x);
            imgui.igTableHeader("Player 2");
        }
        if (imgui.igTableNextColumn()) {
            imgui.igPushID_Str("buttons");
            defer imgui.igPopID();
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_HeaderHovered, header_color);
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_HeaderActive, header_color);
            defer imgui.igPopStyleColor(2);

            self.drawImportButton(tai, controller);
            imgui.igSameLine(0, imgui.igGetStyle().*.ItemInnerSpacing.x);
            self.drawClearButton(tai);
            imgui.igSameLine(0, 0);
            imgui.igTableHeader("");
        }

        const number_of_rows = std.math.lossyCast(c_int, tai.sequence.items.len +| 1);
        var clipper = imgui.ImGuiListClipper{};
        imgui.ImGuiListClipper_Begin(&clipper, number_of_rows, imgui.igGetTextLineHeightWithSpacing());
        defer imgui.ImGuiListClipper_End(&clipper);
        while (imgui.ImGuiListClipper_Step(&clipper)) {
            var c_index = clipper.DisplayStart;
            while (c_index < clipper.DisplayEnd) : (c_index += 1) {
                imgui.igPushID_Int(c_index);
                defer imgui.igPopID();
                imgui.igTableNextRow(0, 0);

                const index = std.math.cast(usize, c_index) orelse break;
                const moved_index = self.findSimulatedMoveIndex(
                    index,
                    .destination_to_source,
                    &clipper,
                    tai.sequence.items.len,
                );
                const frame_maybe = controller.getFrameAt(index);

                if (imgui.igTableNextColumn() and moved_index < tai.sequence.items.len) {
                    self.drawMoveButton(moved_index, tai.sequence.items.len);
                }
                if (imgui.igTableNextColumn()) {
                    const p1_index = if (self.editor.selection.isPlayerIdInside(.player_1)) moved_index else index;
                    self.drawInputCellContent(.player_1, p1_index, &frame_start_selection, tai, frame_maybe);
                }
                if (imgui.igTableNextColumn() and index < tai.sequence.items.len) {
                    if (frame_maybe) |frame| {
                        drawAnimationFrameCellContent(.player_1, frame);
                    }
                }
                if (imgui.igTableNextColumn() and index < tai.sequence.items.len) {
                    self.drawSwapButton(index, tai.sequence.items.len);
                }
                if (imgui.igTableNextColumn() and index < tai.sequence.items.len) {
                    if (frame_maybe) |frame| {
                        drawAnimationFrameCellContent(.player_2, frame);
                    }
                }
                if (imgui.igTableNextColumn()) {
                    const p2_index = if (self.editor.selection.isPlayerIdInside(.player_2)) moved_index else index;
                    self.drawInputCellContent(.player_2, p2_index, &frame_start_selection, tai, frame_maybe);
                }
                if (imgui.igTableNextColumn()) {
                    self.drawInsertButton(index);
                    if (index < tai.sequence.items.len) {
                        imgui.igSameLine(0, imgui.igGetStyle().*.ItemInnerSpacing.x);
                        self.drawDeleteButton(index, tai.sequence.items.len);
                    }
                }
            }
        }

        const dimensions = Dimensions{
            .scroll_area_screen_top = scroll_area_screen_top,
            .scroll_area_visible_height = self.scroll_area_visible_height,
            .player_divide_screen_x = player_divide_screen_x,
        };

        self.handleMouseEdit(tai);
        self.handleMouseSelect(&clipper, &dimensions, tai.sequence.items.len);
        self.handleMouseMove(&clipper, tai.sequence.items.len);

        self.editor.commit(tai) catch |err| {
            sdk.misc.error_context.append("Failed to commit tool assisted input change.", .{});
            sdk.misc.error_context.logError(err);
            self.editor.discardUncommitted();
        };

        self.syncWithController(controller, tai);
        self.keepSelectionVisible(&clipper, &dimensions);
        self.handleEdgeScrolling(&dimensions);
    }

    fn syncWithController(self: *Self, controller: *core.Controller, tai: *const core.ToolAssistedInput) void {
        const current_hovered_index: ?usize = if (imgui.igTableGetHoveredRow() > 0) block: {
            break :block @intCast(imgui.igTableGetHoveredRow() - 1);
        } else null;
        defer self.previous_hovered_index = current_hovered_index;
        const tai_mode: TaiMode = switch (tai.mode) {
            .idle => .idle,
            .play => .play,
        };
        defer self.previous_tai_mode = tai_mode;

        if (controller.mode != .pause or tai_mode != .idle or self.previous_tai_mode != .idle) {
            return;
        }

        const current_frame_index = controller.getCurrentFrameIndex();
        const current_selection = self.editor.selection;
        if (current_frame_index != self.previous_frame_index) {
            if (current_frame_index) |index| {
                if (index < tai.sequence.items.len) {
                    self.editor.selection = .{
                        .start = .{ .index = index, .player_id = .player_1 },
                        .end = .{ .index = index, .player_id = .player_2 },
                    };
                }
            }
        } else if (!std.meta.eql(current_selection, self.previous_selection)) {
            const index = current_selection.end.index;
            if (index < controller.getTotalFrames() and index < tai.sequence.items.len) {
                controller.setCurrentFrameIndex(index);
                self.frame_index_before_hover = controller.getCurrentFrameIndex();
            }
        }

        if (current_hovered_index) |index| {
            const mouse_moved = !std.meta.eql(imgui.igGetIO_Nil().*.MouseDelta, imgui.ImVec2{ .x = 0, .y = 0 });
            const scroll_moved = imgui.igGetIO_Nil().*.MouseWheel != 0;
            if ((mouse_moved or scroll_moved) and index < controller.getTotalFrames() and index < tai.sequence.items.len) {
                controller.setCurrentFrameIndex(index);
            }
        } else {
            if (self.previous_hovered_index != null) {
                if (self.frame_index_before_hover) |index| {
                    controller.setCurrentFrameIndex(index);
                }
            }
            self.frame_index_before_hover = controller.getCurrentFrameIndex();
        }
    }

    fn keepSelectionVisible(
        self: *const Self,
        clipper: *const imgui.ImGuiListClipper,
        dimensions: *const Dimensions,
    ) void {
        switch (self.state) {
            .idle => switch (std.meta.eql(self.editor.selection, self.previous_selection)) {
                true => return,
                false => {},
            },
            .editing => |*editing| switch (editing.input_activated) {
                true => return,
                false => {},
            },
            .selecting, .moving, .confirming => return,
        }
        const selection = &self.editor.selection;
        const row_height = clipper.ItemsHeight;
        const selection_start_top = row_height * @as(f32, @floatFromInt(selection.start.index));
        const selection_end_top = row_height * @as(f32, @floatFromInt(selection.end.index));
        const selection_height = @abs(selection_end_top - selection_start_top) + row_height;
        const visible_region_top = imgui.igGetScrollY();
        const visible_region_height = dimensions.scroll_area_visible_height;
        if (selection_end_top < visible_region_top) {
            const scroll_y = switch (selection_height < visible_region_height) {
                true => @min(selection_start_top, selection_end_top),
                false => switch (selection_start_top < selection_end_top) {
                    true => selection_end_top + row_height - visible_region_height,
                    false => selection_end_top,
                },
            };
            imgui.igSetScrollY_Float(scroll_y);
        } else if (selection_end_top + row_height > visible_region_top + visible_region_height) {
            const scroll_y = switch (selection_height < visible_region_height) {
                true => @max(selection_start_top, selection_end_top) + row_height - visible_region_height,
                false => switch (selection_start_top < selection_end_top) {
                    true => selection_end_top + row_height - visible_region_height,
                    false => selection_end_top,
                },
            };
            imgui.igSetScrollY_Float(scroll_y);
        }
    }

    fn handleEdgeScrolling(self: *const Self, dimensions: *const Dimensions) void {
        switch (self.state) {
            .selecting, .moving => {},
            .idle, .confirming, .editing => return,
        }
        var mouse_pos: imgui.ImVec2 = undefined;
        imgui.igGetMousePos(&mouse_pos);
        const mouse_y = mouse_pos.y;
        const scroll_area_start = dimensions.scroll_area_screen_top;
        const scroll_area_end = scroll_area_start + dimensions.scroll_area_visible_height;
        const speed_factor = 0.0005;
        const delta_time = imgui.igGetIO_Nil().*.DeltaTime;
        if (mouse_y < scroll_area_start) {
            const screen_delta = scroll_area_start - mouse_y;
            const scroll_delta = speed_factor * screen_delta * screen_delta * screen_delta * screen_delta * delta_time;
            imgui.igSetScrollY_Float(imgui.igGetScrollY() - scroll_delta);
        } else if (mouse_y > scroll_area_end) {
            const screen_delta = mouse_y - scroll_area_end;
            const scroll_delta = speed_factor * screen_delta * screen_delta * screen_delta * screen_delta * delta_time;
            imgui.igSetScrollY_Float(imgui.igGetScrollY() + scroll_delta);
        }
    }

    fn drawInputCellContent(
        self: *Self,
        player_id: model.PlayerId,
        index: usize,
        frame_start_selection: *const ui.TaiEditor.Selection,
        tai: *const core.ToolAssistedInput,
        frame_maybe: ?*const model.Frame,
    ) void {
        const CellType = enum { normal, selected, active };
        const cell_type: CellType = block: {
            if (frame_start_selection.end.player_id == player_id and frame_start_selection.end.index == index) {
                break :block .active;
            } else if (frame_start_selection.isCellInside(player_id, index)) {
                break :block .selected;
            } else {
                break :block .normal;
            }
        };

        var cell_color = switch (cell_type) {
            .normal => if (frame_maybe) |frame| block: {
                break :block switch (frame.getPlayerById(player_id).can_interact orelse true) {
                    true => imgui.igGetStyle().*.Colors[imgui.ImGuiCol_TableRowBg],
                    false => imgui.igGetStyle().*.Colors[imgui.ImGuiCol_TableRowBgAlt],
                };
            } else imgui.igGetStyle().*.Colors[imgui.ImGuiCol_TableRowBg],
            .selected => imgui.igGetStyle().*.Colors[imgui.ImGuiCol_HeaderHovered],
            .active => imgui.igGetStyle().*.Colors[imgui.ImGuiCol_HeaderActive],
        };
        if (!imgui.igIsWindowFocused(imgui.ImGuiFocusedFlags_ChildWindows)) {
            cell_color.w *= 0.75;
        }
        imgui.igTableSetBgColor(imgui.ImGuiTableBgTarget_CellBg, imgui.igGetColorU32_Vec4(cell_color), -1);

        switch (self.state) {
            .editing => |*editing| switch (cell_type) {
                .normal => drawInputCellText(player_id, index, tai, frame_maybe),
                .selected => imgui.igText("%s", &editing.text_buffer),
                .active => self.drawInputCellEditWidget(editing, tai.sequence.items.len),
            },
            else => drawInputCellText(player_id, index, tai, frame_maybe),
        }
    }

    fn drawInputCellText(
        player_id: model.PlayerId,
        index: usize,
        tai: *const core.ToolAssistedInput,
        frame_maybe: ?*const model.Frame,
    ) void {
        const added_color = imgui.ImVec4{ .x = 0.5, .y = 1, .z = 0.5, .w = 1 };
        const removed_color = imgui.ImVec4{ .x = 1, .y = 0.5, .z = 0.5, .w = 0.3 };
        if (index >= tai.sequence.items.len) {
            if (frame_maybe != null) {
                imgui.igTextColored(removed_color, "...");
            }
            return;
        }
        const table_input = switch (player_id) {
            .player_1 => tai.sequence.items[index].player_1,
            .player_2 => tai.sequence.items[index].player_2,
        };
        var table_buffer: [32]u8 = undefined;
        const table_text = block: {
            const text = std.fmt.bufPrintSentinel(&table_buffer, "{f}", .{table_input}, 0) catch "error";
            break :block if (text.len > 0) text else "---";
        };
        if (frame_maybe) |frame| {
            const recording_input: model.Input = frame.getPlayerById(player_id).input orelse .{};
            if (table_input.equalsIgnoringLeftRight(recording_input)) {
                imgui.igText("%s", table_text.ptr);
            } else {
                var recording_buffer: [32]u8 = undefined;
                const recording_text = block: {
                    const text = std.fmt.bufPrintSentinel(&recording_buffer, "{f}", .{recording_input}, 0) catch "error";
                    break :block if (text.len > 0) text else "---";
                };
                imgui.igTextColored(added_color, "%s", table_text.ptr);
                imgui.igSameLine(0, -1);
                imgui.igTextColored(removed_color, "%s", recording_text.ptr);
            }
        } else {
            imgui.igTextColored(added_color, "%s", table_text.ptr);
        }
    }

    fn drawInputCellEditWidget(self: *Self, editing: *State.Editing, sequence_len: usize) void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);
        const Callbacks = struct {
            fn selectAll(data: [*c]imgui.ImGuiInputTextCallbackData) callconv(.c) c_int {
                data[0].CursorPos = data[0].BufTextLen;
                data[0].SelectionStart = 0;
                data[0].SelectionEnd = data[0].BufTextLen;
                return 0;
            }
            fn selectNone(data: [*c]imgui.ImGuiInputTextCallbackData) callconv(.c) c_int {
                data[0].CursorPos = data[0].BufTextLen;
                data[0].SelectionStart = data[0].BufTextLen;
                data[0].SelectionEnd = data[0].BufTextLen;
                return 0;
            }
        };
        if (!editing.input_activated) {
            imgui.igSetKeyboardFocusHere(0);
        }
        imgui.igSetNextItemWidth(-1);

        const callback: imgui.ImGuiInputTextCallback = switch (editing.input_activated) {
            true => null,
            false => switch (editing.select_all) {
                true => Callbacks.selectAll,
                false => Callbacks.selectNone,
            },
        };
        const flags = if (callback != null) imgui.ImGuiInputTextFlags_CallbackAlways else 0;
        _ = imgui.igInputText("##input", &editing.text_buffer, editing.text_buffer.len, flags, callback, null);
        if (imgui.igIsItemActivated()) {
            editing.input_activated = true;
        }
        if (editing.input_activated and !imgui.igIsItemActive()) {
            const selection = &self.editor.selection;
            if (selection.start.index == sequence_len and selection.end.index == sequence_len) {
                self.editor.insertRows() catch |err| {
                    sdk.misc.error_context.append("Failed to insert a row.", .{});
                    sdk.misc.error_context.logError(err);
                };
            }
            const text = std.mem.sliceTo(&editing.text_buffer, 0);
            const input = model.Input.parse(text);
            self.editor.setValues(input, sequence_len) catch |err| {
                sdk.misc.error_context.append("Failed to set table values.", .{});
                sdk.misc.error_context.logError(err);
            };
            self.state = .idle;
        }
    }

    fn drawAnimationFrameCellContent(player_id: model.PlayerId, frame: *const model.Frame) void {
        const player: *const model.Player = frame.getPlayerById(player_id);

        if (player.move_phase) |move_phase| {
            const color: imgui.ImVec4 = switch (move_phase) {
                .neutral => .{ .x = 0.1, .y = 0.2, .z = 0.1, .w = 1 },
                .start_up => .{ .x = 0.2, .y = 0.1, .z = 0.1, .w = 1 },
                .active => .{ .x = 0.2, .y = 0.2, .z = 0, .w = 1 },
                .active_recovery, .recovery => .{ .x = 0.1, .y = 0.2, .z = 0.2, .w = 1 },
            };
            const color_u32 = imgui.igGetColorU32_Vec4(color);
            imgui.igTableSetBgColor(imgui.ImGuiTableBgTarget_CellBg, color_u32, -1);
        }

        if (player.animation_frame) |animation_frame| {
            var buffer: [16]u8 = undefined;
            const text = std.fmt.bufPrintSentinel(&buffer, "{}", .{animation_frame}, 0) catch "error";
            var text_size: imgui.ImVec2 = undefined;
            imgui.igCalcTextSize(&text_size, text, null, false, -1);
            var available_size: imgui.ImVec2 = undefined;
            imgui.igGetContentRegionAvail(&available_size);
            const offset = @max(0, 0.5 * (available_size.x - text_size.x));
            imgui.igSetCursorPosX(imgui.igGetCursorPosX() + offset);
            imgui.igText("%s", text.ptr);
        }

        const cell_hovered = imgui.igTableGetHoveredColumn() == imgui.igTableGetColumnIndex() and
            imgui.igTableGetHoveredRow() == imgui.igTableGetRowIndex();
        if (cell_hovered and imgui.igBeginTooltip()) {
            defer imgui.igEndTooltip();
            if (player.animation_id) |animation_id| {
                var buffer: [16]u8 = undefined;
                const text = std.fmt.bufPrintSentinel(&buffer, "{}", .{animation_id}, 0) catch "error";
                imgui.igText("Animation ID:");
                imgui.igSameLine(0, -1);
                imgui.igText("%s", text.ptr);
            }
            if (player.animation_frame) |animation_frame| {
                var buffer: [16]u8 = undefined;
                const text = std.fmt.bufPrintSentinel(&buffer, "{}", .{animation_frame}, 0) catch "error";
                imgui.igText("Animation Frame:");
                imgui.igSameLine(0, -1);
                imgui.igText("%s", text.ptr);
            }
            if (player.move_phase) |move_phase| {
                const text, const color: imgui.ImVec4 = switch (move_phase) {
                    .neutral => .{ "Neutral", .{ .x = 0.5, .y = 1, .z = 0.5, .w = 1 } },
                    .start_up => .{ "Start Up", .{ .x = 1, .y = 0.5, .z = 0.5, .w = 1 } },
                    .active => .{ "Active", .{ .x = 1, .y = 1, .z = 0, .w = 1 } },
                    .active_recovery => .{ "Active Recovery", .{ .x = 0.5, .y = 1, .z = 1, .w = 1 } },
                    .recovery => .{ "Recovery", .{ .x = 0.5, .y = 1, .z = 1, .w = 1 } },
                };
                imgui.igText("Move Phase:");
                imgui.igSameLine(0, -1);
                imgui.igTextColored(color, "%s", text.ptr);
            }
            if (player.can_interact) |can_interact| {
                const text, const color: imgui.ImVec4 = switch (can_interact) {
                    true => .{ "Yes", .{ .x = 1, .y = 1, .z = 1, .w = 1 } },
                    false => .{ "No", .{ .x = 0.6, .y = 0.6, .z = 0.6, .w = 1 } },
                };
                imgui.igText("Can Interact:");
                imgui.igSameLine(0, -1);
                imgui.igTextColored(color, "%s", text.ptr);
            }
        }
    }

    fn handleMouseSelect(
        self: *Self,
        clipper: *const imgui.ImGuiListClipper,
        dimensions: *const Dimensions,
        sequence_len: usize,
    ) void {
        switch (self.state) {
            .idle => {
                if (!imgui.igIsMouseClicked_Bool(imgui.ImGuiMouseButton_Left, false)) {
                    return;
                }
                const cell = getHoveredCell() orelse return;
                const mods = imgui.igGetIO_Nil().*.KeyMods;
                if (mods == 0) {
                    self.state = .selecting;
                    self.editor.selection = .{ .start = cell, .end = cell };
                } else if (mods == imgui.ImGuiMod_Shift) {
                    self.state = .selecting;
                    self.editor.selection.end = cell;
                } else if (mods == imgui.ImGuiMod_Alt and self.editor.selection.isCellInside(cell.player_id, cell.index)) {
                    self.state = .{ .moving = .{ .handle_index = cell.index } };
                }
            },
            .selecting => {
                if (!imgui.igIsMouseDown_Nil(imgui.ImGuiMouseButton_Left)) {
                    self.state = .idle;
                    return;
                }
                var mouse_pos: imgui.ImVec2 = undefined;
                imgui.igGetMousePos(&mouse_pos);
                const player_id: model.PlayerId = switch (mouse_pos.x < dimensions.player_divide_screen_x) {
                    true => .player_1,
                    false => .player_2,
                };
                const float_index = std.math.clamp(
                    (mouse_pos.y - clipper.StartPosY) / clipper.ItemsHeight,
                    0,
                    @as(f32, @floatFromInt(std.math.maxInt(usize))),
                );
                var index: usize = @intFromFloat(float_index);
                if (index > sequence_len) {
                    index = sequence_len;
                }
                self.editor.selection.end = .{ .player_id = player_id, .index = index };
            },
            else => {},
        }
    }

    fn handleKeyboardSelect(self: *Self, sequence_len: usize) void {
        if (self.state != .idle) {
            return;
        }

        const flags = table_route | imgui.ImGuiInputFlags_Repeat;
        const shift = imgui.ImGuiMod_Shift;
        const enter_pressed = imgui.igShortcut_Nil(imgui.ImGuiKey_Enter, flags);
        const shift_enter_pressed = imgui.igShortcut_Nil(shift | imgui.ImGuiKey_Enter, flags);
        const up_pressed_no_shift = imgui.igShortcut_Nil(imgui.ImGuiKey_UpArrow, flags);
        const down_pressed_no_shift = imgui.igShortcut_Nil(imgui.ImGuiKey_DownArrow, flags);
        const left_pressed_no_shift = imgui.igShortcut_Nil(imgui.ImGuiKey_LeftArrow, flags);
        const right_pressed_no_shift = imgui.igShortcut_Nil(imgui.ImGuiKey_RightArrow, flags);
        const up_pressed_shift = imgui.igShortcut_Nil(shift | imgui.ImGuiKey_UpArrow, flags);
        const down_pressed_shift = imgui.igShortcut_Nil(shift | imgui.ImGuiKey_DownArrow, flags);
        const left_pressed_shift = imgui.igShortcut_Nil(shift | imgui.ImGuiKey_LeftArrow, flags);
        const right_pressed_shift = imgui.igShortcut_Nil(shift | imgui.ImGuiKey_RightArrow, flags);

        const selection = &self.editor.selection;
        var next_cell = self.editor.selection.end;
        if (enter_pressed) {
            if (selection.start.index == sequence_len and selection.end.index == sequence_len) {
                self.editor.insertRows() catch |err| {
                    sdk.misc.error_context.append("Failed to insert row.", .{});
                    sdk.misc.error_context.logError(err);
                };
                next_cell.index += 1;
                selection.* = .{ .start = next_cell, .end = next_cell };
                return;
            }
            if (next_cell.index < sequence_len) {
                next_cell.index += 1;
            }
            selection.* = .{ .start = next_cell, .end = next_cell };
            return;
        }
        if (shift_enter_pressed) {
            if (next_cell.index > 0) {
                next_cell.index -= 1;
            }
            selection.* = .{ .start = next_cell, .end = next_cell };
            return;
        }

        const up_pressed = up_pressed_no_shift or up_pressed_shift;
        const down_pressed = down_pressed_no_shift or down_pressed_shift;
        const left_pressed = left_pressed_no_shift or left_pressed_shift;
        const right_pressed = right_pressed_no_shift or right_pressed_shift;
        const shift_pressed = up_pressed_shift or down_pressed_shift or left_pressed_shift or right_pressed_shift;
        var detected_press = false;
        if (up_pressed and !down_pressed) {
            detected_press = true;
            if (next_cell.index > 0) {
                next_cell.index -= 1;
            }
        }
        if (down_pressed and !up_pressed) {
            detected_press = true;
            if (next_cell.index < sequence_len) {
                next_cell.index += 1;
            }
        }
        if (left_pressed and !right_pressed) {
            detected_press = true;
            next_cell.player_id = .player_1;
        }
        if (right_pressed and !left_pressed) {
            detected_press = true;
            next_cell.player_id = .player_2;
        }
        if (detected_press) {
            if (shift_pressed) {
                selection.end = next_cell;
            } else {
                selection.* = .{ .start = next_cell, .end = next_cell };
            }
        }
    }

    fn handleMouseEdit(self: *Self, tai: *const core.ToolAssistedInput) void {
        if (self.state != .idle) {
            return;
        }
        if (!imgui.igIsMouseDoubleClicked_Nil(imgui.ImGuiMouseButton_Left)) {
            return;
        }
        if (imgui.igGetIO_Nil().*.KeyMods != 0) {
            return;
        }
        const cell = &self.editor.selection.end;
        if (!std.meta.eql(getHoveredCell(), cell.*)) {
            return;
        }
        if (cell.index >= tai.sequence.items.len) {
            self.state = .{ .editing = .{ .text_buffer = State.Editing.empty_buffer, .select_all = true } };
            return;
        }
        const item = &tai.sequence.items[cell.index];
        const input = switch (cell.player_id) {
            .player_1 => item.player_1,
            .player_2 => item.player_2,
        };
        var buffer: [State.Editing.buffer_size]u8 = undefined;
        _ = std.fmt.bufPrintSentinel(&buffer, "{f}", .{input}, 0) catch |err| {
            sdk.misc.error_context.append("Failed to convert input to text.", .{});
            sdk.misc.error_context.logError(err);
            return;
        };
        self.state = .{ .editing = .{ .text_buffer = buffer, .select_all = true } };
    }

    fn handleSelectAllShortcut(self: *Self, sequence_len: usize) void {
        if (self.state != .idle) {
            return;
        }
        if (!imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_A, table_route)) {
            return;
        }
        self.editor.selection = .{
            .start = .{ .index = 0, .player_id = .player_1 },
            .end = .{ .index = sequence_len, .player_id = .player_2 },
        };
    }

    fn handleClearValuesShortcut(self: *Self, sequence_len: usize) void {
        if (self.state != .idle) {
            return;
        }
        const backspace_pressed = imgui.igShortcut_Nil(
            imgui.ImGuiKey_Backspace,
            table_route | imgui.ImGuiInputFlags_Repeat,
        );
        const shift_backspace_pressed = imgui.igShortcut_Nil(
            imgui.ImGuiMod_Shift | imgui.ImGuiKey_Backspace,
            table_route | imgui.ImGuiInputFlags_Repeat,
        );
        const Direction = enum { up, down };
        const direction: Direction = if (backspace_pressed) .down else if (shift_backspace_pressed) .up else return;
        const selection = &self.editor.selection;
        if (selection.start.index == sequence_len and selection.end.index == sequence_len) {
            return;
        }
        self.editor.setValues(.{}, sequence_len) catch |err| {
            sdk.misc.error_context.append("Failed to set table values.", .{});
            sdk.misc.error_context.logError(err);
            return;
        };
        var next_cell = self.editor.selection.end;
        if (direction == .up and next_cell.index > 0) {
            next_cell.index -= 1;
        }
        if (direction == .down and next_cell.index < sequence_len) {
            next_cell.index += 1;
        }
        selection.* = .{ .start = next_cell, .end = next_cell };
    }

    fn handleEditShortcut(self: *Self, tai: *const core.ToolAssistedInput) void {
        imgui.igSetNextFrameWantCaptureKeyboard(true);
        switch (self.state) {
            .idle => switch (imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_E, table_route)) {
                true => {
                    const cell = &self.editor.selection.end;
                    if (cell.index >= tai.sequence.items.len) {
                        self.state = .{ .editing = .{ .text_buffer = State.Editing.empty_buffer, .select_all = true } };
                        return;
                    }
                    const item = &tai.sequence.items[cell.index];
                    const input = switch (cell.player_id) {
                        .player_1 => item.player_1,
                        .player_2 => item.player_2,
                    };
                    var buffer: [State.Editing.buffer_size]u8 = undefined;
                    _ = std.fmt.bufPrintSentinel(&buffer, "{f}", .{input}, 0) catch |err| {
                        sdk.misc.error_context.append("Failed to convert input to text.", .{});
                        sdk.misc.error_context.logError(err);
                        return;
                    };
                    self.state = .{ .editing = .{ .text_buffer = buffer, .select_all = true } };
                },
                false => {
                    if (imgui.igGetIO_Nil().*.KeyMods != 0) {
                        return;
                    }
                    const queue = &imgui.igGetIO_Nil().*.InputQueueCharacters;
                    if (queue.*.Size <= 0) {
                        return;
                    }
                    const codepoints = queue.*.Data[0..@intCast(queue.*.Size)];
                    var buffer: [State.Editing.buffer_size]u8 = undefined;
                    var len: usize = 0;
                    for (codepoints) |codepoint| {
                        const u21_codepoint = std.math.cast(u21, codepoint) orelse {
                            sdk.misc.error_context.new("Failed to UTF8 encode: 0x{X}", .{codepoint});
                            sdk.misc.error_context.logError(error.CastFailed);
                            continue;
                        };
                        if (u21_codepoint < 256 and !std.ascii.isPrint(@intCast(u21_codepoint))) {
                            continue;
                        }
                        const size = std.unicode.utf8Encode(u21_codepoint, buffer[len..(buffer.len - 1)]) catch |err| {
                            sdk.misc.error_context.new("Failed to UTF8 encode: 0x{X}", .{u21_codepoint});
                            sdk.misc.error_context.logError(err);
                            continue;
                        };
                        len += size;
                    }
                    if (len == 0) {
                        return;
                    }
                    buffer[len] = 0;
                    self.state = .{ .editing = .{ .text_buffer = buffer, .select_all = false } };
                },
            },
            .editing => |*editing| {
                if (editing.input_activated) {
                    return;
                }
                const queue = &imgui.igGetIO_Nil().*.InputQueueCharacters;
                if (queue.*.Size <= 0) {
                    return;
                }
                const buffer = &editing.text_buffer;
                var len = std.mem.sliceTo(buffer, 0).len;
                const codepoints = queue.*.Data[0..@intCast(queue.*.Size)];
                for (codepoints) |codepoint| {
                    const u21_codepoint = std.math.cast(u21, codepoint) orelse {
                        sdk.misc.error_context.new("Failed to UTF8 encode: 0x{X}", .{codepoint});
                        sdk.misc.error_context.logError(error.CastFailed);
                        continue;
                    };
                    if (u21_codepoint < 256 and !std.ascii.isPrint(@intCast(u21_codepoint))) {
                        continue;
                    }
                    const size = std.unicode.utf8Encode(u21_codepoint, buffer[len..(buffer.len - 1)]) catch |err| {
                        sdk.misc.error_context.new("Failed to UTF8 encode: 0x{X}", .{u21_codepoint});
                        sdk.misc.error_context.logError(err);
                        continue;
                    };
                    len += size;
                }
                buffer[len] = 0;
            },
            else => {},
        }
    }

    fn handleConfirmEditShortcut(self: *Self, sequence_len: usize) void {
        const editing = switch (self.state) {
            .editing => |*editing| editing,
            else => return,
        };
        const Direction = enum { up, down };
        const direction: Direction = block: {
            const up_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_UpArrow, false);
            const down_pressed = imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_DownArrow, false);
            if (up_pressed and !down_pressed) {
                break :block .up;
            }
            if (down_pressed and !up_pressed) {
                break :block .down;
            }
            if (imgui.igIsKeyPressed_Bool(imgui.ImGuiKey_Enter, false)) {
                break :block switch (imgui.igGetIO_Nil().*.KeyMods) {
                    0 => .down,
                    imgui.ImGuiMod_Shift => .up,
                    else => return,
                };
            }
            return;
        };
        const selection = &self.editor.selection;
        var set_values_sequence_len = sequence_len;
        if (selection.start.index == sequence_len and selection.end.index == sequence_len) {
            self.editor.insertRows() catch |err| {
                sdk.misc.error_context.append("Failed to insert row.", .{});
                sdk.misc.error_context.logError(err);
                return;
            };
            set_values_sequence_len += 1;
        }
        const text = std.mem.sliceTo(&editing.text_buffer, 0);
        const input = model.Input.parse(text);
        self.editor.setValues(input, set_values_sequence_len) catch |err| {
            sdk.misc.error_context.append("Failed to set table values.", .{});
            sdk.misc.error_context.logError(err);
            return;
        };
        self.state = .idle;
        var next_cell = self.editor.selection.end;
        if (direction == .up and next_cell.index > 0) {
            next_cell.index -= 1;
        }
        if (direction == .down and next_cell.index <= sequence_len) {
            next_cell.index += 1;
        }
        selection.* = .{ .start = next_cell, .end = next_cell };
    }

    fn drawEnabledCheckbox(enabled: *bool, player_id: model.PlayerId) void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        _ = imgui.igCheckbox("##enabled", enabled);

        const cell_hovered = imgui.igTableGetHoveredColumn() == imgui.igTableGetColumnIndex() and
            imgui.igTableGetHoveredRow() == imgui.igTableGetRowIndex();
        const check_hovered = imgui.igIsItemHovered(0);
        if (cell_hovered and !check_hovered and imgui.igIsMouseClicked_Bool(imgui.ImGuiMouseButton_Left, false)) {
            enabled.* = !enabled.*;
        }
        if (cell_hovered or check_hovered) {
            const tooltip = switch (enabled.*) {
                false => switch (player_id) {
                    .player_1 => "Enable player 1 input simulation. [Ctrl + 1]",
                    .player_2 => "Enable player 2 input simulation. [Ctrl + 2]",
                },
                true => switch (player_id) {
                    .player_1 => "Disable player 1 input simulation. [Ctrl + 1]",
                    .player_2 => "Disable player 2 input simulation. [Ctrl + 2]",
                },
            };
            imgui.igSetTooltip(tooltip);
        }
    }

    fn handleEnabledShortcut(enabled: *bool, player_id: model.PlayerId) void {
        const key_chord = switch (player_id) {
            .player_1 => imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_1,
            .player_2 => imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_2,
        };
        if (!imgui.igShortcut_Nil(key_chord, window_route)) {
            return;
        }
        enabled.* = !enabled.*;
    }

    fn isCancelDisabled(self: *const Self) bool {
        return switch (self.state) {
            .idle, .selecting => true,
            .moving, .editing, .confirming => false,
        };
    }

    fn drawCancelButton(self: *Self) void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        imgui.igBeginDisabled(self.isCancelDisabled());
        defer imgui.igEndDisabled();

        _ = imgui.igButton(" ❌ ###cancel", .{});
        if (imgui.igIsItemHovered(imgui.ImGuiHoveredFlags_AllowWhenBlockedByActiveItem)) {
            const mouse_pressed = imgui.igIsMouseClicked_Bool(imgui.ImGuiMouseButton_Left, false);
            const mouse_released = imgui.igIsMouseReleased_Nil(imgui.ImGuiMouseButton_Left);
            if (mouse_pressed or mouse_released) {
                self.state = .idle;
            }
            imgui.igSetTooltip("Cancel [Esc]");
        }
    }

    fn handleCancelShortcut(self: *Self) void {
        if (self.isCancelDisabled()) {
            return;
        }
        const flags = imgui.ImGuiInputFlags_RouteGlobal | imgui.ImGuiInputFlags_RouteOverActive;
        if (!imgui.igShortcut_Nil(imgui.ImGuiKey_Escape, flags)) {
            return;
        }
        self.state = .idle;
    }

    fn isUndoDisabled(self: *const Self) bool {
        return !self.editor.canUndo();
    }

    fn drawUndoButton(self: *Self, tai: *core.ToolAssistedInput) void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        imgui.igBeginDisabled(self.isUndoDisabled());
        defer imgui.igEndDisabled();

        if (imgui.igButton(" ↶ ###undo", .{})) {
            self.editor.undo(tai) catch |err| {
                sdk.misc.error_context.append("Failed to undo.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Undo [Ctrl + Z]");
        }
    }

    fn handleUndoShortcut(self: *Self, tai: *core.ToolAssistedInput) void {
        if (self.state != .idle) {
            return;
        }
        if (self.isUndoDisabled()) {
            return;
        }
        if (!imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_Z, window_route | imgui.ImGuiInputFlags_Repeat)) {
            return;
        }
        self.editor.undo(tai) catch |err| {
            sdk.misc.error_context.append("Failed to undo.", .{});
            sdk.misc.error_context.logError(err);
        };
    }

    fn isRedoDisabled(self: *const Self) bool {
        return !self.editor.canRedo();
    }

    fn drawRedoButton(self: *Self, tai: *core.ToolAssistedInput) void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        imgui.igBeginDisabled(self.isRedoDisabled());
        defer imgui.igEndDisabled();

        if (imgui.igButton(" ↷ ###redo", .{})) {
            self.editor.redo(tai) catch |err| {
                sdk.misc.error_context.append("Failed to redo.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
        if (imgui.igIsItemHovered(0)) {
            imgui.igSetTooltip("Redo [Ctrl + Y]");
        }
    }

    fn handleRedoShortcut(self: *Self, tai: *core.ToolAssistedInput) void {
        if (self.state != .idle) {
            return;
        }
        if (self.isRedoDisabled()) {
            return;
        }
        if (!imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_Y, window_route | imgui.ImGuiInputFlags_Repeat)) {
            return;
        }
        self.editor.redo(tai) catch |err| {
            sdk.misc.error_context.append("Failed to redo.", .{});
            sdk.misc.error_context.logError(err);
        };
    }

    fn isImportDisabled(controller: *const core.Controller) bool {
        return controller.getTotalFrames() == 0;
    }

    fn drawImportButton(self: *Self, tai: *core.ToolAssistedInput, controller: *const core.Controller) void {
        const is_confirm_open = self.state == .confirming and self.state.confirming == .import;
        var next_confirm_open = is_confirm_open;

        {
            imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
            defer imgui.igPopStyleVar(1);

            imgui.igBeginDisabled(isImportDisabled(controller));
            defer imgui.igEndDisabled();

            if (imgui.igButton(" → ###import", .{})) {
                if (tai.sequence.items.len == 0) {
                    self.editor.importFromRecording(tai, controller) catch |err| {
                        sdk.misc.error_context.append("Failed to import tool assisted inputs from recording.", .{});
                        sdk.misc.error_context.logError(err);
                    };
                } else {
                    next_confirm_open = true;
                }
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Import Recorded Inputs [Ctrl + I]");
            }
        }

        const action = ui.drawConfirmDialog(
            &next_confirm_open,
            "Import inputs from the recording?",
            \\Are you sure you want to import inputs from the recording?
            \\This will override all existing input values and can not be undone.
        ,
            "Import",
            "Cancel",
        );
        if (action == .confirm) {
            self.editor.importFromRecording(tai, controller) catch |err| {
                sdk.misc.error_context.append("Failed to import tool assisted inputs from recording.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
        if (is_confirm_open != next_confirm_open) {
            switch (next_confirm_open) {
                false => self.state = .idle,
                true => self.state = .{ .confirming = .import },
            }
        }
    }

    fn handleImportShortcut(self: *Self, tai: *core.ToolAssistedInput, controller: *const core.Controller) void {
        if (self.state != .idle) {
            return;
        }
        if (isImportDisabled(controller)) {
            return;
        }
        if (!imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_I, window_route)) {
            return;
        }
        if (tai.sequence.items.len == 0) {
            self.editor.importFromRecording(tai, controller) catch |err| {
                sdk.misc.error_context.append("Failed to import tool assisted inputs from recording.", .{});
                sdk.misc.error_context.logError(err);
            };
        } else {
            self.state = .{ .confirming = .import };
        }
    }

    fn isClearDisabled(tai: *const core.ToolAssistedInput) bool {
        return tai.sequence.items.len == 0;
    }

    fn drawClearButton(self: *Self, tai: *core.ToolAssistedInput) void {
        const is_confirm_open = self.state == .confirming and self.state.confirming == .clear;
        var next_confirm_open = is_confirm_open;

        {
            imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
            defer imgui.igPopStyleVar(1);

            imgui.igBeginDisabled(isClearDisabled(tai));
            defer imgui.igEndDisabled();

            if (imgui.igButton(" 🗑 ###clear", .{})) {
                next_confirm_open = true;
            }
            if (imgui.igIsItemHovered(0)) {
                imgui.igSetTooltip("Clear Table [Ctrl + Del]");
            }
        }

        const action = ui.drawConfirmDialog(
            &next_confirm_open,
            "Clear all inputs from the table?",
            \\Are you sure you want to clear all inputs from the table?
            \\This will delete all table rows and can not be undone.
        ,
            "Clear",
            "Cancel",
        );
        if (action == .confirm) {
            self.editor.clear(tai);
        }
        if (is_confirm_open != next_confirm_open) {
            switch (next_confirm_open) {
                false => self.state = .idle,
                true => self.state = .{ .confirming = .clear },
            }
        }
    }

    fn handleClearShortcut(self: *Self, tai: *const core.ToolAssistedInput) void {
        if (self.state != .idle) {
            return;
        }
        if (isClearDisabled(tai)) {
            return;
        }
        if (!imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_Delete, window_route)) {
            return;
        }
        self.state = .{ .confirming = .clear };
    }

    fn drawMoveButton(self: *Self, index: usize, sequence_len: usize) void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        const is_being_moved = self.state == .moving and self.state.moving.handle_index == index;
        if (is_being_moved) {
            const active_color = imgui.igGetStyleColorVec4(imgui.ImGuiCol_ButtonActive).*;
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, active_color);
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, active_color);
        }
        defer if (is_being_moved) {
            imgui.igPopStyleColor(2);
        };

        const selection = &self.editor.selection;
        _ = imgui.igButton(" ⋯ ###move", .{});
        if (imgui.igIsItemActivated()) {
            if (!selection.isIndexInside(index)) {
                selection.* = .{
                    .start = .{ .index = index, .player_id = .player_1 },
                    .end = .{ .index = index, .player_id = .player_2 },
                };
            }
            selection.* = selection.clampIndices(sequence_len);
            self.state = .{ .moving = .{ .handle_index = index } };
        }
        if (imgui.igIsItemHovered(0)) {
            const Things = union(enum) {
                row: void,
                selected_row: void,
                selected_rows: usize,
                selected_value: void,
                selected_values: usize,
            };
            const things: Things = switch (selection.isIndexInside(index)) {
                true => switch (selection.start.player_id == selection.end.player_id) {
                    true => switch (selection.clampIndices(sequence_len).getNumberOfRows()) {
                        1 => .selected_value,
                        else => |n| .{ .selected_values = n },
                    },
                    false => switch (selection.clampIndices(sequence_len).getNumberOfRows()) {
                        1 => .selected_row,
                        else => |n| .{ .selected_rows = n },
                    },
                },
                false => .row,
            };
            var buffer: [128]u8 = undefined;
            const text = switch (things) {
                .row => "Move Row",
                .selected_row => "Move Selected Row [Alt + Up/Down] [Alt + Left Click Drag]",
                .selected_rows => |n| std.fmt.bufPrintSentinel(
                    &buffer,
                    "Move {} Selected Rows [Alt + Up/Down] [Alt + Left Click Drag]",
                    .{n},
                    0,
                ) catch "error",
                .selected_value => "Move Selected Value [Alt + Up/Down] [Alt + Left Click Drag]",
                .selected_values => |n| std.fmt.bufPrintSentinel(
                    &buffer,
                    "Move {} Selected Values [Alt + Up/Down] [Alt + Left Click Drag]",
                    .{n},
                    0,
                ) catch "error",
            };
            imgui.igSetTooltip("%s", text.ptr);
        }
    }

    fn handleMouseMove(self: *Self, clipper: *const imgui.ImGuiListClipper, sequence_len: usize) void {
        if (self.state != .moving or imgui.igIsMouseDown_Nil(imgui.ImGuiMouseButton_Left)) {
            return;
        }
        defer self.state = .idle;
        const selection = &self.editor.selection;
        const source_min_index = selection.getMinIndex();
        const destination_min_index = self.findSimulatedMoveIndex(
            source_min_index,
            .source_to_destination,
            clipper,
            sequence_len,
        );
        if (source_min_index == destination_min_index) {
            return;
        }
        self.editor.move(destination_min_index, sequence_len) catch |err| {
            sdk.misc.error_context.append("Failed move inputs.", .{});
            sdk.misc.error_context.logError(err);
        };
    }

    fn findSimulatedMoveIndex(
        self: *const Self,
        index: usize,
        direction: enum { source_to_destination, destination_to_source },
        clipper: *const imgui.ImGuiListClipper,
        sequence_len: usize,
    ) usize {
        if (sequence_len == 0) {
            return index;
        }
        const source_handle_index = switch (self.state) {
            .moving => |*moving| moving.handle_index,
            else => return index,
        };

        var mouse_pos: imgui.ImVec2 = undefined;
        imgui.igGetMousePos(&mouse_pos);
        const float_handle_index = std.math.clamp(
            (mouse_pos.y - clipper.StartPosY) / clipper.ItemsHeight,
            0,
            @as(f32, @floatFromInt(std.math.maxInt(usize))),
        );
        const destination_handle_index: usize = @intFromFloat(float_handle_index);

        if (destination_handle_index == source_handle_index) {
            return index;
        }

        const selection = &self.editor.selection;
        var source_min_index = selection.getMinIndex();
        var source_max_index = selection.getMaxIndex();
        const number_of_rows = selection.getNumberOfRows();
        var destination_min_index = source_min_index + destination_handle_index -| source_handle_index;
        var destination_max_index = destination_min_index + number_of_rows - 1;
        if (destination_max_index + 1 > sequence_len) {
            destination_min_index = sequence_len -| number_of_rows;
            destination_max_index = destination_min_index + number_of_rows - 1;
        }

        switch (direction) {
            .source_to_destination => {},
            .destination_to_source => {
                std.mem.swap(usize, &source_min_index, &destination_min_index);
                std.mem.swap(usize, &source_max_index, &destination_max_index);
            },
        }

        if (index >= source_min_index and index <= source_max_index) {
            return index + destination_min_index - source_min_index;
        }
        if (source_min_index < destination_min_index) {
            if (index > source_max_index and index <= destination_max_index) {
                return index - number_of_rows;
            }
        } else {
            if (index >= destination_min_index and index < source_min_index) {
                return index + number_of_rows;
            }
        }
        return index;
    }

    fn handleMoveShortcut(self: *Self, sequence_len: usize) void {
        if (self.state != .idle) {
            return;
        }
        const up_pressed = imgui.igShortcut_Nil(
            imgui.ImGuiMod_Alt | imgui.ImGuiKey_UpArrow,
            table_route | imgui.ImGuiInputFlags_Repeat,
        );
        const down_pressed = imgui.igShortcut_Nil(
            imgui.ImGuiMod_Alt | imgui.ImGuiKey_DownArrow,
            table_route | imgui.ImGuiInputFlags_Repeat,
        );
        const selection = &self.editor.selection;
        const min_index = selection.getMinIndex();
        const max_index = selection.getMaxIndex();
        if (up_pressed and !down_pressed and min_index > 0) {
            self.editor.move(min_index - 1, sequence_len) catch |err| {
                sdk.misc.error_context.append("Failed move inputs.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
        if (down_pressed and !up_pressed and max_index + 1 < sequence_len) {
            self.editor.move(min_index + 1, sequence_len) catch |err| {
                sdk.misc.error_context.append("Failed move inputs.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
    }

    fn drawSwapButton(self: *Self, index_maybe: ?usize, sequence_len: usize) void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        imgui.igBeginDisabled(sequence_len == 0);
        defer imgui.igEndDisabled();

        const selection = &self.editor.selection;
        if (imgui.igButton(" ⇄ ###swap", .{})) {
            if (index_maybe) |index| {
                if (!selection.isIndexInside(index)) {
                    selection.* = .{
                        .start = .{ .index = index, .player_id = .player_1 },
                        .end = .{ .index = index, .player_id = .player_2 },
                    };
                }
            } else {
                selection.* = .{
                    .start = .{ .index = 0, .player_id = .player_1 },
                    .end = .{ .index = sequence_len - 1, .player_id = .player_2 },
                };
            }
            self.editor.swapSides(sequence_len) catch |err| {
                sdk.misc.error_context.append("Failed to swap input sides.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
        if (imgui.igIsItemHovered(0)) {
            const Things = union(enum) {
                all_rows: void,
                row: void,
                selected_row: void,
                selected_rows: usize,
            };
            const things: Things = if (index_maybe) |index| block: {
                break :block switch (selection.isIndexInside(index)) {
                    true => switch (selection.clampIndices(sequence_len).getNumberOfRows()) {
                        1 => .selected_row,
                        else => |n| .{ .selected_rows = n },
                    },
                    false => .row,
                };
            } else .all_rows;
            var buffer: [128]u8 = undefined;
            const text = switch (things) {
                .all_rows => "Swap Inputs Inside All Rows",
                .row => "Swap Inputs Inside Row",
                .selected_row => "Swap Inputs Inside Selected Row [Alt + Left/Right]",
                .selected_rows => |n| std.fmt.bufPrintSentinel(
                    &buffer,
                    "Swap Inputs Inside {} Selected Rows [Alt + Left/Right]",
                    .{n},
                    0,
                ) catch "error",
            };
            imgui.igSetTooltip("%s", text.ptr);
        }
    }

    fn handleSwapShortcut(self: *Self, sequence_len: usize) void {
        if (self.state != .idle) {
            return;
        }
        const left_pressed = imgui.igShortcut_Nil(imgui.ImGuiMod_Alt | imgui.ImGuiKey_LeftArrow, table_route);
        const right_pressed = imgui.igShortcut_Nil(imgui.ImGuiMod_Alt | imgui.ImGuiKey_RightArrow, table_route);
        const selection = &self.editor.selection;
        const swap = block: {
            if (selection.start.player_id == selection.end.player_id) {
                if (left_pressed and !right_pressed and selection.start.player_id == .player_2) {
                    break :block true;
                }
                if (right_pressed and !left_pressed and selection.start.player_id == .player_1) {
                    break :block true;
                }
            } else if (left_pressed != right_pressed) {
                break :block true;
            }
            break :block false;
        };
        if (swap) {
            self.editor.swapSides(sequence_len) catch |err| {
                sdk.misc.error_context.append("Failed to swap input sides.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
    }

    fn drawInsertButton(self: *Self, index: usize) void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        const selection = &self.editor.selection;
        if (imgui.igButton(" ➕ ###insert", .{})) {
            if (!selection.isIndexInside(index)) {
                self.editor.selection = .{
                    .start = .{ .index = index, .player_id = .player_1 },
                    .end = .{ .index = index, .player_id = .player_2 },
                };
            }
            self.editor.insertRows() catch |err| {
                sdk.misc.error_context.append("Failed to insert rows.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
        if (imgui.igIsItemHovered(0)) {
            const Things = union(enum) {
                row: void,
                selected_row: void,
                selected_rows: usize,
            };
            const things: Things = switch (selection.isIndexInside(index)) {
                true => switch (selection.getNumberOfRows()) {
                    1 => .selected_row,
                    else => |n| .{ .selected_rows = n },
                },
                false => .row,
            };
            var buffer: [64]u8 = undefined;
            const text = switch (things) {
                .row => "Insert Row",
                .selected_row => "Insert Row [Ins]",
                .selected_rows => |n| std.fmt.bufPrintSentinel(&buffer, "Insert {} Rows [Ins]", .{n}, 0) catch "error",
            };
            imgui.igSetTooltip("%s", text.ptr);
        }
    }

    fn handleInsertShortcut(self: *Self) void {
        if (self.state != .idle) {
            return;
        }
        if (!imgui.igShortcut_Nil(imgui.ImGuiKey_Insert, window_route | imgui.ImGuiInputFlags_Repeat)) {
            return;
        }
        self.editor.insertRows() catch |err| {
            sdk.misc.error_context.append("Failed to insert rows.", .{});
            sdk.misc.error_context.logError(err);
        };
    }

    fn drawDeleteButton(self: *Self, index: usize, sequence_len: usize) void {
        imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_FramePadding, .{});
        defer imgui.igPopStyleVar(1);

        const selection = &self.editor.selection;
        if (imgui.igButton(" ⌫ ###delete", .{})) {
            if (!selection.isIndexInside(index)) {
                selection.* = .{
                    .start = .{ .index = index, .player_id = .player_1 },
                    .end = .{ .index = index, .player_id = .player_2 },
                };
            }
            self.editor.deleteRows(sequence_len) catch |err| {
                sdk.misc.error_context.append("Failed to delete rows.", .{});
                sdk.misc.error_context.logError(err);
            };
        }
        if (imgui.igIsItemHovered(0)) {
            const Things = union(enum) {
                row: void,
                selected_row: void,
                selected_rows: usize,
            };
            const things: Things = switch (selection.isIndexInside(index)) {
                true => switch (selection.clampIndices(sequence_len).getNumberOfRows()) {
                    1 => .selected_row,
                    else => |n| .{ .selected_rows = n },
                },
                false => .row,
            };
            var buffer: [64]u8 = undefined;
            const text = switch (things) {
                .row => "Delete Row",
                .selected_row => "Delete Selected Row [Del]",
                .selected_rows => |n| std.fmt.bufPrintSentinel(
                    &buffer,
                    "Delete {} Selected Rows [Del]",
                    .{n},
                    0,
                ) catch "error",
            };
            imgui.igSetTooltip("%s", text.ptr);
        }
    }

    fn handleDeleteShortcut(self: *Self, sequence_len: usize) void {
        if (self.state != .idle) {
            return;
        }
        if (sequence_len == 0) {
            return;
        }
        if (!imgui.igShortcut_Nil(imgui.ImGuiKey_Delete, window_route | imgui.ImGuiInputFlags_Repeat)) {
            return;
        }
        self.editor.deleteRows(sequence_len) catch |err| {
            sdk.misc.error_context.append("Failed to delete rows.", .{});
            sdk.misc.error_context.logError(err);
        };
    }

    fn handleCopyShortcut(self: *Self, tai: *const core.ToolAssistedInput) void {
        if (self.state != .idle) {
            return;
        }
        if (tai.sequence.items.len == 0) {
            return;
        }
        if (!imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_C, window_route)) {
            return;
        }
        const setClipboardText = struct {
            fn call(text: [:0]const u8) void {
                imgui.igSetClipboardText(text);
            }
        }.call;
        if (self.editor.copy(setClipboardText, tai)) {
            sdk.ui.toasts.send(.info, null, "Copied selection to clipboard.", .{});
        } else |err| {
            sdk.misc.error_context.append("Failed to copy selection.", .{});
            sdk.misc.error_context.logError(err);
        }
    }

    fn handlePasteShortcut(self: *Self, sequence_len: usize) void {
        if (self.state != .idle) {
            return;
        }
        if (!imgui.igShortcut_Nil(imgui.ImGuiMod_Ctrl | imgui.ImGuiKey_V, window_route)) {
            return;
        }
        const text = imgui.igGetClipboardText();
        if (text == null) {
            return;
        }
        self.editor.paste(std.mem.sliceTo(text, 0), sequence_len) catch |err| {
            sdk.misc.error_context.append("Failed to paste into table.", .{});
            sdk.misc.error_context.logError(err);
            return;
        };
    }

    fn getHoveredCell() ?ui.TaiEditor.Selection.Cell {
        const player_id: model.PlayerId = switch (imgui.igTableGetHoveredColumn()) {
            1, 2 => .player_1,
            4, 5 => .player_2,
            else => return null,
        };
        const index = std.math.cast(usize, imgui.igTableGetHoveredRow() - 1) orelse return null;
        return .{ .player_id = player_id, .index = index };
    }
};
