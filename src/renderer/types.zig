pub const Packet = struct {
    delta_time: f32,
};

pub const MAX_MATERIAL_INSTANCES = 64;

pub const MaterialInstanceID = enum(u32) { null_handle = std.math.maxInt(u32), _ };

pub const RendererLog = core.log.ScopedLogger(core.log.default_log, .RENDERER, core.log.default_level);

// TODO: Create an extent type in math
pub const FramebufferExtentFn = *const fn () [2]u32;

pub const Vertex3D = extern struct {
    position: m.Vec3.Array,
    uv: m.Vec2.Array,
};

// NOTE: We want the Global UBO to be 256 bytes
// Specifically on some Nvidia cards UBOs need to have 256 bytes
pub const GlobalUO = extern struct {
    /// The view projection matrix P * V (Order is important)
    view_projection: m.Mat4, // 64 bytes
    _reserved_0: m.Mat4,
    _reserved_1: m.Mat4,
    _reserved_2: m.Mat4,
};

// NOTE: This is the per object uniform object
pub const ObjectUO = extern struct {
    diffuse_colour: m.Vec4,
    _reserved_0: m.Vec4,
    _reserved_1: m.Vec4,
    _reserved_2: m.Vec4,
};

// NOTE: This is the data that will be passed to the renderer
pub const RenderData = extern struct {
    // TODO: Make this a handle
    object_id: MaterialInstanceID,
    model: m.Transform,
    textures: [16]?*Texture = [_]?*Texture{null} ** 16,
};

const std = @import("std");
const core = @import("fr_core");
const m = core.math;
const Texture = core.resource.Texture;
