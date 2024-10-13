const types = @import("fracture").types;
const config = @import("config.zig");

pub const GameState = struct {
    delta_time: f64,
};

var game_state: *GameState = undefined;
var testing: bool = true;

pub fn init(ctx: *types.Fracture) bool {
    const foo_allocator = ctx.memory.gpa.get_type_allocator(.foo);
    game_state = foo_allocator.create(GameState) catch return false;
    return true;
}

pub fn deinit(ctx: *types.Fracture) void {
    const foo_allocator = ctx.memory.gpa.get_type_allocator(.foo);
    foo_allocator.destroy(game_state);
}

pub fn update(ctx: *types.Fracture, delta_time: f64) bool {
    game_state.delta_time = delta_time;
    if (testing) {
        const frame_alloc = ctx.memory.frame_allocator.get_type_allocator(.application);
        const temp_data = frame_alloc.alloc(f32, 16) catch return false;
        ctx.memory.gpa.print_memory_stats(&ctx.core_log);
        ctx.memory.frame_allocator.print_memory_stats(&ctx.core_log);
        frame_alloc.free(temp_data);
        testing = false;
    }
    return true;
}

pub fn render(ctx: *types.Fracture, delta_time: f64) bool {
    _ = ctx;
    _ = delta_time;
    return true;
}

pub fn on_resize(ctx: *types.Fracture, width: u32, height: u32) void {
    _ = ctx; // autofix
    _ = width;
    _ = height;
}

const std = @import("std");
