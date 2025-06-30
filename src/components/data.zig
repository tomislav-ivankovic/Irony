const std = @import("std");
const imgui = @import("imgui");
const builtin = @import("builtin");
const memory = @import("../memory/root.zig");
const math = @import("../math/root.zig");
const ui = @import("../ui/root.zig");

pub fn drawData(label: [:0]const u8, pointer: anytype) void {
    if (@typeInfo(@TypeOf(pointer)) != .pointer or @typeInfo(@TypeOf(pointer)).pointer.size != .one) {
        @compileError(
            "The drawData function expects a pointer but provided value is of type: " ++ @typeName(@TypeOf(pointer)),
        );
    }
    const Type = @typeInfo(@TypeOf(pointer)).pointer.child;
    const ctx = Context{
        .label = label,
        .type_name = @typeName(Type),
        .address = @intFromPtr(pointer),
        .bit_offset = null,
        .bit_size = @bitSizeOf(Type),
        .parent = null,
    };
    drawAny(&ctx, pointer);
}

fn drawAny(ctx: *const Context, pointer: anytype) void {
    if (@typeInfo(@TypeOf(pointer)) != .pointer or @typeInfo(@TypeOf(pointer)).pointer.size != .one) {
        @compileError(
            "The drawAny function expects a pointer but provided value is of type: " ++ @typeName(@TypeOf(pointer)),
        );
    }
    const Type = @typeInfo(@TypeOf(pointer)).pointer.child;
    if (Type == memory.PointerTrail) {
        drawPointerTrail(ctx, pointer);
    } else if (hasTag(Type, memory.converted_value_tag)) {
        drawConvertedValue(ctx, pointer);
    } else if (hasTag(Type, memory.pointer_tag)) {
        drawCustomPointer(ctx, pointer);
    } else if (hasTag(Type, memory.proxy_tag)) {
        drawProxy(ctx, pointer);
    } else if (hasTag(Type, memory.struct_proxy_tag)) {
        drawStructProxy(ctx, pointer);
    } else if (hasTag(Type, memory.self_sortable_array_tag)) {
        drawSelfSortableArray(ctx, pointer);
    } else if (hasTag(Type, math.vector_tag)) {
        drawVector(ctx, pointer);
    } else switch (@typeInfo(Type)) {
        .void => drawVoid(ctx),
        .null => drawNull(ctx),
        .undefined => drawUndefined(ctx),
        .bool => drawBool(ctx, pointer),
        .int => drawNumber(ctx, pointer),
        .float => drawNumber(ctx, pointer),
        .comptime_float => drawNumber(ctx, pointer),
        .comptime_int => drawNumber(ctx, pointer),
        .type => drawType(ctx, pointer),
        .enum_literal => drawEnumLiteral(ctx, pointer),
        .@"enum" => drawEnum(ctx, pointer),
        .error_set => drawError(ctx, pointer),
        .optional => drawOptional(ctx, pointer),
        .error_union => drawErrorUnion(ctx, pointer),
        .array => drawArray(ctx, pointer),
        .@"struct" => drawStruct(ctx, pointer),
        .@"union" => drawUnion(ctx, pointer),
        .pointer => |info| switch (@typeInfo(info.child)) {
            .@"fn" => drawMemoryAddress(ctx, pointer),
            .@"opaque" => drawMemoryAddress(ctx, pointer),
            else => drawPointer(ctx, pointer),
        },
        else => @compileError("Unsupported data type: " ++ @tagName(@typeInfo(Type))),
    }
}

// Rendering of language types.

fn drawVoid(ctx: *const Context) void {
    const text = "{} (void instance)";
    drawTreeText(ctx.label, text);

    if (!beginMenu()) return;
    defer endMenu();

    drawDefaultMenuItems(ctx);
    drawSeparator();
    drawMenuText("value", text);
}

fn drawNull(ctx: *const Context) void {
    const text = "null";
    drawTreeText(ctx.label, text);

    if (!beginMenu()) return;
    defer endMenu();

    drawDefaultMenuItems(ctx);
    drawSeparator();
    drawMenuText("value", text);
}

fn drawUndefined(ctx: *const Context) void {
    const text = "undefined";
    drawTreeText(ctx, text);

    if (!beginMenu()) return;
    defer endMenu();

    drawDefaultMenuItems(ctx);
    drawSeparator();
    drawMenuText("value", text);
}

fn drawBool(ctx: *const Context, pointer: anytype) void {
    const text = if (pointer.*) "true" else "false";
    drawTreeText(ctx.label, text);

    if (!beginMenu()) return;
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
    drawTreeText(ctx.label, text);

    if (!beginMenu()) return;
    defer endMenu();

    drawDefaultMenuItems(ctx);
    drawSeparator();
    drawMenuText("value", text);
    drawSeparator();
    drawNumberMenuItems(value);
}

fn drawMemoryAddress(ctx: *const Context, pointer: anytype) void {
    const casted_pointer: *const usize = @ptrCast(pointer);
    drawNumber(ctx, casted_pointer);
}

fn drawType(ctx: *const Context, pointer: *const type) void {
    const text = @typeName(pointer.*);
    drawTreeText(ctx.label, text);

    if (!beginMenu()) return;
    defer endMenu();

    drawDefaultMenuItems(ctx);
    drawSeparator();
    drawMenuText("value", text);
}

fn drawEnumLiteral(ctx: *const Context, pointer: anytype) void {
    const text = @tagName(pointer.*);
    drawTreeText(ctx.label, text);

    if (!beginMenu()) return;
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
    drawTreeText(ctx.label, text);

    if (!beginMenu()) return;
    defer endMenu();

    drawDefaultMenuItems(ctx);
    drawSeparator();
    drawMenuText("value", text);
    drawSeparator();
    drawNumberMenuItems(value);
}

fn drawError(ctx: *const Context, pointer: anytype) void {
    var buffer: [string_buffer_size]u8 = undefined;

    const text = std.fmt.bufPrintZ(&buffer, "error.{s}", .{@errorName(pointer.*)}) catch error_string;
    drawTreeText(ctx.label, text);

    if (!beginMenu()) return;
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
        drawAny(ctx, data);
    } else |err| {
        drawError(ctx, &err);
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

fn drawUnion(ctx: *const Context, pointer: anytype) void {
    const node_open = beginNode(ctx.label);
    defer if (node_open) endNode();
    useDefaultMenu(ctx);
    if (!node_open) return;

    const info = @typeInfo(@TypeOf(pointer.*)).@"union";
    if (info.tag_type) |Tag| {
        const tag_pointer: *const Tag = @ptrCast(pointer);
        const tag_ctx = Context{
            .label = "tag",
            .type_name = @typeName(Tag),
            .address = @intFromPtr(tag_pointer),
            .bit_offset = 0,
            .bit_size = @sizeOf(Tag) * std.mem.byte_size_in_bits,
            .parent = ctx,
        };
        drawAny(&tag_ctx, tag_pointer);

        switch (pointer.*) {
            inline else => |*value_pointer| {
                const value_ctx = Context{
                    .label = "value",
                    .type_name = @typeName(@TypeOf(value_pointer.*)),
                    .address = @intFromPtr(value_pointer),
                    .bit_offset = (@intFromPtr(value_pointer) - @intFromPtr(tag_pointer)) * std.mem.byte_size_in_bits,
                    .bit_size = @bitSizeOf(@TypeOf(value_pointer.*)),
                    .parent = ctx,
                };
                drawAny(&value_ctx, value_pointer);
            },
        }
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
            const Value = info.child;
            const value_pointer = pointer.*;
            const value_ctx = Context{
                .label = "value",
                .type_name = @typeName(Value),
                .address = @intFromPtr(value_pointer),
                .bit_offset = null,
                .bit_size = @bitSizeOf(Value),
                .parent = ctx,
            };
            drawAny(&value_ctx, value_pointer);
        },
        .slice => {
            const len_pointer = &pointer.len;
            const len_ctx = Context{
                .label = "len",
                .type_name = @typeName(@TypeOf(len_pointer.*)),
                .address = @intFromPtr(len_pointer),
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

fn drawPointerTrail(ctx: *const Context, pointer: anytype) void {
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

    const resolved_pointer = &pointer.resolve();
    const resolved_ctx = Context{
        .label = "resolved",
        .type_name = @typeName(@TypeOf(resolved_pointer.*)),
        .address = @intFromPtr(resolved_pointer),
        .bit_offset = null,
        .bit_size = @bitSizeOf(@TypeOf(resolved_pointer.*)),
        .parent = ctx,
    };
    drawAny(&resolved_ctx, resolved_pointer);
}

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
        .type_name = @typeName(@TypeOf(value_pointer.*)),
        .address = @intFromPtr(value_pointer),
        .bit_offset = null,
        .bit_size = @bitSizeOf(@TypeOf(value_pointer.*)),
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
        drawTreeText("value", "not readable");
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

fn drawProxy(ctx: *const Context, pointer: anytype) void {
    const maybe_value_pointer = pointer.toConstPointer();
    if (maybe_value_pointer == null) pushErrorStyle();
    defer if (maybe_value_pointer == null) popErrorStyle();

    const node_open = beginNode(ctx.label);
    defer if (node_open) endNode();
    useDefaultMenu(ctx);
    if (!node_open) return;

    const trail_pointer = &pointer.trail;
    const trail_ctx = Context{
        .label = "trail",
        .type_name = @typeName(@TypeOf(trail_pointer.*)),
        .address = @intFromPtr(trail_pointer),
        .bit_offset = null,
        .bit_size = @bitSizeOf(@TypeOf(trail_pointer.*)),
        .parent = ctx,
    };
    drawAny(&trail_ctx, trail_pointer);

    const value_pointer = maybe_value_pointer orelse {
        drawTreeText("value", "not readable");
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

fn drawStructProxy(ctx: *const Context, pointer: anytype) void {
    const is_valid = pointer.takeFullCopy() != null;
    if (!is_valid) pushErrorStyle();
    const node_open = beginNode(ctx.label);
    defer if (node_open) endNode();
    useDefaultMenu(ctx);
    if (!is_valid) popErrorStyle();
    if (!node_open) return;

    const base_trail_pointer = &pointer.base_trail;
    const base_trail_ctx = Context{
        .label = "base_trail",
        .type_name = @typeName(@TypeOf(base_trail_pointer.*)),
        .address = @intFromPtr(base_trail_pointer),
        .bit_offset = null,
        .bit_size = @bitSizeOf(@TypeOf(base_trail_pointer.*)),
        .parent = ctx,
    };
    drawAny(&base_trail_ctx, base_trail_pointer);

    const field_offsets_pointer = &pointer.field_offsets;
    const field_offsets_ctx = Context{
        .label = "field_offsets",
        .type_name = @typeName(@TypeOf(field_offsets_pointer.*)),
        .address = @intFromPtr(field_offsets_pointer),
        .bit_offset = null,
        .bit_size = @bitSizeOf(@TypeOf(field_offsets_pointer.*)),
        .parent = ctx,
    };
    drawAny(&field_offsets_ctx, field_offsets_pointer);

    const value_ctx = Context{
        .label = "value",
        .type_name = @typeName(@TypeOf(pointer.*).Child),
        .address = pointer.findBaseAddress() orelse 0,
        .bit_offset = null,
        .bit_size = pointer.findSizeFromMaxOffset() * std.mem.byte_size_in_bits,
        .parent = ctx,
    };
    drawStructProxyFields(&value_ctx, pointer);
}

fn drawStructProxyFields(ctx: *const Context, pointer: anytype) void {
    const is_valid = pointer.takeFullCopy() != null;
    if (!is_valid) pushErrorStyle();
    const node_open = beginNode(ctx.label);
    defer if (node_open) endNode();
    useDefaultMenu(ctx);
    if (!is_valid) popErrorStyle();
    if (!node_open) return;

    const fields = @typeInfo(@TypeOf(pointer.*).Child).@"struct".fields;
    inline for (fields) |*field| {
        if (pointer.findConstFieldPointer(field.name)) |field_pointer| {
            const field_ctx = Context{
                .label = field.name,
                .type_name = @typeName(field.type),
                .address = @intFromPtr(field_pointer),
                .bit_offset = (@field(pointer.field_offsets, field.name) orelse 0) * std.mem.byte_size_in_bits,
                .bit_size = @sizeOf(field.type) * std.mem.byte_size_in_bits,
                .parent = ctx,
            };
            drawAny(&field_ctx, field_pointer);
        } else {
            pushErrorStyle();
            defer popErrorStyle();
            drawTreeText(field.name, "not readable");
        }
    }
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

fn drawVector(ctx: *const Context, pointer: anytype) void {
    if (pointer.array.len > 4) {
        drawAny(ctx, &pointer.array);
    } else {
        drawAny(ctx, pointer.asConstCoords());
    }
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

inline fn hasTag(comptime Type: type, comptime tag: type) bool {
    comptime {
        const info = @typeInfo(Type);
        if (info != .@"struct" and info != .@"enum" and info != .@"union") return false;
        if (!@hasDecl(Type, "tag")) return false;
        if (@TypeOf(Type.tag) != type) return false;
        return Type.tag == tag;
    }
}

fn drawTreeText(label: [:0]const u8, text: [:0]const u8) void {
    imgui.igIndent(0.0);
    defer imgui.igUnindent(0.0);
    drawText(label, text);
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
    drawMenuText("address", std.fmt.bufPrintZ(&buffer, "{} (0x{X})", .{ ctx.address, ctx.address }) catch error_string);
    if (ctx.bit_offset) |offset| {
        drawMenuText("offset", bitsToText(&buffer, offset) catch error_string);
    }
    drawMenuText("size", bitsToText(&buffer, ctx.bit_size) catch error_string);
}

fn drawNumberMenuItems(value: anytype) void {
    var buffer: [string_buffer_size]u8 = undefined;
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
    drawText(label, text);
}

fn drawText(label: [:0]const u8, text: [:0]const u8) void {
    imgui.igText("%s: %s", label.ptr, text.ptr);

    var min: imgui.ImVec2 = undefined;
    var max: imgui.ImVec2 = undefined;
    imgui.igGetItemRectMin(&min);
    imgui.igGetItemRectMax(&max);
    const rect = imgui.ImRect{ .Min = min, .Max = max };
    _ = imgui.igItemAdd(rect, imgui.igGetID_Str(label), null, imgui.ImGuiItemFlags_NoNav);

    if (imgui.igIsItemClicked(imgui.ImGuiMouseButton_Left)) {
        imgui.igSetClipboardText(text);
        ui.toasts.send(.info, null, "Copied to clipboard: {s}", .{text});
    }

    if (builtin.is_test) {
        var buffer: [string_buffer_size]u8 = undefined;
        const full_text = std.fmt.bufPrintZ(&buffer, "{s}: {s}", .{ label, text }) catch error_string;
        imgui.teItemAdd(imgui.igGetCurrentContext(), imgui.igGetID_Str(label), &rect, null);
        imgui.teItemAdd(imgui.igGetCurrentContext(), imgui.igGetID_Str(full_text), &rect, null);
    }
}

fn drawSeparator() void {
    imgui.igSeparator();
}

// Language types tests.

const testing = std.testing;

test "should draw void correctly" {
    const Test = struct {
        var value: void = {};

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw null correctly" {
    const Test = struct {
        var value: ?void = null;

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw bool correctly" {
    const Test = struct {
        var value: bool = false;

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw int correctly" {
    const Test = struct {
        var value: u8 = 0;

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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

            value = 255;
            ctx.yield(1);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("u8: 255 (0xFF)");
            try ctx.expectItemExists("i8: -1 (0x-1)");
            try ctx.expectItemExists("character: not printable");
        }
    };
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw float correctly" {
    const Test = struct {
        var value: f32 = -1.0;

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: ui.TestContext) !void {
            const address = @intFromPtr(&value);

            ctx.setRef("Window");
            try ctx.expectItemExists("test: -1e0");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: f32");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ address, address });
            try ctx.expectItemExists("size: 4 (0x4) bytes");
            try ctx.expectItemExists("value: -1e0");
            try ctx.expectItemExists("u32: 3212836864 (0xBF800000)");
            try ctx.expectItemExists("i32: -1082130432 (0x-40800000)");
            try ctx.expectItemExists("f32: -1e0");
        }
    };
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw enum correctly" {
    const Enum = enum(u8) { test_value = 255, _ };
    const Test = struct {
        var value: Enum = @enumFromInt(0);

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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

            value = @enumFromInt(97);
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test: 97 (0x61) 'a'");

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("value: 97 (0x61) 'a'");
            try ctx.expectItemExists("u8: 97 (0x61)");
            try ctx.expectItemExists("i8: 97 (0x61)");
            try ctx.expectItemExists("character: a");
        }
    };
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw error correctly" {
    const Test = struct {
        var value: anyerror = error.TestError;

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw optional correctly" {
    const Test = struct {
        var value: ?bool = null;

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw error union correctly" {
    const Test = struct {
        var value: anyerror!bool = false;

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw function correctly" {
    const Test = struct {
        var value: *const fn (i32, i32) i32 = add;

        fn add(a: i32, b: i32) i32 {
            return a + b;
        }

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw opaque correctly" {
    const Test = struct {
        var value: *const opaque {} = @ptrFromInt(1234);

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
        }
    };
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw array correctly" {
    const Test = struct {
        var value: [3]u32 = .{ 1, 2, 3 };

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
    const context = try ui.getTestingContext();
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

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
    const context = try ui.getTestingContext();
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

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw union correctly" {
    const Int8 = extern union {
        unsigned: u8,
        signed: i8,
    };
    const Test = struct {
        var value: Int8 = .{ .unsigned = 255 };

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw tagged union correctly" {
    const Int8 = union(enum) {
        unsigned: u8,
        signed: i8,
    };
    const Test = struct {
        var value: Int8 = .{ .unsigned = 0 };

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: ui.TestContext) !void {
            const tag_address = @intFromPtr(&value);
            const value_address = tag_address + 1;

            value = .{ .unsigned = 255 };
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: test");
            try ctx.expectItemExists("path: test");
            try ctx.expectItemExists("type: " ++ @typeName(Int8));
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ tag_address, tag_address });
            try ctx.expectItemExists("size: 2 (0x2) bytes");
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemExists("test/tag: unsigned");
            try ctx.expectItemExists("test/value: 255 (0xFF)");
            ctx.itemClick("test/tag", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: tag");
            try ctx.expectItemExists("path: test.tag");
            try ctx.expectItemExists("type: " ++ @typeName(@typeInfo(Int8).@"union".tag_type.?));
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ tag_address, tag_address });
            try ctx.expectItemExists("offset: 0 (0x0) bytes");
            try ctx.expectItemExists("size: 1 (0x1) bytes");
            try ctx.expectItemExists("value: unsigned");
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");
            ctx.itemClick("test/value", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: value");
            try ctx.expectItemExists("path: test.value");
            try ctx.expectItemExists("type: u8");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ value_address, value_address });
            try ctx.expectItemExists("offset: 1 (0x1) bytes");
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
            try ctx.expectItemExists("offset: 1 (0x1) bytes");
            try ctx.expectItemExists("size: 1 (0x1) bytes");
            try ctx.expectItemExists("value: -1 (0x-1)");
        }
    };
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw pointer correctly" {
    const Test = struct {
        var value: *const i32 = &123;

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw slice correctly" {
    const Test = struct {
        var array: [3]u32 = .{ 1, 2, 3 };
        var slice: []u32 = &array;

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &slice);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

// Custom types tests.

test "should draw pointer trail correctly" {
    const Test = struct {
        var trail: memory.PointerTrail = .fromArray(.{});

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &trail);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw converted value correctly" {
    const Test = struct {
        var converted: memory.ConvertedValue(i32, i64, rawToValue, null) = .{ .raw = 123 };

        fn rawToValue(raw: i32) i64 {
            return raw * 2;
        }

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &converted);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
            try ctx.expectItemExists("test/value: 246 (0xF6)");
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
            ctx.itemClick("test/value", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: value");
            try ctx.expectItemExists("path: test.value");
            try ctx.expectItemExists("type: i64");
            try ctx.expectItemExists("address");
            try ctx.expectItemExists("size: 8 (0x8) bytes");
            try ctx.expectItemExists("value: 246 (0xF6)");
        }
    };
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw custom pointer correctly" {
    const Test = struct {
        var pointer: memory.Pointer(i32) = .{ .address = 0 };
        var value: i32 = 123;

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &pointer);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
            try ctx.expectItemExists("type: " ++ @typeName(memory.Pointer(i32)));
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
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw proxy correctly" {
    const Test = struct {
        var proxy: memory.Proxy(i32) = .fromArray(.{});
        var value: i32 = 123;

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &proxy);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw struct proxy correctly" {
    const Struct = extern struct { field_1: u8, field_2: u16, field_3: u32 };
    const Test = struct {
        var proxy: memory.StructProxy(Struct) = .{
            .base_trail = .fromArray(.{}),
            .field_offsets = .{
                .field_1 = @offsetOf(Struct, "field_1"),
                .field_2 = @offsetOf(Struct, "field_2"),
                .field_3 = @offsetOf(Struct, "field_3"),
            },
        };
        var value: Struct = .{ .field_1 = 1, .field_2 = 2, .field_3 = 3 };

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &proxy);
        }

        fn testFunction(ctx: ui.TestContext) !void {
            const proxy_address = @intFromPtr(&proxy);
            const value_address = @intFromPtr(&value);
            const field_2_address = @intFromPtr(&value.field_2);
            const field_1_offset = @offsetOf(Struct, "field_1");
            const field_2_offset = @offsetOf(Struct, "field_2");
            const field_3_offset = @offsetOf(Struct, "field_3");
            const proxy_size = @sizeOf(@TypeOf(proxy));
            const value_size = field_3_offset + @sizeOf(@FieldType(Struct, "field_3"));

            proxy.base_trail = .fromArray(.{value_address});
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
            try ctx.expectItemExists("test/base_trail");
            try ctx.expectItemExists("test/field_offsets");
            try ctx.expectItemExists("test/value");
            ctx.itemClick("test/value", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: value");
            try ctx.expectItemExists("path: test.value");
            try ctx.expectItemExists("type: " ++ @typeName(@TypeOf(value)));
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ value_address, value_address });
            try ctx.expectItemExistsFmt("size: {} (0x{X}) bytes", .{ value_size, value_size });
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            ctx.setRef("Window");

            try ctx.expectItemExists("test/base_trail");
            try ctx.expectItemExists("test/field_offsets");
            try ctx.expectItemExists("test/value");

            ctx.itemClick("test/base_trail", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("test/base_trail/offsets", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("test/field_offsets", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("test/value", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemExists("test/base_trail/offsets/address");
            try ctx.expectItemExists("test/base_trail/offsets/len: 1 (0x1)");
            try ctx.expectItemExistsFmt("test/base_trail/offsets/0: {} (0x{X})", .{ value_address, value_address });
            try ctx.expectItemExistsFmt("test/base_trail/resolved: {} (0x{X})", .{ value_address, value_address });
            try ctx.expectItemExistsFmt("test/field_offsets/field_1: {} (0x{X})", .{ field_1_offset, field_1_offset });
            try ctx.expectItemExistsFmt("test/field_offsets/field_2: {} (0x{X})", .{ field_2_offset, field_2_offset });
            try ctx.expectItemExistsFmt("test/field_offsets/field_3: {} (0x{X})", .{ field_3_offset, field_3_offset });
            try ctx.expectItemExists("test/value/field_1: 1 (0x1)");
            try ctx.expectItemExists("test/value/field_2: 2 (0x2)");
            try ctx.expectItemExists("test/value/field_3: 3 (0x3)");
            ctx.itemClick("test/value/field_2", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);

            ctx.setRef("//$FOCUSED");
            try ctx.expectItemExists("label: field_2");
            try ctx.expectItemExists("path: test.value.field_2");
            try ctx.expectItemExists("type: u16");
            try ctx.expectItemExistsFmt("address: {} (0x{X})", .{ field_2_address, field_2_address });
            try ctx.expectItemExists("size: 2 (0x2) bytes");
            try ctx.expectItemExists("value: 2 (0x2)");
            ctx.mouseClickOnVoid(imgui.ImGuiMouseButton_Left, null);

            proxy.field_offsets.field_3 = null;
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test/field_offsets/field_3: null");
            try ctx.expectItemExists("test/value/field_3: not readable");

            proxy.base_trail = .fromArray(.{null});
            ctx.yield(1);

            ctx.setRef("Window");
            try ctx.expectItemExists("test/base_trail/offsets/len: 1 (0x1)");
            try ctx.expectItemExists("test/base_trail/offsets/0: null");
            try ctx.expectItemExists("test/value/field_1: not readable");
            try ctx.expectItemExists("test/value/field_2: not readable");
            try ctx.expectItemExists("test/value/field_3: not readable");
        }
    };
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw self sortable array correctly" {
    const Test = struct {
        var value: memory.SelfSortableArray(3, i32, isLessThan) = .{
            .raw = .{ 2, 1, 3 },
        };

        fn isLessThan(lhs: *const i32, rhs: *const i32) bool {
            return lhs.* < rhs.*;
        }

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test", &value);
        }

        fn testFunction(ctx: ui.TestContext) !void {
            const address = @intFromPtr(&value);
            const address_of_1 = @intFromPtr(&value.raw[1]);
            const address_of_2 = @intFromPtr(&value.raw[0]);
            const address_of_3 = @intFromPtr(&value.raw[2]);
            const size = @sizeOf(@TypeOf(value));

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
            try ctx.expectItemExists("test/raw");
            try ctx.expectItemExists("test/sorted");
            ctx.itemClick("test/raw", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("test/sorted", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("test/sorted/0", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("test/sorted/1", imgui.ImGuiMouseButton_Left, 0);
            ctx.itemClick("test/sorted/2", imgui.ImGuiMouseButton_Left, 0);
            try ctx.expectItemExists("test/raw/0: 2 (0x2)");
            try ctx.expectItemExists("test/raw/1: 1 (0x1)");
            try ctx.expectItemExists("test/raw/2: 3 (0x3)");
            try ctx.expectItemExistsFmt("test/sorted/0/address: {} (0x{X})", .{ address_of_1, address_of_1 });
            try ctx.expectItemExists("test/sorted/0/value: 1 (0x1)");
            try ctx.expectItemExistsFmt("test/sorted/1/address: {} (0x{X})", .{ address_of_2, address_of_2 });
            try ctx.expectItemExists("test/sorted/1/value: 2 (0x2)");
            try ctx.expectItemExistsFmt("test/sorted/2/address: {} (0x{X})", .{ address_of_3, address_of_3 });
            try ctx.expectItemExists("test/sorted/2/value: 3 (0x3)");
        }
    };
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should draw vector correctly" {
    const Test = struct {
        var value_1: math.Vector(4, f32) = .fromArray(.{ 1, 2, 3, 4 });
        var value_2: math.Vector(5, f32) = .fromArray(.{ 5, 6, 7, 8, 9 });

        fn guiFunction(_: ui.TestContext) !void {
            _ = imgui.igBegin("Window", null, 0);
            defer imgui.igEnd();
            drawData("test_1", &value_1);
            drawData("test_2", &value_2);
        }

        fn testFunction(ctx: ui.TestContext) !void {
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
            try ctx.expectItemExists("test_1/x: 1e0");
            try ctx.expectItemExists("test_1/y: 2e0");
            try ctx.expectItemExists("test_1/z: 3e0");
            try ctx.expectItemExists("test_1/w: 4e0");
            try ctx.expectItemExists("test_2/0: 5e0");
            try ctx.expectItemExists("test_2/1: 6e0");
            try ctx.expectItemExists("test_2/2: 7e0");
            try ctx.expectItemExists("test_2/3: 8e0");
            try ctx.expectItemExists("test_2/4: 9e0");
        }
    };
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}

test "should copy correct text to clipboard when left clicking text" {
    const Test = struct {
        var value: u8 = 97;

        fn guiFunction(_: ui.TestContext) !void {
            {
                _ = imgui.igBegin("Window", null, 0);
                defer imgui.igEnd();
                drawData("test", &value);
            }
            ui.toasts.draw();
        }

        fn testFunction(ctx: ui.TestContext) !void {
            const address = @intFromPtr(&value);

            ctx.setRef("Window");

            ctx.itemClick("test", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("97 (0x61) 'a'");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 97 (0x61) 'a'");
            ui.toasts.update(100);

            ctx.itemClick("test", imgui.ImGuiMouseButton_Right, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            ctx.setRef("//$FOCUSED");

            ctx.itemClick("label", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("test");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: test");
            ui.toasts.update(100);

            ctx.itemClick("path", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("test");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: test");
            ui.toasts.update(100);

            ctx.itemClick("type", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("u8");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: u8");
            ui.toasts.update(100);

            ctx.itemClick("address", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardTextFmt("{} (0x{X})", .{ address, address });
            try ctx.expectItemExistsFmt("//toast-0/Copied to clipboard: {} (0x{X})", .{ address, address });
            ui.toasts.update(100);

            ctx.itemClick("size", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("1 (0x1) bytes");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 1 (0x1) bytes");
            ui.toasts.update(100);

            ctx.itemClick("value", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("97 (0x61) 'a'");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 97 (0x61) 'a'");
            ui.toasts.update(100);

            ctx.itemClick("u8", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("97 (0x61)");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 97 (0x61)");
            ui.toasts.update(100);

            ctx.itemClick("i8", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("97 (0x61)");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: 97 (0x61)");
            ui.toasts.update(100);

            ctx.itemClick("character", imgui.ImGuiMouseButton_Left, imgui.ImGuiTestOpFlags_NoCheckHoveredId);
            try ctx.expectClipboardText("a");
            try ctx.expectItemExists("//toast-0/Copied to clipboard: a");
            ui.toasts.update(100);
        }
    };
    const context = try ui.getTestingContext();
    try context.runTest(.{}, Test.guiFunction, Test.testFunction);
}
