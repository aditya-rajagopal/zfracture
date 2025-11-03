const fr = @import("fracture");
const game = @import("game.zig");

export fn init(engine: *fr.EngineState) ?*anyopaque {
    return game.init(engine);
}

export fn deinit(engine: *fr.EngineState, game_state: *anyopaque) void {
    game.deinit(engine, game_state);
}

export fn updateAndRender(
    engine: *fr.EngineState,
    game_state: *anyopaque,
) bool {
    return game.updateAndRender(engine, game_state);
}
