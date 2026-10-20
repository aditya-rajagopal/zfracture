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

pub const Controls = struct {
    pressed_this_frame: struct {
        ctrl: bool = false,
        space: bool = false,
        p: bool = false,
        @"1": bool = false,
        @"2": bool = false,
        @"3": bool = false,
        left_mouse: bool = false,
        right_mouse: bool = false,
        g: bool = false,
    } = .{},
    down: struct {
        s: bool = false,
        f: bool = false,
        e: bool = false,
        d: bool = false,
        escape: bool = false,
        ctrl: bool = false,
    } = .{},

    // Retain each side so releasing one Ctrl does not release the other.
    modifier_down: u2 = 0,

    const left_ctrl: u2 = 1 << 0;
    const right_ctrl: u2 = 1 << 1;

    pub fn consumeFrame(self: *Controls, events: []const fr.event.Event) void {
        self.pressed_this_frame = .{};
        for (events) |event| {
            switch (event) {
                .key_pressed => |key| {
                    self.setHeld(key, true);
                    switch (key) {
                        .lcontrol, .rcontrol => self.pressed_this_frame.ctrl = true,
                        .space => self.pressed_this_frame.space = true,
                        .p => self.pressed_this_frame.p = true,
                        .g => self.pressed_this_frame.g = true,
                        .@"1" => self.pressed_this_frame.@"1" = true,
                        .@"2" => self.pressed_this_frame.@"2" = true,
                        .@"3" => self.pressed_this_frame.@"3" = true,
                        else => {},
                    }
                },
                .key_repeat => |key| self.setHeld(key, true),
                .key_released => |key| self.setHeld(key, false),
                .reset_keyboard, .reset_all => {
                    self.down = .{};
                    self.modifier_down = 0;
                },
                .mouse_pressed => |button| switch (button.button) {
                    .left => self.pressed_this_frame.left_mouse = true,
                    .right => self.pressed_this_frame.right_mouse = true,
                    else => {},
                },
                else => {},
            }
        }
    }

    fn setHeld(self: *Controls, key: fr.event.Key, is_down: bool) void {
        switch (key) {
            .s => self.down.s = is_down,
            .f => self.down.f = is_down,
            .e => self.down.e = is_down,
            .d => self.down.d = is_down,
            .escape => self.down.escape = is_down,
            .lcontrol, .rcontrol => {
                const mask: u2 = if (key == .lcontrol) left_ctrl else right_ctrl;
                if (is_down) {
                    self.modifier_down |= mask;
                } else {
                    self.modifier_down &= ~mask;
                }
                self.down.ctrl = self.modifier_down != 0;
            },
            else => {},
        }
    }
};

pub const GameState = struct {
    controls: Controls,
    impact_sound: fr.wav.WavData,
    pop_sound: fr.wav.WavData,
    latest_pop: ?fr.PlaybackHandle,

    level_index: usize,

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

const tile_width_meters: f32 = 1.0;
const tile_height_meters: f32 = 1.0;

const meters_per_pixel: f32 = 1.0 / 48.0;

const player_width: f32 = tile_width_meters;
const player_height: f32 = tile_height_meters;
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
            .min_x = @as(f32, @floatFromInt(level.width)) * tile_width_meters,
            .min_y = @as(f32, @floatFromInt(level.height)) * tile_height_meters,
            .max_x = 0,
            .max_y = 0,
        };
        for (level.tiles, 0..) |tile, tile_index| {
            if (tile == 0) continue;

            const x = @as(f32, @floatFromInt(tile_index % level.width)) * tile_width_meters;
            const y = @as(f32, @floatFromInt(tile_index / level.width)) * tile_height_meters;
            bounds[index].min_x = @min(bounds[index].min_x, x);
            bounds[index].min_y = @min(bounds[index].min_y, y);
            bounds[index].max_x = @max(bounds[index].max_x, x + tile_width_meters);
            bounds[index].max_y = @max(bounds[index].max_y, y + tile_height_meters);
        }
    }
    break :blk bounds;
};

pub fn init(engine: *EngineState) *anyopaque {
    const game_state = engine.permanent_allocator.create(GameState) catch unreachable;
    engine.renderer.setMetersPerPixel(meters_per_pixel);

    game_state.controls = .{};
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
    engine.renderer.updateCameraTo(game_state.player.position_x, game_state.player.position_y);

    return @ptrCast(game_state);
}

pub fn deinit(_: *EngineState, _: *anyopaque) void {}

fn enterLevel(state: *GameState, index: usize) void {
    std.debug.assert(index < test_levels.len);
    const level = test_levels[index];
    state.level_index = index;
    state.player.position_x = (@as(f32, @floatFromInt(level.start.x)) + 0.5) * tile_width_meters;
    state.player.position_y = (@as(f32, @floatFromInt(level.start.y)) + 0.5) * tile_height_meters;
}

pub fn updateAndRender(
    engine: *EngineState,
    game_state: *anyopaque,
    events: []const fr.event.Event,
) bool {
    engine.renderer.setMetersPerPixel(meters_per_pixel);
    const renderer: *Renderer = &engine.renderer;
    const state: *GameState = @ptrCast(@alignCast(game_state));
    state.controls.consumeFrame(events);
    const controls = &state.controls;
    var running: bool = true;

    // NOTE: Clear to magenta
    renderer.clearScreen(1.0, 0.0, 1.0);

    if (controls.down.escape) {
        running = false;
    }

    if (controls.pressed_this_frame.left_mouse) {
        if (playSound(engine, state.pop_sound.data)) |handle| state.latest_pop = handle;
    }

    if (controls.pressed_this_frame.right_mouse) {
        if (state.latest_pop) |handle| engine.sound.stop(handle);
        state.latest_pop = null;
    }

    if (controls.pressed_this_frame.space) {
        _ = playSound(engine, state.impact_sound.data);
    }

    if (controls.pressed_this_frame.p) {
        // The host measures frame intervals including pacing; held keys do not repeat this log.
        if (engine.delta_time > 0) {
            std.log.err("FPS: {d:.1} | frame: {d:.2} ms", .{
                1.0 / engine.delta_time,
                engine.delta_time * 1000.0,
            });
        } else {
            std.log.info("FPS: waiting for a timed frame", .{});
        }
    }

    var entered_level = false;
    const control = controls.down.ctrl or controls.pressed_this_frame.ctrl;
    const level_presses = [_]bool{ controls.pressed_this_frame.@"1", controls.pressed_this_frame.@"2", controls.pressed_this_frame.@"3" };
    for (level_presses, 0..) |pressed, index| {
        if (control and pressed) {
            enterLevel(state, index);
            renderer.updateCameraTo(state.player.position_x, state.player.position_y);
            entered_level = true;
            break;
        }
    }

    const level = test_levels[state.level_index];
    const bounds = level_bounds[state.level_index];

    if (!entered_level) { // Leave the player exactly at the start on entry.
        var delta_x: f32 = 0.0;
        var delta_y: f32 = 0.0;

        if (controls.down.s) {
            delta_x -= 1.0;
        }
        if (controls.down.f) {
            delta_x += 1.0;
        }
        if (controls.down.e) {
            delta_y -= 1.0;
        }
        if (controls.down.d) {
            delta_y += 1.0;
        }

        const magnitude = std.math.sqrt(delta_x * delta_x + delta_y * delta_y);
        if (magnitude > 0.0) {
            const magnitude_inv: f32 = 1.0 / magnitude;
            delta_x = delta_x * magnitude_inv;
            delta_y = delta_y * magnitude_inv;
        }

        var new_player_x = state.player.position_x +
            delta_x * state.player.stats.movement_speed * engine.delta_time;
        var new_player_y = state.player.position_y +
            delta_y * state.player.stats.movement_speed * engine.delta_time;

        // Position tracks the center; clamping it to the edge would leave half the player outside.
        new_player_x = std.math.clamp(
            new_player_x,
            bounds.min_x + player_half_width,
            bounds.max_x - player_half_width,
        );
        new_player_y = std.math.clamp(
            new_player_y,
            bounds.min_y + player_height / 2,
            bounds.max_y - player_height / 2,
        );

        // @INCOMPLETE: Collision detection against tilemap
        // @TODO: Spawn a collision box when the player attacks the ground. This box should have a
        // damage value that
        // is applied to the enemies when they collide with it with corresponding on hit effects
        state.player.position_x = new_player_x;
        state.player.position_y = new_player_y;
        renderer.updateCameraTo(new_player_x, new_player_y);
    }

    { // NOTE: Culling what needs to be drawn. THis becomes frusturm culling when we move to 3D
        const floor_colour: Color = .green;
        const wall_colour: Color = .brown;

        const visible_bounds = renderer.visibleWorldBounds();

        // Player is at the center of the screen always so draw the player there and the camera
        // moves with the player
        // Based on the player position figure out the tiles we need to draw

        const first_column_raw: i32 = @intFromFloat(@floor(visible_bounds.min_x));
        const first_column: u64 = @intCast(std.math.clamp(first_column_raw, 0, level.width - 1));

        const first_row_raw: i32 = @intFromFloat(@floor(visible_bounds.min_y));
        const first_row: u64 = @intCast(std.math.clamp(first_row_raw, 0, level.height - 1));

        const last_column_raw: i32 = @intFromFloat(@ceil(visible_bounds.max_x));
        const last_column: u64 = @intCast(std.math.clamp(last_column_raw, 0, level.width - 1));

        const last_row_raw: i32 = @intFromFloat(@ceil(visible_bounds.max_y));
        const last_row: u64 = @intCast(std.math.clamp(last_row_raw, 0, level.height - 1));

        for (first_row..last_row + 1) |y| {
            for (first_column..last_column + 1) |x| {
                const tile_type = level.tiles[y * level.width + x];
                const tile_x: f32 = @as(f32, @floatFromInt(x)) * tile_width_meters;
                const tile_y: f32 = @as(f32, @floatFromInt(y)) * tile_height_meters;
                const screen_position = renderer.screenFromWorld(tile_x, tile_y);
                if (state.controls.pressed_this_frame.g) {
                    std.log.info("Tile at {d}, {d}: {d}", .{ x, y, tile_type });
                    std.log.info("Screen position: {d}, {d}", .{ screen_position.x, screen_position.y });
                }

                switch (tile_type) {
                    1 => { // Floor.
                        renderer.drawRectangle(
                            screen_position.x,
                            screen_position.y,
                            tile_width_meters,
                            tile_height_meters,
                            floor_colour,
                        );
                    },
                    2 => { // Wall.
                        renderer.drawRectangle(
                            screen_position.x,
                            screen_position.y,
                            tile_width_meters,
                            tile_height_meters,
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

test "press flags survive same-frame releases and expire while holds persist" {
    var controls: Controls = .{};
    controls.consumeFrame(&.{
        .{ .key_pressed = .s },
        .{ .key_pressed = .space },
        .{ .key_released = .space },
        .{ .mouse_pressed = .{ .button = .left, .pos = .{ .x = 1, .y = 2 } } },
        .{ .mouse_released = .{ .button = .left, .pos = .{ .x = 1, .y = 2 } } },
    });
    try std.testing.expect(controls.pressed_this_frame.space);
    try std.testing.expect(controls.pressed_this_frame.left_mouse);
    controls.consumeFrame(&.{});
    try std.testing.expect(controls.down.s);
    try std.testing.expect(!controls.pressed_this_frame.space);
    try std.testing.expect(!controls.pressed_this_frame.left_mouse);
    controls.consumeFrame(&.{.{ .key_released = .s }});
    try std.testing.expect(!controls.down.s);
}

test "resets affect only their scope and preserve this frame's presses" {
    const cases = [_]struct { reset: fr.event.Event, keyboard_down: bool }{
        .{ .reset = .reset_keyboard, .keyboard_down = false },
        .{ .reset = .reset_mouse, .keyboard_down = true },
        .{ .reset = .reset_all, .keyboard_down = false },
    };
    for (cases) |case| {
        var controls: Controls = .{};
        controls.consumeFrame(&.{
            .{ .key_pressed = .s },
            .{ .key_pressed = .lcontrol },
            .{ .key_pressed = .space },
            .{ .mouse_pressed = .{ .button = .left, .pos = .{ .x = 1, .y = 2 } } },
            case.reset,
        });
        try std.testing.expectEqual(case.keyboard_down, controls.down.s);
        try std.testing.expectEqual(case.keyboard_down, controls.down.ctrl);
        try std.testing.expect(controls.pressed_this_frame.ctrl);
        try std.testing.expect(controls.pressed_this_frame.space);
        try std.testing.expect(controls.pressed_this_frame.left_mouse);
    }
}

test "repeats restore held state without presses" {
    var controls: Controls = .{};
    controls.consumeFrame(&.{ .reset_keyboard, .{ .key_repeat = .s }, .{ .key_repeat = .space }, .{ .key_repeat = .lcontrol } });
    try std.testing.expect(controls.down.s);
    try std.testing.expect(controls.down.ctrl);
    try std.testing.expect(!controls.pressed_this_frame.space);
    try std.testing.expect(!controls.pressed_this_frame.ctrl);
}

test "control stays held until both sides are released" {
    var controls: Controls = .{};
    controls.consumeFrame(&.{
        .{ .key_pressed = .lcontrol },
        .{ .key_pressed = .rcontrol },
        .{ .key_pressed = .lcontrol },
        .{ .key_repeat = .lcontrol },
        .{ .key_released = .rcontrol },
    });
    try std.testing.expect(controls.down.ctrl);
    try std.testing.expect(controls.pressed_this_frame.ctrl);
    controls.consumeFrame(&.{.{ .key_released = .lcontrol }});
    try std.testing.expect(!controls.down.ctrl);
    try std.testing.expect(!controls.pressed_this_frame.ctrl);
}

test "reset forgets control sides before repeats restore them" {
    for ([_]fr.event.Event{ .reset_keyboard, .reset_all }) |reset| {
        var controls: Controls = .{};
        controls.consumeFrame(&.{ .{ .key_pressed = .lcontrol }, reset });
        try std.testing.expect(!controls.down.ctrl);
        try std.testing.expect(controls.pressed_this_frame.ctrl);
        controls.consumeFrame(&.{.{ .key_repeat = .rcontrol }});
        try std.testing.expect(controls.down.ctrl);
        try std.testing.expect(!controls.pressed_this_frame.ctrl);
        controls.consumeFrame(&.{.{ .key_released = .rcontrol }});
        try std.testing.expect(!controls.down.ctrl);
    }
}
