const entrypoint = @import("entrypoint");

pub const main = entrypoint.entrypoint;

export fn init(engine: *core.Fracture) ?*anyopaque {
    return game.init(engine);
}

export fn deinit(engine: *core.Fracture, game_state: *anyopaque) void {
    game.deinit(engine, game_state);
}

export fn update_and_render(engine: *core.Fracture, game_state: *anyopaque) bool {
    return game.update_and_render(engine, game_state);
}

export fn on_resize(engine: *core.Fracture, game_state: *anyopaque, width: u32, height: u32) void {
    return game.on_resize(engine, game_state, width, height);
}

pub const config = @import("config.zig");
const builtin = @import("builtin");
const core = @import("fr_core");
const game = @import("game.zig");
const std = @import("std");
