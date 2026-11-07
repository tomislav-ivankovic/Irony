const std = @import("std");
const sdk = @import("../../sdk/root.zig");
const model = @import("../model/root.zig");
const core = @import("../core/root.zig");

pub const TaiEditor = struct {
    allocator: std.mem.Allocator,
    selection: Selection,
    uncommitted: std.ArrayList(Change),
    undo_stack: std.ArrayList(Change),
    redo_stack: std.ArrayList(Change),

    const Self = @This();
    pub const Selection = struct {
        start: Cell,
        end: Cell,

        pub const Cell = struct {
            player_id: model.PlayerId,
            index: usize,
        };
        pub const initial = Selection{
            .start = .{ .index = 0, .player_id = .player_1 },
            .end = .{ .index = 0, .player_id = .player_1 },
        };

        pub fn clampIndices(self: *const Selection, len: usize) Selection {
            var clamped = self.*;
            clamped.start.index = @min(clamped.start.index, len -| 1);
            clamped.end.index = @min(clamped.end.index, len -| 1);
            return clamped;
        }

        pub fn getMinPlayerId(self: *const Selection) model.PlayerId {
            if (self.start.player_id == self.end.player_id) {
                return self.start.player_id;
            } else {
                return .player_1;
            }
        }

        pub fn getMaxPlayerId(self: *const Selection) model.PlayerId {
            if (self.start.player_id == self.end.player_id) {
                return self.start.player_id;
            } else {
                return .player_2;
            }
        }

        pub fn getMinIndex(self: *const Selection) usize {
            return @min(self.start.index, self.end.index);
        }

        pub fn getMaxIndex(self: *const Selection) usize {
            return @max(self.start.index, self.end.index);
        }

        pub fn getNumberOfRows(self: *const Selection) usize {
            return self.getMaxIndex() - self.getMinIndex() + 1;
        }

        pub fn getNumberOfColumns(self: *const Selection) usize {
            return if (self.start.player_id == self.end.player_id) 1 else 2;
        }

        pub fn getNumberOfCells(self: *const Selection) usize {
            return self.getNumberOfRows() * self.getNumberOfColumns();
        }

        pub fn isPlayerIdInside(self: *const Selection, player_id: model.PlayerId) bool {
            return player_id == self.start.player_id or player_id == self.end.player_id;
        }

        pub fn isIndexInside(self: *const Selection, index: usize) bool {
            return index >= self.getMinIndex() and index <= self.getMaxIndex();
        }

        pub fn isCellInside(self: *const Selection, player_id: model.PlayerId, index: usize) bool {
            return self.isPlayerIdInside(player_id) and self.isIndexInside(index);
        }
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .selection = .initial,
            .uncommitted = .empty,
            .undo_stack = .empty,
            .redo_stack = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.redo_stack.deinit(self.allocator);
        self.undo_stack.deinit(self.allocator);
        self.uncommitted.deinit(self.allocator);
    }

    pub fn insertRows(self: *Self) !void {
        const min_index = self.selection.getMinIndex();
        const max_index = self.selection.getMaxIndex();
        var number_of_changes_added: usize = 0;
        errdefer for (0..number_of_changes_added) |_| {
            self.removeLastUncommittedChange();
        };
        var index = min_index;
        while (true) {
            const change = Change{ .insert_row = .{
                .index = index,
                .new_values = .{},
            } };
            self.addUncommittedChange(&change) catch |err| {
                sdk.misc.error_context.append("Failed to add insert uncommitted change for index: {}", .{index});
                return err;
            };
            number_of_changes_added += 1;
            if (index >= max_index) {
                break;
            }
            index += 1;
        }
    }

    pub fn deleteRows(self: *Self, sequence_len: usize) !void {
        self.selection = self.selection.clampIndices(sequence_len);
        const min_index = self.selection.getMinIndex();
        const max_index = self.selection.getMaxIndex();
        var number_of_changes_added: usize = 0;
        errdefer for (0..number_of_changes_added) |_| {
            self.removeLastUncommittedChange();
        };
        var index = max_index;
        while (true) {
            const change = Change{ .delete_row = .{
                .index = index,
                .old_values = .{},
            } };
            self.addUncommittedChange(&change) catch |err| {
                sdk.misc.error_context.append("Failed to add delete uncommitted change for index: {}", .{index});
                return err;
            };
            number_of_changes_added += 1;
            if (index <= min_index) {
                break;
            }
            index -= 1;
        }
        self.selection.start.index = min_index;
        self.selection.end.index = min_index;
    }

    pub fn move(self: *Self, destination_min_index: usize, sequence_len: usize) !void {
        self.selection = self.selection.clampIndices(sequence_len);
        const columns: Change.Move.Columns = block: {
            if (self.selection.start.player_id != self.selection.end.player_id) {
                break :block .both;
            }
            break :block switch (self.selection.start.player_id) {
                .player_1 => .player_1,
                .player_2 => .player_2,
            };
        };
        const change = Change{ .move = .{
            .columns = columns,
            .source_index = self.selection.getMinIndex(),
            .destination_index = destination_min_index,
            .number_of_rows = self.selection.getNumberOfRows(),
        } };
        self.addUncommittedChange(&change) catch |err| {
            sdk.misc.error_context.append("Failed to add move rows uncommitted change.", .{});
            return err;
        };
        const destination_max_index = destination_min_index + self.selection.getNumberOfRows() - 1;
        if (self.selection.start.index <= self.selection.end.index) {
            self.selection.start.index = destination_min_index;
            self.selection.end.index = destination_max_index;
        } else {
            self.selection.start.index = destination_max_index;
            self.selection.end.index = destination_min_index;
        }
    }

    pub fn swapSides(self: *Self, sequence_len: usize) !void {
        self.selection = self.selection.clampIndices(sequence_len);
        const change = Change{ .swap_sides = .{
            .index = self.selection.getMinIndex(),
            .number_of_rows = self.selection.getNumberOfRows(),
        } };
        self.addUncommittedChange(&change) catch |err| {
            sdk.misc.error_context.append("Failed to add swap uncommitted change.", .{});
            return err;
        };
        if (self.selection.start.player_id == self.selection.end.player_id) {
            self.selection.start.player_id = self.selection.start.player_id.getOther();
            self.selection.end.player_id = self.selection.end.player_id.getOther();
        }
    }

    pub fn setValues(self: *Self, value: model.Input, sequence_len: usize) !void {
        const selection = &self.selection;
        selection.* = selection.clampIndices(sequence_len);
        const player_ids: []const model.PlayerId = switch (selection.start.player_id == selection.end.player_id) {
            true => &[1]model.PlayerId{selection.start.player_id},
            false => &[2]model.PlayerId{ .player_1, .player_2 },
        };
        const min_index = selection.getMinIndex();
        const max_index = selection.getMaxIndex();
        var number_of_changes_added: usize = 0;
        errdefer for (0..number_of_changes_added) |_| {
            self.removeLastUncommittedChange();
        };
        var index = min_index;
        while (true) {
            for (player_ids) |player_id| {
                const change = Change{ .set_value = .{
                    .player_id = player_id,
                    .index = index,
                    .old_value = .{},
                    .new_value = value,
                } };
                self.addUncommittedChange(&change) catch |err| {
                    sdk.misc.error_context.append(
                        "Failed to add set value uncommitted change for {s} at index: {}",
                        .{ @tagName(player_id), index },
                    );
                    return err;
                };
                number_of_changes_added += 1;
            }
            if (index >= max_index) {
                break;
            }
            index += 1;
        }
    }

    pub fn copy(
        self: *Self,
        setClipboardText: *const fn (text: [:0]const u8) void,
        tai: *const core.ToolAssistedInput,
    ) !void {
        const selection = &self.selection;
        selection.* = selection.clampIndices(tai.sequence.items.len);

        const max_bytes_per_value = 20;
        const number_of_values = selection.getNumberOfCells();
        const buffer = self.allocator.alloc(u8, max_bytes_per_value * number_of_values) catch |err| {
            sdk.misc.error_context.new("Failed to allocate buffer to copy into.", .{});
            return err;
        };
        defer self.allocator.free(buffer);

        var writer = std.Io.Writer.fixed(buffer);
        const player_ids: []const model.PlayerId = switch (selection.start.player_id == selection.end.player_id) {
            true => switch (selection.start.player_id) {
                .player_1 => &.{.player_1},
                .player_2 => &.{.player_2},
            },
            else => &.{ .player_1, .player_2 },
        };
        var index = self.selection.getMinIndex();
        while (index <= self.selection.getMaxIndex()) : (index += 1) {
            const item = &tai.sequence.items[index];
            for (player_ids, 0..) |player_id, i| {
                const value = switch (player_id) {
                    .player_1 => item.player_1,
                    .player_2 => item.player_2,
                };
                writer.print("{f}", .{value}) catch |err| {
                    sdk.misc.error_context.new(
                        "Failed to write {s} input at index: {}",
                        .{ @tagName(player_id), index },
                    );
                    return err;
                };
                if (i < player_ids.len - 1) {
                    writer.writeByte('\t') catch |err| {
                        sdk.misc.error_context.new("Failed to write tab character at index: {}", .{index});
                        return err;
                    };
                }
            }
            writer.writeByte('\n') catch |err| {
                sdk.misc.error_context.new("Failed to write new line character at index: {}", .{index});
                return err;
            };
        }
        writer.writeByte(0) catch |err| {
            sdk.misc.error_context.new("Failed to write the 0 terminator at the end of the string.", .{});
            return err;
        };

        setClipboardText(buffer[0..(writer.end - 1) :0]);
    }

    pub fn paste(self: *Self, text: [:0]const u8, sequence_len: usize) !void {
        const text_with_null: []const u8 = text[0..(text.len + 1)];

        var number_of_changes_added: usize = 0;
        errdefer for (0..number_of_changes_added) |_| {
            self.removeLastUncommittedChange();
        };

        const starting_row_index = self.selection.getMinIndex();
        const starting_column = self.selection.getMinPlayerId();
        var current_row_index = starting_row_index;
        var current_column: ?model.PlayerId = starting_column;
        var max_column = starting_column;
        var value_start_text_index: usize = 0;
        for (text_with_null, 0..) |byte, current_text_index| {
            if (byte != '\t' and byte != '\n' and byte != 0) {
                continue;
            }
            if (byte == 0 and current_text_index > 0 and text[current_text_index - 1] == '\n') {
                if (current_row_index > starting_row_index) {
                    current_row_index -= 1;
                }
                break;
            }
            if (current_column) |player_id| {
                const value_text = text[value_start_text_index..current_text_index];
                const value = model.Input.parse(value_text);
                const change: Change = block: {
                    if (current_row_index >= sequence_len and player_id == starting_column) {
                        break :block .{ .insert_row = .{
                            .index = current_row_index,
                            .new_values = switch (player_id) {
                                .player_1 => .{ .player_1 = value, .player_2 = .{} },
                                .player_2 => .{ .player_1 = .{}, .player_2 = value },
                            },
                        } };
                    } else {
                        break :block .{ .set_value = .{
                            .player_id = player_id,
                            .index = current_row_index,
                            .old_value = .{},
                            .new_value = value,
                        } };
                    }
                };
                self.addUncommittedChange(&change) catch |err| {
                    sdk.misc.error_context.append(
                        "Failed to add the change for {s} at index {} to uncommitted changes.",
                        .{ @tagName(player_id), current_row_index },
                    );
                    return err;
                };
                number_of_changes_added += 1;
            }
            value_start_text_index = current_text_index + 1;
            switch (byte) {
                0 => break,
                '\t' => if (current_column) |player_id| switch (player_id) {
                    .player_1 => {
                        max_column = .player_2;
                        current_column = .player_2;
                    },
                    .player_2 => {
                        current_column = null;
                    },
                },
                '\n' => {
                    current_column = starting_column;
                    current_row_index += 1;
                },
                else => unreachable,
            }
        }

        self.selection = .{
            .start = .{ .player_id = self.selection.getMinPlayerId(), .index = self.selection.getMinIndex() },
            .end = .{ .player_id = max_column, .index = current_row_index },
        };
    }

    fn addUncommittedChange(self: *Self, change: *const Change) !void {
        const is_first_change = self.uncommitted.items.len == 0;
        if (is_first_change) {
            const checkpoint = Change{ .checkpoint = .{
                .selection_before = self.selection,
                .selection_after = null,
            } };
            self.uncommitted.append(self.allocator, checkpoint) catch |err| {
                sdk.misc.error_context.new("Failed to append first change checkpoint to uncommitted changes.", .{});
                return err;
            };
        }
        errdefer if (is_first_change) {
            _ = self.uncommitted.pop();
        };
        self.uncommitted.append(self.allocator, change.*) catch |err| {
            sdk.misc.error_context.new("Failed to append the change to uncommitted changes.", .{});
            return err;
        };
    }

    fn removeLastUncommittedChange(self: *Self) void {
        _ = self.uncommitted.pop();
        if (self.uncommitted.getLastOrNull()) |change| {
            switch (change) {
                .checkpoint => _ = self.uncommitted.pop(),
                else => {},
            }
        }
    }

    pub fn commit(self: *Self, tai: *core.ToolAssistedInput) !void {
        if (self.uncommitted.items.len == 0) {
            return;
        }
        var number_of_changes_applied: usize = 0;
        errdefer {
            var index = number_of_changes_applied;
            while (index > 0) : (index -= 1) {
                const change = &self.uncommitted.items[index - 1];
                change.undo(tai, &self.selection) catch unreachable;
            }
        }
        var number_of_changes_appended: usize = 0;
        errdefer self.undo_stack.items.len -= number_of_changes_appended;
        for (self.uncommitted.items, 0..) |*change, change_index| {
            const changed_something = change.apply(tai, &self.selection) catch |err| {
                sdk.misc.error_context.append("Failed to apply uncommitted change at index: {}", .{change_index});
                return err;
            };
            number_of_changes_applied += 1;
            if (changed_something) {
                self.undo_stack.append(self.allocator, change.*) catch |err| {
                    sdk.misc.error_context.new("Failed to append change {} to undo stack.", .{change_index});
                    return err;
                };
                number_of_changes_appended += 1;
            }
        }
        if (number_of_changes_appended == 1 and self.undo_stack.getLast() == .checkpoint) {
            self.undo_stack.items.len -= 1;
        }
        self.redo_stack.clearAndFree(self.allocator);
        self.discardUncommitted();
    }

    pub fn discardUncommitted(self: *Self) void {
        if (self.uncommitted.items.len <= 32) {
            self.uncommitted.clearRetainingCapacity();
        } else {
            self.uncommitted.clearAndFree(self.allocator);
        }
    }

    pub fn canUndo(self: *const Self) bool {
        return self.undo_stack.items.len > 0;
    }

    pub fn undo(self: *Self, tai: *core.ToolAssistedInput) !void {
        if (self.undo_stack.items.len == 0) {
            sdk.misc.error_context.new("Nothing to undo.", .{});
            return error.NothingToUndo;
        }
        const old_selection = self.selection;
        errdefer self.selection = old_selection;
        const number_of_changes_to_undo = block: {
            var count: usize = 0;
            var index = self.undo_stack.items.len;
            while (index > 0) : (index -= 1) {
                count += 1;
                if (self.undo_stack.items[index - 1] == .checkpoint) {
                    break;
                }
            }
            break :block count;
        };
        self.redo_stack.ensureUnusedCapacity(self.allocator, number_of_changes_to_undo) catch |err| {
            sdk.misc.error_context.new("Failed to allocate memory to store undone changes on the redo stack.", .{});
            return err;
        };
        var number_of_changes_undone: usize = 0;
        errdefer for (0..number_of_changes_undone) |_| {
            var change = self.redo_stack.pop() orelse unreachable;
            _ = change.apply(tai, &self.selection) catch unreachable;
            self.undo_stack.appendAssumeCapacity(change);
        };
        for (0..number_of_changes_to_undo) |change_number| {
            const change = self.undo_stack.pop() orelse unreachable;
            errdefer self.undo_stack.appendAssumeCapacity(change);
            change.undo(tai, &self.selection) catch |err| {
                sdk.misc.error_context.append("Failed to undo change: {}", .{change_number});
                return err;
            };
            self.redo_stack.appendAssumeCapacity(change);
            number_of_changes_undone += 1;
        }
    }

    pub fn canRedo(self: *const Self) bool {
        return self.redo_stack.items.len > 0;
    }

    pub fn redo(self: *Self, tai: *core.ToolAssistedInput) !void {
        if (self.redo_stack.items.len == 0) {
            sdk.misc.error_context.new("Nothing to redo.", .{});
            return error.NothingToRedo;
        }
        const old_selection = self.selection;
        errdefer self.selection = old_selection;
        const number_of_changes_to_redo = block: {
            var count: usize = 0;
            var is_first_checkpoint = true;
            var index = self.redo_stack.items.len;
            while (index > 0) : (index -= 1) {
                if (self.redo_stack.items[index - 1] == .checkpoint) {
                    if (!is_first_checkpoint) {
                        break;
                    }
                    is_first_checkpoint = false;
                }
                count += 1;
            }
            break :block count;
        };
        self.undo_stack.ensureUnusedCapacity(self.allocator, number_of_changes_to_redo) catch |err| {
            sdk.misc.error_context.new("Failed to allocate memory to store redone changes on the undo stack.", .{});
            return err;
        };
        var number_of_changes_redone: usize = 0;
        errdefer for (0..number_of_changes_redone) |_| {
            const change = self.undo_stack.pop() orelse unreachable;
            change.undo(tai, &self.selection) catch unreachable;
            self.redo_stack.appendAssumeCapacity(change);
        };
        for (0..number_of_changes_to_redo) |change_number| {
            var change = self.redo_stack.pop() orelse unreachable;
            errdefer self.redo_stack.appendAssumeCapacity(change);
            _ = change.apply(tai, &self.selection) catch |err| {
                sdk.misc.error_context.append("Failed to redo change: {}", .{change_number});
                return err;
            };
            self.undo_stack.appendAssumeCapacity(change);
            number_of_changes_redone += 1;
        }
    }

    pub fn clear(self: *Self, tai: *core.ToolAssistedInput) void {
        tai.sequence.clearAndFree(tai.allocator);
        self.uncommitted.clearAndFree(self.allocator);
        self.undo_stack.clearAndFree(self.allocator);
        self.redo_stack.clearAndFree(self.allocator);
        self.selection = .initial;
    }

    pub fn importFromRecording(self: *Self, tai: *core.ToolAssistedInput, controller: anytype) !void {
        if (@typeInfo(@TypeOf(controller)) != .pointer) {
            @compileError(
                "Expecting the controller to be passed by reference but got type: " ++ @typeName(@TypeOf(controller)),
            );
        }
        self.clear(tai);
        const total_frames = controller.getTotalFrames();
        tai.sequence.ensureTotalCapacity(tai.allocator, total_frames) catch |err| {
            sdk.misc.error_context.new("Failed to allocate memory for tool assisted input sequence.", .{});
            return err;
        };
        for (0..total_frames) |index| {
            const frame = controller.getFrameAt(index) orelse unreachable;
            tai.sequence.appendAssumeCapacity(.{
                .player_1 = frame.getPlayerById(.player_1).input orelse .{},
                .player_2 = frame.getPlayerById(.player_2).input orelse .{},
            });
        }
    }
};

const Change = union(enum) {
    checkpoint: Checkpoint,
    insert_row: InsertRow,
    delete_row: DeleteRow,
    move: Move,
    swap_sides: SwapSides,
    set_value: SetValue,

    pub fn apply(self: *Change, tai: *core.ToolAssistedInput, selection: *TaiEditor.Selection) !bool {
        return (switch (self.*) {
            .checkpoint => |*checkpoint| checkpoint.apply(selection),
            .insert_row => |*insert_row| insert_row.apply(tai),
            .delete_row => |*delete_row| delete_row.apply(tai),
            .move => |*move| move.apply(tai),
            .swap_sides => |*swap_sides| swap_sides.apply(tai),
            .set_value => |*set_value| set_value.apply(tai),
        }) catch |err| {
            sdk.misc.error_context.append("Failed to apply {s} change.", .{@tagName(self.*)});
            return err;
        };
    }

    pub fn undo(self: *const Change, tai: *core.ToolAssistedInput, selection: *TaiEditor.Selection) !void {
        (switch (self.*) {
            .checkpoint => |*checkpoint| checkpoint.undo(selection),
            .insert_row => |*insert_row| insert_row.undo(tai),
            .delete_row => |*delete_row| delete_row.undo(tai),
            .move => |*move| move.undo(tai),
            .swap_sides => |*swap_sides| swap_sides.undo(tai),
            .set_value => |*set_value| set_value.undo(tai),
        }) catch |err| {
            sdk.misc.error_context.append("Failed to undo {s} change.", .{@tagName(self.*)});
            return err;
        };
    }

    pub const Checkpoint = struct {
        selection_before: TaiEditor.Selection,
        selection_after: ?TaiEditor.Selection,

        pub fn apply(self: *Checkpoint, selection: *TaiEditor.Selection) bool {
            if (self.selection_after) |selection_after| {
                selection.* = selection_after;
            } else {
                self.selection_after = selection.*;
            }
            return true;
        }

        pub fn undo(self: *const Checkpoint, selection: *TaiEditor.Selection) void {
            selection.* = self.selection_before;
        }
    };
    pub const InsertRow = struct {
        index: usize,
        new_values: core.ToolAssistedInput.SequenceItem,

        pub fn apply(self: *const InsertRow, tai: *core.ToolAssistedInput) !bool {
            if (self.index > tai.sequence.items.len) {
                sdk.misc.error_context.new("Index out of bounds: {}", .{self.index});
                return error.IndexOutOfBounds;
            }
            tai.sequence.insert(tai.allocator, self.index, self.new_values) catch |err| {
                sdk.misc.error_context.new(
                    "Failed to insert an item into the tool assisted input sequence at index: {}",
                    .{self.index},
                );
                return err;
            };
            return true;
        }

        pub fn undo(self: *const InsertRow, tai: *core.ToolAssistedInput) !void {
            var inverse = DeleteRow{
                .index = self.index,
                .old_values = self.new_values,
            };
            _ = inverse.apply(tai) catch |err| {
                sdk.misc.error_context.append("Failed to apply the inverse (delete row) change.", .{});
                return err;
            };
        }
    };
    pub const DeleteRow = struct {
        index: usize,
        old_values: core.ToolAssistedInput.SequenceItem,

        pub fn apply(self: *DeleteRow, tai: *core.ToolAssistedInput) !bool {
            if (self.index >= tai.sequence.items.len) {
                sdk.misc.error_context.new("Index out of bounds: {}", .{self.index});
                return error.IndexOutOfBounds;
            }
            self.old_values = tai.sequence.items[self.index];
            _ = tai.sequence.orderedRemove(self.index);
            return true;
        }

        pub fn undo(self: *const DeleteRow, tai: *core.ToolAssistedInput) !void {
            const inverse = InsertRow{
                .index = self.index,
                .new_values = self.old_values,
            };
            _ = inverse.apply(tai) catch |err| {
                sdk.misc.error_context.append("Failed to apply the inverse (insert row) change.", .{});
                return err;
            };
        }
    };
    pub const Move = struct {
        columns: Columns,
        source_index: usize,
        destination_index: usize,
        number_of_rows: usize,

        pub const Columns = enum { player_1, player_2, both };
        const SequenceItem = core.ToolAssistedInput.SequenceItem;

        pub fn apply(self: *const Move, tai: *core.ToolAssistedInput) !bool {
            const items = tai.sequence.items;
            if (self.number_of_rows == 0 or self.source_index == self.destination_index) {
                return false;
            }
            const source_end = std.math.add(usize, self.source_index, self.number_of_rows) catch |err| {
                sdk.misc.error_context.new("Failed to calculate source end index.", .{});
                return err;
            };
            if (source_end > items.len) {
                sdk.misc.error_context.new("Source index range out of bounds.", .{});
                return error.IndexOutOfBounds;
            }
            const destination_end = std.math.add(usize, self.destination_index, self.number_of_rows) catch |err| {
                sdk.misc.error_context.new("Failed to calculate destination end index.", .{});
                return err;
            };
            if (destination_end > items.len) {
                sdk.misc.error_context.new("Destination index range out of bounds.", .{});
                return error.IndexOutOfBounds;
            }
            const swap = switch (self.columns) {
                .player_1 => &swapPlayer1,
                .player_2 => &swapPlayer2,
                .both => &swapBoth,
            };
            var change_detected = false;
            if (self.destination_index < self.source_index) {
                const a_len = self.source_index - self.destination_index;
                const b_len = self.number_of_rows;
                var a = a_len;
                var b = b_len;
                var first = self.destination_index;
                var middle = self.source_index;
                while (a != 0 and b != 0) {
                    if (a <= b) {
                        for (0..a) |i| {
                            swap(&change_detected, &items[first + i], &items[middle + i]);
                        }
                        first += a;
                        middle += a;
                        b -= a;
                    } else {
                        for (0..b) |i| {
                            swap(&change_detected, &items[first + a - b + i], &items[middle + i]);
                        }
                        middle -= b;
                        a -= b;
                    }
                }
            } else {
                const a_len = self.number_of_rows;
                const b_len = self.destination_index - self.source_index;
                var a = a_len;
                var b = b_len;
                var first = self.source_index;
                var middle = source_end;
                while (a != 0 and b != 0) {
                    if (a <= b) {
                        for (0..a) |i| {
                            swap(&change_detected, &items[first + i], &items[middle + i]);
                        }
                        first += a;
                        middle += a;
                        b -= a;
                    } else {
                        for (0..b) |i| {
                            swap(&change_detected, &items[first + a - b + i], &items[middle + i]);
                        }
                        middle -= b;
                        a -= b;
                    }
                }
            }
            return change_detected;
        }

        pub fn undo(self: *const Move, tai: *core.ToolAssistedInput) !void {
            const inverse = Move{
                .columns = self.columns,
                .source_index = self.destination_index,
                .destination_index = self.source_index,
                .number_of_rows = self.number_of_rows,
            };
            _ = inverse.apply(tai) catch |err| {
                sdk.misc.error_context.append("Failed to apply the inverse (move) change.", .{});
                return err;
            };
        }

        fn swapPlayer1(change_detected: *bool, item_1: *SequenceItem, item_2: *SequenceItem) void {
            if (item_1.player_1.equalsIgnoringLeftRight(item_2.player_1)) {
                return;
            }
            std.mem.swap(model.Input, &item_1.player_1, &item_2.player_1);
            change_detected.* = true;
        }

        fn swapPlayer2(change_detected: *bool, item_1: *SequenceItem, item_2: *SequenceItem) void {
            if (item_1.player_2.equalsIgnoringLeftRight(item_2.player_2)) {
                return;
            }
            std.mem.swap(model.Input, &item_1.player_2, &item_2.player_2);
            change_detected.* = true;
        }

        fn swapBoth(change_detected: *bool, item_1: *SequenceItem, item_2: *SequenceItem) void {
            const p1_equals = item_1.player_1.equalsIgnoringLeftRight(item_2.player_1);
            const p2_equals = item_1.player_2.equalsIgnoringLeftRight(item_2.player_2);
            if (p1_equals and p2_equals) {
                return;
            }
            std.mem.swap(core.ToolAssistedInput.SequenceItem, item_1, item_2);
            change_detected.* = true;
        }
    };
    pub const SwapSides = struct {
        index: usize,
        number_of_rows: usize,

        pub fn apply(self: *const SwapSides, tai: *core.ToolAssistedInput) !bool {
            if (self.number_of_rows == 0) {
                return false;
            }
            const start = self.index;
            const end = std.math.add(usize, start, self.number_of_rows) catch |err| {
                sdk.misc.error_context.new("Failed to calculate end index.", .{});
                return err;
            };
            if (end > tai.sequence.items.len) {
                sdk.misc.error_context.new("Index range out of bounds.", .{});
                return error.IndexOutOfBounds;
            }
            var change_detected = false;
            for (tai.sequence.items[start..end]) |*item| {
                if (item.player_1.equalsIgnoringLeftRight(item.player_2)) {
                    continue;
                }
                std.mem.swap(model.Input, &item.player_1, &item.player_2);
                change_detected = true;
            }
            return change_detected;
        }

        pub fn undo(self: *const SwapSides, tai: *core.ToolAssistedInput) !void {
            _ = try self.apply(tai);
        }
    };
    pub const SetValue = struct {
        player_id: model.PlayerId,
        index: usize,
        old_value: model.Input,
        new_value: model.Input,

        pub fn apply(self: *SetValue, tai: *core.ToolAssistedInput) !bool {
            if (self.index >= tai.sequence.items.len) {
                sdk.misc.error_context.new("Index out of bounds: {}", .{self.index});
                return error.IndexOutOfBounds;
            }
            const item = &tai.sequence.items[self.index];
            const value = switch (self.player_id) {
                .player_1 => &item.player_1,
                .player_2 => &item.player_2,
            };
            if (!value.equalsIgnoringLeftRight(self.new_value)) {
                self.old_value = value.*;
                value.* = self.new_value;
                return true;
            } else {
                return false;
            }
        }

        pub fn undo(self: *const SetValue, tai: *core.ToolAssistedInput) !void {
            var inverse = SetValue{
                .player_id = self.player_id,
                .index = self.index,
                .old_value = self.new_value,
                .new_value = self.old_value,
            };
            _ = inverse.apply(tai) catch |err| {
                sdk.misc.error_context.append("Failed to apply the inverse (set value) change.", .{});
                return err;
            };
        }
    };
};

const testing = std.testing;

test "commit should do nothing when no uncommitted changes are pending" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();

    try editor.commit(&tai);
    try testing.expectEqual(false, editor.canUndo());
}

test "commit should not store changes when changes don't change the input sequence" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .button_2 = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .button_2 = true }, .player_2 = .{ .button_2 = true } },
    });

    editor.selection = .{
        .start = .{ .index = 0, .player_id = .player_1 },
        .end = .{ .index = 1, .player_id = .player_2 },
    };
    try editor.setValues(.{ .button_1 = true }, tai.sequence.items.len);
    try editor.commit(&tai);
    try testing.expectEqual(false, editor.canUndo());

    editor.selection = .{
        .start = .{ .index = 2, .player_id = .player_2 },
        .end = .{ .index = 3, .player_id = .player_2 },
    };
    try editor.move(3, tai.sequence.items.len);
    try editor.commit(&tai);
    try testing.expectEqual(false, editor.canUndo());

    editor.selection = .{
        .start = .{ .index = 3, .player_id = .player_1 },
        .end = .{ .index = 4, .player_id = .player_1 },
    };
    try editor.swapSides(tai.sequence.items.len);
    try editor.commit(&tai);
    try testing.expectEqual(false, editor.canUndo());
}

test "commit should revert changes and return error when operating out of bounds" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    });

    editor.selection = .{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 4, .player_id = .player_2 },
    };
    try editor.setValues(.{}, 5);
    try testing.expectError(error.IndexOutOfBounds, editor.commit(&tai));

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
}

test "discardUncommitted should drop pending changes without applying them" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
    });

    editor.selection = .{
        .start = .{ .index = 0, .player_id = .player_1 },
        .end = .{ .index = 1, .player_id = .player_2 },
    };
    try editor.setValues(.{ .button_3 = true }, tai.sequence.items.len);
    try editor.insertRows();
    editor.discardUncommitted();
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(false, editor.canUndo());
}

test "undo should return error when there is nothing to undo" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();

    try testing.expectError(error.NothingToUndo, editor.undo(&tai));
}

test "redo should return error when there is nothing to redo" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();

    try testing.expectError(error.NothingToRedo, editor.redo(&tai));
}

test "canUndo and canRedo should return correct values" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();

    try testing.expectEqual(false, editor.canUndo());
    try testing.expectEqual(false, editor.canRedo());

    editor.selection = .{
        .start = .{ .index = 0, .player_id = .player_1 },
        .end = .{ .index = 0, .player_id = .player_1 },
    };
    try editor.insertRows();
    try editor.commit(&tai);

    try testing.expectEqual(true, editor.canUndo());
    try testing.expectEqual(false, editor.canRedo());

    editor.selection = .{
        .start = .{ .index = 0, .player_id = .player_1 },
        .end = .{ .index = 0, .player_id = .player_1 },
    };
    try editor.insertRows();
    try editor.commit(&tai);

    try testing.expectEqual(true, editor.canUndo());
    try testing.expectEqual(false, editor.canRedo());

    try editor.undo(&tai);

    try testing.expectEqual(true, editor.canUndo());
    try testing.expectEqual(true, editor.canRedo());

    try editor.undo(&tai);

    try testing.expectEqual(false, editor.canUndo());
    try testing.expectEqual(true, editor.canRedo());

    editor.selection = .{
        .start = .{ .index = 0, .player_id = .player_1 },
        .end = .{ .index = 0, .player_id = .player_1 },
    };
    try editor.insertRows();
    try editor.commit(&tai);

    try testing.expectEqual(true, editor.canUndo());
    try testing.expectEqual(false, editor.canRedo());
}

test "insertRows should insert empty rows at selected indices" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    });

    editor.selection = .{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    };
    try editor.insertRows();
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    }, editor.selection);

    editor.selection = .{
        .start = .{ .index = 6, .player_id = .player_1 },
        .end = .{ .index = 6, .player_id = .player_1 },
    };
    try editor.insertRows();
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{}, .player_2 = .{} },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 6, .player_id = .player_1 },
        .end = .{ .index = 6, .player_id = .player_1 },
    }, editor.selection);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 6, .player_id = .player_1 },
        .end = .{ .index = 6, .player_id = .player_1 },
    }, editor.selection);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    }, editor.selection);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    }, editor.selection);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{}, .player_2 = .{} },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{}, .player_2 = .{} },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 6, .player_id = .player_1 },
        .end = .{ .index = 6, .player_id = .player_1 },
    }, editor.selection);
}

test "deleteRows should delete rows at selected indices" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    });

    editor.selection = .{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    };
    try editor.deleteRows(tai.sequence.items.len);
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 1, .player_id = .player_2 },
    }, editor.selection);

    editor.selection = .{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_1 },
    };
    try editor.deleteRows(tai.sequence.items.len);
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 1, .player_id = .player_1 },
    }, editor.selection);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 1, .player_id = .player_1 },
    }, editor.selection);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    }, editor.selection);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 1, .player_id = .player_2 },
    }, editor.selection);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 1, .player_id = .player_1 },
    }, editor.selection);
}

test "move should move selected values to specified destination index" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    });

    editor.selection = .{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 1, .player_id = .player_2 },
    };
    try editor.move(3, tai.sequence.items.len);
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 3, .player_id = .player_1 },
        .end = .{ .index = 3, .player_id = .player_2 },
    }, editor.selection);

    editor.selection = .{
        .start = .{ .index = 2, .player_id = .player_2 },
        .end = .{ .index = 4, .player_id = .player_2 },
    };
    try editor.move(0, tai.sequence.items.len);
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_3 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 0, .player_id = .player_2 },
        .end = .{ .index = 1, .player_id = .player_2 },
    }, editor.selection);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 2, .player_id = .player_2 },
        .end = .{ .index = 3, .player_id = .player_2 },
    }, editor.selection);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 1, .player_id = .player_2 },
    }, editor.selection);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 3, .player_id = .player_1 },
        .end = .{ .index = 3, .player_id = .player_2 },
    }, editor.selection);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_3 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 0, .player_id = .player_2 },
        .end = .{ .index = 1, .player_id = .player_2 },
    }, editor.selection);
}

test "swapSides should swap values between player 1 and player 2 on selected indices" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    });

    editor.selection = .{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    };
    try editor.swapSides(tai.sequence.items.len);
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .button_2 = true }, .player_2 = .{ .down = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .forward = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    }, editor.selection);

    editor.selection = .{
        .start = .{ .index = 0, .player_id = .player_2 },
        .end = .{ .index = 4, .player_id = .player_2 },
    };
    try editor.swapSides(tai.sequence.items.len);
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .up = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .button_4 = true }, .player_2 = .{ .back = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 0, .player_id = .player_1 },
        .end = .{ .index = 3, .player_id = .player_1 },
    }, editor.selection);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .button_2 = true }, .player_2 = .{ .down = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .forward = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 0, .player_id = .player_2 },
        .end = .{ .index = 3, .player_id = .player_2 },
    }, editor.selection);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    }, editor.selection);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .button_2 = true }, .player_2 = .{ .down = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .forward = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    }, editor.selection);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .up = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .button_4 = true }, .player_2 = .{ .back = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 0, .player_id = .player_1 },
        .end = .{ .index = 3, .player_id = .player_1 },
    }, editor.selection);
}

test "setValues should set every cell in the selection to the specified value" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    });

    editor.selection = .{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    };
    try editor.setValues(.{ .rage = true }, tai.sequence.items.len);
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .rage = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .rage = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    }, editor.selection);

    editor.selection = .{
        .start = .{ .index = 0, .player_id = .player_2 },
        .end = .{ .index = 4, .player_id = .player_2 },
    };
    try editor.setValues(.{ .heat = true }, tai.sequence.items.len);
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .heat = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .heat = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .heat = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .heat = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 0, .player_id = .player_2 },
        .end = .{ .index = 3, .player_id = .player_2 },
    }, editor.selection);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .rage = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .rage = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 0, .player_id = .player_2 },
        .end = .{ .index = 3, .player_id = .player_2 },
    }, editor.selection);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    }, editor.selection);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .rage = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .rage = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    }, editor.selection);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .heat = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .heat = true } },
        .{ .player_1 = .{ .rage = true }, .player_2 = .{ .heat = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .heat = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 0, .player_id = .player_2 },
        .end = .{ .index = 3, .player_id = .player_2 },
    }, editor.selection);
}

test "copy should set clipboard text to the stringified version of the selection" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .back = true }, .player_2 = .{ .button_4 = true } },
    });

    const Clipboard = struct {
        var data: ?[]u8 = null;

        fn setText(text: [:0]const u8) void {
            const copy = testing.allocator.alloc(u8, text.len) catch @panic("Failed to allocate clipboard data.");
            @memcpy(copy, text);
            deinit();
            data = copy;
        }

        fn deinit() void {
            if (data) |text| {
                testing.allocator.free(text);
            }
        }
    };
    defer Clipboard.deinit();

    editor.selection = .{
        .start = .{ .index = 0, .player_id = .player_1 },
        .end = .{ .index = 4, .player_id = .player_2 },
    };
    try editor.copy(Clipboard.setText, &tai);
    try testing.expect(Clipboard.data != null);
    try testing.expectEqualStrings("u\t1\nd\t2\nf\t3\nb\t4\n", Clipboard.data.?);

    editor.selection = .{
        .start = .{ .index = 2, .player_id = .player_2 },
        .end = .{ .index = 1, .player_id = .player_1 },
    };
    try editor.copy(Clipboard.setText, &tai);
    try testing.expect(Clipboard.data != null);
    try testing.expectEqualStrings("d\t2\nf\t3\n", Clipboard.data.?);

    editor.selection = .{
        .start = .{ .index = 0, .player_id = .player_2 },
        .end = .{ .index = 2, .player_id = .player_2 },
    };
    try editor.copy(Clipboard.setText, &tai);
    try testing.expect(Clipboard.data != null);
    try testing.expectEqualStrings("1\n2\n3\n", Clipboard.data.?);

    editor.selection = .{
        .start = .{ .index = 2, .player_id = .player_2 },
        .end = .{ .index = 2, .player_id = .player_1 },
    };
    try editor.copy(Clipboard.setText, &tai);
    try testing.expect(Clipboard.data != null);
    try testing.expectEqualStrings("f\t3\n", Clipboard.data.?);

    editor.selection = .{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 1, .player_id = .player_1 },
    };
    try editor.copy(Clipboard.setText, &tai);
    try testing.expect(Clipboard.data != null);
    try testing.expectEqualStrings("d\n", Clipboard.data.?);
}

test "paste should change the selection controlled part of sequence to match the provided text" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();

    editor.selection = .{
        .start = .{ .index = 0, .player_id = .player_2 },
        .end = .{ .index = 0, .player_id = .player_2 },
    };
    try editor.paste("1\n2\t123\n3\n4", tai.sequence.items.len);
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{}, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{}, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{}, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{}, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 0, .player_id = .player_2 },
        .end = .{ .index = 3, .player_id = .player_2 },
    }, editor.selection);

    editor.selection = .{
        .start = .{ .index = 1, .player_id = .player_2 },
        .end = .{ .index = 3, .player_id = .player_1 },
    };
    try editor.paste("1\t2\n3\t4\n", tai.sequence.items.len);
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{}, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{}, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 2, .player_id = .player_2 },
    }, editor.selection);

    editor.selection = .{
        .start = .{ .index = 3, .player_id = .player_1 },
        .end = .{ .index = 3, .player_id = .player_1 },
    };
    try editor.paste("1\t2\n3\t4", tai.sequence.items.len);
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{}, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 3, .player_id = .player_1 },
        .end = .{ .index = 4, .player_id = .player_2 },
    }, editor.selection);

    editor.selection = .{
        .start = .{ .index = 4, .player_id = .player_2 },
        .end = .{ .index = 4, .player_id = .player_2 },
    };
    try editor.paste("1\t2\n3\t4\n", tai.sequence.items.len);
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{}, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{}, .player_2 = .{ .button_3 = true } },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 4, .player_id = .player_2 },
        .end = .{ .index = 5, .player_id = .player_2 },
    }, editor.selection);

    editor.selection = .{
        .start = .{ .index = 6, .player_id = .player_1 },
        .end = .{ .index = 6, .player_id = .player_1 },
    };
    try editor.paste("1234\n1234", tai.sequence.items.len);
    try editor.commit(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{}, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{}, .player_2 = .{ .button_3 = true } },
        .{ .player_1 = .{ .button_1 = true, .button_2 = true, .button_3 = true, .button_4 = true }, .player_2 = .{} },
        .{ .player_1 = .{ .button_1 = true, .button_2 = true, .button_3 = true, .button_4 = true }, .player_2 = .{} },
    }, tai.sequence.items);
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 6, .player_id = .player_1 },
        .end = .{ .index = 7, .player_id = .player_1 },
    }, editor.selection);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{}, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{}, .player_2 = .{ .button_3 = true } },
    }, tai.sequence.items);

    try editor.undo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{}, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .button_4 = true } },
    }, tai.sequence.items);

    try editor.redo(&tai);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{}, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .button_4 = true } },
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .button_3 = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{}, .player_2 = .{ .button_3 = true } },
    }, tai.sequence.items);
}

test "clear should remove all rows, pending changes, undo and redo history and reset selection" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .down = true }, .player_2 = .{ .button_2 = true } },
        .{ .player_1 = .{ .forward = true }, .player_2 = .{ .button_3 = true } },
    });

    editor.selection = .{
        .start = .{ .index = 0, .player_id = .player_1 },
        .end = .{ .index = 0, .player_id = .player_2 },
    };
    try editor.setValues(.{ .button_4 = true }, tai.sequence.items.len);
    try editor.commit(&tai);
    editor.selection = .{
        .start = .{ .index = 1, .player_id = .player_1 },
        .end = .{ .index = 1, .player_id = .player_2 },
    };
    try editor.setValues(.{ .button_4 = true }, tai.sequence.items.len);
    try editor.commit(&tai);
    try editor.undo(&tai);
    editor.selection = .{
        .start = .{ .index = 1, .player_id = .player_2 },
        .end = .{ .index = 2, .player_id = .player_2 },
    };
    try editor.setValues(.{ .back = true }, tai.sequence.items.len);
    try testing.expectEqual(true, editor.canUndo());
    try testing.expectEqual(true, editor.canRedo());

    editor.clear(&tai);

    try testing.expectEqual(0, tai.sequence.items.len);
    try testing.expectEqual(false, editor.canUndo());
    try testing.expectEqual(false, editor.canRedo());
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 0, .player_id = .player_1 },
        .end = .{ .index = 0, .player_id = .player_1 },
    }, editor.selection);

    try editor.commit(&tai);

    try testing.expectEqual(0, tai.sequence.items.len);
    try testing.expectEqual(false, editor.canUndo());
}

const MockController = struct {
    frames: []const model.Frame,

    const Self = @This();

    pub fn getTotalFrames(self: *const Self) usize {
        return self.frames.len;
    }

    pub fn getFrameAt(self: *const Self, index: usize) ?*const model.Frame {
        return if (index < self.frames.len) &self.frames[index] else null;
    }
};

test "importFromRecording should replace the sequence with inputs from the recording" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    const controller = MockController{ .frames = &.{
        .{ .players = .{
            .{ .input = .{ .up = true } },
            .{ .input = .{ .button_1 = true } },
        } },
        .{ .players = .{
            .{ .input = null },
            .{ .input = .{ .down = true } },
        } },
        .{ .players = .{
            .{ .input = .{ .forward = true, .button_2 = true } },
            .{ .input = null },
        } },
    } };
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .button_2 = true }, .player_2 = .{ .button_2 = true } },
    });

    editor.selection = .{
        .start = .{ .index = 0, .player_id = .player_1 },
        .end = .{ .index = 0, .player_id = .player_2 },
    };
    try editor.setValues(.{ .button_3 = true }, tai.sequence.items.len);
    try editor.commit(&tai);
    editor.selection = .{
        .start = .{ .index = 1, .player_id = .player_2 },
        .end = .{ .index = 1, .player_id = .player_2 },
    };
    try testing.expectEqual(true, editor.canUndo());

    try editor.importFromRecording(&tai, &controller);

    try testing.expectEqualSlices(core.ToolAssistedInput.SequenceItem, &.{
        .{ .player_1 = .{ .up = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{}, .player_2 = .{ .down = true } },
        .{ .player_1 = .{ .forward = true, .button_2 = true }, .player_2 = .{} },
    }, tai.sequence.items);
    try testing.expectEqual(false, editor.canUndo());
    try testing.expectEqual(false, editor.canRedo());
    try testing.expectEqual(TaiEditor.Selection{
        .start = .{ .index = 0, .player_id = .player_1 },
        .end = .{ .index = 0, .player_id = .player_1 },
    }, editor.selection);
}

test "importFromRecording should produce an empty sequence when the recording is empty" {
    var editor = TaiEditor.init(testing.allocator);
    defer editor.deinit();
    var tai = core.ToolAssistedInput.init(testing.allocator);
    defer tai.deinit();
    const controller = MockController{ .frames = &.{} };
    try tai.sequence.appendSlice(testing.allocator, &.{
        .{ .player_1 = .{ .button_1 = true }, .player_2 = .{ .button_1 = true } },
        .{ .player_1 = .{ .button_2 = true }, .player_2 = .{ .button_2 = true } },
    });

    try editor.importFromRecording(&tai, &controller);

    try testing.expectEqual(0, tai.sequence.items.len);
}
