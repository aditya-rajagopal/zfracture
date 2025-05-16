const std = @import("std");
const builtin = @import("builtin");

const core = @import("fr_core");
const math = core.math;

const config = @import("config.zig");

const GameLog = core.log.ScopedLogger(core.log.default_log, .GAME, core.log.default_level);

pub const GameState = struct {
    delta_time: f64,
    log: GameLog,
    // HACK: temp
    generation: u32,
    // HACK: Camera needed here
    near_clip: f32,
    far_clip: f32,
    view: math.Mat4,
    projection: math.Mat4,
    camera_pos: math.Vec3,
    camera_euler: math.Vec3,
    camera_dirty: bool,
    move_speed: f32,
    // HACK: For now this lives here
    render_data: core.renderer.RenderData,
    // HACK: Load random textures
    textures: [3]core.renderer.texture_system.TextureHandle,
};

pub fn init(engine: *core.Fracture) ?*anyopaque {
    const foo_allocator: std.mem.Allocator = engine.memory.gpa.get_type_allocator(.game);
    const state = foo_allocator.create(GameState) catch return null;
    state.delta_time = 1.0;
    state.log = GameLog.init(&engine.log_config);

    state.camera_pos = math.vec3s(0, 0, 2.0);
    state.camera_euler = math.Vec3.zeros;
    state.camera_dirty = true;
    state.move_speed = 5.0;
    state.generation = 0;
    state.near_clip = 0.1;
    state.far_clip = 1000.0;

    state.projection = math.Mat4.perspective(math.deg_to_rad(45.0), 1920.0 / 1080.0, state.near_clip, state.far_clip);
    state.view = math.Transform.init_trans(&math.Vec3.init(0.0, 0.0, -2.0)).to_mat();

    state.render_data.material_id = engine.renderer.shader_acquire_resource();
    state.render_data.model = math.Transform.identity;
    state.render_data.textures[0] = .missing_texture;
    state.textures = [_]core.renderer.texture_system.TextureHandle{.null_handle} ** 3;

    const names = [_][]const u8{ "paving", "cobblestone", "paving2" };
    for (names, 0..) |name, i| {
        state.textures[i] = engine.renderer.textures.create(name, .default);
    }
    return state;
}

pub fn deinit(engine: *core.Fracture, game_state: *anyopaque) void {
    const state: *GameState = @ptrCast(@alignCast(game_state));
    const foo_allocator = engine.memory.gpa.get_type_allocator(.game);
    foo_allocator.destroy(state);
}

pub fn update_and_render(engine: *core.Fracture, game_state: *anyopaque) bool {
    const state: *GameState = @ptrCast(@alignCast(game_state));
    const frame_alloc = engine.memory.frame_allocator.get_type_allocator(.untagged);
    const temp_data = frame_alloc.alloc(f32, 16) catch return false;
    _ = temp_data;

    if (engine.input.is_key_down(.RCONTROL) and engine.input.is_key_down(.P)) {
        engine.memory.gpa.print_memory_stats();
        engine.memory.frame_allocator.print_memory_stats();
    }

    { // HACK: Flipping through textures
        if (engine.input.key_pressed_this_frame(.T)) {
            state.log.debug("Changing Texture", .{});
            const index = state.generation % 3;
            state.generation += 1;
            state.render_data.textures[0] = state.textures[index];
        }
    }

    { // HACK: Setting the camera view in the hacked engine view
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

        var velocity = math.Vec3.zeros;

        if (engine.input.is_key_down(.W)) {
            const forward = state.view.to_affine().get_forward();
            velocity = velocity.add(&forward);
        }

        if (engine.input.is_key_down(.S)) {
            const backward = state.view.to_affine().get_backward();
            velocity = velocity.add(&backward);
        }

        if (engine.input.is_key_down(.A)) {
            const left = state.view.to_affine().get_left();
            velocity = velocity.add(&left);
        }

        if (engine.input.is_key_down(.D)) {
            const right = state.view.to_affine().get_right();
            velocity = velocity.add(&right);
        }

        if (engine.input.is_key_down(.RSHIFT)) {
            const up = state.view.to_affine().get_up();
            velocity = velocity.add(&up);
        }

        if (engine.input.is_key_down(.LCONTROL)) {
            const down = state.view.to_affine().get_down();
            velocity = velocity.add(&down);
        }

        if (!velocity.eql_approx(&math.Vec3.zeros, 0.0002)) {
            velocity = velocity.normalize(0.00000001);
            state.camera_pos = state.camera_pos.add(&velocity.muls(delta_time * state.move_speed));
            state.camera_dirty = true;
        }

        if (engine.input.is_key_down(.KEY_1)) {
            state.camera_pos = math.vec3s(0, 0, 2.0);
            state.camera_euler = math.Vec3.zeros;
            state.camera_dirty = true;
        }

        // Re calculate the view matrix
        if (state.camera_dirty) {
            const rot = math.Transform.init_rot_xyz(state.camera_euler.x(), state.camera_euler.y(), state.camera_euler.z());
            const trans = math.Transform.init_trans(&state.camera_pos);
            state.view = trans.mul(&rot).inv_tr().to_mat();
            state.camera_dirty = false;
        }
    }

    { // HACK: Rendering
        engine.renderer.update_global_state(state.projection, state.view, math.Vec3.zeros, math.Vec4.ones, 0);
        engine.renderer.draw_temp_object(state.render_data);
    }

    return true;
}

inline fn camera_pitch(state: *GameState, amount: f32) void {
    // NOTE: Limiting the pitch to prevent gimble lock
    const pitch_limit = comptime math.deg_to_rad(89.0);
    state.camera_euler.vec[0] = math.clamp(state.camera_euler.vec[0] + amount, -pitch_limit, pitch_limit);
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

pub fn on_resize(engine: *core.Fracture, game_state: *anyopaque, width: u32, height: u32) void {
    _ = engine;
    const state: *GameState = @ptrCast(@alignCast(game_state));
    const aspect_ratio = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
    state.projection = math.Mat4.perspective(math.deg_to_rad(45.0), aspect_ratio, state.near_clip, state.far_clip);
}
