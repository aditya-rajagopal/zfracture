const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    switch (target.result.os.tag) {
        .windows => if (target.result.cpu.arch != .x86_64) return error.UnsupportedArchitecture,
        .macos => if (target.result.cpu.arch != .aarch64) return error.UnsupportedArchitecture,
        else => return error.UnsupportedOS,
    }
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
    try addPlatformDependencies(b, fracture);

    // ==================================== TESTBED ==================================/
    const entrypoint = b.createModule(.{
        .root_source_file = b.path("testbed/entrypoint.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "fracture", .module = fracture },
        },
    });

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

    // ==================================== CHECK STEP ==================================/
    const exe_check = b.addExecutable(.{
        .name = "check",
        .root_module = entrypoint,
    });
    exe_check.subsystem = exe.subsystem;
    const check = b.step(
        "check",
        "Check the testbed and tests without running them",
    );
    check.dependOn(&exe_check.step);

    // ==================================== TESTS ==================================/
    const test_step = b.step(
        "test",
        "Run engine tests; check Windows audio tests",
    );
    const native_target = target.result.os.tag == b.graph.host.result.os.tag and
        target.result.cpu.arch == b.graph.host.result.cpu.arch;
    const host_sound = b.createModule(.{
        .root_source_file = b.path("src/sound.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    try addAudioDependencies(b, host_sound);
    const sound_tests = b.addTest(.{ .name = "sound-tests", .root_module = host_sound });
    check.dependOn(&sound_tests.step);
    test_step.dependOn(&b.addRunArtifact(sound_tests).step);
    for ([_][]const u8{
        "src/software_renderer.zig",
        "src/wav.zig",
        "src/stdx/png.zig",
    }) |path| {
        // Native platform-tests already includes the renderer test.
        if (native_target and std.mem.eql(u8, path, "src/software_renderer.zig")) continue;
        const test_module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = b.graph.host,
            .optimize = optimize,
        });
        const host_tests = b.addTest(.{ .root_module = test_module });
        check.dependOn(&host_tests.step);
        test_step.dependOn(&b.addRunArtifact(host_tests).step);
    }

    const window_smoke = b.option(bool, "macos-window-smoke", "Run native macOS window tests (requires a desktop)") orelse false;
    const platform_module = b.createModule(.{
        .root_source_file = b.path("src/platform.zig"),
        .target = target,
        .optimize = optimize,
    });
    try addPlatformDependencies(b, platform_module);
    const platform_options = b.addOptions();
    platform_options.addOption(bool, "window_smoke", window_smoke);
    platform_module.addOptions("test_options", platform_options);
    const platform_tests = b.addTest(.{ .name = "platform-tests", .root_module = platform_module });
    check.dependOn(&platform_tests.step);
    test_step.dependOn(&platform_tests.step);
    if (native_target) {
        test_step.dependOn(&b.addRunArtifact(platform_tests).step);
    }

    if (b.graph.host.result.os.tag != .windows or b.graph.host.result.cpu.arch != .x86_64) {
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
        test_step.dependOn(&audio_tests.step);
    }
}

fn addPlatformDependencies(b: *std.Build, module: *std.Build.Module) !void {
    const target = module.resolved_target.?;
    if (target.result.os.tag != .macos) return;
    const dep = b.lazyDependency("zig_objc", .{
        .target = target,
        .optimize = module.optimize.?,
    }) orelse return;
    module.addImport("objc", dep.module("objc"));
    module.linkFramework("AppKit", .{});
    module.linkFramework("CoreGraphics", .{});

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
        .optimize = module.optimize.?,
    });
    cg.addSystemIncludePath(.{ .cwd_relative = sdk_include });
    cg.addSystemFrameworkPath(.{ .cwd_relative = sdk_frameworks });
    module.addImport("macos-c", cg.createModule());
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
