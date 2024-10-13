///! The application system contains the main loop of the application
///!
///! It owns the engine state and dispatches events
const core = @import("fr_core");
const platform = @import("platform/platform.zig");

const config = @import("config.zig");
const app_config = config.app_config;

pub const Application = @This();
platform_state: platform.PlatformState = undefined,
engine: core.Fracture = undefined,
frame_arena: std.heap.ArenaAllocator = undefined,
game_state: *anyopaque,

const ApplicationError =
    error{ ClientAppInit, FailedUpdate, FailedRender } || platform.PlatformError || std.mem.Allocator.Error || core.log.LoggerError;

pub fn init(allocator: std.mem.Allocator) ApplicationError!*Application {

    // Memory
    const app: *Application = try allocator.create(Application);

    app.engine.is_running = true;
    app.engine.is_suspended = false;

    // Logging
    try app.engine.core_log.stderr_init();
    errdefer app.engine.core_log.deinit();
    app.engine.core_log.info("Logging system has been initialized", .{});

    try app.engine.log.stderr_init();
    errdefer app.engine.log.deinit();
    app.engine.log.info("Logging system has been initialized", .{});

    // Platform
    try platform.init(
        &app.platform_state,
        app_config.application_name,
        app_config.window_pos.x,
        app_config.window_pos.y,
        app_config.window_pos.width,
        app_config.window_pos.height,
    );
    errdefer platform.deinit(&app.platform_state);
    app.engine.core_log.info("Platform layer has been initialized", .{});

    // Memory
    app.engine.memory.gpa.init(allocator);
    const arena_allocator = app.engine.memory.gpa.get_type_allocator(.frame_arena);
    if (comptime builtin.mode == .Debug) {
        app.engine.memory.gpa.memory_stats.current_memory[@intFromEnum(core.mem.EngineMemoryTag.application)] = @sizeOf(Application);
        app.engine.memory.gpa.memory_stats.current_total_memory = @sizeOf(Application);
        app.engine.memory.gpa.memory_stats.peak_total_memory = @sizeOf(Application);
        app.engine.memory.gpa.memory_stats.peak_memory[@intFromEnum(core.mem.EngineMemoryTag.application)] = @sizeOf(Application);
    }

    app.frame_arena = std.heap.ArenaAllocator.init(arena_allocator);
    app.engine.memory.frame_allocator.init(app.frame_arena.allocator());

    if (comptime app_config.frame_arena_preheat_bytes != 0) {
        _ = try app.engine.memory.frame_allocator.backing_allocator.alloc(u8, app_config.frame_arena_preheat_bytes);
        if (!app.frame_arena.reset(.retain_capacity)) {
            @setCold(true);
            app.engine.core_log.warn("Arena allocation failed to reset with retain capacity. It will hard reset", .{});
        }
        app.engine.core_log.info("Frame arena has been preheated with {d} bytes of memory", .{app_config.frame_arena_preheat_bytes});
    }
    app.engine.core_log.info("Memory has been initialized", .{});

    // Event
    try app.engine.event.init();
    errdefer app.engine.event.deinit();

    // Application
    app.game_state = config.app_api.init(&app.engine) orelse {
        @setCold(true);
        app.engine.core_log.fatal("Client application failed to initialize", .{});
        return ApplicationError.ClientAppInit;
    };

    app.engine.core_log.info("Client application has been initialized", .{});

    config.app_api.on_resize(&app.engine, app.game_state, app_config.window_pos.width, app_config.window_pos.height);
    app.engine.core_log.info("Application has been initialized", .{});

    return app;
}

pub fn deinit(self: *Application) void {

    // Application shutdown
    config.app_api.deinit(&self.engine, self.game_state);
    self.engine.core_log.info("Client application has been shutdown", .{});

    // Event shutdown
    self.engine.event.deinit();

    // Platform shutdown
    platform.deinit(&self.platform_state);
    self.engine.core_log.info("Platform layer has been shutdown", .{});

    // Memory Shutdown
    self.engine.memory.gpa.print_memory_stats(&self.engine.core_log);
    self.engine.memory.frame_allocator.print_memory_stats(&self.engine.core_log);

    // self.engine.memory.gpa.deinit();
    self.engine.memory.frame_allocator.deinit();
    self.frame_arena.deinit();
    self.engine.core_log.info("Context memory has been shutdown", .{});

    // Logging shutdown
    self.engine.core_log.info("Logging system is shutting down", .{});
    self.engine.log.deinit();
    self.engine.core_log.deinit();

    // Free application
    const appliation_allocator: std.mem.Allocator = self.engine.memory.gpa.get_type_allocator(.application);
    appliation_allocator.destroy(self);
}

pub fn run(self: *Application) ApplicationError!void {
    // debug_assert(initialized, @src(), "Trying to run application when none was created.", .{});
    var err: ?ApplicationError = null;

    self.engine.memory.gpa.print_memory_stats(&self.engine.core_log);
    const core_log = &self.engine.core_log;

    while (self.engine.is_running) {
        platform.pump_messages(&self.platform_state);

        // Clear the arena right before the loop stats but after the events are handled else we might be invalidating
        // some pointers.
        if (!self.frame_arena.reset(.retain_capacity)) {
            @setCold(true);
            core_log.warn("Arena allocation failed to reset with retain capacity. It will hard reset", .{});
        }
        self.engine.memory.frame_allocator.reset_stats();

        if (!self.engine.is_suspended) {
            if (!config.app_api.update(&self.engine, self.game_state)) {
                @setCold(true);
                core_log.fatal("Client app update failed, shutting down", .{});
                err = ApplicationError.FailedUpdate;
                break;
            }

            if (!config.app_api.render(&self.engine, self.game_state)) {
                @setCold(true);
                core_log.fatal("Client app render failed, shutting down", .{});
                err = ApplicationError.FailedRender;
                break;
            }
        }
        // break;
    }

    // In case the loop exited for some other reason
    self.engine.is_running = false;
    if (err) |e| {
        return e;
    }
}

const std = @import("std");
const builtin = @import("builtin");
