const std = @import("std");

pub fn build(b: *std.Build) !void {
    const query = try std.Target.Query.parse(.{
        .cpu_features = "x86_64-avx512f",
    });
    const target = b.standardTargetOptions(.{
        .default_target = query,
    });
    const optimize = b.standardOptimizeOption(.{});
    // ==================================== VULKAN ==================================/

    const registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml");
    const vulkan = b.dependency("vulkan", .{
        .registry = registry,
    }).module("vulkan-zig");

    // ====================================== Shader Compile =======================/

    // const shader_compiler = b.dependency("shader_compiler", .{
    //     .target = b.graph.host,
    //     .optimize = .ReleaseFast,
    // }).artifact("shader_compiler");

    // ================================== MODULES ==================================/
    const entrypoint = b.createModule(.{
        .root_source_file = b.path("src/entrypoint_win32.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "vulkan", .module = vulkan },
        },
    });

    // ==================================== GAME ==================================/
    const game = b.addExecutable(
        .{
            .name = "game",
            .root_module = entrypoint,
        },
    );

    if (optimize == .ReleaseFast and target.query.os_tag == .windows) {
        // NOTE(adi): Disables debug console on windows
        game.subsystem = .Windows;
    }

    b.installArtifact(game);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(game);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // ==================================== GAME DLL ==================================/
    // ==================================== CHECK STEP ==================================/
    const exe_check = b.addExecutable(.{
        .name = "check",
        .root_module = entrypoint,
    });
    const check = b.step("check", "Check if the app compiles");
    check.dependOn(&exe_check.step);

    // ==================================== TESTS ==================================/
}

// fn compile_shader(
//     b: *std.Build,
//     optimize: std.builtin.OptimizeMode,
//     shader_compiler: *std.Build.Step.Compile,
//     src: std.Build.LazyPath,
//     out_name: []const u8,
// ) std.Build.LazyPath {
//     const artifact = b.addRunArtifact(shader_compiler);
//     artifact.addArgs(&.{ "--target", "Vulkan-1.3" });
//     switch (optimize) {
//         .Debug => artifact.addArgs(&.{"--robust-access"}),
//         .ReleaseSafe => artifact.addArgs(&.{ "--optimize-perf", "--robust-access" }),
//         .ReleaseFast => artifact.addArgs(&.{"--optimize-perf"}),
//         .ReleaseSmall => artifact.addArgs(&.{ "--optimize-perf", "--optimize-small" }),
//     }
//     artifact.addFileArg(src);
//     return artifact.addOutputFileArg(out_name);
// }
