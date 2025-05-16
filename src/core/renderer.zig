//! WIP: Renderer module
pub const texture_system = @import("systems/texture.zig");
// TODO: Move these to the right places
pub const MAX_MATERIAL_INSTANCES = 64;

pub const RendererLog = log.ScopedLogger(log.default_log, .RENDERER, log.default_level);

pub const Vertex3D = extern struct {
    position: math.Vec3.Array,
    uv: math.Vec2.Array,
};

// NOTE: We want the Global UBO to be 256 bytes
// Specifically on some Nvidia cards UBOs need to have 256 bytes
pub const GlobalUO = extern struct {
    /// The view projection matrix P * V (Order is important)
    view_projection: math.Mat4, // 64 bytes
    _reserved_0: math.Mat4,
    _reserved_1: math.Mat4,
    _reserved_2: math.Mat4,
};

// NOTE: This is the per material instance uniform
pub const MaterialUO = extern struct {
    diffuse_colour: math.Vec4,
    _reserved_0: math.Vec4,
    _reserved_1: math.Vec4,
    _reserved_2: math.Vec4,
};

pub const MaterialInstanceID = enum(u32) { null_handle = std.math.maxInt(u32), _ };

// NOTE: This is the data that will be passed to the renderer
// NOTE: This is the data that will be passed to the renderer
pub const RenderData = extern struct {
    material_id: MaterialInstanceID,
    model: math.Transform,
    textures: [16]TextureHandle = [_]TextureHandle{.null_handle} ** 16,
};

pub const Packet = struct {
    delta_time: f32,
};

// TODO: Create an interface definition for backend

pub fn Renderer(renderer_backend: type) type {
    comptime assert(@hasDecl(renderer_backend, "init"));
    comptime assert(@hasDecl(renderer_backend, "deinit"));
    comptime assert(@hasDecl(renderer_backend, "create_texture"));
    comptime assert(@hasDecl(renderer_backend, "destroy_texture"));
    comptime assert(@hasDecl(renderer_backend, "begin_frame"));
    comptime assert(@hasDecl(renderer_backend, "end_frame"));

    // HACK: This should be in the shader/material system
    comptime assert(@hasDecl(renderer_backend, "update_global_state"));
    comptime assert(@hasDecl(renderer_backend, "update_object"));

    comptime assert(@hasDecl(renderer_backend, "Error"));

    return struct {
        /// Texture system to load and unload textures.
        textures: TexturesType,

        /// Allocator tagged with the renderer type in debug
        allocator: std.mem.Allocator,

        /// Private logger for the renderer subsystem. Dont use this directly if you can.
        _log: RendererLog,
        /// Private instance of a renderer backend. Do not access this directly unless you know what you are doing
        _backend: renderer_backend,

        pub const TexturesType = Textures(renderer_backend);

        pub const Error = error{ InitFailed, EndFrameFailed } || renderer_backend.Error;

        pub const Self = @This();

        pub fn init(
            self: *Self,
            allocator: std.mem.Allocator,
            application_name: [:0]const u8,
            platform_state: *anyopaque,
            log_config: *log.LogConfig,
            framebuffer_extent: *const math.Extent2D,
        ) Error!void {
            // TODO: Make this configurable
            self.allocator = allocator;
            self._log = RendererLog.init(log_config);
            try self._backend.init(
                allocator,
                application_name,
                platform_state,
                self._log,
                framebuffer_extent,
                &self.textures,
            );
            try self.textures.init(self, allocator);
        }

        pub fn deinit(self: *Self) void {
            self.textures.deinit();
            self._backend.deinit();
        }

        pub fn begin_frame(self: *Self, delta_time: f32) bool {
            self._backend.frame_delta_time = delta_time;
            return self._backend.begin_frame(delta_time);
        }

        pub fn end_frame(self: *Self, delta_time: f32) bool {
            self._backend.current_frame += 1;
            return self._backend.end_frame(delta_time);
        }

        // TODO: Pass camera information here
        // TODO: Make a shader system and camera system to provide for global state
        // HACK: This should be in the shader/material system
        pub inline fn update_global_state(
            self: *Self,
            projection: math.Mat4,
            view: math.Mat4,
            view_position: math.Vec3,
            ambient_colour: math.Vec4,
            mode: i32,
        ) void {
            self._backend.update_global_state(projection, view, view_position, ambient_colour, mode);
        }

        pub inline fn shader_acquire_resource(self: *Self) MaterialInstanceID {
            return self._backend.material_shader.acquire_resources(&self._backend);
        }

        pub inline fn shader_release_resource(self: *Self, id: MaterialInstanceID) void {
            self._backend.material_shader.release_resources(&self._backend, id);
        }

        pub inline fn draw_temp_object(self: *Self, render_data: RenderData) void {
            self._backend.temp_draw_object(render_data);
        }

        pub fn on_resize(self: *Self, new_extent: math.Extent2D) void {
            self._backend.on_resized(new_extent);
        }

        test Self {
            std.testing.refAllDecls(renderer_backend);
        }
    };
}

const math = @import("fr_math");
const log = @import("log.zig");
const Textures = texture_system.Textures;
const TextureHandle = texture_system.TextureHandle;
const img = @import("image.zig");
const std = @import("std");
const assert = std.debug.assert;
