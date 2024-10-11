const types = @import("fracture").types;

pub const GameState = struct {
    delta_time: f64,
};

pub fn init(ctx: *types.AppContext) bool {
    _ = ctx;
    return true;
}

pub fn deinit(ctx: *types.AppContext) void {
    _ = ctx;
}

pub fn update(ctx: *types.AppContext, delta_time: f64) bool {
    _ = ctx;
    _ = delta_time;
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
