///! The application system contains the main loop of the application
///!
///! It owns the engine state and dispatches events
// TODO:
//      - [ ] Should i replace the frame arena by a fixed buffer allocator that is defined by asking the application
//            how much memory it needs at startup and give it that much memory to work with forever. Instead of an arena
const core = @import("fr_core");
const platform = @import("platform/platform.zig");
const Frontend = @import("renderer/frontend.zig");

const config = @import("config.zig");
const application_config = config.app_config;
const DLL = switch (builtin.mode) {
    .Debug => struct {
        instance: platform.LibraryHandle,
        time_stamp: i128 align(8),
    },
    else => void,
};

const EngineLog = core.log.ScopedLogger(core.log.default_log, .ENGINE, core.log.default_level);

pub const Application = @This();
engine: core.Fracture = undefined,
log: EngineLog,
platform_state: platform.PlatformState = undefined,

frontend: Frontend = undefined,
game_state: *anyopaque,
api: core.API,
dll: DLL,
frame_arena: std.heap.ArenaAllocator = undefined,
timer: std.time.Timer,

const ApplicationError =
    error{ ClientAppInit, FailedUpdate, FailedRender, DLLLoadFailed } ||
    platform.PlatformError ||
    std.mem.Allocator.Error ||
    core.log.LoggerError ||
    std.fs.File.OpenError ||
    std.fs.File.StatError ||
    Frontend.FrontendError;

pub fn init(allocator: std.mem.Allocator) ApplicationError!*Application {
    var start = std.time.Timer.start() catch unreachable;

    // Memory
    const app: *Application = try allocator.create(Application);
    errdefer allocator.destroy(app);

    app.engine.is_running = false;
    app.engine.is_suspended = false;
    const app_config = application_config;
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
            app.api = config.app_api;
        },
    }

    // Logging
    app.engine.log_config.init();
    try app.engine.log_config.stderr_init();
    try app.engine.log_config.file_init();
    errdefer app.engine.log_config.deinit();

    app.log = EngineLog.init(&app.engine.log_config);

    app.log.info("Logging system has been initialized", .{});

    // Event
    try app.engine.event.init();
    errdefer app.engine.event.deinit();

    // Platform
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

    // Memory
    app.engine.memory.gpa.init(allocator, &app.engine.log_config);
    const arena_allocator = app.engine.memory.gpa.get_type_allocator(.frame_arena);
    if (comptime builtin.mode == .Debug) {
        // NOTE: Tracking the allocation of the application
        app.engine.memory.gpa.memory_stats.current_memory[@intFromEnum(core.EngineMemoryTag.application)] = @sizeOf(Application);
        app.engine.memory.gpa.memory_stats.current_total_memory = @sizeOf(Application);
        app.engine.memory.gpa.memory_stats.peak_total_memory = @sizeOf(Application);
        app.engine.memory.gpa.memory_stats.peak_memory[@intFromEnum(core.EngineMemoryTag.application)] = @sizeOf(Application);
    }

    app.frame_arena = std.heap.ArenaAllocator.init(arena_allocator);
    app.engine.memory.frame_allocator.init(app.frame_arena.allocator(), &app.engine.log_config);

    const preheat_bytes = comptime app_config.frame_arena_preheat_size.as_bytes();
    if (comptime preheat_bytes != 0) {
        const ptr = try app.engine.memory.frame_allocator.backing_allocator.alloc(u8, preheat_bytes);
        @memset(ptr, 0);
        if (!app.frame_arena.reset(.retain_capacity)) {
            @branchHint(.unlikely);
            app.log.warn("Arena allocation failed to reset with retain capacity. It will hard reset", .{});
        }
        app.log.info("Frame arena has been preheated with {d} bytes of memory", .{preheat_bytes});
    }
    app.log.info("Memory has been initialized", .{});
    errdefer app.frame_arena.deinit();

    // Input
    app.engine.input.init();

    // Renderer
    const renderer_allocator = app.engine.memory.gpa.get_type_allocator(.renderer);
    try app.frontend.init(
        renderer_allocator,
        app_config.application_name,
        &app.platform_state,
        &app.engine.log_config,
        &app.engine.extent,
    );
    errdefer app.frontend.deinit();
    app.log.info("Renderer initialized", .{});

    app.engine.view = app.frontend.view;

    // Application
    app.game_state = app.api.init(&app.engine) orelse {
        @branchHint(.cold);
        app.log.fatal("Client application failed to initialize", .{});
        return ApplicationError.ClientAppInit;
    };

    app.log.info("Client application has been initialized", .{});

    app.api.on_resize(&app.engine, app.game_state, app_config.window_pos.width, app_config.window_pos.height);
    const end = start.read();

    app.log.info("Engine has been initialized in {s}", .{std.fmt.fmtDuration(end)});
    app.engine.is_running = true;
    return app;
}

pub fn deinit(self: *Application) void {

    // Application shutdown
    self.api.deinit(&self.engine, self.game_state);
    self.log.info("Client application has been shutdown", .{});

    // Renderer shutdown
    self.frontend.deinit();
    self.log.info("Renderer has been shutdown", .{});

    // Platform shutdown
    platform.deinit(&self.platform_state);
    self.log.info("Platform layer has been shutdown", .{});

    // Memory Shutdown
    self.engine.memory.frame_allocator.print_memory_stats();

    // self.engine.memory.gpa.deinit();
    self.engine.memory.frame_allocator.deinit();
    self.frame_arena.deinit();
    self.engine.memory.gpa.print_memory_stats();
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
    // debug_assert(initialized, @src(), "Trying to run application when none was created.", .{});
    var err: ?ApplicationError = null;

    self.engine.memory.gpa.print_memory_stats();
    const core_log = &self.log;

    // NOTE(aditya): This cannot fail on windows
    self.timer = std.time.Timer.start() catch unreachable;
    var delta_time: u64 = 0;
    var frame_time: u64 = 0;
    var frame_count: u64 = 0;
    var last_frame_count: u64 = 0;

    var end = self.timer.lap();

    const frame_rate_interval = 2 * std.time.ns_per_s;
    var current_frame_rate: f32 = 0.0;

    while (self.engine.is_running) {
        platform.pump_messages(&self.platform_state);

        // NOTE: Clear the arena right before the loop stats but after the events are handled else we might be invalidating
        // some pointers.
        if (!self.frame_arena.reset(.retain_capacity)) {
            @branchHint(.unlikely);
            core_log.warn("Arena allocation failed to reset with retain capacity. It will hard reset", .{});
        }
        self.engine.memory.frame_allocator.reset_stats();

        if (!self.engine.is_suspended) {
            if (!self.api.update(&self.engine, self.game_state)) {
                @branchHint(.cold);
                core_log.fatal("Client app update failed, shutting down", .{});
                err = ApplicationError.FailedUpdate;
                break;
            }

            if (self.engine.camera_dirty) {
                self.frontend.set_object_view(&self.engine.view);
                self.engine.camera_dirty = false;
            }

            if (!self.api.render(&self.engine, self.game_state)) {
                @branchHint(.cold);
                core_log.fatal("Client app render failed, shutting down", .{});
                err = ApplicationError.FailedRender;
                break;
            }

            // HACK: Temporary packet passing
            self.frontend.draw_frame(.{ .delta_time = 0 }) catch |e| {
                err = e;
                self.engine.is_running = false;
                continue;
            };

            delta_time += end;
            frame_time += end;
            frame_count += 1;

            if (frame_time > frame_rate_interval) {
                current_frame_rate = @as(f32, @floatFromInt(frame_count - last_frame_count)) / @as(f32, @floatFromInt(frame_time));
                current_frame_rate *= @as(f32, @floatFromInt(std.time.ns_per_s));
                frame_time = 0;
                last_frame_count = frame_count;
            }
        }

        switch (builtin.mode) {
            .Debug => {
                const file: std.fs.File = std.fs.cwd().openFile(config.dll_name, .{}) catch {
                    continue;
                };
                const stats = try file.stat();
                file.close();
                if (self.dll.time_stamp != stats.mtime) {
                    self.log.debug("New DLL detected", .{});
                    self.dll.time_stamp = stats.mtime;
                    _ = platform.free_library(self.dll.instance);
                    _ = self.reload_library();
                }
            },
            else => {},
        }

        if (self.engine.input.key_pressed_this_frame(.KEY_2)) {
            self.log.info("Frame rate: {d}\n", .{current_frame_rate});
        }
        self.engine.input.update();
        end = self.timer.lap();

        const ns_to_s: f32 = 1.0 / @as(f32, @floatFromInt(std.time.ns_per_s));
        self.engine.delta_time = @as(f32, @floatFromInt(end)) * ns_to_s;

        // break;
    }

    var dt: f64 = @floatFromInt(delta_time);
    dt /= std.time.ns_per_s;
    const float_count: f64 = @floatFromInt(frame_count);
    self.log.err("Avg Delta_time: {d}, FPS: {d}f/s", .{ std.fmt.fmtDuration(@divTrunc(delta_time, frame_count)), float_count / dt });
    // In case the loop exited for some other reason
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
                // self.log.trace("window_resized: w/h: {d}/{d}", .{ self.engine.extent.width, self.engine.extent.height });
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
                        self.frontend.on_resize(self.engine.extent);
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

    self.dll.instance = platform.load_library(new_name) orelse return false;
    const init_fn = platform.library_lookup(self.dll.instance, "init", core.InitFn) orelse return false;
    const deinit_fn = platform.library_lookup(self.dll.instance, "deinit", core.DeinitFn) orelse return false;
    const update = platform.library_lookup(self.dll.instance, "update", core.UpdateFn) orelse return false;
    const render = platform.library_lookup(self.dll.instance, "render", core.RenderFn) orelse return false;
    const on_resize = platform.library_lookup(self.dll.instance, "on_resize", core.OnResizeFn) orelse return false;
    self.api.init = init_fn;
    self.api.deinit = deinit_fn;
    self.api.update = update;
    self.api.render = render;
    self.api.on_resize = on_resize;
    return true;
}

// test {
//     std.debug.print("Size of: {d}, {d}\n", .{ @sizeOf(Application), @alignOf(Application) });
// }

const std = @import("std");
const builtin = @import("builtin");
