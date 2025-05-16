const std = @import("std");
const imgui = @import("imgui");
const memory = @import("../memory/root.zig");

const error_color = imgui.ImVec4{ .x = 1, .y = 0.5, .z = 0.5, .w = 1 };
const null_color = imgui.ImVec4{ .x = 0, .y = 1, .z = 1, .w = 1 };

const Context = struct {
    label: [:0]const u8,
    type_name: [:0]const u8,
    parent: ?*const Context,
};

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
        .void => drawVoid(ctx),
        .null => drawNull(ctx),
        .undefined => drawUndefined(),
        .bool => drawBool(ctx, pointer),
        .int => drawNumber(ctx, pointer),
        .float => drawNumber(ctx, pointer),
        .comptime_float => drawComptimeNumber(ctx, pointer),
        .comptime_int => drawComptimeNumber(ctx, pointer),
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

fn drawConvertedValue(ctx: *const Context, pointer: anytype) void {
    drawAny(ctx, &pointer.getValue());
}

fn drawPointer(ctx: *const Context, pointer: anytype) void {
    if (pointer.toConstPointer()) |ptr| {
        drawAny(ctx, ptr);
    } else {
        drawText(ctx.label, "Invalid pointer.", error_color);
    }
}

fn drawPointerTrail(ctx: *const Context, pointer: anytype) void {
    if (pointer.toConstPointer()) |ptr| {
        drawAny(ctx, ptr);
    } else {
        drawText(ctx.label, "Invalid pointer trail.", error_color);
    }
}

fn drawSelfSortableArray(ctx: *const Context, pointer: anytype) void {
    drawAny(ctx, pointer.sortedConst());
}

fn drawVoid(ctx: *const Context) void {
    drawText(ctx, "{} (void instance)", null);
}

fn drawNull(ctx: *const Context) void {
    drawText(ctx, "null", null_color);
}

fn drawUndefined(ctx: *const Context) void {
    drawText(ctx, "undefined", null);
}

fn drawBool(ctx: *const Context, pointer: *const bool) void {
    const text = if (pointer.*) "true" else "false";
    drawText(ctx.label, text, null);
}

fn drawNumber(ctx: *const Context, pointer: anytype) void {
    var buffer: [64]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buffer, "{}", .{pointer.*}) catch "display error";
    drawText(ctx.label, text, null);
}

fn drawComptimeNumber(ctx: *const Context, pointer: anytype) void {
    const text = std.fmt.comptimePrint("{}", .{pointer.*});
    drawText(ctx.label, text, null);
}

fn drawMemoryAddress(ctx: *const Context, pointer: anytype) void {
    const address = @intFromPtr(pointer);
    var buffer: [64]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buffer, "0x{X}", .{address}) catch "display error";
    drawText(ctx.label, text, null);
}

fn drawType(ctx: *const Context, pointer: *const type) void {
    const text = @typeName(pointer.*);
    drawText(ctx.label, text, null);
}

fn drawEnumLiteral(ctx: *const Context, pointer: anytype) void {
    const text = @tagName(pointer.*);
    drawText(ctx.label, text, null);
}

fn drawEnum(ctx: *const Context, pointer: anytype) void {
    const ChildType = @typeInfo(@TypeOf(pointer)).pointer.child;
    const info = @typeInfo(ChildType).@"enum";
    const value = @intFromEnum(pointer.*);
    inline for (info.fields) |*field| {
        if (field.value == value) {
            drawText(ctx.label, field.name, null);
            break;
        }
    } else {
        drawAny(ctx, &value);
    }
}

fn drawError(ctx: *const Context, pointer: anytype) void {
    const text = @errorName(pointer.*);
    drawText(ctx.label, text, error_color);
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
    const ChildType = @typeInfo(@TypeOf(pointer)).pointer.child;
    const ElementType = @typeInfo(ChildType).array.child;
    if (!imgui.igTreeNode_Str(ctx.label)) {
        return;
    }
    defer imgui.igTreePop();
    for (pointer, 0..) |*element_pointer, index| {
        var buffer: [64]u8 = undefined;
        const element_ctx = Context{
            .label = std.fmt.bufPrintZ(&buffer, "{}", .{index}) catch "display error",
            .type_name = @typeName(ElementType),
            .parent = ctx,
        };
        drawAny(&element_ctx, element_pointer);
    }
}

fn drawStruct(ctx: *const Context, pointer: anytype) void {
    const ChildType = @typeInfo(@TypeOf(pointer)).pointer.child;
    const info = @typeInfo(ChildType).@"struct";
    if (!imgui.igTreeNode_Str(ctx.label)) {
        return;
    }
    defer imgui.igTreePop();
    inline for (info.fields) |*field| {
        if (comptime std.mem.startsWith(u8, field.name, "_")) {
            continue;
        }
        const field_ctx = Context{
            .label = field.name,
            .type_name = @typeName(field.type),
            .parent = ctx,
        };
        const field_pointer = &@field(pointer, field.name);
        drawAny(&field_ctx, field_pointer);
    }
}

fn drawUnion(ctx: *const Context, pointer: anytype) void {
    const ChildType = @typeInfo(@TypeOf(pointer)).pointer.child;
    const info = @typeInfo(ChildType).@"union";
    if (!imgui.igTreeNode_Str(ctx.label)) {
        return;
    }
    defer imgui.igTreePop();
    if (info.tag_type) |tag_type| {
        const tag_ctx = Context{
            .label = "tag",
            .type_name = @typeName(tag_type),
            .parent = ctx,
        };
        const tag_pointer = &@as(tag_type, pointer.*);
        drawAny(&tag_ctx, tag_pointer);

        const value_pointer = switch (pointer.*) {
            inline else => |*ptr| ptr,
        };
        const value_ctx = Context{
            .label = "value",
            .type_name = @typeName(@typeInfo(@TypeOf(value_pointer)).pointer.child),
            .parent = ctx,
        };
        drawAny(&value_ctx, value_pointer);
    } else inline for (info.fields) |*field| {
        const field_ctx = Context{
            .label = field.name,
            .type_name = @typeName(field.type),
            .parent = ctx,
        };
        const field_pointer: *const field.type = @ptrCast(pointer);
        drawAny(&field_ctx, field_pointer);
    }
}

pub inline fn hasTag(comptime Type: type, comptime tag: type) bool {
    comptime {
        if (@typeInfo(Type) != .@"struct") return false;
        if (!@hasDecl(Type, "tag")) return false;
        if (@TypeOf(Type.tag) != type) return false;
        return Type.tag == tag;
    }
}

fn drawText(label: [:0]const u8, text: [:0]const u8, color: ?imgui.ImVec4) void {
    imgui.igIndent(0.0);
    defer imgui.igUnindent(0.0);
    imgui.igBeginGroup();
    defer imgui.igEndGroup();
    imgui.igText("%s:", label.ptr);
    imgui.igSameLine(0.0, -0.1);
    if (color) |col| {
        imgui.igTextColored(col, "%s", text.ptr);
    } else {
        imgui.igText("%s", text.ptr);
    }
}
