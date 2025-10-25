const std = @import("std");
const builtin = @import("builtin");
const misc = @import("../misc/root.zig");

const FieldIndex = u8;
const FieldPathLength = u8;
const FieldOffset = u16;
const FieldSize = u16;
const NumberOfFrames = u64;
const LocalField = struct {
    path: []const u8,
    access: []const AccessElement,
    Type: type,
};
const AccessElement = union(enum) {
    name: []const u8,
    index: usize,
};
const RemoteField = struct {
    local_index: ?usize,
    size: FieldSize,
};

const magic_number = "irony";
const endian = std.builtin.Endian.little;
const max_number_of_fields = std.math.maxInt(FieldIndex);
const max_field_path_len = std.math.maxInt(FieldPathLength);
const field_separator = '.';
const field_separator_str = [1]u8{field_separator};

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
    var writer = file.writer(&buffer);

    writer.interface.writeAll(magic_number) catch |err| {
        misc.error_context.new("Failed to write magic number.", .{});
        return err;
    };

    const fields = getLocalFields(Frame, config);
    writeFieldList(&writer, fields) catch |err| {
        misc.error_context.append("Failed to write field list.", .{});
        return err;
    };

    const initial_values = if (frames.len > 0) &frames[0] else &Frame{};
    writeInitialValues(Frame, &writer, initial_values, fields) catch |err| {
        misc.error_context.append("Failed to write initial values.", .{});
        return err;
    };

    writeFrames(Frame, &writer, initial_values, frames, fields) catch |err| {
        misc.error_context.append("Failed to write frames.", .{});
        return err;
    };

    writer.end() catch |err| {
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
    var reader = file.reader(&buffer);

    var magic_buffer: [magic_number.len]u8 = undefined;
    reader.interface.readSliceAll(&magic_buffer) catch |err| {
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

    const initial_values = readInitialValues(Frame, &reader, remote_fields, local_fields) catch |err| {
        misc.error_context.append("Failed to read initial values.", .{});
        return err;
    };

    const frames = readFrames(Frame, allocator, &reader, &initial_values, remote_fields, local_fields) catch |err| {
        misc.error_context.append("Failed to read frames.", .{});
        return err;
    };

    return frames;
}

fn writeFieldList(writer: *std.fs.File.Writer, comptime fields: []const LocalField) !void {
    writer.interface.writeInt(FieldIndex, @intCast(fields.len), endian) catch |err| {
        misc.error_context.new("Failed to write number of fields: {}", .{fields.len});
        return err;
    };
    inline for (fields) |*field| {
        errdefer misc.error_context.append("Failed to write field: {s}", .{field.path});
        writer.interface.writeInt(FieldPathLength, @intCast(field.path.len), endian) catch |err| {
            misc.error_context.new("Failed to write the size of field path: {}", .{field.path.len});
            return err;
        };
        writer.interface.writeAll(field.path) catch |err| {
            misc.error_context.new("Failed to write the field path: {s}", .{field.path});
            return err;
        };
        const size: FieldSize = serializedSizeOf(field.Type);
        writer.interface.writeInt(FieldSize, size, endian) catch |err| {
            misc.error_context.new("Failed to write the field size: {}", .{size});
            return err;
        };
    }
}

fn readFieldList(
    reader: *std.fs.File.Reader,
    remote_fields_buffer: []RemoteField,
    comptime local_fields: []const LocalField,
) ![]RemoteField {
    const remote_fields_len = reader.interface.takeInt(FieldIndex, endian) catch |err| {
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
        const path_len = reader.interface.takeInt(FieldPathLength, endian) catch |err| {
            misc.error_context.new("Failed to read the size of the field path.", .{});
            return err;
        };
        var path_buffer: [max_field_path_len]u8 = undefined;
        const path = path_buffer[0..path_len];
        reader.interface.readSliceAll(path) catch |err| {
            misc.error_context.new("Failed to read the field path.", .{});
            return err;
        };
        const remote_size = reader.interface.takeInt(FieldSize, endian) catch |err| {
            misc.error_context.new("Failed to read the field size. Field path is: {s}", .{path});
            return err;
        };
        inline for (local_fields, 0..) |*local_field, local_index| {
            const local_size = serializedSizeOf(local_field.Type);
            if (std.mem.eql(u8, local_field.path, path) and local_size == remote_size) {
                remote_fields_buffer[index] = .{
                    .local_index = local_index,
                    .size = remote_size,
                };
                break;
            }
        } else {
            remote_fields_buffer[index] = .{
                .local_index = null,
                .size = remote_size,
            };
        }
    }
    return remote_fields_buffer[0..remote_fields_len];
}

fn writeInitialValues(
    comptime Frame: type,
    writer: *std.fs.File.Writer,
    frame: *const Frame,
    comptime fields: []const LocalField,
) !void {
    inline for (fields) |*field| {
        const field_pointer = getConstFieldPointer(frame, field);
        writeValue(writer, field_pointer) catch |err| {
            misc.error_context.append("Failed to write the value of field: {s}", .{field.path});
            return err;
        };
    }
}

fn readInitialValues(
    comptime Frame: type,
    reader: *std.fs.File.Reader,
    remote_fields: []const RemoteField,
    comptime local_fields: []const LocalField,
) !Frame {
    const default_frame = Frame{};
    var frame = default_frame;
    for (remote_fields) |*remote_field| {
        const local_index = remote_field.local_index orelse {
            reader.interface.discardAll(remote_field.size) catch |err| {
                misc.error_context.append("Failed to discard unknown field's data.", .{});
                return err;
            };
            continue;
        };
        inline for (local_fields, 0..) |*local_field, index| {
            if (local_index == index) {
                const field_pointer = getFieldPointer(&frame, local_field);
                if (readValue(local_field.Type, reader)) |field_value| {
                    field_pointer.* = field_value;
                } else |err| {
                    misc.error_context.append("Failed to read the value of field: {s}", .{local_field.path});
                    if (err == error.InvalidValue) {
                        if (!builtin.is_test) {
                            misc.error_context.logWarning(err);
                        }
                        field_pointer.* = getConstFieldPointer(&default_frame, local_field).*;
                    } else {
                        return err;
                    }
                }
                break;
            }
        } else unreachable;
    }
    return frame;
}

fn writeFrames(
    comptime Frame: type,
    writer: *std.fs.File.Writer,
    initial_values: *const Frame,
    frames: []const Frame,
    comptime fields: []const LocalField,
) !void {
    writer.interface.writeInt(NumberOfFrames, @intCast(frames.len), endian) catch |err| {
        misc.error_context.new("Failed to write number of frames: {}", .{frames.len});
        return err;
    };
    var last_frame: *const Frame = initial_values;
    for (frames, 0..) |*frame, frame_index| {
        errdefer misc.error_context.append("Failed to write frame: {}", .{frame_index});
        var number_of_changes: FieldIndex = 0;
        inline for (fields) |*field| {
            const field_pointer = getConstFieldPointer(frame, field);
            const last_field_pointer = getConstFieldPointer(last_frame, field);
            if (!areValuesEqual(field_pointer.*, last_field_pointer.*)) {
                number_of_changes += 1;
            }
        }
        writer.interface.writeInt(FieldIndex, number_of_changes, endian) catch |err| {
            misc.error_context.new("Failed to write number of changes: {}", .{number_of_changes});
            return err;
        };
        inline for (fields, 0..) |*field, field_index| {
            errdefer misc.error_context.append("Failed to write change for field: {s}", .{field.path});
            const field_pointer = getConstFieldPointer(frame, field);
            const last_field_pointer = getConstFieldPointer(last_frame, field);
            if (!areValuesEqual(field_pointer.*, last_field_pointer.*)) {
                writer.interface.writeInt(FieldIndex, @intCast(field_index), endian) catch |err| {
                    misc.error_context.new("Failed to write field index: {}", .{field_index});
                    return err;
                };
                writeValue(writer, field_pointer) catch |err| {
                    misc.error_context.append("Failed to write the new value.", .{});
                    return err;
                };
            }
        }
        last_frame = frame;
    }
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
    reader: *std.fs.File.Reader,
    initial_values: *const Frame,
    remote_fields: []const RemoteField,
    comptime local_fields: []const LocalField,
) ![]Frame {
    const number_of_frames = reader.interface.takeInt(NumberOfFrames, endian) catch |err| {
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
    const default_frame = Frame{};
    var current_frame = initial_values.*;
    for (0..number_of_frames) |frame_index| {
        errdefer misc.error_context.append("Failed read frame: {}", .{frame_index});
        const number_of_changes = reader.interface.takeInt(FieldIndex, endian) catch |err| {
            misc.error_context.new("Failed to read number changes.", .{});
            return err;
        };
        for (0..number_of_changes) |change_index| {
            errdefer misc.error_context.append("Failed read change: {}", .{change_index});
            const remote_index = reader.interface.takeInt(FieldIndex, endian) catch |err| {
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
                reader.interface.discardAll(remote_field.size) catch |err| {
                    misc.error_context.append("Failed to discard unknown field's data.", .{});
                    return err;
                };
                continue;
            };
            inline for (local_fields, 0..) |*local_field, index| {
                if (index == local_index) {
                    const field_pointer = getFieldPointer(&current_frame, local_field);
                    if (readValue(local_field.Type, reader)) |field_value| {
                        field_pointer.* = field_value;
                    } else |err| {
                        misc.error_context.append("Failed to read the new value of: {s}", .{local_field.path});
                        if (err == error.InvalidValue) {
                            if (!builtin.is_test) {
                                misc.error_context.logWarning(err);
                            }
                            field_pointer.* = getConstFieldPointer(&default_frame, local_field).*;
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

fn writeValue(writer: *std.fs.File.Writer, value_pointer: anytype) !void {
    const Type = switch (@typeInfo(@TypeOf(value_pointer))) {
        .pointer => |info| info.child,
        else => @compileError("Expected value_pointer to be a pointer but got: " ++ @typeName(@TypeOf(value_pointer))),
    };
    const start_pos = writer.pos + writer.interface.end;
    defer {
        const end_pos = writer.pos + writer.interface.end;
        std.debug.assert(end_pos - start_pos == serializedSizeOf(Type));
    }
    switch (@typeInfo(Type)) {
        .void => {},
        .bool => {
            const byte: u8 = switch (value_pointer.*) {
                false => 0,
                true => 1,
            };
            writer.interface.writeByte(byte) catch |err| {
                misc.error_context.new("Failed to write bool's byte: {}", .{byte});
                return err;
            };
        },
        .int => |info| {
            const WriteType = @Type(.{ .int = .{
                .signedness = info.signedness,
                .bits = serializedSizeOf(Type) * std.mem.byte_size_in_bits,
            } });
            const value = value_pointer.*;
            writer.interface.writeInt(WriteType, value, endian) catch |err| {
                misc.error_context.new(
                    "Failed to write int: {} ({s} -> {s})",
                    .{ value, @typeName(Type), @typeName(WriteType) },
                );
                return err;
            };
        },
        .float => |*info| {
            const IntType = @Type(.{ .int = .{ .signedness = .unsigned, .bits = info.bits } });
            const value = value_pointer.*;
            const int_value: IntType = @bitCast(value);
            writer.interface.writeInt(IntType, int_value, endian) catch |err| {
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
                writer.interface.writeByte(1) catch |err| {
                    misc.error_context.new("Failed to write optional's tag byte: 1", .{});
                    return err;
                };
                writeValue(writer, child_pointer) catch |err| {
                    misc.error_context.append("Failed to write optional's payload.", .{});
                    return err;
                };
            } else {
                writer.interface.writeByte(0) catch |err| {
                    misc.error_context.new("Failed to write optional's tag byte: 0", .{});
                    return err;
                };
                for (0..serializedSizeOf(info.child)) |_| {
                    writer.interface.writeByte(0) catch |err| {
                        misc.error_context.new("Failed to write optional's null padding.", .{});
                        return err;
                    };
                }
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
            const tag = @intFromEnum(value_pointer.*);
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
                    const padding_size = serializedSizeOf(Type) - serializedSizeOf(Tag) - serializedSizeOf(Payload);
                    for (0..padding_size) |_| {
                        writer.interface.writeByte(0) catch |err| {
                            misc.error_context.new("Failed to write union's padding.", .{});
                            return err;
                        };
                    }
                },
            }
        },
        else => @compileError("Unsupported type: " ++ @typeName(Type)),
    }
}

fn readValue(comptime Type: type, reader: *std.fs.File.Reader) anyerror!Type {
    const start_pos = reader.logicalPos();
    defer {
        const end_pos = reader.logicalPos();
        const target_end_pos = start_pos + serializedSizeOf(Type);
        if (end_pos != target_end_pos) {
            // If the value read fails,
            // the writer still needs to position itself correctly to read the rest of the file.
            reader.seekTo(target_end_pos) catch {};
        }
    }
    switch (@typeInfo(Type)) {
        .void => return {},
        .bool => {
            const byte = reader.interface.takeByte() catch |err| {
                misc.error_context.new("Failed to read bool's byte.", .{});
                return err;
            };
            switch (byte) {
                0 => return false,
                1 => return true,
                else => {
                    misc.error_context.new("Invalid value of bool's byte: {}", .{byte});
                    return error.InvalidValue;
                },
            }
        },
        .int => |info| {
            const ReadType = @Type(.{ .int = .{
                .signedness = info.signedness,
                .bits = serializedSizeOf(Type) * std.mem.byte_size_in_bits,
            } });
            const read_int = reader.interface.takeInt(ReadType, endian) catch |err| {
                misc.error_context.new("Failed to read int. ({s} -> {s})", .{ @typeName(Type), @typeName(ReadType) });
                return err;
            };
            return std.math.cast(Type, read_int) orelse return error.InvalidValue;
        },
        .float => |*info| {
            const IntType = @Type(.{ .int = .{ .signedness = .unsigned, .bits = info.bits } });
            const int = reader.interface.takeInt(IntType, endian) catch |err| {
                misc.error_context.new("Failed to read float. ({s})", .{@typeName(Type)});
                return err;
            };
            return @bitCast(int);
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
            const byte = reader.interface.takeByte() catch |err| {
                misc.error_context.new("Failed to read optional's tag byte.", .{});
                return err;
            };
            switch (byte) {
                0 => {
                    reader.interface.discardAll(serializedSizeOf(info.child)) catch |err| {
                        misc.error_context.append("Failed to discard null optional's payload.", .{});
                        return err;
                    };
                    return null;
                },
                1 => return readValue(info.child, reader) catch |err| {
                    misc.error_context.append("Failed to read optional's payload.", .{});
                    return err;
                },
                else => {
                    misc.error_context.new("Invalid optional's tag byte: {}", .{byte});
                    return error.InvalidValue;
                },
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
                    const padding_size = serializedSizeOf(Type) - serializedSizeOf(Tag) - serializedSizeOf(Payload);
                    reader.interface.discardAll(padding_size) catch |err| {
                        misc.error_context.append("Failed to discard union's padding.", .{});
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

fn serializedSizeOf(comptime Type: type) comptime_int {
    return switch (@typeInfo(Type)) {
        .void => 0,
        .bool => 1,
        .int => |*info| std.math.divCeil(u16, info.bits, std.mem.byte_size_in_bits) catch {
            @compileError(std.fmt.comptimePrint(
                "Failed to ceil devide {} with {}.",
                .{ info.bits, std.mem.byte_size_in_bits },
            ));
        },
        .float => @sizeOf(Type),
        .@"enum" => |*info| serializedSizeOf(info.tag_type),
        .optional => |*info| 1 + serializedSizeOf(info.child),
        .array => |*info| info.len * serializedSizeOf(info.child),
        .@"struct" => |*info| {
            if (info.backing_integer) |IntType| {
                return serializedSizeOf(IntType);
            }
            var sum: usize = 0;
            for (info.fields) |*field| {
                sum += serializedSizeOf(field.type);
            }
            return sum;
        },
        .@"union" => |*info| {
            if (info.layout == .@"packed") {
                const IntType = @Type(.{ .int = .{ .signedness = .unsigned, .bits = @bitSizeOf(Type) } });
                return serializedSizeOf(IntType);
            }
            const Tag = info.tag_type orelse {
                @compileError("Union " ++ @typeName(Type) ++ " is not serializable. (Not tagged and not packed.)");
            };
            var max: usize = 0;
            inline for (info.fields) |*field| {
                max = @max(max, serializedSizeOf(field.type));
            }
            return @sizeOf(Tag) + max;
        },
        else => @compileError("Unsupported type: " ++ @typeName(Type)),
    };
}

fn getFieldPointer(frame: anytype, comptime field: *const LocalField) *field.Type {
    return getFieldPointerRecursive(*field.Type, frame, field.access);
}

fn getConstFieldPointer(frame: anytype, comptime field: *const LocalField) *const field.Type {
    return getFieldPointerRecursive(*const field.Type, frame, field.access);
}

fn getFieldPointerRecursive(
    comptime Pointer: type,
    lhs_pointer: anytype,
    comptime access: []const AccessElement,
) Pointer {
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
        .name => |name| &@field(lhs_pointer, name),
        .index => |index| &lhs_pointer[index],
    };
    const next_access = access[1..];
    return getFieldPointerRecursive(Pointer, next_pointer, next_access);
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
        .bool, .int, .float, .@"enum", .optional, .@"union" => {
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
                        break :block field.path ++ field_separator_str ++ struct_field.name;
                    },
                    .access = field.access ++ &[1]AccessElement{.{ .name = struct_field.name }},
                    .Type = struct_field.type,
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
                        break :block std.fmt.comptimePrint("{s}{s}{}", .{ field.path, field_separator_str, index });
                    },
                    .access = field.access ++ &[1]AccessElement{.{ .index = index }},
                    .Type = info.child,
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
                if (pattern_char == '?') {
                    state = .wildcard;
                } else if (path_char != pattern_char) {
                    return false;
                }
                pattern_index += 1;
            },
            .wildcard => {
                if (path_char == field_separator) {
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

test "loadRecording should use default value when encountering invalid bool value" {
    const SavedFrame = struct { a: u8 = 1, b: ?u8 = null };
    const LoadedFrame = struct { a: bool = false, b: ?bool = null };
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
        .{ .a = false, .b = null },
        .{ .a = false, .b = false },
        .{ .a = true, .b = true },
        .{ .a = false, .b = null },
    }, recording);
}

test "loadRecording should use default value when encountering invalid int value" {
    const SavedFrame = struct { a: u16 = 0, b: ?u16 = null };
    const LoadedFrame = struct { a: u9 = 1, b: ?u9 = null };
    try saveRecording(SavedFrame, &.{
        .{ .a = 0, .b = null },
        .{ .a = 0, .b = 0 },
        .{ .a = 511, .b = 511 },
        .{ .a = 512, .b = 512 },
    }, "./test_assets/recording.irony", &.{});
    defer std.fs.cwd().deleteFile("./test_assets/recording.irony") catch @panic("Failed to cleanup test file.");
    const recording = try loadRecording(LoadedFrame, testing.allocator, "./test_assets/recording.irony", &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .a = 0, .b = null },
        .{ .a = 0, .b = 0 },
        .{ .a = 511, .b = 511 },
        .{ .a = 1, .b = null },
    }, recording);
}

test "loadRecording should use default value when encountering invalid enum value" {
    const Enum = enum(u8) { a = 1, b = 2 };
    const SavedFrame = struct { a: u8 = 0, b: ?u8 = null };
    const LoadedFrame = struct { a: Enum = .a, b: ?Enum = null };
    try saveRecording(SavedFrame, &.{
        .{ .a = 0, .b = null },
        .{ .a = 0, .b = 0 },
        .{ .a = 1, .b = 1 },
        .{ .a = 2, .b = 2 },
        .{ .a = 3, .b = 3 },
    }, "./test_assets/recording.irony", &.{});
    defer std.fs.cwd().deleteFile("./test_assets/recording.irony") catch @panic("Failed to cleanup test file.");
    const recording = try loadRecording(LoadedFrame, testing.allocator, "./test_assets/recording.irony", &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .a = .a, .b = null },
        .{ .a = .a, .b = null },
        .{ .a = .a, .b = .a },
        .{ .a = .b, .b = .b },
        .{ .a = .a, .b = null },
    }, recording);
}

test "loadRecording should use default value when encountering invalid optional" {
    const TagAndPayload = packed struct { tag: u8 = 255, payload: u8 = 255 };
    const SavedFrame = struct { a: TagAndPayload = .{}, b: TagAndPayload = .{} };
    const LoadedFrame = struct { a: ?u8 = null, b: ?u8 = 0 };
    try saveRecording(SavedFrame, &.{
        .{ .a = .{ .tag = 0, .payload = 0 }, .b = .{ .tag = 0, .payload = 0 } },
        .{ .a = .{ .tag = 1, .payload = 0 }, .b = .{ .tag = 1, .payload = 0 } },
        .{ .a = .{ .tag = 1, .payload = 1 }, .b = .{ .tag = 1, .payload = 1 } },
        .{ .a = .{ .tag = 2, .payload = 1 }, .b = .{ .tag = 2, .payload = 1 } },
    }, "./test_assets/recording.irony", &.{});
    defer std.fs.cwd().deleteFile("./test_assets/recording.irony") catch @panic("Failed to cleanup test file.");
    const recording = try loadRecording(LoadedFrame, testing.allocator, "./test_assets/recording.irony", &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .a = null, .b = null },
        .{ .a = 0, .b = 0 },
        .{ .a = 1, .b = 1 },
        .{ .a = null, .b = 0 },
    }, recording);
}

test "loadRecording should use default value when encountering invalid tagged union" {
    const TagAndPayload = packed struct { tag: u8 = 0xFF, payload: u16 = 0xFFFF };
    const Tag = enum(u8) { a = 1, b = 2 };
    const Union = union(Tag) { a: u8, b: u16 };
    const SavedFrame = struct { f1: TagAndPayload = .{}, f2: TagAndPayload = .{} };
    const LoadedFrame = struct { f1: Union = .{ .a = 128 }, f2: Union = .{ .b = 129 } };
    try testing.expectEqual(serializedSizeOf(Union), serializedSizeOf(TagAndPayload));
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
