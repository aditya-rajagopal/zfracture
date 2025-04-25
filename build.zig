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
    const vk_gen = b.dependency("vulkan", .{}).artifact("vulkan-zig-generator");
    const vk_generate_cmd = b.addRunArtifact(vk_gen);
    vk_generate_cmd.addFileArg(registry);

    // ====================================== Shader Compile =======================/

    const shader_compiler = b.dependency("shader_compiler", .{
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    }).artifact("shader_compiler");

    // ================================== MODULES ==================================/
    const math_lib = b.addModule("fr_math", .{
        .root_source_file = b.path("src/core/math/math.zig"),
        .target = target,
        .optimize = optimize,
    });
    const core_lib = b.addModule("fracture", .{
        .root_source_file = b.path("src/core/fracture.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "fr_math", .module = math_lib },
        },
    });

    const vulkan = b.addModule("vulkan", .{
        .root_source_file = vk_generate_cmd.addOutputFileArg("vk.zig"),
        .target = target,
        .optimize = optimize,
    });

    const shaders = b.addModule("shaders", .{
        .root_source_file = b.path("src/renderer/shaders.zig"),
        .target = target,
        .optimize = optimize,
    });

    shaders.addAnonymousImport(
        "builtin.MaterialShader.vert",
        .{ .root_source_file = compile_shader(
            b,
            optimize,
            shader_compiler,
            b.path("assets/shaders/builtin.MaterialShader.vert"),
            "assets/shaders/builtin.MaterialShader.vert.spv",
        ) },
    );
    shaders.addAnonymousImport(
        "builtin.MaterialShader.frag",
        .{ .root_source_file = compile_shader(
            b,
            optimize,
            shader_compiler,
            b.path("assets/shaders/builtin.MaterialShader.frag"),
            "assets/shaders/builtin.MaterialShader.frag.spv",
        ) },
    );
    const vulkan_backend = b.addModule(
        "vulkan_backend",
        .{
            .root_source_file = b.path("src/renderer/vulkan/context.zig"),
            .imports = &.{
                .{ .name = "fr_core", .module = core_lib },
                .{ .name = "vulkan", .module = vulkan },
                .{ .name = "shaders", .module = shaders },
            },
            .target = target,
            .optimize = optimize,
        },
    );

    const entrypoint = b.addModule("entrypoint", .{
        .root_source_file = b.path("src/entrypoint.zig"),
        .imports = &.{
            .{ .name = "fr_core", .module = core_lib },
            .{ .name = "vulkan_backend", .module = vulkan_backend },
        },
        .target = target,
        .optimize = optimize,
    });

    // ==================================== GAME ==================================/
    const exe = b.addExecutable(.{
        .name = "game",
        .root_source_file = b.path("testbed/app.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("entrypoint", entrypoint);
    exe.root_module.addImport("fr_core", core_lib);
    exe.root_module.addImport("vulkan_backend", vulkan_backend);

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
    const dll_module = b.addModule("dynamic_game", .{
        .root_source_file = b.path("testbed/app.zig"),
        .target = target,
        .optimize = optimize,
    });
    const game_dll = b.addLibrary(.{
        .name = "dynamic_game",
        .linkage = .dynamic,
        .root_module = dll_module,
    });
    game_dll.root_module.addImport("fr_core", core_lib);
    game_dll.root_module.addImport("vulkan_backend", vulkan_backend);

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
    exe_check.root_module.addImport("entrypoint", entrypoint);
    exe_check.root_module.addImport("fr_core", core_lib);
    exe_check.root_module.addImport("vulkan_backend", vulkan_backend);

    const check_step = b.step("check", "Check if the app compiles");
    check_step.dependOn(&exe_check.step);

    // ==================================== TESTS ==================================/
    const core_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/core/fracture.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_core_unit_tests = b.addRunArtifact(core_unit_tests);
    run_core_unit_tests.has_side_effects = true;

    const engine_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/unit_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    engine_unit_tests.root_module.addImport("fr_core", core_lib);
    engine_unit_tests.root_module.addImport("vulkan", vulkan);
    engine_unit_tests.root_module.addImport("shaders", shaders);

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

    const test_temp = b.addTest(.{
        .root_source_file = b.path("src/core/fracture_structure_notation/parser.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_temp.root_module.addImport("fr_math", math_lib);

    var run_temp_test = b.addRunArtifact(test_temp);
    run_temp_test.has_side_effects = true;

    const test_temp_step = b.step("test_temp", "Run a temp test with the math module imported");
    test_temp_step.dependOn(&run_temp_test.step);
}

fn compile_shader(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    shader_compiler: *std.Build.Step.Compile,
    src: std.Build.LazyPath,
    out_name: []const u8,
) std.Build.LazyPath {
    const artifact = b.addRunArtifact(shader_compiler);
    artifact.addArgs(&.{ "--target", "Vulkan-1.3" });
    switch (optimize) {
        .Debug => artifact.addArgs(&.{"--robust-access"}),
        .ReleaseSafe => artifact.addArgs(&.{ "--optimize-perf", "--robust-access" }),
        .ReleaseFast => artifact.addArgs(&.{"--optimize-perf"}),
        .ReleaseSmall => artifact.addArgs(&.{ "--optimize-perf", "--optimize-small" }),
    }
    artifact.addFileArg(src);
    return artifact.addOutputFileArg(out_name);
}
