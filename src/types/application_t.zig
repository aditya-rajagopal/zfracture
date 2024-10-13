const core = @import("fr_core");

/// The data passed to the application API
pub const Memory = struct {
    /// The general allocator used to allocate permanent data
    gpa: core.GPA = undefined,
    /// Temporary Allocator that is cleared each frame. Used for storing transient frame data.
    frame_allocator: core.FrameArena = undefined,
};

/// Game API that must be defined by the application
/// The GameData is passed to these functions as context
pub const API = struct {
    /// The function called when the application is started
    init: *const fn (ctx: *Fracture) bool,
    /// Function called when the application shuts down
    deinit: *const fn (ctx: *Fracture) void,
    /// Function called each frame by the engine
    /// delta_time: the frame time of the last frame
    update: *const fn (ctx: *Fracture, delta_time: f64) bool,
    /// Function called each fraom by the engine to do rendering tasks
    render: *const fn (ctx: *Fracture, delta_time: f64) bool,
    /// Function called by the engine on update events
    on_resize: *const fn (ctx: *Fracture, width: u32, height: u32) void,
};

/// The configuration of the application that must be defined by the client
pub const AppConfig = struct {
    /// The name of the application displayed on the window
    application_name: [:0]const u8 = "Unnamed Application. Please Name the application",
    /// The initial position and size of the window
    window_pos: struct { x: i32 = 0, y: i32 = 0, width: i32 = 1280, height: i32 = 720 } = .{},
    /// The value to start the frame_arena at. It can still grow after but this can be set by the
    /// application to a reasonable upper bound to prevent reallocations
    frame_arena_preheat_bytes: u64 = 0,
    /// The log function to use instead of the engine provided default one
    log_fn: core.log.LogFn = core.log.default_log,
};

const std = @import("std");
const Fracture = @import("types.zig").Fracture;
