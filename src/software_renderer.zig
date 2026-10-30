const std = @import("std");
const assert = std.debug.assert;
const profile = @import("profiling.zig");

const types = @import("types.zig");
const Color = types.Color;
const Bitmap = @import("bitmap.zig");
const png = @import("stdx/png.zig");

const AABB = @import("shapes.zig").AABB;

const Renderer = @import("renderer.zig");

const Self = @This();

back_buffer: FrameBuffer,
pixels_per_meter: f32,
camera_position: struct { x: f32, y: f32 },
textures: [32]Bitmap,
head: u8 = 1,
debug_color: u32,

pub const Config = struct {
    width: u16,
    height: u16,
    pixels_per_meter: f32,
};

pub fn init(
    self: *Self,
    gpa: std.mem.Allocator,
    config: Config,
) !void {
    self.back_buffer = .{
        .width = config.width,
        .height = config.height,
        .data = try gpa.alignedAlloc(
            u8,
            .fromByteUnits(4096),
            @as(usize, config.width) * config.height * bytes_per_pixel,
        ),
    };
    self.pixels_per_meter = config.pixels_per_meter;
    self.camera_position.x = 0;
    self.camera_position.y = 0;
    self.debug_color = Color.magenta.toARGB();
    self.textures = @splat(.{ .width = 1, .height = 1, .pixels = @as([*]u32, @ptrCast(&self.debug_color))[0..1] });
    self.head = 1;
}

pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
    gpa.free(self.back_buffer.data);
    for (self.textures[1..self.head]) |texture| {
        gpa.free(texture.pixels);
    }
}

pub fn submit(self: *Self, command: Renderer.Command) void {
    switch (command) {
        .clear_screen => |cc| self.clearScreen(
            cc.r,
            cc.g,
            cc.b,
        ),
        .set_view => |view| self.setView(
            view.meters_per_pixel,
            view.camera_x,
            view.camera_y,
        ),
        .draw_rectangle => |rect| {
            const screen = self.screenFromWorld(rect.x, rect.y);
            self.drawRectangle(
                screen.x,
                screen.y,
                rect.width,
                rect.height,
                rect.angle_radians,
                rect.color_srgb,
            );
        },
        .draw_sprite => |sprite| {
            const screen = self.screenFromWorld(sprite.x, sprite.y);
            self.drawSprite(
                screen.x,
                screen.y,
                sprite.width,
                sprite.height,
                self.getTexture(sprite.texture),
            );
        },
        .draw_textured_rectangle => |trect| {
            const screen = self.screenFromWorld(trect.x, trect.y);
            self.drawTexturedRectangle(
                screen.x,
                screen.y,
                trect.width,
                trect.height,
                trect.angle_radians,
                self.getTexture(trect.texture),
                trect.tint_srgb,
            );
        },
    }
}

pub fn getTexture(self: *const Self, texture: Renderer.Texture) Bitmap {
    const index: u32 = @backingInt(texture);
    if (index >= self.head) return self.textures[0];
    return self.textures[index];
}

pub fn createTextureCopy(self: *Self, gpa: std.mem.Allocator, texture: Bitmap) Renderer.Texture {
    if (self.head >= self.textures.len) {
        std.log.err("Texture slots full", .{});
        return @fromBackingInt(0);
    }
    const t: *Bitmap = &self.textures[self.head];
    assert(@as(u64, texture.width) * texture.height <= texture.pixels.len);
    t.pixels = gpa.dupe(u32, texture.pixels) catch {
        std.log.err("Failed to allocate memory for texture", .{});
        return @fromBackingInt(0);
    };
    defer self.head += 1;
    t.width = texture.width;
    t.height = texture.height;
    return @fromBackingInt(self.head);
}

pub fn loadAndCreateTexture(
    self: *Self,
    io: std.Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    file_path: []const u8,
) Renderer.Texture {
    if (self.head >= self.textures.len) {
        std.log.err("Texture slots full", .{});
        return @fromBackingInt(0);
    }

    const texture: *Bitmap = &self.textures[self.head];
    texture.* = loadTexture(io, gpa, arena, file_path) orelse return @fromBackingInt(0);
    defer self.head += 1;
    return @fromBackingInt(@intCast(self.head));
}

pub fn loadTexture(
    io: std.Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    file_path: []const u8,
) ?Bitmap {
    const file = std.Io.Dir.cwd().openFile(io, file_path, .{}) catch {
        std.log.err("Failed to open texture: {s}", .{file_path});
        return null;
    };
    defer file.close(io);
    var diagnostic: ?[]const u8 = null;
    const image = png.fromFile(
        file,
        io,
        arena,
        gpa,
        &diagnostic,
        .{ .flip_vertical_on_load = false, .requested_channels = 4 },
    ) catch {
        if (diagnostic) |d| {
            std.log.err("Failed to load texture png: {s}", .{d});
        }
        return null;
    };
    return Bitmap.prepareFromPNG(image);
}

pub const FrameBuffer = struct {
    width: u16,
    height: u16,
    data: []align(4096) u8,

    fn pixels(self: *FrameBuffer) []u32 {
        const count = @as(usize, self.width) * @as(usize, self.height);
        return @ptrCast(self.data[0 .. count * bytes_per_pixel]);
    }
};

pub const bytes_per_pixel: usize = 4;

pub fn setView(self: *Self, meters_per_pixel: f32, camera_x: f32, camera_y: f32) void {
    assert(meters_per_pixel != 0);
    self.pixels_per_meter = 1.0 / meters_per_pixel;
    self.camera_position = .{ .x = camera_x, .y = camera_y };
}

/// Convert world meters to framebuffer pixels, with the camera at the image center.
pub fn screenFromWorld(self: *Self, x: f32, y: f32) struct { x: f32, y: f32 } {
    assert(self.pixels_per_meter > 0);
    return .{
        .x = (x - self.camera_position.x) * self.pixels_per_meter + @as(f32, @floatFromInt(self.back_buffer.width)) / 2.0,
        .y = (y - self.camera_position.y) * self.pixels_per_meter + @as(f32, @floatFromInt(self.back_buffer.height)) / 2.0,
    };
}

/// Convert framebuffer pixels to world meters using the current camera and scale.
pub fn worldFromScreen(self: *Self, x: f32, y: f32) struct { x: f32, y: f32 } {
    assert(self.pixels_per_meter > 0);
    return .{
        .x = (x - @as(f32, @floatFromInt(self.back_buffer.width)) / 2.0) / self.pixels_per_meter + self.camera_position.x,
        .y = (y - @as(f32, @floatFromInt(self.back_buffer.height)) / 2.0) / self.pixels_per_meter + self.camera_position.y,
    };
}

pub fn visibleWorldBounds(self: *Self) AABB {
    assert(self.pixels_per_meter > 0);
    const half_width: f32 = @as(f32, @floatFromInt(self.back_buffer.width)) / self.pixels_per_meter / 2.0;
    const half_height: f32 = @as(f32, @floatFromInt(self.back_buffer.height)) / self.pixels_per_meter / 2.0;
    return .{
        .min_x = self.camera_position.x - half_width,
        .min_y = self.camera_position.y - half_height,
        .max_x = self.camera_position.x + half_width,
        .max_y = self.camera_position.y + half_height,
    };
}

pub fn clearScreen(renderer: *Self, r: f32, g: f32, b: f32) void {
    const trace = profile.begin(.renderer_clear);
    defer profile.end(trace);
    const back_buffer: *FrameBuffer = &renderer.back_buffer;

    const red_quantized: u32 = @intFromFloat(@round(r * 255.0));
    const r_int: u8 = @truncate(red_quantized);
    const green_quantized: u32 = @intFromFloat(@round(g * 255.0));
    const g_int: u8 = @truncate(green_quantized);
    const blue_quantized: u32 = @intFromFloat(@round(b * 255.0));
    const b_int: u8 = @truncate(blue_quantized);

    const clear_colour: u32 = (@as(u32, r_int) << 16) | (@as(u32, g_int) << 8) | b_int;

    @memset(back_buffer.pixels(), clear_colour);
}

fn clipped(buffer: *const FrameBuffer, left: f32, top: f32, right: f32, bottom: f32) ?AABB {
    @setFloatMode(.optimized);
    // Keep offscreen coordinates in floating point until the intersection
    // bounds them to the framebuffer; finite inputs can be larger than i64.
    const bounds: AABB = .{
        .min_x = @max(left, 0),
        .min_y = @max(top, 0),
        .max_x = @min(right, @as(f32, @floatFromInt(buffer.width))),
        .max_y = @min(bottom, @as(f32, @floatFromInt(buffer.height))),
    };
    if (bounds.max_x <= bounds.min_x or bounds.max_y <= bounds.min_y) return null;
    return bounds;
}

const PreparedRectangle = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    right_x: f32,
    right_y: f32,
    down_x: f32,
    down_y: f32,
    bounds: AABB,

    const BoundsRounding = enum { pixel_centres, outward };

    fn init(
        buffer: *const FrameBuffer,
        x: f32,
        y: f32,
        width: f32,
        height: f32,
        angle_radians: f32,
        rounding: BoundsRounding,
    ) ?PreparedRectangle {
        @setFloatMode(.optimized);
        if (width <= 0 or height <= 0) return null;
        // Exact pixel-centre bounds are only sufficient for an unrotated rectangle.
        assert(rounding != .pixel_centres or angle_radians == 0);

        const right_x = @cos(angle_radians);
        const right_y = @sin(angle_radians);
        const down_x = -right_y;
        const down_y = right_x;

        const p1_x = x + width * right_x;
        const p1_y = y + width * right_y;
        const p2_x = x + height * down_x;
        const p2_y = y + height * down_y;
        const p3_x = x + height * down_x + width * right_x;
        const p3_y = y + height * down_y + width * right_y;
        const raw_left = @min(x, p1_x, p2_x, p3_x);
        const raw_right = @max(x, p1_x, p2_x, p3_x);
        const raw_top = @min(y, p1_y, p2_y, p3_y);
        const raw_bottom = @max(y, p1_y, p2_y, p3_y);

        // At zero rotation, solve x <= i + 0.5 < x + width once at the bounds.
        // Otherwise include candidate pixels and reject uncovered centres below.
        const left = if (rounding == .pixel_centres) @ceil(raw_left - 0.5) else @floor(raw_left);
        const top = if (rounding == .pixel_centres) @ceil(raw_top - 0.5) else @floor(raw_top);
        const right = if (rounding == .pixel_centres) @ceil(raw_right - 0.5) else @ceil(raw_right);
        const bottom = if (rounding == .pixel_centres) @ceil(raw_bottom - 0.5) else @ceil(raw_bottom);
        return .{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .right_x = right_x,
            .right_y = right_y,
            .down_x = down_x,
            .down_y = down_y,
            .bounds = clipped(buffer, left, top, right, bottom) orelse return null,
        };
    }

    fn coveredPosition(self: PreparedRectangle, pixel_x: f32, pixel_y: f32) ?struct { x: f32, y: f32 } {
        @setFloatMode(.optimized);
        const translated_x = pixel_x - self.x;
        const translated_y = pixel_y - self.y;
        const local_x = translated_x * self.right_x + translated_y * self.right_y;
        const local_y = translated_x * self.down_x + translated_y * self.down_y;

        // Test half-open geometry before scaling to texels. For a 31-pixel
        // texture drawn 7 pixels wide, f32 can round 7 * (31 / 7) below 31
        // and incorrectly admit the ending edge if coverage is tested afterward.
        if (local_x < 0 or local_x >= self.width) return null;
        if (local_y < 0 or local_y >= self.height) return null;
        return .{ .x = local_x, .y = local_y };
    }
};

fn fillSolidRows(buffer: *FrameBuffer, bounds: AABB, packed_color: u32) void {
    const x_min: usize = @intFromFloat(bounds.min_x);
    const y_min: usize = @intFromFloat(bounds.min_y);
    const x_max: usize = @intFromFloat(bounds.max_x);
    const y_max: usize = @intFromFloat(bounds.max_y);
    const pixels = buffer.pixels();
    for (y_min..y_max) |y| {
        const offset = y * @as(usize, buffer.width);
        @memset(pixels[offset + x_min .. offset + x_max], packed_color);
    }
}

// TODO(adi): Maybe have nearest-neighbour sampling and bilinear sampling as options?
pub fn drawTexturedRectangle(
    renderer: *Self,
    // x position in frame buffer coordinate
    x: f32,
    // y position in frame buffer coordinate
    y: f32,
    width: f32,
    height: f32,
    angle_radians: f32,
    texture: Bitmap,
    tint_srgb: ?Color,
) void {
    @setFloatMode(.optimized);
    const trace = profile.begin(.renderer_draw_textured_rectangle);
    defer profile.end(trace);
    if (angle_radians == 0) {
        if (tint_srgb == null) {
            drawSprite(renderer, x, y, width, height, texture);
            return;
        }
    }
    if (width <= 0 or height <= 0) return;
    if (texture.width == 0 or texture.height == 0) return;
    const back_buffer = &renderer.back_buffer;

    const rectangle = PreparedRectangle.init(back_buffer, x, y, width, height, angle_radians, .outward) orelse return;

    const bounds = rectangle.bounds;
    const x_min: usize = @intFromFloat(bounds.min_x);
    const y_min: usize = @intFromFloat(bounds.min_y);
    const x_max: usize = @intFromFloat(bounds.max_x);
    const y_max: usize = @intFromFloat(bounds.max_y);

    const pixels = back_buffer.pixels();

    const texture_width: f32 = @floatFromInt(texture.width);
    const texture_height: f32 = @floatFromInt(texture.height);
    const texels_per_pixel_x = texture_width / width;
    const texels_per_pixel_y = texture_height / height;

    const tint_r: f32, const tint_g: f32, const tint_b: f32, const tint_a: f32 = if (tint_srgb) |tint| blk: {
        break :blk .{ tint.r * tint.r * tint.a, tint.g * tint.g * tint.a, tint.b * tint.b * tint.a, tint.a };
    } else blk: {
        break :blk .{ 1.0, 1.0, 1.0, 1.0 };
    };

    for (y_min..y_max) |j| {
        const pixel_y = @as(f32, @floatFromInt(j)) + 0.5;
        for (x_min..x_max) |i| {
            const pixel_x = @as(f32, @floatFromInt(i)) + 0.5;
            const local = rectangle.coveredPosition(pixel_x, pixel_y) orelse continue;

            // Scale directly to texels: for a native-size 127-pixel texture,
            // (87.5 / 127) * 127 can drift whereas 87.5 * (127 / 127) does not.
            // Subtract 0.5 so integer coordinates address texel centres.
            const texel_x = local.x * texels_per_pixel_x - 0.5;
            const texel_y = local.y * texels_per_pixel_y - 0.5;

            const raw_x0: f32 = @floor(texel_x);
            const raw_y0: f32 = @floor(texel_y);
            const raw_x1 = raw_x0 + 1;
            const raw_y1 = raw_y0 + 1;

            // Distance to center of pixel being sampled. texel_* is the pixel centre in texture space.
            const dx: f32 = texel_x - raw_x0;
            const dy: f32 = texel_y - raw_y0;

            const x0: usize = @intFromFloat(std.math.clamp(raw_x0, 0.0, texture_width - 1));
            const y0: usize = @intFromFloat(std.math.clamp(raw_y0, 0.0, texture_height - 1));
            const x1: usize = @intFromFloat(std.math.clamp(raw_x1, 0.0, texture_width - 1));
            const y1: usize = @intFromFloat(std.math.clamp(raw_y1, 0.0, texture_height - 1));

            // Convention: • denotes the pixel being sampled.
            // A ───── B
            // │       │
            // │   •   │
            // │       │
            // C ───── D
            const pixel_a: [4]u8 = @bitCast(texture.pixels[y0 * texture.width + x0]);
            const pixel_b: [4]u8 = @bitCast(texture.pixels[y0 * texture.width + x1]);
            const pixel_c: [4]u8 = @bitCast(texture.pixels[y1 * texture.width + x0]);
            const pixel_d: [4]u8 = @bitCast(texture.pixels[y1 * texture.width + x1]);

            var pixel_a_b: f32 = @as(f32, @floatFromInt(pixel_a[0])) / 255.0;
            var pixel_a_g: f32 = @as(f32, @floatFromInt(pixel_a[1])) / 255.0;
            var pixel_a_r: f32 = @as(f32, @floatFromInt(pixel_a[2])) / 255.0;
            const pixel_a_a: f32 = @as(f32, @floatFromInt(pixel_a[3])) / 255.0;

            var pixel_b_b: f32 = @as(f32, @floatFromInt(pixel_b[0])) / 255.0;
            var pixel_b_g: f32 = @as(f32, @floatFromInt(pixel_b[1])) / 255.0;
            var pixel_b_r: f32 = @as(f32, @floatFromInt(pixel_b[2])) / 255.0;
            const pixel_b_a: f32 = @as(f32, @floatFromInt(pixel_b[3])) / 255.0;

            var pixel_c_b: f32 = @as(f32, @floatFromInt(pixel_c[0])) / 255.0;
            var pixel_c_g: f32 = @as(f32, @floatFromInt(pixel_c[1])) / 255.0;
            var pixel_c_r: f32 = @as(f32, @floatFromInt(pixel_c[2])) / 255.0;
            const pixel_c_a: f32 = @as(f32, @floatFromInt(pixel_c[3])) / 255.0;

            var pixel_d_b: f32 = @as(f32, @floatFromInt(pixel_d[0])) / 255.0;
            var pixel_d_g: f32 = @as(f32, @floatFromInt(pixel_d[1])) / 255.0;
            var pixel_d_r: f32 = @as(f32, @floatFromInt(pixel_d[2])) / 255.0;
            const pixel_d_a: f32 = @as(f32, @floatFromInt(pixel_d[3])) / 255.0;

            // Gamma-2 decode. Bitmap RGB was premultiplied before encoding;
            pixel_a_b = pixel_a_b * pixel_a_b;
            pixel_a_g = pixel_a_g * pixel_a_g;
            pixel_a_r = pixel_a_r * pixel_a_r;

            pixel_b_b = pixel_b_b * pixel_b_b;
            pixel_b_g = pixel_b_g * pixel_b_g;
            pixel_b_r = pixel_b_r * pixel_b_r;

            pixel_c_b = pixel_c_b * pixel_c_b;
            pixel_c_g = pixel_c_g * pixel_c_g;
            pixel_c_r = pixel_c_r * pixel_c_r;

            pixel_d_b = pixel_d_b * pixel_d_b;
            pixel_d_g = pixel_d_g * pixel_d_g;
            pixel_d_r = pixel_d_r * pixel_d_r;

            const top_r = std.math.lerp(pixel_a_r, pixel_b_r, dx);
            const top_g = std.math.lerp(pixel_a_g, pixel_b_g, dx);
            const top_b = std.math.lerp(pixel_a_b, pixel_b_b, dx);
            const top_a = std.math.lerp(pixel_a_a, pixel_b_a, dx);

            const bottom_r = std.math.lerp(pixel_c_r, pixel_d_r, dx);
            const bottom_g = std.math.lerp(pixel_c_g, pixel_d_g, dx);
            const bottom_b = std.math.lerp(pixel_c_b, pixel_d_b, dx);
            const bottom_a = std.math.lerp(pixel_c_a, pixel_d_a, dx);

            const source_r = std.math.lerp(top_r, bottom_r, dy) * tint_r;
            const source_g = std.math.lerp(top_g, bottom_g, dy) * tint_g;
            const source_b = std.math.lerp(top_b, bottom_b, dy) * tint_b;
            const source_a = std.math.lerp(top_a, bottom_a, dy) * tint_a;

            if (source_a == 0) continue;
            const index = j * @as(usize, back_buffer.width) + i;
            const destination_u8: [4]u8 = @bitCast(pixels[index]);

            var destination_b: f32 = @as(f32, @floatFromInt(destination_u8[0])) / 255.0;
            var destination_g: f32 = @as(f32, @floatFromInt(destination_u8[1])) / 255.0;
            var destination_r: f32 = @as(f32, @floatFromInt(destination_u8[2])) / 255.0;

            destination_r = destination_r * destination_r;
            destination_g = destination_g * destination_g;
            destination_b = destination_b * destination_b;

            var blended_r = source_r + destination_r * (1.0 - source_a);
            var blended_g = source_g + destination_g * (1.0 - source_a);
            var blended_b = source_b + destination_b * (1.0 - source_a);

            blended_r = @sqrt(blended_r);
            blended_g = @sqrt(blended_g);
            blended_b = @sqrt(blended_b);

            const final = [_]u8{
                @truncate(@as(u32, @intFromFloat(@round(blended_b * 255.0)))),
                @truncate(@as(u32, @intFromFloat(@round(blended_g * 255.0)))),
                @truncate(@as(u32, @intFromFloat(@round(blended_r * 255.0)))),
                255,
            };

            pixels[index] = @bitCast(final);
        }
    }
}

/// Draw an untinted, axis-aligned texture in framebuffer pixels.
/// Retains bilinear filtering, premultiplied alpha and gamma-2 conversion.
pub fn drawSprite(
    renderer: *Self,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    texture: Bitmap,
) void {
    @setFloatMode(.optimized);
    const trace = profile.begin(.renderer_draw_sprite);
    defer profile.end(trace);
    if (width <= 0) return;
    if (height <= 0) return;
    if (texture.width == 0) return;
    if (texture.height == 0) return;
    const back_buffer = &renderer.back_buffer;
    // Clip before converting potentially large coordinates to integers.
    const bounds = clipped(
        back_buffer,
        @floor(x),
        @floor(y),
        @ceil(x + width),
        @ceil(y + height),
    ) orelse return;
    const x_min: usize = @intFromFloat(bounds.min_x);
    const y_min: usize = @intFromFloat(bounds.min_y);
    const x_max: usize = @intFromFloat(bounds.max_x);
    const y_max: usize = @intFromFloat(bounds.max_y);
    const pixels = back_buffer.pixels();
    const texture_width: f32 = @floatFromInt(texture.width);
    const texture_height: f32 = @floatFromInt(texture.height);
    const texels_per_pixel_x = texture_width / width;
    const texels_per_pixel_y = texture_height / height;

    // Bounded stack storage, independent of framebuffer size; no frame allocation.
    var cached_x0: [256]usize = undefined;
    var cached_x1: [256]usize = undefined;
    var cached_dx: [256]f32 = undefined;
    var covered_x: [256]bool = undefined;
    var first_x = x_min;

    // NOTE(adi): We process the pixels for all rows and at most 256 columns at a time.
    // this allows us to save on the recalculation of the texel coordinates for each coloumn.
    // We break it up into fixed-sized chunks so that we can just have the cache on the stack.
    while (first_x < x_max) {
        const column_count = @min(cached_x0.len, x_max - first_x);
        for (0..column_count) |column| {
            const pixel_x = @as(f32, @floatFromInt(first_x + column)) + 0.5;
            const local_x = pixel_x - x;

            covered_x[column] = false;
            if (local_x < 0) continue;
            if (local_x >= width) continue;
            covered_x[column] = true;

            const texel_x = local_x * texels_per_pixel_x - 0.5;
            const raw_x0 = @floor(texel_x);
            const raw_x1 = raw_x0 + 1;
            cached_x0[column] = @intFromFloat(std.math.clamp(raw_x0, 0.0, texture_width - 1));
            cached_x1[column] = @intFromFloat(std.math.clamp(raw_x1, 0.0, texture_width - 1));
            cached_dx[column] = texel_x - raw_x0;
        }

        for (y_min..y_max) |j| {
            const pixel_y = @as(f32, @floatFromInt(j)) + 0.5;
            const local_y = pixel_y - y;
            if (local_y < 0) continue;
            if (local_y >= height) continue;

            const texel_y = local_y * texels_per_pixel_y - 0.5;
            const raw_y0 = @floor(texel_y);
            const raw_y1 = raw_y0 + 1;
            const y0: usize = @intFromFloat(std.math.clamp(raw_y0, 0.0, texture_height - 1));
            const y1: usize = @intFromFloat(std.math.clamp(raw_y1, 0.0, texture_height - 1));
            const dy = texel_y - raw_y0;
            const row0 = y0 * texture.width;
            const row1 = y1 * texture.width;
            const destination_row = j * @as(usize, back_buffer.width) + first_x;

            for (0..column_count) |column| {
                if (!covered_x[column]) continue;
                const x0 = cached_x0[column];
                const x1 = cached_x1[column];
                const dx = cached_dx[column];
                const index = destination_row + column;
                const texel_a = texture.pixels[row0 + x0];
                const texel_b = texture.pixels[row0 + x1];
                const texel_c = texture.pixels[row1 + x0];
                const texel_d = texture.pixels[row1 + x1];
                if ((texel_a | texel_b | texel_c | texel_d) >> 24 == 0) continue;
                // Uniform opaque regions need neither filtering nor blending.
                if (texel_a >> 24 == 255) {
                    if (texel_a == texel_b and texel_a == texel_c and texel_a == texel_d) {
                        pixels[index] = texel_a;
                        continue;
                    }
                }

                const pixel_a: [4]u8 = @bitCast(texel_a);
                const pixel_b: [4]u8 = @bitCast(texel_b);
                const pixel_c: [4]u8 = @bitCast(texel_c);
                const pixel_d: [4]u8 = @bitCast(texel_d);

                var pixel_a_b: f32 = @as(f32, @floatFromInt(pixel_a[0])) / 255.0;
                var pixel_a_g: f32 = @as(f32, @floatFromInt(pixel_a[1])) / 255.0;
                var pixel_a_r: f32 = @as(f32, @floatFromInt(pixel_a[2])) / 255.0;
                const pixel_a_a: f32 = @as(f32, @floatFromInt(pixel_a[3])) / 255.0;

                var pixel_b_b: f32 = @as(f32, @floatFromInt(pixel_b[0])) / 255.0;
                var pixel_b_g: f32 = @as(f32, @floatFromInt(pixel_b[1])) / 255.0;
                var pixel_b_r: f32 = @as(f32, @floatFromInt(pixel_b[2])) / 255.0;
                const pixel_b_a: f32 = @as(f32, @floatFromInt(pixel_b[3])) / 255.0;

                var pixel_c_b: f32 = @as(f32, @floatFromInt(pixel_c[0])) / 255.0;
                var pixel_c_g: f32 = @as(f32, @floatFromInt(pixel_c[1])) / 255.0;
                var pixel_c_r: f32 = @as(f32, @floatFromInt(pixel_c[2])) / 255.0;
                const pixel_c_a: f32 = @as(f32, @floatFromInt(pixel_c[3])) / 255.0;

                var pixel_d_b: f32 = @as(f32, @floatFromInt(pixel_d[0])) / 255.0;
                var pixel_d_g: f32 = @as(f32, @floatFromInt(pixel_d[1])) / 255.0;
                var pixel_d_r: f32 = @as(f32, @floatFromInt(pixel_d[2])) / 255.0;
                const pixel_d_a: f32 = @as(f32, @floatFromInt(pixel_d[3])) / 255.0;

                // Gamma-2 decode. Bitmap RGB was premultiplied before encoding;
                pixel_a_b = pixel_a_b * pixel_a_b;
                pixel_a_g = pixel_a_g * pixel_a_g;
                pixel_a_r = pixel_a_r * pixel_a_r;

                pixel_b_b = pixel_b_b * pixel_b_b;
                pixel_b_g = pixel_b_g * pixel_b_g;
                pixel_b_r = pixel_b_r * pixel_b_r;

                pixel_c_b = pixel_c_b * pixel_c_b;
                pixel_c_g = pixel_c_g * pixel_c_g;
                pixel_c_r = pixel_c_r * pixel_c_r;

                pixel_d_b = pixel_d_b * pixel_d_b;
                pixel_d_g = pixel_d_g * pixel_d_g;
                pixel_d_r = pixel_d_r * pixel_d_r;

                const top_r = std.math.lerp(pixel_a_r, pixel_b_r, dx);
                const top_g = std.math.lerp(pixel_a_g, pixel_b_g, dx);
                const top_b = std.math.lerp(pixel_a_b, pixel_b_b, dx);
                const top_a = std.math.lerp(pixel_a_a, pixel_b_a, dx);

                const bottom_r = std.math.lerp(pixel_c_r, pixel_d_r, dx);
                const bottom_g = std.math.lerp(pixel_c_g, pixel_d_g, dx);
                const bottom_b = std.math.lerp(pixel_c_b, pixel_d_b, dx);
                const bottom_a = std.math.lerp(pixel_c_a, pixel_d_a, dx);

                const source_r = std.math.lerp(top_r, bottom_r, dy);
                const source_g = std.math.lerp(top_g, bottom_g, dy);
                const source_b = std.math.lerp(top_b, bottom_b, dy);
                const source_a = std.math.lerp(top_a, bottom_a, dy);

                if (source_a == 0) continue;
                var blended_r = source_r;
                var blended_g = source_g;
                var blended_b = source_b;
                if (source_a != 1) {
                    const destination_u8: [4]u8 = @bitCast(pixels[index]);
                    var destination_b: f32 = @as(f32, @floatFromInt(destination_u8[0])) / 255.0;
                    var destination_g: f32 = @as(f32, @floatFromInt(destination_u8[1])) / 255.0;
                    var destination_r: f32 = @as(f32, @floatFromInt(destination_u8[2])) / 255.0;

                    destination_r = destination_r * destination_r;
                    destination_g = destination_g * destination_g;
                    destination_b = destination_b * destination_b;

                    blended_r += destination_r * (1.0 - source_a);
                    blended_g += destination_g * (1.0 - source_a);
                    blended_b += destination_b * (1.0 - source_a);
                }

                blended_r = @sqrt(blended_r);
                blended_g = @sqrt(blended_g);
                blended_b = @sqrt(blended_b);

                const final = [_]u8{
                    @truncate(@as(u32, @intFromFloat(@round(blended_b * 255.0)))),
                    @truncate(@as(u32, @intFromFloat(@round(blended_g * 255.0)))),
                    @truncate(@as(u32, @intFromFloat(@round(blended_r * 255.0)))),
                    255,
                };

                pixels[index] = @bitCast(final);
            }
        }
        first_x += column_count;
    }
}

/// Draw in framebuffer pixels, independent of the camera and world scale.
/// Positive angles rotate clockwise around (x, y), like drawTexturedRectangle.
pub fn drawRectangle(
    renderer: *Self,
    // x position in frame buffer coordinate
    x: f32,
    // y position in frame buffer coordinate
    y: f32,
    width: f32,
    height: f32,
    angle_radians: f32,
    color_srgb: Color,
) void {
    @setFloatMode(.optimized);
    const trace = profile.begin(.renderer_draw_rectangle);
    defer profile.end(trace);
    const back_buffer = &renderer.back_buffer;
    const rounding: PreparedRectangle.BoundsRounding = if (angle_radians == 0) .pixel_centres else .outward;
    const rectangle = PreparedRectangle.init(back_buffer, x, y, width, height, angle_radians, rounding) orelse return;

    const source_r = color_srgb.r * color_srgb.r * color_srgb.a;
    const source_g = color_srgb.g * color_srgb.g * color_srgb.a;
    const source_b = color_srgb.b * color_srgb.b * color_srgb.a;
    const source_a = color_srgb.a;
    if (angle_radians == 0 and source_a == 1) {
        const packed_color: u32 = @bitCast([_]u8{
            @truncate(@as(u32, @intFromFloat(@round(@sqrt(source_b) * 255.0)))),
            @truncate(@as(u32, @intFromFloat(@round(@sqrt(source_g) * 255.0)))),
            @truncate(@as(u32, @intFromFloat(@round(@sqrt(source_r) * 255.0)))),
            255,
        });
        fillSolidRows(back_buffer, rectangle.bounds, packed_color);
        return;
    }

    const bounds = rectangle.bounds;
    const x_min: usize = @intFromFloat(bounds.min_x);
    const y_min: usize = @intFromFloat(bounds.min_y);
    const x_max: usize = @intFromFloat(bounds.max_x);
    const y_max: usize = @intFromFloat(bounds.max_y);
    const pixels = back_buffer.pixels();

    for (y_min..y_max) |j| {
        const pixel_y = @as(f32, @floatFromInt(j)) + 0.5;
        for (x_min..x_max) |i| {
            if (angle_radians != 0) {
                const pixel_x = @as(f32, @floatFromInt(i)) + 0.5;
                _ = rectangle.coveredPosition(pixel_x, pixel_y) orelse continue;
            }
            const index = j * @as(usize, back_buffer.width) + i;
            const destination_u8: [4]u8 = @bitCast(pixels[index]);

            var destination_b: f32 = @as(f32, @floatFromInt(destination_u8[0])) / 255.0;
            var destination_g: f32 = @as(f32, @floatFromInt(destination_u8[1])) / 255.0;
            var destination_r: f32 = @as(f32, @floatFromInt(destination_u8[2])) / 255.0;

            destination_r = destination_r * destination_r;
            destination_g = destination_g * destination_g;
            destination_b = destination_b * destination_b;

            var blended_r = source_r + destination_r * (1.0 - source_a);
            var blended_g = source_g + destination_g * (1.0 - source_a);
            var blended_b = source_b + destination_b * (1.0 - source_a);

            blended_r = @sqrt(blended_r);
            blended_g = @sqrt(blended_g);
            blended_b = @sqrt(blended_b);

            const final = [_]u8{
                @truncate(@as(u32, @intFromFloat(@round(blended_b * 255.0)))),
                @truncate(@as(u32, @intFromFloat(@round(blended_g * 255.0)))),
                @truncate(@as(u32, @intFromFloat(@round(blended_r * 255.0)))),
                255,
            };

            pixels[index] = @bitCast(final);
        }
    }
}

test "native size texture preserves pixel channels and row stride" {
    var texels = [_]u32{ 0xffff0000, 0xff00ff00, 0xff0000ff, 0xff204080, 0xff000000, 0xffffffff };
    var pixels: [6]u32 align(4096) = @splat(0);
    var renderer: Self = .{
        .back_buffer = .{ .width = 3, .height = 2, .data = std.mem.sliceAsBytes(&pixels) },
        .pixels_per_meter = 1,
        .camera_position = .{ .x = 0, .y = 0 },
        .textures = undefined,
        .debug_color = Color.magenta.toARGB(),
    };
    renderer.drawTexturedRectangle(0, 0, 3, 2, 0, .{ .width = 3, .height = 2, .pixels = &texels }, null);
    try std.testing.expectEqualSlices(u32, &texels, &pixels);
}

test "bilinear texture filtering averages linear colors and clamps edge texels" {
    var texels = [_]u32{ 0xffff0000, 0xff00ff00, 0xff0000ff, 0xffffffff };
    const texture: Bitmap = .{ .width = 2, .height = 2, .pixels = &texels };
    var pixels: [16]u32 align(4096) = @splat(0);
    var renderer: Self = .{
        .back_buffer = .{ .width = 4, .height = 4, .data = std.mem.sliceAsBytes(&pixels) },
        .pixels_per_meter = 1,
        .camera_position = .{ .x = 0, .y = 0 },
        .textures = undefined,
        .debug_color = undefined,
    };
    // The centre averages all four texels: each linear RGB channel is 0.5.
    renderer.drawTexturedRectangle(0, 0, 1, 1, 0, texture, null);
    try std.testing.expectEqual(@as(u32, 0xffb4b4b4), pixels[0]);

    renderer.drawTexturedRectangle(0, 0, 4, 4, 0, texture, null);
    try std.testing.expectEqual(@as(u32, 0xffff0000), pixels[0]);
    try std.testing.expectEqual(@as(u32, 0xff00ff00), pixels[3]);
    try std.testing.expectEqual(@as(u32, 0xff0000ff), pixels[12]);
    try std.testing.expectEqual(@as(u32, 0xffffffff), pixels[15]);
}

test "offscreen rectangles clip without overwriting the framebuffer boundary" {
    const Case = struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
        angle_radians: f32 = 0,
        left: usize = 0,
        top: usize = 0,
        right: usize = 0,
        bottom: usize = 0,
    };
    const cases = [_]Case{
        .{ .x = 0, .y = -3, .width = 10, .height = 2 },
        .{ .x = -3, .y = 0, .width = 2, .height = 10 },
        .{ .x = -3, .y = 0, .width = 10, .height = 2, .right = 7, .bottom = 2 },
        .{ .x = 0, .y = -3, .width = 2, .height = 10, .right = 2, .bottom = 7 },
        .{ .x = -1, .y = -1, .width = 20, .height = 20, .right = 16, .bottom = 16 },
        .{
            .x = 14,
            .y = 14,
            .width = 4,
            .height = 4,
            .left = 14,
            .top = 14,
            .right = 16,
            .bottom = 16,
        },
        .{ .x = 16, .y = 0, .width = 2, .height = 10 },
        .{ .x = 0, .y = 16, .width = 10, .height = 2 },
        .{ .x = -2, .y = 0, .width = 2, .height = 10 },
        .{ .x = 0, .y = -2, .width = 10, .height = 2 },
        .{ .x = 4, .y = 4, .width = 0, .height = 4 },
        .{ .x = 4, .y = 4, .width = 4, .height = -1 },
        .{ .x = 1.5, .y = 1.5, .width = 2, .height = 2, .left = 1, .top = 1, .right = 3, .bottom = 3 },
        .{ .x = 1.75, .y = 1.75, .width = 2, .height = 2, .left = 2, .top = 2, .right = 4, .bottom = 4 },
        .{ .x = 5, .y = 2, .width = 2, .height = 3, .angle_radians = std.math.pi / 2.0, .left = 2, .top = 2, .right = 5, .bottom = 4 },
        .{ .x = 1, .y = 2, .width = 2, .height = 3, .angle_radians = std.math.pi / 2.0, .top = 2, .right = 1, .bottom = 4 },
        // Each operand fits i32, but their sum does not. Offscreen geometry must
        // remain a no-op rather than overflow before clipping.
        .{ .x = 1073741824, .y = 1073741824, .width = 1073741824, .height = 1073741824 },
        // Finite f32 bounds can exceed i64. Clip before converting to integers.
        .{ .x = 1e20, .y = 0, .width = 4, .height = 4 },
        .{ .x = -1e20, .y = 0, .width = 4, .height = 4 },
        .{ .x = 0, .y = 1e20, .width = 4, .height = 4 },
        .{ .x = 0, .y = -1e20, .width = 4, .height = 4 },
        .{ .x = 1e20, .y = 0, .width = 4, .height = 4, .angle_radians = std.math.pi / 4.0 },
        // Large intersecting rectangles must still draw their visible portion.
        .{ .x = 4, .y = 2, .width = 1e20, .height = 3, .left = 4, .top = 2, .right = 16, .bottom = 5 },
        .{ .x = 2, .y = 4, .width = 3, .height = 1e20, .left = 2, .top = 4, .right = 5, .bottom = 16 },
        .{ .x = -1e20, .y = -1e20, .width = 2e20, .height = 2e20, .right = 16, .bottom = 16 },
        .{ .x = 0, .y = -1e20, .width = 2e20, .height = 2e20, .angle_radians = std.math.pi / 4.0, .right = 16, .bottom = 16 },
    };

    for (cases) |case| {
        // The trailing pixels detect writes past the framebuffer in fast builds too.
        var pixels: [16 * 16 + 16]u32 align(4096) = @splat(0);
        @memset(pixels[16 * 16 ..], 0x12345678);
        var renderer: Self = .{
            .back_buffer = .{
                .width = 16,
                .height = 16,
                .data = std.mem.sliceAsBytes(pixels[0 .. 16 * 16]),
            },
            .pixels_per_meter = 48,
            .camera_position = .{ .x = 10, .y = -4 },
            .textures = undefined,
            .debug_color = undefined,
        };

        renderer.drawRectangle(case.x, case.y, case.width, case.height, case.angle_radians, .white);

        for (pixels[0 .. 16 * 16], 0..) |pixel, index| {
            const x = index % 16;
            const y = index / 16;
            const expected: u32 = if (x >= case.left and x < case.right and
                y >= case.top and y < case.bottom) 0xffffffff else 0;
            try std.testing.expectEqual(expected, pixel);
        }
        for (pixels[16 * 16 ..]) |pixel| try std.testing.expectEqual(@as(u32, 0x12345678), pixel);
    }
}

test "textured rectangles clip and exclude ending edges irrespective of texture size" {
    const Case = struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
        angle_radians: f32 = 0,
        texture_width: usize,
        texture_height: usize,
        left: usize = 0,
        top: usize = 0,
        right: usize,
        bottom: usize,
    };
    const cases = [_]Case{
        // Pixel centres lie on both edges: include the start, exclude the end.
        // In f32, (31 / 7) * 7 can round below 31 and admit the ending edge.
        .{ .x = 0.5, .y = 0, .width = 7, .height = 1, .texture_width = 31, .texture_height = 1, .right = 7, .bottom = 1 },
        .{ .x = 0, .y = 0.5, .width = 1, .height = 7, .texture_width = 1, .texture_height = 31, .right = 1, .bottom = 7 },
        .{ .x = 1.5, .y = 1.5, .width = 7, .height = 7, .texture_width = 31, .texture_height = 31, .left = 1, .top = 1, .right = 8, .bottom = 8 },
        // A different scale also exercises the boundary with optimized math.
        .{ .x = 0.5, .y = 0, .width = 41, .height = 1, .texture_width = 1, .texture_height = 1, .right = 41, .bottom = 1 },
        .{ .x = 0, .y = 0.5, .width = 1, .height = 41, .texture_width = 1, .texture_height = 1, .right = 1, .bottom = 41 },
        // Clipping preserves the original local coordinates and ending edges.
        .{ .x = -3.5, .y = -3.5, .width = 7, .height = 7, .texture_width = 31, .texture_height = 31, .right = 3, .bottom = 3 },
        // Centres strictly inside the rectangle must remain covered.
        .{ .x = 1, .y = 1, .width = 7, .height = 7, .texture_width = 31, .texture_height = 31, .left = 1, .top = 1, .right = 8, .bottom = 8 },
        .{ .x = 1.75, .y = 1.75, .width = 7, .height = 7, .texture_width = 31, .texture_height = 31, .left = 2, .top = 2, .right = 9, .bottom = 9 },
        // Both public entry points reject empty or negative destination sizes.
        .{ .x = 0, .y = 0, .width = 0, .height = 7, .texture_width = 1, .texture_height = 1, .right = 0, .bottom = 0 },
        .{ .x = 0, .y = 0, .width = 7, .height = 0, .texture_width = 1, .texture_height = 1, .right = 0, .bottom = 0 },
        .{ .x = 0, .y = 0, .width = -1, .height = 7, .texture_width = 1, .texture_height = 1, .right = 0, .bottom = 0 },
        .{ .x = 0, .y = 0, .width = 7, .height = -1, .texture_width = 1, .texture_height = 1, .right = 0, .bottom = 0 },
        // Empty textures remain a no-op when coverage is checked in local space.
        .{ .x = 0, .y = 0, .width = 7, .height = 7, .texture_width = 0, .texture_height = 1, .right = 0, .bottom = 0 },
        .{ .x = 0, .y = 0, .width = 7, .height = 7, .texture_width = 1, .texture_height = 0, .right = 0, .bottom = 0 },
        // Finite bounds outside i64 must be clipped before integer conversion.
        .{ .x = 1e20, .y = 0, .width = 4, .height = 4, .texture_width = 1, .texture_height = 1, .right = 0, .bottom = 0 },
        .{ .x = -1e20, .y = 0, .width = 4, .height = 4, .texture_width = 1, .texture_height = 1, .right = 0, .bottom = 0 },
        .{ .x = 0, .y = 1e20, .width = 4, .height = 4, .texture_width = 1, .texture_height = 1, .right = 0, .bottom = 0 },
        .{ .x = 0, .y = -1e20, .width = 4, .height = 4, .texture_width = 1, .texture_height = 1, .right = 0, .bottom = 0 },
        .{ .x = 1e20, .y = 0, .width = 4, .height = 4, .angle_radians = std.math.pi / 4.0, .texture_width = 1, .texture_height = 1, .right = 0, .bottom = 0 },
        // Intersecting rectangles retain their visible portion, including rotation.
        .{ .x = 4, .y = 2, .width = 1e20, .height = 3, .texture_width = 1, .texture_height = 1, .left = 4, .top = 2, .right = 48, .bottom = 5 },
        .{ .x = 2, .y = 4, .width = 3, .height = 1e20, .texture_width = 1, .texture_height = 1, .left = 2, .top = 4, .right = 5, .bottom = 48 },
        .{ .x = -1e20, .y = -1e20, .width = 2e20, .height = 2e20, .texture_width = 1, .texture_height = 1, .right = 48, .bottom = 48 },
        .{ .x = 0, .y = -1e20, .width = 2e20, .height = 2e20, .angle_radians = std.math.pi / 4.0, .texture_width = 1, .texture_height = 1, .right = 48, .bottom = 48 },
    };
    var texels: [31 * 31]u32 = @splat(0xffffffff);

    for (cases) |case| {
        for ([_]bool{ false, true }) |direct_tile| {
            if (direct_tile) {
                if (case.angle_radians != 0) continue;
            }
            var pixels: [48 * 48 + 16]u32 align(4096) = @splat(0);
            @memset(pixels[48 * 48 ..], 0x12345678);
            var renderer: Self = .{
                .back_buffer = .{
                    .width = 48,
                    .height = 48,
                    .data = std.mem.sliceAsBytes(pixels[0 .. 48 * 48]),
                },
                .pixels_per_meter = 1,
                .camera_position = .{ .x = 0, .y = 0 },
                .textures = undefined,
                .debug_color = undefined,
            };
            const texture: Bitmap = .{
                .width = case.texture_width,
                .height = case.texture_height,
                .pixels = texels[0 .. case.texture_width * case.texture_height],
            };

            if (direct_tile) {
                renderer.drawSprite(case.x, case.y, case.width, case.height, texture);
            } else {
                renderer.drawTexturedRectangle(case.x, case.y, case.width, case.height, case.angle_radians, texture, null);
            }

            for (pixels[0 .. 48 * 48], 0..) |pixel, index| {
                const x = index % 48;
                const y = index / 48;
                const expected: u32 = if (x >= case.left and x < case.right and
                    y >= case.top and y < case.bottom) 0xffffffff else 0;
                try std.testing.expectEqual(expected, pixel);
            }
            for (pixels[48 * 48 ..]) |pixel| try std.testing.expectEqual(@as(u32, 0x12345678), pixel);
        }
    }
}

test "rotated rectangles blend only covered pixel centres" {
    var pixels: [8 * 8]u32 align(4096) = @splat(0xff0000ff);
    var renderer: Self = .{
        .back_buffer = .{ .width = 8, .height = 8, .data = std.mem.sliceAsBytes(&pixels) },
        .pixels_per_meter = 1,
        .camera_position = .{ .x = 0, .y = 0 },
        .textures = undefined,
        .debug_color = undefined,
    };
    renderer.drawRectangle(4, 1.25, 3, 3, std.math.pi / 4.0, .{ .r = 1, .g = 0, .b = 0, .a = 0.5 });

    // A 45-degree square forms a diamond. These pixel centres are strictly
    // inside it; the other pixels in its bounding box must remain blue.
    const coverage = [_][]const u8{
        "........",
        "........",
        "...##...",
        "..####..",
        "...##...",
        "........",
        "........",
        "........",
    };
    for (pixels, 0..) |pixel, index| {
        const expected: u32 = if (coverage[index / 8][index % 8] == '#') 0xffb400b4 else 0xff0000ff;
        try std.testing.expectEqual(expected, pixel);
    }
}
