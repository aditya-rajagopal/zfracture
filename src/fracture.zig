// TODO: Move this to a common module? So we can use platform specific code in many places
// TODO: Seperate the win32 code into seperate files that has similar structure to the zig windows
// module
pub const win32 = @import("windows/win32.zig");
pub const appkit = @import("macos/appkit.zig");
pub const XAudio2 = @import("windows/xaudio2.zig");

pub const Platform = @import("platform.zig");

const Types = @import("types.zig");
pub const Color = Types.Color;
pub const Bitmap = Types.Bitmap;
pub const AABB = @import("AABB.zig");

pub const wav = @import("wav.zig");
pub const event = @import("event.zig");

// TODO: Make a switch for which type of renderer we want to use
pub const Renderer = @import("software_renderer.zig");

pub const SoundSystem = @import("sound.zig");
pub const PlaybackHandle = SoundSystem.PlaybackHandle;

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
