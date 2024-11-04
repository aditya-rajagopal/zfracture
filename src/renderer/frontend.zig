const core = @import("fr_core");
const math = core.math;
// TODO: Make this configurable from build or other means. TO allow different contexts
const Context = @import("vulkan/context.zig");
const T = @import("types.zig");
const std = @import("std");

const Frontend = @This();

// const view_mat = math.Transform.init_trans(&math.Vec3.init(0.0, 0.0, -1.0));

backend: Context,
log: T.RendererLog,
projection: math.Mat4,
view: math.Mat4,
near_clip: f32,
far_clip: f32,

angle: f32,
z: f32 = 0.0,

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
    self.z = 0;
    self.near_clip = 0.1;
    self.far_clip = 1000.0;
    self.projection = math.Mat4.perspective(math.deg_to_rad(45.0), 1920.0 / 1080.0, self.near_clip, self.far_clip);
    self.view = math.Transform.init_trans(&math.Vec3.init(0.0, 0.0, -2.0)).to_mat();
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

pub inline fn set_object_view(self: *Frontend, view: *const math.Mat4) void {
    self.view = view.*;
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
        self.backend.update_global_state(self.projection, self.view, math.Vec3.zeros, math.Vec4.ones, 0);

        const quat = math.Quat.init_axis_angle(&math.Vec3.z_basis.negate(), self.angle, false);
        const model = quat.to_affine_center(&math.Vec3.zeros);
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
    const aspect_ratio = @as(f32, @floatFromInt(new_extent.width)) / @as(f32, @floatFromInt(new_extent.height));
    self.projection = math.Mat4.perspective(math.deg_to_rad(45.0), aspect_ratio, self.near_clip, self.far_clip);
    self.backend.on_resized(new_extent);
}

test Frontend {
    std.testing.refAllDecls(Context);
}
