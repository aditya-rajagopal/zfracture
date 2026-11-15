const std = @import("std");
const png = @import("stdx/png.zig");
const Bitmap = @import("bitmap.zig");
const font = @import("monogram.zig");
const pixel_count = font.pixel_count;

pub fn bake(comptime encoded_png: []const u8) [pixel_count * 4]u8 {
    @setEvalBranchQuota(3_000_000);
    var scratch: [128 * 1024]u8 = undefined;
    var arena = std.heap.FixedBufferAllocator.init(&scratch);
    var output: DecodeBuffer = .{};
    var diagnostic: ?[]const u8 = null;
    const image = png.fromMemory(encoded_png, arena.allocator(), output.allocator(), &diagnostic, .{
        .requested_channels = 4,
        .flip_vertical_on_load = false,
    }) catch |err| @compileError("Monogram PNG: " ++ (diagnostic orelse @errorName(err)));
    if (image.width != font.width or image.height != font.height or image.channels != 4)
        @compileError("expected a 96×96 RGBA Monogram atlas");

    // Monogram's ink is black. Retain its coverage and let the draw tint supply the color.
    for (0..pixel_count) |i| @memset(image.data[i * 4 ..][0..3], 255);
    const bitmap = Bitmap.prepareFromPNG(image);
    return std.mem.sliceAsBytes(bitmap.pixels)[0 .. pixel_count * 4].*;
}

const DecodeBuffer = struct {
    bytes: [pixel_count * 4]u8 align(4) = undefined,
    used: bool = false,

    fn allocator(self: *DecodeBuffer) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{
            .alloc = alloc,
            .resize = std.mem.Allocator.noResize,
            .remap = std.mem.Allocator.noRemap,
            .free = std.mem.Allocator.noFree,
        } };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
        const self: *DecodeBuffer = @ptrCast(@alignCast(ctx));
        if (self.used or len != self.bytes.len or alignment.toByteUnits() > 4) return null;
        self.used = true;
        return &self.bytes;
    }
};
