const std = @import("std");
const fr = @import("fracture");
const Bitmap = fr.Bitmap;

const bitmap_size = 64;

const DrawCase = struct {
    name: []const u8,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub fn main(init: std.process.Init) !void {
    var platform: fr.Platform = .{};
    try platform.init();
    defer platform.deinit();

    const width = 1280;
    const height = 720;
    const centre_x = width / 2;
    const centre_y = height / 2;
    const draw_cases = [_]DrawCase{
        // Keep the image centred while changing the destination dimensions.
        .{ .name = "Native (1x)", .x = centre_x - 32, .y = centre_y - 32, .width = 64, .height = 64 },
        .{ .name = "Half size (0.5x)", .x = centre_x - 16, .y = centre_y - 16, .width = 32, .height = 32 },
        .{ .name = "Fractional scale (1.5x)", .x = centre_x - 48, .y = centre_y - 48, .width = 96, .height = 96 },
        .{ .name = "Double size (2x)", .x = centre_x - 64, .y = centre_y - 64, .width = 128, .height = 128 },
        .{ .name = "Quadruple size (4x)", .x = centre_x - 128, .y = centre_y - 128, .width = 256, .height = 256 },
        .{ .name = "Wide (2x, 0.5x)", .x = centre_x - 64, .y = centre_y - 16, .width = 128, .height = 32 },
        .{ .name = "Tall (0.5x, 2x)", .x = centre_x - 16, .y = centre_y - 64, .width = 32, .height = 128 },

        // Half-pixel origins put pixel centres exactly on the starting edges.
        .{ .name = "Native, quarter-pixel origin", .x = centre_x - 32 + 0.25, .y = centre_y - 32 + 0.25, .width = 64, .height = 64 },
        .{ .name = "Native, half-pixel origin", .x = centre_x - 32 + 0.5, .y = centre_y - 32 + 0.5, .width = 64, .height = 64 },
        .{ .name = "1.5x, half-pixel origin", .x = centre_x - 48 + 0.5, .y = centre_y - 48 + 0.5, .width = 96, .height = 96 },
        .{ .name = "0.5x, quarter-pixel origin", .x = centre_x - 16 + 0.25, .y = centre_y - 16 + 0.25, .width = 32, .height = 32 },

        // Clipping must preserve the scale and the original texture position.
        .{ .name = "2x, left edge, half-pixel origin", .x = -63.5, .y = centre_y - 64, .width = 128, .height = 128 },
        .{ .name = "2x, right edge, half-pixel origin", .x = width - 63.5, .y = centre_y - 64, .width = 128, .height = 128 },
        .{ .name = "2x, top edge, half-pixel origin", .x = centre_x - 64, .y = -63.5, .width = 128, .height = 128 },
        .{ .name = "2x, bottom edge, half-pixel origin", .x = centre_x - 64, .y = height - 63.5, .width = 128, .height = 128 },
        .{ .name = "1.5x, top-left corner, quarter-pixel origin", .x = -47.75, .y = -47.75, .width = 96, .height = 96 },
        .{ .name = "1.5x, top-right corner, quarter-pixel origin", .x = width - 47.75, .y = -47.75, .width = 96, .height = 96 },
        .{ .name = "1.5x, bottom-left corner, quarter-pixel origin", .x = -47.75, .y = height - 47.75, .width = 96, .height = 96 },
        .{ .name = "1.5x, bottom-right corner, quarter-pixel origin", .x = width - 47.75, .y = height - 47.75, .width = 96, .height = 96 },

        // These are offscreen at zero rotation; rotating corners can enter the screen.
        .{ .name = "2x, fully offscreen left", .x = -128, .y = centre_y - 64, .width = 128, .height = 128 },
        .{ .name = "2x, fully offscreen right", .x = width, .y = centre_y - 64, .width = 128, .height = 128 },
        .{ .name = "2x, fully offscreen top", .x = centre_x - 64, .y = -128, .width = 128, .height = 128 },
        .{ .name = "2x, fully offscreen bottom", .x = centre_x - 64, .y = height, .width = 128, .height = 128 },
    };

    const allocator = std.heap.page_allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var renderer: fr.Renderer = undefined;
    try renderer.init(allocator, .{ .width = width, .height = height, .pixels_per_meter = 1 });

    const bitmap = renderer.loadAndCreateTexture(
        init.io,
        allocator,
        arena.allocator(),
        "assets/textures/paving2.png",
    );
    renderer.submit(.{ .clear_screen = .{ .r = 0.08, .g = 0.08, .b = 0.08 } });

    try platform.createWindow(.{
        .title = "Testbed - left click or Space: next texture case",
        .frame_buffer = &renderer.back_buffer,
    });
    defer platform.destroyWindow();
    platform.setCursorHidden(false);
    platform.showWindow();

    var case_index: usize = 0;
    // A sentinel makes the initial case print as well as later changes.
    var previous_case_index: usize = draw_cases.len;
    const frame_duration: std.Io.Duration = .fromNanoseconds(std.time.ns_per_s / 60);
    const rotation_period_ns: i96 = 8 * std.time.ns_per_s;
    const rotation_start = std.Io.Clock.awake.now(init.io);
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
                    if (mouse.button == .left) {
                        case_index = (case_index + 1) % draw_cases.len;
                    }
                },
                .key_pressed => |key| {
                    if (key == .escape) return;
                    if (key == .space) {
                        case_index = (case_index + 1) % draw_cases.len;
                    }
                },
                else => {},
            }
        }

        const draw_case = draw_cases[case_index];
        if (case_index != previous_case_index) {
            std.debug.print("Texture {d}/{d}: {s}, position ({d}, {d}), size {d} x {d}\n", .{
                case_index + 1, draw_cases.len, draw_case.name, draw_case.x, draw_case.y, draw_case.width, draw_case.height,
            });
            previous_case_index = case_index;
        }

        const rotation_ns = @mod(rotation_start.durationTo(frame_start).nanoseconds, rotation_period_ns);
        const angle_radians: f32 = @as(f32, @floatFromInt(rotation_ns)) /
            @as(f32, @floatFromInt(rotation_period_ns)) * std.math.tau;

        const half_width = draw_case.width * 0.5;
        const half_height = draw_case.height * 0.5;
        const cosine = @cos(angle_radians);
        const sine = @sin(angle_radians);
        const origin_x = draw_case.x + half_width - (cosine * half_width - sine * half_height);
        const origin_y = draw_case.y + half_height - (sine * half_width + cosine * half_height);

        renderer.submit(.{ .clear_screen = .{ .r = 0.08, .g = 0.08, .b = 0.08 } });
        renderer.submit(.{ .draw_textured_rectangle = .{
            .x = origin_x,
            .y = origin_y,
            .width = draw_case.width,
            .height = draw_case.height,
            .angle_radians = angle_radians,
            .texture = bitmap,
            .tint_srgb = null,
        } });
        platform.present();
    }
}
