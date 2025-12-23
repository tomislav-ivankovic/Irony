const std = @import("std");
const builtin = @import("builtin");
const sdk = @import("../../../sdk/root.zig");
const t8 = @import("root.zig");
const h = @import("../memory_helpers.zig");

pub const Memory = struct {
    player_1: sdk.memory.StructProxy(t8.Player),
    player_2: sdk.memory.StructProxy(t8.Player),
    camera: sdk.memory.Proxy(t8.Camera),
    functions: Functions,

    const Self = @This();
    pub const Functions = struct {
        tick: ?*const t8.TickFunction = null,
        updateCamera: ?*const t8.UpdateCameraFunction = null,
        decryptHealth: ?*const t8.DecryptHealthFunction = null,
    };

    const pattern_cache_file_name = "pattern_cache_t8.json";

    pub fn init(
        allocator: std.mem.Allocator,
        base_dir: ?*const sdk.misc.BaseDir,
        comptime game_hooks: type,
    ) Self {
        var cache = h.initPatternCache(allocator, base_dir, pattern_cache_file_name) catch |err| block: {
            sdk.misc.error_context.append("Failed to initialize pattern cache.", .{});
            sdk.misc.error_context.logError(err);
            break :block null;
        };
        defer if (cache) |*pattern_cache| {
            h.deinitPatternCache(pattern_cache, base_dir, pattern_cache_file_name);
        };
        const player_offsets = h.structOffsets(t8.Player, .{
            .is_picked_by_main_player = 0x9,
            .character_id = 0x168,
            .transform_matrix = 0x200,
            .floor_z = 0x354,
            .rotation = 0x376,
            .state_flags = 0x434,
            .animation_frame = h.deref(u32, h.add(8, h.pattern(
                &cache,
                "8B 81 ?? ?? 00 00 39 81 ?? ?? 00 00 0F 84 ?? ?? 00 00 48 C7 81",
            ))),
            .attack_damage = 0x504,
            .attack_type = h.deref(u32, h.add(2, h.pattern(
                &cache,
                "89 8E ?? ?? 00 00 48 8D 8E ?? ?? 00 00 E8 ?? ?? ?? ?? 48 8D 8E ?? ?? ?? ?? E8 ?? ?? ?? ?? 8B 86",
            ))),
            .animation_id = 0x548,
            .can_move = 0x5C8,
            .animation_total_frames = 0x5D4,
            .hit_outcome = 0x610,
            .invincible = 0x8F8, // TODO Probably incorrect because the same value does not work with T7 Akuma moves.
            .is_a_parry_move = 0xA2C,
            .power_crushing = 0xBEC,
            .airborne_flags = 0xF1C,
            .in_rage = 0xF51,
            .used_rage = 0xF88,
            .frames_since_round_start = 0x1590,
            .phase_flags = 0x1BC4,
            .heat_gauge = 0x2440,
            .used_heat = 0x2450,
            .in_heat = 0x2471,
            .input_side = 0x27BC,
            .input = 0x27E4,
            .hit_lines = 0x2850,
            .hurt_cylinders = 0x2C50,
            .collision_spheres = 0x3090,
            .health = 0x3810,
        });
        const self = Self{
            .player_1 = h.structProxy("player_1", t8.Player, .{
                h.relativeOffset(u32, h.add(3, h.pattern(&cache, "4C 89 35 ?? ?? ?? ?? 41 88 5E 28"))),
                0x30,
                0x0,
            }, player_offsets),
            .player_2 = h.structProxy("player_2", t8.Player, .{
                h.relativeOffset(u32, h.add(3, h.pattern(&cache, "4C 89 35 ?? ?? ?? ?? 41 88 5E 28"))),
                0x38,
                0x0,
            }, player_offsets),
            .camera = h.proxy("camera", t8.Camera, .{
                @intFromPtr(&game_hooks.last_camera_manager_address),
                0x22D0,
            }),
            .functions = .{
                .tick = h.functionPointer(
                    "tick",
                    t8.TickFunction,
                    h.pattern(&cache, "48 8B 0D ?? ?? ?? ?? 48 85 C9 74 0A 48 8B 01 0F 28 C8"),
                ),
                .updateCamera = h.functionPointer(
                    "updateCamera",
                    t8.UpdateCameraFunction,
                    h.pattern(&cache, "48 8B C4 48 89 58 18 55 56 57 48 81 EC 50"),
                ),
                .decryptHealth = h.functionPointer(
                    "decryptHealth",
                    t8.DecryptHealthFunction,
                    h.pattern(&cache, "48 89 5C 24 08 57 48 83 EC ?? 48 8D 79 08 48 8B D9 48 8B CF E8 ?? ?? ?? ?? 85 C0"),
                ),
            },
        };
        t8.conversion_globals.decryptHealth = self.functions.decryptHealth;
        return self;
    }
};
