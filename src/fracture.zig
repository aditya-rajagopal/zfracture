const std = @import("std");
const builtin = @import("builtin");

// TODO: Move this to a common module? So we can use platform specific code in many places
// TODO: Seperate the win32 code into seperate files that has similar structure to the zig windows module
pub const win32 = @import("windows/win32.zig");
pub const XAudio2 = @import("windows/xaudio2.zig");

// pub const Platform = switch (builtin.os.tag) {
// };

const Types = @import("types.zig");
pub const Color = Types.Color;
pub const wav = @import("wav.zig");
pub const input = @import("input.zig");

// TODO: Make a switch for which type of renderer we want to use
pub const Renderer = @import("software_renderer.zig");

// TODO: Currently this is a direct call into the platform api. We maybe can explore abstracting
// the loading of sounds especially when IO is going to be abstrated out into jobs.
pub const SoundSystem = switch (builtin.os.tag) {
    .windows => @import("windows/xaudio2.zig"),
    else => @compileError("Unsupported OS"),
};

// TODO: Move this to some common place
pub fn KB(value: comptime_int) comptime_int {
    return value * 1024;
}

pub fn MB(value: comptime_int) comptime_int {
    return value * 1024 * 1024;
}

pub fn GB(value: comptime_int) comptime_int {
    return value * 1024 * 1024 * 1024;
}
