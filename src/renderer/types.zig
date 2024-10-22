pub const Packet = struct {
    delta_time: f32,
};

pub const RendererLog = core.log.ScopedLogger(core.log.default_log, .RENDERER, core.log.default_level);

const core = @import("fr_core");
