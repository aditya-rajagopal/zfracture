const core = @import("fr_core");
// TODO: Make this configurable from build or other means. TO allow different contexts
const Context = @import("vulkan/context.zig");
const types = @import("types.zig");
const std = @import("std");

const Frontend = @This();

backend: Context,
log: types.RendererLog,

pub const FrontendError = error{ InitFailed, EndFrameFailed } || Context.Error;

pub fn init(
    self: *Frontend,
    allocator: std.mem.Allocator,
    application_name: [:0]const u8,
    platform_state: *anyopaque,
    log_config: *core.log.LogConfig,
) FrontendError!void {
    // TODO: Make this configurable
    self.log = types.RendererLog.init(log_config);
    try self.backend.init(allocator, application_name, platform_state, self.log);
}

pub fn deinit(self: *Frontend) void {
    self.backend.deinit();
}

pub fn begin_frame(self: *Frontend, delta_time: f32) bool {
    return self.backend.begin_frame(delta_time);
}

pub fn end_frame(self: *Frontend, delta_time: f32) bool {
    self.backend.current_frame += 1;
    return self.backend.end_frame(delta_time);
}

// Does this need to be an error or can it just be a bool?
pub fn draw_frame(self: *Frontend, packet: types.Packet) FrontendError!void {
    // Only if the begin frame is successful can we continue with the mid frame operations
    if (self.begin_frame(packet.delta_time)) {
        // If the end frame fails it is likely irrecoverable
        if (!self.end_frame(packet.delta_time)) {
            return FrontendError.EndFrameFailed;
        }
    }
}

pub fn on_resize(width: u16, height: u16) void {
    _ = width;
    _ = height;
}
