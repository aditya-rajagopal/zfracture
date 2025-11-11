const std = @import("std");
const fracture = @import("fracture");
const EngineState = fracture.EngineState;
const FrameBuffer = fracture.FrameBuffer;

// NOTE: PoE1 and 2 do not have plyaer inertia.

// @HACK:
const NUM_ENEMIES = 10;

pub const GameState = struct {
    impact_sound: fracture.wav.WavData,
    pop_sound: fracture.wav.WavData,

    // FIXME:
    tile_map: TileMap,

    // FIXME: In screen space currently
    camera_x: f32,
    camera_y: f32,

    player: Entity,
    enemies: [NUM_ENEMIES]Entity,
};

const Entity = struct {
    position_x: f32,
    position_y: f32,
    movement_speed: f32,
};

const TileType = enum(u8) {
    none = 0,
    floor,
    wall,
};

const TileMap = struct {
    data: []TileType,
    tile_width: u32,
    tile_height: u32,
};

const tile_width: f32 = 32.0;
const tile_height: f32 = 32.0;

const player_width: f32 = tile_width;
const player_height: f32 = tile_height;
const player_half_width: f32 = player_width / 2.0;

pub fn init(engine: *EngineState) *anyopaque {
    const game_state = engine.permanent_allocator.create(GameState) catch unreachable;
    game_state.camera_x = @as(f32, @floatFromInt(engine.back_buffer.width)) / 2;
    game_state.camera_y = @as(f32, @floatFromInt(engine.back_buffer.height)) / 2;
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

    { // HACK: debug level generation
        game_state.tile_map.tile_width = 200;
        game_state.tile_map.tile_height = 200;
        game_state.tile_map.data = engine.permanent_allocator.alloc(
            TileType,
            game_state.tile_map.tile_width * game_state.tile_map.tile_height,
        ) catch unreachable;

        @memset(game_state.tile_map.data, .floor);

        // Randomly generate some walls
        var wall_count: usize = 0;
        var rand = std.Random.DefaultPrng.init(12345);
        var random = rand.random();
        while (wall_count < game_state.tile_map.tile_width * game_state.tile_map.tile_height / 10) : (wall_count += 1) {
            const x = random.intRangeAtMost(u32, 0, game_state.tile_map.tile_width - 1);
            const y = random.intRangeAtMost(u32, 0, game_state.tile_map.tile_height - 1);
            game_state.tile_map.data[y * game_state.tile_map.tile_width + x] = .wall;
        }
        const tile_map_width = @as(f32, @floatFromInt(game_state.tile_map.tile_width)) * tile_width;
        const tile_map_height = @as(f32, @floatFromInt(game_state.tile_map.tile_height)) * tile_height;
        // Player starts in the middle of the map
        game_state.camera_x = tile_map_width / 2;
        game_state.camera_y = tile_map_height / 2;
        game_state.player.position_x = game_state.camera_x;
        game_state.player.position_y = game_state.camera_y;
        game_state.player.movement_speed = 32.0 * 5;

        for (0..NUM_ENEMIES) |i| {
            game_state.enemies[i].position_x = game_state.camera_x + ((random.float(f32) * 2 - 1) * @as(f32, @floatFromInt(engine.back_buffer.width - 50))) / 2.0;
            game_state.enemies[i].position_y = game_state.camera_y + ((random.float(f32) * 2 - 1) * @as(f32, @floatFromInt(engine.back_buffer.height - 50))) / 2.0;
            game_state.enemies[i].movement_speed = 32.0 * 4;
        }
    }

    return @ptrCast(game_state);
}

pub fn deinit(_: *EngineState, _: *anyopaque) void {}

pub fn updateAndRender(
    engine: *EngineState,
    game_state: *anyopaque,
) bool {
    const state: *GameState = @ptrCast(@alignCast(game_state));
    var running: bool = true;

    // NOTE: Clear to magenta
    clearScreen(&engine.back_buffer, 1.0, 0.0, 1.0);

    if (engine.input.isKeyDown(.escape)) {
        running = false;
    }

    if (engine.input.mouseButtonPressedThisFrame(.left)) {
        _ = engine.sound.playSound(state.pop_sound.data, .{});
    }

    if (engine.input.keyPressedThisFrame(.space)) {
        _ = engine.sound.playSound(state.impact_sound.data, .{});
    }

    const screen_width = @as(f32, @floatFromInt(engine.back_buffer.width));
    const screen_height = @as(f32, @floatFromInt(engine.back_buffer.height));

    // The limits in pixels for the tilemap
    const tile_map_width = @as(f32, @floatFromInt(state.tile_map.tile_width)) * tile_width;
    const tile_map_height = @as(f32, @floatFromInt(state.tile_map.tile_height)) * tile_height;

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
            const magnitude_inv: f32 = 1.0 / magnitude;
            delta_x = delta_x * magnitude_inv;
            delta_y = delta_y * magnitude_inv;
        }

        var new_camera_x = state.camera_x + delta_x * state.player.movement_speed * engine.delta_time / 1000.0;
        var new_camera_y = state.camera_y + delta_y * state.player.movement_speed * engine.delta_time / 1000.0;

        // Clamp player position to the tile map. The tile map top right is the 0, 0 position.

        new_camera_x = std.math.clamp(
            new_camera_x,
            player_half_width,
            tile_map_width - player_half_width,
        );
        new_camera_y = std.math.clamp(
            new_camera_y,
            0,
            tile_map_height,
        );

        // @INCOMPLETE: Collision detection against tilemap
        // @TODO: Change coordinate system from pixels to meters

        state.camera_x = new_camera_x;
        state.camera_y = new_camera_y;
        state.player.position_x = new_camera_x;
        state.player.position_y = new_camera_y;
    }

    { // Enemy movement
        // NOTE: The enemies move towards the player always

        for (0..state.enemies.len) |i| {
            const enemy = &state.enemies[i];
            const player = &state.player;
            var delta_x: f32 = player.position_x - enemy.position_x;
            var delta_y: f32 = player.position_y - enemy.position_y;
            const magnitude = std.math.sqrt(delta_x * delta_x + delta_y * delta_y);
            if (magnitude > 0.0) {
                const magnitude_inv: f32 = 1.0 / magnitude;
                delta_x = delta_x * magnitude_inv;
                delta_y = delta_y * magnitude_inv;
            }

            enemy.position_x = enemy.position_x + delta_x * enemy.movement_speed * engine.delta_time / 1000.0;
            enemy.position_y = enemy.position_y + delta_y * enemy.movement_speed * engine.delta_time / 1000.0;
        }
    }

    { // Draw tile map
        const floor_colour_r: f32 = 0.043;
        const floor_colour_g: f32 = 0.635;
        const floor_colour_b: f32 = 0.000;

        const wall_colour_r: f32 = 0.400;
        const wall_colour_g: f32 = 0.400;
        const wall_colour_b: f32 = 0.400;

        // Player is at the center of the screen always so draw the player there and the camera moves with the player
        // Based on the player position figure out the tiles we need to draw
        const top_left_tile_x_int: i32 = @intFromFloat(@floor((state.camera_x - screen_width / 2) / tile_width));
        const top_left_tile_x: usize = @intCast(std.math.clamp(top_left_tile_x_int, 0, state.tile_map.tile_width - 1));

        const top_left_tile_y_int: i32 = @intFromFloat(@floor((state.camera_y - screen_height / 2) / tile_height));
        const top_left_tile_y: usize = @intCast(std.math.clamp(top_left_tile_y_int, 0, state.tile_map.tile_height - 1));

        const bottom_right_tile_x_int: i32 = @intFromFloat(@ceil((state.camera_x + screen_width / 2) / tile_width));
        const bottom_right_tile_x: usize = @intCast(std.math.clamp(bottom_right_tile_x_int, 0, state.tile_map.tile_width - 1));

        const bottom_right_tile_y_int: i32 = @intFromFloat(@ceil((state.camera_y + screen_height / 2) / tile_height));
        const bottom_right_tile_y: usize = @intCast(std.math.clamp(bottom_right_tile_y_int, 0, state.tile_map.tile_height - 1));

        for (top_left_tile_y..bottom_right_tile_y + 1) |y| {
            for (top_left_tile_x..bottom_right_tile_x + 1) |x| {
                const tile_type = state.tile_map.data[y * state.tile_map.tile_width + x];
                const x_position = @as(f32, @floatFromInt(x)) * tile_width - state.camera_x + screen_width / 2;
                const y_position = @as(f32, @floatFromInt(y)) * tile_height - state.camera_y + screen_height / 2;
                switch (tile_type) {
                    .floor => {
                        drawRectangle(
                            &engine.back_buffer,
                            x_position,
                            y_position,
                            tile_width,
                            tile_height,
                            floor_colour_r,
                            floor_colour_g,
                            floor_colour_b,
                            1.0,
                        );
                    },
                    .wall => {
                        drawRectangle(
                            &engine.back_buffer,
                            x_position,
                            y_position,
                            tile_width,
                            tile_height,
                            wall_colour_r,
                            wall_colour_g,
                            wall_colour_b,
                            1.0,
                        );
                    },
                    else => {},
                }
            }
        }
    }

    { // Draw enemies
        for (0..state.enemies.len) |i| {
            const enemey_screen_x = state.enemies[i].position_x - state.camera_x + screen_width / 2;
            const enemey_screen_y = state.enemies[i].position_y - state.camera_y + screen_height / 2;
            drawRectangle(
                &engine.back_buffer,
                enemey_screen_x - player_half_width,
                enemey_screen_y - player_height,
                player_width,
                player_height,
                0.0,
                0.0,
                1.0,
                1.0,
            );
        }
    }

    { // Draw player at the center of the screen always
        // NOTE: The players anchor point is at the feet of the player
        drawRectangle(
            &engine.back_buffer,
            screen_width / 2 - player_half_width,
            screen_height / 2 - player_height,
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
    const x_int: i32 = @intFromFloat(@round(x));
    const y_int: i32 = @intFromFloat(@round(y));
    const width_int: i32 = @intFromFloat(@round(width));
    const height_int: i32 = @intFromFloat(@round(height));

    // NOTE: If the position is too far off screen to draw a rectangle we dont draw it
    if (y_int > frame_buffer.height or
        x_int > frame_buffer.width or
        y_int < -width_int or
        x_int < -height_int)
    {
        return;
    }

    // NOTE: Clamping so we dont overflow the buffer
    const x_uint: usize = @intCast(std.math.clamp(x_int, 0, frame_buffer.width - 1));
    const y_uint: usize = @intCast(std.math.clamp(y_int, 0, frame_buffer.height - 1));
    const width_uint: usize = @intCast(std.math.clamp(width_int, 0, frame_buffer.width - x_int));
    const height_uint: usize = @intCast(std.math.clamp(height_int, 0, frame_buffer.height - y_int));

    const r_int: u8 = @truncate(@as(u32, @intFromFloat(@round(r * 255.0))));
    const g_int: u8 = @truncate(@as(u32, @intFromFloat(@round(g * 255.0))));
    const b_int: u8 = @truncate(@as(u32, @intFromFloat(@round(b * 255.0))));
    const colour: u32 = (@as(u32, @intCast(r_int)) << 16) | (@as(u32, @intCast(g_int)) << 8) | @as(u32, @intCast(b_int));

    const total_pixels: usize = @as(usize, @intCast(frame_buffer.width)) * @as(usize, @intCast(frame_buffer.height));
    const pixles_u32: []u32 = @ptrCast(frame_buffer.data[0 .. total_pixels * FrameBuffer.bytes_per_pixel]);

    for (0..height_uint) |j| {
        for (0..width_uint) |i| {
            pixles_u32[(y_uint + j) * frame_buffer.width + x_uint + i] = colour;
        }
    }
}
