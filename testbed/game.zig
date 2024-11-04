const config = @import("config.zig");
const core = @import("fr_core");
const m = core.math;

const GameLog = core.log.ScopedLogger(core.log.default_log, .GAME, core.log.default_level);

pub const GameState = struct {
    delta_time: f64,
    testing: bool = false,
    log: GameLog,
    camera_pos: m.Vec3,
    camera_euler: m.Vec3,
    camera_dirty: bool,
    move_speed: f32,
};

pub fn init(engine: *core.Fracture) ?*anyopaque {
    const foo_allocator: std.mem.Allocator = engine.memory.gpa.get_type_allocator(.game);
    const state = foo_allocator.create(GameState) catch return null;
    state.testing = true;
    state.delta_time = 1.0;
    state.log = GameLog.init(&engine.log_config);
    state.camera_pos = m.vec3s(0, 0, 2.0);
    state.camera_euler = m.Vec3.zeros;
    state.camera_dirty = true;
    state.move_speed = 5.0;
    engine.camera_dirty = true;
    // _ = engine.event.register(.KEY_PRESS, state, random_event);
    // _ = engine.event.register(.KEY_RELEASE, state, random_event);
    // _ = engine.event.register(.KEY_ESCAPE, state, random_event);
    // _ = engine.event.register(.MOUSE_BUTTON_PRESS, state, random_event);
    // _ = engine.event.register(.MOUSE_BUTTON_RELEASE, state, random_event);
    return state;
}

pub fn deinit(engine: *core.Fracture, game_state: *anyopaque) void {
    const state: *GameState = @ptrCast(@alignCast(game_state));
    const foo_allocator = engine.memory.gpa.get_type_allocator(.game);
    foo_allocator.destroy(state);
    // _ = engine.event.deregister(.KEY_PRESS, game_state, random_event);
    // _ = engine.event.deregister(.KEY_RELEASE, game_state, random_event);
    // _ = engine.event.deregister(.KEY_ESCAPE, game_state, random_event);
    // _ = engine.event.deregister(.MOUSE_BUTTON_PRESS, game_state, random_event);
    // _ = engine.event.deregister(.MOUSE_BUTTON_RELEASE, game_state, random_event);
}

pub fn update(engine: *core.Fracture, game_state: *anyopaque) bool {
    const state: *GameState = @ptrCast(@alignCast(game_state));
    const frame_alloc = engine.memory.frame_allocator.get_type_allocator(.untagged);
    const temp_data = frame_alloc.alloc(f32, 16) catch return false;
    _ = temp_data;
    if (state.testing) {
        engine.memory.gpa.print_memory_stats();
        engine.memory.frame_allocator.print_memory_stats();
        state.testing = false;
    }

    {
        // HACK: Setting the camera view in the hacked engine view

        const delta_time = engine.delta_time;

        if (engine.input.is_key_down(.Q) or engine.input.is_key_down(.LEFT)) {
            camera_yaw(state, 1.0 * delta_time);
        }

        if (engine.input.is_key_down(.E) or engine.input.is_key_down(.RIGHT)) {
            camera_yaw(state, -1.0 * delta_time);
        }

        if (engine.input.is_key_down(.UP)) {
            camera_pitch(state, 1.0 * delta_time);
        }

        if (engine.input.is_key_down(.DOWN)) {
            camera_pitch(state, -1.0 * delta_time);
        }

        var velocity = m.Vec3.zeros;

        if (engine.input.is_key_down(.W)) {
            const forward = engine.view.to_affine().get_forward();
            velocity = velocity.add(&forward);
        }

        if (engine.input.is_key_down(.S)) {
            const backward = engine.view.to_affine().get_backward();
            velocity = velocity.add(&backward);
        }

        if (engine.input.is_key_down(.A)) {
            const left = engine.view.to_affine().get_left();
            velocity = velocity.add(&left);
        }

        if (engine.input.is_key_down(.D)) {
            const right = engine.view.to_affine().get_right();
            velocity = velocity.add(&right);
        }

        if (engine.input.is_key_down(.RSHIFT)) {
            velocity.vec[1] += 1.0;
        }

        if (engine.input.is_key_down(.RCONTROL)) {
            velocity.vec[1] -= 1.0;
        }

        if (!velocity.eql_approx(&m.Vec3.zeros, 0.0002)) {
            velocity = velocity.normalize(0.00000001);
            state.camera_pos.vec[0] += velocity.x() * delta_time * state.move_speed;
            state.camera_pos.vec[1] += velocity.y() * delta_time * state.move_speed;
            state.camera_pos.vec[2] += velocity.z() * delta_time * state.move_speed;
            state.camera_dirty = true;
        }

        if (engine.input.is_key_down(.KEY_1)) {
            state.camera_pos = m.vec3s(0, 0, 10.0);
            state.camera_euler = m.Vec3.zeros;
            state.camera_dirty = true;
        }

        recalculate_camera_view(engine, state);
    }

    return true;
}

fn recalculate_camera_view(engine: *core.Fracture, state: *GameState) void {
    if (state.camera_dirty) {
        const rot = m.Transform.init_rot_xyz(state.camera_euler.x(), state.camera_euler.y(), state.camera_euler.z());
        const trans = m.Transform.init_trans(&state.camera_pos);
        engine.view = trans.mul(&rot).inv_tr().to_mat();
        engine.camera_dirty = true;
        state.camera_dirty = false;
    }
}

inline fn camera_pitch(state: *GameState, amount: f32) void {
    // NOTE: Limiting the pitch to prevent gimble lock
    const pitch_limit = comptime m.deg_to_rad(89.0);
    state.camera_euler.vec[0] = m.clamp(state.camera_euler.vec[0] + amount, -pitch_limit, pitch_limit);
    state.camera_dirty = true;
}

inline fn camera_yaw(state: *GameState, amount: f32) void {
    state.camera_euler.vec[1] += amount;
    state.camera_dirty = true;
}

inline fn camera_roll(state: *GameState, amount: f32) void {
    state.camera_euler.vec[2] += amount;
    state.camera_dirty = true;
}

pub fn render(engine: *core.Fracture, game_state: *anyopaque) bool {
    _ = engine;
    _ = game_state;
    return true;
}

pub fn random_event(
    event_code: core.Event.EventCode,
    event_data: core.Event.EventData,
    listener: ?*anyopaque,
    sender: ?*anyopaque,
) bool {
    _ = sender;
    if (listener) |l| {
        const game_state: *GameState = @ptrCast(@alignCast(l));
        game_state.log.err("FROM GAME: {s}", .{@tagName(event_code)});
        game_state.log.err("FROM GAME: {any}", .{event_data});
    }
    return true;
}

pub fn on_resize(engine: *core.Fracture, game_state: *anyopaque, width: u32, height: u32) void {
    _ = engine; // autofix
    _ = game_state;
    _ = width;
    _ = height;
}

const std = @import("std");
const builtin = @import("builtin");
