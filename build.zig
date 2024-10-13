const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // const platform = b.addModule("platform", .{
    //     .root_source_file = b.path("src/platform/platform.zig"),
    // });

    const core_lib = b.addModule("fr_core", .{
        .root_source_file = b.path("src/core/core.zig"),
        // .imports = &.{
        //     .{ .name = "platform", .module = platform },
        // },
    });

    const fracture = b.addModule("entrypoint", .{
        .root_source_file = b.path("src/fracture.zig"),
        .imports = &.{
            .{ .name = "fr_core", .module = core_lib },
            // .{ .name = "platform", .module = platform },
        },
    });

    const entrypoint = b.addModule("entrypoint", .{
        .root_source_file = b.path("src/entrypoint.zig"),
        .imports = &.{
            .{ .name = "fracture", .module = fracture },
            .{ .name = "fr_core", .module = core_lib },
            // .{ .name = "platform", .module = platform },
        },
    });

    const exe = b.addExecutable(.{
        .name = "game",
        .root_source_file = b.path("testbed/app.zig"),
        .target = target,
        .optimize = optimize,
        // .use_llvm = false,
        // .use_lld = false,
    });
    exe.root_module.addImport("entrypoint", entrypoint);
    exe.root_module.addImport("fracture", fracture);
    exe.root_module.addImport("fr_core", core_lib);
    // exe.root_module.addImport("platform", platform);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_check = b.addExecutable(.{
        .name = "game",
        .root_source_file = b.path("testbed/app.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_check.root_module.addImport("entrypoint", entrypoint);
    exe_check.root_module.addImport("fracture", fracture);
    exe_check.root_module.addImport("fr_core", core_lib);
    // exe_check.root_module.addImport("platform", platform);

    const check_step = b.step("check", "Check if the app compiles");
    check_step.dependOn(&exe_check.step);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = exe.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Copy documentation artifacts to prefix path");
    docs_step.dependOn(&install_docs.step);

    const platform_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/platform/platform.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_platform_unit_tests = b.addRunArtifact(platform_unit_tests);
    run_platform_unit_tests.has_side_effects = true;

    const core_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/core/core.zig"),
        .target = target,
        .optimize = optimize,
    });
    // core_unit_tests.root_module.addImport("platform", platform);

    const run_core_unit_tests = b.addRunArtifact(core_unit_tests);
    run_core_unit_tests.has_side_effects = true;

    const engine_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/unit_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    // engine_unit_tests.root_module.addImport("platform", platform);
    engine_unit_tests.root_module.addImport("fr_core", core_lib);

    const run_engine_unit_tests = b.addRunArtifact(engine_unit_tests);
    run_engine_unit_tests.has_side_effects = true;

    const game_unit_tests = b.addTest(.{
        .root_source_file = b.path("testbed/unit_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    game_unit_tests.root_module.addImport("entrypoint", entrypoint);
    game_unit_tests.root_module.addImport("fracture", fracture);
    game_unit_tests.root_module.addImport("fr_core", core_lib);

    const run_game_unit_tests = b.addRunArtifact(game_unit_tests);
    run_game_unit_tests.has_side_effects = true;
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_engine_unit_tests.step);
    test_step.dependOn(&run_game_unit_tests.step);
    test_step.dependOn(&run_platform_unit_tests.step);
    test_step.dependOn(&run_core_unit_tests.step);
}
