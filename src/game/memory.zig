const std = @import("std");
const os = @import("../os/module.zig");
const misc = @import("../misc/root.zig");
const memory = @import("../memory/root.zig");
const game = @import("root.zig");

pub const Memory = struct {
    player_1: memory.MultilevelPointer(game.Player, 4),
    player_2: memory.MultilevelPointer(game.Player, 4),

    const Self = @This();

    pub fn init() Self {
        return .{
            .player_1 = multilevelPointer("player_1", game.Player, 4, .{
                relativeOffset(u32, add(pattern(11, "4C 89 35 ?? ?? ?? ?? 41 88 5E 28"), 3)),
                0x0,
                0x30,
                0x0,
            }),
            .player_2 = multilevelPointer("player_2", game.Player, 4, .{
                relativeOffset(u32, add(pattern(11, "4C 89 35 ?? ?? ?? ?? 41 88 5E 28"), 3)),
                0x0,
                0x38,
                0x0,
            }),
        };
    }

    fn multilevelPointer(
        name: []const u8,
        comptime Type: type,
        comptime offsets_size: usize,
        offsets: [offsets_size]anyerror!usize,
    ) memory.MultilevelPointer(Type, offsets_size) {
        var last_error: ?anyerror = null;
        var mapped_offsets: [offsets_size]?usize = undefined;
        for (offsets, 0..) |offset, i| {
            if (offset) |o| {
                mapped_offsets[i] = o;
            } else |err| {
                last_error = err;
                mapped_offsets[i] = null;
            }
        }
        if (last_error) |err| {
            misc.errorContext().appendFmt(err, "Failed to resolve multilevel pointer: {s}", .{name});
            misc.errorContext().logError();
        }
        return memory.MultilevelPointer(Type, offsets_size){
            .offsets = mapped_offsets,
        };
    }

    fn pattern(comptime number_of_bytes: usize, comptime pattern_string: []const u8) !usize {
        const memory_pattern = memory.Pattern(number_of_bytes).new(pattern_string);
        const main_module = os.Module.getMain() catch |err| {
            misc.errorContext().append(err, "Failed to get main module.");
            return err;
        };
        const range = main_module.getMemoryRange() catch |err| {
            misc.errorContext().append(err, "Failed to get main module memory range.");
            return err;
        };
        const address = memory_pattern.findAddress(range) catch |err| {
            misc.errorContext().appendFmt(err, "Failed to find address of memory pattern: {}", .{memory_pattern});
            return err;
        };
        return address;
    }

    fn relativeOffset(comptime Offset: type, address: anyerror!usize) !usize {
        const addr = try address;
        const offset_address = memory.resolveRelativeOffset(Offset, addr) catch |err| {
            misc.errorContext().appendFmt(
                err,
                "Failed to resolve {s} relative memory offset at address: 0x{X}",
                .{ @typeName(Offset), addr },
            );
            return err;
        };
        return offset_address;
    }

    fn add(address: anyerror!usize, addition: usize) !usize {
        const addr = try address;
        const result = @addWithOverflow(addr, addition);
        if (result[1] == 1) {
            misc.errorContext().newFmt(
                error.Overflow,
                "Adding 0x{X} to address 0x{X} resulted in a overflow.",
                .{ addr, addition },
            );
            return error.Overflow;
        }
        return result[0];
    }
};
