pub const Packet = struct {
    delta_time: f32,
};

pub const RendererLog = core.log.ScopedLogger(core.log.default_log, .RENDERER, core.log.default_level);

// TODO: Create an extent type in math
pub const FramebufferExtentFn = *const fn () [2]u32;

pub const Vertex3D = extern struct {
    position: m.Vec3.Array,
};

// NOTE: We want the Global UBO to be 256 bytes
// Specifically on some Nvidia cards UBOs need to have 256 bytes
pub const GlobalUO = extern struct {
    /// The view projection matrix P * V (Order is important)
    view_projection: m.Mat4, // 64 bytes
    reserved_0: m.Mat4,
    reserved_1: m.Mat4,
    reserved_2: m.Mat4,
};

const core = @import("fr_core");
const m = core.math;
