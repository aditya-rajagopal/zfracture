const config = @import("config.zig");
const core = @import("fr_core");

pub const GameState = struct {
    delta_time: f64,
    testing: bool = false,
};

pub fn init(engine: *core.Fracture) ?*anyopaque {
    const foo_allocator: std.mem.Allocator = engine.memory.gpa.get_type_allocator(.game);
    const state = foo_allocator.create(GameState) catch return null;
    state.testing = true;
    state.delta_time = 0.0;
    return state;
}

pub fn deinit(engine: *core.Fracture, game_state: *anyopaque) void {
    const state: *GameState = @ptrCast(@alignCast(game_state));
    const foo_allocator = engine.memory.gpa.get_type_allocator(.game);
    foo_allocator.destroy(state);
}

pub fn update(engine: *core.Fracture, game_state: *anyopaque) bool {
    const state: *GameState = @ptrCast(@alignCast(game_state));
    if (state.testing) {
        const frame_alloc = engine.memory.frame_allocator.get_type_allocator(.application);
        const temp_data = frame_alloc.alloc(f32, 16) catch return false;
        engine.memory.gpa.print_memory_stats(&engine.core_log);
        engine.memory.frame_allocator.print_memory_stats(&engine.core_log);
        frame_alloc.free(temp_data);
        state.testing = false;
    }
    return true;
}

pub fn render(engine: *core.Fracture, game_state: *anyopaque) bool {
    _ = engine;
    _ = game_state;
    return true;
}

pub fn on_resize(engine: *core.Fracture, game_state: *anyopaque, width: u32, height: u32) void {
    _ = engine; // autofix
    _ = game_state;
    _ = width;
    _ = height;
}

const std = @import("std");
