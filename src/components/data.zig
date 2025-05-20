const std = @import("std");
const imgui = @import("imgui");
const memory = @import("../memory/root.zig");

pub fn drawData(label: [:0]const u8, pointer: anytype) void {
    const type_name = switch (@typeInfo(@TypeOf(pointer))) {
        .pointer => |info| @typeName(info.child),
        else => @compileError(
            "The drawData function expects a pointer but provided value is of type: " ++ @typeName(@TypeOf(pointer)),
        ),
    };
    const ctx = Context{
        .label = label,
        .type_name = type_name,
        .address = @intFromPtr(pointer),
        .bit_offset = null,
        .bit_size = @bitSizeOf(@TypeOf(pointer.*)),
        .parent = null,
    };
    drawAny(&ctx, pointer);
}

fn drawAny(ctx: *const Context, pointer: anytype) void {
    const base_info = @typeInfo(@TypeOf(pointer));
    const ChildType = switch (base_info) {
        .pointer => |info| info.child,
        else => @compileError(
            "The drawAny function expects a pointer but provided value is of type: " ++ @typeName(@TypeOf(pointer)),
        ),
    };
    if (hasTag(ChildType, memory.converted_value_tag)) {
        drawConvertedValue(ctx, pointer);
    } else if (hasTag(ChildType, memory.pointer_tag)) {
        drawCustomPointer(ctx, pointer);
    } else if (hasTag(ChildType, memory.pointer_trail_tag)) {
        drawPointerTrail(ctx, pointer);
    } else if (hasTag(ChildType, memory.self_sortable_array_tag)) {
        drawSelfSortableArray(ctx, pointer);
    } else switch (@typeInfo(ChildType)) {
        .void => drawVoid(ctx),
        .null => drawNull(ctx),
        .undefined => drawUndefined(ctx),
        .bool => drawBool(ctx, pointer),
        .int => drawNumber(ctx, pointer),
        .float => drawNumber(ctx, pointer),
        .comptime_float => drawNumber(ctx, pointer),
        .comptime_int => drawNumber(ctx, pointer),
        .@"fn" => drawMemoryAddress(ctx, pointer),
        .@"opaque" => drawMemoryAddress(ctx, pointer),
        .type => drawType(ctx, pointer),
        .enum_literal => drawEnumLiteral(ctx, pointer),
        .@"enum" => drawEnum(ctx, pointer),
        .error_set => drawError(ctx, pointer),
        .optional => drawOptional(ctx, pointer),
        .error_union => drawErrorUnion(ctx, pointer),
        .array => drawArray(ctx, pointer),
        .@"struct" => drawStruct(ctx, pointer),
        .@"union" => drawUnion(ctx, pointer),
        .pointer => drawPointer(ctx, pointer),
        else => @compileError("Unsupported data type: " ++ @tagName(@typeInfo(ChildType))),
    }
}

// Rendering of language types.

fn drawVoid(ctx: *const Context) void {
    const text = "{} (void instance)";
    drawText(ctx, text);

    if (!beginMenu(ctx.label)) return;
    defer endMenu();

    drawDefaultMenuItems(ctx);
    drawSeparator();
    drawMenuText("value", text);
}

fn drawNull(ctx: *const Context) void {
    const text = "null";
    drawText(ctx.label, text);

    if (!beginMenu(ctx.label)) return;
    defer endMenu();

    drawDefaultMenuItems(ctx);
    drawSeparator();
    drawMenuText("value", text);
}

fn drawUndefined(ctx: *const Context) void {
    const text = "undefined";
    drawText(ctx, text);

    if (!beginMenu(ctx.label)) return;
    defer endMenu();

    drawDefaultMenuItems(ctx);
    drawSeparator();
    drawMenuText("value", text);
}

fn drawBool(ctx: *const Context, pointer: *const bool) void {
    const text = if (pointer.*) "true" else "false";
    drawText(ctx.label, text);

    if (!beginMenu(ctx.label)) return;
    defer endMenu();

    drawDefaultMenuItems(ctx);
    drawSeparator();
    drawMenuText("value", text);
}

fn drawNumber(ctx: *const Context, pointer: anytype) void {
    const value = pointer.*;
    var buffer: [string_buffer_size]u8 = undefined;

    const text = if (@TypeOf(value) == u8 and std.ascii.isPrint(value)) block: {
        break :block std.fmt.bufPrintZ(&buffer, "{} (0x{X}) '{c}'", .{ value, value, value }) catch error_string;
    } else if (@typeInfo(@TypeOf(value)) == .int) block: {
        break :block std.fmt.bufPrintZ(&buffer, "{} (0x{X})", .{ value, value }) catch error_string;
    } else block: {
        break :block std.fmt.bufPrintZ(&buffer, "{}", .{value}) catch error_string;
    };
    drawText(ctx.label, text);

    if (!beginMenu(ctx.label)) return;
    defer endMenu();

    drawDefaultMenuItems(ctx);
    drawSeparator();
    drawMenuText("value", text);
    drawSeparator();

    const bits = @bitSizeOf(@TypeOf(value));
    const UType = @Type(std.builtin.Type{ .int = .{ .signedness = .unsigned, .bits = bits } });
    const u_value: UType = @bitCast(value);
    const u_text = std.fmt.bufPrintZ(&buffer, "{} (0x{X})", .{ u_value, u_value }) catch error_string;
    drawMenuText(@typeName(UType), u_text);
    const IType = @Type(std.builtin.Type{ .int = .{ .signedness = .signed, .bits = bits } });
    const i_value: IType = @bitCast(value);
    const i_text = std.fmt.bufPrintZ(&buffer, "{} (0x{X})", .{ i_value, i_value }) catch error_string;
    drawMenuText(@typeName(IType), i_text);
    if (bits == 16 or bits == 32 or bits == 64 or bits == 80 or bits == 128) {
        const FType = @Type(std.builtin.Type{ .float = .{ .bits = bits } });
        const f_value: FType = @bitCast(value);
        const f_text = std.fmt.bufPrintZ(&buffer, "{}", .{f_value}) catch error_string;
        drawMenuText(@typeName(FType), f_text);
    }

    if (bits == 8) {
        drawSeparator();
        if (std.ascii.isPrint(u_value)) {
            const char_text = std.fmt.bufPrintZ(&buffer, "{c}", .{u_value}) catch error_string;
            drawMenuText("character", char_text);
        } else {
            drawMenuText("character", "not printable");
        }
    }
}

fn drawMemoryAddress(ctx: *const Context, pointer: anytype) void {
    const casted_pointer: *const usize = @ptrCast(pointer);
    drawAny(ctx, casted_pointer);
}

fn drawType(ctx: *const Context, pointer: *const type) void {
    const text = @typeName(pointer.*);
    drawText(ctx.label, text);

    if (!beginMenu(ctx.label)) return;
    defer endMenu();

    drawDefaultMenuItems(ctx);
    drawSeparator();
    drawMenuText("value", text);
}

fn drawEnumLiteral(ctx: *const Context, pointer: anytype) void {
    const text = @tagName(pointer.*);
    drawText(ctx.label, text);

    if (!beginMenu(ctx.label)) return;
    defer endMenu();

    drawDefaultMenuItems(ctx);
    drawSeparator();
    drawMenuText("value", text);
}

fn drawEnum(ctx: *const Context, pointer: anytype) void {
    const info = @typeInfo(@TypeOf(pointer.*)).@"enum";
    const value = @intFromEnum(pointer.*);
    var text: [:0]const u8 = undefined;
    inline for (info.fields) |*field| {
        if (field.value == value) {
            text = field.name;
            break;
        }
    } else {
        pushErrorStyle();
        defer popErrorStyle();
        drawAny(ctx, &value);
        return;
    }
    drawText(ctx.label, text);

    if (!beginMenu(ctx.label)) return;
    defer endMenu();

    drawDefaultMenuItems(ctx);
    drawSeparator();
    drawMenuText("value", text);
}

fn drawError(ctx: *const Context, pointer: anytype) void {
    const text = @errorName(pointer.*);
    drawText(ctx.label, text);

    if (!beginMenu(ctx.label)) return;
    defer endMenu();

    drawDefaultMenuItems(ctx);
    drawSeparator();
    drawMenuText("value", text);
}

fn drawOptional(ctx: *const Context, pointer: anytype) void {
    if (pointer.*) |*data| {
        drawAny(ctx, data);
    } else {
        drawNull(ctx);
    }
}

fn drawErrorUnion(ctx: *const Context, pointer: anytype) void {
    if (pointer.*) |*data| {
        drawAny(ctx.label, data);
    } else |err| {
        drawError(ctx.label, &err);
    }
}

fn drawArray(ctx: *const Context, pointer: anytype) void {
    const node_open = beginNode(ctx.label);
    defer if (node_open) endNode();
    useDefaultMenu(ctx);
    if (!node_open) return;

    for (pointer, 0..) |*element_pointer, index| {
        var buffer: [string_buffer_size]u8 = undefined;
        const element_ctx = Context{
            .label = std.fmt.bufPrintZ(&buffer, "{}", .{index}) catch error_string,
            .type_name = @typeName(@TypeOf(element_pointer.*)),
            .address = @intFromPtr(element_pointer),
            .bit_offset = std.mem.byte_size_in_bits * (@intFromPtr(element_pointer) - @intFromPtr(pointer)),
            .bit_size = @bitSizeOf(@TypeOf(element_pointer.*)),
            .parent = ctx,
        };
        drawAny(&element_ctx, element_pointer);
    }
}

fn drawStruct(ctx: *const Context, pointer: anytype) void {
    const node_open = beginNode(ctx.label);
    defer if (node_open) endNode();

    const storage = imgui.igGetStateStorage();
    const show_hidden_id = imgui.igGetID_Str("show_hidden");
    const cast_to_array_id = imgui.igGetID_Str("cast_to_array");
    var show_hidden = imgui.ImGuiStorage_GetBool(storage, show_hidden_id, false);
    var cast_to_array = imgui.ImGuiStorage_GetBool(storage, cast_to_array_id, false);
    if (beginMenu(ctx.label)) {
        defer endMenu();
        drawDefaultMenuItems(ctx);
        drawSeparator();
        _ = imgui.igCheckbox("Show Hidden Fields", &show_hidden);
        _ = imgui.igCheckbox("Cast to Array", &cast_to_array);
    }
    imgui.ImGuiStorage_SetBool(storage, show_hidden_id, show_hidden);
    imgui.ImGuiStorage_SetBool(storage, cast_to_array_id, cast_to_array);

    if (!node_open) return;

    if (cast_to_array) {
        drawStructAsArray(ctx, pointer);
        return;
    }

    const info = @typeInfo(@TypeOf(pointer.*)).@"struct";
    if (info.backing_integer) |BackingInt| {
        const backing_int_pointer: *const BackingInt = @ptrCast(pointer);
        const backing_int_ctx = Context{
            .label = "backing integer",
            .type_name = @typeName(BackingInt),
            .address = @intFromPtr(backing_int_pointer),
            .bit_offset = null,
            .bit_size = @bitSizeOf(BackingInt),
            .parent = ctx,
        };
        drawAny(&backing_int_ctx, backing_int_pointer);
    }
    inline for (info.fields) |*field| {
        const is_hidden = comptime std.mem.startsWith(u8, field.name, "_");
        if (!is_hidden or show_hidden) {
            const field_pointer = &@field(pointer, field.name);
            const bit_size = @bitSizeOf(@TypeOf(field_pointer.*));
            const byte_size = @sizeOf(@TypeOf(field_pointer.*));
            const final_size = if (info.layout == .@"packed") bit_size else std.mem.byte_size_in_bits * byte_size;
            const field_ctx = Context{
                .label = field.name,
                .type_name = @typeName(field.type),
                .address = @intFromPtr(field_pointer),
                .bit_offset = @bitOffsetOf(@TypeOf(pointer.*), field.name),
                .bit_size = final_size,
                .parent = ctx,
            };
            drawAny(&field_ctx, field_pointer);
        }
    }
}

fn drawStructAsArray(ctx: *const Context, pointer: anytype) void {
    const Struct = @TypeOf(pointer.*);
    inline for (.{ u8, u16, u32, u64, u128, i8, i16, i32, i64, i128, f32, f64 }) |Element| {
        if (@sizeOf(Element) > @sizeOf(Struct) or @alignOf(Struct) % @alignOf(Element) != 0) {
            continue;
        }
        const Array = @Type(.{ .array = .{
            .child = Element,
            .len = @sizeOf(Struct) / @sizeOf(Element),
            .sentinel_ptr = null,
        } });
        const array_pointer: *const Array = @ptrCast(pointer);
        const array_ctx = Context{
            .label = @typeName(Array),
            .type_name = @typeName(Array),
            .address = @intFromPtr(array_pointer),
            .bit_offset = null,
            .bit_size = @bitSizeOf(Array),
            .parent = ctx,
        };
        drawAny(&array_ctx, array_pointer);
    }
}

fn drawUnion(ctx: *const Context, pointer: anytype) void {
    const node_open = beginNode(ctx.label);
    defer if (node_open) endNode();
    useDefaultMenu(ctx);
    if (!node_open) return;

    const info = @typeInfo(@TypeOf(pointer.*)).@"union";
    if (info.tag_type) |Tag| {
        const tag_pointer = &@as(Tag, pointer.*);
        const tag_ctx = Context{
            .label = "tag",
            .type_name = @typeName(Tag),
            .address = @intFromPtr(tag_pointer),
            .bit_offset = null,
            .bit_size = @bitSizeOf(Tag),
            .parent = ctx,
        };
        drawAny(&tag_ctx, tag_pointer);

        const value_pointer = switch (pointer.*) {
            inline else => |*ptr| ptr,
        };
        const value_ctx = Context{
            .label = "value",
            .type_name = @typeName(@TypeOf(value_pointer.*)),
            .address = @intFromPtr(value_pointer),
            .bit_offset = null,
            .bit_size = @bitSizeOf(@TypeOf(value_pointer.*)),
            .parent = ctx,
        };
        drawAny(&value_ctx, value_pointer);
    } else inline for (info.fields) |*field| {
        const field_pointer: *const field.type = @ptrCast(pointer);
        const field_ctx = Context{
            .label = field.name,
            .type_name = @typeName(field.type),
            .address = @intFromPtr(field_pointer),
            .bit_offset = null,
            .bit_size = @bitSizeOf(field.type),
            .parent = ctx,
        };
        drawAny(&field_ctx, field_pointer);
    }
}

fn drawPointer(ctx: *const Context, pointer: anytype) void {
    const node_open = beginNode(ctx.label);
    defer if (node_open) endNode();
    useDefaultMenu(ctx);
    if (!node_open) return;

    const address_pointer: *const usize = @ptrCast(pointer);
    const address_ctx = Context{
        .label = "address",
        .type_name = @typeName(usize),
        .address = @intFromPtr(address_pointer),
        .bit_offset = null,
        .bit_size = @bitSizeOf(usize),
        .parent = ctx,
    };
    drawAny(&address_ctx, address_pointer);

    const info = @typeInfo(@TypeOf(pointer.*)).pointer;
    switch (info.size) {
        .one => {
            const value_pointer = pointer.*;
            const value_ctx = Context{
                .label = "value",
                .type_name = @typeName(@TypeOf(value_pointer.*)),
                .address = @intFromPtr(value_pointer),
                .bit_offset = null,
                .bit_size = @bitSizeOf(@TypeOf(value_pointer.*)),
                .parent = ctx,
            };
            drawAny(&value_ctx, value_pointer);
        },
        .slice => {
            const len_pointer = &pointer.len;
            const len_ctx = Context{
                .label = "len",
                .type_name = @typeName(@TypeOf(len_pointer.*)),
                .address = @intFromPtr(address_pointer),
                .bit_offset = null,
                .bit_size = @bitSizeOf(@TypeOf(len_pointer.*)),
                .parent = ctx,
            };
            drawAny(&len_ctx, len_pointer);

            for (pointer.*, 0..) |*element_pointer, index| {
                var buffer: [string_buffer_size]u8 = undefined;
                const element_ctx = Context{
                    .label = std.fmt.bufPrintZ(&buffer, "{}", .{index}) catch error_string,
                    .type_name = @typeName(@TypeOf(element_pointer.*)),
                    .address = @intFromPtr(element_pointer),
                    .bit_offset = std.mem.byte_size_in_bits * (@intFromPtr(element_pointer) - @intFromPtr(pointer.ptr)),
                    .bit_size = @bitSizeOf(@TypeOf(element_pointer.*)),
                    .parent = ctx,
                };
                drawAny(&element_ctx, element_pointer);
            }
        },
        else => {},
    }
}

// Rendering of custom types.

fn drawConvertedValue(ctx: *const Context, pointer: anytype) void {
    const node_open = beginNode(ctx.label);
    defer if (node_open) endNode();
    useDefaultMenu(ctx);
    if (!node_open) return;

    const raw_pointer = &pointer.raw;
    const raw_ctx = Context{
        .label = "raw",
        .type_name = @typeName(@TypeOf(raw_pointer.*)),
        .address = @intFromPtr(raw_pointer),
        .bit_offset = @bitOffsetOf(@TypeOf(pointer.*), "raw"),
        .bit_size = @bitSizeOf(@TypeOf(raw_pointer.*)),
        .parent = ctx,
    };
    drawAny(&raw_ctx, raw_pointer);

    const value_pointer = &pointer.getValue();
    const value_ctx = Context{
        .label = "value",
        .type_name = @typeName(@TypeOf(raw_pointer.*)),
        .address = @intFromPtr(raw_pointer),
        .bit_offset = null,
        .bit_size = @bitSizeOf(@TypeOf(raw_pointer.*)),
        .parent = ctx,
    };
    drawAny(&value_ctx, value_pointer);
}

fn drawCustomPointer(ctx: *const Context, pointer: anytype) void {
    const maybe_value_pointer = pointer.toConstPointer();
    if (maybe_value_pointer == null) pushErrorStyle();
    defer if (maybe_value_pointer == null) popErrorStyle();

    const node_open = beginNode(ctx.label);
    defer if (node_open) endNode();
    useDefaultMenu(ctx);
    if (!node_open) return;

    const address_pointer = &pointer.address;
    const address_ctx = Context{
        .label = "address",
        .type_name = @typeName(@TypeOf(address_pointer.*)),
        .address = @intFromPtr(address_pointer),
        .bit_offset = @bitOffsetOf(@TypeOf(pointer.*), "address"),
        .bit_size = @bitSizeOf(@TypeOf(address_pointer.*)),
        .parent = ctx,
    };
    drawAny(&address_ctx, address_pointer);

    const value_pointer = maybe_value_pointer orelse {
        drawText("value", "not readable");
        return;
    };
    const value_ctx = Context{
        .label = "value",
        .type_name = @typeName(@TypeOf(value_pointer.*)),
        .address = @intFromPtr(value_pointer),
        .bit_offset = null,
        .bit_size = @bitSizeOf(@TypeOf(value_pointer.*)),
        .parent = ctx,
    };
    drawAny(&value_ctx, value_pointer);
}

fn drawPointerTrail(ctx: *const Context, pointer: anytype) void {
    const maybe_value_pointer = pointer.toConstPointer();
    if (maybe_value_pointer == null) pushErrorStyle();
    defer if (maybe_value_pointer == null) popErrorStyle();

    const node_open = beginNode(ctx.label);
    defer if (node_open) endNode();
    useDefaultMenu(ctx);
    if (!node_open) return;

    const offsets_pointer = &pointer.getOffsets();
    const offsets_ctx = Context{
        .label = "offsets",
        .type_name = @typeName(@TypeOf(offsets_pointer.*)),
        .address = @intFromPtr(offsets_pointer),
        .bit_offset = null,
        .bit_size = @bitSizeOf(@TypeOf(offsets_pointer.*)),
        .parent = ctx,
    };
    drawAny(&offsets_ctx, offsets_pointer);

    const value_pointer = maybe_value_pointer orelse {
        drawText("value", "not readable");
        return;
    };
    const value_ctx = Context{
        .label = "value",
        .type_name = @typeName(@TypeOf(value_pointer.*)),
        .address = @intFromPtr(value_pointer),
        .bit_offset = null,
        .bit_size = @bitSizeOf(@TypeOf(value_pointer.*)),
        .parent = ctx,
    };
    drawAny(&value_ctx, value_pointer);
}

fn drawSelfSortableArray(ctx: *const Context, pointer: anytype) void {
    const node_open = beginNode(ctx.label);
    defer if (node_open) endNode();
    useDefaultMenu(ctx);
    if (!node_open) return;

    const raw_pointer = &pointer.raw;
    const raw_ctx = Context{
        .label = "raw",
        .type_name = @typeName(@TypeOf(raw_pointer.*)),
        .address = @intFromPtr(raw_pointer),
        .bit_offset = @bitOffsetOf(@TypeOf(pointer.*), "raw"),
        .bit_size = @bitSizeOf(@TypeOf(raw_pointer.*)),
        .parent = ctx,
    };
    drawAny(&raw_ctx, raw_pointer);

    const sorted_pointer = &pointer.sortedConst();
    const sorted_ctx = Context{
        .label = "sorted",
        .type_name = @typeName(@TypeOf(sorted_pointer.*)),
        .address = @intFromPtr(sorted_pointer),
        .bit_offset = null,
        .bit_size = @bitSizeOf(@TypeOf(sorted_pointer.*)),
        .parent = ctx,
    };
    drawAny(&sorted_ctx, sorted_pointer);
}

// Helper data-structures and functions.

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
        var stream = std.io.fixedBufferStream(buffer);
        try self.writePath(stream.writer());
        try stream.writer().writeByte(0);
        return buffer[0..(stream.pos - 1) :0];
    }

    fn writePath(self: *const Self, writer: anytype) !void {
        if (self.parent) |parent| {
            try parent.writePath(writer);
            try writer.writeByte('.');
        }
        try writer.writeAll(self.label);
    }
};

pub inline fn hasTag(comptime Type: type, comptime tag: type) bool {
    comptime {
        if (@typeInfo(Type) != .@"struct") return false;
        if (!@hasDecl(Type, "tag")) return false;
        if (@TypeOf(Type.tag) != type) return false;
        return Type.tag == tag;
    }
}

fn drawText(label: [:0]const u8, text: [:0]const u8) void {
    imgui.igIndent(0.0);
    defer imgui.igUnindent(0.0);
    imgui.igBeginGroup();
    defer imgui.igEndGroup();
    imgui.igText("%s:", label.ptr);
    imgui.igSameLine(0.0, -0.1);
    imgui.igText("%s", text.ptr);
}

fn beginNode(label: [:0]const u8) bool {
    return imgui.igTreeNode_Str(label);
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

fn beginMenu(id: [:0]const u8) bool {
    return imgui.igBeginPopupContextItem(id, imgui.ImGuiPopupFlags_MouseButtonRight);
}

fn endMenu() void {
    imgui.igEndPopup();
}

fn useDefaultMenu(ctx: *const Context) void {
    if (!beginMenu(ctx.label)) return;
    defer endMenu();
    drawDefaultMenuItems(ctx);
}

fn drawDefaultMenuItems(ctx: *const Context) void {
    var buffer: [string_buffer_size]u8 = undefined;
    drawMenuText("label", ctx.label);
    drawMenuText("path", ctx.getPath(&buffer) catch error_string);
    drawMenuText("type", ctx.type_name);
    drawSeparator();
    drawMenuText("address", std.fmt.bufPrintZ(&buffer, "{} (0x{X})", .{ ctx.address, ctx.address }) catch error_string);
    if (ctx.bit_offset) |offset| {
        drawMenuText("offset", bitsToText(&buffer, offset) catch error_string);
    }
    drawMenuText("size", bitsToText(&buffer, ctx.bit_size) catch error_string);
}

fn bitsToText(buffer: []u8, bits_value: usize) ![:0]u8 {
    const bytes = bits_value / std.mem.byte_size_in_bits;
    const bits = bits_value % std.mem.byte_size_in_bits;
    if (bits == 0) {
        return std.fmt.bufPrintZ(buffer, "{} (0x{X}) bytes", .{ bytes, bytes });
    } else if (bytes == 0) {
        return std.fmt.bufPrintZ(buffer, "{} (0x{X}) bits", .{ bits, bits });
    } else {
        return std.fmt.bufPrintZ(buffer, "{} (0x{X}) bytes, {} (0x{X}) bits", .{ bytes, bytes, bits, bits });
    }
}

fn drawMenuText(label: [:0]const u8, text: [:0]const u8) void {
    imgui.igText("%s:", label.ptr);
    imgui.igSameLine(0.0, -0.1);
    imgui.igText("%s", text.ptr);
}

fn drawSeparator() void {
    imgui.igSeparator();
}
