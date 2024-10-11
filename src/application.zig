///! The application system contains the main loop of the application
///!
///! It owns the engine state and dispatches events
const core = @import("fr_core");
const core_log = core.logging.core_log;
const debug_assert = core.asserts.debug_assert_msg;
const platform = @import("platform");

const config = @import("config.zig");
const app_config = config.app_config;

const types = @import("types.zig");

// -------------------------------------------- Application Types ------------------------------------------------/

const AppState = struct {
    context: types.AppContext,
    frame_arena: std.heap.ArenaAllocator,
    platform_state: platform.PlatformState,
    is_suspended: bool,
    is_running: bool,
    width: i32,
    height: i32,
    last_time: f64,
};
const ApplicationError = error{ ClientAppInit, FailedUpdate, FailedRender } || platform.PlatformError;

// -------------------------------------------- Application Abstraction -------------------------------------------/

var initialized: bool = false;
var app_state: AppState = undefined;

pub fn init(allocator: std.mem.Allocator) ApplicationError!void {
    debug_assert(!initialized, @src(), "Trying to reinitialize application. There can only ever be 1.", .{});

    app_state.is_running = true;
    app_state.is_suspended = false;

    try platform.init(
        &app_state.platform_state,
        app_config.application_name,
        app_config.window_pos.x,
        app_config.window_pos.y,
        app_config.window_pos.width,
        app_config.window_pos.height,
    );
    core_log.info("Platform layer has been initialized", .{});

    app_state.context.gpa = types.GPA{};
    app_state.context.gpa.init(allocator);
    const arena_allocator = app_state.context.gpa.get_type_allocator(.frame_arena);

    app_state.frame_arena = std.heap.ArenaAllocator.init(arena_allocator);
    app_state.context.frame_allocator = types.FrameArena{};
    app_state.context.frame_allocator.init(app_state.frame_arena.allocator());

    if (!config.app_api.init(&app_state.context)) {
        core_log.fatal("Client application failed to initialize", .{});
        return ApplicationError.ClientAppInit;
    }

    core_log.info("Client application has been initialized", .{});

    config.app_api.on_resize(&app_state.context, app_config.window_pos.width, app_config.window_pos.height);
    core_log.info("Application has been initialized", .{});
    initialized = true;
}

pub fn deinit() void {
    debug_assert(initialized, @src(), "Trying to deinit application when none was created.", .{});
    config.app_api.deinit(&app_state.context);
    core_log.info("Client application has been shutdown", .{});

    platform.deinit(&app_state.platform_state);
    core_log.info("Platform layer has been shutdown", .{});

    app_state.context.gpa.print_memory_stats();
    app_state.context.frame_allocator.print_memory_stats();

    app_state.context.gpa.deinit();
    app_state.context.frame_allocator.deinit();
    app_state.frame_arena.deinit();
    core_log.info("Context memory has been shutdown", .{});

    initialized = false;
}

pub fn run() ApplicationError!void {
    debug_assert(initialized, @src(), "Trying to run application when none was created.", .{});
    var err: ?ApplicationError = null;

    app_state.context.gpa.print_memory_stats();

    while (app_state.is_running) {
        if (!app_state.frame_arena.reset(.retain_capacity)) {
            @setCold(true);
            core_log.warn("Arena allocation failed to reset with retain capacity. It will hard reset", .{});
        }
        app_state.context.frame_allocator.reset_stats();

        platform.pump_messages(&app_state.platform_state);

        if (!app_state.is_suspended) {
            if (!config.app_api.update(&app_state.context, 0.0)) {
                @setCold(true);
                core_log.fatal("Client app update failed, shutting down", .{});
                err = ApplicationError.FailedUpdate;
                break;
            }

            if (!config.app_api.render(&app_state.context, 0.0)) {
                @setCold(true);
                core_log.fatal("Client app render failed, shutting down", .{});
                err = ApplicationError.FailedRender;
                break;
            }
        }
    }

    // In case the loop exited for some other reason
    app_state.is_running = false;
    if (err) |e| {
        return e;
    }
}

const std = @import("std");
