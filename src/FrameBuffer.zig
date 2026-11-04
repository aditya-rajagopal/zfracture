const FrameBuffer = @This();

width: u16,
height: u16,
data: []align(4096) u8,

pub const bytes_per_pixel: usize = 4;

pub fn initCapacity(width: u16, height: u16, gpa: std.mem.Allocator) !FrameBuffer {
    const data = try gpa.alignedAlloc(
        u8,
        .fromByteUnits(4096),
        @as(usize, width) * height * bytes_per_pixel,
    );
    return .{
        .width = width,
        .height = height,
        .data = data,
    };
}

pub fn deinit(self: FrameBuffer, gpa: std.mem.Allocator) void {
    gpa.free(self.data);
}

pub fn pixels(self: FrameBuffer) []u32 {
    const count = @as(usize, self.width) * @as(usize, self.height);
    return @ptrCast(self.data[0 .. count * bytes_per_pixel]);
}

const std = @import("std");
