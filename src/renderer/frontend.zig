const core = @import("fr_core");
const math = core.math;
// TODO: Make this configurable from build or other means. TO allow different contexts
const Context = @import("vulkan/context.zig");
const T = @import("types.zig");
const std = @import("std");

const Frontend = @This();

const perspective = math.Transform.perspective(math.deg_to_rad(45.0), 1920.0 / 1080.0, 0.1, 1000.0);
const view_mat = math.Transform.init_trans(&math.Vec3.init(0.0, 0.0, -1.0));

backend: Context,
log: T.RendererLog,
angle: f32,

pub const FrontendError = error{ InitFailed, EndFrameFailed } || Context.Error;

pub fn init(
    self: *Frontend,
    allocator: std.mem.Allocator,
    application_name: [:0]const u8,
    platform_state: *anyopaque,
    log_config: *core.log.LogConfig,
    framebuffer_extent: *const core.math.Extent2D,
) FrontendError!void {
    // TODO: Make this configurable
    self.log = T.RendererLog.init(log_config);
    try self.backend.init(allocator, application_name, platform_state, self.log, framebuffer_extent);
    self.angle = 0;
}

pub fn deinit(self: *Frontend) void {
    self.backend.deinit();
}

pub fn update_global_state(
    self: *Frontend,
    projection: math.Transform,
    view: math.Transform,
    view_position: math.Vec3,
    ambient_colour: math.Vec4,
    mode: i32,
) void {
    self.backend.update_global_state(projection, view, view_position, ambient_colour, mode);
}

pub fn begin_frame(self: *Frontend, delta_time: f32) bool {
    return self.backend.begin_frame(delta_time);
}

pub fn end_frame(self: *Frontend, delta_time: f32) bool {
    self.backend.current_frame += 1;
    return self.backend.end_frame(delta_time);
}

// Does this need to be an error or can it just be a bool?
pub fn draw_frame(self: *Frontend, packet: T.Packet) FrontendError!void {
    // Only if the begin frame is successful can we continue with the mid frame operations
    if (self.begin_frame(packet.delta_time)) {
        self.backend.update_global_state(perspective, view_mat, math.Vec3.zeros, math.Vec4.ones, 0);

        // const model = math.Transform.init_trans(&math.vec3s(0, 0, 0));

        const model = math.Transform.init_rot_z(math.deg_to_rad(self.angle));
        // const quat = math.Quat.init_axis_angle(&math.Vec3.z_basis.negate(), self.angle, false);
        // const model = quat.to_affine_center(&math.Vec3.zeros);
        self.angle += 0.001;

        self.backend.update_object(model);

        self.backend.temp_draw_object();

        // If the end frame fails it is likely irrecoverable
        if (!self.end_frame(packet.delta_time)) {
            return FrontendError.EndFrameFailed;
        }
    }
}

pub fn on_resize(self: *Frontend, new_extent: core.math.Extent2D) void {
    self.backend.on_resized(new_extent);
}

test Frontend {
    std.testing.refAllDecls(Context);
}
