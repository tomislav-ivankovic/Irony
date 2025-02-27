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

    // ZIG Dependencies:
    const win32 = b.dependency("zigwin32", .{}).module("zigwin32");

    // C dependency: minhook
    const minhook = b.dependency("minhook", .{});
    const minhook_include_path = minhook.path("include");
    const minhook_source_files = std.Build.Module.AddCSourceFilesOptions{
        .root = .{
            .dependency = .{
                .dependency = minhook,
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
    };

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
    dll.addIncludePath(minhook_include_path);
    dll.addCSourceFiles(minhook_source_files);

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
    tests.root_module.addImport("win32", win32);
    tests.addIncludePath(minhook_include_path);
    tests.addCSourceFiles(minhook_source_files);

    // This *creates* a Test step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const test_command = b.addRunArtifact(tests);

    // Stop Wine from spamming debug messages in the console when running tests.
    test_command.setEnvironmentVariable("WINEDEBUG", "-all");

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the tests.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&test_command.step);
}
