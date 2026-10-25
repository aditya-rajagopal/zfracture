pub const Bitmap = @This();

width: usize,
height: usize,
// Top-down rows of tightly packed 0xAARRGGBB pixels.
// RGB is premultiplied in linear space, then encoded; alpha is stored unchanged.
pixels: []u32,

pub fn prepareFromPNG(image: png.Image) Bitmap {
    std.debug.assert(image.channels == 4);
    for (0..image.height) |y| {
        for (0..image.width) |x| {
            const offset = (y * image.width + x) * 4;
            const pixel: [4]u8 = @bitCast(image.data[offset..][0..4].*);
            var r: f32 = @as(f32, @floatFromInt(pixel[0])) / 255.0;
            var g: f32 = @as(f32, @floatFromInt(pixel[1])) / 255.0;
            var b: f32 = @as(f32, @floatFromInt(pixel[2])) / 255.0;
            const a: f32 = @as(f32, @floatFromInt(pixel[3])) / 255.0;

            r = @sqrt(r * r * a);
            g = @sqrt(g * g * a);
            b = @sqrt(b * b * a);

            image.data[offset] = @intFromFloat(@round(b * 255.0));
            image.data[offset + 1] = @intFromFloat(@round(g * 255.0));
            image.data[offset + 2] = @intFromFloat(@round(r * 255.0));
            image.data[offset + 3] = pixel[3];
        }
    }
    return .{
        .width = image.width,
        .height = image.height,
        .pixels = @as([*]u32, @ptrCast(image.data.ptr))[0 .. image.height * image.width],
    };
}

const std = @import("std");
const png = @import("stdx/png.zig");
