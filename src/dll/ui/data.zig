const std = @import("std");
const imgui = @import("imgui");
const builtin = @import("builtin");
const sdk = @import("../../sdk/root.zig");

pub fn drawData(label: [:0]const u8, pointer: anytype) void {
    if (comptime builtin.cpu.arch.endian() != .little) {
        @compileError("The drawData function is only implemented for little-endian targets.");
    }
    if (@typeInfo(@TypeOf(pointer)) != .pointer or @typeInfo(@TypeOf(pointer)).pointer.size != .one) {
        @compileError(
            "The drawData function expects a pointer but provided value is of type: " ++ @typeName(@TypeOf(pointer)),
        );
    }
    const info = TypeInfo.fromType(@typeInfo(@TypeOf(pointer)).pointer.child);
    const ctx = Context{
        .label = label,
        .type_name = info.type_name,
        .address = @intFromPtr(pointer),
        .bit_offset = null,
        .bit_size = info.bit_size,
        .parent = null,
    };
    drawValue(&ctx, info, @intFromPtr(pointer), 0);
}

const TypeInfo = struct {
    type_name: [:0]const u8,
    size: usize,
    bit_size: usize,
    kind: Kind,

    pub const Kind = union(enum) {
        void: void,
        null: void,
        undefined: void,
        bool: void,
        number: Number,
        @"enum": Enum,
        error_set: void,
        optional: Optional,
        error_union: ErrorUnion,
        array: Array,
        @"struct": Struct,
        @"union": Union,
        tagged_union: TaggedUnion,
        pointer: Pointer,
        slice: Slice,
        pointer_trail: void,
        converted_value: ConvertedValue,
        custom_pointer: CustomPointer,
        proxy: Proxy,
        alias: *const TypeInfo,
        bounded_array: BoundedArray,
    };
    pub const Number = struct {
        kind: enum { unsigned, signed, float },
        bits: u16,
        is_character: bool,
    };
    pub const Enum = struct {
        names: []const [:0]const u8,
        values: []const u128,
        tag: *const TypeInfo,
    };
    pub const Optional = struct {
        payload: *const TypeInfo,
        getPayload: *const fn (pointer: *const anyopaque) ?*const anyopaque,
    };
    pub const ErrorUnion = struct {
        payload: *const TypeInfo,
        getValue: *const fn (pointer: *const anyopaque) ErrorUnionValue,
    };
    pub const ErrorUnionValue = union(enum) {
        payload: *const anyopaque,
        err: anyerror,
    };
    pub const Array = struct {
        len: usize,
        element: *const TypeInfo,
    };
    pub const Struct = struct {
        is_packed: bool,
        backing_integer: ?*const TypeInfo,
        fields: []const StructField,
    };
    pub const StructField = struct {
        name: [:0]const u8,
        is_hidden: bool,
        bit_offset: usize,
        bit_size: usize,
        info: *const TypeInfo,
    };
    pub const Union = struct {
        fields: []const UnionField,
    };
    pub const UnionField = struct {
        name: [:0]const u8,
        info: *const TypeInfo,
    };
    pub const TaggedUnion = struct {
        variants: []const *const TypeInfo,
        getActive: *const fn (pointer: *const anyopaque) ActiveVariant,
    };
    pub const ActiveVariant = struct {
        tag_name: [:0]const u8,
        index: usize,
        address: usize,
    };
    pub const Pointer = struct {
        /// Null for pointers that point to an unknown number of elements.
        getChild: ?*const fn () *const TypeInfo,
    };
    pub const Slice = struct {
        getElement: *const fn () *const TypeInfo,
        getValue: *const fn (pointer: *const anyopaque) SliceValue,
    };
    pub const SliceValue = struct {
        elements_address: usize,
        len: usize,
        len_address: usize,
    };
    pub const ConvertedValue = struct {
        raw_bit_offset: usize,
        raw: *const TypeInfo,
        drawConverted: *const fn (parent: *const Context, pointer: *const anyopaque) void,
    };
    pub const CustomPointer = struct {
        address_bit_offset: usize,
        getChild: *const fn () *const TypeInfo,
        toConstPointer: *const fn (pointer: *const anyopaque) ?*const anyopaque,
    };
    pub const Proxy = struct {
        trail_offset: usize,
        getChild: *const fn () *const TypeInfo,
        toConstPointer: *const fn (pointer: *const anyopaque) ?*const anyopaque,
    };
    pub const BoundedArray = struct {
        len_offset: usize,
        len: *const TypeInfo,
        buffer_offset: usize,
        buffer_len: usize,
        element: *const TypeInfo,
    };

    pub inline fn fromType(Type: type) *const TypeInfo {
        return comptime &Of(Type).info;
    }

    pub fn fromTypeFunction(Type: type) *const fn () *const TypeInfo {
        return struct {
            fn call() *const TypeInfo {
                return fromType(Type);
            }
        }.call;
    }

    fn Of(Type: type) type {
        return struct {
            const info = TypeInfo{
                .type_name = @typeName(Type),
                .size = @sizeOf(Type),
                .bit_size = bitSizeOf(Type),
                .kind = buildKind(Type),
            };
        };
    }

    fn buildKind(Type: type) TypeInfo.Kind {
        if (Type == sdk.memory.PointerTrail) {
            return .pointer_trail;
        } else if (hasTag(Type, sdk.memory.converted_value_tag)) {
            return .{ .converted_value = .{
                .raw_bit_offset = @bitOffsetOf(Type, "raw"),
                .raw = fromType(@FieldType(Type, "raw")),
                .drawConverted = struct {
                    fn call(parent: *const Context, pointer: *const anyopaque) void {
                        const typed_pointer: *const Type = @ptrCast(@alignCast(pointer));
                        const converted = typed_pointer.convert();
                        drawChild(parent, "converted", fromType(@TypeOf(converted)), @intFromPtr(&converted), null);
                    }
                }.call,
            } };
        } else if (hasTag(Type, sdk.memory.pointer_tag)) {
            return .{ .custom_pointer = .{
                .address_bit_offset = @bitOffsetOf(Type, "address"),
                .getChild = fromTypeFunction(Type.Child),
                .toConstPointer = struct {
                    fn call(pointer: *const anyopaque) ?*const anyopaque {
                        const typed_pointer: *const Type = @ptrCast(@alignCast(pointer));
                        return @ptrCast(typed_pointer.toConstPointer());
                    }
                }.call,
            } };
        } else if (hasTag(Type, sdk.memory.proxy_tag)) {
            return .{ .proxy = .{
                .trail_offset = @offsetOf(Type, "trail"),
                .getChild = fromTypeFunction(Type.Child),
                .toConstPointer = struct {
                    fn call(pointer: *const anyopaque) ?*const anyopaque {
                        const typed_pointer: *const Type = @ptrCast(@alignCast(pointer));
                        return @ptrCast(typed_pointer.toConstPointer());
                    }
                }.call,
            } };
        } else if (hasTag(Type, sdk.math.vector_tag)) {
            const Alias = if (@typeInfo(Type.Array).array.len > 4) Type.Array else Type.Coords;
            return .{ .alias = fromType(Alias) };
        } else if (hasTag(Type, sdk.misc.bounded_array_tag)) {
            return .{ .bounded_array = .{
                .len_offset = @offsetOf(Type, "len"),
                .len = fromType(Type.Length),
                .buffer_offset = @offsetOf(Type, "buffer"),
                .buffer_len = Type.max_len,
                .element = fromType(Type.Child),
            } };
        }
        return switch (@typeInfo(Type)) {
            .void => .void,
            .null => .null,
            .undefined => .undefined,
            .bool => .bool,
            .int => |*info| .{ .number = .{
                .kind = switch (info.signedness) {
                    .unsigned => .unsigned,
                    .signed => .signed,
                },
                .bits = readBitSize(Type),
                .is_character = Type == u8,
            } },
            .float => .{ .number = .{ .kind = .float, .bits = readBitSize(Type), .is_character = false } },
            .@"enum" => |*info| block: {
                const Tag = info.tag_type;
                const UnsignedTag = @Int(.unsigned, @bitSizeOf(Tag));
                var values: [info.field_values.len]u128 = undefined;
                for (info.field_values, &values) |field_value, *value| {
                    value.* = @as(UnsignedTag, @bitCast(@as(Tag, field_value)));
                }
                const final_values = values;
                break :block .{ .@"enum" = .{
                    .names = info.field_names,
                    .values = &final_values,
                    .tag = fromType(info.tag_type),
                } };
            },
            .error_set => .error_set,
            .optional => |*info| .{ .optional = .{
                .payload = fromType(info.child),
                .getPayload = struct {
                    fn call(pointer: *const anyopaque) ?*const anyopaque {
                        const typed_pointer: *const Type = @ptrCast(@alignCast(pointer));
                        if (typed_pointer.*) |*payload| {
                            return @ptrCast(payload);
                        } else {
                            return null;
                        }
                    }
                }.call,
            } },
            .error_union => |*info| .{ .error_union = .{
                .payload = fromType(info.payload),
                .getValue = struct {
                    fn call(pointer: *const anyopaque) TypeInfo.ErrorUnionValue {
                        const typed_pointer: *const Type = @ptrCast(@alignCast(pointer));
                        if (typed_pointer.*) |*payload| {
                            return .{ .payload = @ptrCast(payload) };
                        } else |err| {
                            return .{ .err = err };
                        }
                    }
                }.call,
            } },
            .array => |*info| .{ .array = .{ .len = info.len, .element = fromType(info.child) } },
            .@"struct" => |*info| block: {
                var fields: [info.field_names.len]TypeInfo.StructField = undefined;
                for (info.field_names, info.field_types, &fields) |field_name, Field, *field| {
                    field.* = .{
                        .name = field_name,
                        .is_hidden = std.mem.startsWith(u8, field_name, "_"),
                        .bit_offset = @bitOffsetOf(Type, field_name),
                        .bit_size = switch (info.layout) {
                            .auto, .@"extern" => std.mem.byte_size_in_bits * @sizeOf(Field),
                            .@"packed" => bitSizeOf(Field),
                        },
                        .info = fromType(Field),
                    };
                }
                const final_fields = fields;
                break :block .{ .@"struct" = .{
                    .is_packed = info.layout == .@"packed",
                    .backing_integer = if (info.backing_integer) |BackingInt| fromType(BackingInt) else null,
                    .fields = &final_fields,
                } };
            },
            .@"union" => |*info| if (info.tag_type != null) block: {
                var variants: [info.field_types.len]*const TypeInfo = undefined;
                for (info.field_types, &variants) |Field, *variant| {
                    variant.* = fromType(Field);
                }
                const final_variants = variants;
                break :block .{ .tagged_union = .{
                    .variants = &final_variants,
                    .getActive = struct {
                        fn call(pointer: *const anyopaque) TypeInfo.ActiveVariant {
                            const typed_pointer: *const Type = @ptrCast(@alignCast(pointer));
                            return switch (typed_pointer.*) {
                                inline else => |*payload, tag| .{
                                    .tag_name = @tagName(tag),
                                    .index = comptime std.meta.fieldIndex(Type, @tagName(tag)).?,
                                    .address = @intFromPtr(payload),
                                },
                            };
                        }
                    }.call,
                } };
            } else block: {
                var fields: [info.field_names.len]TypeInfo.UnionField = undefined;
                for (info.field_names, info.field_types, &fields) |field_name, Field, *field| {
                    field.* = .{ .name = field_name, .info = fromType(Field) };
                }
                const final_fields = fields;
                break :block .{ .@"union" = .{ .fields = &final_fields } };
            },
            .pointer => |*info| switch (@typeInfo(info.child)) {
                .@"fn", .@"opaque" => buildKind(usize),
                else => switch (info.size) {
                    .one => .{ .pointer = .{ .getChild = fromTypeFunction(info.child) } },
                    .slice => .{ .slice = .{
                        .getElement = fromTypeFunction(info.child),
                        .getValue = struct {
                            fn call(pointer: *const anyopaque) TypeInfo.SliceValue {
                                const typed_pointer: *const Type = @ptrCast(@alignCast(pointer));
                                return .{
                                    .elements_address = @intFromPtr(typed_pointer.ptr),
                                    .len = typed_pointer.len,
                                    .len_address = @intFromPtr(&typed_pointer.len),
                                };
                            }
                        }.call,
                    } },
                    .many, .c => .{ .pointer = .{ .getChild = null } },
                },
            },
            else => @compileError("Unsupported data type: " ++ @typeName(Type)),
        };
    }

    fn readBitSize(Type: type) u16 {
        if (@bitSizeOf(Type) > 128) {
            @compileError("Numbers larger than 128 bits are not supported: " ++ @typeName(Type));
        }
        return @bitSizeOf(Type);
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
};

fn drawValue(ctx: *const Context, info: *const TypeInfo, address: usize, bit_shift: usize) void {
    switch (info.kind) {
        .void => drawValueText(ctx, "{} (void instance)"),
        .null => drawValueText(ctx, "null"),
        .undefined => drawValueText(ctx, "undefined"),
        .bool => drawValueText(ctx, if (readBits(address, bit_shift, 1) != 0) "true" else "false"),
        .number => |*number| drawNumber(ctx, number, readBits(address, bit_shift, number.bits)),
        .@"enum" => |*@"enum"| drawEnum(ctx, @"enum", address, bit_shift),
        .error_set => {
            const ErrorInt = @Int(.unsigned, @bitSizeOf(anyerror));
            drawError(ctx, @errorFromInt(@as(ErrorInt, @intCast(readBits(address, bit_shift, @bitSizeOf(ErrorInt))))));
        },
        .optional => |*optional| if (optional.getPayload(@ptrFromInt(address))) |payload| {
            drawValue(ctx, optional.payload, @intFromPtr(payload), 0);
        } else {
            drawValueText(ctx, "null");
        },
        .error_union => |*error_union| switch (error_union.getValue(@ptrFromInt(address))) {
            .payload => |payload| drawValue(ctx, error_union.payload, @intFromPtr(payload), 0),
            .err => |err| drawError(ctx, err),
        },
        .array => |*array| {
            if (!beginNodeWithDefaultMenu(ctx)) return;
            defer endNode();
            drawElements(ctx, array.element, address, array.len, address);
        },
        .@"struct" => |*@"struct"| drawStruct(ctx, @"struct", address, bit_shift),
        .@"union" => |*@"union"| {
            if (!beginNodeWithDefaultMenu(ctx)) return;
            defer endNode();
            for (@"union".fields) |*field| {
                drawChildShifted(ctx, field.name, field.info, address, bit_shift, null, field.info.bit_size);
            }
        },
        .tagged_union => |*tagged_union| {
            if (!beginNodeWithDefaultMenu(ctx)) return;
            defer endNode();
            const active = tagged_union.getActive(@ptrFromInt(address));
            drawTreeText("tag", active.tag_name);
            const variant = tagged_union.variants[active.index];
            const bit_offset = (active.address - address) * std.mem.byte_size_in_bits;
            drawChildShifted(ctx, "value", variant, active.address, 0, bit_offset, variant.bit_size);
        },
        .pointer => |*pointer| {
            if (!beginNodeWithDefaultMenu(ctx)) return;
            defer endNode();
            drawChild(ctx, "address", TypeInfo.fromType(usize), address, null);
            const getChild = pointer.getChild orelse return;
            drawChild(ctx, "value", getChild(), readAddress(address), null);
        },
        .slice => |*slice| {
            if (!beginNodeWithDefaultMenu(ctx)) return;
            defer endNode();
            drawChild(ctx, "address", TypeInfo.fromType(usize), address, null);
            const value = slice.getValue(@ptrFromInt(address));
            drawChild(ctx, "len", TypeInfo.fromType(usize), value.len_address, null);
            drawElements(ctx, slice.getElement(), value.elements_address, value.len, value.elements_address);
        },
        .pointer_trail => drawPointerTrail(ctx, @ptrFromInt(address)),
        .converted_value => |*converted_value| {
            if (!beginNodeWithDefaultMenu(ctx)) return;
            defer endNode();
            const raw_address = address + (converted_value.raw_bit_offset / std.mem.byte_size_in_bits);
            drawChild(ctx, "raw", converted_value.raw, raw_address, converted_value.raw_bit_offset);
            converted_value.drawConverted(ctx, @ptrFromInt(address));
        },
        .custom_pointer => |*custom_pointer| {
            const value_pointer = custom_pointer.toConstPointer(@ptrFromInt(address));
            if (value_pointer == null) pushErrorStyle();
            defer if (value_pointer == null) popErrorStyle();
            if (!beginNodeWithDefaultMenu(ctx)) return;
            defer endNode();
            const address_address = address + (custom_pointer.address_bit_offset / std.mem.byte_size_in_bits);
            drawChild(ctx, "address", TypeInfo.fromType(usize), address_address, custom_pointer.address_bit_offset);
            drawPointedValue(ctx, custom_pointer.getChild(), value_pointer);
        },
        .proxy => |*proxy| {
            const value_pointer = proxy.toConstPointer(@ptrFromInt(address));
            if (value_pointer == null) pushErrorStyle();
            defer if (value_pointer == null) popErrorStyle();
            if (!beginNodeWithDefaultMenu(ctx)) return;
            defer endNode();
            drawChild(ctx, "trail", TypeInfo.fromType(sdk.memory.PointerTrail), address + proxy.trail_offset, null);
            drawPointedValue(ctx, proxy.getChild(), value_pointer);
        },
        .alias => |alias| drawValue(ctx, alias, address, bit_shift),
        .bounded_array => |*bounded_array| {
            if (!beginNodeWithDefaultMenu(ctx)) return;
            defer endNode();
            const len_address = address + bounded_array.len_offset;
            const len_bit_offset = std.mem.byte_size_in_bits * bounded_array.len_offset;
            drawChild(ctx, "len", bounded_array.len, len_address, len_bit_offset);
            const len_bits = bounded_array.len.kind.number.bits;
            const len: usize = @intCast(@min(readBits(len_address, 0, len_bits), bounded_array.buffer_len));
            const buffer_address = address + bounded_array.buffer_offset;
            drawElements(ctx, bounded_array.element, buffer_address, len, address);
        },
    }
}

fn drawValueText(ctx: *const Context, text: [:0]const u8) void {
    drawTreeText(ctx.label, text);

    if (!beginMenu()) return;
    defer endMenu();

    drawDefaultMenuItems(ctx);
    drawSeparator();
    drawMenuText("value", text);
}

fn drawNumber(ctx: *const Context, number: *const TypeInfo.Number, raw: u128) void {
    var buffer: [string_buffer_size]u8 = undefined;
    const text = switch (number.kind) {
        .unsigned => if (number.is_character and std.ascii.isPrint(@intCast(raw)))
            std.fmt.bufPrintSentinel(&buffer, "{} (0x{X}) '{c}'", .{ raw, raw, @as(u8, @intCast(raw)) }, 0)
        else
            std.fmt.bufPrintSentinel(&buffer, "{} (0x{X})", .{ raw, raw }, 0),
        .signed => block: {
            const value = signExtend(raw, number.bits);
            break :block std.fmt.bufPrintSentinel(&buffer, "{} (0x{X})", .{ value, value }, 0);
        },
        .float => printFloat(&buffer, raw, number.bits),
    } catch error_string;
    drawTreeText(ctx.label, text);

    if (!beginMenu()) return;
    defer endMenu();

    drawDefaultMenuItems(ctx);
    drawSeparator();
    drawMenuText("value", text);
    drawSeparator();
    drawNumberMenuItems(raw, number.bits);
}

fn drawEnum(ctx: *const Context, @"enum": *const TypeInfo.Enum, address: usize, bit_shift: usize) void {
    const bits = @"enum".tag.kind.number.bits;
    const raw = readBits(address, bit_shift, bits);
    const index = std.mem.indexOfScalar(u128, @"enum".values, raw) orelse {
        pushErrorStyle();
        defer popErrorStyle();
        drawValue(ctx, @"enum".tag, address, bit_shift);
        return;
    };
    const text = @"enum".names[index];
    drawTreeText(ctx.label, text);

    if (!beginMenu()) return;
    defer endMenu();

    drawDefaultMenuItems(ctx);
    drawSeparator();
    drawMenuText("value", text);
    drawSeparator();
    drawNumberMenuItems(raw, bits);
}

fn drawError(ctx: *const Context, err: anyerror) void {
    var buffer: [string_buffer_size]u8 = undefined;
    const text = std.fmt.bufPrintSentinel(&buffer, "error.{s}", .{@errorName(err)}, 0) catch error_string;
    drawValueText(ctx, text);
}

fn drawStruct(ctx: *const Context, @"struct": *const TypeInfo.Struct, address: usize, bit_shift: usize) void {
    imgui.igPushID_Str(ctx.label);
    const storage = imgui.igGetStateStorage();
    const show_hidden_id = imgui.igGetID_Str("show_hidden");
    imgui.igPopID();

    const node_open = beginNode(ctx.label);
    defer if (node_open) endNode();

    var show_hidden = imgui.ImGuiStorage_GetBool(storage, show_hidden_id, false);
    if (beginMenu()) {
        defer endMenu();
        drawDefaultMenuItems(ctx);
        drawSeparator();
        _ = imgui.igCheckbox("Show Hidden Fields", &show_hidden);
    }
    imgui.ImGuiStorage_SetBool(storage, show_hidden_id, show_hidden);

    if (!node_open) return;

    if (@"struct".backing_integer) |backing_integer| {
        drawChildShifted(ctx, "backing integer", backing_integer, address, bit_shift, null, backing_integer.bit_size);
    }
    for (@"struct".fields) |*field| {
        if (field.is_hidden and !show_hidden) {
            continue;
        }
        if (@"struct".is_packed) {
            const field_shift = bit_shift + field.bit_offset;
            drawChildShifted(ctx, field.name, field.info, address, field_shift, field.bit_offset, field.bit_size);
        } else {
            const field_address = address + (field.bit_offset / std.mem.byte_size_in_bits);
            drawChildShifted(ctx, field.name, field.info, field_address, 0, field.bit_offset, field.bit_size);
        }
    }
}

fn drawElements(
    ctx: *const Context,
    element: *const TypeInfo,
    elements_address: usize,
    len: usize,
    offset_base_address: usize,
) void {
    for (0..len) |index| {
        var buffer: [string_buffer_size]u8 = undefined;
        const label = std.fmt.bufPrintSentinel(&buffer, "{}", .{index}, 0) catch error_string;
        const element_address = elements_address + (index * element.size);
        const bit_offset = std.mem.byte_size_in_bits * (element_address - offset_base_address);
        drawChild(ctx, label, element, element_address, bit_offset);
    }
}

fn drawPointerTrail(ctx: *const Context, pointer: *const sdk.memory.PointerTrail) void {
    if (!beginNodeWithDefaultMenu(ctx)) return;
    defer endNode();

    const offsets = pointer.getOffsets();
    drawChild(ctx, "offsets", TypeInfo.fromType(@TypeOf(offsets)), @intFromPtr(&offsets), null);

    const resolved = pointer.resolve();
    drawChild(ctx, "resolved", TypeInfo.fromType(@TypeOf(resolved)), @intFromPtr(&resolved), null);
}

fn drawPointedValue(ctx: *const Context, info: *const TypeInfo, value_pointer: ?*const anyopaque) void {
    const pointer = value_pointer orelse {
        drawTreeText("value", "not readable");
        return;
    };
    drawChild(ctx, "value", info, @intFromPtr(pointer), null);
}

fn drawChild(
    parent: *const Context,
    label: [:0]const u8,
    info: *const TypeInfo,
    address: usize,
    bit_offset: ?usize,
) void {
    drawChildShifted(parent, label, info, address, 0, bit_offset, info.bit_size);
}

fn drawChildShifted(
    parent: *const Context,
    label: [:0]const u8,
    info: *const TypeInfo,
    address: usize,
    bit_shift: usize,
    bit_offset: ?usize,
    bit_size: usize,
) void {
    const ctx = Context{
        .label = label,
        .type_name = info.type_name,
        .address = address,
        .bit_offset = bit_offset,
        .bit_size = bit_size,
        .parent = parent,
    };
    drawValue(&ctx, info, address, bit_shift);
}

const error_string = "display error";
const error_color = imgui.ImVec4{ .x = 1, .y = 0.5, .z = 0.5, .w = 1 };
const string_buffer_size = 128;

const Context = struct {
    label: [:0]const u8,
    type_name: [:0]const u8,
    address: usize,
    bit_offset: ?usize,
    bit_size: usize,
    parent: ?*const Context,

    const Self = @This();

    pub fn getPath(self: *const Self, buffer: []u8) ![:0]u8 {
        var writer = std.Io.Writer.fixed(buffer);
        try self.writePath(&writer);
        try writer.writeByte(0);
        return buffer[0..(writer.end - 1) :0];
    }

    fn writePath(self: *const Self, writer: *std.Io.Writer) !void {
        if (self.parent) |parent| {
            try parent.writePath(writer);
            try writer.writeByte('.');
        }
        try writer.writeAll(self.label);
    }
};

/// Reads `bits` bits starting `bit_shift` bits after `address`, in little endian order.
fn readBits(address: usize, bit_shift: usize, bits: usize) u128 {
    if (bits == 0) {
        return 0;
    }
    const start: [*]const u8 = @ptrFromInt(address + (bit_shift / std.mem.byte_size_in_bits));
    const shift: u7 = @intCast(bit_shift % std.mem.byte_size_in_bits);
    const byte_count = (shift + bits + std.mem.byte_size_in_bits - 1) / std.mem.byte_size_in_bits;
    var bytes: [@sizeOf(u136)]u8 = @splat(0);
    @memcpy(bytes[0..byte_count], start[0..byte_count]);
    const value = std.mem.readInt(u136, bytes[0..@divExact(@bitSizeOf(u136), std.mem.byte_size_in_bits)], .little);
    return @truncate((value >> shift) & mask(bits));
}

fn readAddress(address: usize) usize {
    return @intCast(readBits(address, 0, @bitSizeOf(usize)));
}

fn mask(bits: usize) u136 {
    return (@as(u136, 1) << @intCast(bits)) - 1;
}

fn signExtend(raw: u128, bits: u16) i128 {
    if (bits == 0) {
        return 0;
    }
    const shift: u7 = @intCast(128 - bits);
    return @as(i128, @bitCast(raw << shift)) >> shift;
}

fn printFloat(buffer: []u8, raw: u128, bits: u16) ![:0]u8 {
    return switch (bits) {
        16 => std.fmt.bufPrintSentinel(buffer, "{}", .{@as(f16, @bitCast(@as(u16, @truncate(raw))))}, 0),
        32 => std.fmt.bufPrintSentinel(buffer, "{}", .{@as(f32, @bitCast(@as(u32, @truncate(raw))))}, 0),
        64 => std.fmt.bufPrintSentinel(buffer, "{}", .{@as(f64, @bitCast(@as(u64, @truncate(raw))))}, 0),
        80 => std.fmt.bufPrintSentinel(buffer, "{}", .{@as(f80, @bitCast(@as(u80, @truncate(raw))))}, 0),
        128 => std.fmt.bufPrintSentinel(buffer, "{}", .{@as(f128, @bitCast(raw))}, 0),
        else => error.UnsupportedFloatSize,
    };
}

fn drawTreeText(label: [:0]const u8, text: [:0]const u8) void {
    imgui.igIndent(0.0);
    defer imgui.igUnindent(0.0);
    drawText(label, text);
}

fn beginNode(label: [:0]const u8) bool {
    return imgui.igTreeNode_Str(label);
}

fn beginNodeWithDefaultMenu(ctx: *const Context) bool {
    const node_open = beginNode(ctx.label);
    useDefaultMenu(ctx);
    return node_open;
}

fn endNode() void {
    imgui.igTreePop();
}

fn pushErrorStyle() void {
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Text, error_color);
}

fn popErrorStyle() void {
    imgui.igPopStyleColor(1);
}

fn beginMenu() bool {
    return imgui.igBeginPopupContextItem(null, imgui.ImGuiPopupFlags_MouseButtonRight);
}

fn endMenu() void {
    imgui.igEndPopup();
}

fn useDefaultMenu(ctx: *const Context) void {
    if (!beginMenu()) return;
    defer endMenu();
    drawDefaultMenuItems(ctx);
}

fn drawDefaultMenuItems(ctx: *const Context) void {
    var buffer: [string_buffer_size]u8 = undefined;
    drawMenuText("label", ctx.label);
    drawMenuText("path", ctx.getPath(&buffer) catch error_string);
    drawMenuText("type", ctx.type_name);
    drawSeparator();
    drawMenuText(
        "address",
        std.fmt.bufPrintSentinel(&buffer, "{} (0x{X})", .{ ctx.address, ctx.address }, 0) catch error_string,
    );
    if (ctx.bit_offset) |offset| {
        drawMenuText("offset", bitsToText(&buffer, offset) catch error_string);
    }
    drawMenuText("size", bitsToText(&buffer, ctx.bit_size) catch error_string);
}

fn drawNumberMenuItems(raw: u128, bits: u16) void {
    var label_buffer: [string_buffer_size]u8 = undefined;
    var buffer: [string_buffer_size]u8 = undefined;

    const u_label = std.fmt.bufPrintSentinel(&label_buffer, "u{}", .{bits}, 0) catch error_string;
    const u_text = std.fmt.bufPrintSentinel(&buffer, "{} (0x{X})", .{ raw, raw }, 0) catch error_string;
    drawMenuText(u_label, u_text);

    const i_value = signExtend(raw, bits);
    const i_label = std.fmt.bufPrintSentinel(&label_buffer, "i{}", .{bits}, 0) catch error_string;
    const i_text = std.fmt.bufPrintSentinel(&buffer, "{} (0x{X})", .{ i_value, i_value }, 0) catch error_string;
    drawMenuText(i_label, i_text);

    if (printFloat(&buffer, raw, bits)) |f_text| {
        const f_label = std.fmt.bufPrintSentinel(&label_buffer, "f{}", .{bits}, 0) catch error_string;
        drawMenuText(f_label, f_text);
    } else |_| {}

    if (bits == 8) {
        drawSeparator();
        const character: u8 = @intCast(raw);
        if (std.ascii.isPrint(character)) {
            const char_text = std.fmt.bufPrintSentinel(&buffer, "{c}", .{character}, 0) catch error_string;
            drawMenuText("character", char_text);
        } else {
            drawMenuText("character", "not printable");
        }
    }

    const binary_text = std.fmt.bufPrintSentinel(&buffer, "{[0]b:0>[1]}", .{ raw, @as(usize, bits) }, 0) catch error_string;
    drawMenuText("binary", binary_text);
}

fn bitsToText(buffer: []u8, bits_value: usize) ![:0]u8 {
    const bytes = bits_value / std.mem.byte_size_in_bits;
    const bits = bits_value % std.mem.byte_size_in_bits;
    if (bits == 0) {
        return std.fmt.bufPrintSentinel(buffer, "{} (0x{X}) bytes", .{ bytes, bytes }, 0);
    } else if (bytes == 0) {
        return std.fmt.bufPrintSentinel(buffer, "{} (0x{X}) bits", .{ bits, bits }, 0);
    } else {
        return std.fmt.bufPrintSentinel(buffer, "{} (0x{X}) bytes, {} (0x{X}) bits", .{ bytes, bytes, bits, bits }, 0);
    }
}

fn drawMenuText(label: [:0]const u8, text: [:0]const u8) void {
    drawText(label, text);
}

fn drawText(label: [:0]const u8, text: [:0]const u8) void {
    imgui.igText("%s: %s", label.ptr, text.ptr);

    var rect: imgui.ImRect = undefined;
    imgui.igGetItemRectMin(&rect.Min);
    imgui.igGetItemRectMax(&rect.Max);
    _ = imgui.igItemAdd(rect, imgui.igGetID_Str(label), null, imgui.ImGuiItemFlags_NoNav);

    if (imgui.igIsItemClicked(imgui.ImGuiMouseButton_Left)) {
        imgui.igSetClipboardText(text);
        sdk.ui.toasts.send(.info, null, "Copied to clipboard: {s}", .{text});
    }

    if (builtin.is_test) {
        var buffer: [string_buffer_size]u8 = undefined;
        const full_text = std.fmt.bufPrintSentinel(&buffer, "{s}: {s}", .{ label, text }, 0) catch error_string;
        imgui.teItemAdd(imgui.igGetCurrentContext(), imgui.igGetID_Str(label), &rect, null);
        imgui.teItemAdd(imgui.igGetCurrentContext(), imgui.igGetID_Str(full_text), &rect, null);
    }
}

fn drawSeparator() void {
    imgui.igSeparator();
}

fn bitSizeOf(Type: type) comptime_int {
    return switch (@typeInfo(Type)) {
        .bool => 1,
        .int, .float, .enum_literal => @bitSizeOf(Type),
        .@"struct" => |*s| switch (s.layout) {
            .@"packed" => @bitSizeOf(Type),
            .auto, .@"extern" => std.mem.byte_size_in_bits * @sizeOf(Type),
        },
        .@"union" => |*u| switch (u.layout) {
            .@"packed" => @bitSizeOf(Type),
            .auto, .@"extern" => std.mem.byte_size_in_bits * @sizeOf(Type),
        },
        else => std.mem.byte_size_in_bits * @sizeOf(Type),
    };
}

const testing = std.testing;

test "should draw void correctly" {
    const Test = struct {
        var value: void = {};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const address = @intFromPtr(&value);

            ctx.setRef("Window");
            try ctx.expectItemExists("test: {} (void instance)");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: void");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExists("size: 0 (0x0) bytes");
            try ctx.expectItemExists("value: {} (void instance)");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw null correctly" {
    const Test = struct {
        var value: ?void = null;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const address = @intFromPtr(&value);
            const size = @sizeOf(@TypeOf(value));

            ctx.setRef("Window");
            try ctx.expectItemExists("test: null");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: ?void");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ size, size });
            try ctx.expectItemExists("value: null");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw bool correctly" {
    const Test = struct {
        var value: bool = false;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const address = @intFromPtr(&value);

            ctx.setRef("Window");
            try ctx.expectItemExists("test: false");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: bool");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExists("size: 1 (0x1) bits");
            try ctx.expectItemExists("value: false");

            value = true;
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test: true");

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("value: true");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw int correctly" {
    const Test = struct {
        var value: u8 = 0;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const address = @intFromPtr(&value);

            value = 97;
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test: 97 (0x61) 'a'");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: u8");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExists("size: 1 (0x1) bytes");
            try ctx.expectItemExists("value: 97 (0x61) 'a'");
            try ctx.expectItemExists("u8: 97 (0x61)");
            try ctx.expectItemExists("i8: 97 (0x61)");
            try ctx.expectItemExists("character: a");
            try ctx.expectItemExists("binary: 01100001");

            value = 255;
            ctx.yield(1);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("u8: 255 (0xFF)");
            try ctx.expectItemExists("i8: -1 (0x-1)");
            try ctx.expectItemExists("character: not printable");
            try ctx.expectItemExists("binary: 11111111");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw float correctly" {
    const Test = struct {
        var value: f32 = -1.0;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const address = @intFromPtr(&value);

            ctx.setRef("Window");
            try ctx.expectItemExists("test: -1");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: f32");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExists("size: 4 (0x4) bytes");
            try ctx.expectItemExists("value: -1");
            try ctx.expectItemExists("u32: 3212836864 (0xBF800000)");
            try ctx.expectItemExists("i32: -1082130432 (0x-40800000)");
            try ctx.expectItemExists("f32: -1");
            try ctx.expectItemExists("binary: 10111111100000000000000000000000");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw enum correctly" {
    const Enum = enum(u8) { test_value = 255, _ };
    const Test = struct {
        var value: Enum = @fromBackingInt(0);

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const address = @intFromPtr(&value);

            value = .test_value;
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test: test_value");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: " ++ @typeName(Enum));
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExists("size: 1 (0x1) bytes");
            try ctx.expectItemExists("value: test_value");
            try ctx.expectItemExists("u8: 255 (0xFF)");
            try ctx.expectItemExists("i8: -1 (0x-1)");
            try ctx.expectItemExists("character: not printable");
            try ctx.expectItemExists("binary: 11111111");

            value = @fromBackingInt(97);
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test: 97 (0x61) 'a'");

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("value: 97 (0x61) 'a'");
            try ctx.expectItemExists("u8: 97 (0x61)");
            try ctx.expectItemExists("i8: 97 (0x61)");
            try ctx.expectItemExists("character: a");
            try ctx.expectItemExists("binary: 01100001");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw signed enum correctly" {
    const Enum = enum(i8) { minus_one = -1, _ };
    const Test = struct {
        var value: Enum = @fromBackingInt(0);

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const address = @intFromPtr(&value);

            value = .minus_one;
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test: minus_one");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: " ++ @typeName(Enum));
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExists("size: 1 (0x1) bytes");
            try ctx.expectItemExists("value: minus_one");
            try ctx.expectItemExists("u8: 255 (0xFF)");
            try ctx.expectItemExists("i8: -1 (0x-1)");
            try ctx.expectItemExists("binary: 11111111");

            value = @fromBackingInt(-2);
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test: -2 (0x-2)");

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("value: -2 (0x-2)");
            try ctx.expectItemExists("u8: 254 (0xFE)");
            try ctx.expectItemExists("i8: -2 (0x-2)");
            try ctx.expectItemExists("binary: 11111110");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw error correctly" {
    const Test = struct {
        var value: anyerror = error.TestError;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const address = @intFromPtr(&value);
            const size = @sizeOf(@TypeOf(value));

            ctx.setRef("Window");
            try ctx.expectItemExists("test: error.TestError");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: anyerror");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ size, size });
            try ctx.expectItemExists("value: error.TestError");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw optional correctly" {
    const Test = struct {
        var value: ?bool = null;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const address = @intFromPtr(&value);
            const size = @sizeOf(@TypeOf(value));

            value = null;
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test: null");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: ?bool");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ size, size });
            try ctx.expectItemExists("value: null");

            value = true;
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test: true");

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("value: true");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw error union correctly" {
    const Test = struct {
        var value: anyerror!bool = false;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const address = @intFromPtr(&value);
            const size = @sizeOf(@TypeOf(value));

            value = false;
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test: false");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: anyerror!bool");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ size, size });
            try ctx.expectItemExists("value: false");

            value = error.TestError;
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test: error.TestError");

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("value: error.TestError");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw function correctly" {
    const Test = struct {
        var value: *const fn (i32, i32) i32 = add;

        fn add(a: i32, b: i32) i32 {
            return a + b;
        }

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const address = @intFromPtr(&value);
            const int_value = @intFromPtr(value);
            const size = @sizeOf(@TypeOf(value));

            ctx.setRef("Window");
            try ctx.expectItemExistsFmt("test: {} (0x{X})", .{ int_value, int_value });
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: *const fn (i32, i32) i32");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ size, size });
            try ctx.expectItemExistsFmt("value: {} (0x{X})", .{ int_value, int_value });
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw opaque correctly" {
    const Test = struct {
        var value: *const opaque {} = @ptrFromInt(1234);

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const address = @intFromPtr(&value);
            const size = @sizeOf(@TypeOf(value));

            ctx.setRef("Window");
            try ctx.expectItemExists("test: 1234 (0x4D2)");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: " ++ @typeName(@TypeOf(value)));
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ size, size });
            try ctx.expectItemExists("value: 1234 (0x4D2)");
            try ctx.expectItemExists("u64: 1234 (0x4D2)");
            try ctx.expectItemExists("i64: 1234 (0x4D2)");
            try ctx.expectItemExists("binary: 0000000000000000000000000000000000000000000000000000010011010010");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw array correctly" {
    const Test = struct {
        var value: [3]u32 = .{ 1, 2, 3 };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const array_address = @intFromPtr(&value);
            const element_address = @intFromPtr(&value[2]);

            ctx.setRef("Window");
            try ctx.expectItemExists("test");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: [3]u32");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ array_address, array_address });
            try ctx.expectItemExists("size: 12 (0xC) bytes");
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemExists("test/0: 1 (0x1)");
            try ctx.expectItemExists("test/1: 2 (0x2)");
            try ctx.expectItemExists("test/2: 3 (0x3)");
            ctx.itemClick("test/2", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: 2");
            try ctx.expectItemExists("path: test.2");
            try ctx.expectItemExists("type: u32");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ element_address, element_address });
            try ctx.expectItemExists("offset: 8 (0x8) bytes");
            try ctx.expectItemExists("size: 4 (0x4) bytes");
            try ctx.expectItemExists("value: 3 (0x3)");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw struct correctly" {
    const Struct = extern struct {
        _field_0: u32 = 1,
        field_1: u32 = 2,
        field_2: u32 = 3,
        _field_3: u32 = 4,
    };
    const Test = struct {
        var value: Struct = .{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const struct_address = @intFromPtr(&value);
            const field_address = @intFromPtr(&value.field_2);

            ctx.setRef("Window");
            try ctx.expectItemExists("test");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: " ++ @typeName(Struct));
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ struct_address, struct_address });
            try ctx.expectItemExists("size: 16 (0x10) bytes");
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemNotExists("test/_field_0");
            try ctx.expectItemExists("test/field_1: 2 (0x2)");
            try ctx.expectItemExists("test/field_2: 3 (0x3)");
            try ctx.expectItemNotExists("test/_field_3");
            ctx.itemClick("test/field_2", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: field_2");
            try ctx.expectItemExists("path: test.field_2");
            try ctx.expectItemExists("type: u32");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ field_address, field_address });
            try ctx.expectItemExists("offset: 8 (0x8) bytes");
            try ctx.expectItemExists("size: 4 (0x4) bytes");
            try ctx.expectItemExists("value: 3 (0x3)");
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("Show Hidden Fields", imgui.ImGuiMouseButton_Left, 0);
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            try ctx.expectItemExists("test/_field_0: 1 (0x1)");
            try ctx.expectItemExists("test/field_1: 2 (0x2)");
            try ctx.expectItemExists("test/field_2: 3 (0x3)");
            try ctx.expectItemExists("test/_field_3: 4 (0x4)");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw packed struct correctly" {
    const Struct = packed struct(u8) {
        _field_0: u2 = 1,
        field_1: bool = true,
        field_2: u3 = 2,
        _field_3: u2 = 3,
    };
    const Test = struct {
        var value: Struct = .{};

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const struct_address = @intFromPtr(&value);
            const field_address = @intFromPtr(&value.field_2);

            ctx.setRef("Window");
            try ctx.expectItemExists("test");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: " ++ @typeName(Struct));
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ struct_address, struct_address });
            try ctx.expectItemExists("size: 1 (0x1) bytes");
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemExists("test/backing integer: 213 (0xD5)");
            try ctx.expectItemNotExists("test/_field_0");
            try ctx.expectItemExists("test/field_1: true");
            try ctx.expectItemExists("test/field_2: 2 (0x2)");
            try ctx.expectItemNotExists("test/_field_3");
            ctx.itemClick("test/field_1", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: field_1");
            try ctx.expectItemExists("path: test.field_1");
            try ctx.expectItemExists("type: bool");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ field_address, field_address });
            try ctx.expectItemExists("offset: 2 (0x2) bits");
            try ctx.expectItemExists("size: 1 (0x1) bits");
            try ctx.expectItemExists("value: true");
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            ctx.setRef("//$FOCUSED");
            ctx.itemClick("Show Hidden Fields", imgui.ImGuiMouseButton_Left, 0);
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            try ctx.expectItemExists("test/backing integer: 213 (0xD5)");
            try ctx.expectItemExists("test/_field_0: 1 (0x1)");
            try ctx.expectItemExists("test/field_1: true");
            try ctx.expectItemExists("test/field_2: 2 (0x2)");
            try ctx.expectItemExists("test/_field_3: 3 (0x3)");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw union correctly" {
    const Int8 = extern union {
        unsigned: u8,
        signed: i8,
    };
    const Test = struct {
        var value: Int8 = .{ .unsigned = 255 };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const address = @intFromPtr(&value);

            ctx.setRef("Window");
            try ctx.expectItemExists("test");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: " ++ @typeName(Int8));
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExists("size: 1 (0x1) bytes");
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemExists("test/unsigned: 255 (0xFF)");
            try ctx.expectItemExists("test/signed: -1 (0x-1)");
            ctx.itemClick("test/signed", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: signed");
            try ctx.expectItemExists("path: test.signed");
            try ctx.expectItemExists("type: i8");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExists("size: 1 (0x1) bytes");
            try ctx.expectItemExists("value: -1 (0x-1)");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw tagged union correctly" {
    const Int8 = union(enum) {
        unsigned: u8,
        signed: i8,
    };
    const Test = struct {
        var value: Int8 = .{ .unsigned = 0 };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const union_address = @intFromPtr(&value);
            const value_address = @intFromPtr(&value.unsigned);
            const value_offset = value_address - union_address;

            value = .{ .unsigned = 255 };
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: " ++ @typeName(Int8));
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ union_address, union_address });
            try ctx.expectItemExists("size: 2 (0x2) bytes");
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemExists("test/tag: unsigned");
            try ctx.expectItemExists("test/value: 255 (0xFF)");
            ctx.itemClick("test/value", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: value");
            try ctx.expectItemExists("path: test.value");
            try ctx.expectItemExists("type: u8");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ value_address, value_address });
            try ctx.expectItemExistsFmt("offset: {} (0x{X}) bytes", .{ value_offset, value_offset });
            try ctx.expectItemExists("size: 1 (0x1) bytes");
            try ctx.expectItemExists("value: 255 (0xFF)");
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            value = .{ .signed = -1 };
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test/tag: signed");
            try ctx.expectItemExists("test/value: -1 (0x-1)");
            ctx.itemClick("test/value", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: value");
            try ctx.expectItemExists("path: test.value");
            try ctx.expectItemExists("type: i8");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ value_address, value_address });
            try ctx.expectItemExistsFmt("offset: {} (0x{X}) bytes", .{ value_offset, value_offset });
            try ctx.expectItemExists("size: 1 (0x1) bytes");
            try ctx.expectItemExists("value: -1 (0x-1)");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw tagged union without reading the tag from memory" {
    const Number = union(enum) {
        unsigned: u32,
        float: f32,
    };
    const Test = struct {
        var value: Number = .{ .unsigned = 0 };

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const value_address = @intFromPtr(&value.unsigned);
            const value_offset = value_address - @intFromPtr(&value);

            value = .{ .unsigned = 1 };
            ctx.yield(1);

            ctx.setRef("Window");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemExists("test/tag: unsigned");
            try ctx.expectItemExists("test/value: 1 (0x1)");
            ctx.itemClick("test/value", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ value_address, value_address });
            try ctx.expectItemExistsFmt("offset: {} (0x{X}) bytes", .{ value_offset, value_offset });
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            value = .{ .float = 0 };
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test/tag: float");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw pointer correctly" {
    const Test = struct {
        var value: *const i32 = &123;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const pointer_address = @intFromPtr(&value);
            const value_address = @intFromPtr(value);
            const pointer_size = @sizeOf(usize);

            ctx.setRef("Window");
            try ctx.expectItemExists("test");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: *const i32");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ pointer_address, pointer_address });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ pointer_size, pointer_size });
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemExistsFmt("test/address: {} (0x{X})", .{ value_address, value_address });
            try ctx.expectItemExists("test/value: 123 (0x7B)");
            ctx.itemClick("test/address", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: address");
            try ctx.expectItemExists("path: test.address");
            try ctx.expectItemExists("type: usize");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ pointer_address, pointer_address });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ pointer_size, pointer_size });
            try ctx.expectItemExistsFmt("value: {} (0x{X})", .{ value_address, value_address });
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test/value", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: value");
            try ctx.expectItemExists("path: test.value");
            try ctx.expectItemExists("type: i32");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ value_address, value_address });
            try ctx.expectItemExists("size: 4 (0x4) bytes");
            try ctx.expectItemExists("value: 123 (0x7B)");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw slice correctly" {
    const Test = struct {
        var array: [3]u32 = .{ 1, 2, 3 };
        var slice: []u32 = &array;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &slice);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const slice_address = @intFromPtr(&slice);
            const len_address = @intFromPtr(&slice.len);
            const array_address = @intFromPtr(&array);
            const element_address = @intFromPtr(&array[2]);
            const pointer_size = @sizeOf(usize);
            const slice_size = @sizeOf([]u32);

            ctx.setRef("Window");
            try ctx.expectItemExists("test");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: []u32");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ slice_address, slice_address });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ slice_size, slice_size });
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemExistsFmt("test/address: {} (0x{X})", .{ array_address, array_address });
            try ctx.expectItemExists("test/len: 3 (0x3)");
            try ctx.expectItemExists("test/0: 1 (0x1)");
            try ctx.expectItemExists("test/1: 2 (0x2)");
            try ctx.expectItemExists("test/2: 3 (0x3)");
            ctx.itemClick("test/address", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: address");
            try ctx.expectItemExists("path: test.address");
            try ctx.expectItemExists("type: usize");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ slice_address, slice_address });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ pointer_size, pointer_size });
            try ctx.expectItemExistsFmt("value: {} (0x{X})", .{ array_address, array_address });
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test/len", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: len");
            try ctx.expectItemExists("path: test.len");
            try ctx.expectItemExists("type: usize");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ len_address, len_address });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ pointer_size, pointer_size });
            try ctx.expectItemExists("value: 3 (0x3)");

            ctx.setRef("Window");
            ctx.itemClick("test/2", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: 2");
            try ctx.expectItemExists("path: test.2");
            try ctx.expectItemExists("type: u32");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ element_address, element_address });
            try ctx.expectItemExists("offset: 8 (0x8) bytes");
            try ctx.expectItemExists("size: 4 (0x4) bytes");
            try ctx.expectItemExists("value: 3 (0x3)");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw pointer trail correctly" {
    const Test = struct {
        var trail: sdk.memory.PointerTrail = .fromArray(.{});

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &trail);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const address = @intFromPtr(&trail);
            const size = @sizeOf(@TypeOf(trail));

            trail = .fromArray(.{123});
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: " ++ @typeName(@TypeOf(trail)));
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ size, size });
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemExists("test/offsets");
            try ctx.expectItemExists("test/resolved: 123 (0x7B)");
            ctx.itemClick("test/offsets", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: offsets");
            try ctx.expectItemExists("path: test.offsets");
            try ctx.expectItemExists("type: []const ?usize");
            try ctx.expectItemExists("address");
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ @sizeOf([]const ?usize), @sizeOf([]const ?usize) });
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test/resolved", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: resolved");
            try ctx.expectItemExists("path: test.resolved");
            try ctx.expectItemExists("type: ?usize");
            try ctx.expectItemExists("address");
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ @sizeOf(?usize), @sizeOf(?usize) });
            try ctx.expectItemExists("value: 123 (0x7B)");
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test/offsets", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemExists("test/offsets/address");
            try ctx.expectItemExists("test/offsets/len: 1 (0x1)");
            try ctx.expectItemExists("test/offsets/0: 123 (0x7B)");

            trail = .fromArray(.{ 123, null });
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test/offsets/len: 1 (0x1)");
            try ctx.expectItemExists("test/offsets/0: 123 (0x7B)");
            try ctx.expectItemExists("test/offsets/1: null");
            try ctx.expectItemExists("test/resolved: null");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw converted value correctly" {
    const Test = struct {
        var converted: sdk.memory.ConvertedValue(i32, i64, rawToValue, null) = .{ .raw = 123 };

        fn rawToValue(raw: i32) i64 {
            return raw * 2;
        }

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &converted);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const address = @intFromPtr(&converted);

            ctx.setRef("Window");
            try ctx.expectItemExists("test");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExists("size: 4 (0x4) bytes");
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemExists("test/raw: 123 (0x7B)");
            try ctx.expectItemExists("test/converted: 246 (0xF6)");
            ctx.itemClick("test/raw", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: raw");
            try ctx.expectItemExists("path: test.raw");
            try ctx.expectItemExists("type: i32");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExists("size: 4 (0x4) bytes");
            try ctx.expectItemExists("value: 123 (0x7B)");
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test/converted", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: converted");
            try ctx.expectItemExists("path: test.converted");
            try ctx.expectItemExists("type: i64");
            try ctx.expectItemExists("address");
            try ctx.expectItemExists("size: 8 (0x8) bytes");
            try ctx.expectItemExists("value: 246 (0xF6)");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw custom pointer correctly" {
    const Test = struct {
        var pointer: sdk.memory.Pointer(i32) = .{ .address = 0 };
        var value: i32 = 123;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &pointer);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const pointer_address = @intFromPtr(&pointer);
            const value_address = @intFromPtr(&value);
            const pointer_size = @sizeOf(usize);

            pointer.address = value_address;
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: " ++ @typeName(sdk.memory.Pointer(i32)));
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ pointer_address, pointer_address });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ pointer_size, pointer_size });
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemExistsFmt("test/address: {} (0x{X})", .{ value_address, value_address });
            try ctx.expectItemExists("test/value: 123 (0x7B)");
            ctx.itemClick("test/address", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: address");
            try ctx.expectItemExists("path: test.address");
            try ctx.expectItemExists("type: usize");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ pointer_address, pointer_address });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ pointer_size, pointer_size });
            try ctx.expectItemExistsFmt("value: {} (0x{X})", .{ value_address, value_address });
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test/value", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: value");
            try ctx.expectItemExists("path: test.value");
            try ctx.expectItemExists("type: i32");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ value_address, value_address });
            try ctx.expectItemExists("size: 4 (0x4) bytes");
            try ctx.expectItemExists("value: 123 (0x7B)");
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            pointer.address = 0;
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test/address: 0 (0x0)");
            try ctx.expectItemExists("test/value: not readable");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw proxy correctly" {
    const Test = struct {
        var proxy: sdk.memory.Proxy(i32) = .fromArray(.{});
        var value: i32 = 123;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &proxy);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const proxy_address = @intFromPtr(&proxy);
            const value_address = @intFromPtr(&value);
            const proxy_size = @sizeOf(@TypeOf(proxy));

            proxy = .fromArray(.{value_address});
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: " ++ @typeName(@TypeOf(proxy)));
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ proxy_address, proxy_address });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ proxy_size, proxy_size });
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemExists("test/trail");
            try ctx.expectItemExists("test/value: 123 (0x7B)");
            ctx.itemClick("test/value", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: value");
            try ctx.expectItemExists("path: test.value");
            try ctx.expectItemExists("type: i32");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ value_address, value_address });
            try ctx.expectItemExists("size: 4 (0x4) bytes");
            try ctx.expectItemExists("value: 123 (0x7B)");
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test/trail", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("test/trail/offsets", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemExists("test/trail/offsets/address");
            try ctx.expectItemExists("test/trail/offsets/len: 1 (0x1)");
            try ctx.expectItemExistsFmt("test/trail/offsets/0: {} (0x{X})", .{ value_address, value_address });
            try ctx.expectItemExistsFmt("test/trail/resolved: {} (0x{X})", .{ value_address, value_address });

            proxy = .fromArray(.{null});
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test/trail/offsets/address");
            try ctx.expectItemExists("test/trail/offsets/len: 1 (0x1)");
            try ctx.expectItemExists("test/trail/offsets/0: null");
            try ctx.expectItemExists("test/trail/resolved: null");
            try ctx.expectItemExists("test/value: not readable");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw vector correctly" {
    const Test = struct {
        var value_1: sdk.math.Vector(4, f32) = .fromArray(.{ 1, 2, 3, 4 });
        var value_2: sdk.math.Vector(5, f32) = .fromArray(.{ 5, 6, 7, 8, 9 });

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test_1", &value_1);
            drawData("test_2", &value_2);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const address_1 = @intFromPtr(&value_1);
            const size_1 = @sizeOf(@TypeOf(value_1));

            ctx.setRef("Window");
            try ctx.expectItemExists("test_1");
            try ctx.expectItemExists("test_2");
            ctx.itemClick("test_1", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test_1");
            try ctx.expectItemExists("path: test_1");
            try ctx.expectItemExists("type");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address_1, address_1 });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ size_1, size_1 });
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test_1", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("test_2", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemExists("test_1/x: 1");
            try ctx.expectItemExists("test_1/y: 2");
            try ctx.expectItemExists("test_1/z: 3");
            try ctx.expectItemExists("test_1/w: 4");
            try ctx.expectItemExists("test_2/0: 5");
            try ctx.expectItemExists("test_2/1: 6");
            try ctx.expectItemExists("test_2/2: 7");
            try ctx.expectItemExists("test_2/3: 8");
            try ctx.expectItemExists("test_2/4: 9");
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw bounded array correctly" {
    const Test = struct {
        var value: sdk.misc.BoundedArray(4, f32, 0, false) = .fromArray(.{ 123, 456 });

        fn guiFunction(_: sdk.ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const address = @intFromPtr(&value);
            const size = @sizeOf(@TypeOf(value));
            const len_address = @intFromPtr(&value.len);
            const len_offset = @offsetOf(@TypeOf(value), "len");
            const len_bit_size = bitSizeOf(@TypeOf(value.len));
            const element_1_address = @intFromPtr(&value.buffer[1]);
            const element_1_offset = element_1_address - address;
            const element_1_size = @sizeOf(@TypeOf(value.buffer[1]));

            ctx.setRef("Window");
            try ctx.expectItemExists("test");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ size, size });
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemExists("test/len: 2 (0x2)");
            try ctx.expectItemExists("test/0: 123");
            try ctx.expectItemExists("test/1: 456");
            ctx.itemClick("test/len", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: len");
            try ctx.expectItemExists("path: test.len");
            try ctx.expectItemExistsFmt("type: {s}", .{@typeName(@TypeOf(value.len))});
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ len_address, len_address });
            try ctx.expectItemExistsFmt("offset: {} (0x{X}) bytes", .{ len_offset, len_offset });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bits", .{ len_bit_size, len_bit_size });
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test/1", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: 1");
            try ctx.expectItemExists("path: test.1");
            try ctx.expectItemExists("type: f32");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ element_1_address, element_1_address });
            try ctx.expectItemExistsFmt("offset: {} (0x{X}) bytes", .{ element_1_offset, element_1_offset });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ element_1_size, element_1_size });
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);
        }
    };
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should copy correct text to clipboard when clicking text" {
    const Test = struct {
        var value: u8 = 97;

        fn guiFunction(_: sdk.ui.TestContext) !void {
            {
                _ = imgui.igBegin("Window", null, 0);
                defer imgui.igEnd();
                drawData("test", &value);
            }
            sdk.ui.toasts.draw();
        }

        fn testFunction(ctx: sdk.ui.TestContext) !void {
            const address = @intFromPtr(&value);
            sdk.ui.toasts.update(100);

            ctx.setRef("Window");

            ctx.itemClick("test", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("97 (0x61) 'a'");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 97 (0x61) 'a'");
            sdk.ui.toasts.update(100);

            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            ctx.setRef("//$FOCUSED");

            ctx.itemClick("label", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("test");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: test");
            sdk.ui.toasts.update(100);

            ctx.itemClick("path", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("test");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: test");
            sdk.ui.toasts.update(100);

            ctx.itemClick("type", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("u8");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: u8");
            sdk.ui.toasts.update(100);

            ctx.itemClick("address", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardTextFmt("{} (0x{X})", .{ address, address });
            try ctx.expectItemExistsFmt("//toast-0/Copied to clipboard: {} (0x{X})", .{ address, address });
            sdk.ui.toasts.update(100);

            ctx.itemClick("size", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("1 (0x1) bytes");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 1 (0x1) bytes");
            sdk.ui.toasts.update(100);

            ctx.itemClick("value", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("97 (0x61) 'a'");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 97 (0x61) 'a'");
            sdk.ui.toasts.update(100);

            ctx.itemClick("u8", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("97 (0x61)");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 97 (0x61)");
            sdk.ui.toasts.update(100);

            ctx.itemClick("i8", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("97 (0x61)");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 97 (0x61)");
            sdk.ui.toasts.update(100);

            ctx.itemClick("character", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("a");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: a");
            sdk.ui.toasts.update(100);
        }
    };
    sdk.ui.toasts.setIo(testing.io);
    const context = try sdk.ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
