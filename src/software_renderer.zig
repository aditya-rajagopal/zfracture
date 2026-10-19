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

pub fn drawRectangle(
    renderer: *Renderer,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    colour: Color,
) void {
    @setFloatMode(.optimized);
    const back_buffer: *FrameBuffer = &renderer.back_buffer;

    // TODO: Consider blending
    // NOTE: We are rounding here to if the position of the corner covers most of a pixel in x or y
    // we will draw it.
    const x_int: i32 = @intFromFloat(@round(x * renderer.pixels_per_meter));
    const y_int: i32 = @intFromFloat(@round(y * renderer.pixels_per_meter));
    // @TODO: Should we do x + width and then round it?
    const width_int: i32 = @intFromFloat(@round(width * renderer.pixels_per_meter));
    const height_int: i32 = @intFromFloat(@round(height * renderer.pixels_per_meter));

    // Offscreen endpoints can overflow i32 before clipping, so add them in i64.
    const left = @max(@as(i64, x_int), 0);
    const top = @max(@as(i64, y_int), 0);
    const right = @min(@as(i64, x_int) + width_int, back_buffer.width);
    const bottom = @min(@as(i64, y_int) + height_int, back_buffer.height);
    if (right <= left or bottom <= top) return;

    const x_min: usize = @intCast(left);
    const y_min: usize = @intCast(top);
    const x_max: usize = @intCast(right);
    const y_max: usize = @intCast(bottom);

    const colour_u32: u32 = colour.a8r8g8b8();

    const total_pixels: usize = @as(usize, back_buffer.width) * @as(usize, back_buffer.height);
    const pixles_u32: []u32 = @ptrCast(back_buffer.data[0 .. total_pixels * bytes_per_pixel]);

    for (y_min..y_max) |j| {
        for (x_min..x_max) |i| {
            pixles_u32[j * back_buffer.width + i] = colour_u32;
        }
    }
}

test "rectangle_clipping" {
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
            .pixels_per_meter = 1,
            .camera_position = .{ .x = 0, .y = 0 },
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
