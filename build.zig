const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // ==================================== VULKAN ==================================/

    const registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml");
    // const shader_compiler = b.dependency("shader_compiler", .{
    //     .target = b.host,
    //     .optimize = .ReleaseFast,
    // }).artifact("shader_compiler");
    const vk_gen = b.dependency("vulkan", .{}).artifact("vulkan-zig-generator");
    const vk_generate_cmd = b.addRunArtifact(vk_gen);
    vk_generate_cmd.addFileArg(registry);

    // ================================== MODULES ==================================/
    const core_lib = b.addModule("fr_core", .{
        .root_source_file = b.path("src/core/fracture.zig"),
        .target = target,
        .optimize = optimize,
    });

    const vulkan = b.addModule("vulkan", .{
        .root_source_file = vk_generate_cmd.addOutputFileArg("vk.zig"),
        .target = target,
        .optimize = optimize,
    });
    vulkan.addLibraryPath(.{ .cwd_relative = "C:/Windows/System32/" });
    vulkan.addLibraryPath(.{ .cwd_relative = "C:/VulkanSDK/1.3.283.0/Lib/" });
    vulkan.linkSystemLibrary("vulkan-1", .{});

    const entrypoint = b.addModule("entrypoint", .{
        .root_source_file = b.path("src/entrypoint.zig"),
        .imports = &.{
            .{ .name = "fr_core", .module = core_lib },
            .{ .name = "vulkan", .module = vulkan },
        },
        .target = target,
        .optimize = optimize,
    });
    // entrypoint.addAnonymousImport("vulkan", .{
    //     .root_source_file = vk_generate_cmd.addOutputFileArg("vk.zig"),
    // });
    // entrypoint.addLibraryPath(.{ .cwd_relative = "C:/Windows/System32/" });
    // entrypoint.addLibraryPath(.{ .cwd_relative = "C:/VulkanSDK/1.3.283.0/Lib/" });
    // entrypoint.linkSystemLibrary("vulkan-1", .{});

    // ==================================== GAME ==================================/
    const exe = b.addExecutable(.{
        .name = "game",
        .root_source_file = b.path("testbed/app.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // exe.addLibraryPath(.{ .cwd_relative = "C:/VulkanSDK/1.3.283.0/Lib/" });
    // exe.addLibraryPath(.{ .cwd_relative = "C:/VulkanSDK/1.3.283.0/Include/" });
    // exe.addLibraryPath(.{ .cwd_relative = "C:/Windows/System32/" });
    // exe.linkSystemLibrary("vulkan-1");
    exe.root_module.addImport("entrypoint", entrypoint);
    exe.root_module.addImport("fr_core", core_lib);
    // exe.root_module.addAnonymousImport("vulkan", .{
    //     .root_source_file = vk_generate_cmd.addOutputFileArg("vk.zig"),
    // });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = exe.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Copy documentation artifacts to prefix path");
    docs_step.dependOn(&install_docs.step);

    // ==================================== GAME DLL ==================================/
    const game_dll = b.addSharedLibrary(.{
        .name = "game",
        .root_source_file = b.path("testbed/app.zig"),
        .target = target,
        .optimize = optimize,
    });
    game_dll.root_module.addImport("fr_core", core_lib);

    const dll_step = b.addInstallArtifact(game_dll, .{});

    const game_step = b.step("game", "Build the game as a dll");
    game_step.dependOn(&dll_step.step);

    // ==================================== CHECK STEP ==================================/
    const exe_check = b.addExecutable(.{
        .name = "testbed",
        .root_source_file = b.path("testbed/app.zig"),
        .target = target,
        .optimize = optimize,
    });
    // exe.addSystemIncludePath(.{ .cwd_relative = "C:/VulkanSDK/1.3.283.0/Include/" });
    // exe.addSystemIncludePath(.{ .cwd_relative = "C:/VulkanSDK/1.3.283.0/Lib/" });
    // exe.addSystemIncludePath(.{ .cwd_relative = "C:/Windows/System32/" });
    // exe.linkSystemLibrary("vulkan");
    exe_check.root_module.addImport("entrypoint", entrypoint);
    exe_check.root_module.addImport("fr_core", core_lib);

    const check_step = b.step("check", "Check if the app compiles");
    check_step.dependOn(&exe_check.step);
    // Tests
    const core_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/core/fracture.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ==================================== TESTS ==================================/

    const run_core_unit_tests = b.addRunArtifact(core_unit_tests);
    run_core_unit_tests.has_side_effects = true;

    const engine_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/unit_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    engine_unit_tests.root_module.addImport("fr_core", core_lib);

    const run_engine_unit_tests = b.addRunArtifact(engine_unit_tests);
    run_engine_unit_tests.has_side_effects = true;

    const game_unit_tests = b.addTest(.{
        .root_source_file = b.path("testbed/unit_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    game_unit_tests.root_module.addImport("fr_core", core_lib);

    const run_game_unit_tests = b.addRunArtifact(game_unit_tests);
    run_game_unit_tests.has_side_effects = true;
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_engine_unit_tests.step);
    test_step.dependOn(&run_game_unit_tests.step);
    test_step.dependOn(&run_core_unit_tests.step);
}
