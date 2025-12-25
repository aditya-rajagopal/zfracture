const std = @import("std");

const fr = @import("fracture");
const Renderer = fr.Renderer;
const Color = fr.Color;
const common = @import("common.zig");
const EngineState = common.EngineState;

// NOTE: PoE1 and 2 do not have plyaer inertia.

// @TODO: Flow field for pathing?
// @TODO: Entitiy system that allows me to spawn arbitrary entities. Maybe have a separate slot for attack hit boxes?
// Renderer:
//      @TODO: Triangle rendering: We might be able to speed up rendering with simd by doing checks in a 8x8 grid at once.
//      @TODO: Start with doing 3D geometry with software rendering. Swtich to OpenGL/Vulkan later.
//      @TODO: Premulitplied alpha blending for sprites and other geometry. Convert from sRGB to linear space and back.
//      @TODO: Subpixel rendering
//      @TODO: Support normal maps
//      @TODO: Lighting
//      @TODO: Depth buffer and depth testing
//      @TODO: Render command queues to allow for culling and other optimizations
//      @TODO: Render to textures
// @TODO: Do we want enemy behaviour that is simulated when not interacting with the player? For example patrolling or
// two groups of enemies that are fighing each other: YES
// @TODO: Deal with window resize.

// @HACK:
const NUM_ENEMIES = 200;

pub const GameState = struct {
    impact_sound: fr.wav.WavData,
    pop_sound: fr.wav.WavData,

    // FIXME:
    tile_map: TileMap,

    // FIXME: In screen space currently
    camera_x: f32,
    camera_y: f32,
    view_half_width: f32,
    view_half_height: f32,

    player: Entity,
    enemies: [NUM_ENEMIES]Entity,
};

const Entity = struct {
    entity_type: EntityType,
    position_x: f32,
    position_y: f32,
    stats: Stats,

    // @TODO: This needs to be better
    render_colour: Color,
};

const EntityType = enum(u8) {
    player,
    skeleton,
};

const Stats = struct {
    movement_speed: f32,
    current_health: u16,
    max_health: u16,
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

const tile_width: f32 = 1.0;
const tile_height: f32 = 1.0;

const meters_per_pixel: f32 = 1.0 / 32.0;

const player_width: f32 = tile_width;
const player_height: f32 = tile_height;
const player_half_width: f32 = player_width / 2.0;

const secret_seed: [std.Random.ChaCha.secret_seed_length]u8 = "This is a 32 byte secret seed.!.".*;

pub fn init(engine: *EngineState) *anyopaque {
    const game_state = engine.permanent_allocator.create(GameState) catch unreachable;
    game_state.camera_x = @as(f32, @floatFromInt(engine.renderer.back_buffer.width)) / 2;
    game_state.camera_y = @as(f32, @floatFromInt(engine.renderer.back_buffer.height)) / 2;

    const impact_sound = std.fs.cwd().readFileAlloc(
        "assets/sounds/impactMetal_medium_000-converted.wav",
        engine.transient_allocator,
        .unlimited,
    ) catch unreachable;
    game_state.impact_sound = fr.wav.decode(engine.permanent_allocator, impact_sound) catch unreachable;
    const pop_sound = std.fs.cwd().readFileAlloc(
        "assets/sounds/pop.wav",
        engine.transient_allocator,
        .unlimited,
    ) catch unreachable;
    game_state.pop_sound = fr.wav.decode(engine.permanent_allocator, pop_sound) catch unreachable;

    { // HACK: debug level generation
        game_state.tile_map.tile_width = 50;
        game_state.tile_map.tile_height = 50;
        game_state.tile_map.data = engine.permanent_allocator.alloc(
            TileType,
            game_state.tile_map.tile_width * game_state.tile_map.tile_height,
        ) catch unreachable;

        @memset(game_state.tile_map.data, .floor);

        // TODO: Make this something like a view matrix
        game_state.view_half_width = @as(f32, @floatFromInt(engine.renderer.back_buffer.width)) * meters_per_pixel / 2.0;
        game_state.view_half_height = @as(f32, @floatFromInt(engine.renderer.back_buffer.height)) * meters_per_pixel / 2.0;

        // Randomly generate some walls
        var wall_count: usize = 0;
        var rand = std.Random.ChaCha.init(secret_seed);
        var random = rand.random();
        while (wall_count < game_state.tile_map.tile_width * game_state.tile_map.tile_height / 10) : (wall_count += 1) {
            const x = random.intRangeAtMost(u32, 0, game_state.tile_map.tile_width - 1);
            const y = random.intRangeAtMost(u32, 0, game_state.tile_map.tile_height - 1);
            game_state.tile_map.data[y * game_state.tile_map.tile_width + x] = .wall;
        }
        const tile_map_width = @as(f32, @floatFromInt(game_state.tile_map.tile_width));
        const tile_map_height = @as(f32, @floatFromInt(game_state.tile_map.tile_height));
        // Player starts in the middle of the map
        game_state.camera_x = tile_map_width / 2;
        game_state.camera_y = tile_map_height / 2;

        game_state.player.position_x = game_state.camera_x;
        game_state.player.position_y = game_state.camera_y;
        game_state.player.stats.movement_speed = 5;
        game_state.player.stats.current_health = 100;
        game_state.player.stats.max_health = 100;
        game_state.player.render_colour = .red;

        for (0..NUM_ENEMIES) |i| {
            const x = random.float(f32) * tile_map_width;
            const y = random.float(f32) * tile_map_height;
            game_state.enemies[i].position_x = x;
            game_state.enemies[i].position_y = y;
            game_state.enemies[i].stats.movement_speed = 4.5;
            game_state.enemies[i].stats.current_health = 100;
            game_state.enemies[i].stats.max_health = 100;
            game_state.enemies[i].render_colour = .blue;
        }
    }

    engine.renderer.setMetersPerPixel(meters_per_pixel);

    return @ptrCast(game_state);
}

pub fn deinit(_: *EngineState, _: *anyopaque) void {}

pub fn updateAndRender(
    engine: *EngineState,
    game_state: *anyopaque,
) bool {
    const renderer: *Renderer = &engine.renderer;
    const state: *GameState = @ptrCast(@alignCast(game_state));
    var running: bool = true;

    // NOTE: Clear to magenta
    renderer.clearScreen(1.0, 0.0, 1.0);

    if (engine.input.isKeyDown(.escape)) {
        running = false;
    }

    if (engine.input.mouseButtonPressedThisFrame(.left)) {
        _ = engine.sound.playSound(state.pop_sound.data, .{});
    }

    if (engine.input.keyPressedThisFrame(.space)) {
        _ = engine.sound.playSound(state.impact_sound.data, .{});
    }

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

        var new_camera_x = state.camera_x + delta_x * state.player.stats.movement_speed * engine.delta_time;
        var new_camera_y = state.camera_y + delta_y * state.player.stats.movement_speed * engine.delta_time;

        // Clamp player position to the tile map. The tile map top right is the 0, 0 position.

        new_camera_x = std.math.clamp(
            new_camera_x,
            0,
            tile_map_width,
        );
        new_camera_y = std.math.clamp(
            new_camera_y,
            0,
            tile_map_height,
        );

        // @INCOMPLETE: Collision detection against tilemap
        // @TODO: Spawn a collision box when the player attacks the ground. This box should have a damage value that
        // is applied to the enemies when they collide with it with corresponding on hit effects

        state.camera_x = new_camera_x;
        state.camera_y = new_camera_y;
        state.player.position_x = new_camera_x;
        state.player.position_y = new_camera_y;
    }

    { // Enemy movement
        // NOTE: The enemies move towards the player always
        // @TODO: Enemey collision detection
        // @TODO: Spacial partitioning for enemies to reduce the number of collision checks
        // @TODO: Maybe a flow field for path finding?

        // for (0..state.enemies.len) |i| {
        //     const enemy = &state.enemies[i];
        //     const player = &state.player;
        //     var delta_x: f32 = player.position_x - enemy.position_x;
        //     var delta_y: f32 = player.position_y - enemy.position_y;
        //     const magnitude = std.math.sqrt(delta_x * delta_x + delta_y * delta_y);
        //     if (magnitude > 0.0) {
        //         const magnitude_inv: f32 = 1.0 / magnitude;
        //         delta_x = delta_x * magnitude_inv;
        //         delta_y = delta_y * magnitude_inv;
        //     }
        //
        //     enemy.position_x = enemy.position_x + delta_x * enemy.stats.movement_speed * engine.delta_time;
        //     enemy.position_y = enemy.position_y + delta_y * enemy.stats.movement_speed * engine.delta_time;
        // }
    }

    { // Draw tile map
        const floor_colour: Color = .green;
        const wall_colour: Color = .brown;

        // Player is at the center of the screen always so draw the player there and the camera moves with the player
        // Based on the player position figure out the tiles we need to draw
        // NOTE: Culling what needs to be drawn. THis becomes frusturm culling when we move to 3D
        const top_left_tile_x_int: i32 = @intFromFloat(@floor(state.camera_x - state.view_half_width));
        const top_left_tile_x: usize = @intCast(std.math.clamp(top_left_tile_x_int, 0, state.tile_map.tile_width - 1));

        const top_left_tile_y_int: i32 = @intFromFloat(@floor(state.camera_y - state.view_half_height));
        const top_left_tile_y: usize = @intCast(std.math.clamp(top_left_tile_y_int, 0, state.tile_map.tile_height - 1));

        const bottom_right_tile_x_int: i32 = @intFromFloat(@ceil(state.camera_x + state.view_half_width));
        const bottom_right_tile_x: usize = @intCast(std.math.clamp(bottom_right_tile_x_int, 0, state.tile_map.tile_width - 1));

        const bottom_right_tile_y_int: i32 = @intFromFloat(@ceil(state.camera_y + state.view_half_height));
        const bottom_right_tile_y: usize = @intCast(std.math.clamp(bottom_right_tile_y_int, 0, state.tile_map.tile_height - 1));

        for (top_left_tile_y..bottom_right_tile_y + 1) |y| {
            for (top_left_tile_x..bottom_right_tile_x + 1) |x| {
                const tile_type = state.tile_map.data[y * state.tile_map.tile_width + x];
                const x_position = @as(f32, @floatFromInt(x)) - state.camera_x + state.view_half_width;
                const y_position = @as(f32, @floatFromInt(y)) - state.camera_y + state.view_half_height;
                switch (tile_type) {
                    .floor => {
                        renderer.drawRectangle(
                            x_position,
                            y_position,
                            tile_width,
                            tile_height,
                            floor_colour,
                        );
                    },
                    .wall => {
                        renderer.drawRectangle(
                            x_position,
                            y_position,
                            tile_width,
                            tile_height,
                            wall_colour,
                        );
                    },
                    else => {},
                }
            }
        }
    }

    { // Draw enemies
        for (0..state.enemies.len) |i| {
            const enemey_screen_x = state.enemies[i].position_x - state.camera_x + state.view_half_width;
            const enemey_screen_y = state.enemies[i].position_y - state.camera_y + state.view_half_height;
            renderer.drawRectangle(
                enemey_screen_x - player_half_width,
                enemey_screen_y - player_height / 2,
                player_width,
                player_height,
                state.enemies[i].render_colour,
            );
        }
    }

    { // Draw player at the center of the screen always
        // NOTE: The players anchor point is at the feet of the player
        renderer.drawRectangle(
            state.view_half_width - player_half_width,
            state.view_half_height - player_height / 2,
            player_width,
            player_height,
            state.player.render_colour,
        );
    }

    return running;
}
