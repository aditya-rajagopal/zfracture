const std = @import("std");

const fr = @import("fracture");

pub fn main(init: std.process.Init) !void {
    var platform: fr.Platform = .{};
    try platform.init();
    defer platform.deinit();

    const allocator = std.heap.page_allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const width = 1280;
    const height = 720;

    var renderer: fr.Renderer = undefined;
    try renderer.init(allocator, .{
        .width = width,
        .height = height,
        .pixels_per_meter = 1,
        .missing_texture_color = .magenta,
    });

    try platform.createWindow(.{
        .title = "Testbed - left click or Space: next texture case",
        .frame_buffer = &renderer.back_buffer,
    });
    defer platform.destroyWindow();
    platform.setCursorHidden(false);
    platform.showWindow();

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
            if (event == .key_pressed and event.key_pressed == .escape) {
                return;
            }
        }

        const a_x = width / 4;
        const a_y = 3 * height / 4;
        const b_x = width / 2;
        const b_y = height / 4;
        const c_x = 3 * width / 4;
        const c_y = 3 * height / 4;

        renderer.beginDrawing(.{ .r = 0.08, .g = 0.08, .b = 0.08 });
        renderer.endDrawing();
        renderer.drawTriangle(a_x, a_y, b_x, b_y, c_x, c_y, .white);
        platform.present();
    }
}
