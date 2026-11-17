const std = @import("std");

const fr = @import("fracture");

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    var platform: fr.Platform = .empty;
    try platform.init(.{
        .title = "Testbed - left click or Space: next texture case",
        .width = 1280,
        .height = 720,
    });
    defer platform.deinit();

    var renderer: fr.SoftwareRenderer = undefined;
    try renderer.init(allocator, .{
        .platform = &platform,
        .missing_texture_color = .magenta,
        .workers = .{ .io = init.io },
    });
    defer renderer.deinit(allocator);

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

        const status = platform.pollEvents();
        const events = platform.takeEvents();
        if (status.quit_requested) break;

        for (events) |event| {
            if (event == .key_pressed and event.key_pressed == .escape) {
                return;
            }
        }

        const width: f32 = @floatFromInt(renderer.back_buffer.width);
        const height: f32 = @floatFromInt(renderer.back_buffer.height);
        const a_x = width / 4;
        const a_y = 3 * height / 4;
        const b_x = width / 2;
        const b_y = height / 4;
        const c_x = 3 * width / 4;
        const c_y = 3 * height / 4;

        // This demo writes directly into the framebuffer.
        @memset(renderer.back_buffer.pixels(), 0x141414);
        renderer.drawTriangle(a_x, a_y, b_x, b_y, c_x, c_y, .white);
        platform.softwarePresent(&renderer.back_buffer);
    }
}
