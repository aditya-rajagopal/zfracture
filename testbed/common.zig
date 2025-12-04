const std = @import("std");

const fr = @import("fracture");
const MouseButton = fr.MouseButton;
const Renderer = fr.Renderer;

pub const EngineState = struct {
    input: fr.input.InputState,
    sound: fr.SoundSystem,
    permanent_allocator: std.mem.Allocator,
    transient_allocator: std.mem.Allocator,
    renderer: Renderer,

    delta_time: f32,
};
