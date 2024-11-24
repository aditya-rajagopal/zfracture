// TODO: Move these to the right places
pub const MAX_MATERIAL_INSTANCES = 64;

pub const MaterialInstanceID = enum(u32) { null_handle = std.math.maxInt(u32), _ };

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

// NOTE: This is the per object uniform object
pub const ObjectUO = extern struct {
    diffuse_colour: math.Vec4,
    _reserved_0: math.Vec4,
    _reserved_1: math.Vec4,
    _reserved_2: math.Vec4,
};

// NOTE: This is the data that will be passed to the renderer
pub const RenderData = extern struct {
    object_id: MaterialInstanceID,
    model: math.Transform,
    // TODO: Make these handles
    textures: [16]?*Texture = [_]?*Texture{null} ** 16,
};

pub const Packet = struct {
    delta_time: f32,
};

pub fn Renderer(renderer_backend: type) type {
    comptime assert(@hasDecl(renderer_backend, "init"));
    comptime assert(@hasDecl(renderer_backend, "deinit"));
    comptime assert(@hasDecl(renderer_backend, "create_texture"));
    comptime assert(@hasDecl(renderer_backend, "destroy_texture"));
    comptime assert(@hasDecl(renderer_backend, "begin_frame"));
    comptime assert(@hasDecl(renderer_backend, "end_frame"));
    comptime assert(@hasDecl(renderer_backend, "update_global_state"));

    comptime assert(@hasField(renderer_backend, "Error"));

    return struct {
        backend: renderer_backend,
        log: RendererLog,
        projection: math.Mat4,
        view: math.Mat4,
        near_clip: f32,
        far_clip: f32,
        render_data: RenderData,
        allocator: std.mem.Allocator,

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
            self.log = RendererLog.init(log_config);
            try self.backend.init(
                allocator,
                application_name,
                platform_state,
                self.log,
                framebuffer_extent,
            );
            self.near_clip = 0.1;
            self.far_clip = 1000.0;
            self.projection = math.Mat4.perspective(math.deg_to_rad(45.0), 1920.0 / 1080.0, self.near_clip, self.far_clip);
            self.view = math.Transform.init_trans(&math.Vec3.init(0.0, 0.0, -2.0)).to_mat();
            self.render_data.object_id = self.backend.material_shader.acquire_resources(&self.backend);
            self.render_data.model = math.Transform.identity;
        }

        pub fn deinit(self: *Self) void {
            self.backend.destory_texture(&self.default_texture.data);
            self.backend.destory_texture(&self.test_diffuse.data);
            self.backend.deinit();
        }

        pub inline fn update_global_state(
            self: *Self,
            projection: math.Transform,
            view: math.Transform,
            view_position: math.Vec3,
            ambient_colour: math.Vec4,
            mode: i32,
        ) void {
            self.backend.update_global_state(projection, view, view_position, ambient_colour, mode);
        }

        pub inline fn set_object_view(self: *Self, view: *const math.Mat4) void {
            self.view = view.*;
        }

        pub fn begin_frame(self: *Self, delta_time: f32) bool {
            return self.backend.begin_frame(delta_time);
        }

        pub fn end_frame(self: *Self, delta_time: f32) bool {
            self.backend.current_frame += 1;
            return self.backend.end_frame(delta_time);
        }

        // Does this need to be an error or can it just be a bool?
        pub fn draw_frame(self: *Self, packet: Packet) Error!void {
            self.backend.frame_delta_time = packet.delta_time;
            // Only if the begin frame is successful can we continue with the mid frame operations
            if (self.begin_frame(packet.delta_time)) {
                self.backend.update_global_state(self.projection, self.view, math.Vec3.zeros, math.Vec4.ones, 0);

                self.backend.temp_draw_object(self.render_data);

                // If the end frame fails it is likely irrecoverable
                if (!self.end_frame(packet.delta_time)) {
                    return Error.EndFrameFailed;
                }
            }
        }

        pub inline fn update_object(self: *Self, geometry: RenderData) void {
            self.backend.update_object(geometry);
        }

        pub fn on_resize(self: *Self, new_extent: math.Extent2D) void {
            const aspect_ratio = @as(f32, @floatFromInt(new_extent.width)) / @as(f32, @floatFromInt(new_extent.height));
            self.projection = math.Mat4.perspective(math.deg_to_rad(45.0), aspect_ratio, self.near_clip, self.far_clip);
            self.backend.on_resized(new_extent);
        }

        pub inline fn create_texture(
            self: *Self,
            width: u32,
            height: u32,
            channel_count: u8,
            pixels: []const u8,
        ) Texture.Data {
            self.backend.create_texture(width, height, channel_count, pixels);
        }

        pub inline fn destory_texture(self: *Self, texture_data: *Texture.Data) void {
            self.backend.destory_texture(texture_data);
        }

        test Self {
            std.testing.refAllDecls(renderer_backend);
        }
    };
}

const math = @import("math/math.zig");
const log = @import("log.zig");
const Event = @import("event.zig");
const Texture = @import("resource.zig").Texture;
const img = @import("image.zig");
const std = @import("std");
const assert = std.debug.assert;
