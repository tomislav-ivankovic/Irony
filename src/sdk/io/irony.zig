const std = @import("std");
const builtin = @import("builtin");
const misc = @import("../misc/root.zig");
const io = @import("root.zig");

const VersionNumber = u16;
const FrameSize = u16;
const NumberOfFields = u16;
const FieldPathLength = u8;
const FieldOffset = u16;
const FieldSize = u16;
const NumberOfFrames = u32;
const LocalField = struct {
    path: []const u8,
    access: []const AccessElement,
    offset: FieldOffset,
    size: FieldSize,
};
const AccessElement = union(enum) {
    struct_field: []const u8,
    array_index: usize,
    optional_tag: void,
    optional_payload: void,
    union_tag: void,
    union_field: []const u8,
};
const RemoteField = struct {
    offset: FieldOffset,
    size: FieldSize,
};

const endian = std.builtin.Endian.little;
const magic_number = "irony";
const earliest_supported_version_number = 3;
const current_version_number = 3;
const max_frame_size = std.math.maxInt(FrameSize);
const max_number_of_fields = std.math.maxInt(NumberOfFields);
const max_field_path_len = std.math.maxInt(FieldPathLength);
const max_number_of_frames = std.math.maxInt(NumberOfFrames);
const path_separator = '.';
const tag_path_component = "tag";
const payload_path_component = "payload";
const compression_level = 17;

pub fn writeIronyFormat(
    comptime Frame: type,
    allocator: std.mem.Allocator,
    frames: []const Frame,
    writer: *std.Io.Writer,
) !void {
    writer.writeAll(magic_number) catch |err| {
        misc.error_context.new("Failed to write magic number.", .{});
        return err;
    };

    writer.writeInt(VersionNumber, current_version_number, endian) catch |err| {
        misc.error_context.new("Failed to write version number.", .{});
        return err;
    };

    var encoder = io.ZstdEncoder.init(allocator, writer, compression_level) catch |err| {
        misc.error_context.append("Failed to initialize zstd encoder.", .{});
        return err;
    };
    defer encoder.deinit();
    var encoder_writer = encoder.writer();

    const frame_size = serializedSizeOf(Frame);
    if (frame_size > max_frame_size) {
        @compileError("The frame size exceeds maximum allowed.");
    }
    encoder_writer.writeInt(FrameSize, frame_size, endian) catch |err| {
        misc.error_context.new("Failed to write frame size: {}", .{frame_size});
        return err;
    };

    const fields = getLocalFields(Frame);
    writeFieldList(&encoder_writer, fields) catch |err| {
        misc.error_context.append("Failed to write field list.", .{});
        return err;
    };

    writeFrames(Frame, allocator, &encoder_writer, frames) catch |err| {
        misc.error_context.append("Failed to write frames.", .{});
        return err;
    };

    encoder_writer.flush() catch |err| {
        misc.error_context.new("Failed to flush encoder writer.", .{});
        return err;
    };
}

pub fn readIronyFormat(
    comptime Frame: type,
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    default_frame: *const Frame,
) ![]Frame {
    var magic_buffer: [magic_number.len]u8 = undefined;
    reader.readSliceAll(&magic_buffer) catch |err| {
        misc.error_context.new("Failed to read magic number.", .{});
        return err;
    };
    if (!std.mem.eql(u8, &magic_buffer, magic_number)) {
        misc.error_context.new("Incorrect magic number.", .{});
        return error.MagicNumber;
    }

    const version = reader.takeInt(VersionNumber, endian) catch |err| {
        misc.error_context.new("Failed to read version number.", .{});
        return err;
    };
    if (version < earliest_supported_version_number) {
        misc.error_context.new(
            "Deprecated version of Irony file format {}. Earliest supported version is: {}",
            .{ version, earliest_supported_version_number },
        );
        return error.Deprecated;
    }
    if (version > current_version_number) {
        std.log.warn(
            "File's version number {} is larger than expected {}. Expecting file parsing to fail but proceeding anyway.",
            .{ version, current_version_number },
        );
    }

    var decoder = io.ZstdDecoder.init(allocator, reader) catch |err| {
        misc.error_context.append("Failed to initialize zstd decoder.", .{});
        return err;
    };
    defer decoder.deinit();
    var decoder_buffer: [4096]u8 = undefined;
    var decoder_reader = decoder.reader(&decoder_buffer);

    const remote_frame_size = decoder_reader.takeInt(FrameSize, endian) catch |err| {
        misc.error_context.new("Failed to read frame size.", .{});
        return err;
    };

    const local_fields = getLocalFields(Frame);
    const remote_fields = readFieldList(&decoder_reader, remote_frame_size, local_fields) catch |err| {
        misc.error_context.append("Failed to read field list.", .{});
        return err;
    };

    return readFrames(
        Frame,
        allocator,
        &decoder_reader,
        remote_frame_size,
        local_fields,
        &remote_fields,
        default_frame,
    ) catch |err| {
        misc.error_context.append("Failed to read frames.", .{});
        return err;
    };
}

fn writeFieldList(writer: *std.Io.Writer, comptime fields: []const LocalField) !void {
    writer.writeInt(NumberOfFields, @intCast(fields.len), endian) catch |err| {
        misc.error_context.new("Failed to write number of fields: {}", .{fields.len});
        return err;
    };
    for (fields) |*field| {
        errdefer misc.error_context.append("Failed to write field: {s}", .{field.path});
        writer.writeInt(FieldPathLength, @intCast(field.path.len), endian) catch |err| {
            misc.error_context.new("Failed to write the size of field path: {}", .{field.path.len});
            return err;
        };
        writer.writeAll(field.path) catch |err| {
            misc.error_context.new("Failed to write the field path: {s}", .{field.path});
            return err;
        };
        writer.writeInt(FieldOffset, field.offset, endian) catch |err| {
            misc.error_context.new("Failed to write the field offset: {}", .{field.offset});
            return err;
        };
        writer.writeInt(FieldSize, field.size, endian) catch |err| {
            misc.error_context.new("Failed to write the field size: {}", .{field.size});
            return err;
        };
    }
}

fn readFieldList(
    reader: *std.Io.Reader,
    remote_frame_size: FrameSize,
    comptime local_fields: []const LocalField,
) ![local_fields.len]?RemoteField {
    var result: [local_fields.len]?RemoteField = @splat(null);
    const remote_fields_len = reader.takeInt(NumberOfFields, endian) catch |err| {
        misc.error_context.new("Failed to read number of fields.", .{});
        return err;
    };
    for (0..remote_fields_len) |index| {
        errdefer misc.error_context.append("Failed to read field: {}", .{index});
        const path_len = reader.takeInt(FieldPathLength, endian) catch |err| {
            misc.error_context.new("Failed to read the size of the field path.", .{});
            return err;
        };
        var path_buffer: [max_field_path_len]u8 = undefined;
        const path = path_buffer[0..path_len];
        reader.readSliceAll(path) catch |err| {
            misc.error_context.new("Failed to read the field path.", .{});
            return err;
        };
        const remote_offset = reader.takeInt(FieldOffset, endian) catch |err| {
            misc.error_context.new("Failed to read the field offset. Field path is: {s}", .{path});
            return err;
        };
        const remote_size = reader.takeInt(FieldSize, endian) catch |err| {
            misc.error_context.new("Failed to read the field size. Field path is: {s}", .{path});
            return err;
        };
        const total = std.math.add(FrameSize, remote_offset, remote_size) catch |err| {
            misc.error_context.new("Field exceeded frame size limits: {s}", .{path});
            return err;
        };
        if (total > remote_frame_size) {
            misc.error_context.new("Field exceeded frame size limits: {s}", .{path});
            return error.InvalidRemoteField;
        }
        for (local_fields, 0..) |*local_field, local_index| {
            if (std.mem.eql(u8, local_field.path, path)) {
                result[local_index] = .{
                    .offset = remote_offset,
                    .size = remote_size,
                };
                break;
            }
        }
    }
    return result;
}

fn writeFrames(
    comptime Frame: type,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    frames: []const Frame,
) !void {
    if (frames.len > max_number_of_frames) {
        misc.error_context.new(
            "Number of frames {} exceeded maximum value of {}.",
            .{ frames.len, max_number_of_frames },
        );
        return error.TooManyFrames;
    }
    writer.writeInt(NumberOfFrames, @intCast(frames.len), endian) catch |err| {
        misc.error_context.new("Failed to write number of frames: {}", .{frames.len});
        return err;
    };

    const frame_size = serializedSizeOf(Frame);
    const array_of_structs = allocator.alloc(u8, frames.len * frame_size) catch |err| {
        misc.error_context.new("Failed to allocate array of structs buffer.", .{});
        return err;
    };
    defer allocator.free(array_of_structs);
    var array_of_structs_writer = std.Io.Writer.fixed(array_of_structs);

    for (frames, 0..) |*frame, index| {
        writeValue(&array_of_structs_writer, frame) catch |err| {
            misc.error_context.append("Failed to write frame {} into array of structs buffer.", .{index});
            return err;
        };
    }

    for (0..frame_size) |offset| {
        for (0..frames.len) |frame_index| {
            const byte_index = (frame_index * frame_size) + offset;
            const byte = array_of_structs[byte_index];
            writer.writeByte(byte) catch |err| {
                misc.error_context.new(
                    "Failed to write byte from frame offset {} and frame index {}.",
                    .{ offset, frame_index },
                );
                return err;
            };
        }
    }
}

fn readFrames(
    comptime Frame: type,
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    remote_frame_size: FrameSize,
    comptime local_fields: []const LocalField,
    remote_fields: *const [local_fields.len]?RemoteField,
    default_frame: *const Frame,
) ![]Frame {
    const number_of_frames = reader.takeInt(NumberOfFrames, endian) catch |err| {
        misc.error_context.new("Failed to read number of frames.", .{});
        return err;
    };
    if (number_of_frames > max_number_of_frames) {
        misc.error_context.new(
            "Number of frames {} exceeded maximum value of {}.",
            .{ number_of_frames, max_number_of_frames },
        );
        return error.TooManyFrames;
    }

    const array_of_structs = allocator.alloc(u8, number_of_frames * remote_frame_size) catch |err| {
        misc.error_context.new("Failed to allocate array of structs buffer.", .{});
        return err;
    };
    defer allocator.free(array_of_structs);

    for (0..remote_frame_size) |offset| {
        for (0..number_of_frames) |frame_index| {
            const byte_index = (frame_index * remote_frame_size) + offset;
            const byte = reader.takeByte() catch |err| {
                misc.error_context.new(
                    "Failed to read byte from frame offset {} and frame index {}.",
                    .{ offset, frame_index },
                );
                return err;
            };
            array_of_structs[byte_index] = byte;
        }
    }

    const frames = allocator.alloc(Frame, number_of_frames) catch |err| {
        misc.error_context.new(
            "Failed to allocate enough memory to store the recording frames. Number of frames is: {}",
            .{number_of_frames},
        );
        return err;
    };
    errdefer allocator.free(frames);

    for (frames, 0..) |*frame, frame_index| {
        frame.* = default_frame.*;
        var fields_to_default: [local_fields.len]bool = @splat(false);

        inline for (local_fields, remote_fields, &fields_to_default) |*local_field, *remote_field_maybe, *to_default| {
            if (remote_field_maybe.*) |*remote_field| {
                if (isFieldAccessible(frame, local_field.access)) {
                    const Type = getFieldType(Frame, local_field.access);
                    const data_start = (frame_index * remote_frame_size) + remote_field.offset;
                    const data_end = data_start + remote_field.size;
                    const data = array_of_structs[data_start..data_end];
                    if (readValue(Type, data)) |value| {
                        setFieldValue(frame, local_field.access, &value) catch |err| {
                            misc.error_context.append(
                                "Failed to set field with path {s} on frame {} to its new value. " ++
                                    "Falling back to default value.",
                                .{ local_field.path, frame_index },
                            );
                            if (!builtin.is_test) {
                                misc.error_context.logWarning(err);
                            }
                            to_default.* = true;
                        };
                    } else |err| {
                        misc.error_context.append(
                            "Failed to read field with path {s} on frame {}. Falling back to default value.",
                            .{ local_field.path, frame_index },
                        );
                        if (!builtin.is_test) {
                            misc.error_context.logWarning(err);
                        }
                        to_default.* = true;
                    }
                }
            } else {
                to_default.* = true;
            }
        }

        inline for (local_fields, fields_to_default) |*local_field, to_default| {
            if (to_default) {
                setFieldToDefault(frame, local_field.access, default_frame);
            }
        }
    }
    return frames;
}

fn writeValue(writer: *std.Io.Writer, value_pointer: anytype) !void {
    const Type = switch (@typeInfo(@TypeOf(value_pointer))) {
        .pointer => |info| info.child,
        else => @compileError("Expected value_pointer to be a pointer but got: " ++ @typeName(@TypeOf(value_pointer))),
    };
    switch (@typeInfo(Type)) {
        .void => {},
        .bool => {
            const value = value_pointer.*;
            const byte: u8 = switch (value) {
                false => 0,
                true => 1,
            };
            writer.writeByte(byte) catch |err| {
                misc.error_context.new("Failed to write bool's byte: {}", .{byte});
                return err;
            };
        },
        .int => |*info| {
            const value = value_pointer.*;
            const WriteType = @Int(info.signedness, serializedSizeOf(Type) * std.mem.byte_size_in_bits);
            const write_value: WriteType = @intCast(value);
            writer.writeInt(WriteType, write_value, endian) catch |err| {
                misc.error_context.new(
                    "Failed to write int: {} ({s} -> {s})",
                    .{ value, @typeName(Type), @typeName(WriteType) },
                );
                return err;
            };
        },
        .float => |*info| {
            const value = value_pointer.*;
            const IntType = @Int(.unsigned, info.bits);
            const int_value: IntType = @bitCast(value);
            writeValue(writer, &int_value) catch |err| {
                misc.error_context.append(
                    "Failed to write float: {} ({s} -> {s})",
                    .{ value, @typeName(Type), @typeName(IntType) },
                );
                return err;
            };
        },
        .@"enum" => |*info| {
            const value = value_pointer.*;
            const IntType = info.tag_type;
            const int_value: IntType = @backingInt(value);
            writeValue(writer, &int_value) catch |err| {
                misc.error_context.append(
                    "Failed to write enum: {s} ({s} -> {s})",
                    .{ @tagName(value), @typeName(Type), @typeName(IntType) },
                );
                return err;
            };
        },
        .optional => |*info| {
            if (value_pointer.*) |*child_pointer| {
                writer.writeByte(1) catch |err| {
                    misc.error_context.new("Failed to write optional's tag: 1", .{});
                    return err;
                };
                writeValue(writer, child_pointer) catch |err| {
                    misc.error_context.append("Failed to write optional's payload.", .{});
                    return err;
                };
            } else {
                writer.writeByte(0) catch |err| {
                    misc.error_context.new("Failed to write optional's tag: 0", .{});
                    return err;
                };
                for (0..serializedSizeOf(info.child)) |_| {
                    writer.writeByte(0) catch |err| {
                        misc.error_context.new("Failed to write optional's null padding.", .{});
                        return err;
                    };
                }
            }
        },
        .array => {
            for (value_pointer, 0..) |*element_pointer, index| {
                writeValue(writer, element_pointer) catch |err| {
                    misc.error_context.append("Failed to write array element at index: {}", .{index});
                    return err;
                };
            }
        },
        .@"struct" => |*info| if (info.backing_integer) |IntType| {
            const int_value: IntType = @backingInt(value_pointer.*);
            writeValue(writer, &int_value) catch |err| {
                misc.error_context.append(
                    "Failed to write packed struct's backing int: {} ({s})",
                    .{ int_value, @typeName(IntType) },
                );
                return err;
            };
        } else {
            inline for (info.field_names) |field_name| {
                const field_pointer = &@field(value_pointer, field_name);
                writeValue(writer, field_pointer) catch |err| {
                    misc.error_context.append("Failed to write struct field: {s}", .{field_name});
                    return err;
                };
            }
        },
        .@"union" => |*info| if (info.layout == .@"packed") {
            const int_value = @backingInt(value_pointer.*);
            const IntType = @TypeOf(int_value);
            writeValue(writer, &int_value) catch |err| {
                misc.error_context.append(
                    "Failed to write packed union's backing int: {} ({s})",
                    .{ int_value, @typeName(IntType) },
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
                    const padding_size = serializedSizeOf(Type) - serializedSizeOf(Tag) - serializedSizeOf(Payload);
                    for (0..padding_size) |_| {
                        writer.writeByte(0) catch |err| {
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

fn readValue(comptime Type: type, data: []const u8) !Type {
    switch (@typeInfo(Type)) {
        .void => return {},
        .bool => {
            const byte = readValue(u8, data) catch |err| {
                misc.error_context.append("Failed to read bool's byte.", .{});
                return err;
            };
            switch (byte) {
                0 => return false,
                1 => return true,
                else => {
                    misc.error_context.new("Invalid bool byte: {}", .{data[0]});
                    return error.InvalidValue;
                },
            }
        },
        .int => |*info| {
            const local_size = serializedSizeOf(Type);
            const ReadType = @Int(info.signedness, local_size * std.mem.byte_size_in_bits);
            const read_len = @min(local_size, data.len);
            const read_data, const padding = switch (endian) {
                .little => .{ data[0..read_len], data[read_len..data.len] },
                .big => .{ data[(data.len - read_len)..data.len], data[0..(data.len - read_len)] },
            };
            var read_value = std.mem.readVarInt(ReadType, read_data, endian);
            if (endian == .little and
                info.signedness == .signed and
                read_value >= 0 and
                (read_data[read_data.len - 1] & 0b10000000) != 0)
            {
                read_value -= @shlExact(@as(ReadType, 1), @intCast(data.len * std.mem.byte_size_in_bits));
            }
            const value = std.math.cast(Type, read_value) orelse {
                misc.error_context.new("Failed to cast {} to {s}.", .{ read_value, @typeName(Type) });
                return error.InvalidValue;
            };
            const expected_padding_byte: u8 = if (value >= 0) 0x00 else 0xFF;
            for (padding) |byte| {
                if (byte != expected_padding_byte) {
                    misc.error_context.new(
                        "Expected all padding bytes to be {} but got: {}",
                        .{ expected_padding_byte, byte },
                    );
                    return error.InvalidValue;
                }
            }
            return value;
        },
        .float => {
            inline for (.{ f16, f32, f64, f80, f128 }) |ReadType| {
                const read_size = serializedSizeOf(ReadType);
                if (read_size == data.len) {
                    const IntType = @Int(.unsigned, read_size * std.mem.byte_size_in_bits);
                    const int_value = readValue(IntType, data) catch |err| {
                        misc.error_context.append(
                            "Failed to read float's int value. ({s} -> {s})",
                            .{ @typeName(ReadType), @typeName(IntType) },
                        );
                        return err;
                    };
                    const read_float: ReadType = @bitCast(int_value);
                    return @floatCast(read_float);
                }
            }
            misc.error_context.new("Invalid float size: {}", .{data.len});
            return error.InvalidValue;
        },
        .@"enum" => |*info| {
            const IntType = info.tag_type;
            const int_value = readValue(IntType, data) catch |err| {
                misc.error_context.append(
                    "Failed to read enum's tag. ({s} -> {s})",
                    .{ @typeName(Type), @typeName(IntType) },
                );
                return err;
            };
            return std.enums.fromInt(Type, int_value) orelse {
                misc.error_context.new(
                    "Integer value {} ({s}) does not match any enum tags. ({s})",
                    .{ int_value, @typeName(IntType), @typeName(Type) },
                );
                return error.InvalidEnumValue;
            };
        },
        .@"struct" => |*info| {
            const IntType = info.backing_integer orelse @compileError("Unsupported type: " ++ @typeName(Type));
            const int_value = readValue(IntType, data) catch |err| {
                misc.error_context.append(
                    "Failed to read packed struct's int value. ({s} -> {s})",
                    .{ @typeName(Type), @typeName(IntType) },
                );
                return err;
            };
            return @fromBackingInt(int_value);
        },
        .@"union" => |*info| {
            if (info.layout != .@"packed") {
                @compileError("Unsupported type: " ++ @typeName(Type));
            }
            const IntType = @Int(.unsigned, @bitSizeOf(Type));
            const int_value = readValue(IntType, data) catch |err| {
                misc.error_context.append(
                    "Failed to read packed union's int value. ({s} -> {s})",
                    .{ @typeName(Type), @typeName(IntType) },
                );
                return err;
            };
            return @fromBackingInt(int_value);
        },
        else => @compileError("Unsupported type: " ++ @typeName(Type)),
    }
}

fn getFieldType(comptime Type: type, comptime access: []const AccessElement) type {
    var Result = Type;
    for (access) |element| {
        Result = switch (element) {
            .struct_field => |name| @FieldType(Result, name),
            .array_index => @typeInfo(Result).array.child,
            .optional_tag => bool,
            .optional_payload => @typeInfo(Result).optional.child,
            .union_tag => @typeInfo(Result).@"union".tag_type.?,
            .union_field => |name| @FieldType(Result, name),
        };
    }
    return Result;
}

fn isFieldAccessible(lhs_pointer: anytype, comptime access: []const AccessElement) bool {
    if (@typeInfo(@TypeOf(lhs_pointer)) != .pointer) {
        @compileError("Expected lhs_pointer to be a pointer but got: " ++ @typeName(@TypeOf(lhs_pointer)));
    }
    if (access.len == 0) {
        return true;
    }
    const next_lhs_pointer = switch (access[0]) {
        .struct_field => |name| &@field(lhs_pointer, name),
        .array_index => |index| &lhs_pointer[index],
        .optional_tag => return true,
        .optional_payload => block: {
            if (lhs_pointer.*) |*payload_pointer| {
                break :block payload_pointer;
            } else {
                return false;
            }
        },
        .union_tag => return true,
        .union_field => |name| block: {
            const expected_tag = @field(std.meta.Tag(@TypeOf(lhs_pointer.*)), name);
            const actual_tag = std.meta.activeTag(lhs_pointer.*);
            if (actual_tag == expected_tag) {
                break :block &@field(lhs_pointer, name);
            } else {
                return false;
            }
        },
    };
    const next_access = access[1..];
    return isFieldAccessible(next_lhs_pointer, next_access);
}

fn setFieldValue(lhs_pointer: anytype, comptime access: []const AccessElement, value_pointer: anytype) !void {
    if (@typeInfo(@TypeOf(lhs_pointer)) != .pointer) {
        @compileError("Expected lhs_pointer to be a pointer but got: " ++ @typeName(@TypeOf(lhs_pointer)));
    }
    if (@typeInfo(@TypeOf(value_pointer)) != .pointer) {
        @compileError("Expected value_pointer to be a pointer but got: " ++ @typeName(@TypeOf(value_pointer)));
    }
    if (access.len == 0) {
        lhs_pointer.* = value_pointer.*;
        return;
    }
    const next_lhs_pointer = switch (access[0]) {
        .struct_field => |name| &@field(lhs_pointer, name),
        .array_index => |index| &lhs_pointer[index],
        .optional_tag => {
            const Payload = @typeInfo(@TypeOf(lhs_pointer.*)).optional.child;
            if (value_pointer.*) {
                if (lhs_pointer.* != null) {
                    return;
                }
                lhs_pointer.* = @as(Payload, undefined);
            } else {
                lhs_pointer.* = null;
            }
            return;
        },
        .optional_payload => block: {
            if (lhs_pointer.*) |*payload_pointer| {
                break :block payload_pointer;
            } else {
                misc.error_context.new("Optional value is null.", .{});
                misc.error_context.append("Failed to access the optional's payload.", .{});
                return error.Inaccessible;
            }
        },
        .union_tag => {
            const Union = @TypeOf(lhs_pointer.*);
            const Tag = @typeInfo(Union).@"union".tag_type.?;
            const current_tag = std.meta.activeTag(lhs_pointer.*);
            const next_tag = value_pointer.*;
            if (current_tag == next_tag) {
                return;
            }
            inline for (@typeInfo(Union).@"union".field_names) |field_name| {
                if (@field(Tag, field_name) == next_tag) {
                    lhs_pointer.* = @unionInit(Union, field_name, undefined);
                    return;
                }
            }
            unreachable;
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
    return setFieldValue(next_lhs_pointer, next_access, value_pointer) catch |err| {
        switch (access[0]) {
            .struct_field => |name| misc.error_context.append("Access failure inside struct field: {s}", .{name}),
            .array_index => |index| misc.error_context.append("Access failure inside array index: {}", .{index}),
            .optional_tag => unreachable,
            .optional_payload => misc.error_context.append("Access failure inside optional payload.", .{}),
            .union_tag => unreachable,
            .union_field => |name| misc.error_context.append("Access failure inside tagged union field: {s}", .{name}),
        }
        return err;
    };
}

fn setFieldToDefault(lhs_pointer: anytype, comptime access: []const AccessElement, default_pointer: anytype) void {
    if (@typeInfo(@TypeOf(lhs_pointer)) != .pointer) {
        @compileError("Expected lhs_pointer to be a pointer but got: " ++ @typeName(@TypeOf(lhs_pointer)));
    }
    if (@typeInfo(@TypeOf(default_pointer)) != .pointer) {
        @compileError("Expected default_pointer to be a pointer but got: " ++ @typeName(@TypeOf(default_pointer)));
    }
    const Lhs = @typeInfo(@TypeOf(lhs_pointer)).pointer.child;
    const Default = @typeInfo(@TypeOf(default_pointer)).pointer.child;
    if (Lhs != Default) {
        @compileError(
            "Expected lhs_pointer and default_pointer point to same type but" ++
                " lhs_pointer is " ++ @typeName(@TypeOf(lhs_pointer)) ++
                " and default_pointer is " ++ @typeName(@TypeOf(default_pointer)),
        );
    }
    _ = setFieldToDefaultRecursive(Lhs, lhs_pointer, access, default_pointer);
}

fn setFieldToDefaultRecursive(
    comptime Type: type,
    lhs_pointer: *Type,
    comptime access: []const AccessElement,
    default_pointer_maybe: ?*const Type,
) bool {
    if (access.len == 0) {
        if (default_pointer_maybe) |default_pointer| {
            lhs_pointer.* = default_pointer.*;
            return true;
        } else {
            return false;
        }
    }
    const next_lhs_pointer, const next_default_pointer_maybe = switch (access[0]) {
        .struct_field => |name| .{
            &@field(lhs_pointer, name),
            if (default_pointer_maybe) |default_pointer| &@field(default_pointer, name) else block: {
                const info = &@typeInfo(Type).@"struct";
                comptime for (info.field_names, info.field_types, info.field_attrs) |field_name, Field, attr| {
                    if (std.mem.eql(u8, field_name, name)) {
                        break :block @as(?*const Field, @ptrCast(@alignCast(attr.default_value_ptr)));
                    }
                } else break :block null;
            },
        },
        .array_index => |index| .{
            &lhs_pointer[index],
            if (default_pointer_maybe) |default_pointer| &default_pointer[index] else null,
        },
        .optional_tag => {
            if (default_pointer_maybe) |default_pointer| {
                lhs_pointer.* = default_pointer.*;
                return true;
            } else {
                return false;
            }
        },
        .optional_payload => block: {
            if (lhs_pointer.*) |*lhs_payload_pointer| {
                if (default_pointer_maybe) |default_pointer| {
                    if (default_pointer.*) |*default_payload_pointer| {
                        break :block .{ lhs_payload_pointer, default_payload_pointer };
                    }
                }
                break :block .{ lhs_payload_pointer, null };
            } else {
                if (default_pointer_maybe) |default_pointer| {
                    lhs_pointer.* = default_pointer.*;
                    return true;
                } else {
                    return false;
                }
            }
        },
        .union_tag => {
            if (default_pointer_maybe) |default_pointer| {
                lhs_pointer.* = default_pointer.*;
                return true;
            } else {
                return false;
            }
        },
        .union_field => |name| block: {
            const expected_tag = @field(std.meta.Tag(@TypeOf(lhs_pointer.*)), name);
            const lhs_tag = std.meta.activeTag(lhs_pointer.*);
            if (lhs_tag != expected_tag) {
                if (default_pointer_maybe) |default_pointer| {
                    lhs_pointer.* = default_pointer.*;
                    return true;
                } else {
                    return false;
                }
            }
            if (default_pointer_maybe) |default_pointer| {
                const default_tag = std.meta.activeTag(default_pointer.*);
                if (default_tag == expected_tag) {
                    break :block .{ &@field(lhs_pointer, name), &@field(default_pointer, name) };
                }
            }
            break :block .{ &@field(lhs_pointer, name), null };
        },
    };
    const next_access = access[1..];
    const success = setFieldToDefaultRecursive(
        @TypeOf(next_lhs_pointer.*),
        next_lhs_pointer,
        next_access,
        next_default_pointer_maybe,
    );
    if (!success) {
        if (default_pointer_maybe) |default_pointer| {
            lhs_pointer.* = default_pointer.*;
            return true;
        }
    }
    return success;
}

fn serializedSizeOf(comptime Type: type) comptime_int {
    return switch (@typeInfo(Type)) {
        .void => 0,
        .bool => 1,
        .int => |*info| std.math.divCeil(comptime_int, info.bits, std.mem.byte_size_in_bits) catch {
            @compileError(std.fmt.comptimePrint(
                "Failed to ceil divide {} with {}.",
                .{ info.bits, std.mem.byte_size_in_bits },
            ));
        },
        .float => |*info| std.math.divCeil(comptime_int, info.bits, std.mem.byte_size_in_bits) catch {
            @compileError(std.fmt.comptimePrint(
                "Failed to ceil divide {} with {}.",
                .{ info.bits, std.mem.byte_size_in_bits },
            ));
        },
        .@"enum" => |*info| serializedSizeOf(info.tag_type),
        .optional => |*info| serializedSizeOf(bool) + serializedSizeOf(info.child),
        .array => |*info| info.len * serializedSizeOf(info.child),
        .@"struct" => |*info| {
            if (info.backing_integer) |IntType| {
                return serializedSizeOf(IntType);
            }
            var sum: usize = 0;
            for (info.field_types) |Field| {
                sum += serializedSizeOf(Field);
            }
            return sum;
        },
        .@"union" => |*info| {
            if (info.layout == .@"packed") {
                const IntType = @Int(.unsigned, @bitSizeOf(Type));
                return serializedSizeOf(IntType);
            }
            const Tag = info.tag_type orelse {
                @compileError("Union " ++ @typeName(Type) ++ " is not serializable. (Not tagged and not packed.)");
            };
            var max: usize = 0;
            inline for (info.field_types) |Field| {
                max = @max(max, serializedSizeOf(Field));
            }
            return serializedSizeOf(Tag) + max;
        },
        else => @compileError("Unsupported type: " ++ @typeName(Type)),
    };
}

inline fn getLocalFields(comptime Frame: type) []const LocalField {
    @setEvalBranchQuota(40000);
    comptime {
        var state = GetLocalFieldsState{};
        getLocalFieldsRecursive(&state, Frame);
        const final_fields = state.fields_buffer[0..state.fields_len].*;
        return &final_fields;
    }
}

fn getLocalFieldsRecursive(state: *GetLocalFieldsState, Type: type) void {
    switch (@typeInfo(Type)) {
        .void => {},
        .bool, .int, .float, .@"enum" => {
            state.addField(Type);
        },
        .@"struct" => |*info| if (info.layout == .@"packed") {
            state.addField(Type);
        } else {
            for (info.field_names, info.field_types) |field_name, Field| {
                state.push(.{ .struct_field = field_name });
                getLocalFieldsRecursive(state, Field);
                state.pop();
            }
        },
        .array => |*info| {
            inline for (0..info.len) |index| {
                state.push(.{ .array_index = index });
                getLocalFieldsRecursive(state, info.child);
                state.pop();
            }
        },
        .optional => |*info| {
            state.push(.optional_tag);
            state.addField(bool);
            state.pop();
            state.push(.optional_payload);
            getLocalFieldsRecursive(state, info.child);
            state.pop();
        },
        .@"union" => |*info| if (info.layout == .@"packed") {
            state.addField(Type);
        } else {
            const Tag = info.tag_type orelse @compileError(
                "Union " ++ @typeName(Type) ++ " is not serializable. (Not tagged and not packed.)",
            );
            state.push(.union_tag);
            state.addField(Tag);
            state.pop();
            const payload_start_offset = state.offset;
            var max_payload_end_offset = state.offset;
            for (info.field_names, info.field_types) |field_name, Field| {
                state.offset = payload_start_offset;
                state.push(.{ .union_field = field_name });
                getLocalFieldsRecursive(state, Field);
                state.pop();
                max_payload_end_offset = @max(max_payload_end_offset, state.offset);
            }
            state.offset = max_payload_end_offset;
        },
        else => @compileError("Unsupported type: " ++ @typeName(Type)),
    }
}

const GetLocalFieldsState = struct {
    fields_buffer: [max_number_of_fields]LocalField = undefined,
    fields_len: usize = 0,
    access_buffer: [max_field_path_len]AccessElement = undefined,
    access_len: usize = 0,
    offset: usize = 0,

    const Self = @This();

    pub fn push(self: *Self, access_element: AccessElement) void {
        if (self.access_len >= self.access_buffer.len) {
            @compileError("Maximum access length exceeded.");
        }
        self.access_buffer[self.access_len] = access_element;
        self.access_len += 1;
    }

    pub fn pop(self: *Self) void {
        if (self.access_len == 0) {
            @compileError("Unable to pop empty access element buffer.");
        }
        self.access_len -= 1;
    }

    pub fn addField(self: *Self, Type: type) void {
        if (self.fields_len >= self.fields_buffer.len) {
            @compileError("Maximum number of fields exceeded.");
        }
        var path_buffer: [max_field_path_len]u8 = undefined;
        var path_len: usize = 0;

        for (self.access_buffer[0..self.access_len]) |access| {
            switch (access) {
                .struct_field => |name| appendPathName(&path_buffer, &path_len, name),
                .array_index => |index| appendPathIndex(&path_buffer, &path_len, index),
                .optional_tag => appendPathName(&path_buffer, &path_len, tag_path_component),
                .optional_payload => appendPathName(&path_buffer, &path_len, payload_path_component),
                .union_tag => appendPathName(&path_buffer, &path_len, tag_path_component),
                .union_field => |name| appendPathName(&path_buffer, &path_len, name),
            }
        }

        const final_path = path_buffer[0..path_len].*;
        const final_access = self.access_buffer[0..self.access_len].*;
        const size = serializedSizeOf(Type);
        self.fields_buffer[self.fields_len] = .{
            .path = &final_path,
            .access = &final_access,
            .offset = self.offset,
            .size = size,
        };
        self.fields_len += 1;

        self.offset += size;
    }

    fn appendPathName(buffer: []u8, len: *usize, name: []const u8) void {
        if (len.* > 0) {
            if (len.* >= buffer.len) {
                @compileError("Maximum field path length exceeded.");
            }
            buffer[len.*] = path_separator;
            len.* += 1;
        }
        if (len.* + name.len > buffer.len) {
            @compileError("Maximum field path length exceeded.");
        }
        @memcpy(buffer[len.*..(len.* + name.len)], name);
        len.* += name.len;
    }

    fn appendPathIndex(buffer: []u8, len: *usize, index: usize) void {
        if (len.* > 0) {
            if (len.* >= buffer.len) {
                @compileError("Maximum field path length exceeded.");
            }
            buffer[len.*] = path_separator;
            len.* += 1;
        }
        const size = std.fmt.printInt(buffer[len.*..], index, 10, .lower, .{});
        len.* += size;
    }
};

const testing = std.testing;

test "readIronyFormat should load the same recording that writeIronyFormat saved" {
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
        packed_struct: packed struct(u32) { a: u18 = 0, b: u14 = 0 } = .{},
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
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeIronyFormat(Frame, testing.allocator, &saved_recording, &writer);
    var reader = std.Io.Reader.fixed(buffer[0..writer.end]);
    const loaded_recording = try readIronyFormat(Frame, testing.allocator, &reader, &.{});
    defer testing.allocator.free(loaded_recording);
    try testing.expectEqualSlices(Frame, &saved_recording, loaded_recording);
}

test "readIronyFormat should succeed when recording has more fields than expected" {
    const SavedFrame = struct { a: f32 = -1, b: f32 = -2 };
    const LoadedFrame = struct { a: f32 = -3 };
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeIronyFormat(SavedFrame, testing.allocator, &.{
        .{ .a = 1, .b = 2 },
        .{ .a = 3, .b = 4 },
        .{ .a = 5, .b = 6 },
    }, &writer);
    var reader = std.Io.Reader.fixed(buffer[0..writer.end]);
    const recording = try readIronyFormat(LoadedFrame, testing.allocator, &reader, &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .a = 1 },
        .{ .a = 3 },
        .{ .a = 5 },
    }, recording);
}

test "readIronyFormat should use default value when recording does not contain a value" {
    const SavedFrame = struct { a: f32 = -1 };
    const LoadedFrame = struct { a: f32 = -2, b: f32 = -3 };
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeIronyFormat(SavedFrame, testing.allocator, &.{
        .{ .a = 1 },
        .{ .a = 2 },
        .{ .a = 3 },
    }, &writer);
    var reader = std.Io.Reader.fixed(buffer[0..writer.end]);
    const recording = try readIronyFormat(LoadedFrame, testing.allocator, &reader, &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .a = 1, .b = -3 },
        .{ .a = 2, .b = -3 },
        .{ .a = 3, .b = -3 },
    }, recording);
}

test "readIronyFormat should use struct type default value when missing field does not have a runtime default value" {
    const SavedFrame = struct { a: ?struct { b: f32 = -1 } = null };
    const LoadedFrame = struct { a: ?struct { b: f32 = -2, c: f32 = -3 } = null };
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeIronyFormat(SavedFrame, testing.allocator, &.{
        .{ .a = null },
        .{ .a = .{ .b = 1 } },
        .{ .a = .{ .b = 2 } },
    }, &writer);
    var reader = std.Io.Reader.fixed(buffer[0..writer.end]);
    const recording = try readIronyFormat(LoadedFrame, testing.allocator, &reader, &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .a = null },
        .{ .a = .{ .b = 1, .c = -3 } },
        .{ .a = .{ .b = 2, .c = -3 } },
    }, recording);
}

test "readIronyFormat should succeed in loading fields that are smaller than expected" {
    const SavedFrame = struct { a: u16 = 11, b: i6 = 12, c: f32 = 13, d: enum(u2) { a = 0, b = 1 } = .a };
    const LoadedFrame = struct { a: u32 = 21, b: i12 = 22, c: f64 = 23, d: enum(u3) { a = 0, b = 1, c = 2 } = .b };
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeIronyFormat(SavedFrame, testing.allocator, &.{
        .{ .a = 0, .b = 0, .c = 0, .d = .a },
        .{ .a = 1, .b = 2, .c = 3, .d = .b },
        .{ .a = 2, .b = -4, .c = -6, .d = .a },
    }, &writer);
    var reader = std.Io.Reader.fixed(buffer[0..writer.end]);
    const recording = try readIronyFormat(LoadedFrame, testing.allocator, &reader, &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .a = 0, .b = 0, .c = 0, .d = .a },
        .{ .a = 1, .b = 2, .c = 3, .d = .b },
        .{ .a = 2, .b = -4, .c = -6, .d = .a },
    }, recording);
}

test "readIronyFormat should succeed in loading fields that are larger than expected when the values fit" {
    const SavedFrame = struct { a: u32 = 11, b: i12 = 12, c: f64 = 13, d: enum(u3) { a = 0, b = 1, c = 2 } = .a };
    const LoadedFrame = struct { a: u16 = 21, b: i6 = 22, c: f32 = 23, d: enum(u2) { a = 0, b = 1 } = .b };
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeIronyFormat(SavedFrame, testing.allocator, &.{
        .{ .a = 0, .b = 0, .c = 0, .d = .a },
        .{ .a = 1, .b = 2, .c = 3, .d = .b },
        .{ .a = 2, .b = -4, .c = -6, .d = .a },
    }, &writer);
    var reader = std.Io.Reader.fixed(buffer[0..writer.end]);
    const recording = try readIronyFormat(LoadedFrame, testing.allocator, &reader, &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .a = 0, .b = 0, .c = 0, .d = .a },
        .{ .a = 1, .b = 2, .c = 3, .d = .b },
        .{ .a = 2, .b = -4, .c = -6, .d = .a },
    }, recording);
}

test "readIronyFormat should use default value when loading fields that are larger than expected and values do not fit" {
    const SavedFrame = struct { a: u32 = 11, b: i12 = 12, c: enum(u3) { a = 0, b = 1, c = 2 } = .a };
    const LoadedFrame = struct { a: u16 = 21, b: i6 = 22, c: enum(u2) { a = 0, b = 1 } = .b };
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeIronyFormat(SavedFrame, testing.allocator, &.{
        .{ .a = 65536, .b = 1, .c = .a },
        .{ .a = 2, .b = 32, .c = .b },
        .{ .a = 3, .b = 3, .c = .c },
    }, &writer);
    var reader = std.Io.Reader.fixed(buffer[0..writer.end]);
    const recording = try readIronyFormat(LoadedFrame, testing.allocator, &reader, &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .a = 21, .b = 1, .c = .a },
        .{ .a = 2, .b = 22, .c = .b },
        .{ .a = 3, .b = 3, .c = .b },
    }, recording);
}

test "readIronyFormat should use default value when encountering invalid bool value" {
    const SavedFrame = struct { a: u8 = 1, b: ?u8 = null };
    const LoadedFrame = struct { a: bool = false, b: ?bool = null };
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeIronyFormat(SavedFrame, testing.allocator, &.{
        .{ .a = 0, .b = null },
        .{ .a = 0, .b = 0 },
        .{ .a = 1, .b = 1 },
        .{ .a = 2, .b = 2 },
    }, &writer);
    var reader = std.Io.Reader.fixed(buffer[0..writer.end]);
    const recording = try readIronyFormat(LoadedFrame, testing.allocator, &reader, &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .a = false, .b = null },
        .{ .a = false, .b = false },
        .{ .a = true, .b = true },
        .{ .a = false, .b = null },
    }, recording);
}

test "readIronyFormat should use default value when encountering invalid int value" {
    const SavedFrame = struct { a: u16 = 0, b: ?u16 = null };
    const LoadedFrame = struct { a: u9 = 1, b: ?u9 = null };
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeIronyFormat(SavedFrame, testing.allocator, &.{
        .{ .a = 0, .b = null },
        .{ .a = 0, .b = 0 },
        .{ .a = 511, .b = 511 },
        .{ .a = 512, .b = 512 },
    }, &writer);
    var reader = std.Io.Reader.fixed(buffer[0..writer.end]);
    const recording = try readIronyFormat(LoadedFrame, testing.allocator, &reader, &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .a = 0, .b = null },
        .{ .a = 0, .b = 0 },
        .{ .a = 511, .b = 511 },
        .{ .a = 1, .b = null },
    }, recording);
}

test "readIronyFormat should use default value when encountering invalid enum value" {
    const Enum = enum(u8) { a = 0, b = 1 };
    const SavedFrame = struct { a: u8 = 0, b: ?u8 = null };
    const LoadedFrame = struct { a: Enum = .a, b: ?Enum = null };
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeIronyFormat(SavedFrame, testing.allocator, &.{
        .{ .a = 0, .b = null },
        .{ .a = 0, .b = 0 },
        .{ .a = 1, .b = 1 },
        .{ .a = 2, .b = 2 },
    }, &writer);
    var reader = std.Io.Reader.fixed(buffer[0..writer.end]);
    const recording = try readIronyFormat(LoadedFrame, testing.allocator, &reader, &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .a = .a, .b = null },
        .{ .a = .a, .b = .a },
        .{ .a = .b, .b = .b },
        .{ .a = .a, .b = null },
    }, recording);
}

test "readIronyFormat should use default value when encountering invalid optional" {
    const TagAndPayload = struct { tag: u8 = 255, payload: u8 = 255 };
    const SavedFrame = struct { a: TagAndPayload = .{}, b: TagAndPayload = .{} };
    const LoadedFrame = struct { a: ?u8 = null, b: ?u8 = 0 };
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeIronyFormat(SavedFrame, testing.allocator, &.{
        .{ .a = .{ .tag = 0, .payload = 0 }, .b = .{ .tag = 0, .payload = 0 } },
        .{ .a = .{ .tag = 1, .payload = 0 }, .b = .{ .tag = 1, .payload = 0 } },
        .{ .a = .{ .tag = 1, .payload = 1 }, .b = .{ .tag = 1, .payload = 1 } },
        .{ .a = .{ .tag = 2, .payload = 1 }, .b = .{ .tag = 2, .payload = 1 } },
    }, &writer);
    var reader = std.Io.Reader.fixed(buffer[0..writer.end]);
    const recording = try readIronyFormat(LoadedFrame, testing.allocator, &reader, &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .a = null, .b = null },
        .{ .a = 0, .b = 0 },
        .{ .a = 1, .b = 1 },
        .{ .a = null, .b = 0 },
    }, recording);
}

test "readIronyFormat should use default value when encountering invalid tagged union" {
    const SaveTag = enum(u8) { a = 1, b = 2, c = 3 };
    const LoadTag = enum(u8) { a = 1, b = 2 };
    const SaveUnion = union(SaveTag) { a: u16, b: u16, c: u16 };
    const LoadUnion = union(LoadTag) { a: u8, b: u16 };
    const SavedFrame = struct { f1: SaveUnion = .{ .a = 0xFFFF }, f2: SaveUnion = .{ .b = 0xFFFF } };
    const LoadedFrame = struct { f1: LoadUnion = .{ .a = 128 }, f2: LoadUnion = .{ .b = 129 } };
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeIronyFormat(SavedFrame, testing.allocator, &.{
        .{ .f1 = .{ .a = 0 }, .f2 = .{ .a = 0 } },
        .{ .f1 = .{ .a = 1 }, .f2 = .{ .a = 1 } },
        .{ .f1 = .{ .b = 0 }, .f2 = .{ .b = 0 } },
        .{ .f1 = .{ .b = 1 }, .f2 = .{ .b = 1 } },
        .{ .f1 = .{ .c = 0 }, .f2 = .{ .c = 0 } },
        .{ .f1 = .{ .a = 255 }, .f2 = .{ .a = 255 } },
        .{ .f1 = .{ .a = 256 }, .f2 = .{ .a = 256 } },
        .{ .f1 = .{ .b = 255 }, .f2 = .{ .b = 255 } },
        .{ .f1 = .{ .b = 256 }, .f2 = .{ .b = 256 } },
    }, &writer);
    var reader = std.Io.Reader.fixed(buffer[0..writer.end]);
    const recording = try readIronyFormat(LoadedFrame, testing.allocator, &reader, &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{
        .{ .f1 = .{ .a = 0 }, .f2 = .{ .a = 0 } },
        .{ .f1 = .{ .a = 1 }, .f2 = .{ .a = 1 } },
        .{ .f1 = .{ .b = 0 }, .f2 = .{ .b = 0 } },
        .{ .f1 = .{ .b = 1 }, .f2 = .{ .b = 1 } },
        .{ .f1 = .{ .a = 128 }, .f2 = .{ .b = 129 } },
        .{ .f1 = .{ .a = 255 }, .f2 = .{ .a = 255 } },
        .{ .f1 = .{ .a = 128 }, .f2 = .{ .b = 129 } },
        .{ .f1 = .{ .b = 255 }, .f2 = .{ .b = 255 } },
        .{ .f1 = .{ .b = 256 }, .f2 = .{ .b = 256 } },
    }, recording);
}

test "readIronyFormat should load the same recording that writeIronyFormat saved when working with packed types" {
    const StructOfUnions = packed struct(u24) {
        a: packed union(u8) { u: u8, i: i8 } = .{ .u = 255 },
        b: packed union(u16) { u: u16, i: i16 } = .{ .u = 255 },

        const Self = @This();
        pub const Int = @Int(.unsigned, @bitSizeOf(Self));
    };
    const UnionOfStructs = packed union(u24) {
        a: packed struct(u24) { f1: u16 = 0xFFFF, f2: u8 = 0xFF },
        b: packed struct(u24) { f1: u8 = 0xFF, f2: u16 = 0xFFFF },

        const Self = @This();
        pub const Int = @Int(.unsigned, @bitSizeOf(Self));
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
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeIronyFormat(Frame, testing.allocator, &saved_recording, &writer);
    var reader = std.Io.Reader.fixed(buffer[0..writer.end]);
    const loaded_recording = try readIronyFormat(Frame, testing.allocator, &reader, &.{});
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
