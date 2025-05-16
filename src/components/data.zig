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
        .offset = 0,
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
        drawPointer(ctx, pointer);
    } else if (hasTag(ChildType, memory.pointer_trail_tag)) {
        drawPointerTrail(ctx, pointer);
    } else if (hasTag(ChildType, memory.self_sortable_array_tag)) {
        drawSelfSortableArray(ctx, pointer);
    } else switch (@typeInfo(ChildType)) {
        .pointer => drawAny(ctx, pointer.*),
        .void => drawVoid(ctx, pointer),
        .null => drawNull(ctx, pointer),
        .undefined => drawUndefined(ctx, pointer),
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
        else => @compileError("Unsupported data type: " ++ @tagName(@typeInfo(ChildType))),
    }
}

// Rendering of custom types.

fn drawConvertedValue(ctx: *const Context, pointer: anytype) void {
    drawAny(ctx, &pointer.getValue());
}

fn drawPointer(ctx: *const Context, pointer: anytype) void {
    if (pointer.toConstPointer()) |ptr| {
        drawAny(ctx, ptr);
        return;
    }

    const text = "Invalid pointer.";
    drawText(ctx.label, text);

    if (!beginMenu(ctx, pointer)) return;
    defer endMenu();

    drawSeparator();
    drawMenuText("value", text);
}

fn drawPointerTrail(ctx: *const Context, pointer: anytype) void {
    if (pointer.toConstPointer()) |ptr| {
        drawAny(ctx, ptr);
        return;
    }

    const text = "Invalid pointer trail.";
    drawText(ctx.label, text);

    if (!beginMenu(ctx, pointer)) return;
    defer endMenu();

    drawSeparator();
    drawMenuText("value", text);
}

fn drawSelfSortableArray(ctx: *const Context, pointer: anytype) void {
    drawAny(ctx, pointer.sortedConst());
}

// Rendering of language types.

fn drawVoid(ctx: *const Context, pointer: anytype) void {
    const text = "{} (void instance)";
    drawText(ctx, text);

    if (!beginMenu(ctx, pointer)) return;
    defer endMenu();

    drawSeparator();
    drawMenuText("value", text);
}

fn drawNull(ctx: *const Context, pointer: anytype) void {
    const text = "null";
    drawText(ctx, text);

    if (!beginMenu(ctx, pointer)) return;
    defer endMenu();

    drawSeparator();
    drawMenuText("value", text);
}

fn drawUndefined(ctx: *const Context, pointer: anytype) void {
    const text = "undefined";
    drawText(ctx, text);

    if (!beginMenu(ctx, pointer)) return;
    defer endMenu();

    drawSeparator();
    drawMenuText("value", text);
}

fn drawBool(ctx: *const Context, pointer: *const bool) void {
    const text = if (pointer.*) "true" else "false";
    drawText(ctx.label, text);

    if (!beginMenu(ctx, pointer)) return;
    defer endMenu();

    drawSeparator();
    drawMenuText("value", text);
}

fn drawNumber(ctx: *const Context, pointer: anytype) void {
    const value = pointer.*;
    var buffer: [64]u8 = undefined;

    const text = std.fmt.bufPrintZ(&buffer, "{}", .{value}) catch error_string;
    drawText(ctx.label, text);

    if (!beginMenu(ctx, pointer)) return;
    defer endMenu();

    drawSeparator();
    if (@typeInfo(@TypeOf(value)) == .int) {
        const value_text = std.fmt.bufPrintZ(&buffer, "{} (0x{X})", .{ value, value }) catch error_string;
        drawMenuText("value", value_text);
    } else {
        drawMenuText("value", text);
    }

    const bits = @bitSizeOf(@TypeOf(value));
    drawSeparator();
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
}

fn drawMemoryAddress(ctx: *const Context, pointer: anytype) void {
    const address = @intFromPtr(pointer);

    var buffer: [64]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buffer, "0x{X}", .{address}) catch error_string;
    drawText(ctx.label, text);

    if (!beginMenu(ctx, pointer)) return;
    defer endMenu();

    drawSeparator();
    drawMenuText("value", text);
}

fn drawType(ctx: *const Context, pointer: *const type) void {
    const text = @typeName(pointer.*);
    drawText(ctx.label, text);

    if (!beginMenu(ctx, pointer)) return;
    defer endMenu();

    drawSeparator();
    drawMenuText("value", text);
}

fn drawEnumLiteral(ctx: *const Context, pointer: anytype) void {
    const text = @tagName(pointer.*);
    drawText(ctx.label, text);

    if (!beginMenu(ctx, pointer)) return;
    defer endMenu();

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
        drawAny(ctx, &value);
        return;
    }
    drawText(ctx.label, text);

    if (!beginMenu(ctx, pointer)) return;
    defer endMenu();

    drawSeparator();
    drawMenuText("value", text);
}

fn drawError(ctx: *const Context, pointer: anytype) void {
    const text = @errorName(pointer.*);
    drawText(ctx.label, text);

    if (!beginMenu(ctx, pointer)) return;
    defer endMenu();

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
    if (beginMenu(ctx, pointer)) {
        defer endMenu();
    }
    if (!node_open) return;
    defer endNode();

    const ElementType = @typeInfo(@TypeOf(pointer.*)).array.child;
    for (pointer, 0..) |*element_pointer, index| {
        var buffer: [64]u8 = undefined;
        const element_ctx = Context{
            .label = std.fmt.bufPrintZ(&buffer, "{}", .{index}) catch error_string,
            .type_name = @typeName(ElementType),
            .offset = @intFromPtr(element_pointer) - @intFromPtr(pointer),
            .parent = ctx,
        };
        drawAny(&element_ctx, element_pointer);
    }
}

fn drawStruct(ctx: *const Context, pointer: anytype) void {
    const node_open = beginNode(ctx.label);
    if (beginMenu(ctx, pointer)) {
        defer endMenu();
    }
    if (!node_open) return;
    defer endNode();

    const info = @typeInfo(@TypeOf(pointer.*)).@"struct";
    inline for (info.fields) |*field| {
        if (comptime std.mem.startsWith(u8, field.name, "_")) {
            continue;
        }
        const field_pointer = &@field(pointer, field.name);
        const field_ctx = Context{
            .label = field.name,
            .type_name = @typeName(field.type),
            .offset = @intFromPtr(field_pointer) - @intFromPtr(pointer),
            .parent = ctx,
        };
        drawAny(&field_ctx, field_pointer);
    }
}

fn drawUnion(ctx: *const Context, pointer: anytype) void {
    const node_open = beginNode(ctx.label);
    if (beginMenu(ctx, pointer)) {
        defer endMenu();
    }
    if (!node_open) return;
    defer endNode();

    const info = @typeInfo(@TypeOf(pointer.*)).@"union";
    if (info.tag_type) |tag_type| {
        const tag_pointer = &@as(tag_type, pointer.*);
        const tag_ctx = Context{
            .label = "tag",
            .type_name = @typeName(tag_type),
            .offset = @intFromPtr(tag_pointer) - @intFromPtr(pointer),
            .parent = ctx,
        };
        drawAny(&tag_ctx, tag_pointer);

        const value_pointer = switch (pointer.*) {
            inline else => |*ptr| ptr,
        };
        const value_ctx = Context{
            .label = "value",
            .type_name = @typeName(@TypeOf(value_pointer.*)),
            .offset = value_pointer - pointer,
            .parent = ctx,
        };
        drawAny(&value_ctx, value_pointer);
    } else inline for (info.fields) |*field| {
        const field_pointer: *const field.type = @ptrCast(pointer);
        const field_ctx = Context{
            .label = field.name,
            .type_name = @typeName(field.type),
            .offset = 0,
            .parent = ctx,
        };
        drawAny(&field_ctx, field_pointer);
    }
}

// Helpers.

const error_string = "display error";

const Context = struct {
    label: [:0]const u8,
    type_name: [:0]const u8,
    offset: usize,
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

fn beginMenu(ctx: *const Context, pointer: anytype) bool {
    imgui.igSetItemTooltip("Right-click to open popup.");
    const menu_open = imgui.igBeginPopupContextItem(ctx.label, imgui.ImGuiPopupFlags_MouseButtonRight);
    if (!menu_open) return false;

    var buffer: [128]u8 = undefined;

    drawMenuText("label", ctx.label);
    drawMenuText("path", ctx.getPath(&buffer) catch error_string);
    drawMenuText("type", ctx.type_name);

    drawSeparator();

    const address = @intFromPtr(pointer);
    const address_text = std.fmt.bufPrintZ(&buffer, "0x{X}", .{address}) catch error_string;
    drawMenuText("address", address_text);
    const offset = ctx.offset;
    const offset_text = std.fmt.bufPrintZ(&buffer, "{} (0x{X})", .{ offset, offset }) catch error_string;
    drawMenuText("offset", offset_text);
    const size = @sizeOf(@TypeOf(pointer.*));
    const size_text = std.fmt.bufPrintZ(&buffer, "{} (0x{X})", .{ size, size }) catch error_string;
    drawMenuText("size", size_text);

    return true;
}

fn endMenu() void {
    imgui.igEndPopup();
}

fn drawMenuText(label: [:0]const u8, text: [:0]const u8) void {
    imgui.igText("%s:", label.ptr);
    imgui.igSameLine(0.0, -0.1);
    imgui.igText("%s", text.ptr);
}

fn drawSeparator() void {
    imgui.igSeparator();
}
