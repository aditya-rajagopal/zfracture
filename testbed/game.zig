const std = @import("std");

const fr = @import("fracture");
const Renderer = fr.Renderer;
const Color = fr.Color;
const common = @import("common.zig");
const EngineState = common.EngineState;
const test_levels = @import("levels/level.zig").test_levels;

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

pub const GameState = struct {
    impact_sound: fr.wav.WavData,
    pop_sound: fr.wav.WavData,
    latest_pop: ?fr.PlaybackHandle,

    level_index: usize,

    // FIXME: In screen space currently
    camera_x: f32,
    camera_y: f32,
    view_half_width: f32,
    view_half_height: f32,

    player: Entity,
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

const tile_width: f32 = 1.0;
const tile_height: f32 = 1.0;

const meters_per_pixel: f32 = 1.0 / 32.0;

const player_width: f32 = tile_width;
const player_height: f32 = tile_height;
const player_half_width: f32 = player_width / 2.0;

pub fn init(engine: *EngineState) *anyopaque {
    const game_state = engine.permanent_allocator.create(GameState) catch unreachable;
    game_state.latest_pop = null;

    const impact_sound = std.Io.Dir.cwd().readFileAlloc(
        engine.io,
        "assets/sounds/impactMetal_medium_000-converted.wav",
        engine.transient_allocator,
        .unlimited,
    ) catch unreachable;
    game_state.impact_sound = fr.wav.decode(engine.permanent_allocator, impact_sound) catch unreachable;
    const pop_sound = std.Io.Dir.cwd().readFileAlloc(
        engine.io,
        "assets/sounds/pop.wav",
        engine.transient_allocator,
        .unlimited,
    ) catch unreachable;
    game_state.pop_sound = fr.wav.decode(engine.permanent_allocator, pop_sound) catch unreachable;

    // TODO: Make this something like a view matrix.
    game_state.view_half_width = @as(f32, @floatFromInt(engine.renderer.back_buffer.width)) * meters_per_pixel / 2.0;
    game_state.view_half_height = @as(f32, @floatFromInt(engine.renderer.back_buffer.height)) * meters_per_pixel / 2.0;
    game_state.player = .{
        .entity_type = .player,
        .position_x = 0,
        .position_y = 0,
        .stats = .{ .movement_speed = 5, .current_health = 100, .max_health = 100 },
        .render_colour = .red,
    };
    enterLevel(game_state, 0);

    engine.renderer.setMetersPerPixel(meters_per_pixel);

    return @ptrCast(game_state);
}

pub fn deinit(_: *EngineState, _: *anyopaque) void {}

fn enterLevel(state: *GameState, index: usize) void {
    std.debug.assert(index < test_levels.len);
    const level = test_levels[index];
    state.level_index = index;
    state.player.position_x = (@as(f32, @floatFromInt(level.start.x)) + 0.5) * tile_width;
    state.player.position_y = (@as(f32, @floatFromInt(level.start.y)) + 0.5) * tile_height;
    state.camera_x = state.player.position_x;
    state.camera_y = state.player.position_y;
}

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
        if (playSound(engine, state.pop_sound.data)) |handle| state.latest_pop = handle;
    }

    if (engine.input.mouseButtonPressedThisFrame(.right)) {
        if (state.latest_pop) |handle| engine.sound.stop(handle);
        state.latest_pop = null;
    }

    if (engine.input.keyPressedThisFrame(.space)) {
        _ = playSound(engine, state.impact_sound.data);
    }

    var entered_level = false;
    const control = engine.input.isKeyDown(.lcontrol) or engine.input.isKeyDown(.rcontrol) or
        engine.input.keyPressedThisFrame(.lcontrol) or engine.input.keyPressedThisFrame(.rcontrol);
    const level_keys = [_]fr.input.Key{ .@"1", .@"2", .@"3" };
    for (level_keys, 0..) |key, index| {
        if (control and engine.input.keyPressedThisFrame(key)) {
            enterLevel(state, index);
            entered_level = true;
            break;
        }
    }

    const level = test_levels[state.level_index];
    const tile_map_width = @as(f32, @floatFromInt(level.width)) * tile_width;
    const tile_map_height = @as(f32, @floatFromInt(level.height)) * tile_height;

    if (!entered_level) { // Leave the player exactly at the start on entry.
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

        // Bounds-only movement; (0, 0) is the top-left corner of the map.

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

    { // Draw tile map
        const floor_colour: Color = .green;
        const wall_colour: Color = .brown;

        // Player is at the center of the screen always so draw the player there and the camera moves with the player
        // Based on the player position figure out the tiles we need to draw
        // NOTE: Culling what needs to be drawn. THis becomes frusturm culling when we move to 3D
        const top_left_tile_x_int: i32 = @intFromFloat(@floor(state.camera_x - state.view_half_width));
        const top_left_tile_x: usize = @intCast(std.math.clamp(top_left_tile_x_int, 0, level.width - 1));

        const top_left_tile_y_int: i32 = @intFromFloat(@floor(state.camera_y - state.view_half_height));
        const top_left_tile_y: usize = @intCast(std.math.clamp(top_left_tile_y_int, 0, level.height - 1));

        const bottom_right_tile_x_int: i32 = @intFromFloat(@ceil(state.camera_x + state.view_half_width));
        const bottom_right_tile_x: usize = @intCast(std.math.clamp(bottom_right_tile_x_int, 0, level.width - 1));

        const bottom_right_tile_y_int: i32 = @intFromFloat(@ceil(state.camera_y + state.view_half_height));
        const bottom_right_tile_y: usize = @intCast(std.math.clamp(bottom_right_tile_y_int, 0, level.height - 1));

        for (top_left_tile_y..bottom_right_tile_y + 1) |y| {
            for (top_left_tile_x..bottom_right_tile_x + 1) |x| {
                const tile_type = level.tiles[y * level.width + x];
                const x_position = @as(f32, @floatFromInt(x)) - state.camera_x + state.view_half_width;
                const y_position = @as(f32, @floatFromInt(y)) - state.camera_y + state.view_half_height;
                switch (tile_type) {
                    1 => { // Floor.
                        renderer.drawRectangle(
                            x_position,
                            y_position,
                            tile_width,
                            tile_height,
                            floor_colour,
                        );
                    },
                    2 => { // Wall.
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

    { // Draw player at the center of the screen always
        // The player position is the center of its one-tile rectangle.
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

fn playSound(engine: *EngineState, data: []const u8) ?fr.PlaybackHandle {
    return engine.sound.play(data) catch |err| {
        if (err != error.NoFreeVoices) std.log.err("Sound playback failed: {s}", .{@errorName(err)});
        return null;
    };
}
