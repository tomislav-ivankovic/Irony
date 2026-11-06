const std = @import("std");
const builtin = @import("builtin");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
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
    const win_io = winIoDependency(b);
    const lib_c_time = libCTimeDependency(b, target, optimize);
    const minhook = minhookDependency(b, target, optimize);
    const imgui = imguiDependency(b, target, optimize, false);
    const imgui_te = imguiDependency(b, target, optimize, true);
    const zstd = zstdDependency(b, target, optimize);

    const build_info_t7 = b.createModule(.{ .root_source_file = b.path("build_info_t7.zig") });
    const dll_t7 = b.addLibrary(.{
        .name = "irony_t7",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/dll.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    dll_t7.root_module.addImport("build_info", build_info_t7);
    dll_t7.root_module.addImport("win32", win32);
    dll_t7.root_module.addImport("win_io", win_io);
    dll_t7.root_module.addImport("lib_c_time", lib_c_time);
    dll_t7.root_module.addImport("minhook", minhook);
    dll_t7.root_module.linkLibrary(imgui.library);
    dll_t7.root_module.addImport("imgui", imgui.module);
    dll_t7.root_module.linkLibrary(zstd.library);
    dll_t7.root_module.addImport("zstd", zstd.module);
    if (b.option(bool, "t7", "Whether to build the T7 dll.") orelse true) {
        b.installArtifact(dll_t7);
    }

    const build_info_t8 = b.createModule(.{ .root_source_file = b.path("build_info_t8.zig") });
    const dll_t8 = b.addLibrary(.{
        .name = "irony_t8",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/dll.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    dll_t8.root_module.addImport("build_info", build_info_t8);
    dll_t8.root_module.addImport("win32", win32);
    dll_t8.root_module.addImport("win_io", win_io);
    dll_t8.root_module.addImport("lib_c_time", lib_c_time);
    dll_t8.root_module.addImport("minhook", minhook);
    dll_t8.root_module.linkLibrary(imgui.library);
    dll_t8.root_module.addImport("imgui", imgui.module);
    dll_t8.root_module.linkLibrary(zstd.library);
    dll_t8.root_module.addImport("zstd", zstd.module);
    if (b.option(bool, "t8", "Whether to build the T8 dll.") orelse true) {
        b.installArtifact(dll_t8);
    }

    const injector = b.addExecutable(.{
        .name = "irony_injector",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/injector.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    injector.root_module.addImport("build_info", build_info_t8);
    injector.root_module.addImport("lib_c_time", lib_c_time);
    injector.root_module.addImport("win32", win32);
    b.installArtifact(injector);

    // This *creates* a Run step in the build graph, to be executed when another step is evaluated that depends on it.
    // The next line below will establish such a dependency.
    const run_command = b.addRunArtifact(injector);

    // Make sure that the working directory when the program is ran is the same one where the executable is located.
    run_command.setCwd(.{ .relative = .{ .base = .install_bin } });

    // Stop Wine from spamming debug messages in the console when running the application.
    run_command.setEnvironmentVariable("WINEDEBUG", "-all");

    // By making the run step depend on the install step, it will be run from the installation directory rather than
    // directly from within the cache directory. This is not necessary, however, if the application depends on other
    // installed files, this ensures they will be present and in the expected location.
    run_command.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build command itself, like this:
    // `zig build run -- arg1 arg2 etc`
    run_command.addPassthruArgs();

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
    tests.root_module.addImport("build_info", build_info_t8);
    tests.root_module.addImport("lib_c_time", lib_c_time);
    tests.root_module.addImport("win32", win32);
    tests.root_module.addImport("win_io", win_io);
    tests.root_module.addImport("minhook", minhook);
    tests.root_module.linkLibrary(imgui_te.library);
    tests.root_module.addImport("imgui", imgui_te.module);
    tests.root_module.linkLibrary(zstd.library);
    tests.root_module.addImport("zstd", zstd.module);

    const tests_config = b.addOptions();
    tests_config.addOption(
        bool,
        "skip_gpu",
        b.option(bool, "skip_gpu", "Whether to skip tests that require a GPU to succeed.") orelse false,
    );
    tests_config.addOption(
        bool,
        "skip_display",
        b.option(bool, "skip_display", "Whether to skip tests that require a display to succeed.") orelse false,
    );
    tests.root_module.addOptions("config", tests_config);

    // This *creates* a Test step in the build graph, to be executed when another step is evaluated that depends on it.
    // The next line below will establish such a dependency.
    const test_command = b.addRunArtifact(tests);

    // Make sure that the working directory when the tests are ran is test_assets.
    test_command.setCwd(b.path("./test_assets"));

    // Stop Wine from spamming debug messages in the console when running tests.
    test_command.setEnvironmentVariable("WINEDEBUG", "-all");
    test_command.setEnvironmentVariable("DXVK_LOG_LEVEL", "none");
    test_command.setEnvironmentVariable("VKD3D_DEBUG", "none");
    test_command.setEnvironmentVariable("EGL_LOG_LEVEL", "fatal");
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

// ZIG dependency: win_io
fn winIoDependency(b: *std.Build) *std.Build.Module {
    return b.dependency("win_io", .{}).module("win_io");
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
    const find_replace_patcher = b.addExecutable(.{
        .name = "find_replace_patcher",
        .root_module = b.createModule(.{
            .root_source_file = b.path("dep/file_patchers/find_replace.zig"),
            .target = b.graph.host,
        }),
    });
    const function_patcher = b.addExecutable(.{
        .name = "function_patcher",
        .root_module = b.createModule(.{
            .root_source_file = b.path("dep/file_patchers/function.zig"),
            .target = b.graph.host,
        }),
    });

    const original = b.dependency("imgui_file_dialog", .{}).path("ImGuiFileDialog.cpp");

    const patch_round_number = b.addRunArtifact(function_patcher);
    patch_round_number.addFileArg(original);
    patch_round_number.addArg("std::string IGFD::Utils::RoundNumber(double vvalue, int n)");
    patch_round_number.addArg(
        \\{
        \\    char format[16];
        \\    std::snprintf(format, sizeof(format), "%%.%df", n);
        \\    char buffer[128];
        \\    std::snprintf(buffer, sizeof(buffer), format, vvalue);
        \\    return std::string(buffer);
        \\}
    );
    const imgui_file_dialog_patched_1 = patch_round_number.captureStdOut(.{});

    const patch_file_path = b.addRunArtifact(find_replace_patcher);
    patch_file_path.addFileArg(imgui_file_dialog_patched_1);
    patch_file_path.addArg("fs::path fpath(vFilePathName);");
    patch_file_path.addArg("fs::path fpath = fs::u8path(vFilePathName);");
    const imgui_file_dialog_patched_2 = patch_file_path.captureStdOut(.{});

    const patch_file_name_focus = b.addRunArtifact(find_replace_patcher);
    patch_file_name_focus.addFileArg(imgui_file_dialog_patched_2);
    patch_file_name_focus.addArg(
        \\if (ImGui::InputText("##FileName"
    );
    patch_file_name_focus.addArg(
        \\if (ImGui::IsWindowAppearing()) ImGui::SetKeyboardFocusHere();
        \\if (ImGui::InputText("##FileName"
    );
    const imgui_file_dialog_patched_3 = patch_file_name_focus.captureStdOut(.{});

    const patch_win32_key_event = b.addRunArtifact(find_replace_patcher);
    patch_win32_key_event.addFileArg(b.dependency("imgui", .{}).path("backends/imgui_impl_win32.cpp"));
    const key_event_declaration = "ImGuiKey ImGui_ImplWin32_KeyEventToImGuiKey(WPARAM wParam, LPARAM lParam);";
    patch_win32_key_event.addArg(key_event_declaration);
    patch_win32_key_event.addArg("IMGUI_IMPL_API " ++ key_event_declaration);
    const win32_backend_patched = patch_win32_key_event.captureStdOut(.{});

    const files = b.addWriteFiles();
    _ = files.addCopyDirectory(b.dependency("cimgui", .{}).path("."), ".", .{});
    _ = files.addCopyDirectory(b.dependency("imgui", .{}).path("."), "./imgui", .{});
    _ = files.addCopyFile(win32_backend_patched, "./imgui/backends/imgui_impl_win32_patched.cpp");
    _ = files.addCopyDirectory(b.dependency("imgui_file_dialog", .{}).path("."), "./imgui_file_dialog", .{});
    _ = files.addCopyFile(imgui_file_dialog_patched_3, "./imgui_file_dialog/ImGuiFileDialog_patched.cpp");
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
        "./imgui/backends/imgui_impl_dx11.cpp",
        "./imgui/backends/imgui_impl_dx12.cpp",
        "./imgui/backends/imgui_impl_win32_patched.cpp",
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

// C dependency: zstd
fn zstdDependency(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) ModuleAndLibrary {
    const dependency = b.dependency("zstd", .{});
    const library = b.addLibrary(.{
        .name = "zstd",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    const directory = dependency.path("./lib");
    library.root_module.addIncludePath(directory);
    library.root_module.addCSourceFiles(.{
        .root = directory,
        .files = &.{
            "./common/debug.c",
            "./common/entropy_common.c",
            "./common/error_private.c",
            "./common/fse_decompress.c",
            "./common/pool.c",
            "./common/threading.c",
            "./common/xxhash.c",
            "./common/zstd_common.c",
            "./compress/fse_compress.c",
            "./compress/hist.c",
            "./compress/huf_compress.c",
            "./compress/zstd_compress.c",
            "./compress/zstd_compress_literals.c",
            "./compress/zstd_compress_sequences.c",
            "./compress/zstd_compress_superblock.c",
            "./compress/zstd_double_fast.c",
            "./compress/zstd_fast.c",
            "./compress/zstd_lazy.c",
            "./compress/zstd_ldm.c",
            "./compress/zstd_opt.c",
            "./compress/zstd_preSplit.c",
            "./compress/zstdmt_compress.c",
            "./decompress/huf_decompress.c",
            "./decompress/zstd_ddict.c",
            "./decompress/zstd_decompress.c",
            "./decompress/zstd_decompress_block.c",
        },
    });
    library.root_module.addAssemblyFile(directory.path(b, "./decompress/huf_decompress_amd64.S"));
    library.root_module.addCMacro("ZSTD_STATIC_LINKING_ONLY", "1");
    const translate_c = b.addTranslateC(.{
        .root_source_file = directory.path(b, "zstd.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.defineCMacro("ZSTD_STATIC_LINKING_ONLY", "1");
    const module = translate_c.createModule();
    return .{ .module = module, .library = library };
}
