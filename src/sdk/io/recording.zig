const std = @import("std");
const builtin = @import("builtin");
const misc = @import("../misc/root.zig");
const io = @import("root.zig");

const FieldIndex = u8;
const FieldPathLength = u8;
const FieldBitSize = u16;
const NumberOfFrames = u64;
const LocalField = struct {
    path: []const u8,
    access: []const AccessElement,
    Type: type,
    parent_index: ?FieldIndex,
    has_children: bool,
};
const AccessElement = union(enum) {
    struct_field: []const u8,
    array_index: usize,
    optional_payload: void,
    union_field: []const u8,
};
const RemoteField = struct {
    local_index: ?usize,
    bit_size: FieldBitSize,
};

const magic_number = "irony";
const max_number_of_fields = std.math.maxInt(FieldIndex);
const max_field_path_len = std.math.maxInt(FieldPathLength);
const path_separator = '.';
const path_separator_str = [1]u8{path_separator};
const optional_payload_path_component = "payload";
const pattern_wildcard = '?';

pub const RecordingConfig = struct {
    atomic_types: []const type = &.{},
    atomic_paths: []const []const u8 = &.{},
};

pub fn saveRecording(
    comptime Frame: type,
    frames: []const Frame,
    file_path: []const u8,
    comptime config: *const RecordingConfig,
) !void {
    const file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
        misc.error_context.new("Failed to create or open file: {s}", .{file_path});
        return err;
    };
    defer file.close();
    var buffer: [1024]u8 = undefined;
    var file_writer = file.writer(&buffer);
    var writer = io.BitWriter{ .byte_writer = &file_writer.interface };

    writer.writeBytes(magic_number) catch |err| {
        misc.error_context.new("Failed to write magic number.", .{});
        return err;
    };

    const fields = getLocalFields(Frame, config);
    writeFieldList(&writer, fields) catch |err| {
        misc.error_context.append("Failed to write field list.", .{});
        return err;
    };

    writeFrames(Frame, &writer, frames, fields) catch |err| {
        misc.error_context.append("Failed to write frames.", .{});
        return err;
    };

    writer.flush() catch |err| {
        misc.error_context.new("Failed to flush bit writer.", .{});
        return err;
    };
    file_writer.end() catch |err| {
        misc.error_context.new("Failed to end file writing.", .{});
        return err;
    };
}

pub fn loadRecording(
    comptime Frame: type,
    allocator: std.mem.Allocator,
    file_path: []const u8,
    comptime config: *const RecordingConfig,
) ![]Frame {
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        misc.error_context.new("Failed to open file: {s}", .{file_path});
        return err;
    };
    defer file.close();
    var buffer: [1024]u8 = undefined;
    var file_reader = file.reader(&buffer);
    var reader = io.BitReader{ .byte_reader = &file_reader.interface };

    var magic_buffer: [magic_number.len]u8 = undefined;
    reader.readBytes(&magic_buffer) catch |err| {
        misc.error_context.new("Failed to read magic number.", .{});
        return err;
    };
    if (!std.mem.eql(u8, &magic_buffer, magic_number)) {
        misc.error_context.new("Incorrect magic number.", .{});
        return error.MagicNumber;
    }

    const local_fields = getLocalFields(Frame, config);
    var remote_fields_buffer: [max_number_of_fields]RemoteField = undefined;
    const remote_fields = readFieldList(&reader, &remote_fields_buffer, local_fields) catch |err| {
        misc.error_context.append("Failed to read fields list.", .{});
        return err;
    };

    const frames = readFrames(Frame, allocator, &reader, remote_fields, local_fields) catch |err| {
        misc.error_context.append("Failed to read frames.", .{});
        return err;
    };

    return frames;
}

fn writeFieldList(writer: *io.BitWriter, comptime fields: []const LocalField) !void {
    writer.writeInt(FieldIndex, @intCast(fields.len)) catch |err| {
        misc.error_context.new("Failed to write number of fields: {}", .{fields.len});
        return err;
    };
    inline for (fields) |*field| {
        errdefer misc.error_context.append("Failed to write field: {s}", .{field.path});
        writer.writeInt(FieldPathLength, @intCast(field.path.len)) catch |err| {
            misc.error_context.new("Failed to write the size of field path: {}", .{field.path.len});
            return err;
        };
        writer.writeBytes(field.path) catch |err| {
            misc.error_context.new("Failed to write the field path: {s}", .{field.path});
            return err;
        };
        const bit_size: FieldBitSize = serializedBitSizeOf(field.Type);
        writer.writeInt(FieldBitSize, bit_size) catch |err| {
            misc.error_context.new("Failed to write the field bit size: {}", .{bit_size});
            return err;
        };
    }
}

fn readFieldList(
    reader: *io.BitReader,
    remote_fields_buffer: []RemoteField,
    comptime local_fields: []const LocalField,
) ![]RemoteField {
    const remote_fields_len = reader.readInt(FieldIndex) catch |err| {
        misc.error_context.new("Failed to read number of fields.", .{});
        return err;
    };
    if (remote_fields_len > remote_fields_buffer.len) {
        misc.error_context.new(
            "Number of fields {} exceeds maximum allowed number: {}",
            .{ remote_fields_len, remote_fields_buffer.len },
        );
        return error.TooManyFields;
    }
    for (0..remote_fields_len) |index| {
        errdefer misc.error_context.append("Failed to read field: {}", .{index});
        const path_len = reader.readInt(FieldPathLength) catch |err| {
            misc.error_context.new("Failed to read the size of the field path.", .{});
            return err;
        };
        var path_buffer: [max_field_path_len]u8 = undefined;
        const path = path_buffer[0..path_len];
        reader.readBytes(path) catch |err| {
            misc.error_context.new("Failed to read the field path.", .{});
            return err;
        };
        const remote_bit_size = reader.readInt(FieldBitSize) catch |err| {
            misc.error_context.new("Failed to read the field bit size. Field path is: {s}", .{path});
            return err;
        };
        inline for (local_fields, 0..) |*local_field, local_index| {
            const local_bit_size = serializedBitSizeOf(local_field.Type);
            if (std.mem.eql(u8, local_field.path, path) and local_bit_size == remote_bit_size) {
                remote_fields_buffer[index] = .{
                    .local_index = local_index,
                    .bit_size = remote_bit_size,
                };
                break;
            }
        } else {
            remote_fields_buffer[index] = .{
                .local_index = null,
                .bit_size = remote_bit_size,
            };
        }
    }
    return remote_fields_buffer[0..remote_fields_len];
}

fn writeFrames(
    comptime Frame: type,
    writer: *io.BitWriter,
    frames: []const Frame,
    comptime fields: []const LocalField,
) !void {
    writer.writeInt(NumberOfFrames, @intCast(frames.len)) catch |err| {
        misc.error_context.new("Failed to write number of frames: {}", .{frames.len});
        return err;
    };
    for (frames, 0..) |*frame, frame_index| {
        errdefer misc.error_context.append("Failed to write frame: {}", .{frame_index});
        const changes = switch (frame_index) {
            0 => getInitialChanges(fields),
            else => findFieldChanges(Frame, frame, &frames[frame_index - 1], fields),
        };
        writer.writeInt(FieldIndex, changes.number_of_changes) catch |err| {
            misc.error_context.new("Failed to write number of changes: {}", .{changes.number_of_changes});
            return err;
        };
        inline for (fields, 0..) |*field, field_index| {
            if (changes.field_changed[field_index]) {
                errdefer misc.error_context.append("Failed to write change for field: {s}", .{field.path});
                writer.writeInt(FieldIndex, @intCast(field_index)) catch |err| {
                    misc.error_context.new("Failed to write field index: {}", .{field_index});
                    return err;
                };
                const field_pointer = getConstFieldPointer(frame, field) catch unreachable;
                writeValue(writer, field_pointer) catch |err| {
                    misc.error_context.append("Failed to write the new value.", .{});
                    return err;
                };
            }
        }
    }
}

fn Changes(comptime len: usize) type {
    return struct {
        number_of_changes: FieldIndex,
        field_changed: [len]bool,
    };
}

inline fn getInitialChanges(comptime fields: []const LocalField) Changes(fields.len) {
    comptime {
        var number_of_changes: FieldIndex = 0;
        var field_changed: [fields.len]bool = undefined;
        for (fields, 0..) |*field, field_index| {
            // Ancestors already store the initial value for descendants.
            // There is no need to duplicate that data in the descendants.
            const changed = field.parent_index == null;
            field_changed[field_index] = changed;
            if (changed) {
                number_of_changes += 1;
            }
        }
        return .{
            .number_of_changes = number_of_changes,
            .field_changed = field_changed,
        };
    }
}

fn findFieldChanges(
    comptime Frame: type,
    frame_1: *const Frame,
    frame_2: *const Frame,
    comptime fields: []const LocalField,
) Changes(fields.len) {
    const parent_indices = comptime block: {
        var array: [fields.len]?FieldIndex = undefined;
        for (&array, fields) |*element, *field| {
            element.* = field.parent_index;
        }
        break :block array;
    };
    var number_of_changes: FieldIndex = 0;
    var field_changed: [fields.len]bool = [1]bool{false} ** fields.len;
    inline for (fields, 0..) |*field, field_index| {
        var ancestor_changed = false;
        var ancestor_index = parent_indices[field_index];
        while (ancestor_index) |index| {
            if (field_changed[index]) {
                ancestor_changed = true;
                break;
            }
            ancestor_index = parent_indices[index];
        }
        if (!ancestor_changed) { // Ancestor change supplies changes for all descendants. No need to duplicate changes.
            if (getConstFieldPointer(frame_1, field) catch null) |field_pointer_1| {
                if (getConstFieldPointer(frame_2, field) catch null) |field_pointer_2| {
                    if (!field.has_children) { // Leaf nodes are the regular nodes that change when their raw value changes.
                        if (!areValuesEqual(field_pointer_1.*, field_pointer_2.*)) {
                            field_changed[field_index] = true;
                            number_of_changes += 1;
                        }
                    } else switch (@typeInfo(field.Type)) { // Only optionals and tagged unions can have children.
                        .optional => {
                            // Optional root nodes need to change only when transitioning from and to a null value.
                            // If only the payload changes, descendant nodes are responsible to store these changes.
                            const changed = (field_pointer_1.* == null and field_pointer_2.* != null) or
                                (field_pointer_1.* != null and field_pointer_2.* == null);
                            if (changed) {
                                field_changed[field_index] = true;
                                number_of_changes += 1;
                            }
                        },
                        .@"union" => |*info| {
                            // Tagged union root node needs to change only when union's tag changes.
                            // If only the payload changes, descendant nodes are responsible to store these changes.
                            if (info.tag_type == null) {
                                @compileError(
                                    "Expected optional type or a tagged union but got: " ++ @typeName(field.Type),
                                );
                            }
                            const tag_1 = std.meta.activeTag(field_pointer_1.*);
                            const tag_2 = std.meta.activeTag(field_pointer_2.*);
                            if (tag_1 != tag_2) {
                                field_changed[field_index] = true;
                                number_of_changes += 1;
                            }
                        },
                        else => @compileError(
                            "Expected optional type or a tagged union but got: " ++ @typeName(field.Type),
                        ),
                    }
                }
            }
        }
    }
    return .{
        .number_of_changes = number_of_changes,
        .field_changed = field_changed,
    };
}

fn areValuesEqual(value_1: anytype, value_2: @TypeOf(value_1)) bool {
    const Type = @TypeOf(value_1);
    return switch (@typeInfo(Type)) {
        .@"union" => |*info| switch (info.layout) {
            .@"packed" => {
                const IntType = @Type(.{ .int = .{ .signedness = .unsigned, .bits = @bitSizeOf(Type) } });
                const int_1: IntType = @bitCast(value_1);
                const int_2: IntType = @bitCast(value_2);
                return int_1 == int_2;
            },
            else => std.meta.eql(value_1, value_2),
        },
        else => std.meta.eql(value_1, value_2),
    };
}

fn readFrames(
    comptime Frame: type,
    allocator: std.mem.Allocator,
    reader: *io.BitReader,
    remote_fields: []const RemoteField,
    comptime local_fields: []const LocalField,
) ![]Frame {
    const number_of_frames = reader.readInt(NumberOfFrames) catch |err| {
        misc.error_context.new("Failed to read number of frames.", .{});
        return err;
    };
    const frames = allocator.alloc(Frame, number_of_frames) catch |err| {
        misc.error_context.new(
            "Failed to allocate enough memory to store the recording frames. Number of frames is: {}",
            .{number_of_frames},
        );
        return err;
    };
    var current_frame = Frame{};
    for (0..number_of_frames) |frame_index| {
        errdefer misc.error_context.append("Failed read frame: {}", .{frame_index});
        const number_of_changes = reader.readInt(FieldIndex) catch |err| {
            misc.error_context.new("Failed to read number changes.", .{});
            return err;
        };
        for (0..number_of_changes) |change_index| {
            errdefer misc.error_context.append("Failed read change: {}", .{change_index});
            const remote_index = reader.readInt(FieldIndex) catch |err| {
                misc.error_context.new("Failed to read field index.", .{});
                return err;
            };
            if (remote_index >= remote_fields.len) {
                misc.error_context.new(
                    "Field index {} is out of bounds. Number of fields is: {}",
                    .{ remote_index, remote_fields.len },
                );
                return error.IndexOutOfBounds;
            }
            const remote_field = remote_fields[remote_index];
            const local_index = remote_field.local_index orelse {
                reader.skip(remote_field.bit_size) catch |err| {
                    misc.error_context.append("Failed to discard unknown field's data.", .{});
                    return err;
                };
                continue;
            };
            inline for (local_fields, 0..) |*local_field, index| {
                if (index == local_index) {
                    if (readValue(local_field.Type, reader)) |field_value| {
                        if (getFieldPointer(&current_frame, local_field)) |field_pointer| {
                            field_pointer.* = field_value;
                        } else |err| {
                            misc.error_context.append("Failed to access field: {s}", .{local_field.path});
                            if (!builtin.is_test) {
                                misc.error_context.logWarning(err);
                            }
                            setFieldToDefaultValue(Frame, &current_frame, index, local_fields);
                        }
                    } else |err| {
                        misc.error_context.append("Failed to read the new value of: {s}", .{local_field.path});
                        if (err == error.InvalidValue) {
                            if (!builtin.is_test) {
                                misc.error_context.logWarning(err);
                            }
                            setFieldToDefaultValue(Frame, &current_frame, index, local_fields);
                        } else {
                            return err;
                        }
                    }
                    break;
                }
            } else unreachable;
        }
        frames[frame_index] = current_frame;
    }
    return frames;
}

fn setFieldToDefaultValue(
    comptime Frame: type,
    frame: *Frame,
    field_index: FieldIndex,
    comptime fields: []const LocalField,
) void {
    const default_frame = Frame{};
    var next_index: ?FieldIndex = field_index;
    while (next_index) |current_index| {
        inline for (fields, 0..) |*field, index| {
            if (index == current_index) {
                if (getFieldPointer(frame, field) catch null) |field_pointer| {
                    if (getConstFieldPointer(&default_frame, field) catch null) |default_field_pointer| {
                        field_pointer.* = default_field_pointer.*;
                        return;
                    }
                }
                next_index = field.parent_index;
                break;
            }
        } else unreachable;
    }
}

fn writeValue(writer: *io.BitWriter, value_pointer: anytype) !void {
    const Type = switch (@typeInfo(@TypeOf(value_pointer))) {
        .pointer => |info| info.child,
        else => @compileError("Expected value_pointer to be a pointer but got: " ++ @typeName(@TypeOf(value_pointer))),
    };
    const start_pos = writer.absolute_position;
    defer {
        const end_pos = writer.absolute_position;
        std.debug.assert(end_pos - start_pos == serializedBitSizeOf(Type));
    }
    switch (@typeInfo(Type)) {
        .void => {},
        .bool => {
            const value = value_pointer.*;
            writer.writeBool(value_pointer.*) catch |err| {
                misc.error_context.new("Failed to write bool: {}", .{value});
                return err;
            };
        },
        .int => {
            const value = value_pointer.*;
            writer.writeInt(Type, value) catch |err| {
                misc.error_context.new("Failed to write int: {} ({s})", .{ value, @typeName(Type) });
                return err;
            };
        },
        .float => {
            const value = value_pointer.*;
            writer.writeFloat(Type, value) catch |err| {
                misc.error_context.new("Failed to write float: {} ({s})", .{ value, @typeName(Type) });
                return err;
            };
        },
        .@"enum" => |*info| {
            const Tag = info.tag_type;
            const value = value_pointer.*;
            const tag: Tag = @intFromEnum(value);
            writeValue(writer, &tag) catch |err| {
                misc.error_context.append(
                    "Failed to write enum tag: {s} ({s}) -> {} ({s})",
                    .{ @tagName(value), @typeName(Type), tag, @typeName(Tag) },
                );
                return err;
            };
        },
        .optional => |*info| {
            if (value_pointer.*) |*child_pointer| {
                writer.writeBool(true) catch |err| {
                    misc.error_context.new("Failed to write optional's tag bit: 1", .{});
                    return err;
                };
                writeValue(writer, child_pointer) catch |err| {
                    misc.error_context.append("Failed to write optional's payload.", .{});
                    return err;
                };
            } else {
                writer.writeBool(false) catch |err| {
                    misc.error_context.new("Failed to write optional's tag bit: 0", .{});
                    return err;
                };
                writer.writeZeroes(serializedBitSizeOf(info.child)) catch |err| {
                    misc.error_context.new("Failed to write optional's null padding.", .{});
                    return err;
                };
            }
        },
        .array => {
            for (value_pointer, 0..) |*element_pointer, index| {
                writeValue(writer, element_pointer) catch |err| {
                    misc.error_context.append("Failed to write array element on index: {}", .{index});
                    return err;
                };
            }
        },
        .@"struct" => |*info| if (info.backing_integer) |IntType| {
            const int_pointer: *const IntType = @ptrCast(value_pointer);
            writeValue(writer, int_pointer) catch |err| {
                misc.error_context.append(
                    "Failed to write packed struct backing int: {} ({s})",
                    .{ int_pointer.*, @typeName(IntType) },
                );
                return err;
            };
        } else {
            inline for (info.fields) |*field| {
                const field_pointer = &@field(value_pointer, field.name);
                writeValue(writer, field_pointer) catch |err| {
                    misc.error_context.append("Failed to write struct field: {s}", .{field.name});
                    return err;
                };
            }
        },
        .@"union" => |*info| if (info.layout == .@"packed") {
            const IntType = @Type(.{ .int = .{ .signedness = .unsigned, .bits = @bitSizeOf(Type) } });
            const int_pointer: *const IntType = @ptrCast(value_pointer);
            writeValue(writer, int_pointer) catch |err| {
                misc.error_context.append(
                    "Failed to write packed union backing int: {} ({s})",
                    .{ int_pointer.*, @typeName(IntType) },
                );
                return err;
            };
        } else {
            const Tag = info.tag_type orelse {
                @compileError("Union " ++ @typeName(Type) ++ " is not serializable. (Not tagged and not packed.)");
            };
            const tag = std.meta.activeTag(value_pointer.*);
            writeValue(writer, &tag) catch |err| {
                misc.error_context.append("Failed to write union's tag: {s}", .{@tagName(value_pointer.*)});
                return err;
            };
            switch (value_pointer.*) {
                inline else => |*payload_pointer| {
                    const Payload = @TypeOf(payload_pointer.*);
                    writeValue(writer, payload_pointer) catch |err| {
                        misc.error_context.append("Failed to write union's payload: {s}", .{@tagName(value_pointer.*)});
                        return err;
                    };
                    const padding_size = serializedBitSizeOf(Type) - serializedBitSizeOf(Tag) - serializedBitSizeOf(Payload);
                    writer.writeZeroes(padding_size) catch |err| {
                        misc.error_context.new("Failed to write union's padding.", .{});
                        return err;
                    };
                },
            }
        },
        else => @compileError("Unsupported type: " ++ @typeName(Type)),
    }
}

fn readValue(comptime Type: type, reader: *io.BitReader) anyerror!Type {
    const start_pos = reader.absolute_position;
    defer {
        const end_pos = reader.absolute_position;
        const target_end_pos = start_pos + serializedBitSizeOf(Type);
        if (target_end_pos > end_pos) {
            // If the value read fails,
            // the reader still needs to position itself correctly to read the rest of the file.
            reader.skip(target_end_pos - end_pos) catch {};
        }
    }
    switch (@typeInfo(Type)) {
        .void => return {},
        .bool => {
            return reader.readBool() catch |err| {
                misc.error_context.new("Failed to read bool's byte.", .{});
                return err;
            };
        },
        .int => {
            return reader.readInt(Type) catch |err| {
                misc.error_context.new("Failed to read int. ({s})", .{@typeName(Type)});
                return err;
            };
        },
        .float => {
            return reader.readFloat(Type) catch |err| {
                misc.error_context.new("Failed to read float. ({s})", .{@typeName(Type)});
                return err;
            };
        },
        .@"enum" => |*info| {
            const Tag = info.tag_type;
            const tag = readValue(Tag, reader) catch |err| {
                misc.error_context.append("Failed to read enum tag. ({s} -> {s})", .{ @typeName(Type), @typeName(Tag) });
                return err;
            };
            inline for (info.fields) |*field| {
                if (field.value == tag) {
                    return @enumFromInt(tag);
                }
            }
            misc.error_context.new("Invalid enum tag: {} ({s} -> {s})", .{ tag, @typeName(Type), @typeName(Tag) });
            return error.InvalidValue;
        },
        .optional => |*info| {
            const is_present = reader.readBool() catch |err| {
                misc.error_context.new("Failed to read optional's tag bit.", .{});
                return err;
            };
            if (is_present) {
                return readValue(info.child, reader) catch |err| {
                    misc.error_context.append("Failed to read optional's payload.", .{});
                    return err;
                };
            } else {
                reader.skip(serializedBitSizeOf(info.child)) catch |err| {
                    misc.error_context.append("Failed to skip null optional's payload.", .{});
                    return err;
                };
                return null;
            }
        },
        .array => |*info| {
            var value: Type = undefined;
            for (&value, 0..) |*element, index| {
                element.* = readValue(info.child, reader) catch |err| {
                    misc.error_context.append("Failed to read array element at index: {}", .{index});
                    return err;
                };
            }
            return value;
        },
        .@"struct" => |*info| if (info.backing_integer) |IntType| {
            const int_value = readValue(IntType, reader) catch |err| {
                misc.error_context.append(
                    "Failed to read packed struct's backing integer. ({s})",
                    .{@typeName(IntType)},
                );
                return err;
            };
            return @bitCast(int_value);
        } else {
            var value: Type = undefined;
            inline for (info.fields) |*field| {
                const field_value = readValue(field.type, reader) catch |err| {
                    misc.error_context.append("Failed to read struct field: {s}", .{field.name});
                    return err;
                };
                @field(value, field.name) = field_value;
            }
            return value;
        },
        .@"union" => |info| if (info.layout == .@"packed") {
            const IntType = @Type(.{ .int = .{ .signedness = .unsigned, .bits = @bitSizeOf(Type) } });
            const int_value = readValue(IntType, reader) catch |err| {
                misc.error_context.append(
                    "Failed to read packed unions's backing integer. ({s})",
                    .{@typeName(IntType)},
                );
                return err;
            };
            return @bitCast(int_value);
        } else {
            const Tag = info.tag_type orelse {
                @compileError("Union " ++ @typeName(Type) ++ " is not serializable. (Not tagged and not packed.)");
            };
            const tag = readValue(Tag, reader) catch |err| {
                misc.error_context.append("Failed to read union's tag. ({s})", .{@typeName(Tag)});
                return err;
            };
            inline for (info.fields) |*field| {
                if (std.mem.eql(u8, @tagName(tag), field.name)) {
                    const Payload = field.type;
                    const payload = readValue(Payload, reader) catch |err| {
                        misc.error_context.append("Failed to read union's payload.", .{});
                        return err;
                    };
                    const padding_size = serializedBitSizeOf(Type) - serializedBitSizeOf(Tag) - serializedBitSizeOf(Payload);
                    reader.skip(padding_size) catch |err| {
                        misc.error_context.append("Failed to skip union's padding.", .{});
                        return err;
                    };
                    return @unionInit(Type, field.name, payload);
                }
            }
            return error.InvalidValue;
        },
        else => @compileError("Unsupported type: " ++ @typeName(Type)),
    }
}

fn serializedBitSizeOf(comptime Type: type) comptime_int {
    return switch (@typeInfo(Type)) {
        .void => 0,
        .bool => 1,
        .int => |*info| info.bits,
        .float => |*info| info.bits,
        .@"enum" => |*info| serializedBitSizeOf(info.tag_type),
        .optional => |*info| serializedBitSizeOf(bool) + serializedBitSizeOf(info.child),
        .array => |*info| info.len * serializedBitSizeOf(info.child),
        .@"struct" => |*info| {
            if (info.backing_integer) |IntType| {
                return serializedBitSizeOf(IntType);
            }
            var sum: usize = 0;
            for (info.fields) |*field| {
                sum += serializedBitSizeOf(field.type);
            }
            return sum;
        },
        .@"union" => |*info| {
            if (info.layout == .@"packed") {
                const IntType = @Type(.{ .int = .{ .signedness = .unsigned, .bits = @bitSizeOf(Type) } });
                return serializedBitSizeOf(IntType);
            }
            const Tag = info.tag_type orelse {
                @compileError("Union " ++ @typeName(Type) ++ " is not serializable. (Not tagged and not packed.)");
            };
            var max: usize = 0;
            inline for (info.fields) |*field| {
                max = @max(max, serializedBitSizeOf(field.type));
            }
            return serializedBitSizeOf(Tag) + max;
        },
        else => @compileError("Unsupported type: " ++ @typeName(Type)),
    };
}

fn getFieldPointer(frame: anytype, comptime field: *const LocalField) error{Inaccessible}!*field.Type {
    return getFieldPointerRecursive(*field.Type, frame, field.access);
}

fn getConstFieldPointer(frame: anytype, comptime field: *const LocalField) error{Inaccessible}!*const field.Type {
    return getFieldPointerRecursive(*const field.Type, frame, field.access);
}

fn getFieldPointerRecursive(
    comptime Pointer: type,
    lhs_pointer: anytype,
    comptime access: []const AccessElement,
) error{Inaccessible}!Pointer {
    if (@typeInfo(Pointer) != .pointer) {
        @compileError("Expected Pointer to be a pointer type but got: " ++ @typeName(Pointer));
    }
    if (@typeInfo(@TypeOf(lhs_pointer)) != .pointer) {
        @compileError("Expected lhs_pointer to be a pointer but got: " ++ @typeName(@TypeOf(lhs_pointer)));
    }
    if (access.len == 0) {
        return lhs_pointer;
    }
    const next_pointer = switch (access[0]) {
        .struct_field => |name| &@field(lhs_pointer, name),
        .array_index => |index| &lhs_pointer[index],
        .optional_payload => if (lhs_pointer.*) |*pointer| pointer else {
            misc.error_context.new("Optional value is null.", .{});
            misc.error_context.append("Failed to access the optional's payload.", .{});
            return error.Inaccessible;
        },
        .union_field => |name| block: {
            const expected_tag = @field(std.meta.Tag(@TypeOf(lhs_pointer.*)), name);
            const actual_tag = std.meta.activeTag(lhs_pointer.*);
            if (actual_tag == expected_tag) {
                break :block &@field(lhs_pointer, name);
            } else {
                misc.error_context.new(
                    "Expected tagged union to have tag {s}, but actual tag is {s}.",
                    .{ @tagName(expected_tag), @tagName(actual_tag) },
                );
                misc.error_context.append("Failed to access tagged union field: {s}", .{name});
                return error.Inaccessible;
            }
        },
    };
    const next_access = access[1..];
    return getFieldPointerRecursive(Pointer, next_pointer, next_access) catch |err| {
        switch (access[0]) {
            .struct_field => |name| misc.error_context.append("Access failure inside struct field: {s}", .{name}),
            .array_index => |index| misc.error_context.append("Access failure inside array index: {}", .{index}),
            .optional_payload => misc.error_context.append("Access failure inside optional payload.", .{}),
            .union_field => |name| misc.error_context.append("Access failure inside tagged union field: {s}", .{name}),
        }
        return err;
    };
}

const GetLocalFieldsState = struct {
    fields_buffer: []LocalField,
    fields_len: *usize,
    atomic_type_usage: []bool,
    atomic_path_usage: []bool,
};

inline fn getLocalFields(comptime Frame: type, comptime config: *const RecordingConfig) []const LocalField {
    comptime {
        @setEvalBranchQuota(100000);

        var fields_buffer: [max_number_of_fields]LocalField = undefined;
        var fields_len: usize = 0;
        var atomic_type_usage = [1]bool{false} ** config.atomic_types.len;
        var atomic_path_usage = [1]bool{false} ** config.atomic_paths.len;

        const field = LocalField{
            .path = "",
            .access = &.{},
            .Type = Frame,
            .parent_index = null,
            .has_children = false,
        };
        const state = GetLocalFieldsState{
            .fields_buffer = &fields_buffer,
            .fields_len = &fields_len,
            .atomic_type_usage = &atomic_type_usage,
            .atomic_path_usage = &atomic_path_usage,
        };
        getLocalFieldsRecursive(config, &field, &state);

        for (atomic_type_usage, 0..) |is_used, index| {
            if (!is_used) {
                const Type = config.atomic_types[index];
                @compileError("Unused atomic type in configuration: " ++ @typeName(Type));
            }
        }
        for (atomic_path_usage, 0..) |is_used, index| {
            if (!is_used) {
                const path = config.atomic_paths[index];
                @compileError("Unused atomic path in configuration: " ++ path);
            }
        }

        const fields = fields_buffer[0..fields_len].*;
        return &fields;
    }
}

fn getLocalFieldsRecursive(
    comptime config: *const RecordingConfig,
    field: *const LocalField,
    state: *const GetLocalFieldsState,
) void {
    for (config.atomic_types, 0..) |AtomicType, index| {
        if (AtomicType != field.Type) {
            continue;
        }
        addLocalField(field, state);
        state.atomic_type_usage[index] = true;
        return;
    }
    for (config.atomic_paths, 0..) |pattern, index| {
        if (!doesPathMatchPattern(field.path, pattern)) {
            continue;
        }
        addLocalField(field, state);
        state.atomic_path_usage[index] = true;
        return;
    }
    switch (@typeInfo(field.Type)) {
        .void => {},
        .bool, .int, .float, .@"enum" => {
            addLocalField(field, state);
        },
        .@"struct" => |*info| if (info.layout == .@"packed") {
            addLocalField(field, state);
        } else {
            for (info.fields) |*struct_field| {
                const sub_field = LocalField{
                    .path = if (field.path.len == 0) block: {
                        break :block struct_field.name;
                    } else block: {
                        break :block field.path ++ path_separator_str ++ struct_field.name;
                    },
                    .access = field.access ++ &[1]AccessElement{.{ .struct_field = struct_field.name }},
                    .Type = struct_field.type,
                    .parent_index = field.parent_index,
                    .has_children = false,
                };
                getLocalFieldsRecursive(config, &sub_field, state);
            }
        },
        .array => |*info| {
            inline for (0..info.len) |index| {
                const sub_field = LocalField{
                    .path = if (field.path.len == 0) block: {
                        break :block std.fmt.comptimePrint("{}", .{index});
                    } else block: {
                        break :block std.fmt.comptimePrint("{s}{s}{}", .{ field.path, path_separator_str, index });
                    },
                    .access = field.access ++ &[1]AccessElement{.{ .array_index = index }},
                    .Type = info.child,
                    .parent_index = field.parent_index,
                    .has_children = false,
                };
                getLocalFieldsRecursive(config, &sub_field, state);
            }
        },
        .optional => |*info| {
            const root_index = state.fields_len.*;
            const root_field = LocalField{
                .path = field.path,
                .access = field.access,
                .Type = field.Type,
                .parent_index = field.parent_index,
                .has_children = true,
            };
            addLocalField(&root_field, state);
            const sub_field = LocalField{
                .path = if (field.path.len == 0) block: {
                    break :block optional_payload_path_component;
                } else block: {
                    break :block field.path ++ path_separator_str ++ optional_payload_path_component;
                },
                .access = field.access ++ &[1]AccessElement{.optional_payload},
                .Type = info.child,
                .parent_index = root_index,
                .has_children = false,
            };
            getLocalFieldsRecursive(config, &sub_field, state);
        },
        .@"union" => |*info| if (info.layout == .@"packed") {
            addLocalField(field, state);
        } else {
            if (info.tag_type == null) {
                @compileError("Union " ++ @typeName(field.Type) ++ " is not serializable. (Not tagged and not packed.)");
            }
            const root_index = state.fields_len.*;
            const root_field = LocalField{
                .path = field.path,
                .access = field.access,
                .Type = field.Type,
                .parent_index = field.parent_index,
                .has_children = true,
            };
            addLocalField(&root_field, state);
            for (info.fields) |*union_field| {
                const sub_field = LocalField{
                    .path = if (field.path.len == 0) block: {
                        break :block union_field.name;
                    } else block: {
                        break :block field.path ++ path_separator_str ++ union_field.name;
                    },
                    .access = field.access ++ &[1]AccessElement{.{ .union_field = union_field.name }},
                    .Type = union_field.type,
                    .parent_index = root_index,
                    .has_children = false,
                };
                getLocalFieldsRecursive(config, &sub_field, state);
            }
        },
        else => @compileError("Unsupported type: " ++ @typeName(field.Type)),
    }
}

fn addLocalField(field: *const LocalField, state: *const GetLocalFieldsState) void {
    if (state.fields_len.* >= state.fields_buffer.len) {
        @compileError("Maximum number of fields exceeded.");
    }
    if (field.path.len > max_field_path_len) {
        @compileError("Maximum size of field path exceeded.");
    }
    state.fields_buffer[state.fields_len.*] = field.*;
    state.fields_len.* += 1;
}

fn doesPathMatchPattern(path: []const u8, pattern: []const u8) bool {
    const State = enum { normal, wildcard };
    var state: State = .normal;
    var pattern_index: usize = 0;
    for (path) |path_char| {
        switch (state) {
            .normal => {
                if (pattern_index >= pattern.len) {
                    return false;
                }
                const pattern_char = pattern[pattern_index];
                if (pattern_char == pattern_wildcard) {
                    state = .wildcard;
                } else if (path_char != pattern_char) {
                    return false;
                }
                pattern_index += 1;
            },
            .wildcard => {
                if (path_char == path_separator) {
                    state = .normal;
                    pattern_index += 1;
                }
            },
        }
    }
    return pattern_index == pattern.len;
}

const testing = std.testing;

test "loadRecording should load the same recording that saveRecording saved" {
    const Frame = struct {
        bool: bool = false,
        u8: u8 = 0,
        u16: u16 = 0,
        u32: u32 = 0,
        u64: u64 = 0,
        i8: i8 = 0,
        i16: i16 = 0,
        i32: i32 = 0,
        i64: i64 = 0,
        f32: f32 = 0,
        f64: f64 = 0,
        optional: ?f32 = 0,
        @"enum": enum { a, b } = .a,
        @"struct": struct { a: f32 = 0, b: f32 = 0 } = .{},
        packed_struct: packed struct { a: u18 = 0, b: u14 = 0 } = .{},
        tuple: struct { f32, f32 } = .{ 0, 0 },
        array: [2]f32 = .{ 0, 0 },
        tagged_union: union(enum) { i: i32, f: f32 } = .{ .i = 0 },
        array_of_struct: [2]struct { a: f32 = 0, b: f32 = 0 } = .{ .{}, .{} },
        struct_of_array: struct { a: [2]f32 = .{ 0, 0 }, b: [2]f32 = .{ 0, 0 } } = .{},
    };
    const saved_recording = [_]Frame{
        .{
            .bool = false,
            .u8 = 1,
            .u16 = 2,
            .u32 = 3,
            .u64 = 4,
            .i8 = -1,
            .i16 = -2,
            .i32 = -3,
            .i64 = -4,
            .f32 = 0.1,
            .f64 = 0.2,
            .optional = null,
            .@"enum" = .a,
            .@"struct" = .{ .a = 1, .b = 2 },
            .packed_struct = .{ .a = 3, .b = 4 },
            .tuple = .{ 5, 6 },
            .array = .{ 7, 8 },
            .tagged_union = .{ .i = 9 },
            .array_of_struct = .{ .{ .a = 10, .b = 11 }, .{ .a = 12, .b = 13 } },
            .struct_of_array = .{ .a = .{ 14, 15 }, .b = .{ 16, 17 } },
        },
        .{
            .bool = true,
            .u8 = 4,
            .u16 = 3,
            .u32 = 2,
            .u64 = 1,
            .i8 = -4,
            .i16 = -3,
            .i32 = -2,
            .i64 = -1,
            .f32 = 0.2,
            .f64 = 0.1,
            .optional = 123,
            .@"enum" = .b,
            .@"struct" = .{ .a = 17, .b = 16 },
            .packed_struct = .{ .a = 15, .b = 41 },
            .array = .{ 13, 12 },
            .tuple = .{ 11, 10 },
            .tagged_union = .{ .f = 9 },
            .array_of_struct = .{ .{ .a = 8, .b = 7 }, .{ .a = 6, .b = 5 } },
            .struct_of_array = .{ .a = .{ 4, 3 }, .b = .{ 2, 1 } },
        },
    };
    try saveRecording(Frame, &saved_recording, "./test_assets/recording.irony", &.{});
    defer std.fs.cwd().deleteFile("./test_assets/recording.irony") catch @panic("Failed to cleanup test file.");
    const loaded_recording = try loadRecording(Frame, testing.allocator, "./test_assets/recording.irony", &.{});
    defer testing.allocator.free(loaded_recording);
    try testing.expectEqualSlices(Frame, &saved_recording, loaded_recording);
}

test "saveRecording should overwrite the file if it already exists" {
    const Frame = struct { a: f32 = 0 };
    try saveRecording(Frame, &.{
        .{ .a = 1 },
        .{ .a = 2 },
        .{ .a = 3 },
    }, "./test_assets/recording.irony", &.{});
    defer std.fs.cwd().deleteFile("./test_assets/recording.irony") catch @panic("Failed to cleanup test file.");
    try saveRecording(Frame, &.{
        .{ .a = 2 },
        .{ .a = 3 },
        .{ .a = 4 },
    }, "./test_assets/recording.irony", &.{});
    const recording = try loadRecording(Frame, testing.allocator, "./test_assets/recording.irony", &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(Frame, &.{
        .{ .a = 2 },
        .{ .a = 3 },
        .{ .a = 4 },
    }, recording);
}

test "loadRecording should succeed when when recording has more fields then expected" {
    const SavedFrame = struct { a: f32 = -1, b: f32 = -2 };
    const LoadedFrame = struct { a: f32 = -3 };
    try saveRecording(SavedFrame, &.{
        .{ .a = 1, .b = 2 },
        .{ .a = 3, .b = 4 },
        .{ .a = 5, .b = 6 },
    }, "./test_assets/recording.irony", &.{});
    defer std.fs.cwd().deleteFile("./test_assets/recording.irony") catch @panic("Failed to cleanup test file.");
    const recording = try loadRecording(LoadedFrame, testing.allocator, "./test_assets/recording.irony", &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .a = 1 },
        .{ .a = 3 },
        .{ .a = 5 },
    }, recording);
}

test "loadRecording should load default value when recording does not contain a value" {
    const SavedFrame = struct { a: f32 = -1 };
    const LoadedFrame = struct { a: f32 = -2, b: f32 = -3 };
    try saveRecording(SavedFrame, &.{
        .{ .a = 1 },
        .{ .a = 2 },
        .{ .a = 3 },
    }, "./test_assets/recording.irony", &.{});
    defer std.fs.cwd().deleteFile("./test_assets/recording.irony") catch @panic("Failed to cleanup test file.");
    const recording = try loadRecording(LoadedFrame, testing.allocator, "./test_assets/recording.irony", &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .a = 1, .b = -3 },
        .{ .a = 2, .b = -3 },
        .{ .a = 3, .b = -3 },
    }, recording);
}

test "loadRecording should use default value when a field has different size then expected" {
    const SavedFrame = struct { a: f32 = -1, b: f64 = -2 };
    const LoadedFrame = struct { a: f32 = -3, b: f32 = -4 };
    try saveRecording(SavedFrame, &.{
        .{ .a = 1, .b = 2 },
        .{ .a = 3, .b = 4 },
        .{ .a = 5, .b = 6 },
    }, "./test_assets/recording.irony", &.{});
    defer std.fs.cwd().deleteFile("./test_assets/recording.irony") catch @panic("Failed to cleanup test file.");
    const recording = try loadRecording(LoadedFrame, testing.allocator, "./test_assets/recording.irony", &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .a = 1, .b = -4 },
        .{ .a = 3, .b = -4 },
        .{ .a = 5, .b = -4 },
    }, recording);
}

test "loadRecording should use default value when encountering invalid enum value" {
    const Enum = enum(u8) { a = 0, b = 1 };
    const SavedFrame = struct { a: u8 = 0, b: ?u8 = null };
    const LoadedFrame = struct { a: Enum = .a, b: ?Enum = null };
    try saveRecording(SavedFrame, &.{
        .{ .a = 0, .b = null },
        .{ .a = 0, .b = 0 },
        .{ .a = 1, .b = 1 },
        .{ .a = 2, .b = 2 },
    }, "./test_assets/recording.irony", &.{});
    defer std.fs.cwd().deleteFile("./test_assets/recording.irony") catch @panic("Failed to cleanup test file.");
    const recording = try loadRecording(LoadedFrame, testing.allocator, "./test_assets/recording.irony", &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .a = .a, .b = null },
        .{ .a = .a, .b = .a },
        .{ .a = .b, .b = .b },
        .{ .a = .a, .b = null },
    }, recording);
}

test "loadRecording should use default value when encountering invalid tagged union" {
    const TagAndPayload = packed struct { tag: u8 = 0xFF, payload: u16 = 0xFFFF };
    const Tag = enum(u8) { a = 1, b = 2 };
    const Union = union(Tag) { a: u8, b: u16 };
    const SavedFrame = struct { f1: TagAndPayload = .{}, f2: TagAndPayload = .{} };
    const LoadedFrame = struct { f1: Union = .{ .a = 128 }, f2: Union = .{ .b = 129 } };
    try testing.expectEqual(serializedBitSizeOf(Union), serializedBitSizeOf(TagAndPayload));
    try saveRecording(SavedFrame, &.{
        .{ .f1 = .{ .tag = 0, .payload = 0 }, .f2 = .{ .tag = 0, .payload = 0 } },
        .{ .f1 = .{ .tag = 1, .payload = 0 }, .f2 = .{ .tag = 1, .payload = 0 } },
        .{ .f1 = .{ .tag = 1, .payload = 1 }, .f2 = .{ .tag = 1, .payload = 1 } },
        .{ .f1 = .{ .tag = 2, .payload = 0 }, .f2 = .{ .tag = 2, .payload = 0 } },
        .{ .f1 = .{ .tag = 2, .payload = 1 }, .f2 = .{ .tag = 2, .payload = 1 } },
        .{ .f1 = .{ .tag = 3, .payload = 0 }, .f2 = .{ .tag = 3, .payload = 0 } },
        .{ .f1 = .{ .tag = 1, .payload = 255 }, .f2 = .{ .tag = 1, .payload = 255 } },
        .{ .f1 = .{ .tag = 1, .payload = 256 }, .f2 = .{ .tag = 1, .payload = 256 } },
        .{ .f1 = .{ .tag = 2, .payload = 255 }, .f2 = .{ .tag = 2, .payload = 255 } },
        .{ .f1 = .{ .tag = 2, .payload = 256 }, .f2 = .{ .tag = 2, .payload = 256 } },
    }, "./test_assets/recording.irony", &.{});
    defer std.fs.cwd().deleteFile("./test_assets/recording.irony") catch @panic("Failed to cleanup test file.");
    const recording = try loadRecording(LoadedFrame, testing.allocator, "./test_assets/recording.irony", &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .f1 = .{ .a = 128 }, .f2 = .{ .b = 129 } },
        .{ .f1 = .{ .a = 0 }, .f2 = .{ .a = 0 } },
        .{ .f1 = .{ .a = 1 }, .f2 = .{ .a = 1 } },
        .{ .f1 = .{ .b = 0 }, .f2 = .{ .b = 0 } },
        .{ .f1 = .{ .b = 1 }, .f2 = .{ .b = 1 } },
        .{ .f1 = .{ .a = 128 }, .f2 = .{ .b = 129 } },
        .{ .f1 = .{ .a = 255 }, .f2 = .{ .a = 255 } },
        .{ .f1 = .{ .a = 0 }, .f2 = .{ .a = 0 } },
        .{ .f1 = .{ .b = 255 }, .f2 = .{ .b = 255 } },
        .{ .f1 = .{ .b = 256 }, .f2 = .{ .b = 256 } },
    }, recording);
}

test "loadRecording should load the same recording that saveRecording saved when working with packed types" {
    const StructOfUnions = packed struct {
        a: packed union { u: u8, i: i8 } = .{ .u = 255 },
        b: packed union { u: u16, i: i16 } = .{ .u = 255 },

        const Self = @This();
        pub const Int = @Type(.{ .int = .{ .signedness = .unsigned, .bits = @bitSizeOf(Self) } });
    };
    const UnionOfStructs = packed union {
        a: packed struct { f1: u16 = 0xFFFF, f2: u8 = 0xFF },
        b: packed struct { f1: u8 = 0xFF, f2: u16 = 0xFFFF },

        const Self = @This();
        pub const Int = @Type(.{ .int = .{ .signedness = .unsigned, .bits = @bitSizeOf(Self) } });
    };
    const Frame = struct {
        struct_of_unions: StructOfUnions = .{},
        union_of_structs: UnionOfStructs = .{ .a = .{} },
    };
    const saved_recording = [_]Frame{
        .{
            .struct_of_unions = .{ .a = .{ .u = 255 }, .b = .{ .i = -1 } },
            .union_of_structs = .{ .a = .{ .f1 = 1, .f2 = 1 } },
        },
        .{
            .struct_of_unions = .{ .a = .{ .i = -1 }, .b = .{ .u = 255 } },
            .union_of_structs = .{ .b = .{ .f1 = 1, .f2 = 1 } },
        },
    };
    try saveRecording(Frame, &saved_recording, "./test_assets/recording.irony", &.{});
    defer std.fs.cwd().deleteFile("./test_assets/recording.irony") catch @panic("Failed to cleanup test file.");
    const loaded_recording = try loadRecording(Frame, testing.allocator, "./test_assets/recording.irony", &.{});
    defer testing.allocator.free(loaded_recording);
    try testing.expectEqual(saved_recording.len, loaded_recording.len);
    for (0..saved_recording.len) |index| {
        try testing.expectEqual(
            @as(StructOfUnions.Int, @bitCast(saved_recording[index].struct_of_unions)),
            @as(StructOfUnions.Int, @bitCast(loaded_recording[index].struct_of_unions)),
        );
        try testing.expectEqual(
            @as(UnionOfStructs.Int, @bitCast(saved_recording[index].union_of_structs)),
            @as(UnionOfStructs.Int, @bitCast(loaded_recording[index].union_of_structs)),
        );
    }
}

test "should correctly match paths with patterns" {
    try testing.expectEqual(true, doesPathMatchPattern("", ""));
    try testing.expectEqual(false, doesPathMatchPattern("", "a"));
    try testing.expectEqual(false, doesPathMatchPattern("", "?"));

    try testing.expectEqual(false, doesPathMatchPattern("a", ""));
    try testing.expectEqual(true, doesPathMatchPattern("a", "a"));
    try testing.expectEqual(false, doesPathMatchPattern("a", "ab"));
    try testing.expectEqual(true, doesPathMatchPattern("a", "?"));

    try testing.expectEqual(false, doesPathMatchPattern("ab", ""));
    try testing.expectEqual(false, doesPathMatchPattern("ab", "a"));
    try testing.expectEqual(true, doesPathMatchPattern("ab", "ab"));
    try testing.expectEqual(true, doesPathMatchPattern("ab", "?"));

    try testing.expectEqual(false, doesPathMatchPattern("a.b", ""));
    try testing.expectEqual(false, doesPathMatchPattern("a.b", "a"));
    try testing.expectEqual(false, doesPathMatchPattern("a.b", "ab"));
    try testing.expectEqual(true, doesPathMatchPattern("a.b", "a.b"));
    try testing.expectEqual(false, doesPathMatchPattern("a.b", "?"));
    try testing.expectEqual(true, doesPathMatchPattern("a.b", "a.?"));
    try testing.expectEqual(true, doesPathMatchPattern("a.b", "?.b"));
    try testing.expectEqual(false, doesPathMatchPattern("a.b", "b.?"));
    try testing.expectEqual(false, doesPathMatchPattern("a.b", "?.a"));
    try testing.expectEqual(true, doesPathMatchPattern("a.b", "?.?"));

    try testing.expectEqual(false, doesPathMatchPattern("abc.cde.efg", ""));
    try testing.expectEqual(false, doesPathMatchPattern("abc.cde.efg", "?"));
    try testing.expectEqual(false, doesPathMatchPattern("abc.cde.efg", "?.?"));
    try testing.expectEqual(true, doesPathMatchPattern("abc.cde.efg", "?.?.?"));
    try testing.expectEqual(false, doesPathMatchPattern("abc.cde.efg", "?.?.?.?"));
    try testing.expectEqual(true, doesPathMatchPattern("abc.cde.efg", "abc.cde.efg"));
    try testing.expectEqual(false, doesPathMatchPattern("abc.cde.efg", "abc.cde.efg.?"));
    try testing.expectEqual(true, doesPathMatchPattern("abc.cde.efg", "?.cde.efg"));
    try testing.expectEqual(true, doesPathMatchPattern("abc.cde.efg", "abc.?.efg"));
    try testing.expectEqual(true, doesPathMatchPattern("abc.cde.efg", "abc.cde.?"));
    try testing.expectEqual(true, doesPathMatchPattern("abc.cde.efg", "abc.?.?"));
    try testing.expectEqual(true, doesPathMatchPattern("abc.cde.efg", "?.?.efg"));
    try testing.expectEqual(true, doesPathMatchPattern("abc.cde.efg", "?.cde.?"));
    try testing.expectEqual(false, doesPathMatchPattern("abc.cde.efg", "abc.?.efh"));
}

test "should correctly atomically represent parts of the struct based on configuration" {
    const NormalStruct = struct { a: f32, b: f32 };
    const AtomicStruct = struct { a: f32, b: f32 };
    const Frame = struct {
        f1: [2]NormalStruct,
        f2: [2]AtomicStruct,
        f3: [2]NormalStruct,
        f4: [2]AtomicStruct,
    };
    const fields = getLocalFields(Frame, &.{
        .atomic_types = &.{AtomicStruct},
        .atomic_paths = &.{ "f3", "f4", "?.1" },
    });
    const contains = struct {
        fn call(comptime fields_slice: []const LocalField, path: []const u8) bool {
            inline for (fields_slice) |*field| {
                if (std.mem.eql(u8, field.path, path)) {
                    return true;
                }
            }
            return false;
        }
    }.call;

    try testing.expectEqual(false, contains(fields, "f1"));
    try testing.expectEqual(false, contains(fields, "f2"));
    try testing.expectEqual(true, contains(fields, "f3"));
    try testing.expectEqual(true, contains(fields, "f4"));

    try testing.expectEqual(false, contains(fields, "f1.0"));
    try testing.expectEqual(true, contains(fields, "f1.1"));
    try testing.expectEqual(true, contains(fields, "f2.0"));
    try testing.expectEqual(true, contains(fields, "f2.1"));
    try testing.expectEqual(false, contains(fields, "f3.0"));
    try testing.expectEqual(false, contains(fields, "f3.1"));
    try testing.expectEqual(false, contains(fields, "f4.0"));
    try testing.expectEqual(false, contains(fields, "f4.1"));

    try testing.expectEqual(true, contains(fields, "f1.0.a"));
    try testing.expectEqual(true, contains(fields, "f1.0.b"));
    try testing.expectEqual(false, contains(fields, "f1.1.a"));
    try testing.expectEqual(false, contains(fields, "f1.1.b"));
    try testing.expectEqual(false, contains(fields, "f2.0.a"));
    try testing.expectEqual(false, contains(fields, "f2.0.b"));
    try testing.expectEqual(false, contains(fields, "f2.1.a"));
    try testing.expectEqual(false, contains(fields, "f2.1.b"));
    try testing.expectEqual(false, contains(fields, "f3.0.a"));
    try testing.expectEqual(false, contains(fields, "f3.0.b"));
    try testing.expectEqual(false, contains(fields, "f3.1.a"));
    try testing.expectEqual(false, contains(fields, "f3.1.b"));
    try testing.expectEqual(false, contains(fields, "f4.0.a"));
    try testing.expectEqual(false, contains(fields, "f4.0.b"));
    try testing.expectEqual(false, contains(fields, "f4.1.a"));
    try testing.expectEqual(false, contains(fields, "f4.1.b"));
}
