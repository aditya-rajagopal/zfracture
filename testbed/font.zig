const std = @import("std");
const fr = @import("fracture");

pub fn main(init: std.process.Init) !void {
    var platform: fr.Platform = undefined;
    try platform.init();
    defer platform.deinit();

    const allocator = std.heap.page_allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const width = 1280;
    const height = 720;

    var renderer: fr.SoftwareRenderer = undefined;
    try renderer.init(allocator, .{
        .width = width,
        .height = height,
        .missing_texture_color = .magenta,
        .workers = .{ .io = init.io },
    });
    defer renderer.deinit(allocator);

    try platform.createWindow(.{
        .title = "Font showcase",
        .frame_buffer = &renderer.back_buffer,
    });
    defer platform.destroyWindow();
    platform.setCursorHidden(false);
    platform.showWindow();

    const frame_duration: std.Io.Duration = .fromNanoseconds(std.time.ns_per_s / 60);
    var pacing_error: ?fr.Platform.PaceFrameError = null;

    const font = try renderer.allocTexture(
        allocator,
        fr.SoftwareRenderer.monogram.width,
        fr.SoftwareRenderer.monogram.height,
    );

    const bm = renderer.getTextureOrNull(font) orelse return error.Failed;
    @memcpy(bm.pixels, fr.SoftwareRenderer.monogram.pixels[0..fr.SoftwareRenderer.monogram.pixel_count]);

    while (true) {
        _ = arena.reset(.retain_capacity);
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
            if (event == .key_pressed and event.key_pressed == .escape) {
                return;
            }
        }

        const cmd = renderer.beginDrawing(.black, .{ .camera_x = 0, .camera_y = 0, .meters_per_pixel = 1 });
        const texture_width = @as(f32, @floatFromInt(fr.SoftwareRenderer.monogram.width));
        const texture_height = @as(f32, @floatFromInt(fr.SoftwareRenderer.monogram.height));
        cmd.pushRect(
            0,
            0,
            texture_width * 2,
            texture_height * 2,
            .{
                .texture = font,
                .filter = .nearest,
            },
        );
        renderer.endDrawing(arena.allocator(), cmd);
        platform.present();
    }
}
