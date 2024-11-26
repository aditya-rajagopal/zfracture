const core = @import("fr_core");
const math = core.math;
const Texture = core.resource.Texture;

// TODO: Make this configurable from build or other means. TO allow different contexts
const Context = @import("vulkan_backend");
const T = core.renderer;
const std = @import("std");

const Frontend = @This();

// const view_mat = math.Transform.init_trans(&math.Vec3.init(0.0, 0.0, -1.0));

backend: Context,
log: T.RendererLog,
projection: math.Mat4,
view: math.Mat4,
near_clip: f32,
far_clip: f32,
default_texture: core.resource.Texture,
angle: f32,
render_data: T.RenderData,

// HACK: Temporaray
test_diffuse: core.resource.Texture,
allocator: std.mem.Allocator,

pub const FrontendError = error{ InitFailed, EndFrameFailed } || Context.Error;

pub fn init(
    self: *Frontend,
    allocator: std.mem.Allocator,
    application_name: [:0]const u8,
    platform_state: *anyopaque,
    log_config: *core.log.LogConfig,
    framebuffer_extent: *const core.math.Extent2D,
    // HACK: Event temporary
    event: *core.Event,
) FrontendError!void {
    // TODO: Make this configurable
    self.allocator = allocator;
    self.log = T.RendererLog.init(log_config);
    try self.backend.init(allocator, application_name, platform_state, self.log, framebuffer_extent, &self.default_texture);
    self.angle = 0;
    self.near_clip = 0.1;
    self.far_clip = 1000.0;
    self.projection = math.Mat4.perspective(math.deg_to_rad(45.0), 1920.0 / 1080.0, self.near_clip, self.far_clip);
    self.view = math.Transform.init_trans(&math.Vec3.init(0.0, 0.0, -2.0)).to_mat();
    self.render_data.object_id = self.backend.material_shader.acquire_resources(&self.backend);
    self.render_data.model = math.Transform.identity;

    // INFO: We are going to create a blue and white checkerboard 256x256 texture as default
    // TODO: Maybe this will be the magenta texture
    self.log.debug("Createing Default texture", .{});
    const texture_dim = 256;
    const channels = 4;
    const pixel_count = texture_dim * texture_dim;
    const square_width = 16;
    var pixels: [pixel_count * channels]u8 = undefined;
    @memset(&pixels, 255);

    for (0..texture_dim) |row| {
        for (0..texture_dim) |col| {
            const index = row * texture_dim + col;
            const index_byte = index * channels;
            const r = @divFloor(row, square_width);
            const c = @divFloor(col, square_width);
            if (r % 2 != 0) {
                if (c % 2 != 0) {
                    pixels[index_byte] = 0;
                    pixels[index_byte + 1] = 0;
                }
            } else {
                if (c % 2 == 0) {
                    pixels[index_byte] = 0;
                    pixels[index_byte + 1] = 0;
                }
            }
        }
    }

    // TODO: Create a texture system
    // TODO: Store the image into Fracture format
    // const image = core.image.load("assets/textures/cobblestone.png", allocator, .{ .requested_channels = 4 }) catch unreachable;
    // defer allocator.free(image.data);
    //
    // self.default_texture = self.backend.create_texture(image.width, image.height, 4, image.data, false, false) catch {
    //     self.log.err("Unable to load default texture", .{});
    //     return error.InitFailed;
    // };

    self.default_texture.data = self.backend.create_texture(texture_dim, texture_dim, channels, &pixels) catch {
        self.log.err("Unable to load default texture", .{});
        return error.InitFailed;
    };
    self.default_texture.width = texture_dim;
    self.default_texture.height = texture_dim;
    self.default_texture.channel_count = channels;
    self.default_texture.has_transparency = 0;
    self.default_texture.id = @enumFromInt(0);
    self.default_texture.generation = .null_handle;
    self.test_diffuse = .{ .data = undefined };

    self.render_data.textures[0] = &self.test_diffuse;

    _ = event.register_static(.DEBUG0, @ptrCast(self), on_debug0_event);
}

pub fn deinit(self: *Frontend) void {
    self.backend.destory_texture(&self.default_texture.data);
    self.backend.destory_texture(&self.test_diffuse.data);
    self.backend.deinit();
}

// HACK: Temporary code
fn load_texture(
    self: *Frontend,
    texture: *Texture,
    texture_name: []const u8,
    comptime texture_type: core.image.ImageFileType,
    allocator: std.mem.Allocator,
) bool {
    const format_string: []const u8 = "assets/textures/{s}.{s}";
    var file_name_buffer: [512]u8 = undefined;
    const file_name = std.fmt.bufPrint(&file_name_buffer, format_string, .{ texture_name, @tagName(texture_type) }) catch unreachable;
    const required_channel_count = 4;

    const image = core.image.load(file_name, allocator, .{ .requested_channels = required_channel_count }) catch |err| {
        self.log.err("Unable to load texture image: {s}", .{@errorName(err)});
        return false;
    };
    defer allocator.free(image.data);

    const current_generation = texture.generation;
    texture.generation = .null_handle;

    var has_transparency: bool = false;
    if (image.forced_transparency) {
        has_transparency = true;
    } else {
        var index: usize = 3;
        while (index < image.data.len) : (index += 4) {
            if (image.data[index] < 255) {
                has_transparency = true;
                break;
            }
        }
    }

    var old = texture.*;

    texture.width = image.width;
    texture.height = image.height;

    texture.data = self.backend.create_texture(
        image.width,
        image.height,
        required_channel_count,
        image.data,
    ) catch |err| {
        self.log.err("Unable to create texture: {s}", .{@errorName(err)});
        return false;
    };
    texture.has_transparency = @intFromBool(has_transparency);
    texture.generation = @enumFromInt(0);
    texture.id = @enumFromInt(0);

    self.backend.destory_texture(&old.data);

    if (current_generation == .null_handle) {
        texture.generation = @enumFromInt(0);
    } else {
        texture.generation = current_generation.increment();
    }

    return true;
}

fn on_debug0_event(
    event_code: core.Event.EventCode,
    data: core.Event.EventData,
    listener: ?*anyopaque,
    sender: ?*anyopaque,
) bool {
    _ = event_code;
    _ = sender;
    const index: u32 = @bitCast(data[0..4].*);
    const names = [_][]const u8{ "cobblestone", "paving", "paving2" };
    const self: *Frontend = @ptrCast(@alignCast(listener orelse unreachable));
    _ = self.load_texture(&self.test_diffuse, names[index % 3], .png, self.allocator);
    return true;
}

pub inline fn update_global_state(
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
    self.backend.frame_delta_time = packet.delta_time;
    // Only if the begin frame is successful can we continue with the mid frame operations
    if (self.begin_frame(packet.delta_time)) {
        self.backend.update_global_state(self.projection, self.view, math.Vec3.zeros, math.Vec4.ones, 0);

        // const quat = math.Quat.init_axis_angle(&math.Vec3.z_basis.negate(), self.angle, false);
        // const model = quat.to_affine_center(&math.Vec3.zeros);
        // self.angle += 0.001;
        // self.render_data.model = model;

        self.backend.temp_draw_object(self.render_data);

        // If the end frame fails it is likely irrecoverable
        if (!self.end_frame(packet.delta_time)) {
            return FrontendError.EndFrameFailed;
        }
    }
}

pub inline fn update_object(self: *Frontend, geometry: T.RenderData) void {
    self.backend.update_object(geometry);
}

pub fn on_resize(self: *Frontend, new_extent: core.math.Extent2D) void {
    const aspect_ratio = @as(f32, @floatFromInt(new_extent.width)) / @as(f32, @floatFromInt(new_extent.height));
    self.projection = math.Mat4.perspective(math.deg_to_rad(45.0), aspect_ratio, self.near_clip, self.far_clip);
    self.backend.on_resized(new_extent);
}

pub inline fn create_texture(
    self: *Frontend,
    width: u32,
    height: u32,
    channel_count: u8,
    pixels: []const u8,
) Texture.Data {
    self.backend.create_texture(width, height, channel_count, pixels);
}

pub inline fn destory_texture(self: *Frontend, texture_data: *Texture.Data) void {
    self.backend.destory_texture(texture_data);
}

test Frontend {
    std.testing.refAllDecls(Context);
}
