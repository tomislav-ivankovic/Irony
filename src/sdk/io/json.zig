const std = @import("std");
const builtin = @import("builtin");
const misc = @import("../misc/root.zig");
const math = @import("../math/root.zig");

const buffer_size = 1024;

pub const JsonWhitespace = union(enum) {
    none: void,
    space: void,
    new_line: NewLine,

    const Self = @This();
    pub const NewLine = struct {
        current_indentation: usize = 0,
        indentation_string: []const u8 = "  ",
    };

    pub fn indented(self: *const Self) Self {
        switch (self.*) {
            .none => return .none,
            .space => return .space,
            .new_line => |n| {
                var new_line = n;
                new_line.current_indentation += 1;
                return .{ .new_line = new_line };
            },
        }
    }

    pub fn write(self: *const Self, writer: *std.Io.Writer) !void {
        switch (self.*) {
            .none => {},
            .space => {
                writer.writeByte(' ') catch |err| {
                    misc.error_context.new("Failed to write space character.", .{});
                    return err;
                };
            },
            .new_line => |*new_line| {
                writer.writeByte('\n') catch |err| {
                    misc.error_context.new("Failed to write new line character.", .{});
                    return err;
                };
                for (0..new_line.current_indentation) |index| {
                    writer.writeAll(new_line.indentation_string) catch |err| {
                        misc.error_context.new("Failed to write indentation: {}", .{index});
                        return err;
                    };
                }
            },
        }
    }

    pub fn writeSpace(self: *const Self, writer: *std.Io.Writer) !void {
        switch (self.*) {
            .none => {},
            .space, .new_line => {
                writer.writeByte(' ') catch |err| {
                    misc.error_context.new("Failed to write space character.", .{});
                    return err;
                };
            },
        }
    }
};

pub fn writeJsonValue(
    comptime Type: type,
    value: *const Type,
    writer: *std.Io.Writer,
    whitespace: *const JsonWhitespace,
) !void {
    return writeNode(writer, getNode(Type), value, whitespace) catch |err| {
        misc.error_context.append("Failed to write root value.", .{});
        return err;
    };
}

pub fn readJsonValue(comptime Type: type, reader: *std.Io.Reader, default: ?*const Type) !Type {
    var buffer: [buffer_size]u8 = undefined;
    var allocator = std.heap.FixedBufferAllocator.init(&buffer);
    var json_reader = std.json.Reader.init(allocator.allocator(), reader);
    defer json_reader.deinit();
    const context = ReadContext{ .reader = &json_reader, .allocator = allocator.allocator() };
    var value: Type = undefined;
    readNode(&context, getNode(Type), &value, default) catch |err| {
        misc.error_context.append("Failed to read root value.", .{});
        return err;
    };
    return value;
}

pub fn writeLargeJsonArray(
    Element: type,
    slice: []const Element,
    writer: *std.Io.Writer,
) !void {
    writer.writeAll("[\n") catch |err| {
        misc.error_context.new("Failed to write array start token.", .{});
        return err;
    };
    for (slice, 0..) |*element, index| {
        errdefer misc.error_context.append("Failed to write array element at index: {}", .{index});
        writeNode(writer, getNode(Element), element, &.none) catch |err| {
            misc.error_context.append("Failed to write element value.", .{});
            return err;
        };
        if (index < slice.len - 1) {
            writer.writeAll(",\n") catch |err| {
                misc.error_context.new("Failed to write next element separator.", .{});
                return err;
            };
        }
    }
    writer.writeByte(']') catch |err| {
        misc.error_context.new("Failed to write array end token.", .{});
        return err;
    };
}

pub fn readLargeJsonArray(
    Element: type,
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    default_element: ?*const Element,
) !std.ArrayList(Element) {
    var buffer: [buffer_size]u8 = undefined;
    var buffer_allocator = std.heap.FixedBufferAllocator.init(&buffer);
    var json_reader = std.json.Reader.init(buffer_allocator.allocator(), reader);
    defer json_reader.deinit();
    const context = ReadContext{ .reader = &json_reader, .allocator = buffer_allocator.allocator() };

    const begin_token = json_reader.next() catch |err| {
        misc.error_context.new("Failed to read array begin token.", .{});
        return err;
    };
    if (begin_token != .array_begin) {
        misc.error_context.new("Expected array begin token but got: {s}", .{@tagName(begin_token)});
        return error.UnexpectedToken;
    }

    var list = std.ArrayList(Element).empty;
    errdefer list.deinit(allocator);
    var index: usize = 0;
    while (true) {
        errdefer misc.error_context.append("Failed to read array element at index: {}", .{index});
        const token_type = json_reader.peekNextTokenType() catch |err| {
            misc.error_context.new("Failed to peek element token type.", .{});
            return err;
        };
        if (token_type == .array_end) {
            break;
        }
        var element: Element = undefined;
        readNode(&context, getNode(Element), &element, default_element) catch |err| {
            misc.error_context.append("Failed to read element value.", .{});
            return err;
        };
        list.append(allocator, element) catch |err| {
            misc.error_context.new("Failed to append read element to the result list.", .{});
            return err;
        };
        index += 1;
    }

    _ = json_reader.next() catch |err| {
        misc.error_context.new("Failed to read array end token.", .{});
        return err;
    };
    return list;
}

const max_object_fields = 256;

const Node = struct {
    size: usize,
    kind: Kind,

    pub const Kind = union(enum) {
        void: void,
        value: *const ValueOps,
        @"enum": Enum,
        optional: Optional,
        array: Array,
        tuple: Tuple,
        @"struct": Struct,
        @"union": Union,
        @"packed": *const PackedOps,
        bounded_array: BoundedArray,
        enum_array: EnumArray,
        single_line: SingleLine,
    };
    pub const Enum = struct {
        names: []const [:0]const u8,
        ops: *const EnumOps,
    };
    pub const Optional = struct {
        payload: *const Node,
        ops: *const OptionalOps,
    };
    pub const Array = struct {
        len: usize,
        element: *const Node,
    };
    pub const Tuple = struct {
        fields: []const TupleField,
    };
    pub const TupleField = struct {
        offset: usize,
        node: *const Node,
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
    pub const Union = struct {
        tag_type_name: [:0]const u8,
        names: []const [:0]const u8,
        variants: []const *const Node,
        ops: *const UnionOps,
    };
    pub const BoundedArray = struct {
        max_len: usize,
        buffer_offset: usize,
        is_string: bool,
        element: *const Node,
        ops: *const BoundedArrayOps,
    };
    pub const EnumArray = struct {
        entries: []const EnumArrayEntry,
        value: *const Node,
    };
    pub const EnumArrayEntry = struct {
        name: [:0]const u8,
        offset: usize,
    };
    pub const SingleLine = struct {
        name: [:0]const u8,
        offset: usize,
        node: *const Node,
    };
};

const ValueOps = struct {
    write: *const fn (writer: *std.Io.Writer, value_pointer: *const anyopaque) anyerror!void,
    read: *const fn (reader: *std.json.Reader, allocator: std.mem.Allocator, value_pointer: *anyopaque) anyerror!void,

    pub fn fromType(Type: type) *const ValueOps {
        const Impl = struct {
            fn write(writer: *std.Io.Writer, value_pointer: *const anyopaque) anyerror!void {
                const typed_value_pointer: *const Type = @ptrCast(@alignCast(value_pointer));
                switch (@typeInfo(Type)) {
                    .bool => try writeBool(writer, typed_value_pointer.*),
                    .int => try writeInt(writer, typed_value_pointer.*),
                    .float => try writeFloat(writer, typed_value_pointer.*),
                    else => @compileError("Unsupported type: " ++ @typeName(Type)),
                }
            }
            fn read(reader: *std.json.Reader, allocator: std.mem.Allocator, value_pointer: *anyopaque) anyerror!void {
                const typed_value_pointer: *Type = @ptrCast(@alignCast(value_pointer));
                typed_value_pointer.* = switch (@typeInfo(Type)) {
                    .bool => try readBool(reader),
                    .int => try readInt(Type, reader, allocator),
                    .float => try readFloat(Type, reader, allocator),
                    else => @compileError("Unsupported type: " ++ @typeName(Type)),
                };
            }
        };
        return &.{ .write = Impl.write, .read = Impl.read };
    }
};

const EnumOps = struct {
    getIndex: *const fn (enum_pointer: *const anyopaque) usize,
    setIndex: *const fn (enum_pointer: *anyopaque, index: usize) void,

    pub fn fromType(Enum: type) *const EnumOps {
        const Impl = struct {
            fn getIndex(enum_pointer: *const anyopaque) usize {
                const typed_enum_pointer: *const Enum = @ptrCast(@alignCast(enum_pointer));
                for (std.enums.values(Enum), 0..) |value, index| {
                    if (value == typed_enum_pointer.*) {
                        return index;
                    }
                }
                unreachable;
            }
            fn setIndex(enum_pointer: *anyopaque, index: usize) void {
                const typed_enum_pointer: *Enum = @ptrCast(@alignCast(enum_pointer));
                typed_enum_pointer.* = std.enums.values(Enum)[index];
            }
        };
        return &.{ .getIndex = Impl.getIndex, .setIndex = Impl.setIndex };
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
    setActiveField: *const fn (union_pointer: *anyopaque, field_index: usize) void,

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
            fn setActiveField(union_pointer: *anyopaque, field_index: usize) void {
                const typed_union_pointer: *Union = @ptrCast(@alignCast(union_pointer));
                inline for (info.field_names, 0..) |field_name, index| {
                    if (index == field_index) {
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
            .setActiveField = Impl.setActiveField,
        };
    }
};

const BoundedArrayOps = struct {
    getLen: *const fn (array_pointer: *const anyopaque) usize,
    setLen: *const fn (array_pointer: *anyopaque, len: usize) void,
    setEmpty: *const fn (array_pointer: *anyopaque) void,
    setStringTrimmed: *const fn (array_pointer: *anyopaque, string: []const u8) void,

    pub fn fromType(Array: type) *const BoundedArrayOps {
        const Impl = struct {
            fn getLen(array_pointer: *const anyopaque) usize {
                const typed_array_pointer: *const Array = @ptrCast(@alignCast(array_pointer));
                return typed_array_pointer.asSlice().len;
            }
            fn setLen(array_pointer: *anyopaque, len: usize) void {
                const typed_array_pointer: *Array = @ptrCast(@alignCast(array_pointer));
                typed_array_pointer.len = @intCast(len);
            }
            fn setEmpty(array_pointer: *anyopaque) void {
                const typed_array_pointer: *Array = @ptrCast(@alignCast(array_pointer));
                typed_array_pointer.* = .empty;
            }
            fn setStringTrimmed(array_pointer: *anyopaque, string: []const u8) void {
                if (Array.Child != u8) {
                    unreachable;
                }
                const typed_array_pointer: *Array = @ptrCast(@alignCast(array_pointer));
                typed_array_pointer.* = .fromSliceTrimmed(string);
            }
        };
        return &.{
            .getLen = Impl.getLen,
            .setLen = Impl.setLen,
            .setEmpty = Impl.setEmpty,
            .setStringTrimmed = Impl.setStringTrimmed,
        };
    }
};

const PackedOps = struct {
    write: *const fn (
        writer: *std.Io.Writer,
        value_pointer: *const anyopaque,
        whitespace: *const JsonWhitespace,
    ) anyerror!void,
    read: *const fn (
        context: *const ReadContext,
        value_pointer: *anyopaque,
        default_pointer: ?*const anyopaque,
    ) anyerror!void,

    pub fn fromType(Packed: type) *const PackedOps {
        const info = &@typeInfo(Packed).@"struct";
        const Unpacked = @Struct(.auto, null, info.field_names, info.field_types, info.field_attrs);
        const Impl = struct {
            fn unpack(packed_pointer: *const Packed) Unpacked {
                var unpacked: Unpacked = undefined;
                inline for (info.field_names) |field_name| {
                    @field(unpacked, field_name) = @field(packed_pointer, field_name);
                }
                return unpacked;
            }
            fn pack(unpacked_pointer: *const Unpacked) Packed {
                var packed_value: Packed = undefined;
                inline for (info.field_names) |field_name| {
                    @field(packed_value, field_name) = @field(unpacked_pointer, field_name);
                }
                return packed_value;
            }
            fn write(
                writer: *std.Io.Writer,
                value_pointer: *const anyopaque,
                whitespace: *const JsonWhitespace,
            ) anyerror!void {
                const unpacked = unpack(@ptrCast(@alignCast(value_pointer)));
                try writeNode(writer, getNode(Unpacked), &unpacked, whitespace);
            }
            fn read(
                context: *const ReadContext,
                value_pointer: *anyopaque,
                default_pointer: ?*const anyopaque,
            ) anyerror!void {
                var unpacked: Unpacked = undefined;
                if (default_pointer) |pointer| {
                    const default_unpacked = unpack(@ptrCast(@alignCast(pointer)));
                    try readNode(context, getNode(Unpacked), &unpacked, &default_unpacked);
                } else {
                    try readNode(context, getNode(Unpacked), &unpacked, null);
                }
                const typed_value_pointer: *Packed = @ptrCast(@alignCast(value_pointer));
                typed_value_pointer.* = pack(&unpacked);
            }
        };
        return &.{ .write = Impl.write, .read = Impl.read };
    }
};

fn getNode(Type: type) *const Node {
    return &NodeOf(Type).node;
}

fn NodeOf(Type: type) type {
    return struct {
        const node = buildNode(Type);
    };
}

fn buildNode(Type: type) Node {
    if (isBoundedArray(Type)) {
        return .{ .size = @sizeOf(Type), .kind = .{ .bounded_array = .{
            .max_len = Type.max_len,
            .buffer_offset = @offsetOf(Type, "buffer"),
            .is_string = Type.Child == u8,
            .element = getNode(Type.Child),
            .ops = BoundedArrayOps.fromType(Type),
        } } };
    }
    if (isEnumArray(Type)) {
        const key_names = @typeInfo(Type.Key).@"enum".field_names;
        if (key_names.len > max_object_fields) {
            @compileError("Enum array " ++ @typeName(Type) ++ " has too many keys.");
        }
        var entries: [key_names.len]Node.EnumArrayEntry = undefined;
        for (key_names, &entries) |key_name, *entry| {
            const index = Type.Indexer.indexOf(@field(Type.Key, key_name));
            entry.* = .{
                .name = key_name,
                .offset = @offsetOf(Type, "values") + (index * @sizeOf(Type.Value)),
            };
        }
        const final_entries = entries;
        return .{ .size = @sizeOf(Type), .kind = .{ .enum_array = .{
            .entries = &final_entries,
            .value = getNode(Type.Value),
        } } };
    }
    if (isVector(Type)) {
        return .{ .size = @sizeOf(Type), .kind = .{ .single_line = .{
            .name = "vector",
            .offset = @offsetOf(Type, "array"),
            .node = getNode(Type.Array),
        } } };
    }
    if (isMatrix(Type)) {
        return .{ .size = @sizeOf(Type), .kind = .{ .single_line = .{
            .name = "matrix",
            .offset = @offsetOf(Type, "array"),
            .node = getNode(Type.Flat),
        } } };
    }
    switch (@typeInfo(Type)) {
        .void => return .{ .size = 0, .kind = .void },
        .bool, .int, .float => return .{ .size = @sizeOf(Type), .kind = .{ .value = ValueOps.fromType(Type) } },
        .@"enum" => |*info| {
            switch (info.mode) {
                .exhaustive => {},
                .nonexhaustive => @compileError(
                    "Enum " ++ @typeName(Type) ++ " is nonexhaustive and therefore not supported.",
                ),
            }
            return .{ .size = @sizeOf(Type), .kind = .{ .@"enum" = .{
                .names = info.field_names,
                .ops = EnumOps.fromType(Type),
            } } };
        },
        .optional => |*info| return .{ .size = @sizeOf(Type), .kind = .{ .optional = .{
            .payload = getNode(info.child),
            .ops = OptionalOps.fromType(Type),
        } } },
        .array => |*info| return .{ .size = @sizeOf(Type), .kind = .{ .array = .{
            .len = info.len,
            .element = getNode(info.child),
        } } },
        .@"struct" => |*info| {
            if (info.layout == .@"packed") {
                return .{ .size = @sizeOf(Type), .kind = .{ .@"packed" = PackedOps.fromType(Type) } };
            }
            if (info.is_tuple) {
                var fields: [info.field_names.len]Node.TupleField = undefined;
                for (info.field_names, info.field_types, &fields) |field_name, Field, *field| {
                    field.* = .{ .offset = @offsetOf(Type, field_name), .node = getNode(Field) };
                }
                const final_fields = fields;
                return .{ .size = @sizeOf(Type), .kind = .{ .tuple = .{ .fields = &final_fields } } };
            }
            if (info.field_names.len > max_object_fields) {
                @compileError("Struct " ++ @typeName(Type) ++ " has too many fields.");
            }
            var fields: [info.field_names.len]Node.StructField = undefined;
            for (info.field_names, info.field_types, info.field_attrs, &fields) |field_name, Field, attr, *field| {
                field.* = .{
                    .name = field_name,
                    .offset = @offsetOf(Type, field_name),
                    .default_value = attr.default_value_ptr,
                    .node = getNode(Field),
                };
            }
            const final_fields = fields;
            return .{ .size = @sizeOf(Type), .kind = .{ .@"struct" = .{ .fields = &final_fields } } };
        },
        .@"union" => |*info| {
            const Tag = info.tag_type orelse {
                @compileError("Union " ++ @typeName(Type) ++ " is not tagged and therefore not serializable.");
            };
            var variants: [info.field_types.len]*const Node = undefined;
            for (info.field_types, &variants) |Payload, *variant| {
                variant.* = getNode(Payload);
            }
            const final_variants = variants;
            return .{ .size = @sizeOf(Type), .kind = .{ .@"union" = .{
                .tag_type_name = @typeName(Tag),
                .names = info.field_names,
                .variants = &final_variants,
                .ops = UnionOps.fromType(Type),
            } } };
        },
        else => @compileError("Unsupported type: " ++ @typeName(Type)),
    }
}

fn writeNode(
    writer: *std.Io.Writer,
    node: *const Node,
    value_pointer: *const anyopaque,
    whitespace: *const JsonWhitespace,
) anyerror!void {
    switch (node.kind) {
        .void => try writeVoid(writer),
        .value => |ops| try ops.write(writer, value_pointer),
        .@"enum" => |*@"enum"| {
            const tag_name = @"enum".names[@"enum".ops.getIndex(value_pointer)];
            std.json.Stringify.encodeJsonString(tag_name, .{}, writer) catch |err| {
                misc.error_context.new("Failed to write enum value: {s}", .{tag_name});
                return err;
            };
        },
        .optional => |*optional| {
            if (optional.ops.isSome(value_pointer)) {
                const payload_pointer = optional.ops.getPayload(@constCast(value_pointer));
                writeNode(writer, optional.payload, payload_pointer, whitespace) catch |err| {
                    misc.error_context.append("Failed to write optional's payload.", .{});
                    return err;
                };
            } else {
                writer.writeAll("null") catch |err| {
                    misc.error_context.new("Failed to write optional's null value.", .{});
                    return err;
                };
            }
        },
        .array => |*array| {
            const indented_whitespace = whitespace.indented();
            writer.writeByte('[') catch |err| {
                misc.error_context.new("Failed to write array begin token.", .{});
                return err;
            };
            indented_whitespace.write(writer) catch |err| {
                misc.error_context.append("Failed to write first element whitespace.", .{});
                return err;
            };
            for (0..array.len) |index| {
                errdefer misc.error_context.append("Failed to write array element at index: {}", .{index});
                const element_pointer = offsetConstPointer(value_pointer, index * array.element.size);
                writeNode(writer, array.element, element_pointer, &indented_whitespace) catch |err| {
                    misc.error_context.append("Failed to write element value.", .{});
                    return err;
                };
                if (index < array.len - 1) {
                    writer.writeByte(',') catch |err| {
                        misc.error_context.new("Failed to write next element separator.", .{});
                        return err;
                    };
                    indented_whitespace.write(writer) catch |err| {
                        misc.error_context.append("Failed to write next element whitespace.", .{});
                        return err;
                    };
                }
            }
            whitespace.write(writer) catch |err| {
                misc.error_context.append("Failed to write array end token whitespace.", .{});
                return err;
            };
            writer.writeByte(']') catch |err| {
                misc.error_context.new("Failed to write array end token.", .{});
                return err;
            };
        },
        .tuple => |*tuple| {
            const indented_whitespace = whitespace.indented();
            writer.writeByte('[') catch |err| {
                misc.error_context.new("Failed to write tuple begin token.", .{});
                return err;
            };
            indented_whitespace.write(writer) catch |err| {
                misc.error_context.append("Failed to write first field whitespace.", .{});
                return err;
            };
            for (tuple.fields, 0..) |*field, index| {
                errdefer misc.error_context.append("Failed to write tuple field: {}", .{index});
                const field_pointer = offsetConstPointer(value_pointer, field.offset);
                writeNode(writer, field.node, field_pointer, &indented_whitespace) catch |err| {
                    misc.error_context.append("Failed to write field value.", .{});
                    return err;
                };
                if (index < tuple.fields.len - 1) {
                    writer.writeByte(',') catch |err| {
                        misc.error_context.new("Failed to write next field separator.", .{});
                        return err;
                    };
                    indented_whitespace.write(writer) catch |err| {
                        misc.error_context.append("Failed to write next field whitespace.", .{});
                        return err;
                    };
                }
            }
            whitespace.write(writer) catch |err| {
                misc.error_context.append("Failed to write tuple end token whitespace.", .{});
                return err;
            };
            writer.writeByte(']') catch |err| {
                misc.error_context.new("Failed to write tuple end token.", .{});
                return err;
            };
        },
        .@"struct" => |*@"struct"| {
            const indented_whitespace = whitespace.indented();
            writer.writeByte('{') catch |err| {
                misc.error_context.new("Failed to write struct begin token.", .{});
                return err;
            };
            indented_whitespace.write(writer) catch |err| {
                misc.error_context.append("Failed to write first field whitespace.", .{});
                return err;
            };
            for (@"struct".fields, 0..) |*field, index| {
                errdefer misc.error_context.append("Failed to write struct field: {s}", .{field.name});
                std.json.Stringify.encodeJsonString(field.name, .{}, writer) catch |err| {
                    misc.error_context.new("Failed to write field name.", .{});
                    return err;
                };
                writer.writeByte(':') catch |err| {
                    misc.error_context.new("Failed to write name value separator.", .{});
                    return err;
                };
                indented_whitespace.writeSpace(writer) catch |err| {
                    misc.error_context.append("Failed to write field value whitespace.", .{});
                    return err;
                };
                const field_pointer = offsetConstPointer(value_pointer, field.offset);
                writeNode(writer, field.node, field_pointer, &indented_whitespace) catch |err| {
                    misc.error_context.append("Failed to write field value.", .{});
                    return err;
                };
                if (index < @"struct".fields.len - 1) {
                    writer.writeByte(',') catch |err| {
                        misc.error_context.new("Failed to write next field separator.", .{});
                        return err;
                    };
                    indented_whitespace.write(writer) catch |err| {
                        misc.error_context.append("Failed to write next field whitespace.", .{});
                        return err;
                    };
                }
            }
            whitespace.write(writer) catch |err| {
                misc.error_context.append("Failed to write struct end token whitespace.", .{});
                return err;
            };
            writer.writeByte('}') catch |err| {
                misc.error_context.new("Failed to write struct end token.", .{});
                return err;
            };
        },
        .@"union" => |*@"union"| {
            const field_index = @"union".ops.getActiveFieldIndex(value_pointer);
            const tag_name = @"union".names[field_index];
            writer.writeAll("{ ") catch |err| {
                misc.error_context.new("Failed to write union begin token.", .{});
                return err;
            };
            std.json.Stringify.encodeJsonString(tag_name, .{}, writer) catch |err| {
                misc.error_context.new("Failed to write union's tag: {s}", .{tag_name});
                return err;
            };
            writer.writeByte(':') catch |err| {
                misc.error_context.new("Failed to write union's tag payload separator: {s}", .{tag_name});
                return err;
            };
            whitespace.writeSpace(writer) catch |err| {
                misc.error_context.append("Failed to write union's tag payload whitespace.", .{});
                return err;
            };
            const payload_pointer = @"union".ops.getFieldPointer(@constCast(value_pointer), field_index);
            writeNode(writer, @"union".variants[field_index], payload_pointer, whitespace) catch |err| {
                misc.error_context.append("Failed to write union's payload: {s}", .{tag_name});
                return err;
            };
            writer.writeAll(" }") catch |err| {
                misc.error_context.new("Failed to write union end token.", .{});
                return err;
            };
        },
        .@"packed" => |ops| try ops.write(writer, value_pointer, whitespace),
        .bounded_array => |*array| {
            const len = array.ops.getLen(value_pointer);
            const buffer_pointer = offsetConstPointer(value_pointer, array.buffer_offset);
            if (array.is_string) {
                const string = @as([*]const u8, @ptrCast(buffer_pointer))[0..len];
                std.json.Stringify.encodeJsonString(string, .{}, writer) catch |err| {
                    misc.error_context.new("Failed to write bounded string value: {s}", .{string});
                    return err;
                };
                return;
            }
            const indented_whitespace = whitespace.indented();
            writer.writeByte('[') catch |err| {
                misc.error_context.new("Failed to write bounded array begin token.", .{});
                return err;
            };
            indented_whitespace.write(writer) catch |err| {
                misc.error_context.append("Failed to write first element whitespace.", .{});
                return err;
            };
            for (0..len) |index| {
                errdefer misc.error_context.append("Failed to write bounded array element: {}", .{index});
                const element_pointer = offsetConstPointer(buffer_pointer, index * array.element.size);
                writeNode(writer, array.element, element_pointer, &indented_whitespace) catch |err| {
                    misc.error_context.append("Failed to write element value.", .{});
                    return err;
                };
                if (index < len - 1) {
                    writer.writeByte(',') catch |err| {
                        misc.error_context.new("Failed to write next element separator.", .{});
                        return err;
                    };
                    indented_whitespace.write(writer) catch |err| {
                        misc.error_context.append("Failed to write next element whitespace.", .{});
                        return err;
                    };
                }
            }
            whitespace.write(writer) catch |err| {
                misc.error_context.append("Failed to write bounded array end token whitespace.", .{});
                return err;
            };
            writer.writeByte(']') catch |err| {
                misc.error_context.new("Failed to write bounded array end token.", .{});
                return err;
            };
        },
        .enum_array => |*array| {
            const indented_whitespace = whitespace.indented();
            writer.writeByte('{') catch |err| {
                misc.error_context.new("Failed to write enum array start token.", .{});
                return err;
            };
            indented_whitespace.write(writer) catch |err| {
                misc.error_context.append("Failed to write first entry whitespace.", .{});
                return err;
            };
            for (array.entries, 0..) |*entry, index| {
                errdefer misc.error_context.append("Failed to write enum array entry: {s}", .{entry.name});
                std.json.Stringify.encodeJsonString(entry.name, .{}, writer) catch |err| {
                    misc.error_context.new("Failed to write entry key.", .{});
                    return err;
                };
                writer.writeByte(':') catch |err| {
                    misc.error_context.new("Failed to write key value separator.", .{});
                    return err;
                };
                indented_whitespace.writeSpace(writer) catch |err| {
                    misc.error_context.append("Failed to write entry value whitespace.", .{});
                    return err;
                };
                const entry_pointer = offsetConstPointer(value_pointer, entry.offset);
                writeNode(writer, array.value, entry_pointer, &indented_whitespace) catch |err| {
                    misc.error_context.append("Failed to write entry value.", .{});
                    return err;
                };
                if (index < array.entries.len - 1) {
                    writer.writeByte(',') catch |err| {
                        misc.error_context.new("Failed to write next entry separator.", .{});
                        return err;
                    };
                    indented_whitespace.write(writer) catch |err| {
                        misc.error_context.append("Failed to write next entry whitespace.", .{});
                        return err;
                    };
                }
            }
            whitespace.write(writer) catch |err| {
                misc.error_context.append("Failed to write enum array end token whitespace.", .{});
                return err;
            };
            writer.writeByte('}') catch |err| {
                misc.error_context.new("Failed to write enum array end token.", .{});
                return err;
            };
        },
        .single_line => |*single_line| {
            const inner_whitespace: JsonWhitespace = switch (whitespace.*) {
                .none => .none,
                .space => .space,
                .new_line => .space,
            };
            const inner_pointer = offsetConstPointer(value_pointer, single_line.offset);
            writeNode(writer, single_line.node, inner_pointer, &inner_whitespace) catch |err| {
                misc.error_context.append("Failed to write {s}'s array.", .{single_line.name});
                return err;
            };
        },
    }
}

const ReadContext = struct {
    reader: *std.json.Reader,
    allocator: std.mem.Allocator,
};

fn readNode(
    context: *const ReadContext,
    node: *const Node,
    value_pointer: *anyopaque,
    default_pointer: ?*const anyopaque,
) anyerror!void {
    const start_height = context.reader.stackHeight();
    readNodeValue(context, node, value_pointer, default_pointer) catch |err| {
        try recoverFromReadError(context, err, start_height, default_pointer != null);
        copyBytes(value_pointer, default_pointer.?, node.size);
    };
}

fn recoverFromReadError(context: *const ReadContext, err: anyerror, start_height: usize, has_default: bool) !void {
    if (context.reader.stackHeight() != start_height) {
        context.reader.skipUntilStackHeight(start_height) catch |skip_err| {
            misc.error_context.new("Failed to skip the invalid value.", .{});
            return skip_err;
        };
    }
    if (has_default) {
        misc.error_context.append("Falling back to default value.", .{});
        if (!builtin.is_test) {
            misc.error_context.logWarning(err);
        }
    } else {
        misc.error_context.append("No default value to fall back to.", .{});
        return err;
    }
}

fn readNodeValue(
    context: *const ReadContext,
    node: *const Node,
    value_pointer: *anyopaque,
    default_pointer: ?*const anyopaque,
) anyerror!void {
    const reader = context.reader;
    const allocator = context.allocator;
    switch (node.kind) {
        .void => try readVoid(reader),
        .value => |ops| try ops.read(reader, allocator, value_pointer),
        .@"enum" => |*@"enum"| {
            const index = try readEnumIndex(reader, allocator, @"enum".names);
            @"enum".ops.setIndex(value_pointer, index);
        },
        .optional => |*optional| {
            const ops = optional.ops;
            const token_type = reader.peekNextTokenType() catch |err| {
                misc.error_context.new("Failed to peek optional token type.", .{});
                return err;
            };
            if (token_type == .null) {
                _ = reader.next() catch |err| {
                    misc.error_context.new("Failed to read null token.", .{});
                    return err;
                };
                ops.setNull(value_pointer);
                return;
            }
            const default_payload_pointer = if (default_pointer) |pointer| block: {
                if (!ops.isSome(pointer)) {
                    break :block null;
                }
                break :block ops.getPayload(@constCast(pointer));
            } else null;
            ops.setSome(value_pointer);
            readNode(context, optional.payload, ops.getPayload(value_pointer), default_payload_pointer) catch |err| {
                misc.error_context.append("Failed to read optional's payload.", .{});
                return err;
            };
        },
        .array => |*array| {
            const begin_token = reader.next() catch |err| {
                misc.error_context.new("Failed to read array begin token.", .{});
                return err;
            };
            if (begin_token != .array_begin) {
                misc.error_context.new("Expected array begin token but got: {s}", .{@tagName(begin_token)});
                return error.UnexpectedToken;
            }
            if (default_pointer) |pointer| {
                copyBytes(value_pointer, pointer, node.size);
            }
            var index: usize = 0;
            while (true) {
                errdefer misc.error_context.append("Failed to read array element at index: {}", .{index});
                const token_type = reader.peekNextTokenType() catch |err| {
                    misc.error_context.new("Failed to peek element token type.", .{});
                    return err;
                };
                if (token_type == .array_end) {
                    break;
                }
                if (index < array.len) {
                    const offset = index * array.element.size;
                    const default_element_pointer = if (default_pointer) |pointer| block: {
                        break :block offsetConstPointer(pointer, offset);
                    } else null;
                    const element_pointer = offsetPointer(value_pointer, offset);
                    readNode(context, array.element, element_pointer, default_element_pointer) catch |err| {
                        misc.error_context.append("Failed to read element value.", .{});
                        return err;
                    };
                } else {
                    reader.skipValue() catch |err| {
                        misc.error_context.new("Failed to skip element value.", .{});
                        return err;
                    };
                }
                index += 1;
            }
            _ = reader.next() catch |err| {
                misc.error_context.new("Failed to read array end token.", .{});
                return err;
            };
            if (default_pointer == null and index < array.len) {
                misc.error_context.new("JSON array ended early with length: {}", .{index});
                return error.EarlyEnd;
            }
        },
        .tuple => |*tuple| {
            const begin_token = reader.next() catch |err| {
                misc.error_context.new("Failed to read tuple begin token.", .{});
                return err;
            };
            if (begin_token != .array_begin) {
                misc.error_context.new("Expected array begin token but got: {s}", .{@tagName(begin_token)});
                return error.UnexpectedToken;
            }
            if (default_pointer) |pointer| {
                copyBytes(value_pointer, pointer, node.size);
            }
            var index: usize = 0;
            for (tuple.fields) |*field| {
                errdefer misc.error_context.append("Failed to read tuple field: {}", .{index});
                const token_type = reader.peekNextTokenType() catch |err| {
                    misc.error_context.new("Failed to peek field token type.", .{});
                    return err;
                };
                if (token_type == .array_end) {
                    break;
                }
                const default_field_pointer = if (default_pointer) |pointer| block: {
                    break :block offsetConstPointer(pointer, field.offset);
                } else null;
                const field_pointer = offsetPointer(value_pointer, field.offset);
                readNode(context, field.node, field_pointer, default_field_pointer) catch |err| {
                    misc.error_context.append("Failed to read field value.", .{});
                    return err;
                };
                index += 1;
            }
            while (true) {
                errdefer misc.error_context.append("Failed to skip tuple field: {}", .{index});
                const token_type = reader.peekNextTokenType() catch |err| {
                    misc.error_context.new("Failed to peek field token type.", .{});
                    return err;
                };
                if (token_type == .array_end) {
                    break;
                }
                reader.skipValue() catch |err| {
                    misc.error_context.new("Failed to skip field value.", .{});
                    return err;
                };
                index += 1;
            }
            _ = reader.next() catch |err| {
                misc.error_context.new("Failed to read tuple end token.", .{});
                return err;
            };
            if (default_pointer == null and index < tuple.fields.len) {
                misc.error_context.new("JSON array ended early with length: {}", .{index});
                return error.EarlyEnd;
            }
        },
        .@"struct" => |*@"struct"| {
            const begin_token = reader.next() catch |err| {
                misc.error_context.new("Failed to read struct begin token.", .{});
                return err;
            };
            if (begin_token != .object_begin) {
                misc.error_context.new("Expected object begin token but got: {s}", .{@tagName(begin_token)});
                return error.UnexpectedToken;
            }
            if (default_pointer) |pointer| {
                copyBytes(value_pointer, pointer, node.size);
            }
            var found_fields_buffer: [max_object_fields]bool = undefined;
            const found_fields = found_fields_buffer[0..@"struct".fields.len];
            @memset(found_fields, default_pointer != null);
            while (true) {
                const token = reader.nextAllocMax(allocator, .alloc_always, buffer_size) catch |err| {
                    misc.error_context.new("Failed to read next struct field token.", .{});
                    return err;
                };
                var is_token_freed = false;
                defer if (!is_token_freed) {
                    freeIfAllocated(allocator, token);
                    is_token_freed = true;
                };
                const key = switch (token) {
                    .allocated_string => |string| string,
                    .object_end => break,
                    else => {
                        misc.error_context.new("Expected string or object end token but got: {s}", .{@tagName(token)});
                        return error.UnexpectedToken;
                    },
                };
                var field_found = false;
                for (@"struct".fields, found_fields) |*field, *found| {
                    if (std.mem.eql(u8, field.name, key)) {
                        if (!is_token_freed) { // Field name is not needed while parsing the field value.
                            freeIfAllocated(allocator, token);
                            is_token_freed = true;
                        }
                        const default_field_pointer = if (default_pointer) |pointer| block: {
                            break :block offsetConstPointer(pointer, field.offset);
                        } else field.default_value;
                        const field_pointer = offsetPointer(value_pointer, field.offset);
                        readNode(context, field.node, field_pointer, default_field_pointer) catch |err| {
                            misc.error_context.append("Failed to read field value: {s}", .{field.name});
                            return err;
                        };
                        field_found = true;
                        found.* = true;
                        break;
                    }
                }
                if (!field_found) {
                    reader.skipValue() catch |err| {
                        misc.error_context.new("Failed to skip field value: {s}", .{key});
                        return err;
                    };
                }
            }
            for (@"struct".fields, found_fields) |*field, found| {
                if (!found) {
                    const err = error.FieldNotFound;
                    misc.error_context.new("Failed to find struct field inside JSON object: {s}", .{field.name});
                    const default_field_pointer = if (default_pointer) |pointer| block: {
                        break :block offsetConstPointer(pointer, field.offset);
                    } else field.default_value;
                    if (default_field_pointer) |pointer| {
                        misc.error_context.append("Falling back to default value.", .{});
                        if (!builtin.is_test) {
                            misc.error_context.logWarning(err);
                        }
                        copyBytes(offsetPointer(value_pointer, field.offset), pointer, field.node.size);
                    } else {
                        return err;
                    }
                }
            }
        },
        .@"union" => |*@"union"| {
            const ops = @"union".ops;
            const begin_token = reader.next() catch |err| {
                misc.error_context.new("Failed to read union begin token.", .{});
                return err;
            };
            if (begin_token != .object_begin) {
                misc.error_context.new("Expected object begin token but got: {s}", .{@tagName(begin_token)});
                return error.UnexpectedToken;
            }
            const default_field_index = if (default_pointer) |pointer| ops.getActiveFieldIndex(pointer) else null;
            const tag_start_height = reader.stackHeight();
            const field_index = readEnumIndex(reader, allocator, @"union".names) catch |err| block: {
                recoverFromReadError(context, err, tag_start_height, default_field_index != null) catch |e| {
                    misc.error_context.append("Failed to read union's tag. ({s})", .{@"union".tag_type_name});
                    return e;
                };
                break :block default_field_index.?;
            };
            ops.setActiveField(value_pointer, field_index);
            const default_payload_pointer = if (default_field_index == field_index) block: {
                break :block ops.getFieldPointer(@constCast(default_pointer.?), field_index);
            } else null;
            const payload_pointer = ops.getFieldPointer(value_pointer, field_index);
            readNode(context, @"union".variants[field_index], payload_pointer, default_payload_pointer) catch |err| {
                misc.error_context.append("Failed to read union's payload.", .{});
                return err;
            };
            const end_token = reader.next() catch |err| {
                misc.error_context.new("Failed to read union end token.", .{});
                return err;
            };
            if (end_token != .object_end) {
                misc.error_context.new("Expected object end token but got: {s}", .{@tagName(end_token)});
                return error.UnexpectedToken;
            }
        },
        .@"packed" => |ops| try ops.read(context, value_pointer, default_pointer),
        .bounded_array => |*array| {
            const ops = array.ops;
            if (array.is_string) {
                const token = reader.nextAllocMax(allocator, .alloc_always, buffer_size) catch |err| {
                    misc.error_context.new("Failed to read bounded string token.", .{});
                    return err;
                };
                defer freeIfAllocated(allocator, token);
                const string = switch (token) {
                    .allocated_string => |string| string,
                    else => {
                        misc.error_context.new("Expected a string token but got: {s}", .{@tagName(token)});
                        return error.UnexpectedToken;
                    },
                };
                ops.setStringTrimmed(value_pointer, string);
                return;
            }
            const begin_token = reader.next() catch |err| {
                misc.error_context.new("Failed to read bounded array begin token.", .{});
                return err;
            };
            if (begin_token != .array_begin) {
                misc.error_context.new("Expected array begin token but got: {s}", .{@tagName(begin_token)});
                return error.UnexpectedToken;
            }
            const default_len = if (default_pointer) |pointer| ops.getLen(pointer) else 0;
            const buffer_pointer = offsetPointer(value_pointer, array.buffer_offset);
            ops.setEmpty(value_pointer);
            var len: usize = 0;
            var index: usize = 0;
            while (true) {
                errdefer misc.error_context.append("Failed to read bounded array element at index: {}", .{index});
                const token_type = reader.peekNextTokenType() catch |err| {
                    misc.error_context.new("Failed to peek element token type.", .{});
                    return err;
                };
                if (token_type == .array_end) {
                    break;
                }
                if (len < array.max_len) {
                    const offset = len * array.element.size;
                    const default_element_pointer = if (index < default_len) block: {
                        const default_buffer_pointer = offsetConstPointer(default_pointer.?, array.buffer_offset);
                        break :block offsetConstPointer(default_buffer_pointer, index * array.element.size);
                    } else null;
                    const element_pointer = offsetPointer(buffer_pointer, offset);
                    readNode(context, array.element, element_pointer, default_element_pointer) catch |err| {
                        misc.error_context.append("Failed to read element value.", .{});
                        return err;
                    };
                    len += 1;
                    ops.setLen(value_pointer, len);
                } else {
                    reader.skipValue() catch |err| {
                        misc.error_context.new("Failed to skip element value.", .{});
                        return err;
                    };
                }
                index += 1;
            }
            _ = reader.next() catch |err| {
                misc.error_context.new("Failed to read bounded array end token.", .{});
                return err;
            };
        },
        .enum_array => |*array| {
            const begin_token = reader.next() catch |err| {
                misc.error_context.new("Failed to read enum array begin token.", .{});
                return err;
            };
            if (begin_token != .object_begin) {
                misc.error_context.new("Expected object begin token but got: {s}", .{@tagName(begin_token)});
                return error.UnexpectedToken;
            }
            if (default_pointer) |pointer| {
                copyBytes(value_pointer, pointer, node.size);
            }
            var found_keys_buffer: [max_object_fields]bool = undefined;
            const found_keys = found_keys_buffer[0..array.entries.len];
            @memset(found_keys, default_pointer != null);
            while (true) {
                const token = reader.nextAllocMax(allocator, .alloc_always, buffer_size) catch |err| {
                    misc.error_context.new("Failed to read next enum array entry token.", .{});
                    return err;
                };
                var is_token_freed = false;
                defer if (!is_token_freed) {
                    freeIfAllocated(allocator, token);
                    is_token_freed = true;
                };
                const key_name = switch (token) {
                    .allocated_string => |string| string,
                    .object_end => break,
                    else => {
                        misc.error_context.new("Expected string or object end token but got: {s}", .{@tagName(token)});
                        return error.UnexpectedToken;
                    },
                };
                var key_found = false;
                for (array.entries, found_keys) |*entry, *found| {
                    if (std.mem.eql(u8, entry.name, key_name)) {
                        errdefer misc.error_context.append("Failed to read enum array entry: {s}", .{entry.name});
                        if (!is_token_freed) { // Key name is not needed while parsing the value.
                            freeIfAllocated(allocator, token);
                            is_token_freed = true;
                        }
                        const default_entry_pointer = if (default_pointer) |pointer| block: {
                            break :block offsetConstPointer(pointer, entry.offset);
                        } else null;
                        const entry_pointer = offsetPointer(value_pointer, entry.offset);
                        readNode(context, array.value, entry_pointer, default_entry_pointer) catch |err| {
                            misc.error_context.append("Failed to read entry value.", .{});
                            return err;
                        };
                        key_found = true;
                        found.* = true;
                        break;
                    }
                }
                if (!key_found) {
                    reader.skipValue() catch |err| {
                        misc.error_context.new("Failed to skip enum array entry value: {s}", .{key_name});
                        return err;
                    };
                }
            }
            for (array.entries, found_keys) |*entry, found| {
                if (!found) {
                    misc.error_context.new("Failed to find enum array entry inside JSON object: {s}", .{entry.name});
                    return error.EntryNotFound;
                }
            }
        },
        .single_line => |*single_line| {
            const default_inner_pointer = if (default_pointer) |pointer| block: {
                break :block offsetConstPointer(pointer, single_line.offset);
            } else null;
            const inner_pointer = offsetPointer(value_pointer, single_line.offset);
            readNode(context, single_line.node, inner_pointer, default_inner_pointer) catch |err| {
                misc.error_context.append("Failed to read {s}'s array.", .{single_line.name});
                return err;
            };
        },
    }
}

fn readEnumIndex(reader: *std.json.Reader, allocator: std.mem.Allocator, names: []const [:0]const u8) !usize {
    const token = reader.nextAllocMax(allocator, .alloc_always, buffer_size) catch |err| {
        misc.error_context.new("Failed to read enum value token.", .{});
        return err;
    };
    defer freeIfAllocated(allocator, token);
    const string = switch (token) {
        .allocated_string => |string| string,
        else => {
            misc.error_context.new("Expected a string token but got: {s}", .{@tagName(token)});
            return error.UnexpectedToken;
        },
    };
    for (names, 0..) |name, index| {
        if (std.mem.eql(u8, name, string)) {
            return index;
        }
    }
    misc.error_context.new("Invalid enum value: {s}", .{string});
    return error.InvalidEnumValue;
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

fn writeVoid(writer: *std.Io.Writer) !void {
    writer.writeAll("{}") catch |err| {
        misc.error_context.new("Failed to write void value.", .{});
        return err;
    };
}

fn readVoid(reader: *std.json.Reader) !void {
    const token_type = reader.peekNextTokenType() catch |err| {
        misc.error_context.new("Failed to peek void token type.", .{});
        return err;
    };
    if (token_type != .object_begin) {
        misc.error_context.new("Expected object begin token but got: {s}", .{@tagName(token_type)});
        return error.UnexpectedToken;
    }
    reader.skipValue() catch |err| {
        misc.error_context.new("Failed to skip void value.", .{});
        return err;
    };
}

fn writeBool(writer: *std.Io.Writer, value: bool) !void {
    const string = if (value) "true" else "false";
    writer.writeAll(string) catch |err| {
        misc.error_context.new("Failed to write boolean value: {s}", .{string});
        return err;
    };
}

fn readBool(reader: *std.json.Reader) !bool {
    const token = reader.next() catch |err| {
        misc.error_context.new("Failed to read boolean value token.", .{});
        return err;
    };
    switch (token) {
        .false => return false,
        .true => return true,
        else => {
            misc.error_context.new("Expected true or false token but got: {s}", .{@tagName(token)});
            return error.UnexpectedToken;
        },
    }
}

fn writeInt(writer: *std.Io.Writer, value: anytype) !void {
    writer.print("{}", .{value}) catch |err| {
        misc.error_context.new("Failed to write int value: {}", .{value});
        return err;
    };
}

fn readInt(Type: type, reader: *std.json.Reader, allocator: std.mem.Allocator) !Type {
    const token = reader.nextAllocMax(allocator, .alloc_always, buffer_size) catch |err| {
        misc.error_context.new("Failed to read int value token.", .{});
        return err;
    };
    defer freeIfAllocated(allocator, token);
    const string = switch (token) {
        .allocated_number => |string| string,
        else => {
            misc.error_context.new("Expected a number token but got: {s}", .{@tagName(token)});
            return error.UnexpectedToken;
        },
    };
    return std.fmt.parseInt(Type, string, 10) catch |err| {
        misc.error_context.new("Failed to parse string as integer: {s}", .{string});
        return err;
    };
}

fn writeFloat(writer: *std.Io.Writer, value: anytype) !void {
    writer.print("{}", .{value}) catch |err| {
        misc.error_context.new("Failed to write float value: {}", .{value});
        return err;
    };
}

fn readFloat(Type: type, reader: *std.json.Reader, allocator: std.mem.Allocator) !Type {
    const token = reader.nextAllocMax(allocator, .alloc_always, buffer_size) catch |err| {
        misc.error_context.new("Failed to read float value token.", .{});
        return err;
    };
    defer freeIfAllocated(allocator, token);
    const string = switch (token) {
        .allocated_number => |string| string,
        else => {
            misc.error_context.new("Expected a number token but got: {s}", .{@tagName(token)});
            return error.UnexpectedToken;
        },
    };
    return std.fmt.parseFloat(Type, string) catch |err| {
        misc.error_context.new("Failed to parse string as float: {s}", .{string});
        return err;
    };
}

inline fn isBoundedArray(Type: type) bool {
    comptime return hasTag(Type, misc.bounded_array_tag);
}

inline fn isEnumArray(Type: type) bool {
    comptime {
        const info = @typeInfo(Type);
        if (info != .@"struct") return false;
        if (!@hasDecl(Type, "Indexer")) return false;
        if (!@hasDecl(Type, "Key")) return false;
        if (!@hasDecl(Type, "Value")) return false;
        if (!@hasDecl(Type, "len")) return false;
        return true;
    }
}

inline fn isVector(Type: type) bool {
    comptime return hasTag(Type, math.vector_tag);
}

inline fn isMatrix(Type: type) bool {
    comptime return hasTag(Type, math.matrix_tag);
}

fn freeIfAllocated(allocator: std.mem.Allocator, token: std.json.Token) void {
    switch (token) {
        .allocated_number, .allocated_string => |slice| {
            allocator.free(slice);
        },
        else => {},
    }
}

inline fn hasTag(Type: type, comptime tag: type) bool {
    comptime {
        const info = @typeInfo(Type);
        if (info != .@"struct" and info != .@"enum" and info != .@"union") return false;
        if (!@hasDecl(Type, "tag")) return false;
        if (@TypeOf(Type.tag) != type) return false;
        return Type.tag == tag;
    }
}

const testing = std.testing;

test "readJsonValue should read the same value that writeJsonValue saved" {
    const Value = struct {
        void: void = {},
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
        optional_1: ?i32 = 0,
        optional_2: ?f32 = 0,
        @"enum": enum { a, b } = .a,
        @"struct": struct { a: f32 = 0, b: f32 = 0 } = .{},
        packed_struct: packed struct { a: u18 = 0, b: u14 = 0 } = .{},
        tuple: struct { f32, f32 } = .{ 0, 0 },
        array: [2]f32 = .{ 0, 0 },
        tagged_union: union(enum) { i: i32, f: f32 } = .{ .i = 0 },
        array_of_struct: [2]struct { a: f32 = 0, b: f32 = 0 } = .{ .{}, .{} },
        struct_of_array: struct { a: [2]f32 = .{ 0, 0 }, b: [2]f32 = .{ 0, 0 } } = .{},
        bounded_array: misc.BoundedArray(4, f32, 0, false) = .empty,
        bounded_string: misc.BoundedArray(4, u8, 0, true) = .empty,
        enum_array: std.EnumArray(enum { a, b }, f32) = .initFill(0),
        vector: math.Vec2 = .zero,
        matrix: math.Mat2 = .zero,
        @"\"escape\"": enum { @"\"", @"\"\"" } = .@"\"",
    };
    const write_value = Value{
        .void = {},
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
        .optional_1 = null,
        .optional_2 = 0.3,
        .@"enum" = .b,
        .@"struct" = .{ .a = 1, .b = 2 },
        .packed_struct = .{ .a = 3, .b = 4 },
        .tuple = .{ 5, 6 },
        .array = .{ 7, 8 },
        .tagged_union = .{ .i = 9 },
        .array_of_struct = .{ .{ .a = 10, .b = 11 }, .{ .a = 12, .b = 13 } },
        .struct_of_array = .{ .a = .{ 14, 15 }, .b = .{ 16, 17 } },
        .bounded_array = .fromArray(.{ 18, 19 }),
        .bounded_string = .fromArray("123".*),
        .enum_array = .init(.{ .a = 20, .b = 21 }),
        .vector = .fromArray(.{ 22, 23 }),
        .matrix = .fromArray(.{ .{ 24, 25 }, .{ 26, 27 } }),
        .@"\"escape\"" = .@"\"\"",
    };
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeJsonValue(Value, &write_value, &writer, &.none);
    var reader = std.Io.Reader.fixed(buffer[0..writer.end]);
    const read_value = try readJsonValue(Value, &reader, &.{});
    try testing.expectEqual(write_value, read_value);
}

test "readLargeJsonArray should read the same value that writeLargeJsonArray saved" {
    const Element = struct {
        void: void = {},
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
        optional: ?i32 = 0,
        @"enum": enum { a, b } = .a,
        @"struct": struct { a: f32 = 0, b: f32 = 0 } = .{},
        packed_struct: packed struct { a: u18 = 0, b: u14 = 0 } = .{},
        tuple: struct { f32, f32 } = .{ 0, 0 },
        array: [2]f32 = .{ 0, 0 },
        tagged_union: union(enum) { i: i32, f: f32 } = .{ .i = 0 },
        array_of_struct: [2]struct { a: f32 = 0, b: f32 = 0 } = .{ .{}, .{} },
        struct_of_array: struct { a: [2]f32 = .{ 0, 0 }, b: [2]f32 = .{ 0, 0 } } = .{},
        bounded_array: misc.BoundedArray(4, f32, 0, false) = .empty,
        bounded_string: misc.BoundedArray(4, u8, 0, true) = .empty,
        enum_array: std.EnumArray(enum { a, b }, f32) = .initFill(0),
        vector: math.Vec2 = .zero,
        matrix: math.Mat2 = .zero,
        @"\"escape\"": enum { @"\"", @"\"\"" } = .@"\"",
    };
    const array = [2]Element{
        .{
            .void = {},
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
            .bounded_array = .fromArray(.{ 18, 19 }),
            .bounded_string = .fromArray("123".*),
            .enum_array = .init(.{ .a = 20, .b = 21 }),
            .vector = .fromArray(.{ 22, 23 }),
            .matrix = .fromArray(.{ .{ 24, 25 }, .{ 26, 27 } }),
            .@"\"escape\"" = .@"\"",
        },
        .{
            .void = {},
            .bool = false,
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
            .optional = 1,
            .@"enum" = .b,
            .@"struct" = .{ .a = 27, .b = 26 },
            .packed_struct = .{ .a = 25, .b = 24 },
            .tuple = .{ 23, 22 },
            .array = .{ 21, 20 },
            .tagged_union = .{ .i = 19 },
            .array_of_struct = .{ .{ .a = 18, .b = 17 }, .{ .a = 16, .b = 15 } },
            .struct_of_array = .{ .a = .{ 14, 13 }, .b = .{ 12, 11 } },
            .bounded_array = .fromArray(.{ 10, 9 }),
            .bounded_string = .fromArray("321".*),
            .enum_array = .init(.{ .a = 8, .b = 7 }),
            .vector = .fromArray(.{ 6, 5 }),
            .matrix = .fromArray(.{ .{ 4, 3 }, .{ 2, 1 } }),
            .@"\"escape\"" = .@"\"\"",
        },
    };
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeLargeJsonArray(Element, &array, &writer);
    var reader = std.Io.Reader.fixed(buffer[0..writer.end]);
    var list = try readLargeJsonArray(Element, testing.allocator, &reader, &.{});
    defer list.deinit(testing.allocator);
    try testing.expectEqualSlices(Element, &array, list.items);
}

test "readJsonValue should succeed when json has more values than expected" {
    const Value = struct {
        a: f32,
        d: struct { d1: f32 },
        e: [2]f32,
        f: [2]f32,
        g: misc.BoundedArray(2, f32, 0, false),
        h: misc.BoundedArray(2, u8, 0, true),
        i: std.EnumArray(enum { i1, i2 }, f32),
    };
    var reader = std.Io.Reader.fixed(
        \\{
        \\  "a": 1,
        \\  "b": 2,
        \\  "c": { "c1": 3 },
        \\  "d": { "d1": 4, "d2": 5 },
        \\  "e": [6, 7, 8],
        \\  "f": [9, 10, 11],
        \\  "g": [12, 13, 14],
        \\  "h": "abc",
        \\  "i": { "i1": 15, "i2": 16, "i3": 17 }
        \\}
    );
    const value = try readJsonValue(Value, &reader, null);
    try testing.expectEqual(Value{
        .a = 1,
        .d = .{ .d1 = 4 },
        .e = .{ 6, 7 },
        .f = .{ 9, 10 },
        .g = .fromArray(.{ 12, 13 }),
        .h = .fromArray("ab".*),
        .i = .init(.{ .i1 = 15, .i2 = 16 }),
    }, value);
}

test "readJsonValue should use default value when encountering missing value and default exists" {
    const Value = struct {
        a: f32 = -1,
        b: f32 = -2,
        c: struct { c1: f32 = -3, c2: f32 = -4 } = .{ .c1 = -5, .c2 = -6 },
        d: struct { d1: f32 = -7, d2: f32 = -8 } = .{ .d1 = -9, .d2 = -10 },
        e: [3]f32 = .{ -11, -12, -13 },
        f: struct { f32, f32, f32 } = .{ -14, -15, -16 },
        g: ?struct { g1: f32 = -17, g2: f32 = -18 } = .{ .g1 = -19, .g2 = -20 },
        h: ?struct { h1: f32 = -21, h2: f32 = -22 } = null,
        i: std.EnumArray(enum { i1, i2 }, f32) = .init(.{ .i1 = -23, .i2 = -24 }),
    };
    var reader = std.Io.Reader.fixed(
        \\{
        \\  "a": 1,
        \\  "d": { "d1": 2 },
        \\  "e": [3, 4],
        \\  "f": [5, 6],
        \\  "g": { "g1": 7 },
        \\  "h": { "h1": 8 },
        \\  "i": { "i1": 9 }
        \\}
    );
    const value = try readJsonValue(Value, &reader, &.{});
    try testing.expectEqual(Value{
        .a = 1,
        .b = -2,
        .c = .{ .c1 = -5, .c2 = -6 },
        .d = .{ .d1 = 2, .d2 = -10 },
        .e = .{ 3, 4, -13 },
        .f = .{ 5, 6, -16 },
        .g = .{ .g1 = 7, .g2 = -20 },
        .h = .{ .h1 = 8, .h2 = -22 },
        .i = .init(.{ .i1 = 9, .i2 = -24 }),
    }, value);
}

test "readJsonValue should use default value when encountering invalid value and default exists" {
    const Value = struct {
        a: f32 = -1,
        b: f32 = -2,
        c: struct { c1: f32 = -3, c2: f32 = -4 } = .{ .c1 = -5, .c2 = -6 },
        d: struct { d1: f32 = -7, d2: f32 = -8 } = .{ .d1 = -9, .d2 = -10 },
        e: [3]f32 = .{ -11, -12, -13 },
        f: struct { f32, f32, f32 } = .{ -14, -15, -16 },
        g: ?struct { g1: f32 = -17, g2: f32 = -18 } = .{ .g1 = -19, .g2 = -20 },
        h: ?struct { h1: f32 = -21, h2: f32 = -22 } = null,
        i: misc.BoundedArray(4, f32, 0, false) = .fromArray(.{ -23, -24 }),
        j: misc.BoundedArray(4, u8, 0, true) = .fromArray("ab".*),
        k: std.EnumArray(enum { k1, k2 }, f32) = .init(.{ .k1 = -25, .k2 = -26 }),
        l: std.EnumArray(enum { l1, l2 }, f32) = .init(.{ .l1 = -27, .l2 = -28 }),
    };
    var reader = std.Io.Reader.fixed(
        \\{
        \\  "a": 1,
        \\  "b": [false, false, false],
        \\  "c": false,
        \\  "d": { "d1": 2, "d2": false },
        \\  "e": [3, false, 4],
        \\  "f": [5, false, 6],
        \\  "g": { "g1": 7, "g2": false },
        \\  "h": { "h1": 8, "h2": false },
        \\  "i": [9, false, 10],
        \\  "j": false,
        \\  "k": { "k1": 11, "k2": false },
        \\  "l": false
        \\}
    );
    const value = try readJsonValue(Value, &reader, &.{});
    try testing.expectEqual(Value{
        .a = 1,
        .b = -2,
        .c = .{ .c1 = -5, .c2 = -6 },
        .d = .{ .d1 = 2, .d2 = -10 },
        .e = .{ 3, -12, 4 },
        .f = .{ 5, -15, 6 },
        .g = .{ .g1 = 7, .g2 = -20 },
        .h = .{ .h1 = 8, .h2 = -22 },
        .i = .fromArray(.{ 9, -24, 10 }),
        .j = .fromArray("ab".*),
        .k = .init(.{ .k1 = 11, .k2 = -26 }),
        .l = .init(.{ .l1 = -27, .l2 = -28 }),
    }, value);
}

test "readJsonValue should resolve mixed field order in JSON objects" {
    const Value = struct {
        a: struct { a1: f32, a2: f32 },
        b: struct { b1: f32, b2: f32 },
        c: std.EnumArray(enum { c1, c2 }, f32),
        d: std.EnumArray(enum { d1, d2 }, f32),
    };
    var reader = std.Io.Reader.fixed(
        \\{
        \\  "a": { "a1": 1, "a2": 2 },
        \\  "d": { "d2": 8, "d1": 7 },
        \\  "c": { "c1": 5, "c2": 6 },
        \\  "b": { "b2": 4, "b1": 3 }
        \\}
    );
    const value = try readJsonValue(Value, &reader, null);
    try testing.expectEqual(Value{
        .a = .{ .a1 = 1, .a2 = 2 },
        .b = .{ .b1 = 3, .b2 = 4 },
        .c = .init(.{ .c1 = 5, .c2 = 6 }),
        .d = .init(.{ .d1 = 7, .d2 = 8 }),
    }, value);
}

test "readJsonValue should fail when struct field is missing and default does not exist" {
    var reader = std.Io.Reader.fixed("{ \"a\": 1 }");
    try testing.expectError(error.FieldNotFound, readJsonValue(struct { a: f32, b: f32 }, &reader, null));
}

test "readJsonValue should fail when nested struct field is missing and default does not exist" {
    var reader = std.Io.Reader.fixed("{ \"a\": { \"a1\": 1 } }");
    const Value = struct { a: struct { a1: f32, a2: f32 } };
    try testing.expectError(error.FieldNotFound, readJsonValue(Value, &reader, null));
}

test "readJsonValue should use struct field default value when field is missing and default does not exist" {
    var reader = std.Io.Reader.fixed("{ \"a\": 1 }");
    const Value = struct { a: f32, b: f32 = -1 };
    try testing.expectEqual(Value{ .a = 1, .b = -1 }, try readJsonValue(Value, &reader, null));
}

test "readJsonValue should fail when JSON array is shorter than expected and default does not exist" {
    var reader = std.Io.Reader.fixed("[1, 2]");
    try testing.expectError(error.EarlyEnd, readJsonValue([3]f32, &reader, null));
}

test "readJsonValue should fail when JSON tuple is shorter than expected and default does not exist" {
    var reader = std.Io.Reader.fixed("[1, 2]");
    try testing.expectError(error.EarlyEnd, readJsonValue(struct { f32, f32, f32 }, &reader, null));
}

test "readJsonValue should fail when nested JSON array is shorter than expected and default does not exist" {
    var reader = std.Io.Reader.fixed("{ \"a\": [1, 2] }");
    try testing.expectError(error.EarlyEnd, readJsonValue(struct { a: [3]f32 }, &reader, null));
}

test "readJsonValue should fail when nested JSON tuple is shorter than expected and default does not exist" {
    var reader = std.Io.Reader.fixed("{ \"a\": [1, 2] }");
    try testing.expectError(error.EarlyEnd, readJsonValue(struct { a: struct { f32, f32, f32 } }, &reader, null));
}

test "readJsonValue should fail when optional payload's field is missing and default does not exist" {
    var reader = std.Io.Reader.fixed("{ \"a\": 1 }");
    try testing.expectError(error.FieldNotFound, readJsonValue(?struct { a: f32, b: f32 }, &reader, null));
}

test "readJsonValue should fail when enum array entry is missing and default does not exist" {
    var reader = std.Io.Reader.fixed("{ \"a\": 1 }");
    try testing.expectError(error.EntryNotFound, readJsonValue(std.EnumArray(enum { a, b }, f32), &reader, null));
}

test "writeJsonValue should write vector as an array" {
    const vector = math.Vec2.fromArray(.{ 1, 2 });
    var buffer: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeJsonValue(math.Vec2, &vector, &writer, &.none);
    try testing.expectEqualStrings("[1,2]", buffer[0..writer.end]);
}

test "writeJsonValue should write matrix as a flat array" {
    const matrix = math.Mat2.fromArray(.{ .{ 1, 2 }, .{ 3, 4 } });
    var buffer: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeJsonValue(math.Mat2, &matrix, &writer, &.none);
    try testing.expectEqualStrings("[1,2,3,4]", buffer[0..writer.end]);
}

test "writeJsonValue should write vector and matrix on a single line when whitespace is new line" {
    const Value = struct { vector: math.Vec2, matrix: math.Mat2 };
    const value = Value{
        .vector = .fromArray(.{ 1, 2 }),
        .matrix = .fromArray(.{ .{ 3, 4 }, .{ 5, 6 } }),
    };
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeJsonValue(Value, &value, &writer, &.{ .new_line = .{} });
    try testing.expectEqualStrings(
        \\{
        \\  "vector": [ 1, 2 ],
        \\  "matrix": [ 3, 4, 5, 6 ]
        \\}
    , buffer[0..writer.end]);
}

test "writeJsonValue should not write bounded array elements past the capacity when length is too large" {
    var bounded_array = misc.BoundedArray(2, f32, 0, false).fromArray(.{ 1, 2 });
    bounded_array.len = 3;
    var buffer: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeJsonValue(@TypeOf(bounded_array), &bounded_array, &writer, &.none);
    try testing.expectEqualStrings("[1,2]", buffer[0..writer.end]);
}

test "writeJsonValue should not write bounded string characters past the capacity when length is too large" {
    var bounded_string = misc.BoundedArray(2, u8, 0, false).fromArray("ab".*);
    bounded_string.len = 3;
    var buffer: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeJsonValue(@TypeOf(bounded_string), &bounded_string, &writer, &.none);
    try testing.expectEqualStrings("\"ab\"", buffer[0..writer.end]);
}
