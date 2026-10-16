const std = @import("std");

const fr = @import("fracture");
const MouseButton = fr.MouseButton;
const Renderer = fr.Renderer;

pub const max_fps = 60;
// Round up so the frame rate does not exceed the cap.
pub const frame_duration: std.Io.Duration = .fromNanoseconds(@divTrunc(std.time.ns_per_s + max_fps - 1, max_fps));

pub const EngineState = struct {
    io: std.Io,
    input: fr.input.InputState,
    sound: fr.SoundSystem,
    permanent_allocator: std.mem.Allocator,
    transient_allocator: std.mem.Allocator,
    renderer: Renderer,

    delta_time: f32,
};
