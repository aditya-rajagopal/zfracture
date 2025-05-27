// TODO: Maybe just use stb_image in a tool that processes the image into a fracture format and read that here.
const png = @import("image/png.zig");
pub const ImageFileType = T.ImageFileType;
pub const Image = T.Image;

pub const ImageType = enum(u8) {
    g,
    ga,
    rgb,
    rgba,
};

pub const LoadImageError = Allocator.Error || std.fs.File.OpenError || std.fs.File.ReadError;

/// Load an image from a file.
/// TODO: There should be 1 asset managment system that handles all of this
pub fn load(
    /// The filename of the image to load. This is a relative path to the current working directory.
    filename: []const u8,
    /// The allocator to use for allocating the image data and other intermediate data.
    allocator: Allocator,
    /// The configuration for the load operation.
    comptime load_config: ImageLoadConfig,
) (LoadImageError || png.PNGError)!T.Image {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    switch (load_config.format) {
        .png => return png.read(file, allocator, load_config),
        else => @compileError("Unsupported filetype"),
    }
}

// test "PNG" {
//     // const types = enum { all };
//     // const testing_allocator = TrackingAlloctor(.@"test", types, true);
//     // var talloc = testing_allocator{};
//     // var logger = log.LogConfig{};
//     // try logger.stderr_init();
//     //
//     // talloc.init(std.heap.page_allocator, &logger);
//     // const allocator = talloc.get_type_allocator(.all);
//     const allocator = std.heap.page_allocator;
//
//     var start = std.time.Timer.start() catch unreachable;
//     const out = try load("gray_rock2.png", allocator, .{ .requested_channels = 4 });
//     const end = start.read();
//     std.debug.print("Time: {s}\n", .{std.fmt.fmtDuration(end)});
//     // const row = 24;
//     // const size = 1024;
//     // const col = 1;
//     // std.debug.print("OUtput: {d}\n", .{out[row * size * 4 + col * 4 .. row * size * 4 + 4 + col * 4]});
//
//     // talloc.print_memory_stats();
//
//     allocator.free(out.data);
// }

const T = @import("image/types.zig");
const ImageLoadConfig = T.ImageLoadConfig;
const TrackingAlloctor = @import("memory.zig").TrackingAllocator;
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
