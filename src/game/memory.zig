const std = @import("std");
const builtin = @import("builtin");
const os = @import("../os/module.zig");
const misc = @import("../misc/root.zig");
const memory = @import("../memory/root.zig");
const game = @import("root.zig");

pub const Memory = struct {
    player_1: memory.PointerTrail(game.Player),
    player_2: memory.PointerTrail(game.Player),

    const Self = @This();

    pub fn init() Self {
        const r = findMainModuleMemoryRange() catch |err| block: {
            misc.error_context.append("Failed to get main module memory range.", .{});
            misc.error_context.logError(err);
            break :block null;
        };
        return .{
            .player_1 = trail("player_1", game.Player, .{
                relativeOffset(u32, add(3, pattern(r, "4C 89 35 ?? ?? ?? ?? 41 88 5E 28"))),
                0x0,
                0x30,
                0x0,
            }),
            .player_2 = trail("player_2", game.Player, .{
                relativeOffset(u32, add(3, pattern(r, "4C 89 35 ?? ?? ?? ?? 41 88 5E 28"))),
                0x0,
                0x38,
                0x0,
            }),
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

fn trail(
    name: []const u8,
    comptime Type: type,
    offsets: anytype,
) memory.PointerTrail(Type) {
    if (@typeInfo(@TypeOf(offsets)) != .array) {
        const coerced: [offsets.len]anyerror!usize = offsets;
        return trail(name, Type, coerced);
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
            misc.error_context.append("Failed to resolve pointer trail: {s}", .{name});
            misc.error_context.logError(err);
        }
    }
    return memory.PointerTrail(Type).fromArray(mapped_offsets);
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

test "trail should construct a pointer trail from array" {
    const pointer = trail("pointer", u8, .{ 1, 2, 3 });
    try testing.expectEqualSlices(?usize, &.{ 1, 2, 3 }, pointer.getOffsets());
}

test "trail should map errors to null values" {
    misc.error_context.new("Test error.", .{});
    const pointer = trail("pointer", u8, .{ 1, error.Test, 2, error.Test, 3, error.Test });
    try testing.expectEqualSlices(?usize, &.{ 1, null, 2, null, 3, null }, pointer.getOffsets());
}

test "pattern should return correct value when pattern exisits" {
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
