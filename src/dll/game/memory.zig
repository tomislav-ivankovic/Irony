const std = @import("std");
const builtin = @import("builtin");
const build_info = @import("build_info");
const sdk = @import("../../sdk/root.zig");
const game = @import("root.zig");

pub fn Memory(comptime game_id: build_info.Game) type {
    return struct {
        game_version: Pointer(game.Version(game_id)),
        player_1: Proxy(game.Player(game_id)),
        player_2: Proxy(game.Player(game_id)),
        main_player_info: Proxy(game.PlayerInfo(game_id)),
        secondary_player_info: Proxy(game.PlayerInfo(game_id)),
        match: Pointer(game.Match(game_id)),
        ruleset: Pointer(game.Ruleset(game_id)),
        cancel_requirements: Pointer(game.CancelRequirements),
        replay_mode: Proxy(game.ReplayMode),
        depth_buffer: Proxy(game.DepthBuffer(game_id)),
        camera_manager: Pointer(game.CameraManager(game_id)) = .fromPointer(null),
        walls: Array(max_walls, Pointer(game.Wall(game_id)), .fromPointer(null), false) = .empty,
        floors: Array(max_floors, Pointer(game.Floor(game_id)), .fromPointer(null), false) = .empty,
        player_starts: Array(max_player_starts, Pointer(game.PlayerStart(game_id)), .fromPointer(null), false) = .empty,
        functions: Functions,
        unreal_classes: UnrealClasses = .{},

        const Self = @This();
        const Proxy = sdk.memory.Proxy;
        const Pointer = sdk.memory.Pointer;
        const Array = sdk.misc.BoundedArray;
        pub const Functions = switch (game_id) {
            .t7 => struct {
                tick: ?*const game.TickFunction(.t7) = null,
                processCancelRequirement: ?*const game.ProcessCancelRequirementFunction = null,
                unrealFree: ?*const game.UnrealFreeFunction = null,
                findUnrealClass: ?*const game.FindUnrealClassFunction = null,
                findUnrealObjectsOfClass: ?*const game.FindUnrealObjectsOfClassFunction = null,
            },
            .t8 => struct {
                tick: ?*const game.TickFunction(.t8) = null,
                processCancelRequirement: ?*const game.ProcessCancelRequirementFunction = null,
                unrealFree: ?*const game.UnrealFreeFunction = null,
                findUnrealClass: ?*const game.FindUnrealClassFunction = null,
                findUnrealObjectsOfClass: ?*const game.FindUnrealObjectsOfClassFunction = null,
                setRenderTargets: ?*const game.SetRenderTargetsFunction = null,
                getGlobalsMap: ?*const game.GetGlobalsMapFunction = null,
                findGlobalAddress: ?*const game.FindGlobalAddressFunction = null,
                isReplay: ?*const game.IsReplayFunction = null,
            },
        };
        pub const UnrealClasses = struct {
            camera_manager: ?*const game.UnrealClass = null,
            wall: ?*const game.UnrealClass = null,
            photo_mode_wall: ?*const game.UnrealClass = null,
            floor: ?*const game.UnrealClass = null,
            player_start: ?*const game.UnrealClass = null,
        };

        const pattern_cache_file_name = "pattern_cache_" ++ @tagName(game_id) ++ ".json";
        pub const max_walls = 256;
        pub const max_floors = 16;
        pub const max_player_starts = 32;

        pub fn init(
            allocator: std.mem.Allocator,
            base_dir: ?*const sdk.misc.BaseDir,
            comptime game_hooks: type,
        ) Self {
            var cache = initPatternCache(allocator, base_dir, pattern_cache_file_name) catch |err| block: {
                sdk.misc.error_context.append("Failed to initialize pattern cache.", .{});
                sdk.misc.error_context.logError(err);
                break :block null;
            };
            defer if (cache) |*pattern_cache| {
                deinitPatternCache(pattern_cache, base_dir, pattern_cache_file_name);
            };
            return switch (game_id) {
                .t7 => t7Init(&cache, game_hooks),
                .t8 => t8Init(&cache, game_hooks),
            };
        }

        fn t7Init(cache: *?sdk.memory.PatternCache, comptime game_hooks: type) Self {
            return .{
                .game_version = .fromPointer("5.10" ++ .{0}),
                .player_1 = proxy("player_1", game.Player(.t7), .{
                    relativeOffset(i32, add(0x3, pattern(cache, "48 8B 15 ?? ?? ?? ?? 44 8B C3"))),
                    0x0,
                }),
                .player_2 = proxy("player_2", game.Player(.t7), .{
                    relativeOffset(i32, add(0xD, pattern(cache, "48 8B 15 ?? ?? ?? ?? 44 8B C3"))),
                    0x0,
                }),
                .main_player_info = proxy("main_player_info", game.PlayerInfo(.t7), .{
                    relativeOffset(i32, add(0x9, pattern(
                        cache,
                        "40 53 48 83 EC 20 48 8B 1D ?? ?? ?? ?? 48 85 DB 74 ?? 48 83 3D ?? ?? ?? ?? 00",
                    ))),
                    0x0,
                    0x0,
                    0x0,
                }),
                .secondary_player_info = proxy("secondary_player_info", game.PlayerInfo(.t7), .{
                    relativeOffset(i32, add(0x9, pattern(
                        cache,
                        "40 53 48 83 EC 20 48 8B 1D ?? ?? ?? ?? 48 85 DB 74 ?? 48 83 3D ?? ?? ?? ?? 00",
                    ))),
                    0x0,
                    0x8,
                    0x0,
                }),
                .match = pointer(
                    "match",
                    game.Match(.t7),
                    relativeOffset(i32, add(0x3, pattern(
                        cache,
                        "48 89 1D ?? ?? ?? ?? 48 89 5C 24 20 E8 ?? ?? ?? ?? 48 8B 74 24 48",
                    ))),
                ),
                .ruleset = pointer(
                    "ruleset",
                    game.Ruleset(.t7),
                    relativeOffset(i32, add(0x2, pattern(cache, "8B 05 ?? ?? ?? ?? 83 C0 9C"))),
                ),
                .cancel_requirements = pointer(
                    "cancel_requirements",
                    game.CancelRequirements,
                    @intFromPtr(&game_hooks.cancel_requirements),
                ),
                .replay_mode = proxy("replay_mode", game.ReplayMode, .{
                    add(0x1, relativeOffset(i32, add(0x3, pattern(
                        cache,
                        "48 83 3D ?? ?? ?? ?? 00 75 ?? B9 40 00 00 00",
                    )))),
                    0x38,
                    0x58,
                }),
                .depth_buffer = proxy("depth_buffer", game.DepthBuffer(.t7), .{
                    relativeOffset(i32, add(0x3, pattern(
                        cache,
                        "4C 8B 05 ?? ?? ?? ?? 48 8D 59 08",
                    ))),
                    0x8,
                    0x98,
                    0x0,
                }),
                .functions = .{
                    .tick = functionPointer(
                        "tick",
                        game.TickFunction(.t7),
                        pattern(cache, "48 83 EC 58 84 C9"),
                    ),
                    .processCancelRequirement = functionPointer(
                        "processCancelRequirement",
                        game.ProcessCancelRequirementFunction,
                        pattern(cache, "40 53 56 57 41 56 48 81 EC B8 00 00 00"),
                    ),
                    .unrealFree = functionPointer(
                        "unrealFree",
                        game.UnrealFreeFunction,
                        pattern(cache, "48 85 C9 74 ?? 53 48 83 EC 20 48 8B D9 48 8B 0D"),
                    ),
                    .findUnrealClass = functionPointer(
                        "findUnrealClass",
                        game.FindUnrealClassFunction,
                        relativeOffset(i32, add(0x8, pattern(cache, "45 33 C0 48 83 C9 FF E8"))),
                    ),
                    .findUnrealObjectsOfClass = functionPointer(
                        "findUnrealObjectsOfClass",
                        game.FindUnrealObjectsOfClassFunction,
                        pattern(
                            cache,
                            "48 89 5C 24 18 48 89 74 24 20 55 57 41 54 41 56 41 57 48 8D 6C 24 D1 48 81 EC A0 00 00 00",
                        ),
                    ),
                },
            };
        }

        fn t8Init(cache: *?sdk.memory.PatternCache, comptime game_hooks: type) Self {
            return .{
                .game_version = pointer(
                    "game_version",
                    game.Version(.t8),
                    relativeOffset(i32, add(0x3, pattern(
                        cache,
                        "4C 8D 2D ?? ?? ?? ?? 49 8B CD E8 ?? ?? ?? ?? 41 B9 3F 00 00 00",
                    ))),
                ),
                .player_1 = proxy("player_1", game.Player(.t8), .{
                    relativeOffset(i32, add(0x3, pattern(cache, "4C 89 35 ?? ?? ?? ?? 41 88 5E 28"))),
                    0x30,
                    0x0,
                }),
                .player_2 = proxy("player_2", game.Player(.t8), .{
                    relativeOffset(i32, add(0x3, pattern(cache, "4C 89 35 ?? ?? ?? ?? 41 88 5E 28"))),
                    0x38,
                    0x0,
                }),
                .main_player_info = proxy("main_player_info", game.PlayerInfo(.t8), .{
                    relativeOffset(i32, add(0xF, pattern(
                        cache,
                        "88 81 88 00 00 00 88 81 A8 00 00 00 48 8B 0D",
                    ))),
                    0x0,
                    0x0,
                    0x20,
                    0x0,
                }),
                .secondary_player_info = proxy("secondary_player_info", game.PlayerInfo(.t8), .{
                    relativeOffset(i32, add(0xF, pattern(
                        cache,
                        "88 81 88 00 00 00 88 81 A8 00 00 00 48 8B 0D",
                    ))),
                    0x0,
                    0x8,
                    0x20,
                    0x0,
                }),
                .match = .fromPointer(null), // Continuously updated address.
                .ruleset = .fromPointer(null), // Continuously updated address.
                .cancel_requirements = pointer(
                    "cancel_requirements",
                    game.CancelRequirements,
                    @intFromPtr(&game_hooks.cancel_requirements),
                ),
                .replay_mode = proxy("replay_mode", game.ReplayMode, .{
                    0x0, // Continuously updated address.
                    0x98,
                    0x70,
                }),
                .depth_buffer = proxy("depth_buffer", game.DepthBuffer(.t8), .{
                    @intFromPtr(&game_hooks.depth_buffer_address),
                    0x0,
                }),
                .functions = .{
                    .tick = functionPointer(
                        "tick",
                        game.TickFunction(.t8),
                        pattern(cache, "48 8B C4 48 89 58 08 48 89 68 10 48 89 70 18 57 48 81 EC ?? 01 00 00 48 8B 1D"),
                    ),
                    .processCancelRequirement = functionPointer(
                        "processCancelRequirement",
                        game.ProcessCancelRequirementFunction,
                        pattern(cache, "48 89 4C 24 08 55 53 56 57 41 54 41 55 41 56 48 8D AC 24 30 FF FF FF 48 81 EC D0 01 00 00 8B 39"),
                    ),
                    .unrealFree = functionPointer(
                        "unrealFree",
                        game.UnrealFreeFunction,
                        pattern(cache, "48 85 C9 74 ?? 53 48 83 EC 20 48 8B D9 48 8B 0D"),
                    ),
                    .findUnrealClass = functionPointer(
                        "findUnrealClass",
                        game.FindUnrealClassFunction,
                        relativeOffset(i32, add(0x7, pattern(cache, "45 33 C0 49 8B CF E8 ?? ?? ?? ?? 48 8B 4C 24 60"))),
                    ),
                    .findUnrealObjectsOfClass = functionPointer(
                        "findUnrealObjectsOfClass",
                        game.FindUnrealObjectsOfClassFunction,
                        relativeOffset(i32, add(0x1, pattern(cache, "E8 ?? ?? ?? ?? 90 48 89 6C 24 30"))),
                    ),
                    .setRenderTargets = functionPointer(
                        "setRenderTargets",
                        game.SetRenderTargetsFunction,
                        pattern(cache, "4C 8B DC 53 55 56 57 41 55 41 57"),
                    ),
                    .getGlobalsMap = functionPointer(
                        "getGlobalsMap",
                        game.GetGlobalsMapFunction,
                        relativeOffset(i32, add(0x1, pattern(
                            cache,
                            "E8 ?? ?? ?? ?? 48 8D 15 ?? ?? ?? ?? 48 8B C8 E8 ?? ?? ?? ?? 48 0F BE CB 48 83 C0 40",
                        ))),
                    ),
                    .findGlobalAddress = functionPointer(
                        "findGlobalAddress",
                        game.FindGlobalAddressFunction,
                        relativeOffset(i32, add(0x10, pattern(
                            cache,
                            "E8 ?? ?? ?? ?? 48 8D 15 ?? ?? ?? ?? 48 8B C8 E8 ?? ?? ?? ?? 48 0F BE CB 48 83 C0 40",
                        ))),
                    ),
                    .isReplay = functionPointer(
                        "isReplay",
                        game.IsReplayFunction,
                        pattern(cache, "48 89 5C 24 08 57 48 83 EC 20 C6 01 00"),
                    ),
                },
            };
        }

        pub fn testingInit(params: struct {
            game_version: ?*const game.Version(game_id) = null,
            player_1: ?*const game.Player(game_id) = null,
            player_2: ?*const game.Player(game_id) = null,
            main_player_info: ?*const game.PlayerInfo(game_id) = null,
            secondary_player_info: ?*const game.PlayerInfo(game_id) = null,
            match: ?*const game.Match(game_id) = null,
            ruleset: ?*const game.Ruleset(game_id) = null,
            cancel_requirements: ?*const game.CancelRequirements = null,
            replay_mode: ?*const game.ReplayMode = null,
            depth_buffer: ?*const game.DepthBuffer(game_id) = null,
            camera_manager: ?*const game.CameraManager(game_id) = null,
            walls: []const game.Wall(game_id) = &.{},
            floors: []const game.Floor(game_id) = &.{},
            player_starts: []const game.PlayerStart(game_id) = &.{},
            functions: Functions = .{},
            unreal_classes: UnrealClasses = .{},
        }) Self {
            if (!builtin.is_test) {
                @compileError("This function is only supposed to be called from inside tests.");
            }
            const makePointerArray = struct {
                fn call(
                    comptime Element: type,
                    comptime capacity: usize,
                    slice: []const Element,
                ) Array(capacity, Pointer(Element), .fromPointer(null), false) {
                    var result: Array(capacity, Pointer(Element), .fromPointer(null), false) = .empty;
                    for (slice) |*element| {
                        result.append(.fromPointer(element)) catch @panic("Slice does not fit into the array.");
                    }
                    return result;
                }
            }.call;
            return .{
                .game_version = .fromPointer(params.game_version),
                .player_1 = .fromPointer(params.player_1),
                .player_2 = .fromPointer(params.player_2),
                .main_player_info = .fromPointer(params.main_player_info),
                .secondary_player_info = .fromPointer(params.secondary_player_info),
                .match = .fromPointer(params.match),
                .ruleset = .fromPointer(params.ruleset),
                .cancel_requirements = .fromPointer(params.cancel_requirements),
                .replay_mode = .fromPointer(params.replay_mode),
                .depth_buffer = .fromPointer(params.depth_buffer),
                .camera_manager = .fromPointer(params.camera_manager),
                .walls = makePointerArray(game.Wall(game_id), max_walls, params.walls),
                .floors = makePointerArray(game.Floor(game_id), max_floors, params.floors),
                .player_starts = makePointerArray(game.PlayerStart(game_id), max_player_starts, params.player_starts),
                .functions = params.functions,
                .unreal_classes = params.unreal_classes,
            };
        }

        pub fn updateAddresses(self: *Self) void {
            self.updateGlobalAddresses();
            self.updateUnrealClasses();
            self.updateUnrealObjectAddress((&self.camera_manager), self.unreal_classes.camera_manager);
            self.updateUnrealObjectAddresses(&self.walls, self.unreal_classes.wall);
            self.updateUnrealObjectAddresses(&self.floors, self.unreal_classes.floor);
            self.updateUnrealObjectAddresses(&self.player_starts, self.unreal_classes.player_start);
        }

        fn updateGlobalAddresses(self: *Self) void {
            switch (game_id) {
                .t7 => return,
                .t8 => {},
            }
            const getGlobalsMap = self.functions.getGlobalsMap orelse return;
            const findGlobalAddress = self.functions.findGlobalAddress orelse return;
            const map = getGlobalsMap();
            self.match.address = findGlobalAddress(map, &.match);
            self.ruleset.address = findGlobalAddress(map, &.ruleset);
            self.replay_mode.trail.buffer[0] = findGlobalAddress(map, &.replay) +| 0x8;
        }

        fn updateUnrealClasses(self: *Self) void {
            const findClass = self.functions.findUnrealClass orelse return;
            const w = std.unicode.utf8ToUtf16LeStringLiteral;
            const classes = &self.unreal_classes;
            if (classes.camera_manager == null) {
                classes.camera_manager = findClass(null, w("/Script/Engine.PlayerCameraManager"), true);
            }
            if (classes.wall == null) {
                classes.wall = switch (game_id) {
                    .t7 => findClass(null, w("/Script/TekkenGame.TekkenWallActor"), true),
                    .t8 => findClass(null, w("/Script/Polaris.PolarisStageWallActor"), true),
                };
            }
            if (classes.photo_mode_wall == null) {
                classes.photo_mode_wall = switch (game_id) {
                    .t7 => null,
                    .t8 => findClass(null, w("/Script/Polaris.PolarisPhotoModeWallActor"), true),
                };
            }
            if (classes.player_start == null) {
                classes.player_start = switch (game_id) {
                    .t7 => findClass(null, w("/Script/TekkenGame.TekkenPlayerStart"), true),
                    .t8 => findClass(null, w("/Script/Polaris.PolarisBattlePlayerStart"), true),
                };
            }
            if (classes.floor == null) {
                classes.floor = switch (game_id) {
                    .t7 => findClass(null, w("/Script/TekkenGame.TekkenFloorActor"), true),
                    .t8 => findClass(null, w("/Script/Polaris.PolarisStageFloorActor"), true),
                };
            }
        }

        fn updateUnrealObjectAddress(
            self: *const Self,
            address: anytype,
            class_maybe: ?*const game.UnrealClass,
        ) void {
            if (@typeInfo(@TypeOf(address)) != .pointer) {
                @compileError(
                    "Expecting the address to be passed by reference but got type: " ++ @typeName(@TypeOf(address)),
                );
            }
            const findUnrealObjectsOfClass = self.functions.findUnrealObjectsOfClass orelse return;
            const unrealFree = self.functions.unrealFree orelse return;
            const class = class_maybe orelse return;

            var list = game.UnrealArrayList(*game.UnrealObject).empty;
            findUnrealObjectsOfClass(class, &list, true, .default_exclude, .{});
            defer list.free(unrealFree);

            const slice = list.asSlice();
            if (slice.len > 0) {
                address.address = @intFromPtr(slice[0]);
            } else {
                address.address = 0;
            }
        }

        fn updateUnrealObjectAddresses(
            self: *const Self,
            addresses: anytype,
            class_maybe: ?*const game.UnrealClass,
        ) void {
            if (@typeInfo(@TypeOf(addresses)) != .pointer) {
                @compileError(
                    "Expecting the pointers to be passed by reference but got type: " ++ @typeName(@TypeOf(addresses)),
                );
            }
            const findUnrealObjectsOfClass = self.functions.findUnrealObjectsOfClass orelse return;
            const unrealFree = self.functions.unrealFree orelse return;
            const class = class_maybe orelse return;

            var list = game.UnrealArrayList(*game.UnrealObject).empty;
            findUnrealObjectsOfClass(class, &list, true, .default_exclude, .{});
            defer list.free(unrealFree);

            const slice = list.asSlice();
            addresses.* = .empty;
            for (slice) |element| {
                addresses.append(.{ .address = @intFromPtr(element) }) catch {};
            }
        }

        fn initPatternCache(
            allocator: std.mem.Allocator,
            base_dir: ?*const sdk.misc.BaseDir,
            file_name: []const u8,
        ) !sdk.memory.PatternCache {
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
                loadPatternCache(&cache, dir, file_name) catch |err| {
                    sdk.misc.error_context.append("Failed to load memory pattern cache. Using empty cache.", .{});
                    sdk.misc.error_context.logWarning(err);
                };
            }
            return cache;
        }

        fn deinitPatternCache(
            cache: *sdk.memory.PatternCache,
            base_dir: ?*const sdk.misc.BaseDir,
            file_name: []const u8,
        ) void {
            if (base_dir) |dir| {
                savePatternCache(cache, dir, file_name) catch |err| {
                    sdk.misc.error_context.append("Failed to save memory pattern cache.", .{});
                    sdk.misc.error_context.logWarning(err);
                };
            }
            cache.deinit();
        }

        fn loadPatternCache(
            cache: *sdk.memory.PatternCache,
            base_dir: *const sdk.misc.BaseDir,
            file_name: []const u8,
        ) !void {
            var buffer: [sdk.os.max_file_path_length]u8 = undefined;
            const file_path = base_dir.getPath(&buffer, file_name) catch |err| {
                sdk.misc.error_context.append("Failed to construct file path.", .{});
                return err;
            };

            const executable_timestamp = sdk.os.getExecutableTimestamp() catch |err| {
                sdk.misc.error_context.append("Failed to get executable timestamp.", .{});
                return err;
            };

            return cache.load(file_path, executable_timestamp);
        }

        fn savePatternCache(
            cache: *sdk.memory.PatternCache,
            base_dir: *const sdk.misc.BaseDir,
            file_name: []const u8,
        ) !void {
            var buffer: [sdk.os.max_file_path_length]u8 = undefined;
            const file_path = base_dir.getPath(&buffer, file_name) catch |err| {
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
}

fn proxy(name: []const u8, comptime Type: type, offsets: anytype) sdk.memory.Proxy(Type) {
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

fn pointer(name: []const u8, comptime Type: type, address: anyerror!usize) sdk.memory.Pointer(Type) {
    const addr = address catch |err| {
        if (!builtin.is_test) {
            sdk.misc.error_context.append("Failed to resolve pointer: {s}", .{name});
            sdk.misc.error_context.logError(err);
        }
        return .{ .address = 0 };
    };
    return .{ .address = addr };
}

fn functionPointer(name: []const u8, comptime Function: type, address: anyerror!usize) ?*const Function {
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

test "proxy should construct a proxy from offsets" {
    const byte_proxy = proxy("byte_proxy", u8, .{ 1, 2, 3 });
    try testing.expectEqualSlices(?usize, &.{ 1, 2, 3 }, byte_proxy.trail.getOffsets());
}

test "proxy should map errors to null values" {
    sdk.misc.error_context.new("Test error.", .{});
    const byte_proxy = proxy("byte_proxy", u8, .{ 1, error.Test, 2, error.Test });
    try testing.expectEqualSlices(?usize, &.{ 1, null, 2, null }, byte_proxy.trail.getOffsets());
}

test "pointer should return a pointer with the provided address when a address is provided" {
    const ptr = pointer("test", u32, 123);
    try testing.expectEqual(123, ptr.address);
}

test "pointer should return a pointer with zero address when error is provided" {
    const ptr = pointer("test", u32, error.Testt);
    try testing.expectEqual(0, ptr.address);
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
