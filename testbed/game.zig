const std = @import("std");
const fracture = @import("fracture");
const EngineState = fracture.EngineState;
const FrameBuffer = fracture.FrameBuffer;

pub const GameState = struct {
    impact_sound: fracture.wav.WavData,
    pop_sound: fracture.wav.WavData,

    // FIXME: In screen space currently
    player_x: f32,
    player_y: f32,
};

const player_width: f32 = 20.0;
const player_height: f32 = 40.0;
const player_half_width: f32 = player_width / 2.0;

pub fn init(engine: *EngineState) *anyopaque {
    const game_state = engine.permanent_allocator.create(GameState) catch unreachable;
    game_state.player_x = @as(f32, @floatFromInt(engine.back_buffer.width)) / 2;
    game_state.player_y = @as(f32, @floatFromInt(engine.back_buffer.height)) / 2;
    const impact_sound = std.fs.cwd().readFileAlloc(
        "assets/sounds/impactMetal_medium_000-converted.wav",
        engine.transient_allocator,
        .unlimited,
    ) catch unreachable;
    game_state.impact_sound = fracture.wav.decode(engine.permanent_allocator, impact_sound) catch unreachable;
    const pop_sound = std.fs.cwd().readFileAlloc(
        "assets/sounds/pop.wav",
        engine.transient_allocator,
        .unlimited,
    ) catch unreachable;
    game_state.pop_sound = fracture.wav.decode(engine.permanent_allocator, pop_sound) catch unreachable;
    return @ptrCast(game_state);
}

pub fn deinit(_: *EngineState, _: *anyopaque) void {}

pub fn updateAndRender(
    engine: *EngineState,
    game_state: *anyopaque,
) bool {
    const state: *GameState = @ptrCast(@alignCast(game_state));
    var running: bool = true;
    if (engine.input.isKeyDown(.escape)) {
        running = false;
    }

    { // Player movement
        var delta_x: f32 = 0.0;
        var delta_y: f32 = 0.0;

        if (engine.input.isKeyDown(.s)) {
            delta_x -= 1.0;
        }
        if (engine.input.isKeyDown(.f)) {
            delta_x += 1.0;
        }
        if (engine.input.isKeyDown(.e)) {
            delta_y -= 1.0;
        }
        if (engine.input.isKeyDown(.d)) {
            delta_y += 1.0;
        }

        const magnitude = std.math.sqrt(delta_x * delta_x + delta_y * delta_y);
        if (magnitude > 0.0) {
            delta_x = delta_x / magnitude;
            delta_y = delta_y / magnitude;
        }

        if (engine.input.mouseButtonPressedThisFrame(.left)) {
            _ = engine.sound.playSound(state.pop_sound.data, .{});
        }

        if (engine.input.keyPressedThisFrame(.space)) {
            _ = engine.sound.playSound(state.impact_sound.data, .{});
        }

        clearScreen(&engine.back_buffer, 0.0, 0.0, 0.0);

        var new_player_x = state.player_x + delta_x;
        var new_player_y = state.player_y + delta_y;
        new_player_x = std.math.clamp(
            new_player_x,
            player_half_width,
            @as(f32, @floatFromInt(engine.back_buffer.width - 1)) - player_half_width,
        );
        new_player_y = std.math.clamp(
            new_player_y,
            player_height,
            @as(f32, @floatFromInt(engine.back_buffer.height - 1)),
        );

        state.player_x = new_player_x;
        state.player_y = new_player_y;
    }

    { // Draw player
        // NOTE: The players anchor point is at the feet of the player
        drawRectangle(
            &engine.back_buffer,
            state.player_x - player_half_width,
            state.player_y - player_height,
            player_width,
            player_height,
            1.0,
            0.0,
            0.0,
            1.0,
        );
    }

    return running;
}

fn clearScreen(frame_buffer: *FrameBuffer, r: f32, g: f32, b: f32) void {
    const r_int: u8 = @truncate(@as(u32, @intFromFloat(@round(r * 255.0))));
    const g_int: u8 = @truncate(@as(u32, @intFromFloat(@round(g * 255.0))));
    const b_int: u8 = @truncate(@as(u32, @intFromFloat(@round(b * 255.0))));
    const clear_colour: u32 = (@as(u32, @intCast(r_int)) << 16) | (@as(u32, @intCast(g_int)) << 8) | @as(u32, @intCast(b_int));
    const total_pixels: usize = @as(usize, @intCast(frame_buffer.width)) * @as(usize, @intCast(frame_buffer.height));
    const pixles_u32: []u32 = @ptrCast(frame_buffer.data[0 .. total_pixels * FrameBuffer.bytes_per_pixel]);
    @memset(pixles_u32[0..total_pixels], clear_colour);
}

fn drawRectangle(frame_buffer: *FrameBuffer, x: f32, y: f32, width: f32, height: f32, r: f32, g: f32, b: f32, a: f32) void {
    // TODO: Consider blending
    _ = a;
    // NOTE: We are rounding here to if the position of the corner covers most of a pixel in x or y we will draw it.
    var x_int: usize = @intFromFloat(@round(x));
    var y_int: usize = @intFromFloat(@round(y));
    var width_int: usize = @intFromFloat(@round(width));
    var height_int: usize = @intFromFloat(@round(height));

    // NOTE: Clamping so we dont overflow the buffer
    x_int = std.math.clamp(x_int, 0, frame_buffer.width - 1);
    y_int = std.math.clamp(y_int, 0, frame_buffer.height - 1);
    width_int = std.math.clamp(width_int, 0, frame_buffer.width - 1 - x_int);
    height_int = std.math.clamp(height_int, 0, frame_buffer.height - 1 - y_int);

    const r_int: u8 = @truncate(@as(u32, @intFromFloat(@round(r * 255.0))));
    const g_int: u8 = @truncate(@as(u32, @intFromFloat(@round(g * 255.0))));
    const b_int: u8 = @truncate(@as(u32, @intFromFloat(@round(b * 255.0))));
    const colour: u32 = (@as(u32, @intCast(r_int)) << 16) | (@as(u32, @intCast(g_int)) << 8) | @as(u32, @intCast(b_int));

    const total_pixels: usize = @as(usize, @intCast(frame_buffer.width)) * @as(usize, @intCast(frame_buffer.height));
    const pixles_u32: []u32 = @ptrCast(frame_buffer.data[0 .. total_pixels * FrameBuffer.bytes_per_pixel]);

    for (0..height_int) |j| {
        for (0..width_int) |i| {
            pixles_u32[(y_int + j) * frame_buffer.width + x_int + i] = colour;
        }
    }
}
