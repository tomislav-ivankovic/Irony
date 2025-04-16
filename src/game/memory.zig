const std = @import("std");
const os = @import("../os/module.zig");
const misc = @import("../misc/root.zig");
const memory = @import("../memory/root.zig");
const game = @import("root.zig");

pub const Memory = struct {
    player_1: memory.MultilevelPointer(game.Player, 4),
    player_2: memory.MultilevelPointer(game.Player, 4),
    selected_side: memory.MultilevelPointer(u8, 7),

    const Self = @This();

    pub fn find() Self {
        return .{
            .player_1 = pointer(game.Player, 4, .{
                offset(u32, pattern(11, "4C 89 35 ?? ?? ?? ?? 41 88 5E 28") +| 3),
                0x0,
                0x30,
                0x0,
            }),
            .player_2 = pointer(game.Player, 4, .{
                offset(u32, pattern(11, "4C 89 35 ?? ?? ?? ?? 41 88 5E 28") +| 3),
                0x0,
                0x38,
                0x0,
            }),
            .selected_side = pointer(u8, 7, .{
                offset(u32, pattern(30, "48 8B 35 ?? ?? ?? ?? 48 85 F6 0F 84 ?? ?? ?? ?? 48 8B CE E8 ?? ?? ?? ?? 48 8B C8 48 8B 10") +| 3),
                0x0,
                0x60,
                0x58,
                0x18,
                0x8,
                0x4,
            }),
        };
    }

    fn pointer(
        comptime Type: type,
        comptime offsets_size: usize,
        offsets: [offsets_size]usize,
    ) memory.MultilevelPointer(Type, offsets_size) {
        return memory.MultilevelPointer(Type, offsets_size){
            .offsets = offsets,
        };
    }

    fn offset(comptime Offset: type, address: usize) usize {
        const offset_address = memory.resolveRelativeOffset(Offset, address) catch |err| {
            misc.errorContext().appendFmt(
                err,
                "Failed to resolve {s} memory offset at address: 0x{X}",
                .{ @typeName(Offset), address },
            );
            return std.math.maxInt(usize);
        };
        return offset_address;
    }

    fn pattern(
        comptime number_of_bytes: usize,
        comptime pattern_string: []const u8,
    ) usize {
        const memory_pattern = memory.Pattern(number_of_bytes).new(pattern_string);
        const main_module = os.Module.getMain() catch |err| {
            misc.errorContext().append(err, "Failed to get main module.");
            misc.errorContext().appendFmt(err, "Failed to find address of memory pattern: {}", .{memory_pattern});
            misc.errorContext().logError();
            return std.math.maxInt(usize);
        };
        const range = main_module.getMemoryRange() catch |err| {
            misc.errorContext().append(err, "Failed to get main module memory range.");
            misc.errorContext().appendFmt(err, "Failed to find address of memory pattern: {}", .{memory_pattern});
            misc.errorContext().logError();
            return std.math.maxInt(usize);
        };
        const address = memory_pattern.findAddress(range) catch |err| {
            misc.errorContext().appendFmt(err, "Failed to find address of memory pattern: {}", .{memory_pattern});
            misc.errorContext().logError();
            return std.math.maxInt(usize);
        };
        return address;
    }
};
