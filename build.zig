const std = @import("std");

pub fn build(b: *std.Build) !void {
    // The testbed is Windows-only, including when checking it from another host OS.
    const query = try std.Target.Query.parse(.{
        .arch_os_abi = "x86_64-windows",
        // .cpu_features = "x86_64-avx512f",
    });
    const target = b.standardTargetOptions(.{
        .default_target = query,
    });
    const optimize = b.standardOptimizeOption(.{});
    // ==================================== VULKAN ==================================/

    // const registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml");
    // const vulkan = b.dependency("vulkan", .{
    //     .registry = registry,
    // }).module("vulkan-zig");

    // ====================================== Shader Compile =======================/

    // const shader_compiler = b.dependency("shader_compiler", .{
    //     .target = b.graph.host,
    //     .optimize = .fast,
    // }).artifact("shader_compiler");

    // ================================== MODULES ==================================/
    const fracture = b.createModule(.{
        .root_source_file = b.path("src/fracture.zig"),
        .target = target,
        .optimize = optimize,
    });

    // TODO(adi): Import the module from a build file within the game folder
    // const game = b.createModule(.{
    //     .root_source_file = b.path("testbed/game.zig"),
    //     .target = target,
    //     .optimize = optimize,
    //     .imports = &.{
    //         .{ .name = "fracture", .module = fracture },
    //     },
    // });

    // ==================================== GAME ==================================/
    const entrypoint = b.createModule(.{
        .root_source_file = b.path("testbed/entrypoint_win32.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "fracture", .module = fracture },
            // .{ .name = "game", .module = game },
        },
    });

    const exe = b.addExecutable(
        .{
            .name = "game",
            .root_module = entrypoint,
        },
    );

    if (optimize == .fast and target.result.os.tag == .windows) {
        // NOTE(adi): Disables debug console on windows
        exe.subsystem = .windows;
    }

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.addPassthruArgs();

    // ==================================== GAME DLL ==================================/

    const dll_module = b.addModule("dynamic_game", .{
        .root_source_file = b.path("testbed/debug_dll.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "fracture", .module = fracture },
        },
    });
    const game_dll = b.addLibrary(.{
        .name = "dynamic_game",
        .linkage = .dynamic,
        .root_module = dll_module,
    });

    const dll_step = b.addInstallArtifact(game_dll, .{});

    const game_step = b.step("game", "Build the game as a dll");
    game_step.dependOn(&dll_step.step);
    // ==================================== CHECK STEP ==================================/
    const exe_check = b.addExecutable(.{
        .name = "check",
        .root_module = entrypoint,
    });
    exe_check.subsystem = exe.subsystem;
    const dll_check = b.addLibrary(.{
        .name = "check_dynamic_game",
        .linkage = .dynamic,
        .root_module = dll_module,
    });
    const check = b.step("check", "Check the Windows app and game DLL without emitting binaries");
    check.dependOn(&exe_check.step);
    check.dependOn(&dll_check.step);

    // ==================================== TESTS ==================================/
    const test_step = b.step("test", "Run portable tests and check Windows audio tests");
    for ([_][]const u8{ "src/software_renderer.zig", "src/windows/win32.zig" }) |path| {
        const host_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = b.graph.host,
                .optimize = optimize,
            }),
        });
        test_step.dependOn(&b.addRunArtifact(host_tests).step);
    }

    const audio_tests = b.addTest(.{
        .name = "audio-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/windows/xaudio2.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    check.dependOn(&audio_tests.step);
    if (b.graph.host.result.os.tag == .windows and target.result.os.tag == .windows and
        b.graph.host.result.cpu.arch == target.result.cpu.arch)
    {
        test_step.dependOn(&b.addRunArtifact(audio_tests).step);
    } else {
        test_step.dependOn(&audio_tests.step);
    }
}

// fn compile_shader(
//     b: *std.Build,
//     optimize: std.lang.Optimize,
//     shader_compiler: *std.Build.Step.Compile,
//     src: std.Build.LazyPath,
//     out_name: []const u8,
// ) std.Build.LazyPath {
//     const artifact = b.addRunArtifact(shader_compiler);
//     artifact.addArgs(&.{ "--target", "Vulkan-1.3" });
//     switch (optimize) {
//         .debug => artifact.addArgs(&.{"--robust-access"}),
//         .safe => artifact.addArgs(&.{ "--optimize-perf", "--robust-access" }),
//         .fast => artifact.addArgs(&.{"--optimize-perf"}),
//         .small => artifact.addArgs(&.{ "--optimize-perf", "--optimize-small" }),
//     }
//     artifact.addFileArg(src);
//     return artifact.addOutputFileArg(out_name);
// }
