///! The application system contains the main loop of the application
///!
///! It owns the engine state and dispatches events
// TODO:
//      - [ ] Should i replace the frame arena by a fixed buffer allocator that is defined by asking the application
//            how much memory it needs at startup and give it that much memory to work with forever. Instead of an arena
const std = @import("std");
const builtin = @import("builtin");

const core = @import("fr_core");

const config = @import("config.zig");
const app_config = config.app_config;
const platform = @import("platform/platform.zig");

/// Struct for storing the game DLL instance and last modified timestamp
const DLL = switch (builtin.mode) {
    .Debug => struct {
        instance: std.DynLib,
        time_stamp: i128 align(8),
    },
    else => void,
};

/// The type for the logging system used by the engine internal
const EngineLog = core.log.ScopedLogger(core.log.default_log, .ENGINE, core.log.default_level);

pub const Application = @This();
/// The engine state that is passed to the game for use in systems. The engine internal owns the state memory
/// to allow the game to be reloaded. All fracture systems are designed to not have any internal state and accept a pointer
/// to the data that controls behaviour. These states live in the fracture structure.
///
/// see :Fracture
engine: core.Fracture = undefined,
/// Private engine log
log: EngineLog,
/// The state for the platform layer
platform_state: platform.PlatformState = undefined,

/// A pointer to the game state that is defined by and manipulated by the game but owned by the engine. The game
/// must initialize this state and allocate it based on its requirements using the allocators provided by the engine.
/// This allows the game to be reloaded without requiring an engine and game restart. To ensure this the game/application should
/// ensure it does not have any internal state that is not owned by the engine.
game_state: *anyopaque,
/// The game api that is required by the engine to run the application
api: core.API,
/// In debug mode to reference the DLL
dll: DLL,
/// The frame memory reference
frame_memory: []u8,
/// The arnea that is refreshed each frame.
frame_arena: std.heap.FixedBufferAllocator = undefined,
/// engine clock
timer: std.time.Timer,

var game_api: core.API = undefined;

const ApplicationError =
    error{ ClientAppInit, FailedUpdate, FailedRender, DLLLoadFailed } ||
    platform.PlatformError ||
    std.mem.Allocator.Error ||
    core.log.LoggerError ||
    std.fs.File.OpenError ||
    std.fs.File.StatError ||
    core.Renderer.Error;

pub fn init(allocator: std.mem.Allocator) ApplicationError!*Application {
    var start = std.time.Timer.start() catch unreachable;

    // NOTE: Allocate application state
    const app: *Application = try allocator.create(Application);
    errdefer allocator.destroy(app);

    app.engine.is_running = false;
    app.engine.is_suspended = false;

    // NOTE: Game API
    switch (builtin.mode) {
        .Debug => {
            const file: std.fs.File = try std.fs.cwd().openFile(config.dll_name, .{});
            const stats = try file.stat();
            file.close();
            app.dll.time_stamp = stats.mtime;
            if (!app.reload_library()) {
                return error.DLLLoadFailed;
            }
        },
        else => {
            game_api = config.app_api;
        },
    }

    // NOTE: Init Logging
    app.engine.log_config.init();
    try app.engine.log_config.stdout_init();
    // try app.engine.log_config.file_init();
    errdefer app.engine.log_config.deinit();

    app.log = EngineLog.init(&app.engine.log_config);

    app.log.info("Logging system has been initialized", .{});

    // NOTE: Event System
    try app.engine.event.init();
    errdefer app.engine.event.deinit();

    // NOTE: Init Platform
    try platform.init(
        app,
        &app.platform_state,
        app_config.application_name,
        app_config.window_pos.x,
        app_config.window_pos.y,
        app_config.window_pos.width,
        app_config.window_pos.height,
    );
    errdefer platform.deinit(&app.platform_state);
    app.log.info("Platform layer has been initialized", .{});

    // NOTE: Memory
    app.engine.memory.gpa.init(allocator, &app.engine.log_config);
    if (comptime builtin.mode == .Debug) {
        // NOTE: Tracking the allocation of the application
        app.engine.memory.gpa.memory_stats.current_memory[@intFromEnum(core.EngineMemoryTag.application)] = @sizeOf(Application);
        app.engine.memory.gpa.memory_stats.current_total_memory = @sizeOf(Application);
        app.engine.memory.gpa.memory_stats.peak_total_memory = @sizeOf(Application);
        app.engine.memory.gpa.memory_stats.peak_memory[@intFromEnum(core.EngineMemoryTag.application)] = @sizeOf(Application);
    }

    // NOTE: Init frame arena
    const frame_allocator = app.engine.memory.gpa.get_type_allocator(.frame_arena);
    const preheat_bytes = comptime app_config.frame_arena_preheat_size.as_bytes();
    app.frame_memory = try frame_allocator.alloc(u8, preheat_bytes);

    app.frame_arena = std.heap.FixedBufferAllocator.init(app.frame_memory);
    app.engine.memory.frame_allocator.init(app.frame_arena.allocator(), &app.engine.log_config);

    app.log.info("Memory has been initialized", .{});
    errdefer frame_allocator.free(app.frame_memory);

    // NOTE: Input System
    app.engine.input.init();

    // NOTE: Renderer
    const renderer_allocator = app.engine.memory.gpa.get_type_allocator(.renderer);
    try app.engine.renderer.init(
        renderer_allocator,
        app_config.application_name,
        &app.platform_state,
        &app.engine.log_config,
        &app.engine.extent,
    );
    errdefer app.engine.renderer.deinit();
    app.log.info("Renderer initialized", .{});

    // NOTE: Client application
    app.log.debug("Engine address: {*}\n", .{&app.engine});
    app.game_state = game_api.init(&app.engine) orelse {
        @branchHint(.cold);
        app.log.fatal("Client application failed to initialize", .{});
        return ApplicationError.ClientAppInit;
    };

    app.log.info("Client application has been initialized", .{});

    // NOTE: Call the game's on_resize callback to allow teh game to make resolution related decisions before the
    // game loop starts
    game_api.on_resize(&app.engine, app.game_state, app_config.window_pos.width, app_config.window_pos.height);
    const end = start.read();

    app.log.info("Engine has been initialized in {s}", .{std.fmt.fmtDuration(end)});
    app.engine.is_running = true;
    return app;
}

pub fn deinit(self: *Application) void {

    // Application shutdown
    game_api.deinit(&self.engine, self.game_state);
    self.log.info("Client application has been shutdown", .{});

    // Renderer shutdown
    self.engine.renderer.deinit();
    self.log.info("Renderer has been shutdown", .{});

    // Platform shutdown
    platform.deinit(&self.platform_state);
    self.log.info("Platform layer has been shutdown", .{});

    // Memory Shutdown
    self.engine.memory.frame_allocator.print_memory_stats();
    self.engine.memory.frame_allocator.deinit();
    // Free the memory backing for the linear allocator
    const frame_allocator = self.engine.memory.gpa.get_type_allocator(.frame_arena);
    frame_allocator.free(self.frame_memory);
    self.engine.memory.gpa.print_memory_stats();
    self.engine.memory.gpa.deinit();
    self.log.info("Context memory has been shutdown", .{});

    // Event shutdown
    self.engine.event.deinit();

    // Logging shutdown
    self.log.info("Logging system is shutting down", .{});
    self.engine.log_config.deinit();

    // Free application
    const appliation_allocator: std.mem.Allocator = self.engine.memory.gpa.get_type_allocator(.application);
    appliation_allocator.destroy(self);
}

pub fn run(self: *Application) ApplicationError!void {
    var err: ?ApplicationError = null;

    self.engine.memory.gpa.print_memory_stats();
    const core_log = &self.log;

    // NOTE(aditya): This cannot fail on windows
    self.timer = std.time.Timer.start() catch unreachable;
    var delta_time: u64 = 0;
    var frame_time: u64 = 0;
    var dll_time: u64 = 0;
    var frame_count: u64 = 0;
    var last_frame_count: u64 = 0;

    var end = self.timer.lap();

    const frame_rate_interval = 2 * std.time.ns_per_s;
    const dll_update_interval = @divFloor(std.time.ns_per_s, 30);
    var current_frame_rate: f32 = 0.0;

    while (self.engine.is_running) {
        platform.pump_messages(&self.platform_state);

        // NOTE: Clear the arena right before the loop stats but after the events are handled else we might be invalidating
        // some pointers.
        self.frame_arena.reset();

        self.engine.memory.frame_allocator.reset_stats();

        if (!self.engine.is_suspended) {
            @branchHint(.likely);
            if (self.engine.renderer.begin_frame(self.engine.delta_time)) {
                @branchHint(.likely);
                if (!game_api.update_and_render(&self.engine, self.game_state)) {
                    @branchHint(.cold);
                    core_log.fatal("Client app update failed, shutting down", .{});
                    err = ApplicationError.FailedUpdate;
                    break;
                }

                if (!self.engine.renderer.end_frame(self.engine.delta_time)) {
                    @branchHint(.cold);
                    self.engine.is_running = false;
                    continue;
                }
            }
        }

        if (self.engine.input.key_pressed_this_frame(.KEY_2)) {
            self.log.err("Frame rate: {d}", .{current_frame_rate});
        }
        // NOTE: Update the input states
        self.engine.input.update();

        if (!self.engine.is_suspended) {
            @branchHint(.likely);
            delta_time += end;
            frame_time += end;
            dll_time += end;
            frame_count += 1;

            if (delta_time > dll_update_interval) {
                switch (builtin.mode) {
                    .Debug => {
                        const file: std.fs.File = std.fs.cwd().openFile(config.dll_name, .{}) catch {
                            continue;
                        };
                        const stats = try file.stat();
                        file.close();
                        if (self.dll.time_stamp != stats.mtime) {
                            self.log.debug("new dll detected", .{});
                            self.dll.time_stamp = stats.mtime;
                            self.dll.instance.close();
                            _ = self.reload_library();
                        }
                    },
                    else => {},
                }
                dll_time = 0;
            }

            if (frame_time > frame_rate_interval) {
                current_frame_rate = @as(f32, @floatFromInt(frame_count - last_frame_count)) / @as(f32, @floatFromInt(frame_time));
                current_frame_rate *= @as(f32, @floatFromInt(std.time.ns_per_s));
                frame_time = 0;
                last_frame_count = frame_count;
            }
        }

        end = self.timer.lap();
        const ns_to_s: f32 = 1.0 / @as(f32, @floatFromInt(std.time.ns_per_s));
        self.engine.delta_time = @as(f32, @floatFromInt(end)) * ns_to_s;
    }

    var dt: f64 = @floatFromInt(delta_time);
    dt /= std.time.ns_per_s;
    const float_count: f64 = @floatFromInt(frame_count);
    self.log.debug("Avg Delta_time: {d}, FPS: {d}f/s", .{ std.fmt.fmtDuration(@divTrunc(delta_time, frame_count)), float_count / dt });

    // NOTE: In case the loop exited for some other reason
    self.engine.is_running = false;
    if (err) |e| {
        return e;
    }
}

pub fn on_event(self: *Application, comptime event_code: core.Event.EventCode, event_data: core.Event.EventData) void {
    switch (event_code) {
        .APPLICATION_QUIT => {
            _ = self.engine.event.fire(.APPLICATION_QUIT, &self.engine, event_data);
            self.engine.is_running = false;
        },
        .WINDOW_RESIZE => {
            const window_resize_data: core.Event.WindowResizeEventData = @bitCast(event_data);
            const w = window_resize_data.size.width;
            const h = window_resize_data.size.height;
            if (self.engine.extent.width != w or self.engine.extent.height != h) {
                self.engine.extent.width = w;
                self.engine.extent.height = h;
                if (w == 0 or h == 0) {
                    self.log.info("Application has been minimized/suspended\n", .{});
                    self.engine.is_suspended = true;
                    return;
                } else {
                    if (self.engine.is_suspended) {
                        self.log.info("Application has been restored\n", .{});
                        self.engine.is_suspended = false;
                    }

                    if (self.engine.is_running) {
                        _ = self.engine.event.fire(.WINDOW_RESIZE, &self.engine, event_data);
                        self.engine.renderer.on_resize(self.engine.extent);
                        game_api.on_resize(&self.engine, self.game_state, self.engine.extent.width, self.engine.extent.height);
                    }
                }
            }
        },
        else => {},
    }
}

fn reload_library(self: *Application) bool {
    const new_name = config.dll_name ++ "_tmp";
    if (!platform.copy_file(config.dll_name, new_name, true)) {
        return false;
    }

    self.dll.instance = std.DynLib.open(new_name) catch return false;
    const init_fn = self.dll.instance.lookup(core.InitFn, "init") orelse return false;
    const deinit_fn = self.dll.instance.lookup(core.DeinitFn, "deinit") orelse return false;
    const update_and_render = self.dll.instance.lookup(core.UpdateAndRenderFn, "update_and_render") orelse return false;
    const on_resize = self.dll.instance.lookup(core.OnResizeFn, "on_resize") orelse return false;

    game_api.init = init_fn;
    game_api.deinit = deinit_fn;
    game_api.update_and_render = update_and_render;
    game_api.on_resize = on_resize;
    return true;
}
