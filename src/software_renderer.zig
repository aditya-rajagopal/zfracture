const std = @import("std");
const assert = std.debug.assert;

const types = @import("types.zig");
const Color = types.Color;

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

pub fn clearScreen(renderer: *Renderer, r: f32, g: f32, b: f32) void {
    const back_buffer: *FrameBuffer = &renderer.back_buffer;
    const r_int: u8 = @truncate(@as(u32, @intFromFloat(@round(r * 255.0))));
    const g_int: u8 = @truncate(@as(u32, @intFromFloat(@round(g * 255.0))));
    const b_int: u8 = @truncate(@as(u32, @intFromFloat(@round(b * 255.0))));
    const clear_colour: u32 = (@as(u32, @intCast(r_int)) << 16) | (@as(u32, @intCast(g_int)) << 8) | @as(u32, @intCast(b_int));

    const total_pixels: usize = @as(usize, @intCast(back_buffer.width)) * @as(usize, @intCast(back_buffer.height));
    const pixles_u32: []u32 = @ptrCast(back_buffer.data[0 .. total_pixels * bytes_per_pixel]);
    @memset(pixles_u32[0..total_pixels], clear_colour);
}

pub fn drawRectangle(renderer: *Renderer, x: f32, y: f32, width: f32, height: f32, colour: Color) void {
    @setFloatMode(.optimized);
    const back_buffer: *FrameBuffer = &renderer.back_buffer;
    // TODO: Consider blending
    // NOTE: We are rounding here to if the position of the corner covers most of a pixel in x or y we will draw it.
    var x_int: i32 = @intFromFloat(@round(x * renderer.pixels_per_meter));
    var y_int: i32 = @intFromFloat(@round(y * renderer.pixels_per_meter));
    // @TODO: Should we do x + width and then round it?
    var width_int: i32 = @intFromFloat(@round(width * renderer.pixels_per_meter));
    var height_int: i32 = @intFromFloat(@round(height * renderer.pixels_per_meter));

    // NOTE: If the position is too far off screen to draw a rectangle we dont draw it
    if (y_int > back_buffer.height or
        x_int > back_buffer.width or
        y_int < -width_int or
        x_int < -height_int)
    {
        return;
    }

    // NOTE: Clamping so we dont overflow the buffer and only draw the visible part of the rectangle
    if (x_int < 0) {
        width_int += x_int;
        x_int = 0;
    } else if (x_int + width_int > back_buffer.width) {
        width_int = back_buffer.width - x_int;
    }
    if (y_int < 0) {
        height_int += y_int;
        y_int = 0;
    } else if (y_int + height_int > back_buffer.height) {
        height_int = back_buffer.height - y_int;
    }

    const x_uint: u32 = @intCast(x_int);
    const y_uint: u32 = @intCast(y_int);
    const width_uint: u32 = @intCast(width_int);
    const height_uint: u32 = @intCast(height_int);

    const colour_u32: u32 = colour.a8r8g8b8();

    const total_pixels: usize = @as(usize, @intCast(back_buffer.width)) * @as(usize, @intCast(back_buffer.height));
    const pixles_u32: []u32 = @ptrCast(back_buffer.data[0 .. total_pixels * bytes_per_pixel]);

    for (0..height_uint) |j| {
        for (0..width_uint) |i| {
            pixles_u32[(y_uint + j) * back_buffer.width + x_uint + i] = colour_u32;
        }
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
