const fr = @import("fracture");
const game = @import("game.zig");
const common = @import("common.zig");
const EngineState = common.EngineState;

export fn init(engine: *EngineState) ?*anyopaque {
    return game.init(engine);
}

export fn deinit(engine: *EngineState, game_state: *anyopaque) void {
    game.deinit(engine, game_state);
}

export fn updateAndRender(
    engine: *EngineState,
    game_state: *anyopaque,
) bool {
    return game.updateAndRender(engine, game_state);
}
