const std = @import("std");
const builtin = @import("builtin");
const sdk = @import("../../../sdk/root.zig");
const t7 = @import("root.zig");
const h = @import("../memory_helpers.zig");

pub const Memory = struct {
    player_1: sdk.memory.StructProxy(t7.Player),
    player_2: sdk.memory.StructProxy(t7.Player),
    world_to_clip_matrix: sdk.memory.Proxy(sdk.math.Mat4),
    functions: Functions,

    const Self = @This();
    pub const Functions = struct {
        tick: ?*const t7.TickFunction = null,
    };

    const pattern_cache_file_name = "pattern_cache_t7.json";

    pub fn init(
        allocator: std.mem.Allocator,
        base_dir: ?*const sdk.misc.BaseDir,
        comptime game_hooks: type,
    ) Self {
        _ = game_hooks;
        var cache = h.initPatternCache(allocator, base_dir, pattern_cache_file_name) catch |err| block: {
            sdk.misc.error_context.append("Failed to initialize pattern cache.", .{});
            sdk.misc.error_context.logError(err);
            break :block null;
        };
        defer if (cache) |*pattern_cache| {
            h.deinitPatternCache(pattern_cache, base_dir, pattern_cache_file_name);
        };
        const player_offsets = h.structOffsets(t7.Player, .{
            .is_picked_by_main_player = 0x9,
            .character_id = 0xD8,
            .transform_matrix = 0x130,
            .floor_z = 0x1B0,
            .rotation = 0x1CA,
            .animation_frame = 0x1D4,
            .state_flags = 0x264,
            .attack_damage = 0x324,
            .attack_type = 0x328,
            .animation_id = 0x350,
            .can_move = 0x390,
            .animation_total_frames = 0x39C,
            .hit_outcome = 0x3D8,
            .invincible = 0x630, // TODO Find a better value that works with Akuma invincible moves.
            .power_crushing = 0x6C0,
            .airborne_flags = 0x8D8,
            .frames_since_round_start = 0x900,
            .in_rage = 0xC00,
            .input_side = 0xDE4,
            .input = 0xE0C,
            .hit_lines = 0xE50,
            .hurt_cylinders = 0xF10,
            .collision_spheres = 0x10D0,
            .health = 0x14E8,
        });
        return .{
            .player_1 = h.structProxy("player_1", t7.Player, .{
                h.relativeOffset(u32, h.add(0x3, h.pattern(&cache, "48 8B 15 ?? ?? ?? ?? 44 8B C3"))),
                0x0,
            }, player_offsets),
            .player_2 = h.structProxy("player_2", t7.Player, .{
                h.relativeOffset(u32, h.add(0xD, h.pattern(&cache, "48 8B 15 ?? ?? ?? ?? 44 8B C3"))),
                0x0,
            }, player_offsets),
            .world_to_clip_matrix = h.proxy("world_to_clip_matrix", sdk.math.Mat4, .{
                h.relativeOffset(u32, h.add(
                    0x7,
                    h.pattern(&cache, "48 83 EC 28 48 8B 05 ?? ?? ?? ?? 48 85 C0 0F 85 AD 00 00 00"),
                )),
                0x70,
                0xE0,
                0x260,
            }),
            .functions = .{
                .tick = h.functionPointer(
                    "tick",
                    t7.TickFunction,
                    h.pattern(&cache, "4C 8B DC 55 41 57 49 8D 6B A1 48 81 EC E8"),
                ),
            },
        };
    }
};
