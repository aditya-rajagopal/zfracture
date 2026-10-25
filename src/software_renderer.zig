const std = @import("std");
const assert = std.debug.assert;

const types = @import("types.zig");
const Color = types.Color;
const Bitmap = types.Bitmap;

const AABB = @import("aabb.zig");

const Renderer = @This();

back_buffer: FrameBuffer,
pixels_per_meter: f32,
camera_position: struct { x: f32, y: f32 },

pub const FrameBuffer = struct {
    width: u16,
    height: u16,
    data: []align(4096) u8,
};

pub const bytes_per_pixel: usize = 4;

// TODO: This is basically setting the viewmatrix
pub fn setMetersPerPixel(renderer: *Renderer, meters_per_pixel: f32) void {
    assert(meters_per_pixel != 0);
    renderer.pixels_per_meter = 1.0 / meters_per_pixel;
}

/// Convert world meters to framebuffer pixels, with the camera at the image center.
pub fn screenFromWorld(self: *Renderer, x: f32, y: f32) struct { x: f32, y: f32 } {
    assert(self.pixels_per_meter > 0);
    return .{
        .x = (x - self.camera_position.x) * self.pixels_per_meter + @as(f32, @floatFromInt(self.back_buffer.width)) / 2.0,
        .y = (y - self.camera_position.y) * self.pixels_per_meter + @as(f32, @floatFromInt(self.back_buffer.height)) / 2.0,
    };
}

/// Convert framebuffer pixels to world meters using the current camera and scale.
pub fn worldFromScreen(self: *Renderer, x: f32, y: f32) struct { x: f32, y: f32 } {
    assert(self.pixels_per_meter > 0);
    return .{
        .x = (x - @as(f32, @floatFromInt(self.back_buffer.width)) / 2.0) / self.pixels_per_meter + self.camera_position.x,
        .y = (y - @as(f32, @floatFromInt(self.back_buffer.height)) / 2.0) / self.pixels_per_meter + self.camera_position.y,
    };
}

pub fn updateCameraTo(renderer: *Renderer, x: f32, y: f32) void {
    renderer.camera_position = .{ .x = x, .y = y };
}

pub fn visibleWorldBounds(self: *Renderer) AABB {
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

pub fn clearScreen(renderer: *Renderer, r: f32, g: f32, b: f32) void {
    const back_buffer: *FrameBuffer = &renderer.back_buffer;

    const red_quantized: u32 = @intFromFloat(@round(r * 255.0));
    const r_int: u8 = @truncate(red_quantized);
    const green_quantized: u32 = @intFromFloat(@round(g * 255.0));
    const g_int: u8 = @truncate(green_quantized);
    const blue_quantized: u32 = @intFromFloat(@round(b * 255.0));
    const b_int: u8 = @truncate(blue_quantized);

    const clear_colour: u32 = (@as(u32, r_int) << 16) | (@as(u32, g_int) << 8) | b_int;

    const total_pixels: usize = @as(usize, back_buffer.width) * @as(usize, back_buffer.height);
    const pixles_u32: []u32 = @ptrCast(back_buffer.data[0 .. total_pixels * bytes_per_pixel]);
    @memset(pixles_u32[0..total_pixels], clear_colour);
}

// TODO(adi): Maybe have nearest-neighbour sampling and bilinear sampling as options?
pub fn drawTexturedRectangle(
    renderer: *Renderer,
    // x position in frame buffer coordinate
    x: f32,
    // y position in frame buffer coordinate
    y: f32,
    width: f32,
    height: f32,
    texture: Bitmap,
) void {
    @setFloatMode(.optimized);
    const back_buffer: *FrameBuffer = &renderer.back_buffer;

    // We deliberately chose a slightly larger bound here and the uv coordinates
    // are clamped to the texture bounds. This is to avoid rounding errors
    // causing the texture to be sampled outside the bounds.
    const left_int: i64 = @intFromFloat(@floor(x));
    const top_int: i64 = @intFromFloat(@floor(y));
    const right_int: i64 = @intFromFloat(@ceil(x + width));
    const bottom_int: i64 = @intFromFloat(@ceil(y + height));

    const left: i64 = @max(left_int, 0);
    const top: i64 = @max(top_int, 0);
    const right: i64 = @min(right_int, back_buffer.width);
    const bottom: i64 = @min(bottom_int, back_buffer.height);
    if (right <= left or bottom <= top) return;

    const x_min: usize = @intCast(left);
    const y_min: usize = @intCast(top);
    const x_max: usize = @intCast(right);
    const y_max: usize = @intCast(bottom);

    const total_pixels: usize = @as(usize, back_buffer.width) * @as(usize, back_buffer.height);
    const pixles_u32: []u32 = @ptrCast(back_buffer.data[0 .. total_pixels * bytes_per_pixel]);

    const inv_width: f32 = 1.0 / width;
    const inv_height: f32 = 1.0 / height;

    const texture_width: f32 = @floatFromInt(texture.width);
    const texture_height: f32 = @floatFromInt(texture.height);

    for (y_min..y_max) |j| {
        const pixel_y: f32 = @as(f32, @floatFromInt(j)) + 0.5;
        const v = (pixel_y - y) * inv_height;
        if (v < 0 or v >= 1) continue;
        // NOTE(adi): We do -0.5 makes it so integer texel coordinates refer to the centre of the texel.
        // for texel i: (i + 0.5) / texture_width is the canonical centre.
        // Got this from GPU Gems
        const texel_y = v * texture_height - 0.5;

        for (x_min..x_max) |i| {
            const pixel_x: f32 = @as(f32, @floatFromInt(i)) + 0.5;
            const u = (pixel_x - x) * inv_width;
            if (u < 0 or u >= 1) continue;
            const texel_x = u * texture_width - 0.5;

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

            // NOTE(adi): We assume the texture is sRGB encoded and premultiplied by the alpha.
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

            const destination_u8: [4]u8 = @bitCast(pixles_u32[j * back_buffer.width + i]);

            if (source_a == 0) continue;

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

            pixles_u32[j * back_buffer.width + i] = @bitCast(final);
        }
    }
}

/// Draw in framebuffer pixels, independent of the camera and world scale.
pub fn drawRectangle(
    renderer: *Renderer,
    // x position in frame buffer coordinate
    x: f32,
    // y position in frame buffer coordinate
    y: f32,
    width: f32,
    height: f32,
    color: Color,
) void {
    @setFloatMode(.optimized);
    const back_buffer: *FrameBuffer = &renderer.back_buffer;

    // Round fractional pixel positions and sizes before rasterizing.
    const left_int: i64 = @intFromFloat(@round(x));
    const top_int: i64 = @intFromFloat(@round(y));
    const right_int: i64 = @intFromFloat(@round(x + width));
    const bottom_int: i64 = @intFromFloat(@round(y + height));

    // Offscreen endpoints can overflow i32 before clipping, so add them in i64.
    const left: i64 = @max(left_int, 0);
    const top: i64 = @max(top_int, 0);
    const right: i64 = @min(right_int, back_buffer.width);
    const bottom: i64 = @min(bottom_int, back_buffer.height);
    if (right <= left or bottom <= top) return;

    const x_min: usize = @intCast(left);
    const y_min: usize = @intCast(top);
    const x_max: usize = @intCast(right);
    const y_max: usize = @intCast(bottom);

    const total_pixels: usize = @as(usize, back_buffer.width) * @as(usize, back_buffer.height);
    const pixles_u32: []u32 = @ptrCast(back_buffer.data[0 .. total_pixels * bytes_per_pixel]);

    const source_r: f32 = color.r * color.r * color.a;
    const source_g: f32 = color.g * color.g * color.a;
    const source_b: f32 = color.b * color.b * color.a;
    const source_a: f32 = color.a;

    for (y_min..y_max) |j| {
        for (x_min..x_max) |i| {
            const destination_u8: [4]u8 = @bitCast(pixles_u32[j * back_buffer.width + i]);

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

            pixles_u32[j * back_buffer.width + i] = @bitCast(final);
        }
    }
}

test "offscreen rectangles clip without overwriting the framebuffer boundary" {
    const Case = struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
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
        // Each operand fits i32, but their sum does not. Offscreen geometry must
        // remain a no-op rather than overflow before clipping.
        .{ .x = 1073741824, .y = 1073741824, .width = 1073741824, .height = 1073741824 },
    };

    for (cases) |case| {
        // The trailing pixels detect writes past the framebuffer in fast builds too.
        var pixels: [16 * 16 + 16]u32 align(4096) = @splat(0);
        @memset(pixels[16 * 16 ..], 0x12345678);
        var renderer: Renderer = .{
            .back_buffer = .{
                .width = 16,
                .height = 16,
                .data = std.mem.sliceAsBytes(pixels[0 .. 16 * 16]),
            },
            .pixels_per_meter = 48,
            .camera_position = .{ .x = 10, .y = -4 },
        };

        renderer.drawRectangle(case.x, case.y, case.width, case.height, .white);

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

// INCOMPLETE
pub const CommandType = enum(u8) {
    set_view,
    clear_screen,
    draw_rectangle,
};

pub const SetViewCommand = struct {
    meters_per_pixel: f32,
};

pub const ClearCommand = struct {
    clear_color: Color,
};

pub const DrawRectangleCommand = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    color: Color,
};

pub const RenderQueue = struct {
    commands: std.ArrayList(CommandType),
    data: std.ArrayList(u8),
    allocator: std.mem.Allocator,
};
// INCOMPLETE
