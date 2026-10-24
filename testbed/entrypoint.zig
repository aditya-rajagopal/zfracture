const std = @import("std");
const fr = @import("fracture");

const Rectangle = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    colour: fr.Color,
};

// Alpha is stored with each colour; the renderer does not blend it yet.
const rectangles = [_]Rectangle{
    .{
        .x = 320,
        .y = 180,
        .width = 400,
        .height = 260,
        .colour = .{ .r = 0.9, .g = 0.15, .b = 0.2, .a = 0.5 },
    },
    .{
        .x = 560,
        .y = 300,
        .width = 400,
        .height = 260,
        .colour = .{ .r = 0.15, .g = 0.35, .b = 0.9, .a = 0.5 },
    },
};

pub fn main(init: std.process.Init) !void {
    var platform: fr.Platform = .{};
    try platform.init();
    defer platform.deinit();

    const width = 1280;
    const height = 720;
    const allocator = std.heap.page_allocator;
    const pixels = try allocator.alignedAlloc(
        u8,
        .fromByteUnits(4096),
        width * height * fr.Renderer.bytes_per_pixel,
    );
    defer allocator.free(pixels);

    var renderer: fr.Renderer = .{
        .back_buffer = .{ .width = width, .height = height, .data = pixels },
        .pixels_per_meter = 1,
        .camera_position = .{ .x = 0, .y = 0 },
    };
    renderer.clearScreen(0.08, 0.08, 0.08);

    try platform.createWindow(.{
        .title = "Testbed - left click to swap draw order",
        .frame_buffer = &renderer.back_buffer,
    });
    defer platform.destroyWindow();
    platform.setCursorHidden(false);
    platform.showWindow();

    var reverse_order = false;
    const frame_duration: std.Io.Duration = .fromNanoseconds(std.time.ns_per_s / 60);
    var pacing_error: ?fr.Platform.PaceFrameError = null;
    while (true) {
        const frame_start = std.Io.Clock.awake.now(init.io);
        defer {
            platform.paceFrame(init.io, frame_start, frame_duration) catch |err| {
                if (err != error.Canceled) pacing_error = err;
            };
        }
        platform.beginFrame();
        defer platform.endFrame();

        const status = platform.pollEvents();
        const events = platform.takeEvents();
        if (status.quit_requested) break;

        for (events) |event| {
            switch (event) {
                .mouse_pressed => |mouse| {
                    if (mouse.button == .left) reverse_order = !reverse_order;
                },
                .key_pressed => |key| {
                    if (key == .escape) return;
                },
                else => {},
            }
        }

        renderer.clearScreen(0.08, 0.08, 0.08);
        for (0..rectangles.len) |i| {
            const index = if (reverse_order) rectangles.len - 1 - i else i;
            const rectangle = rectangles[index];
            renderer.drawRectangle(
                rectangle.x,
                rectangle.y,
                rectangle.width,
                rectangle.height,
                rectangle.colour,
            );
        }
        platform.present();
    }
}
