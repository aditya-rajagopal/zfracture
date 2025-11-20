const std = @import("std");
const fracture = @import("fracture");
const EngineState = fracture.EngineState;
const FrameBuffer = fracture.FrameBuffer;
const Renderer = fracture.Renderer;
const Color = fracture.Color;
// NOTE: PoE1 and 2 do not have plyaer inertia.

// @TODO: Change coordinate system from pixels to meters
// @TODO: Full screen support and for debug builds only render the exact aspect ration of the screen buffer and leave
// the rest of the screen blank.
// @TODO: Collision detetion.
// @TODO: Entity type so that we can store a contiguous array of entities
// @TODO: Flow field for pathing?
// @TODO: Debug wireframe rectangles, lines and points
// @TODO: Player movement code unification so that it handles all keyboard events it needs to.
// @TODO: Enemies have a range where they leash to the player. We can simulate their movement only when they need to start moving
// towards or attack the player. There is also a range where they unleash from the player and stay where they are.
// @TODO: We need to simulate entities that are outside the screen. We can divide the Map into chunks and only update
// the entities that are in chunks the player has visited. We will not have a very large world so we will load all
// the entities needed for the particular level at once as dormant entities and add them to the active entity list
// When a particular chunk enters the simlulation region. We will update all entities that are active.
// We currently dont need the active entities to interact with dormant ones? Maybe there is a scenario where that might be
// needed? Excample if an enemy in the simulation region is the type that will go alert a bigger group of enemies when
// attacked it is possible that the entity that is to be activated is not in the active entity list.
// The simulation region is a rectangle that is centered around the player.
// We should spawn all entities that are needed for a level, even the ones that are "hidden" from the player and only
// activate when the player does certain actions like activating a mechanic or triggering a boss fight.
// @TODO: Arena allocator that is simpler than the one zig uses.
// @TODO: Spawn enemies all over the map.
// @TODO: Enemy attacks should spawn a damage box that contains the final damage calculated. The enemy attacks
// could be at different ranges and only deal damage if the player is in the range.
// @TODO: Level generation. Need a tool to help generate levels. This will need to also set masks for different types
// of terrains, eg. walkable, impassable, impassable but projectiles can go through, etc. As well as providing locations
// for specific events to be able to span as well as posssible spawn locations for enemies. I will not be doing complete
// random generation. I will use the PoE approach of creating a template for a level and then generating variations based
// on this template and at runtime choose one variation to load.
// @TODO: Entitiy system that allows me to spawn arbitrary entities. Maybe have a separate slot for attack hit boxes?
// @TODO: We need a way to change levels. Unload the previous level into disk so that the state is saved if the player
// wants to go back and load the new level along with all the assets and entities that are needed for it. We could
// @TODO: Need a simple debug UI system.
// @TODO: In game debug console
//
// @TODO: Create vector math.
// LOADERS:
//      @TODO: Load OBJ files and materials
//      @TODO: Load BMP/PNG files
//      @TODO: LOAD OGG files
//      @TODO: Load FBX/GLTF files?
//      @TODO: Load Fonts with TTF/OTF files (maybe create a bitmap for the fonts). Have default font for the engine.
//      @TODO: Load Text databases for ingame text
//      @TODO: Custom asset pipeline for loading assets
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
//
// @TODO: Do we want enemy behaviour that is simulated when not interacting with the player? For example patrolling or
// two groups of enemies that are fighing each other: YES

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

const tile_width: f32 = 32.0;
const tile_height: f32 = 32.0;

const player_width: f32 = tile_width;
const player_height: f32 = tile_height;
const player_half_width: f32 = player_width / 2.0;

pub fn init(engine: *EngineState) *anyopaque {
    const game_state = engine.permanent_allocator.create(GameState) catch unreachable;
    game_state.camera_x = @as(f32, @floatFromInt(engine.renderer.back_buffer.width)) / 2;
    game_state.camera_y = @as(f32, @floatFromInt(engine.renderer.back_buffer.height)) / 2;
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
        game_state.player.stats.movement_speed = 32.0 * 5;
        game_state.player.stats.current_health = 100;
        game_state.player.stats.max_health = 100;
        game_state.player.render_colour = .{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 };

        for (0..NUM_ENEMIES) |i| {
            game_state.enemies[i].position_x = game_state.camera_x + ((random.float(f32) * 2 - 1) * @as(f32, @floatFromInt(engine.renderer.back_buffer.width - 50))) / 2.0;
            game_state.enemies[i].position_y = game_state.camera_y + ((random.float(f32) * 2 - 1) * @as(f32, @floatFromInt(engine.renderer.back_buffer.height - 50))) / 2.0;
            game_state.enemies[i].stats.movement_speed = 32.0 * 4.5;
            game_state.enemies[i].stats.current_health = 100;
            game_state.enemies[i].stats.max_health = 100;
            game_state.enemies[i].render_colour = .{ .r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0 };
        }
    }

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

    const screen_width = @as(f32, @floatFromInt(engine.renderer.back_buffer.width));
    const screen_height = @as(f32, @floatFromInt(engine.renderer.back_buffer.height));

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

        var new_camera_x = state.camera_x + delta_x * state.player.stats.movement_speed * engine.delta_time / 1000.0;
        var new_camera_y = state.camera_y + delta_y * state.player.stats.movement_speed * engine.delta_time / 1000.0;

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

            enemy.position_x = enemy.position_x + delta_x * enemy.stats.movement_speed * engine.delta_time / 1000.0;
            enemy.position_y = enemy.position_y + delta_y * enemy.stats.movement_speed * engine.delta_time / 1000.0;
        }
    }

    { // Draw tile map
        const floor_colour: Color = .{ .r = 0.043, .g = 0.635, .b = 0.00, .a = 1.0 };
        const wall_colour: Color = .{ .r = 0.400, .g = 0.400, .b = 0.400, .a = 1.0 };

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
            const enemey_screen_x = state.enemies[i].position_x - state.camera_x + screen_width / 2;
            const enemey_screen_y = state.enemies[i].position_y - state.camera_y + screen_height / 2;
            renderer.drawRectangle(
                enemey_screen_x - player_half_width,
                enemey_screen_y - player_height,
                player_width,
                player_height,
                state.enemies[i].render_colour,
            );
        }
    }

    { // Draw player at the center of the screen always
        // NOTE: The players anchor point is at the feet of the player
        renderer.drawRectangle(
            screen_width / 2 - player_half_width,
            screen_height / 2 - player_height,
            player_width,
            player_height,
            state.player.render_colour,
        );
    }

    return running;
}
