const std = @import("std");

// TODO: Move this to a common module? So we can use platform specific code in many places
// TODO: Seperate the win32 code into seperate files that has similar structure to the zig windows module
pub const win32 = @import("windows/win32.zig");
pub const appkit = @import("macos/appkit.zig");
pub const XAudio2 = @import("windows/xaudio2.zig");

// pub const Platform = switch (builtin.target.os.tag) {
// };

const Types = @import("types.zig");
pub const Color = Types.Color;
pub const wav = @import("wav.zig");
pub const input = @import("input.zig");

// TODO: Make a switch for which type of renderer we want to use
pub const Renderer = @import("software_renderer.zig");

pub const SoundSystem = @import("sound.zig");
pub const PlaybackHandle = SoundSystem.PlaybackHandle;

/// Sleeps until frame_start + frame_duration, retrying if sleep returns early.
/// frame_start must use std.Io.Clock.awake. Late frames return without sleeping.
pub fn paceFrame(io: std.Io, frame_start: std.Io.Timestamp, frame_duration: std.Io.Duration) std.Io.Cancelable!void {
    const deadline = frame_start.addDuration(frame_duration);
    while (std.Io.Clock.awake.now(io).nanoseconds < deadline.nanoseconds) {
        try deadline.withClock(.awake).wait(io);
    }
}

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
