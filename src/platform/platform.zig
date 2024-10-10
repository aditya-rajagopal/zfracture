const platform = switch (builtin.os.tag) {
    .windows => @import("windows.zig"),
    else => |p| @compileError("Platform " ++ @tagName(p) ++ " is not supported"),
};

pub const PlatformState = platform.InternalState;

pub const PlatformError = platform.Error;

pub const init = platform.init;
pub const deinit = platform.deinit;
pub const pump_messages = platform.pump_messages;
pub const get_tty_config = platform.get_tty_config;
pub const get_allocator = platform.get_allocator;

const builtin = @import("builtin");
const std = @import("std");
