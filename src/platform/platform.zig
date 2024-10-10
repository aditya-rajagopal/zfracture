///! The Platform abstraction lives here.
///!
///! To define a new platform you need to implement the functions defined in this file.
const platform = switch (builtin.os.tag) {
    .windows => @import("windows.zig"),
    else => |p| @compileError("Platform " ++ @tagName(p) ++ " is not supported"),
};

/// The state stored by the platform layer. This is only for managing types and not
/// to interact with the state. You can technically do it but you really should not.
pub const PlatformState = platform.InternalState;

/// Error type that will be returned by platform functions
pub const PlatformError = platform.Error;

/// Initialize the platform and create a window
pub const init = platform.init;
/// Destroy the windows
pub const deinit = platform.deinit;
/// Read and process all the platform event messages in queue
pub const pump_messages = platform.pump_messages;
/// Get the terminal config for colouring
pub const get_tty_config = platform.get_tty_config;
/// Get the platform specific allocator
pub const get_allocator = platform.get_allocator;

const builtin = @import("builtin");
const std = @import("std");
