const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const fracture = b.addModule("entrypoint", .{
        .root_source_file = b.path("src/fracture.zig"),
    });

    const entrypoint = b.addModule("entrypoint", .{
        .root_source_file = b.path("src/entrypoint.zig"),
        .imports = &.{.{ .name = "fracture", .module = fracture }},
    });

    const exe = b.addExecutable(.{
        .name = "game",
        .root_source_file = b.path("testbed/app.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("entrypoint", entrypoint);
    exe.root_module.addImport("fracture", fracture);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const engine_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/unit_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_engine_unit_tests = b.addRunArtifact(engine_unit_tests);
    run_engine_unit_tests.has_side_effects = true;

    const game_unit_tests = b.addTest(.{
        .root_source_file = b.path("testbed/unit_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_game_unit_tests = b.addRunArtifact(game_unit_tests);
    run_game_unit_tests.has_side_effects = true;
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_engine_unit_tests.step);
    test_step.dependOn(&run_game_unit_tests.step);
}
