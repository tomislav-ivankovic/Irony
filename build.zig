const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Use system Wine installation to run cross compiled Windows build artifacts.
    b.enable_wine = true;

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we restrict the standard options to only
    // allow building for 64-bit Windows, and make that the default target.
    const target = b.standardTargetOptions(.{
        .whitelist = &.{.{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
        }},
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
        },
    });

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // ZIG dependency: zigwin32
    const win32 = b.dependency("zigwin32", .{}).module("win32");

    // C dependency: lib_c_time ("time.h" from C)
    const lib_c_time = b.addTranslateC(.{
        .root_source_file = b.addWriteFile(
            "time.h",
            "#define _POSIX_C_SOURCE 200809L\n#include <time.h>",
        ).getDirectory().path(b, "time.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();

    // C dependency: minhook
    const minhook_dep = b.dependency("minhook", .{});
    const minhook = b.addTranslateC(.{
        .root_source_file = minhook_dep.path("include/MinHook.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();
    minhook.addIncludePath(minhook_dep.path("include"));
    minhook.addCSourceFiles(.{
        .root = .{
            .dependency = .{
                .dependency = minhook_dep,
                .sub_path = "src",
            },
        },
        .files = &[_][]const u8{
            "buffer.c",
            "hook.c",
            "trampoline.c",
            "hde/hde32.c",
            "hde/hde64.c",
        },
    });

    // C++ dependency: imgui (cimgui)
    const imgui_files = b.addWriteFiles();
    _ = imgui_files.addCopyDirectory(b.dependency("cimgui", .{}).path("."), ".", .{});
    _ = imgui_files.addCopyDirectory(b.dependency("imgui", .{}).path("."), "./imgui", .{});
    const imgui_dir = imgui_files.getDirectory();
    const imgui_lib = b.addStaticLibrary(.{
        .name = "imgui",
        .target = target,
        .optimize = optimize,
    });
    imgui_lib.addIncludePath(imgui_dir);
    imgui_lib.addIncludePath(imgui_dir.path(b, "./imgui"));
    imgui_lib.addCSourceFiles(.{
        .root = imgui_dir,
        .files = &.{
            "./cimgui.cpp",
            "./imgui/imgui.cpp",
            "./imgui/imgui_demo.cpp",
            "./imgui/imgui_draw.cpp",
            "./imgui/imgui_tables.cpp",
            "./imgui/imgui_widgets.cpp",
            "./imgui/backends/imgui_impl_dx12.cpp",
            "./imgui/backends/imgui_impl_win32.cpp",
        },
    });
    imgui_lib.linkSystemLibrary("d3dcompiler_47"); // Required by: imgui_impl_dx12.cpp
    imgui_lib.linkSystemLibrary("dwmapi"); // Required by: imgui_impl_win32.cpp
    switch (target.result.abi) { // Required by: imgui_impl_win32.cpp
        .msvc => imgui_lib.linkSystemLibrary("Gdi32"),
        .gnu => imgui_lib.linkSystemLibrary("gdi32"),
        else => {},
    }
    imgui_lib.root_module.addCMacro("IMGUI_IMPL_API", "extern \"C\"");
    imgui_lib.root_module.addCMacro("IMGUI_DISABLE_OBSOLETE_FUNCTIONS", "1");
    imgui_lib.linkLibC();
    imgui_lib.linkLibCpp();
    const imgui_c = b.addTranslateC(.{
        .root_source_file = imgui_dir.path(b, "cimgui.h"),
        .target = target,
        .optimize = optimize,
    });
    imgui_c.defineCMacro("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    const imgui = imgui_c.createModule();

    const dll = b.addSharedLibrary(.{
        .name = "irony",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/dll.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    dll.root_module.addImport("win32", win32);
    dll.root_module.addImport("lib_c_time", lib_c_time);
    dll.root_module.addImport("minhook", minhook);
    dll.linkLibrary(imgui_lib);
    dll.root_module.addImport("imgui", imgui);

    // This declares intent for the dll to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(dll);

    const injector = b.addExecutable(.{
        .name = "irony_injector",
        .root_source_file = b.path("src/injector.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    injector.root_module.addImport("lib_c_time", lib_c_time);
    injector.root_module.addImport("win32", win32);

    // This declares intent for the injector to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(injector);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_command = b.addRunArtifact(injector);

    // Make sure that the working directory when the program is ran is the same one where the executable is located.
    run_command.setCwd(std.Build.LazyPath{ .cwd_relative = "./zig-out/bin" });

    // Stop Wine from spamming debug messages in the console when running the application.
    run_command.setEnvironmentVariable("WINEDEBUG", "-all");

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_command.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_command.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the injector");
    run_step.dependOn(&run_command.step);

    // Creates a step for testing. This only builds the test executable
    // but does not run it.
    const tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    tests.root_module.addImport("lib_c_time", lib_c_time);
    tests.root_module.addImport("win32", win32);
    tests.root_module.addImport("minhook", minhook);
    tests.linkLibrary(imgui_lib);
    tests.root_module.addImport("imgui", imgui);

    // This *creates* a Test step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const test_command = b.addRunArtifact(tests);

    // Stop Wine from spamming debug messages in the console when running tests.
    test_command.setEnvironmentVariable("WINEDEBUG", "-all");
    test_command.setEnvironmentVariable("DXVK_LOG_LEVEL", "error");
    test_command.setEnvironmentVariable("VKD3D_DEBUG", "err");
    // Stop vkd3d from caching shaders in a file when running tests.
    test_command.setEnvironmentVariable("VKD3D_SHADER_CACHE_PATH", "0");

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the tests.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&test_command.step);
}
