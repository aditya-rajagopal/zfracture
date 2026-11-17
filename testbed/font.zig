const std = @import("std");
const fr = @import("fracture");

pub const fracture_profiling = struct {
    pub const Anchors = enum {
        total,
    };

    pub const Tracer = fr.tracer.Tracer(Anchors, fr.tracer.defaultTimer, true);

    // The executable and each loaded DLL have their own binding. Storage stays in EngineState.
    pub var tracer: ?*Tracer = null;
};

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var tracer: fracture_profiling.Tracer = .empty;
    tracer.init(50);
    fracture_profiling.tracer = &tracer;
    defer fracture_profiling.tracer = null;

    var platform: fr.Platform = .empty;
    try platform.init(.{
        .title = "Font showcase",
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

    const monogram = fr.SoftwareRenderer.monogram;
    const font = try renderer.allocTexture(allocator, monogram.width, monogram.height);

    const bm = renderer.getTextureOrNull(font) orelse return error.Failed;
    @memcpy(bm.pixels, &monogram.pixels);

    var frame_time: f64 = 0;

    while (true) {
        _ = arena.reset(.retain_capacity);
        tracer.reset();
        const total = tracer.startTrace(.total);
        defer {
            tracer.end(&total);
            frame_time = tracer.getAnchorTime(.total);
        }

        const frame_start = std.Io.Clock.awake.now(init.io);
        defer {
            platform.paceFrame(init.io, frame_start, frame_duration) catch |err| {
                if (err != error.Canceled) pacing_error = err;
            };
        }

        const status = platform.pollEvents();
        if (status.quit_requested) break;

        const events = platform.takeEvents();

        for (events) |event| {
            if (event == .key_pressed and event.key_pressed == .escape) {
                return;
            }
        }

        const text = "Hello, World!\nAll your codebase are belong to us.";
        var buffer: [1024]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);

        try writer.print("Frame time: {d:.5}ms", .{frame_time});

        const half_width = @as(f32, @floatFromInt(renderer.back_buffer.width)) / 2.0;
        const half_height = @as(f32, @floatFromInt(renderer.back_buffer.height)) / 2.0;

        const cmd = renderer.beginDrawing(.black, .{
            .camera_x = half_width,
            .camera_y = half_height,
            .meters_per_pixel = 1,
        });

        const layout: fr.Renderer.TextConfig = .{
            .scale = 2,
            .width = half_width,
            .height = half_height,
            .mode = .wrap,
        };
        const size = fr.Renderer.measureText(text, layout);
        cmd.pushText(half_width - size.width / 2, half_height - size.height / 2, text, font, layout);
        cmd.pushText(10, 10, writer.buffered(), font, .{ .scale = 1 });

        renderer.endDrawing(arena.allocator(), cmd);
    }
}
