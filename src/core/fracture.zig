//! The core fracture engine library
//!
//! This module provides all the core functionality provided by fracture.
//!
//! The engine is designed to contain all the state and have 0 global state so that it can be hot swapped.
//!
//! # Examples
//!
//! ```zig
//! const std = @import("std");
//! const Fracture = @import("fr_core").Fracture;
//!
//! pub fn main() !void {
//!     var engine = try std.heap.page_allocator.create(Fracture);
//!     defer engine.deinit();
//!     defer std.heap.page_allocator.destroy(engine);
//!     // Initialize the individual systems
//!     try engine.renderer.init(std.heap.page_allocator, "My Application", &.{});
//! }
//! ```
const root = @import("root");
/// Renderer backend
pub const renderer_backend: type = if (@hasDecl(root, "config") and @hasDecl(root.config, "renderer_backend"))
    root.config.renderer_backend
else
    @compileError("No renderer backend defined in root.config");

/// The Renderer Type
pub const Renderer = renderer.Renderer(renderer_backend);

/// The core engine that contains all the state
pub const Fracture = struct {
    /// The renderer that provides a frontend to the chosen renderer backend
    renderer: Renderer,
    /// The memory system. Contains the persistent allocator and the frame allocator
    memory: Memory,
    /// The event system
    event: Event,
    /// The log configuration that can be used to configure application side logging
    log_config: log.LogConfig,
    /// The last time the application was updated
    last_time: f64 = 0,
    /// The extent of the window
    extent: math.Extent2D = .{
        .width = 1280,
        .height = 720,
    },
    /// The delta time of the last frame
    delta_time: f32 = 0,
    /// The input system
    input: Input,
    /// True if the application is suspended
    is_suspended: bool = false,
    /// True if the application is running
    is_running: bool = false,
};

pub const log = @import("log.zig");
pub const defines = @import("defines.zig");
pub const mem = @import("memory.zig");
pub const Event = @import("event.zig");
pub const Input = @import("input.zig");
pub const math = @import("fr_math");
pub const image = @import("image.zig");
pub const renderer = @import("renderer.zig");
pub const @"comptime" = @import("comptime.zig");

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

pub const InitFn = switch (builtin.mode) {
    .Debug => *const fn (engine: *Fracture) callconv(.c) ?*anyopaque,
    else => *const fn (engine: *Fracture) ?*anyopaque,
};
pub const DeinitFn = switch (builtin.mode) {
    .Debug => *const fn (engine: *Fracture, game_state: *anyopaque) callconv(.c) void,
    else => *const fn (engine: *Fracture, game_state: *anyopaque) void,
};
pub const UpdateAndRenderFn = switch (builtin.mode) {
    .Debug => *const fn (engine: *Fracture, game_state: *anyopaque) callconv(.c) bool,
    else => *const fn (engine: *Fracture, game_state: *anyopaque) bool,
};
pub const OnResizeFn = switch (builtin.mode) {
    .Debug => *const fn (engine: *Fracture, game_state: *anyopaque, width: u32, height: u32) callconv(.c) void,
    else => *const fn (engine: *Fracture, game_state: *anyopaque, width: u32, height: u32) void,
};

/// Game API that must be defined by the application
/// The GameData is passed to these functions as context
pub const API = struct {
    /// The function to initialize the game's internal state if it has been reloaded
    init: InitFn,
    /// Function called when the application shuts down
    deinit: DeinitFn,
    /// Function called each frame by the engine
    /// delta_time: the frame time of the last frame
    update_and_render: UpdateAndRenderFn,
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
    frame_arena_preheat_size: defines.BytesRepr = .{ .B = 1024 },
    /// The log function to use instead of the engine provided default one
    log_fn: log.LogFn = log.default_log,
};

// TODO: Bring back tests failing due to missing backend in root
// test Fracture {
//     testing.refAllDecls(@This());
// }

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
