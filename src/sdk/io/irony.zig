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
    Frame: type,
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

    const root = comptime getRootNode(Frame);
    encoder_writer.writeInt(FrameSize, @intCast(root.serialized_size), endian) catch |err| {
        misc.error_context.new("Failed to write frame size: {}", .{root.serialized_size});
        return err;
    };

    writeFieldList(&encoder_writer, root) catch |err| {
        misc.error_context.append("Failed to write field list.", .{});
        return err;
    };

    writeFrames(Frame, allocator, &encoder_writer, root, frames) catch |err| {
        misc.error_context.append("Failed to write frames.", .{});
        return err;
    };

    encoder_writer.flush() catch |err| {
        misc.error_context.new("Failed to flush encoder writer.", .{});
        return err;
    };
}

pub fn readIronyFormat(
    Frame: type,
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

    const root = comptime getRootNode(Frame);
    const remote_fields = readFieldList(&decoder_reader, remote_frame_size, root) catch |err| {
        misc.error_context.append("Failed to read field list.", .{});
        return err;
    };

    return readFrames(
        Frame,
        allocator,
        &decoder_reader,
        remote_frame_size,
        root,
        &remote_fields,
        default_frame,
    ) catch |err| {
        misc.error_context.append("Failed to read frames.", .{});
        return err;
    };
}

fn writeFieldList(writer: *std.Io.Writer, root: *const Node) !void {
    writer.writeInt(NumberOfFields, @intCast(root.number_of_fields), endian) catch |err| {
        misc.error_context.new("Failed to write number of fields: {}", .{root.number_of_fields});
        return err;
    };
    var path = FieldPath{};
    writeFields(writer, root, &path, 0) catch |err| {
        misc.error_context.append("Failed to write fields of the frame.", .{});
        return err;
    };
}

fn writeFields(writer: *std.Io.Writer, node: *const Node, path: *FieldPath, data_offset: usize) !void {
    switch (node.kind) {
        .empty => {},
        .value => writeField(writer, path.get(), data_offset, node.serialized_size) catch |err| {
            misc.error_context.append("Failed to write value field: {s}", .{path.get()});
            return err;
        },
        .@"struct" => |*@"struct"| {
            var field_data_offset = data_offset;
            for (@"struct".fields) |*field| {
                const saved_len = path.push(field.name);
                defer path.pop(saved_len);
                writeFields(writer, field.node, path, field_data_offset) catch |err| {
                    misc.error_context.append("Failed to write fields of struct field: {s}", .{field.name});
                    return err;
                };
                field_data_offset += field.node.serialized_size;
            }
        },
        .array => |*array| {
            for (0..array.len) |index| {
                const saved_len = path.pushIndex(index);
                defer path.pop(saved_len);
                const element_data_offset = data_offset + (index * array.element.serialized_size);
                writeFields(writer, array.element, path, element_data_offset) catch |err| {
                    misc.error_context.append("Failed to write fields of array element: {}", .{index});
                    return err;
                };
            }
        },
        .optional => |*optional| {
            const saved_len = path.push(tag_path_component);
            writeField(writer, path.get(), data_offset, serializedSizeOf(bool)) catch |err| {
                misc.error_context.append("Failed to write optional's tag field: {s}", .{path.get()});
                return err;
            };
            path.pop(saved_len);
            _ = path.push(payload_path_component);
            defer path.pop(saved_len);
            writeFields(writer, optional.payload, path, data_offset + serializedSizeOf(bool)) catch |err| {
                misc.error_context.append("Failed to write fields of optional's payload.", .{});
                return err;
            };
        },
        .@"union" => |*@"union"| {
            const saved_len = path.push(tag_path_component);
            writeField(writer, path.get(), data_offset, @"union".tag_size) catch |err| {
                misc.error_context.append("Failed to write union's tag field: {s}", .{path.get()});
                return err;
            };
            path.pop(saved_len);
            for (@"union".names, @"union".variants) |name, variant| {
                _ = path.push(name);
                defer path.pop(saved_len);
                writeFields(writer, variant, path, data_offset + @"union".tag_size) catch |err| {
                    misc.error_context.append("Failed to write fields of union variant: {s}", .{name});
                    return err;
                };
            }
        },
    }
}

fn writeField(writer: *std.Io.Writer, path: []const u8, offset: usize, size: usize) !void {
    writer.writeInt(FieldPathLength, @intCast(path.len), endian) catch |err| {
        misc.error_context.new("Failed to write the size of field path: {}", .{path.len});
        return err;
    };
    writer.writeAll(path) catch |err| {
        misc.error_context.new("Failed to write the field path: {s}", .{path});
        return err;
    };
    writer.writeInt(FieldOffset, @intCast(offset), endian) catch |err| {
        misc.error_context.new("Failed to write the field offset: {}", .{offset});
        return err;
    };
    writer.writeInt(FieldSize, @intCast(size), endian) catch |err| {
        misc.error_context.new("Failed to write the field size: {}", .{size});
        return err;
    };
}

fn readFieldList(
    reader: *std.Io.Reader,
    remote_frame_size: FrameSize,
    comptime root: *const Node,
) ![root.number_of_fields]?RemoteField {
    var remote_fields: [root.number_of_fields]?RemoteField = @splat(null);
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
        if (findFieldIndex(root, path)) |local_index| {
            remote_fields[local_index] = .{
                .offset = remote_offset,
                .size = remote_size,
            };
        }
    }
    return remote_fields;
}

fn findFieldIndex(root: *const Node, path: []const u8) ?usize {
    var node = root;
    var field_index: usize = 0;
    var components = std.mem.splitScalar(u8, path, path_separator);
    var component_maybe = if (path.len == 0) null else components.next();
    while (true) : (component_maybe = components.next()) {
        const component = component_maybe orelse return switch (node.kind) {
            .value => field_index,
            else => null,
        };
        switch (node.kind) {
            .empty, .value => return null,
            .@"struct" => |*@"struct"| {
                for (@"struct".fields) |*field| {
                    if (std.mem.eql(u8, field.name, component)) {
                        node = field.node;
                        break;
                    }
                    field_index += field.node.number_of_fields;
                } else return null;
            },
            .array => |*array| {
                const index = std.fmt.parseInt(usize, component, 10) catch return null;
                if (index >= array.len) {
                    return null;
                }
                field_index += index * array.element.number_of_fields;
                node = array.element;
            },
            .optional => |*optional| {
                if (std.mem.eql(u8, component, tag_path_component)) {
                    return if (components.next() == null) field_index else null;
                }
                if (!std.mem.eql(u8, component, payload_path_component)) {
                    return null;
                }
                field_index += 1;
                node = optional.payload;
            },
            .@"union" => |*@"union"| {
                if (std.mem.eql(u8, component, tag_path_component)) {
                    return if (components.next() == null) field_index else null;
                }
                field_index += 1;
                for (@"union".names, @"union".variants) |name, variant| {
                    if (std.mem.eql(u8, name, component)) {
                        node = variant;
                        break;
                    }
                    field_index += variant.number_of_fields;
                } else return null;
            },
        }
    }
}

fn getFieldPath(root: *const Node, field_index: usize, path: *FieldPath) void {
    var node = root;
    var index = field_index;
    while (true) switch (node.kind) {
        .empty, .value => return,
        .@"struct" => |*@"struct"| for (@"struct".fields) |*field| {
            if (index < field.node.number_of_fields) {
                _ = path.push(field.name);
                node = field.node;
                break;
            }
            index -= field.node.number_of_fields;
        } else unreachable,
        .array => |*array| {
            const element_fields = array.element.number_of_fields;
            _ = path.pushIndex(index / element_fields);
            index %= element_fields;
            node = array.element;
        },
        .optional => |*optional| {
            if (index == 0) {
                _ = path.push(tag_path_component);
                return;
            }
            index -= 1;
            _ = path.push(payload_path_component);
            node = optional.payload;
        },
        .@"union" => |*@"union"| {
            if (index == 0) {
                _ = path.push(tag_path_component);
                return;
            }
            index -= 1;
            for (@"union".names, @"union".variants) |name, variant| {
                if (index < variant.number_of_fields) {
                    _ = path.push(name);
                    node = variant;
                    break;
                }
                index -= variant.number_of_fields;
            } else unreachable;
        },
    };
}

const FieldPath = struct {
    buffer: [max_field_path_len]u8 = undefined,
    len: usize = 0,

    const Self = @This();

    fn get(self: *const Self) []const u8 {
        return self.buffer[0..self.len];
    }

    fn push(self: *Self, component: []const u8) usize {
        const saved_len = self.len;
        if (self.len > 0) {
            self.buffer[self.len] = path_separator;
            self.len += 1;
        }
        @memcpy(self.buffer[self.len..][0..component.len], component);
        self.len += component.len;
        return saved_len;
    }

    fn pushIndex(self: *Self, index: usize) usize {
        var index_buffer: [std.math.log10_int(@as(usize, std.math.maxInt(usize))) + 1]u8 = undefined;
        const index_len = std.fmt.printInt(&index_buffer, index, 10, .lower, .{});
        return self.push(index_buffer[0..index_len]);
    }

    fn pop(self: *Self, saved_len: usize) void {
        self.len = saved_len;
    }
};

fn writeFrames(
    Frame: type,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    root: *const Node,
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

    const frame_size = root.serialized_size;
    const array_of_structs = allocator.alloc(u8, frames.len * frame_size) catch |err| {
        misc.error_context.new("Failed to allocate array of structs buffer.", .{});
        return err;
    };
    defer allocator.free(array_of_structs);
    @memset(array_of_structs, 0);

    const plan = WritePlan.init(allocator, root) catch |err| {
        misc.error_context.append("Failed to initialize write plan.", .{});
        return err;
    };
    defer plan.deinit(allocator);
    for (frames, 0..) |*frame, index| {
        plan.write(array_of_structs[(index * frame_size)..][0..frame_size], frame);
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
    Frame: type,
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    remote_frame_size: FrameSize,
    root: *const Node,
    remote_fields: []const ?RemoteField,
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

    const column = allocator.alloc(u8, number_of_frames) catch |err| {
        misc.error_context.new("Failed to allocate column buffer.", .{});
        return err;
    };
    defer allocator.free(column);
    for (0..remote_frame_size) |offset| {
        reader.readSliceAll(column) catch |err| {
            misc.error_context.new("Failed to read bytes of frame offset {}.", .{offset});
            return err;
        };
        for (column, 0..) |byte, frame_index| {
            const byte_index = (frame_index * remote_frame_size) + offset;
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
        const context = ReadContext{
            .root = root,
            .remote_fields = remote_fields,
            .frame_data = array_of_structs[(frame_index * remote_frame_size)..][0..remote_frame_size],
            .frame_index = frame_index,
        };
        _ = readNode(&context, root, 0, frame, default_frame);
    }
    return frames;
}

fn writeValue(Type: type, value: Type, data: []u8) void {
    switch (@typeInfo(Type)) {
        .bool => data[0] = @intFromBool(value),
        .int => |*info| {
            const size = serializedSizeOf(Type);
            const WriteType = @Int(info.signedness, size * std.mem.byte_size_in_bits);
            std.mem.writeInt(WriteType, data[0..size], value, endian);
        },
        .float => |*info| writeValue(@Int(.unsigned, info.bits), @bitCast(value), data),
        .@"enum" => |*info| writeValue(info.tag_type, @backingInt(value), data),
        .@"struct" => |*info| {
            const IntType = info.backing_integer orelse @compileError("Unsupported type: " ++ @typeName(Type));
            writeValue(IntType, @backingInt(value), data);
        },
        .@"union" => |*info| {
            if (info.layout != .@"packed") {
                @compileError("Unsupported type: " ++ @typeName(Type));
            }
            writeValue(@Int(.unsigned, @bitSizeOf(Type)), @backingInt(value), data);
        },
        else => @compileError("Unsupported type: " ++ @typeName(Type)),
    }
}

fn readValue(Type: type, data: []const u8) !Type {
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
                .little => .{ data[0..read_len], data[read_len..] },
                .big => .{ data[(data.len - read_len)..], data[0..(data.len - read_len)] },
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

const Node = struct {
    size: usize,
    serialized_size: usize,
    number_of_fields: usize,
    max_path_len: usize,
    sanitize: ?*const fn (value_pointer: *anyopaque) void,
    kind: Kind,

    pub const Kind = union(enum) {
        empty: void,
        value: *const ValueOps,
        @"struct": Struct,
        array: Array,
        optional: Optional,
        @"union": Union,
    };
    pub const Struct = struct {
        fields: []const StructField,
    };
    pub const StructField = struct {
        name: [:0]const u8,
        offset: usize,
        default_value: ?*const anyopaque,
        node: *const Node,
    };
    pub const Array = struct {
        len: usize,
        element: *const Node,
    };
    pub const Optional = struct {
        payload: *const Node,
        ops: *const OptionalOps,
    };
    pub const Union = struct {
        tag_size: usize,
        names: []const [:0]const u8,
        variants: []const *const Node,
        ops: *const UnionOps,
    };
};

const ValueOps = struct {
    write: *const fn (value_pointer: *const anyopaque, data: []u8) void,
    read: *const fn (data: []const u8, value_pointer: *anyopaque) anyerror!void,

    pub fn fromType(Type: type) *const ValueOps {
        const Impl = struct {
            fn write(value_pointer: *const anyopaque, data: []u8) void {
                const typed_value_pointer: *const Type = @ptrCast(@alignCast(value_pointer));
                writeValue(Type, typed_value_pointer.*, data);
            }
            fn read(data: []const u8, value_pointer: *anyopaque) anyerror!void {
                const typed_value_pointer: *Type = @ptrCast(@alignCast(value_pointer));
                typed_value_pointer.* = readValue(Type, data) catch |err| {
                    misc.error_context.append("Failed to read value.", .{});
                    return err;
                };
            }
        };
        return &.{ .write = Impl.write, .read = Impl.read };
    }
};

const OptionalOps = struct {
    isSome: *const fn (optional_pointer: *const anyopaque) bool,
    getPayload: *const fn (optional_pointer: *anyopaque) *anyopaque,
    setNull: *const fn (optional_pointer: *anyopaque) void,
    setSome: *const fn (optional_pointer: *anyopaque) void,

    pub fn fromType(Optional: type) *const OptionalOps {
        const Payload = @typeInfo(Optional).optional.child;
        const Impl = struct {
            fn isSome(optional_pointer: *const anyopaque) bool {
                const typed_optional_pointer: *const Optional = @ptrCast(@alignCast(optional_pointer));
                return typed_optional_pointer.* != null;
            }
            fn getPayload(optional_pointer: *anyopaque) *anyopaque {
                if (@sizeOf(Payload) == 0) {
                    return optional_pointer;
                }
                const typed_optional_pointer: *Optional = @ptrCast(@alignCast(optional_pointer));
                return &typed_optional_pointer.*.?;
            }
            fn setNull(optional_pointer: *anyopaque) void {
                const typed_optional_pointer: *Optional = @ptrCast(@alignCast(optional_pointer));
                typed_optional_pointer.* = null;
            }
            fn setSome(optional_pointer: *anyopaque) void {
                const typed_optional_pointer: *Optional = @ptrCast(@alignCast(optional_pointer));
                typed_optional_pointer.* = @as(Payload, undefined);
            }
        };
        return &.{
            .isSome = Impl.isSome,
            .getPayload = Impl.getPayload,
            .setNull = Impl.setNull,
            .setSome = Impl.setSome,
        };
    }
};

const UnionOps = struct {
    getActiveFieldIndex: *const fn (union_pointer: *const anyopaque) usize,
    getFieldPointer: *const fn (union_pointer: *anyopaque, field_index: usize) *anyopaque,
    writeActiveTag: *const fn (union_pointer: *const anyopaque, data: []u8) void,
    readActiveTag: *const fn (union_pointer: *anyopaque, data: []const u8) anyerror!void,

    pub fn fromType(Union: type) *const UnionOps {
        const info = &@typeInfo(Union).@"union";
        const Tag = info.tag_type.?;
        const Impl = struct {
            fn getActiveFieldIndex(union_pointer: *const anyopaque) usize {
                const typed_union_pointer: *const Union = @ptrCast(@alignCast(union_pointer));
                const active_tag = std.meta.activeTag(typed_union_pointer.*);
                inline for (info.field_names, 0..) |field_name, field_index| {
                    if (@field(Tag, field_name) == active_tag) {
                        return field_index;
                    }
                }
                unreachable;
            }
            fn getFieldPointer(union_pointer: *anyopaque, field_index: usize) *anyopaque {
                const typed_union_pointer: *Union = @ptrCast(@alignCast(union_pointer));
                inline for (info.field_names, info.field_types, 0..) |field_name, Payload, index| {
                    if (index == field_index) {
                        if (@sizeOf(Payload) == 0) {
                            return union_pointer;
                        }
                        return &@field(typed_union_pointer, field_name);
                    }
                }
                unreachable;
            }
            fn writeActiveTag(union_pointer: *const anyopaque, data: []u8) void {
                const typed_union_pointer: *const Union = @ptrCast(@alignCast(union_pointer));
                writeValue(Tag, std.meta.activeTag(typed_union_pointer.*), data);
            }
            fn readActiveTag(union_pointer: *anyopaque, data: []const u8) anyerror!void {
                const typed_union_pointer: *Union = @ptrCast(@alignCast(union_pointer));
                const next_tag = readValue(Tag, data) catch |err| {
                    misc.error_context.append("Failed to read union's tag value.", .{});
                    return err;
                };
                if (std.meta.activeTag(typed_union_pointer.*) == next_tag) {
                    return;
                }
                inline for (info.field_names) |field_name| {
                    if (@field(Tag, field_name) == next_tag) {
                        typed_union_pointer.* = @unionInit(Union, field_name, undefined);
                        return;
                    }
                }
                unreachable;
            }
        };
        return &.{
            .getActiveFieldIndex = Impl.getActiveFieldIndex,
            .getFieldPointer = Impl.getFieldPointer,
            .writeActiveTag = Impl.writeActiveTag,
            .readActiveTag = Impl.readActiveTag,
        };
    }
};

fn getRootNode(Frame: type) *const Node {
    const root = getNode(Frame);
    if (root.serialized_size > max_frame_size) {
        @compileError("The frame size exceeds maximum allowed.");
    }
    if (root.number_of_fields > max_number_of_fields) {
        @compileError("Maximum number of fields exceeded.");
    }
    if (root.max_path_len > max_field_path_len + 1) {
        @compileError("Maximum field path length exceeded.");
    }
    return root;
}

fn getNode(Type: type) *const Node {
    return &NodeOf(Type).node;
}

fn NodeOf(Type: type) type {
    return struct {
        const node = buildNode(Type);
    };
}

fn buildNode(Type: type) Node {
    switch (@typeInfo(Type)) {
        .void => return .{
            .size = 0,
            .serialized_size = 0,
            .number_of_fields = 0,
            .max_path_len = 0,
            .sanitize = null,
            .kind = .empty,
        },
        .bool, .int, .float, .@"enum" => return buildValueNode(Type),
        .@"struct" => |*info| {
            if (info.layout == .@"packed") {
                return buildValueNode(Type);
            }
            var fields: [info.field_names.len]Node.StructField = undefined;
            var serialized_size: usize = 0;
            var number_of_fields: usize = 0;
            var max_path_len: usize = 0;
            for (info.field_names, info.field_types, info.field_attrs, &fields) |field_name, Field, attr, *field| {
                const field_node = getNode(Field);
                field.* = .{
                    .name = field_name,
                    .offset = @offsetOf(Type, field_name),
                    .default_value = attr.default_value_ptr,
                    .node = field_node,
                };
                serialized_size += field_node.serialized_size;
                number_of_fields += field_node.number_of_fields;
                max_path_len = @max(max_path_len, getChildPathLen(field_name.len, field_node));
            }
            const final_fields = fields;
            return .{
                .size = @sizeOf(Type),
                .serialized_size = serialized_size,
                .number_of_fields = number_of_fields,
                .max_path_len = max_path_len,
                .sanitize = misc.getTypeErasedSanitize(Type),
                .kind = .{ .@"struct" = .{ .fields = &final_fields } },
            };
        },
        .array => |*info| {
            const element = getNode(info.child);
            const max_index_len = if (info.len > 1) std.math.log10_int(@as(usize, info.len - 1)) + 1 else 1;
            return .{
                .size = @sizeOf(Type),
                .serialized_size = info.len * element.serialized_size,
                .number_of_fields = info.len * element.number_of_fields,
                .max_path_len = getChildPathLen(max_index_len, element),
                .sanitize = misc.getTypeErasedSanitize(Type),
                .kind = .{ .array = .{ .len = info.len, .element = element } },
            };
        },
        .optional => |*info| {
            const payload = getNode(info.child);
            return .{
                .size = @sizeOf(Type),
                .serialized_size = serializedSizeOf(bool) + payload.serialized_size,
                .number_of_fields = 1 + payload.number_of_fields,
                .max_path_len = @max(
                    getChildPathLen(tag_path_component.len, null),
                    getChildPathLen(payload_path_component.len, payload),
                ),
                .sanitize = misc.getTypeErasedSanitize(Type),
                .kind = .{ .optional = .{
                    .payload = payload,
                    .ops = OptionalOps.fromType(Type),
                } },
            };
        },
        .@"union" => |*info| {
            if (info.layout == .@"packed") {
                return buildValueNode(Type);
            }
            const Tag = info.tag_type orelse @compileError(
                "Union " ++ @typeName(Type) ++ " is not serializable. (Not tagged and not packed.)",
            );
            const tag_size = serializedSizeOf(Tag);
            var variants: [info.field_types.len]*const Node = undefined;
            var max_variant_size: usize = 0;
            var number_of_fields: usize = 1;
            var max_path_len: usize = getChildPathLen(tag_path_component.len, null);
            for (info.field_names, info.field_types, &variants) |field_name, Field, *variant| {
                variant.* = getNode(Field);
                max_variant_size = @max(max_variant_size, variant.*.serialized_size);
                number_of_fields += variant.*.number_of_fields;
                max_path_len = @max(max_path_len, getChildPathLen(field_name.len, variant.*));
            }
            const final_variants = variants;
            return .{
                .size = @sizeOf(Type),
                .serialized_size = tag_size + max_variant_size,
                .number_of_fields = number_of_fields,
                .max_path_len = max_path_len,
                .sanitize = misc.getTypeErasedSanitize(Type),
                .kind = .{ .@"union" = .{
                    .tag_size = tag_size,
                    .names = info.field_names,
                    .variants = &final_variants,
                    .ops = UnionOps.fromType(Type),
                } },
            };
        },
        else => @compileError("Unsupported type: " ++ @typeName(Type)),
    }
}

fn buildValueNode(Type: type) Node {
    return .{
        .size = @sizeOf(Type),
        .serialized_size = serializedSizeOf(Type),
        .number_of_fields = 1,
        .max_path_len = 0,
        .sanitize = misc.getTypeErasedSanitize(Type),
        .kind = .{ .value = ValueOps.fromType(Type) },
    };
}

fn getChildPathLen(component_len: usize, child: ?*const Node) usize {
    const child_path_len = if (child) |node| node.max_path_len else 0;
    return 1 + component_len + child_path_len;
}

const WritePlan = struct {
    steps: []const Step,

    const Self = @This();

    pub const Step = union(enum) {
        value: Value,
        optional: Optional,
        @"union": Union,
    };
    pub const Value = struct {
        memory_offset: usize,
        data_offset: usize,
        data_size: usize,
        ops: *const ValueOps,
    };
    pub const Optional = struct {
        memory_offset: usize,
        tag_data_offset: usize,
        payload_len: usize,
        ops: *const OptionalOps,
    };
    pub const Union = struct {
        memory_offset: usize,
        tag_data_offset: usize,
        tag_data_size: usize,
        variants: []const *const Node,
        ops: *const UnionOps,
    };

    pub fn init(allocator: std.mem.Allocator, root: *const Node) !Self {
        const steps = allocator.alloc(Step, root.number_of_fields) catch |err| {
            misc.error_context.new("Failed to allocate {} write plan steps.", .{root.number_of_fields});
            return err;
        };
        var len: usize = 0;
        fillSteps(steps, &len, root, 0, 0);
        return .{ .steps = steps };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        allocator.free(self.steps);
    }

    fn fillSteps(steps: []Step, len: *usize, node: *const Node, memory_offset: usize, data_offset: usize) void {
        switch (node.kind) {
            .empty => {},
            .value => |ops| {
                steps[len.*] = .{ .value = .{
                    .memory_offset = memory_offset,
                    .data_offset = data_offset,
                    .data_size = node.serialized_size,
                    .ops = ops,
                } };
                len.* += 1;
            },
            .@"struct" => |*@"struct"| {
                var field_data_offset = data_offset;
                for (@"struct".fields) |*field| {
                    fillSteps(steps, len, field.node, memory_offset + field.offset, field_data_offset);
                    field_data_offset += field.node.serialized_size;
                }
            },
            .array => |*array| {
                const element = array.element;
                for (0..array.len) |index| {
                    const element_memory_offset = memory_offset + (index * element.size);
                    const element_data_offset = data_offset + (index * element.serialized_size);
                    fillSteps(steps, len, element, element_memory_offset, element_data_offset);
                }
            },
            .optional => |*optional| {
                steps[len.*] = .{ .optional = .{
                    .memory_offset = memory_offset,
                    .tag_data_offset = data_offset,
                    .payload_len = optional.payload.number_of_fields,
                    .ops = optional.ops,
                } };
                len.* += 1;
                fillSteps(steps, len, optional.payload, 0, data_offset + serializedSizeOf(bool));
            },
            .@"union" => |*@"union"| {
                steps[len.*] = .{ .@"union" = .{
                    .memory_offset = memory_offset,
                    .tag_data_offset = data_offset,
                    .tag_data_size = @"union".tag_size,
                    .variants = @"union".variants,
                    .ops = @"union".ops,
                } };
                len.* += 1;
                for (@"union".variants) |variant| {
                    fillSteps(steps, len, variant, 0, data_offset + @"union".tag_size);
                }
            },
        }
    }

    pub fn write(self: *const Self, frame_data: []u8, frame: *const anyopaque) void {
        writeSteps(self.steps, frame_data, frame);
    }

    fn writeSteps(steps: []const Step, frame_data: []u8, base_pointer: *const anyopaque) void {
        var index: usize = 0;
        while (index < steps.len) switch (steps[index]) {
            .value => |*value| {
                const value_pointer = offsetConstPointer(base_pointer, value.memory_offset);
                value.ops.write(value_pointer, frame_data[value.data_offset..][0..value.data_size]);
                index += 1;
            },
            .optional => |*optional| {
                const optional_pointer = offsetConstPointer(base_pointer, optional.memory_offset);
                const payload_steps = steps[(index + 1)..][0..optional.payload_len];
                if (optional.ops.isSome(optional_pointer)) {
                    frame_data[optional.tag_data_offset] = 1;
                    const payload_pointer = optional.ops.getPayload(@constCast(optional_pointer));
                    writeSteps(payload_steps, frame_data, payload_pointer);
                }
                index += 1 + payload_steps.len;
            },
            .@"union" => |*@"union"| {
                const ops = @"union".ops;
                const union_pointer = offsetConstPointer(base_pointer, @"union".memory_offset);
                const tag_data = frame_data[@"union".tag_data_offset..][0..@"union".tag_data_size];
                ops.writeActiveTag(union_pointer, tag_data);
                const active_index = ops.getActiveFieldIndex(union_pointer);
                const variant_pointer = ops.getFieldPointer(@constCast(union_pointer), active_index);
                index += 1;
                for (@"union".variants, 0..) |variant, variant_index| {
                    const variant_steps = steps[index..][0..variant.number_of_fields];
                    if (variant_index == active_index) {
                        writeSteps(variant_steps, frame_data, variant_pointer);
                    }
                    index += variant_steps.len;
                }
            },
        };
    }
};

const ReadContext = struct {
    root: *const Node,
    remote_fields: []const ?RemoteField,
    frame_data: []const u8,
    frame_index: usize,

    const Self = @This();

    fn getFieldData(self: *const Self, field_index: usize) ?[]const u8 {
        const remote_field = self.remote_fields[field_index] orelse return null;
        return self.frame_data[remote_field.offset..][0..remote_field.size];
    }

    fn handleReadError(self: *const Self, err: anyerror, field_index: usize) void {
        var path = FieldPath{};
        getFieldPath(self.root, field_index, &path);
        misc.error_context.append(
            "Failed to read field with path {s} on frame {}. Falling back to default value.",
            .{ path.get(), self.frame_index },
        );
        if (!builtin.is_test) {
            misc.error_context.logWarning(err);
        }
    }
};

const ReadNodeResult = enum {
    completed,
    needs_parent_default,
};

fn readNode(
    context: *const ReadContext,
    node: *const Node,
    field_index: usize,
    lhs_pointer: *anyopaque,
    default_pointer_maybe: ?*const anyopaque,
) ReadNodeResult {
    const success = switch (node.kind) {
        .empty => true,
        .value => |ops| block: {
            const data = context.getFieldData(field_index) orelse break :block false;
            ops.read(data, lhs_pointer) catch |err| {
                context.handleReadError(err, field_index);
                break :block false;
            };
            break :block true;
        },
        .@"struct" => |*@"struct"| block: {
            var success = true;
            var child_field_index = field_index;
            for (@"struct".fields) |*field| {
                const field_default_pointer = if (default_pointer_maybe) |default_pointer| block_default: {
                    break :block_default offsetConstPointer(default_pointer, field.offset);
                } else field.default_value;
                const field_pointer = offsetPointer(lhs_pointer, field.offset);
                const result = readNode(context, field.node, child_field_index, field_pointer, field_default_pointer);
                if (result == .needs_parent_default) {
                    success = false;
                }
                child_field_index += field.node.number_of_fields;
            }
            break :block success;
        },
        .array => |*array| block: {
            var success = true;
            const element = array.element;
            for (0..array.len) |index| {
                const offset = index * element.size;
                const element_default_pointer = if (default_pointer_maybe) |default_pointer| block_default: {
                    break :block_default offsetConstPointer(default_pointer, offset);
                } else null;
                const element_pointer = offsetPointer(lhs_pointer, offset);
                const element_field_index = field_index + (index * element.number_of_fields);
                const result = readNode(context, element, element_field_index, element_pointer, element_default_pointer);
                if (result == .needs_parent_default) {
                    success = false;
                }
            }
            break :block success;
        },
        .optional => |*optional| block: {
            const ops = optional.ops;
            const data = context.getFieldData(field_index) orelse break :block false;
            const is_some = readValue(bool, data) catch |err| {
                context.handleReadError(err, field_index);
                break :block false;
            };
            if (!is_some) {
                ops.setNull(lhs_pointer);
                break :block true;
            }
            if (!ops.isSome(lhs_pointer)) {
                ops.setSome(lhs_pointer);
            }
            const payload_default_pointer = if (default_pointer_maybe) |default_pointer| block_default: {
                if (!ops.isSome(default_pointer)) {
                    break :block_default null;
                }
                break :block_default ops.getPayload(@constCast(default_pointer));
            } else null;
            const payload_pointer = ops.getPayload(lhs_pointer);
            const result = readNode(context, optional.payload, field_index + 1, payload_pointer, payload_default_pointer);
            break :block result == .completed;
        },
        .@"union" => |*@"union"| block: {
            const ops = @"union".ops;
            const data = context.getFieldData(field_index) orelse break :block false;
            ops.readActiveTag(lhs_pointer, data) catch |err| {
                context.handleReadError(err, field_index);
                break :block false;
            };
            const index = ops.getActiveFieldIndex(lhs_pointer);
            var variant_field_index = field_index + 1;
            for (@"union".variants[0..index]) |variant| {
                variant_field_index += variant.number_of_fields;
            }
            const variant_default_pointer = if (default_pointer_maybe) |default_pointer| block_default: {
                if (ops.getActiveFieldIndex(default_pointer) != index) {
                    break :block_default null;
                }
                break :block_default ops.getFieldPointer(@constCast(default_pointer), index);
            } else null;
            const variant_pointer = ops.getFieldPointer(lhs_pointer, index);
            const variant = @"union".variants[index];
            const result = readNode(context, variant, variant_field_index, variant_pointer, variant_default_pointer);
            break :block result == .completed;
        },
    };
    if (!success) {
        const default_pointer = default_pointer_maybe orelse return .needs_parent_default;
        copyBytes(lhs_pointer, default_pointer, node.size);
    }
    if (node.sanitize) |sanitize| {
        sanitize(lhs_pointer);
    }
    return .completed;
}

fn copyBytes(destination: *anyopaque, source: *const anyopaque, size: usize) void {
    const destination_bytes: [*]u8 = @ptrCast(destination);
    const source_bytes: [*]const u8 = @ptrCast(source);
    @memcpy(destination_bytes[0..size], source_bytes[0..size]);
}

fn offsetPointer(pointer: *anyopaque, offset: usize) *anyopaque {
    const bytes: [*]u8 = @ptrCast(pointer);
    return @ptrCast(bytes + offset);
}

fn offsetConstPointer(pointer: *const anyopaque, offset: usize) *const anyopaque {
    const bytes: [*]const u8 = @ptrCast(pointer);
    return @ptrCast(bytes + offset);
}

fn serializedSizeOf(Type: type) comptime_int {
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
        .@"struct" => |*info| {
            const IntType = info.backing_integer orelse @compileError("Unsupported type: " ++ @typeName(Type));
            return serializedSizeOf(IntType);
        },
        .@"union" => |*info| {
            if (info.layout != .@"packed") {
                @compileError("Unsupported type: " ++ @typeName(Type));
            }
            return serializedSizeOf(@Int(.unsigned, @bitSizeOf(Type)));
        },
        else => @compileError("Unsupported type: " ++ @typeName(Type)),
    };
}

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

test "readIronyFormat should sanitize values of types that have a sanitize function" {
    const Sanitized = struct {
        value: u8 = 0,
        pub fn sanitize(self: *@This()) void {
            self.value = @min(self.value, 10);
        }
    };
    const Frame = struct {
        a: Sanitized = .{},
        b: [2]Sanitized = .{ .{}, .{} },
        c: ?Sanitized = null,
        d: union(enum) { x: Sanitized, y: u8 } = .{ .y = 0 },
        sanitized_a: u8 = 0,
        pub fn sanitize(self: *@This()) void {
            self.sanitized_a = self.a.value;
        }
    };
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeIronyFormat(Frame, testing.allocator, &.{
        .{
            .a = .{ .value = 20 },
            .b = .{ .{ .value = 30 }, .{ .value = 5 } },
            .c = .{ .value = 40 },
            .d = .{ .x = .{ .value = 50 } },
        },
    }, &writer);
    var reader = std.Io.Reader.fixed(buffer[0..writer.end]);
    const recording = try readIronyFormat(Frame, testing.allocator, &reader, &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(Frame, &.{
        .{
            .a = .{ .value = 10 },
            .b = .{ .{ .value = 10 }, .{ .value = 5 } },
            .c = .{ .value = 10 },
            .d = .{ .x = .{ .value = 10 } },
            .sanitized_a = 10,
        },
    }, recording);
}

test "readIronyFormat should sanitize default values that are used as fallback" {
    const Sanitized = struct {
        value: u8 = 0,
        pub fn sanitize(self: *@This()) void {
            self.value = @min(self.value, 10);
        }
    };
    const SavedFrame = struct { a: u8 = 0 };
    const LoadedFrame = struct { a: u8 = 0, b: Sanitized = .{} };
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeIronyFormat(SavedFrame, testing.allocator, &.{.{ .a = 1 }}, &writer);
    var reader = std.Io.Reader.fixed(buffer[0..writer.end]);
    const recording = try readIronyFormat(LoadedFrame, testing.allocator, &reader, &.{ .b = .{ .value = 50 } });
    defer testing.allocator.free(recording);
    try testing.expectEqualSlices(LoadedFrame, &.{.{ .a = 1, .b = .{ .value = 10 } }}, recording);
}

test "readIronyFormat should load valid bounded strings when recording contains invalid length and sentinel" {
    const SavedString = struct { buffer: [5]u8, len: u8 };
    const SavedFrame = struct {
        a: SavedString = .{ .buffer = @splat(0), .len = 0 },
        b: SavedString = .{ .buffer = @splat(0), .len = 0 },
    };
    const LoadedFrame = struct {
        a: misc.BoundedArray(4, u8, 0, true) = .empty,
        b: misc.BoundedArray(4, u8, 0, true) = .empty,
    };
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeIronyFormat(SavedFrame, testing.allocator, &.{.{
        .a = .{ .buffer = "abXYZ".*, .len = 7 },
        .b = .{ .buffer = "abXYZ".*, .len = 2 },
    }}, &writer);
    var reader = std.Io.Reader.fixed(buffer[0..writer.end]);
    const recording = try readIronyFormat(LoadedFrame, testing.allocator, &reader, &.{});
    defer testing.allocator.free(recording);
    try testing.expectEqualStrings("abXY", recording[0].a.asSlice());
    try testing.expectEqualStrings("ab", recording[0].b.asSlice());
}
