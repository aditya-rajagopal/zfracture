pub const GameState = struct {
    delta_time: f64,
};

pub fn init(allocator: std.mem.Allocator) bool {
    _ = allocator;
    return true;
}

pub fn deinit() void {}

pub fn update(delta_time: f64) bool {
    _ = delta_time;
    return true;
}

pub fn render(delta_time: f64) bool {
    _ = delta_time;
    return true;
}

pub fn on_resize(width: u32, height: u32) void {
    _ = width;
    _ = height;
}

const std = @import("std");
