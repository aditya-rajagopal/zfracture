pub const Fracture = struct {
    memory: Memory,
    event: Event,
    input: Input,
    log_config: log.LogConfig,
    width: i32 = 1280,
    height: i32 = 720,
    last_time: f64 = 0,
    delta_time: f64 = 0,
    is_suspended: bool = false,
    is_running: bool = false,
};

pub const log = @import("log.zig");
pub const defines = @import("defines.zig");
pub const mem = @import("memory.zig");
pub const Event = @import("event.zig");
pub const Input = @import("input.zig");

// pub const MergeEnums = comptime_funcs.MergeEnums;
// pub const Distinct = comptime_funcs.Distinct;

pub const GPA = mem.TrackingAllocator(.gpa, EngineMemoryTag, true);
pub const FrameArena: type = mem.TrackingAllocator(.frame_arena, ArenaMemoryTags, true);

/// The memory system passed to the game
pub const Memory = struct {
    /// The general allocator used to allocate permanent data
    gpa: GPA = undefined,
    /// Temporary Allocator that is cleared each frame. Used for storing transient frame data.
    frame_allocator: FrameArena = undefined,
};

pub const EngineMemoryTag = enum(u8) {
    untagged = 0,
    event,
    renderer,
    application,
    game,
    frame_arena,
};

pub const ArenaMemoryTags = enum(u8) {
    untagged = 0,
};

pub const InitFn = *const fn (engine: *Fracture) ?*anyopaque;
pub const DeinitFn = *const fn (engine: *Fracture, game_state: *anyopaque) void;
pub const UpdateFn = *const fn (engine: *Fracture, game_state: *anyopaque) bool;
pub const RenderFn = *const fn (engine: *Fracture, game_state: *anyopaque) bool;
pub const OnResizeFn = *const fn (engine: *Fracture, game_state: *anyopaque, width: u32, height: u32) void;

/// Game API that must be defined by the application
/// The GameData is passed to these functions as context
pub const API = struct {
    /// The function to initialize the game's internal state if it has been reloaded
    init: InitFn,
    /// Function called when the application shuts down
    deinit: DeinitFn,
    /// Function called each frame by the engine
    /// delta_time: the frame time of the last frame
    update: UpdateFn,
    /// Function called each fraom by the engine to do rendering tasks
    render: RenderFn,
    /// Function called by the engine on update events
    on_resize: OnResizeFn,
};

/// The configuration of the application that must be defined by the client
pub const AppConfig = struct {
    /// The name of the application displayed on the window
    application_name: [:0]const u8 = "Unnamed Application. Please Name the application",
    /// The initial position and size of the window
    window_pos: struct { x: i32 = 0, y: i32 = 0, width: i32 = 1280, height: i32 = 720 } = .{},
    /// The value to start the frame_arena at. It can still grow after but this can be set by the
    /// application to a reasonable upper bound to prevent reallocations
    frame_arena_preheat_size: defines.BytesRepr = .{ .B = 0 },
    /// The log function to use instead of the engine provided default one
    log_fn: log.LogFn = log.default_log,
};

pub fn not_implemented(comptime src: std.builtin.SourceLocation) void {
    @compileError("NOT IMPLEMENTED: " ++ src.fn_name ++ " - " ++ src.file);
}

test {
    testing.refAllDeclsRecursive(@This());
}

const std = @import("std");
const testing = std.testing;
const comptime_funcs = @import("comptime.zig");
const static_array_list = @import("containers/static_array_list.zig");
