const std = @import("std");
const builtin = @import("builtin");
const os = @import("../os/module.zig");
const misc = @import("../misc/root.zig");
const memory = @import("../memory/root.zig");
const game = @import("root.zig");

pub const Memory = struct {
    player_1: memory.StructProxy(game.Player),
    player_2: memory.StructProxy(game.Player),

    const Self = @This();

    pub fn init() Self {
        const range = findMainModuleMemoryRange() catch |err| block: {
            misc.error_context.append("Failed to get main module memory range.", .{});
            misc.error_context.logError(err);
            break :block null;
        };
        const player_offsets = structOffsets(game.Player, .{
            // TODO Add runtime known struct offsets based on memory patterns here.
            .player_id = 0x0004,
            .is_picked_by_main_player = 0x0009,
            .character_id = 0x0168,
            .position_x_base = 0x0170,
            .position_y_base = 0x0178,
            .position_y_relative_to_floor = 0x0184,
            .position_x_relative_to_floor = 0x018C,
            .position_z_relative_to_floor = 0x01A4,
            .location = 0x0230,
            .current_frame_number = 0x0390,
            .current_frame_float = 0x03BC,
            .current_move_pointer = 0x03D8,
            .current_move_pointer_2 = 0x03E0,
            .previous_move_pointer = 0x03E8,
            .attack_damage = 0x0504,
            .attack_type = 0x0510,
            .current_move_id = 0x0548,
            .can_move = 0x05C8,
            .current_move_total_frames = 0x05D4,
            .hit_outcome = 0x0610,
            .already_attacked = 0x066C,
            .already_attacked_2 = 0x0674,
            .stun = 0x0774,
            .cancel_flags = 0x0C80,
            .rage = 0x0D71,
            .floor_number_1 = 0x1770,
            .floor_number_2 = 0x1774,
            .floor_number_3 = 0x1778,
            .frame_data_flags = 0x19E0,
            .next_move_pointer = 0x1F30,
            .next_move_id = 0x1F4C,
            .reaction_to_have = 0x1F50,
            .attack_input = 0x1F70,
            .direction_input = 0x1F74,
            .used_heat = 0x2110,
            .input = 0x2494,
            .health = 0x2EE4,
        });
        return .{
            .player_1 = structProxy("player_1", game.Player, .{
                relativeOffset(u32, add(3, pattern(range, "4C 89 35 ?? ?? ?? ?? 41 88 5E 28"))),
                0x30,
                0x0,
            }, player_offsets),
            .player_2 = structProxy("player_2", game.Player, .{
                relativeOffset(u32, add(3, pattern(range, "4C 89 35 ?? ?? ?? ?? 41 88 5E 28"))),
                0x38,
                0x0,
            }, player_offsets),
        };
    }

    fn findMainModuleMemoryRange() !memory.Range {
        const main_module = os.Module.getMain() catch |err| {
            misc.error_context.append("Failed to get main module.", .{});
            return err;
        };
        return main_module.getMemoryRange();
    }
};

fn structOffsets(
    comptime Struct: type,
    offsets: misc.FieldMap(Struct, anyerror!usize),
) misc.FieldMap(Struct, ?usize) {
    var last_error: ?struct { err: anyerror, field_name: []const u8 } = null;
    var mapped_offsets: misc.FieldMap(Struct, ?usize) = undefined;
    inline for (@typeInfo(Struct).@"struct".fields) |*field| {
        const offset = @field(offsets, field.name);
        if (offset) |o| {
            @field(mapped_offsets, field.name) = o;
        } else |err| {
            last_error = .{ .err = err, .field_name = field.name };
            @field(mapped_offsets, field.name) = null;
        }
    }
    if (last_error) |err| {
        if (!builtin.is_test) {
            misc.error_context.append("Failed to resolve offset for field: {s}", .{err.field_name});
            misc.error_context.append("Failed to resolve field offsets for struct: {s}", .{@typeName(Struct)});
            misc.error_context.logError(err.err);
        }
    }
    return mapped_offsets;
}

fn proxy(
    name: []const u8,
    comptime Type: type,
    offsets: anytype,
) memory.Proxy(Type) {
    if (@typeInfo(@TypeOf(offsets)) != .array) {
        const coerced: [offsets.len]anyerror!usize = offsets;
        return proxy(name, Type, coerced);
    }
    var last_error: ?anyerror = null;
    var mapped_offsets: [offsets.len]?usize = undefined;
    for (offsets, 0..) |offset, i| {
        if (offset) |o| {
            mapped_offsets[i] = o;
        } else |err| {
            last_error = err;
            mapped_offsets[i] = null;
        }
    }
    if (last_error) |err| {
        if (!builtin.is_test) {
            misc.error_context.append("Failed to resolve proxy: {s}", .{name});
            misc.error_context.logError(err);
        }
    }
    return .fromArray(mapped_offsets);
}

fn structProxy(
    name: []const u8,
    comptime Struct: type,
    base_offsets: anytype,
    field_offsets: misc.FieldMap(Struct, ?usize),
) memory.StructProxy(Struct) {
    if (@typeInfo(@TypeOf(base_offsets)) != .array) {
        const coerced: [base_offsets.len]anyerror!usize = base_offsets;
        return structProxy(name, Struct, coerced, field_offsets);
    }
    var last_error: ?anyerror = null;
    var mapped_offsets: [base_offsets.len]?usize = undefined;
    for (base_offsets, 0..) |offset, i| {
        if (offset) |o| {
            mapped_offsets[i] = o;
        } else |err| {
            last_error = err;
            mapped_offsets[i] = null;
        }
    }
    if (last_error) |err| {
        if (!builtin.is_test) {
            misc.error_context.append("Failed to resolve struct proxy: {s}", .{name});
            misc.error_context.logError(err);
        }
    }
    return .{
        .base_trail = .fromArray(mapped_offsets),
        .field_offsets = field_offsets,
    };
}

fn pattern(memory_range: ?memory.Range, comptime pattern_string: []const u8) !usize {
    const range = memory_range orelse {
        misc.error_context.new("No memory range to find the memory pattern in.", .{});
        return error.NoMemoryRange;
    };
    const memory_pattern = memory.Pattern.fromComptime(pattern_string);
    const address = memory_pattern.findAddress(range) catch |err| {
        misc.error_context.append("Failed to find address of memory pattern: {}", .{memory_pattern});
        return err;
    };
    return address;
}

fn relativeOffset(comptime Offset: type, address: anyerror!usize) !usize {
    const addr = try address;
    const offset_address = memory.resolveRelativeOffset(Offset, addr) catch |err| {
        misc.error_context.append(
            "Failed to resolve {s} relative memory offset at address: 0x{X}",
            .{ @typeName(Offset), addr },
        );
        return err;
    };
    return offset_address;
}

fn add(addition: usize, address: anyerror!usize) !usize {
    const addr = try address;
    const result = @addWithOverflow(addr, addition);
    if (result[1] == 1) {
        misc.error_context.new("Adding 0x{X} to address 0x{X} resulted in a overflow.", .{ addr, addition });
        return error.Overflow;
    }
    return result[0];
}

const testing = std.testing;

test "structOffsets should map errors to null values" {
    const Struct = struct {
        field_1: u8,
        field_2: u16,
        field_3: u32,
        field_4: u64,
    };
    const offsets = structOffsets(Struct, .{
        .field_1 = 1,
        .field_2 = error.Test,
        .field_3 = 2,
        .field_4 = error.Test,
    });
    try testing.expectEqual(1, offsets.field_1);
    try testing.expectEqual(null, offsets.field_2);
    try testing.expectEqual(2, offsets.field_3);
    try testing.expectEqual(null, offsets.field_4);
}

test "proxy should construct a proxy from offsets" {
    const byte_proxy = proxy("byte_proxy", u8, .{ 1, 2, 3 });
    try testing.expectEqualSlices(?usize, &.{ 1, 2, 3 }, byte_proxy.trail.getOffsets());
}

test "proxy should map errors to null values" {
    misc.error_context.new("Test error.", .{});
    const byte_proxy = proxy("byte_proxy", u8, .{ 1, error.Test, 2, error.Test, 3, error.Test });
    try testing.expectEqualSlices(?usize, &.{ 1, null, 2, null, 3, null }, byte_proxy.trail.getOffsets());
}

test "structProxy should construct a proxy from offsets" {
    const Struct = struct { field_1: u8, field_2: u16 };
    const struct_proxy = structProxy(
        "pointer",
        Struct,
        .{ 1, 2, 3 },
        .{ .field_1 = 4, .field_2 = 5 },
    );
    try testing.expectEqualSlices(?usize, &.{ 1, 2, 3 }, struct_proxy.base_trail.getOffsets());
    try testing.expectEqual(4, struct_proxy.field_offsets.field_1);
    try testing.expectEqual(5, struct_proxy.field_offsets.field_2);
}

test "structProxy should map errors to null values in base offsets" {
    const Struct = struct { field_1: u8, field_2: u16 };
    misc.error_context.new("Test error.", .{});
    const struct_proxy = structProxy(
        "pointer",
        Struct,
        .{ 1, error.Test, 2, error.Test, 3, error.Test },
        .{ .field_1 = 4, .field_2 = 5 },
    );
    try testing.expectEqualSlices(?usize, &.{ 1, null, 2, null, 3, null }, struct_proxy.base_trail.getOffsets());
}

test "pattern should return correct value when pattern exists" {
    const data = [_]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9 };
    const range = memory.Range.fromPointer(&data);
    try testing.expectEqual(@intFromPtr(&data[4]), pattern(range, "04 ?? ?? 07"));
}

test "pattern should error when no memory range" {
    try testing.expectError(error.NoMemoryRange, pattern(null, "04 ?? ?? 07"));
}

test "pattern should error when pattern does not exist" {
    const data = [_]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9 };
    const range = memory.Range.fromPointer(&data);
    try testing.expectError(error.NotFound, pattern(range, "05 ?? ?? 02"));
}

test "relativeOffset should return correct value when good offset address" {
    const data = [_]u8{ 3, 1, 2, 3, 4 };
    const offset_address = relativeOffset(u8, @intFromPtr(&data[0]));
    try testing.expectEqual(@intFromPtr(&data[data.len - 1]), offset_address);
}

test "relativeOffset should error when error argument" {
    try testing.expectError(error.Test, relativeOffset(u8, error.Test));
}

test "relativeOffset should error when bad offset address" {
    try testing.expectError(error.NotReadable, relativeOffset(u8, std.math.maxInt(usize)));
}

test "add should return correct value when no overflow" {
    try testing.expectEqual(3, add(1, 2));
}

test "add should error when error argument" {
    try testing.expectError(error.Test, add(1, error.Test));
}

test "add should error when address space overflows" {
    try testing.expectError(error.Overflow, add(1, std.math.maxInt(usize)));
}
