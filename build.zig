const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const is_macos = target.result.os.tag == .macos;
    switch (target.result.os.tag) {
        .windows => if (target.result.cpu.arch != .x86_64) return error.UnsupportedArchitecture,
        .macos => if (target.result.cpu.arch != .aarch64) return error.UnsupportedArchitecture,
        else => return error.UnsupportedOS,
    }
    const objc_dep = if (is_macos) b.lazyDependency("zig_objc", .{
        .target = target,
        .optimize = optimize,
    }) orelse return else null;
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
    const fracture = b.addModule("fracture", .{
        .root_source_file = b.path("src/fracture.zig"),
        .target = target,
        .optimize = optimize,
    });
    try addAudioDependencies(b, fracture);

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
    const entrypoint_path = if (is_macos)
        "testbed/entrypoint_macos.zig"
    else
        "testbed/entrypoint_win32.zig";
    const entrypoint = b.createModule(.{
        .root_source_file = b.path(entrypoint_path),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "fracture", .module = fracture },
        },
    });

    if (objc_dep) |dep| {
        entrypoint.addImport("objc", dep.module("objc"));
        entrypoint.linkFramework("AppKit", .{});
        entrypoint.linkFramework("CoreGraphics", .{});

        // zig-objc supplies the runtime bindings and SDK paths for linking.
        // Our CoreGraphics C calls and modifier masks need separate header
        // translation; translate-c does not inherit the imported module's paths.
        const sdk_path = std.zig.system.darwin.getSdk(
            b.allocator,
            b.graph.io,
            &target.result,
        ) orelse return error.MacOSSDKNotFound;
        const sdk_include = b.pathJoin(&.{ sdk_path, "usr/include" });
        const sdk_frameworks = b.pathJoin(&.{ sdk_path, "System/Library/Frameworks" });
        const headers = b.addWriteFiles();
        const cg_header = headers.add("macos-c.h",
            \\#include <CoreGraphics/CoreGraphics.h>
            \\#include <IOKit/hidsystem/IOLLEvent.h>
        );
        const cg = b.addTranslateC(.{
            .root_source_file = cg_header,
            .target = target,
            .optimize = optimize,
        });
        cg.addSystemIncludePath(.{ .cwd_relative = sdk_include });
        cg.addSystemFrameworkPath(.{ .cwd_relative = sdk_frameworks });
        entrypoint.addImport("macos-c", cg.createModule());
    }

    const exe = b.addExecutable(.{
        .name = "game",
        .root_module = entrypoint,
    });

    if (optimize == .fast and target.result.os.tag == .windows) {
        // NOTE(adi): Disables debug console on windows
        exe.subsystem = .windows;
    }

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.setCwd(b.path("."));
    run_step.dependOn(&run_cmd.step);

    // Keep an installed executable available alongside the development run.
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

    // A debug executable loads the game at startup, so `zig build run` needs
    // the installed library as well as the executable (on either platform).
    if (optimize == .debug) run_cmd.step.dependOn(&dll_step.step);
    if (is_macos) {
        const options = b.addOptions();
        // Track only the path so game rebuilds do not invalidate the executable.
        options.addOptionPathUntracked(
            "game_library_path",
            .{ .relative = .{ .base = .install_lib, .sub_path = "libdynamic_game.dylib" } },
        );
        entrypoint.addOptions("build_options", options);
    }
    const game_step = b.step("game", "Build the reloadable game library");
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
    const check = b.step(
        "check",
        "Check the selected app and game library without emitting binaries",
    );
    check.dependOn(&exe_check.step);
    check.dependOn(&dll_check.step);

    // ==================================== TESTS ==================================/
    const test_step = b.step(
        "test",
        "Run engine tests; check Windows audio tests",
    );
    const host_fracture = b.createModule(.{
        .root_source_file = b.path("src/fracture.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    const host_sound = b.createModule(.{
        .root_source_file = b.path("src/sound.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    try addAudioDependencies(b, host_fracture);
    try addAudioDependencies(b, host_sound);
    const sound_tests = b.addTest(.{ .name = "sound-tests", .root_module = host_sound });
    test_step.dependOn(&b.addRunArtifact(sound_tests).step);
    for ([_][]const u8{
        "src/software_renderer.zig",
        "src/windows/win32.zig",
        "src/wav.zig",
    }) |path| {
        const test_module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = b.graph.host,
            .optimize = optimize,
            .imports = &.{.{ .name = "fracture", .module = host_fracture }},
        });
        const host_tests = b.addTest(.{ .root_module = test_module });
        test_step.dependOn(&b.addRunArtifact(host_tests).step);
    }

    const windows_query = try std.Target.Query.parse(.{ .arch_os_abi = "x86_64-windows" });
    const windows_target = b.resolveTargetQuery(windows_query);
    const windows_sound = b.createModule(.{
        .root_source_file = b.path("src/sound.zig"),
        .target = windows_target,
        .optimize = optimize,
    });
    const audio_tests = b.addTest(.{
        .name = "audio-tests",
        .root_module = windows_sound,
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

fn addAudioDependencies(b: *std.Build, module: *std.Build.Module) !void {
    const target = module.resolved_target.?;
    if (target.result.os.tag != .macos) return;
    const sdk_path = std.zig.system.darwin.getSdk(
        b.allocator,
        b.graph.io,
        &target.result,
    ) orelse return error.MacOSSDKNotFound;
    const sdk_frameworks = b.pathJoin(&.{ sdk_path, "System/Library/Frameworks" });
    const header = b.addWriteFiles().add("audio-c.h",
        \\#include <AudioToolbox/AudioComponent.h>
        \\#include <AudioToolbox/AudioUnit.h>
    );
    const audio = b.addTranslateC(.{
        .root_source_file = header,
        .target = target,
        .optimize = module.optimize.?,
    });
    audio.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ sdk_path, "usr/include" }) });
    audio.addSystemFrameworkPath(.{ .cwd_relative = sdk_frameworks });
    module.addImport("audio-c", audio.createModule());
    module.addSystemFrameworkPath(.{ .cwd_relative = sdk_frameworks });
    module.linkFramework("AudioToolbox", .{});
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
