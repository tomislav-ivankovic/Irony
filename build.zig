const std = @import("std");
const builtin = @import("builtin");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Use system Wine installation to run cross compiled Windows build artifacts.
    b.enable_wine = true;

    // Standard target options allows the person running `zig build` to choose what target to build for.
    // Here we restrict the standard options to only allow building for 64-bit Windows, and make that the default target.
    const target = b.standardTargetOptions(.{
        .whitelist = &.{.{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
            .abi = .gnu,
        }},
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
            .abi = .gnu,
        },
    });

    // Standard optimization options allow the person running `zig build` to select between Debug, ReleaseSafe,
    // ReleaseFast, and ReleaseSmall. Here we do not set a preferred release mode, allowing the user to decide how to
    // optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies:
    const win32 = zigwin32Dependency(b);
    const lib_c_time = libCTimeDependency(b, target, optimize);
    const minhook = minhookDependency(b, target, optimize);
    const imgui = imguiDependency(b, target, optimize, false);
    const imgui_te = imguiDependency(b, target, optimize, true);
    const xz = xzDependency(b, target, optimize);

    // This module makes the values from inside build.zig.zon available from inside the application code.
    const build_info = b.createModule(.{ .root_source_file = b.path("build.zig.zon") });

    const dll = b.addLibrary(.{
        .name = "irony",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/dll.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    dll.root_module.addImport("build_info", build_info);
    dll.root_module.addImport("win32", win32);
    dll.root_module.addImport("lib_c_time", lib_c_time);
    dll.root_module.addImport("minhook", minhook);
    dll.root_module.linkLibrary(imgui.library);
    dll.root_module.addImport("imgui", imgui.module);
    dll.root_module.linkLibrary(xz.library);
    dll.root_module.addImport("xz", xz.module);

    // This declares intent for the dll to be installed into the standard location when the user invokes the "install"
    // step (the default step when running `zig build`).
    b.installArtifact(dll);

    const injector = b.addExecutable(.{
        .name = "irony_injector",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/injector.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    injector.root_module.addImport("build_info", build_info);
    injector.root_module.addImport("lib_c_time", lib_c_time);
    injector.root_module.addImport("win32", win32);

    // This declares intent for the injector to be installed into the standard location when the user invokes the
    // "install" step (the default step when running `zig build`).
    b.installArtifact(injector);

    // This *creates* a Run step in the build graph, to be executed when another step is evaluated that depends on it.
    // The next line below will establish such a dependency.
    const run_command = b.addRunArtifact(injector);

    // Make sure that the working directory when the program is ran is the same one where the executable is located.
    run_command.setCwd(std.Build.LazyPath{ .cwd_relative = "./zig-out/bin" });

    // Stop Wine from spamming debug messages in the console when running the application.
    run_command.setEnvironmentVariable("WINEDEBUG", "-all");

    // By making the run step depend on the install step, it will be run from the installation directory rather than
    // directly from within the cache directory. This is not necessary, however, if the application depends on other
    // installed files, this ensures they will be present and in the expected location.
    run_command.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build command itself, like this:
    // `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_command.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu, and can be selected like this:
    // `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the injector");
    run_step.dependOn(&run_command.step);

    // Creates a step for testing. This only builds the test executable but does not run it.
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    tests.root_module.addImport("build_info", build_info);
    tests.root_module.addImport("lib_c_time", lib_c_time);
    tests.root_module.addImport("win32", win32);
    tests.root_module.addImport("minhook", minhook);
    tests.root_module.linkLibrary(imgui_te.library);
    tests.root_module.addImport("imgui", imgui_te.module);
    tests.root_module.linkLibrary(xz.library);
    tests.root_module.addImport("xz", xz.module);

    // This *creates* a Test step in the build graph, to be executed when another step is evaluated that depends on it.
    // The next line below will establish such a dependency.
    const test_command = b.addRunArtifact(tests);

    // Stop Wine from spamming debug messages in the console when running tests.
    test_command.setEnvironmentVariable("WINEDEBUG", "-all");
    test_command.setEnvironmentVariable("DXVK_LOG_LEVEL", "none");
    test_command.setEnvironmentVariable("VKD3D_DEBUG", "none");
    // Stop vkd3d from caching shaders in a file when running tests.
    test_command.setEnvironmentVariable("VKD3D_SHADER_CACHE_PATH", "0");

    // Similar to creating the run step earlier, this exposes a `test` step to the `zig build --help` menu, providing a
    // way for the user to request running the tests.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&test_command.step);
}

const ModuleAndLibrary = struct {
    module: *std.Build.Module,
    library: *std.Build.Step.Compile,
};

// ZIG dependency: zigwin32
fn zigwin32Dependency(b: *std.Build) *std.Build.Module {
    return b.dependency("zigwin32", .{}).module("win32");
}

// C dependency: lib_c_time ("time.h" from C)
fn libCTimeDependency(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const file = b.addWriteFile("time.h",
        \\#define _POSIX_C_SOURCE 200809L
        \\#include <time.h>
    ).getDirectory().path(b, "time.h");
    const translate_c = b.addTranslateC(.{
        .root_source_file = file,
        .target = target,
        .optimize = optimize,
    });
    return translate_c.createModule();
}

// C dependency: minhook
fn minhookDependency(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const dependency = b.dependency("minhook", .{});
    const translate_c = b.addTranslateC(.{
        .root_source_file = dependency.path("include/MinHook.h"),
        .target = target,
        .optimize = optimize,
    });
    const module = translate_c.createModule();
    module.addIncludePath(dependency.path("include"));
    module.addCSourceFiles(.{
        .root = dependency.path("src"),
        .files = &.{
            "buffer.c",
            "hook.c",
            "trampoline.c",
            "hde/hde32.c",
            "hde/hde64.c",
        },
        // Fixes undefined behaviour in hde64.c line 318.
        .flags = &.{"-fno-sanitize=undefined"},
    });
    return module;
}

// C++ dependency: imgui (imgui, cimgui, imgui_test_engine, cimgui_test_engine, imgui_file_dialog)
fn imguiDependency(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    use_test_engine: bool,
) ModuleAndLibrary {
    const file_dialog_patcher = b.addExecutable(.{
        .name = "imgui_file_dialog_patcher",
        .root_module = b.createModule(.{
            .root_source_file = b.path("dep/imgui_file_dialog/patcher.zig"),
            .target = b.graph.host,
        }),
    });
    const file_dialog_patcher_run = b.addRunArtifact(file_dialog_patcher);
    file_dialog_patcher_run.addFileArg(b.dependency("imgui_file_dialog", .{}).path("ImGuiFileDialog.cpp"));
    const patched_file_dialog = file_dialog_patcher_run.captureStdOut();

    const files = b.addWriteFiles();
    _ = files.addCopyDirectory(b.dependency("cimgui", .{}).path("."), ".", .{});
    _ = files.addCopyDirectory(b.dependency("imgui", .{}).path("."), "./imgui", .{});
    _ = files.addCopyDirectory(b.dependency("imgui_file_dialog", .{}).path("."), "./imgui_file_dialog", .{});
    _ = files.addCopyFile(patched_file_dialog, "./imgui_file_dialog/ImGuiFileDialog_patched.cpp");
    if (use_test_engine) {
        _ = files.addCopyDirectory(
            b.dependency("imgui_test_engine", .{}).path("./imgui_test_engine"),
            "./imgui_test_engine",
            .{},
        );
        _ = files.addCopyDirectory(b.dependency("cimgui_test_engine", .{}).path("."), ".", .{});
    }
    if (use_test_engine) {
        _ = files.add("root.h",
            \\#include "cimgui_test_engine.h"
            \\#include "imgui_file_dialog/ImGuiFileDialog.h"
        );
    } else {
        _ = files.add("root.h",
            \\#include "cimgui.h"
            \\#include "imgui_file_dialog/ImGuiFileDialog.h"
        );
    }
    const directory = files.getDirectory();
    const library = b.addLibrary(.{
        .name = "imgui",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });
    library.root_module.addIncludePath(directory);
    library.root_module.addIncludePath(directory.path(b, "./imgui"));
    if (use_test_engine) {
        library.root_module.addIncludePath(directory.path(b, "./imgui_test_engine"));
    }
    library.root_module.addCSourceFiles(.{ .root = directory, .files = &.{
        "./cimgui.cpp",
        "./imgui/imgui.cpp",
        "./imgui/imgui_demo.cpp",
        "./imgui/imgui_draw.cpp",
        "./imgui/imgui_tables.cpp",
        "./imgui/imgui_widgets.cpp",
        "./imgui/backends/imgui_impl_dx12.cpp",
        "./imgui/backends/imgui_impl_win32.cpp",
        "./imgui_file_dialog/ImGuiFileDialog_patched.cpp",
    } });
    if (use_test_engine) {
        library.root_module.addCSourceFiles(.{ .root = directory, .files = &.{
            "./cimgui_test_engine.cpp",
            "./imgui_test_engine/imgui_capture_tool.cpp",
            "./imgui_test_engine/imgui_te_context.cpp",
            "./imgui_test_engine/imgui_te_coroutine.cpp",
            "./imgui_test_engine/imgui_te_engine.cpp",
            "./imgui_test_engine/imgui_te_exporters.cpp",
            "./imgui_test_engine/imgui_te_perftool.cpp",
            "./imgui_test_engine/imgui_te_ui.cpp",
            "./imgui_test_engine/imgui_te_utils.cpp",
        } });
    }
    library.root_module.linkSystemLibrary("d3dcompiler_47", .{}); // Required by: imgui_impl_dx12.cpp
    library.root_module.linkSystemLibrary("dwmapi", .{}); // Required by: imgui_impl_win32.cpp
    switch (target.result.abi) { // Required by: imgui_impl_win32.cpp
        .msvc => library.root_module.linkSystemLibrary("Gdi32", .{}),
        .gnu => library.root_module.linkSystemLibrary("gdi32", .{}),
        else => {},
    }
    library.root_module.addCMacro("IMGUI_IMPL_API", "extern \"C\"");
    library.root_module.addCMacro("IMGUI_DISABLE_OBSOLETE_FUNCTIONS", "1");
    library.root_module.addCMacro("IMGUI_IMPL_WIN32_DISABLE_GAMEPAD", "1");
    library.root_module.addCMacro("IMGUI_USE_WCHAR32", "1");
    if (use_test_engine) {
        library.root_module.addCMacro("IMGUI_ENABLE_TEST_ENGINE", "");
        library.root_module.addCMacro("IMGUI_TEST_ENGINE_ENABLE_IMPLOT", "0");
        library.root_module.addCMacro("IMGUI_TEST_ENGINE_ENABLE_CAPTURE", "1");
        library.root_module.addCMacro("IMGUI_TEST_ENGINE_ENABLE_STD_FUNCTION", "0");
        library.root_module.addCMacro("IMGUI_TEST_ENGINE_ENABLE_COROUTINE_STDTHREAD_IMPL", "1");
        library.root_module.addCMacro("IM_DEBUG_BREAK()", "IM_ASSERT(0)");
    }
    library.root_module.addCMacro("USE_STD_FILESYSTEM", "1");
    const translate_c = b.addTranslateC(.{
        .root_source_file = directory.path(b, "root.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.defineCMacro("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    translate_c.defineCMacro("IMGUI_USE_WCHAR32", "1");
    const module = translate_c.createModule();
    return .{ .module = module, .library = library };
}

// C dependency: xz utils
fn xzDependency(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) ModuleAndLibrary {
    const dependency = b.dependency("xz", .{});
    const library = b.addLibrary(.{
        .name = "xz",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    const directory = dependency.path("./src");
    library.root_module.addIncludePath(directory.path(b, "./common"));
    library.root_module.addIncludePath(directory.path(b, "./liblzma/api"));
    library.root_module.addIncludePath(directory.path(b, "./liblzma/check"));
    library.root_module.addIncludePath(directory.path(b, "./liblzma/common"));
    library.root_module.addIncludePath(directory.path(b, "./liblzma/delta"));
    library.root_module.addIncludePath(directory.path(b, "./liblzma/lz"));
    library.root_module.addIncludePath(directory.path(b, "./liblzma/lzma"));
    library.root_module.addIncludePath(directory.path(b, "./liblzma/simple"));
    library.root_module.addIncludePath(directory.path(b, "./liblzma/rangecoder"));
    library.root_module.addCSourceFiles(.{
        .root = directory.path(b, "./liblzma"),
        .files = &.{
            "./common/common.c",
            "./common/block_util.c",
            "./common/easy_preset.c",
            "./common/filter_common.c",
            "./common/filter_common.c",
            "./common/hardware_physmem.c",
            "./common/hardware_physmem.c",
            "./common/index.c",
            "./common/stream_flags_common.c",
            "./common/string_conversion.c",
            "./common/vli_size.c",
            "./common/alone_encoder.c",
            "./common/block_buffer_encoder.c",
            "./common/block_encoder.c",
            "./common/block_header_encoder.c",
            "./common/easy_buffer_encoder.c",
            "./common/easy_encoder.c",
            "./common/easy_encoder_memusage.c",
            "./common/filter_buffer_encoder.c",
            "./common/filter_encoder.c",
            "./common/filter_flags_encoder.c",
            "./common/index_encoder.c",
            "./common/stream_buffer_encoder.c",
            "./common/stream_encoder.c",
            "./common/stream_flags_encoder.c",
            "./common/vli_encoder.c",
            "./common/alone_decoder.c",
            "./common/auto_decoder.c",
            "./common/block_buffer_decoder.c",
            "./common/block_decoder.c",
            "./common/block_header_decoder.c",
            "./common/easy_decoder_memusage.c",
            "./common/file_info.c",
            "./common/filter_buffer_decoder.c",
            "./common/filter_decoder.c",
            "./common/filter_flags_decoder.c",
            "./common/index_decoder.c",
            "./common/index_hash.c",
            "./common/stream_buffer_decoder.c",
            "./common/stream_decoder.c",
            "./common/stream_flags_decoder.c",
            "./common/vli_decoder.c",
            "./check/crc_clmul_consts_gen.c",
            "./check/crc32_tablegen.c",
            "./check/crc64_tablegen.c",
            "./check/check.c",
            "./check/crc32_fast.c",
            "./check/crc64_fast.c",
            "./lz/lz_encoder.c",
            "./lz/lz_encoder_mf.c",
            "./lz/lz_decoder.c",
            "./lzma/fastpos_tablegen.c",
            "./lzma/lzma_encoder_presets.c",
            "./lzma/lzma_encoder.c",
            "./lzma/lzma_encoder_optimum_fast.c",
            "./lzma/lzma_encoder_optimum_normal.c",
            "./lzma/fastpos_table.c",
            "./lzma/lzma_decoder.c",
            "./lzma/lzma2_encoder.c",
            "./lzma/lzma2_decoder.c",
            "./rangecoder/price_tablegen.c",
            "./rangecoder/price_table.c",
        },
    });
    library.root_module.addCMacro("ASSUME_RAM", "32");
    library.root_module.addCMacro("HAVE_CHECK_CRC64", "1");
    library.root_module.addCMacro("HAVE_DECODERS", "1");
    library.root_module.addCMacro("HAVE_DECODER_LZMA2", "1");
    library.root_module.addCMacro("HAVE_ENCODERS", "1");
    library.root_module.addCMacro("HAVE_ENCODER_LZMA2", "1");
    library.root_module.addCMacro("HAVE_MF_BT4", "1");
    library.root_module.addCMacro("HAVE_STDBOOL_H", "1");
    const translate_c = b.addTranslateC(.{
        .root_source_file = directory.path(b, "./liblzma/api/lzma.h"),
        .target = target,
        .optimize = optimize,
    });
    const module = translate_c.createModule();
    return .{ .module = module, .library = library };
}
