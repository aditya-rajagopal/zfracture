pub const Tag = enum {
    VULKAN,
    OPENGL,
    DIRECTX,
};

pub const Packet = struct {
    delta_time: f32,
};
