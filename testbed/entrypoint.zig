const std = @import("std");
const fr = @import("fracture");
const Bitmap = fr.Bitmap;

const bitmap_size = 64;

const DrawCase = struct {
    name: []const u8,
    pivot_world_x: f32,
    pivot_world_y: f32,
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
        .{ .name = "Native (1x)", .pivot_world_x = centre_x, .pivot_world_y = centre_y, .width = 64, .height = 64 },
        .{ .name = "Half size (0.5x)", .pivot_world_x = centre_x, .pivot_world_y = centre_y, .width = 32, .height = 32 },
        .{ .name = "Fractional scale (1.5x)", .pivot_world_x = centre_x, .pivot_world_y = centre_y, .width = 96, .height = 96 },
        .{ .name = "Double size (2x)", .pivot_world_x = centre_x, .pivot_world_y = centre_y, .width = 128, .height = 128 },
        .{ .name = "Quadruple size (4x)", .pivot_world_x = centre_x, .pivot_world_y = centre_y, .width = 256, .height = 256 },
        .{ .name = "Wide (2x, 0.5x)", .pivot_world_x = centre_x, .pivot_world_y = centre_y, .width = 128, .height = 32 },
        .{ .name = "Tall (0.5x, 2x)", .pivot_world_x = centre_x, .pivot_world_y = centre_y, .width = 32, .height = 128 },

        // At zero rotation, half-pixel pivots put pixel centres on the starting edges.
        .{ .name = "Native, quarter-pixel pivot", .pivot_world_x = centre_x + 0.25, .pivot_world_y = centre_y + 0.25, .width = 64, .height = 64 },
        .{ .name = "Native, half-pixel pivot", .pivot_world_x = centre_x + 0.5, .pivot_world_y = centre_y + 0.5, .width = 64, .height = 64 },
        .{ .name = "1.5x, half-pixel pivot", .pivot_world_x = centre_x + 0.5, .pivot_world_y = centre_y + 0.5, .width = 96, .height = 96 },
        .{ .name = "0.5x, quarter-pixel pivot", .pivot_world_x = centre_x + 0.25, .pivot_world_y = centre_y + 0.25, .width = 32, .height = 32 },

        // Clipping must preserve the scale and the original texture position.
        .{ .name = "2x, left edge, half-pixel pivot", .pivot_world_x = 0.5, .pivot_world_y = centre_y, .width = 128, .height = 128 },
        .{ .name = "2x, right edge, half-pixel pivot", .pivot_world_x = width + 0.5, .pivot_world_y = centre_y, .width = 128, .height = 128 },
        .{ .name = "2x, top edge, half-pixel pivot", .pivot_world_x = centre_x, .pivot_world_y = 0.5, .width = 128, .height = 128 },
        .{ .name = "2x, bottom edge, half-pixel pivot", .pivot_world_x = centre_x, .pivot_world_y = height + 0.5, .width = 128, .height = 128 },
        .{ .name = "1.5x, top-left corner, quarter-pixel pivot", .pivot_world_x = 0.25, .pivot_world_y = 0.25, .width = 96, .height = 96 },
        .{ .name = "1.5x, top-right corner, quarter-pixel pivot", .pivot_world_x = width + 0.25, .pivot_world_y = 0.25, .width = 96, .height = 96 },
        .{ .name = "1.5x, bottom-left corner, quarter-pixel pivot", .pivot_world_x = 0.25, .pivot_world_y = height + 0.25, .width = 96, .height = 96 },
        .{ .name = "1.5x, bottom-right corner, quarter-pixel pivot", .pivot_world_x = width + 0.25, .pivot_world_y = height + 0.25, .width = 96, .height = 96 },

        // These are offscreen at zero rotation; rotating corners can enter the screen.
        .{ .name = "2x, fully offscreen left", .pivot_world_x = -64, .pivot_world_y = centre_y, .width = 128, .height = 128 },
        .{ .name = "2x, fully offscreen right", .pivot_world_x = width + 64, .pivot_world_y = centre_y, .width = 128, .height = 128 },
        .{ .name = "2x, fully offscreen top", .pivot_world_x = centre_x, .pivot_world_y = -64, .width = 128, .height = 128 },
        .{ .name = "2x, fully offscreen bottom", .pivot_world_x = centre_x, .pivot_world_y = height + 64, .width = 128, .height = 128 },
    };

    const allocator = std.heap.page_allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var renderer: fr.Renderer = undefined;
    try renderer.init(allocator, .{
        .width = width,
        .height = height,
        .pixels_per_meter = 1,
        .missing_texture_color = .magenta,
    });

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
            std.debug.print("Texture {d}/{d}: {s}, pivot ({d}, {d}), size {d} x {d}\n", .{
                case_index + 1, draw_cases.len, draw_case.name, draw_case.pivot_world_x, draw_case.pivot_world_y, draw_case.width, draw_case.height,
            });
            previous_case_index = case_index;
        }

        const rotation_ns = @mod(rotation_start.durationTo(frame_start).nanoseconds, rotation_period_ns);
        const angle_radians: f32 = @as(f32, @floatFromInt(rotation_ns)) /
            @as(f32, @floatFromInt(rotation_period_ns)) * std.math.tau;

        renderer.beginDrawing(.{ .r = 0.08, .g = 0.08, .b = 0.08 });
        renderer.submit(.{ .set_view = .{ .meters_per_pixel = 1, .camera_x = centre_x, .camera_y = centre_y } });
        renderer.submit(.{ .draw_rectangle = .{
            .pivot_world_x = draw_case.pivot_world_x,
            .pivot_world_y = draw_case.pivot_world_y,
            .width = draw_case.width,
            .height = draw_case.height,
            .pivot_fraction_x = 0.5,
            .pivot_fraction_y = 0.5,
            .angle_radians = angle_radians,
            .texture = bitmap,
            .tint_srgb = null,
        } });
        renderer.endDrawing(arena.allocator());
        platform.present();
    }
}
