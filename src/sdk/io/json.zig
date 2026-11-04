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
    return writeValue(writer, value, whitespace) catch |err| {
        misc.error_context.append("Failed to write root value.", .{});
        return err;
    };
}

pub fn readJsonValue(comptime Type: type, reader: *std.Io.Reader, default: ?*const Type) !Type {
    var buffer: [buffer_size]u8 = undefined;
    var allocator = std.heap.FixedBufferAllocator.init(&buffer);
    var json_reader = std.json.Reader.init(allocator.allocator(), reader);
    defer json_reader.deinit();
    return readValue(Type, &json_reader, allocator.allocator(), default) catch |err| {
        misc.error_context.append("Failed to read root value.", .{});
        return err;
    };
}

pub fn writeLargeJsonArray(
    comptime Element: type,
    slice: []const Element,
    writer: *std.Io.Writer,
) !void {
    writer.writeAll("[\n") catch |err| {
        misc.error_context.new("Failed to write array start token.", .{});
        return err;
    };
    for (slice, 0..) |*element, index| {
        errdefer misc.error_context.append("Failed to write array element at index: {}", .{index});
        writeValue(writer, element, &.none) catch |err| {
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
    comptime Element: type,
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    default_element: ?*const Element,
) !std.ArrayList(Element) {
    var buffer: [buffer_size]u8 = undefined;
    var buffer_allocator = std.heap.FixedBufferAllocator.init(&buffer);
    var json_reader = std.json.Reader.init(buffer_allocator.allocator(), reader);
    defer json_reader.deinit();

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
        const element = readValue(Element, &json_reader, buffer_allocator.allocator(), default_element) catch |err| {
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

fn writeValue(writer: *std.Io.Writer, value_pointer: anytype, whitespace: *const JsonWhitespace) !void {
    const Type = switch (@typeInfo(@TypeOf(value_pointer))) {
        .pointer => |info| info.child,
        else => @compileError("Expected value_pointer to be a pointer but got: " ++ @typeName(@TypeOf(value_pointer))),
    };
    if (isBoundedArray(Type)) {
        try writeBoundedArray(writer, value_pointer, whitespace);
    } else if (isEnumArray(Type)) {
        try writeEnumArray(writer, value_pointer, whitespace);
    } else if (isVector(Type)) {
        try writeVector(writer, value_pointer, whitespace);
    } else if (isMatrix(Type)) {
        try writeMatrix(writer, value_pointer, whitespace);
    } else switch (@typeInfo(Type)) {
        .void => try writeVoid(writer),
        .bool => try writeBool(writer, value_pointer.*),
        .int => try writeInt(writer, value_pointer.*),
        .float => try writeFloat(writer, value_pointer.*),
        .@"enum" => try writeEnum(writer, value_pointer.*),
        .optional => try writeOptional(writer, value_pointer, whitespace),
        .array => try writeArray(writer, value_pointer, whitespace),
        .@"struct" => |*info| switch (info.is_tuple) {
            true => try writeTuple(writer, value_pointer, whitespace),
            false => try writeStruct(writer, value_pointer, whitespace),
        },
        .@"union" => try writeUnion(writer, value_pointer, whitespace),
        else => @compileError("Unsupported type: " ++ @typeName(Type)),
    }
}

fn readValue(comptime Type: type, reader: *std.json.Reader, allocator: std.mem.Allocator, default: anytype) !Type {
    const Default = @TypeOf(default);
    if (!isPointerTo(Type, Default)) {
        @compileError("Expected default to be a pointer to " ++ @typeName(Type) ++ " but got: " ++ @typeName(Default));
    }
    const start_height = reader.stackHeight();
    const value_or_error = if (isBoundedArray(Type)) block: {
        break :block readBoundedArray(Type, reader, allocator, default);
    } else if (isEnumArray(Type)) block: {
        break :block readEnumArray(Type, reader, allocator, default);
    } else if (isVector(Type)) block: {
        break :block readVector(Type, reader, allocator, default);
    } else if (isMatrix(Type)) block: {
        break :block readMatrix(Type, reader, allocator, default);
    } else switch (@typeInfo(Type)) {
        .void => readVoid(reader),
        .bool => readBool(reader),
        .int => readInt(Type, reader, allocator),
        .float => readFloat(Type, reader, allocator),
        .@"enum" => readEnum(Type, reader, allocator),
        .optional => readOptional(Type, reader, allocator, default),
        .array => readArray(Type, reader, allocator, default),
        .@"struct" => |*info| switch (info.is_tuple) {
            true => readTuple(Type, reader, allocator, default),
            false => readStruct(Type, reader, allocator, default),
        },
        .@"union" => readUnion(Type, reader, allocator, default),
        else => @compileError("Unsupported type: " ++ @typeName(Type)),
    };
    return value_or_error catch |err_1| {
        if (reader.stackHeight() != start_height) {
            reader.skipUntilStackHeight(start_height) catch |err_2| {
                misc.error_context.new("Failed to skip the invalid value.", .{});
                return err_2;
            };
        }
        if (default) |d| {
            misc.error_context.append("Falling back to default value.", .{});
            if (!builtin.is_test) {
                misc.error_context.logWarning(err_1);
            }
            return d.*;
        } else {
            misc.error_context.append("No default value to fall back to.", .{});
            return err_1;
        }
    };
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

fn readInt(comptime Type: type, reader: *std.json.Reader, allocator: std.mem.Allocator) !Type {
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

fn readFloat(comptime Type: type, reader: *std.json.Reader, allocator: std.mem.Allocator) !Type {
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

fn writeEnum(writer: *std.Io.Writer, value: anytype) !void {
    const Type = @TypeOf(value);
    const info = &@typeInfo(Type).@"enum";
    switch (info.mode) {
        .exhaustive => {},
        .nonexhaustive => @compileError("Enum " ++ @typeName(Type) ++ " is nonexhaustive and therefore not supported."),
    }
    const tag_name = @tagName(value);
    std.json.Stringify.encodeJsonString(tag_name, .{}, writer) catch |err| {
        misc.error_context.new("Failed to write enum value: {s}", .{tag_name});
        return err;
    };
}

fn readEnum(comptime Type: type, reader: *std.json.Reader, allocator: std.mem.Allocator) !Type {
    const info = &@typeInfo(Type).@"enum";
    switch (info.mode) {
        .exhaustive => {},
        .nonexhaustive => @compileError("Enum " ++ @typeName(Type) ++ " is nonexhaustive and therefore not supported."),
    }
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
    inline for (info.field_names, info.field_values) |field_name, field_value| {
        if (std.mem.eql(u8, field_name, string)) {
            return @fromBackingInt(field_value);
        }
    }
    misc.error_context.new("Invalid enum value: {s}", .{string});
    return error.InvalidEnumValue;
}

fn writeOptional(writer: *std.Io.Writer, value_pointer: anytype, whitespace: *const JsonWhitespace) !void {
    if (value_pointer.*) |*child_pointer| {
        writeValue(writer, child_pointer, whitespace) catch |err| {
            misc.error_context.append("Failed to write optional's payload.", .{});
            return err;
        };
    } else {
        writer.writeAll("null") catch |err| {
            misc.error_context.new("Failed to write optional's null value.", .{});
            return err;
        };
    }
}

fn readOptional(comptime Type: type, reader: *std.json.Reader, allocator: std.mem.Allocator, default: anytype) !Type {
    const info = &@typeInfo(Type).optional;
    const Payload = info.child;
    const token_type = reader.peekNextTokenType() catch |err| {
        misc.error_context.new("Failed to peek optional token type.", .{});
        return err;
    };
    switch (token_type) {
        .null => {
            _ = reader.next() catch |err| {
                misc.error_context.new("Failed to read null token.", .{});
                return err;
            };
            return null;
        },
        else => {
            const default_payload = if (default) |d| block: {
                break :block if (d.*) |*payload| payload else null;
            } else null;
            return readValue(Payload, reader, allocator, default_payload) catch |err| {
                misc.error_context.append("Failed to read optional's payload.", .{});
                return err;
            };
        },
    }
}

fn writeArray(writer: *std.Io.Writer, value_pointer: anytype, whitespace: *const JsonWhitespace) !void {
    const indented_whitespace = whitespace.indented();
    writer.writeByte('[') catch |err| {
        misc.error_context.new("Failed to write array begin token.", .{});
        return err;
    };
    indented_whitespace.write(writer) catch |err| {
        misc.error_context.append("Failed to write first element whitespace.", .{});
        return err;
    };
    for (value_pointer, 0..) |*element_pointer, index| {
        errdefer misc.error_context.append("Failed to write array element at index: {}", .{index});
        writeValue(writer, element_pointer, &indented_whitespace) catch |err| {
            misc.error_context.append("Failed to write element value.", .{});
            return err;
        };
        if (index < value_pointer.len - 1) {
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
}

fn readArray(comptime Type: type, reader: *std.json.Reader, allocator: std.mem.Allocator, default: anytype) !Type {
    const info = &@typeInfo(Type).array;
    const Element = info.child;
    const begin_token = reader.next() catch |err| {
        misc.error_context.new("Failed to read array begin token.", .{});
        return err;
    };
    if (begin_token != .array_begin) {
        misc.error_context.new("Expected array begin token but got: {s}", .{@tagName(begin_token)});
        return error.UnexpectedToken;
    }
    var array: Type = if (default) |d| d.* else undefined;
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
            const default_element = if (default) |d| &d[index] else null;
            array[index] = readValue(Element, reader, allocator, default_element) catch |err| {
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
    if (default == null and (index + 1) < array.len) {
        misc.error_context.new("JSON array ended early with length: {}", .{index});
        return error.EarlyEnd;
    }
    return array;
}

fn writeTuple(writer: *std.Io.Writer, value_pointer: anytype, whitespace: *const JsonWhitespace) !void {
    const indented_whitespace = whitespace.indented();
    const info = @typeInfo(@TypeOf(value_pointer.*)).@"struct";
    writer.writeByte('[') catch |err| {
        misc.error_context.new("Failed to write tuple begin token.", .{});
        return err;
    };
    indented_whitespace.write(writer) catch |err| {
        misc.error_context.append("Failed to write first field whitespace.", .{});
        return err;
    };
    inline for (0..info.field_names.len) |index| {
        errdefer misc.error_context.append("Failed to write tuple field: {}", .{index});
        const field_pointer = &value_pointer[index];
        writeValue(writer, field_pointer, &indented_whitespace) catch |err| {
            misc.error_context.append("Failed to write field value.", .{});
            return err;
        };
        if (index < value_pointer.len - 1) {
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
}

fn readTuple(comptime Type: type, reader: *std.json.Reader, allocator: std.mem.Allocator, default: anytype) !Type {
    const info = @typeInfo(Type).@"struct";
    const begin_token = reader.next() catch |err| {
        misc.error_context.new("Failed to read tuple begin token.", .{});
        return err;
    };
    if (begin_token != .array_begin) {
        misc.error_context.new("Expected array begin token but got: {s}", .{@tagName(begin_token)});
        return error.UnexpectedToken;
    }
    var tuple: Type = if (default) |d| d.* else undefined;
    var index: usize = 0;
    inline for (info.field_names, info.field_types) |field_name, Field| {
        errdefer misc.error_context.append("Failed to read tuple field: {}", .{index});
        const token_type = reader.peekNextTokenType() catch |err| {
            misc.error_context.new("Failed to peek field token type.", .{});
            return err;
        };
        if (token_type == .array_end) {
            break;
        }
        const default_field = if (default) |d| &@field(d, field_name) else null;
        @field(tuple, field_name) = readValue(Field, reader, allocator, default_field) catch |err| {
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
    if (default == null and (index + 1) < info.field_names.len) {
        misc.error_context.new("JSON array ended early with length: {}", .{index});
        return error.EarlyEnd;
    }
    return tuple;
}

fn writeStruct(writer: *std.Io.Writer, value_pointer: anytype, whitespace: *const JsonWhitespace) !void {
    const indented_whitespace = whitespace.indented();
    const info = @typeInfo(@TypeOf(value_pointer.*)).@"struct";
    writer.writeByte('{') catch |err| {
        misc.error_context.new("Failed to write struct begin token.", .{});
        return err;
    };
    indented_whitespace.write(writer) catch |err| {
        misc.error_context.append("Failed to write first field whitespace.", .{});
        return err;
    };
    inline for (info.field_names, 0..) |field_name, index| {
        errdefer misc.error_context.append("Failed to write struct field: {s}", .{field_name});
        std.json.Stringify.encodeJsonString(field_name, .{}, writer) catch |err| {
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
        const field_pointer = &@field(value_pointer, field_name);
        writeValue(writer, field_pointer, &indented_whitespace) catch |err| {
            misc.error_context.append("Failed to write field value.", .{});
            return err;
        };
        if (index < info.field_names.len - 1) {
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
}

fn readStruct(comptime Type: type, reader: *std.json.Reader, allocator: std.mem.Allocator, default: anytype) !Type {
    const info = @typeInfo(Type).@"struct";
    const begin_token = reader.next() catch |err| {
        misc.error_context.new("Failed to read struct begin token.", .{});
        return err;
    };
    if (begin_token != .object_begin) {
        misc.error_context.new("Expected object begin token but got: {s}", .{@tagName(begin_token)});
        return error.UnexpectedToken;
    }
    var structure: Type = if (default) |d| d.* else undefined;
    var found_fields: [info.field_names.len]bool = @splat(default != null);
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
        inline for (info.field_names, info.field_types, info.field_attrs, 0..) |field_name, Field, attr, index| {
            if (std.mem.eql(u8, field_name, key)) {
                if (!is_token_freed) { // Field name is not needed while parsing the field value.
                    freeIfAllocated(allocator, token);
                    is_token_freed = true;
                }
                const default_field = if (default) |d| block: {
                    break :block &@field(d, field_name);
                } else block: {
                    break :block @as(
                        ?@TypeOf(&@field(default.?, field_name)),
                        @ptrCast(@alignCast(attr.default_value_ptr)),
                    );
                };
                @field(structure, field_name) = readValue(Field, reader, allocator, default_field) catch |err| {
                    misc.error_context.append("Failed to read field value: {s}", .{field_name});
                    return err;
                };
                field_found = true;
                found_fields[index] = true;
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
    inline for (info.field_names, info.field_attrs, found_fields) |field_name, attr, found| {
        if (!found) {
            const err = error.FieldNotFound;
            misc.error_context.new("Failed to find struct field inside JSON object: {s}", .{field_name});
            const default_field = if (default) |d| block: {
                break :block &@field(d, field_name);
            } else block: {
                break :block @as(
                    ?@TypeOf(&@field(default.?, field_name)),
                    @ptrCast(@alignCast(attr.default_value_ptr)),
                );
            };
            if (default_field) |d| {
                misc.error_context.append("Falling back to default value.", .{});
                if (!builtin.is_test) {
                    misc.error_context.logWarning(err);
                }
                @field(structure, field_name) = d.*;
            } else {
                return err;
            }
        }
    }
    return structure;
}

fn writeUnion(writer: *std.Io.Writer, value_pointer: anytype, whitespace: *const JsonWhitespace) !void {
    const Type = @TypeOf(value_pointer.*);
    const info = @typeInfo(Type).@"union";
    if (info.tag_type == null) {
        @compileError("Union " ++ @typeName(Type) ++ " is not tagged and therefore not serializable.");
    }
    const tag_name = @tagName(value_pointer.*);
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
    switch (value_pointer.*) {
        inline else => |*payload_pointer| {
            writeValue(writer, payload_pointer, whitespace) catch |err| {
                misc.error_context.append("Failed to write union's payload: {s}", .{tag_name});
                return err;
            };
        },
    }
    writer.writeAll(" }") catch |err| {
        misc.error_context.new("Failed to write union end token.", .{});
        return err;
    };
}

fn readUnion(comptime Type: type, reader: *std.json.Reader, allocator: std.mem.Allocator, default: anytype) !Type {
    const info = @typeInfo(Type).@"union";
    const Tag = info.tag_type orelse {
        @compileError("Union " ++ @typeName(Type) ++ " is not tagged and therefore not serializable.");
    };
    const begin_token = reader.next() catch |err| {
        misc.error_context.new("Failed to read union begin token.", .{});
        return err;
    };
    if (begin_token != .object_begin) {
        misc.error_context.new("Expected object begin token but got: {s}", .{@tagName(begin_token)});
        return error.UnexpectedToken;
    }
    const tagged_union: Type = block: {
        const default_tag = if (default) |d| &std.meta.activeTag(d.*) else null;
        const tag = readValue(Tag, reader, allocator, default_tag) catch |err| {
            misc.error_context.append("Failed to read union's tag. ({s})", .{@typeName(Tag)});
            return err;
        };
        inline for (info.field_names, info.field_types) |field_name, Payload| {
            if (@field(Tag, field_name) == tag) {
                const default_payload = switch (default != null and tag == default_tag.?.*) {
                    true => &@field(default.?, field_name),
                    false => null,
                };
                const payload = readValue(Payload, reader, allocator, default_payload) catch |err| {
                    misc.error_context.append("Failed to read union's payload.", .{});
                    return err;
                };
                break :block @unionInit(Type, field_name, payload);
            }
        }
        unreachable;
    };
    const end_token = reader.next() catch |err| {
        misc.error_context.new("Failed to read union end token.", .{});
        return err;
    };
    if (end_token != .object_end) {
        misc.error_context.new("Expected object end token but got: {s}", .{@tagName(end_token)});
        return error.UnexpectedToken;
    }
    return tagged_union;
}

inline fn isBoundedArray(comptime Type: type) bool {
    comptime return hasTag(Type, misc.bounded_array_tag);
}

fn writeBoundedArray(writer: *std.Io.Writer, value_pointer: anytype, whitespace: *const JsonWhitespace) !void {
    const indented_whitespace = whitespace.indented();
    const slice = value_pointer.asSlice();
    const Element = @TypeOf(value_pointer.*).Child;
    if (Element == u8) {
        std.json.Stringify.encodeJsonString(slice, .{}, writer) catch |err| {
            misc.error_context.new("Failed to write bounded string value: {s}", .{slice});
            return err;
        };
        return;
    }
    writer.writeByte('[') catch |err| {
        misc.error_context.new("Failed to write bounded array begin token.", .{});
        return err;
    };
    indented_whitespace.write(writer) catch |err| {
        misc.error_context.append("Failed to write first element whitespace.", .{});
        return err;
    };
    for (slice, 0..) |*element_pointer, index| {
        errdefer misc.error_context.append("Failed to write bounded array element: {}", .{index});
        writeValue(writer, element_pointer, &indented_whitespace) catch |err| {
            misc.error_context.append("Failed to write element value.", .{});
            return err;
        };
        if (index < slice.len - 1) {
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
}

fn readBoundedArray(
    comptime Type: type,
    reader: *std.json.Reader,
    allocator: std.mem.Allocator,
    default: anytype,
) !Type {
    const Element = Type.Child;
    if (Element == u8) {
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
        return .fromSliceTrimmed(string);
    }
    const begin_token = reader.next() catch |err| {
        misc.error_context.new("Failed to read bounded array begin token.", .{});
        return err;
    };
    if (begin_token != .array_begin) {
        misc.error_context.new("Expected array begin token but got: {s}", .{@tagName(begin_token)});
        return error.UnexpectedToken;
    }
    const default_slice = if (default) |d| d.asSlice() else &.{};
    var array: Type = .empty;
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
        if (array.len < Type.max_len) {
            const default_element = if (index < default_slice.len) &default_slice[index] else null;
            array.buffer[array.len] = readValue(Element, reader, allocator, default_element) catch |err| {
                misc.error_context.append("Failed to read element value.", .{});
                return err;
            };
            array.len += 1;
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
    return array;
}

inline fn isEnumArray(comptime Type: type) bool {
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

fn writeEnumArray(writer: *std.Io.Writer, value_pointer: anytype, whitespace: *const JsonWhitespace) !void {
    const indented_whitespace = whitespace.indented();
    const Type = @TypeOf(value_pointer.*);
    const Key = Type.Key;
    const key_info = &@typeInfo(Key).@"enum";
    writer.writeByte('{') catch |err| {
        misc.error_context.new("Failed to write enum array start token.", .{});
        return err;
    };
    indented_whitespace.write(writer) catch |err| {
        misc.error_context.append("Failed to write first entry whitespace.", .{});
        return err;
    };
    inline for (key_info.field_names, key_info.field_values, 0..) |field_name, field_value, index| {
        errdefer misc.error_context.append("Failed to write enum array entry: {s}", .{field_name});
        std.json.Stringify.encodeJsonString(field_name, .{}, writer) catch |err| {
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
        const key: Key = @fromBackingInt(field_value);
        const field_pointer = value_pointer.getPtrConst(key);
        writeValue(writer, field_pointer, &indented_whitespace) catch |err| {
            misc.error_context.append("Failed to write entry value.", .{});
            return err;
        };
        if (index < key_info.field_names.len - 1) {
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
}

fn readEnumArray(comptime Type: type, reader: *std.json.Reader, allocator: std.mem.Allocator, default: anytype) !Type {
    const Key = Type.Key;
    const Value = Type.Value;
    const key_info = &@typeInfo(Key).@"enum";
    const begin_token = reader.next() catch |err| {
        misc.error_context.new("Failed to read enum array begin token.", .{});
        return err;
    };
    if (begin_token != .object_begin) {
        misc.error_context.new("Expected object begin token but got: {s}", .{@tagName(begin_token)});
        return error.UnexpectedToken;
    }
    var enum_array: Type = if (default) |d| d.* else undefined;
    var found_keys: [key_info.field_names.len]bool = @splat(default != null);
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
        inline for (key_info.field_names, key_info.field_values, 0..) |field_name, field_value, index| {
            if (std.mem.eql(u8, field_name, key_name)) {
                errdefer misc.error_context.append("Failed to read enum array entry: {s}", .{field_name});
                if (!is_token_freed) { // Key name is not needed while parsing the value.
                    freeIfAllocated(allocator, token);
                    is_token_freed = true;
                }
                const key: Key = @fromBackingInt(field_value);
                const default_field = if (default) |d| d.getPtrConst(key) else null;
                const value = readValue(Value, reader, allocator, default_field) catch |err| {
                    misc.error_context.append("Failed to read entry value.", .{});
                    return err;
                };
                enum_array.set(key, value);
                key_found = true;
                found_keys[index] = true;
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
    for (key_info.field_names, found_keys) |field_name, found| {
        if (!found) {
            misc.error_context.new("Failed to find enum array entry inside JSON object: {s}", .{field_name});
            return error.EntryNotFound;
        }
    }
    return enum_array;
}

inline fn isVector(comptime Type: type) bool {
    comptime return hasTag(Type, math.vector_tag);
}

fn writeVector(writer: *std.Io.Writer, value_pointer: anytype, whitespace: *const JsonWhitespace) !void {
    const inner_whitespace: JsonWhitespace = switch (whitespace.*) {
        .none => .none,
        .space => .space,
        .new_line => .space,
    };
    writeValue(writer, &value_pointer.array, &inner_whitespace) catch |err| {
        misc.error_context.append("Failed to write vector's array.", .{});
        return err;
    };
}

fn readVector(comptime Type: type, reader: *std.json.Reader, allocator: std.mem.Allocator, default: anytype) !Type {
    const default_array = if (default) |d| &d.array else null;
    const array = readValue(Type.Array, reader, allocator, default_array) catch |err| {
        misc.error_context.append("Failed to read vector's array.", .{});
        return err;
    };
    return .fromArray(array);
}

inline fn isMatrix(comptime Type: type) bool {
    comptime return hasTag(Type, math.vector_tag);
}

fn writeMatrix(writer: *std.Io.Writer, value_pointer: anytype, whitespace: JsonWhitespace) !void {
    const inner_whitespace: JsonWhitespace = switch (whitespace) {
        .none => .none,
        .space => .space,
        .new_line => .space,
    };
    return writeValue(writer, value_pointer.asFlat(), inner_whitespace) catch |err| {
        misc.error_context.append("Failed to write matrix's array.", .{});
        return err;
    };
}

fn readMatrix(comptime Type: type, reader: *std.json.Reader, allocator: std.mem.Allocator, default: anytype) !Type {
    const default_flat = if (default) |d| d.asFlat() else null;
    return readValue(Type.Flat, reader, allocator, default_flat) catch |err| {
        misc.error_context.append("Failed to read matrix's array.", .{});
        return err;
    };
}

fn freeIfAllocated(allocator: std.mem.Allocator, token: std.json.Token) void {
    switch (token) {
        .allocated_number, .allocated_string => |slice| {
            allocator.free(slice);
        },
        else => {},
    }
}

inline fn hasTag(comptime Type: type, comptime tag: type) bool {
    comptime {
        const info = @typeInfo(Type);
        if (info != .@"struct" and info != .@"enum" and info != .@"union") return false;
        if (!@hasDecl(Type, "tag")) return false;
        if (@TypeOf(Type.tag) != type) return false;
        return Type.tag == tag;
    }
}

inline fn isPointerTo(comptime Expected: type, comptime Actual: type) bool {
    comptime {
        return switch (@typeInfo(Actual)) {
            .optional => |*optional| switch (@typeInfo(optional.child)) {
                .pointer => |*pointer| pointer.child == Expected,
                else => false,
            },
            .pointer => |*pointer| pointer.child == Expected,
            else => false,
        };
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
