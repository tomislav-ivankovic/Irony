const std = @import("std");
const builtin = @import("builtin");
const sdk = @import("../../../sdk/root.zig");
const t8 = @import("root.zig");

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
        var cache = initPatternCache(allocator, base_dir) catch |err| block: {
            sdk.misc.error_context.append("Failed to initialize pattern cache.", .{});
            sdk.misc.error_context.logError(err);
            break :block null;
        };
        defer if (cache) |*pattern_cache| {
            deinitPatternCache(pattern_cache, base_dir);
        };
        const player_offsets = structOffsets(t8.Player, .{
            .is_picked_by_main_player = 0x9,
            .character_id = 0x168,
            .transform_matrix = 0x200,
            .floor_z = 0x354,
            .rotation = 0x376,
            .state_flags = 0x434,
            .animation_frame = deref(u32, add(8, pattern(
                &cache,
                "8B 81 ?? ?? 00 00 39 81 ?? ?? 00 00 0F 84 ?? ?? 00 00 48 C7 81",
            ))),
            .attack_damage = 0x504,
            .attack_type = deref(u32, add(2, pattern(
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
            .player_1 = structProxy("player_1", t8.Player, .{
                relativeOffset(u32, add(3, pattern(&cache, "4C 89 35 ?? ?? ?? ?? 41 88 5E 28"))),
                0x30,
                0x0,
            }, player_offsets),
            .player_2 = structProxy("player_2", t8.Player, .{
                relativeOffset(u32, add(3, pattern(&cache, "4C 89 35 ?? ?? ?? ?? 41 88 5E 28"))),
                0x38,
                0x0,
            }, player_offsets),
            .camera = proxy("camera", t8.Camera, .{
                @intFromPtr(&game_hooks.last_camera_manager_address),
                0x22D0,
            }),
            .functions = .{
                .tick = functionPointer(
                    "tick_function",
                    t8.TickFunction,
                    pattern(&cache, "48 8B 0D ?? ?? ?? ?? 48 85 C9 74 0A 48 8B 01 0F 28 C8"),
                ),
                .updateCamera = functionPointer(
                    "update_camera_function",
                    t8.UpdateCameraFunction,
                    pattern(&cache, "48 8B C4 48 89 58 18 55 56 57 48 81 EC 50"),
                ),
                .decryptHealth = functionPointer(
                    "decrypt_health_function",
                    t8.DecryptHealthFunction,
                    pattern(&cache, "48 89 5C 24 08 57 48 83 EC ?? 48 8D 79 08 48 8B D9 48 8B CF E8 ?? ?? ?? ?? 85 C0"),
                ),
            },
        };
        t8.conversion_globals.decryptHealth = self.functions.decryptHealth;
        return self;
    }

    fn initPatternCache(allocator: std.mem.Allocator, base_dir: ?*const sdk.misc.BaseDir) !sdk.memory.PatternCache {
        const main_module = sdk.os.Module.getMain() catch |err| {
            sdk.misc.error_context.append("Failed to get main module.", .{});
            return err;
        };
        const range = main_module.getMemoryRange() catch |err| {
            sdk.misc.error_context.append("Failed to get main module memory range.", .{});
            return err;
        };
        var cache = sdk.memory.PatternCache.init(allocator, range);
        if (base_dir) |dir| {
            loadPatternCache(&cache, dir) catch |err| {
                sdk.misc.error_context.append("Failed to load memory pattern cache. Using empty cache.", .{});
                sdk.misc.error_context.logWarning(err);
            };
        }
        return cache;
    }

    fn deinitPatternCache(cache: *sdk.memory.PatternCache, base_dir: ?*const sdk.misc.BaseDir) void {
        if (base_dir) |dir| {
            savePatternCache(cache, dir) catch |err| {
                sdk.misc.error_context.append("Failed to save memory pattern cache.", .{});
                sdk.misc.error_context.logWarning(err);
            };
        }
        cache.deinit();
    }

    fn loadPatternCache(cache: *sdk.memory.PatternCache, base_dir: *const sdk.misc.BaseDir) !void {
        var buffer: [sdk.os.max_file_path_length]u8 = undefined;
        const file_path = base_dir.getPath(&buffer, pattern_cache_file_name) catch |err| {
            sdk.misc.error_context.append("Failed to construct file path.", .{});
            return err;
        };

        const executable_timestamp = sdk.os.getExecutableTimestamp() catch |err| {
            sdk.misc.error_context.append("Failed to get executable timestamp.", .{});
            return err;
        };

        return cache.load(file_path, executable_timestamp);
    }

    fn savePatternCache(cache: *sdk.memory.PatternCache, base_dir: *const sdk.misc.BaseDir) !void {
        var buffer: [sdk.os.max_file_path_length]u8 = undefined;
        const file_path = base_dir.getPath(&buffer, pattern_cache_file_name) catch |err| {
            sdk.misc.error_context.append("Failed to construct file path.", .{});
            return err;
        };

        const executable_timestamp = sdk.os.getExecutableTimestamp() catch |err| {
            sdk.misc.error_context.append("Failed to get executable timestamp.", .{});
            return err;
        };

        return cache.save(file_path, executable_timestamp);
    }
};

fn structOffsets(
    comptime Struct: type,
    offsets: sdk.misc.FieldMap(Struct, anyerror!usize, null),
) sdk.misc.FieldMap(Struct, ?usize, null) {
    var last_error: ?struct { err: anyerror, field_name: []const u8 } = null;
    var mapped_offsets: sdk.misc.FieldMap(Struct, ?usize, null) = undefined;
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
            sdk.misc.error_context.append("Failed to resolve offset for field: {s}", .{err.field_name});
            sdk.misc.error_context.append("Failed to resolve field offsets for struct: {s}", .{@typeName(Struct)});
            sdk.misc.error_context.logError(err.err);
        }
    }
    return mapped_offsets;
}

fn proxy(
    name: []const u8,
    comptime Type: type,
    offsets: anytype,
) sdk.memory.Proxy(Type) {
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
            sdk.misc.error_context.append("Failed to resolve proxy: {s}", .{name});
            sdk.misc.error_context.logError(err);
        }
    }
    return .fromArray(mapped_offsets);
}

fn structProxy(
    name: []const u8,
    comptime Struct: type,
    base_offsets: anytype,
    field_offsets: sdk.misc.FieldMap(Struct, ?usize, null),
) sdk.memory.StructProxy(Struct) {
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
            sdk.misc.error_context.append("Failed to resolve struct proxy: {s}", .{name});
            sdk.misc.error_context.logError(err);
        }
    }
    return .{
        .base_trail = .fromArray(mapped_offsets),
        .field_offsets = field_offsets,
    };
}

fn functionPointer(
    name: []const u8,
    comptime Function: type,
    address: anyerror!usize,
) ?*const Function {
    const addr = address catch |err| {
        if (!builtin.is_test) {
            sdk.misc.error_context.append("Failed to resolve function pointer: {s}", .{name});
            sdk.misc.error_context.logError(err);
        }
        return null;
    };
    if (!sdk.os.isMemoryReadable(addr, 6)) {
        if (!builtin.is_test) {
            sdk.misc.error_context.new("The memory address is not readable: 0x{X}", .{addr});
            sdk.misc.error_context.append("Failed to resolve function pointer: {s}", .{name});
            sdk.misc.error_context.logError(error.NotReadable);
        }
        return null;
    }
    return @ptrFromInt(addr);
}

fn pattern(pattern_cache: *?sdk.memory.PatternCache, comptime pattern_string: []const u8) !usize {
    const cache = if (pattern_cache.*) |*c| c else {
        sdk.misc.error_context.new("No memory pattern cache to find the memory pattern in.", .{});
        return error.NoPatternCache;
    };
    const memory_pattern = sdk.memory.Pattern.fromComptime(pattern_string);
    const address = cache.findAddress(&memory_pattern) catch |err| {
        sdk.misc.error_context.append("Failed to find address of memory pattern: {f}", .{memory_pattern});
        return err;
    };
    return address;
}

fn deref(comptime Type: type, address: anyerror!usize) !usize {
    if (Type != u8 and Type != u16 and Type != u32 and Type != u64) {
        @compileError("Unsupported deref type: " ++ @typeName(Type));
    }
    const addr = try address;
    const value = sdk.memory.dereferenceMisaligned(Type, addr) catch |err| {
        sdk.misc.error_context.append("Failed to dereference {s} on memory address: 0x{X}", .{ @typeName(Type), addr });
        return err;
    };
    return @intCast(value);
}

fn relativeOffset(comptime Offset: type, address: anyerror!usize) !usize {
    const addr = try address;
    const offset_address = sdk.memory.resolveRelativeOffset(Offset, addr) catch |err| {
        sdk.misc.error_context.append(
            "Failed to resolve {s} relative memory offset at address: 0x{X}",
            .{ @typeName(Offset), addr },
        );
        return err;
    };
    return offset_address;
}

fn add(comptime addition: comptime_int, address: anyerror!usize) !usize {
    const addr = try address;
    const result = if (addition >= 0) @addWithOverflow(addr, addition) else @subWithOverflow(addr, -addition);
    if (result[1] == 1) {
        sdk.misc.error_context.new("Adding 0x{X} to address 0x{X} resulted in a overflow.", .{ addr, addition });
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
    sdk.misc.error_context.new("Test error.", .{});
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
    sdk.misc.error_context.new("Test error.", .{});
    const struct_proxy = structProxy(
        "pointer",
        Struct,
        .{ 1, error.Test, 2, error.Test, 3, error.Test },
        .{ .field_1 = 4, .field_2 = 5 },
    );
    try testing.expectEqualSlices(?usize, &.{ 1, null, 2, null, 3, null }, struct_proxy.base_trail.getOffsets());
}

test "functionPointer should return a function pointer when address is valid" {
    const function = struct {
        fn call(a: i32, b: i32) i32 {
            return a + b;
        }
    }.call;
    const function_pointer = functionPointer("function", @TypeOf(function), @intFromPtr(&function));
    try testing.expectEqual(function, function_pointer);
}

test "functionPointer should return null when address is error" {
    const function_pointer = functionPointer("function", fn (i32, i32) i32, error.Test);
    try testing.expectEqual(null, function_pointer);
}

test "functionPointer should return null when address is not readable" {
    const function_pointer = functionPointer("function", fn (i32, i32) i32, std.math.maxInt(usize));
    try testing.expectEqual(null, function_pointer);
}

test "pattern should return correct value when pattern exists" {
    const data = [_]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9 };
    const range = sdk.memory.Range.fromPointer(&data);
    var cache: ?sdk.memory.PatternCache = sdk.memory.PatternCache.init(testing.allocator, range);
    defer if (cache) |*c| c.deinit();
    try testing.expectEqual(@intFromPtr(&data[4]), pattern(&cache, "04 ?? ?? 07"));
}

test "pattern should error when no cache" {
    var cache: ?sdk.memory.PatternCache = null;
    try testing.expectError(error.NoPatternCache, pattern(&cache, "04 ?? ?? 07"));
}

test "pattern should error when pattern does not exist" {
    const data = [_]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9 };
    const range = sdk.memory.Range.fromPointer(&data);
    var cache: ?sdk.memory.PatternCache = sdk.memory.PatternCache.init(testing.allocator, range);
    defer if (cache) |*c| c.deinit();
    try testing.expectError(error.NotFound, pattern(&cache, "05 ?? ?? 02"));
}

test "deref should return correct value when memory is readable" {
    const value: u64 = 0xFF00;
    const address = @intFromPtr(&value) + 1;
    try testing.expectEqual(0xFF, deref(u32, address));
}

test "deref should return error when error argument" {
    try testing.expectError(error.Test, deref(u64, error.Test));
}

test "deref should return error when memory is not readable" {
    try testing.expectError(error.NotReadable, deref(u64, 0));
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

test "add should return correct value when no overflow and positive argument" {
    try testing.expectEqual(3, add(1, 2));
    try testing.expectEqual(3, add(-2, 5));
}

test "add should error when error argument" {
    try testing.expectError(error.Test, add(1, error.Test));
}

test "add should error when address space overflows" {
    try testing.expectError(error.Overflow, add(1, std.math.maxInt(usize)));
    try testing.expectError(error.Overflow, add(-1, 0));
}
