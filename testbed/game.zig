const std = @import("std");

const fr = @import("fracture");
const Renderer = fr.Renderer;
const Color = fr.Color;
const common = @import("common.zig");
const EngineState = common.EngineState;
const test_levels = @import("levels/level.zig").test_levels;

// NOTE: PoE1 and 2 do not have plyaer inertia.

// @TODO: Flow field for pathing?
// @TODO: Entitiy system that allows me to spawn arbitrary entities. Maybe have a separate slot for
// attack hit boxes?
// Renderer:
//      @TODO: Triangle rendering: We might be able to speed up rendering with simd by doing checks
//      in a 8x8 grid at once.
//      @TODO: Start with doing 3D geometry with software rendering. Swtich to OpenGL/Vulkan later.
//      @TODO: Premulitplied alpha blending for sprites and other geometry. Convert from sRGB to
//      linear space and back.
//      @TODO: Subpixel rendering
//      @TODO: Support normal maps
//      @TODO: Lighting
//      @TODO: Depth buffer and depth testing
//      @TODO: Render command queues to allow for culling and other optimizations
//      @TODO: Render to textures
// @TODO: Do we want enemy behaviour that is simulated when not interacting with the player? For
// example patrolling or
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

const meters_per_pixel: f32 = 1.0 / 48.0;

const player_width: f32 = tile_width;
const player_height: f32 = tile_height;
const player_half_width: f32 = player_width / 2.0;

// Outer void tiles pad the maps and must not enlarge the player's movement bounds.
const level_bounds = blk: {
    @setEvalBranchQuota(10000);
    var bounds: [test_levels.len]struct {
        min_x: f32,
        min_y: f32,
        max_x: f32,
        max_y: f32,
    } = undefined;
    for (test_levels, 0..) |level, index| {
        bounds[index] = .{
            .min_x = @as(f32, @floatFromInt(level.width)) * tile_width,
            .min_y = @as(f32, @floatFromInt(level.height)) * tile_height,
            .max_x = 0,
            .max_y = 0,
        };
        for (level.tiles, 0..) |tile, tile_index| {
            if (tile == 0) continue;

            const x = @as(f32, @floatFromInt(tile_index % level.width)) * tile_width;
            const y = @as(f32, @floatFromInt(tile_index / level.width)) * tile_height;
            bounds[index].min_x = @min(bounds[index].min_x, x);
            bounds[index].min_y = @min(bounds[index].min_y, y);
            bounds[index].max_x = @max(bounds[index].max_x, x + tile_width);
            bounds[index].max_y = @max(bounds[index].max_y, y + tile_height);
        }
    }
    break :blk bounds;
};

pub fn init(engine: *EngineState) *anyopaque {
    const game_state = engine.permanent_allocator.create(GameState) catch unreachable;
    game_state.latest_pop = null;

    const impact_sound = std.Io.Dir.cwd().readFileAlloc(
        engine.io,
        "assets/sounds/impactMetal_medium_000-converted.wav",
        engine.transient_allocator,
        .unlimited,
    ) catch unreachable;
    game_state.impact_sound = fr.wav.decode(
        engine.permanent_allocator,
        impact_sound,
    ) catch unreachable;

    const pop_sound = std.Io.Dir.cwd().readFileAlloc(
        engine.io,
        "assets/sounds/pop.wav",
        engine.transient_allocator,
        .unlimited,
    ) catch unreachable;
    game_state.pop_sound = fr.wav.decode(engine.permanent_allocator, pop_sound) catch unreachable;

    // TODO: Make this something like a view matrix.
    const buffer_width: f32 = @floatFromInt(engine.renderer.back_buffer.width);
    game_state.view_half_width = buffer_width * meters_per_pixel / 2.0;
    const buffer_height: f32 = @floatFromInt(engine.renderer.back_buffer.height);
    game_state.view_half_height = buffer_height * meters_per_pixel / 2.0;

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
    const bounds = level_bounds[state.level_index];

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

        var new_camera_x = state.camera_x +
            delta_x * state.player.stats.movement_speed * engine.delta_time;
        var new_camera_y = state.camera_y +
            delta_y * state.player.stats.movement_speed * engine.delta_time;

        // Position tracks the center; clamping it to the edge would leave half the player outside.
        new_camera_x = std.math.clamp(
            new_camera_x,
            bounds.min_x + player_half_width,
            bounds.max_x - player_half_width,
        );
        new_camera_y = std.math.clamp(
            new_camera_y,
            bounds.min_y + player_height / 2,
            bounds.max_y - player_height / 2,
        );

        // @INCOMPLETE: Collision detection against tilemap
        // @TODO: Spawn a collision box when the player attacks the ground. This box should have a
        // damage value that
        // is applied to the enemies when they collide with it with corresponding on hit effects

        state.camera_x = new_camera_x;
        state.camera_y = new_camera_y;
        state.player.position_x = new_camera_x;
        state.player.position_y = new_camera_y;
    }

    {
        const floor_colour: Color = .green;
        const wall_colour: Color = .brown;

        // Player is at the center of the screen always so draw the player there and the camera
        // moves with the player
        // Based on the player position figure out the tiles we need to draw
        // NOTE: Culling what needs to be drawn. THis becomes frusturm culling when we move to 3D
        const view_left = state.camera_x - state.view_half_width;
        const first_column_raw: i32 = @intFromFloat(@floor(view_left));
        const first_column: usize = @intCast(std.math.clamp(first_column_raw, 0, level.width - 1));

        const view_top = state.camera_y - state.view_half_height;
        const first_row_raw: i32 = @intFromFloat(@floor(view_top));
        const first_row: usize = @intCast(std.math.clamp(first_row_raw, 0, level.height - 1));

        const view_right = state.camera_x + state.view_half_width;
        const last_column_raw: i32 = @intFromFloat(@ceil(view_right));
        const last_column: usize = @intCast(std.math.clamp(last_column_raw, 0, level.width - 1));

        const view_bottom = state.camera_y + state.view_half_height;
        const last_row_raw: i32 = @intFromFloat(@ceil(view_bottom));
        const last_row: usize = @intCast(std.math.clamp(last_row_raw, 0, level.height - 1));

        for (first_row..last_row + 1) |y| {
            for (first_column..last_column + 1) |x| {
                const tile_type = level.tiles[y * level.width + x];
                const tile_x: f32 = @floatFromInt(x);
                const x_position = tile_x - state.camera_x + state.view_half_width;
                const tile_y: f32 = @floatFromInt(y);
                const y_position = tile_y - state.camera_y + state.view_half_height;

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

    {
        // The camera follows the player's center; the renderer takes the rectangle's corner.
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
        if (err != error.NoFreeVoices) {
            std.log.err(
                "Sound playback failed: {s}",
                .{@errorName(err)},
            );
        }
        return null;
    };
}
