pub const Fracture = struct {
    memory: mem.Memory,
    event: event,
    core_log: log.CoreLog,
    log: log.GameLog,
    is_suspended: bool = false,
    is_running: bool = false,
    width: i32 = 1280,
    height: i32 = 720,
    last_time: f64 = 0,
};

/// Game API that must be defined by the application
/// The GameData is passed to these functions as context
pub const API = struct {
    /// The function to initialize the game's internal state if it has been reloaded
    init: *const fn (engine: *Fracture) ?*anyopaque,
    /// Function called when the application shuts down
    deinit: *const fn (engine: *Fracture, game_state: *anyopaque) void,
    /// Function called each frame by the engine
    /// delta_time: the frame time of the last frame
    update: *const fn (engine: *Fracture, game_state: *anyopaque) bool,
    /// Function called each fraom by the engine to do rendering tasks
    render: *const fn (engine: *Fracture, game_state: *anyopaque) bool,
    /// Function called by the engine on update events
    on_resize: *const fn (engine: *Fracture, game_state: *anyopaque, width: u32, height: u32) void,
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
    log_fn: log.LogFn = log.default_log,
};

pub const log = @import("log.zig");
pub const defines = @import("defines.zig");
pub const mem = @import("memory.zig");
pub const event = @import("event.zig");

pub const MergeEnums = comptime_funcs.MergeEnums;
pub const Distinct = comptime_funcs.Distinct;

pub const StaticArrayList = static_array_list.StaticArrayList;

pub fn not_implemented(src: std.builtin.SourceLocation) void {
    @compileError("NOT IMPLEMENTED: " ++ src.fn_name ++ " - " ++ src.file);
}

test {
    testing.refAllDeclsRecursive(@This());
}

const std = @import("std");
const testing = std.testing;
const comptime_funcs = @import("comptime.zig");
const static_array_list = @import("containers/static_array_list.zig");
