pub const Packet = struct {
    delta_time: f32,
};

pub const RendererLog = core.log.ScopedLogger(core.log.default_log, .RENDERER, core.log.default_level);

// TODO: Create an extent type in math
pub const FramebufferExtentFn = *const fn () [2]u32;

const core = @import("fr_core");
