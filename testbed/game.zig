const types = @import("fracture").types;

pub const GameState = struct {
    delta_time: f64,
};

var game_state: *GameState = undefined;
var testing: bool = true;

pub fn init(ctx: *types.AppContext) bool {
    const foo_allocator = ctx.gpa.get_type_allocator(.foo);
    game_state = foo_allocator.create(GameState) catch return false;
    return true;
}

pub fn deinit(ctx: *types.AppContext) void {
    const foo_allocator = ctx.gpa.get_type_allocator(.foo);
    foo_allocator.destroy(game_state);
}

pub fn update(ctx: *types.AppContext, delta_time: f64) bool {
    game_state.delta_time = delta_time;
    if (testing) {
        const frame_alloc = ctx.frame_allocator.get_type_allocator(.application);
        const temp_data = frame_alloc.alloc(f32, 16) catch return false;
        ctx.gpa.print_memory_stats();
        ctx.frame_allocator.print_memory_stats();
        frame_alloc.free(temp_data);
        testing = false;
    }
    return true;
}

pub fn render(ctx: *types.AppContext, delta_time: f64) bool {
    _ = ctx;
    _ = delta_time;
    return true;
}

pub fn on_resize(ctx: *types.AppContext, width: u32, height: u32) void {
    _ = ctx; // autofix
    _ = width;
    _ = height;
}

const std = @import("std");
