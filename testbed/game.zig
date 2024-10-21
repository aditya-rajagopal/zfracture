const config = @import("config.zig");
const core = @import("fr_core");

const GameLog = core.log.ScopedLogger(core.log.default_log, .game, core.log.default_level);

pub const GameState = struct {
    delta_time: f64,
    testing: bool = false,
    log: GameLog,
};

pub fn init(engine: *core.Fracture) ?*anyopaque {
    const foo_allocator: std.mem.Allocator = engine.memory.gpa.get_type_allocator(.game);
    const state = foo_allocator.create(GameState) catch return null;
    state.testing = true;
    state.delta_time = 1.0;
    state.log = GameLog.init(&engine.log_config);
    _ = engine.event.register(.KEY_PRESS, state, random_event);
    _ = engine.event.register(.KEY_RELEASE, state, random_event);
    _ = engine.event.register(.KEY_ESCAPE, state, random_event);
    _ = engine.event.register(.MOUSE_BUTTON_PRESS, state, random_event);
    _ = engine.event.register(.MOUSE_BUTTON_RELEASE, state, random_event);
    return state;
}

pub fn deinit(engine: *core.Fracture, game_state: *anyopaque) void {
    const state: *GameState = @ptrCast(@alignCast(game_state));
    const foo_allocator = engine.memory.gpa.get_type_allocator(.game);
    foo_allocator.destroy(state);
    _ = engine.event.deregister(.KEY_PRESS, game_state, random_event);
    _ = engine.event.deregister(.KEY_RELEASE, game_state, random_event);
    _ = engine.event.deregister(.KEY_ESCAPE, game_state, random_event);
    _ = engine.event.deregister(.MOUSE_BUTTON_PRESS, game_state, random_event);
    _ = engine.event.deregister(.MOUSE_BUTTON_RELEASE, game_state, random_event);
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
    if (engine.input.key_pressed_this_frame(.A)) {
        state.log.trace("A was pressed this frame", .{});
    }

    if (engine.input.key_released_this_frame(.A)) {
        state.log.trace("A was released this frame", .{});
    }

    if (engine.input.is_scroll_down()) {
        state.log.trace("Scrolled down!", .{});
    }

    return true;
}

pub fn render(engine: *core.Fracture, game_state: *anyopaque) bool {
    _ = engine;
    _ = game_state;
    return true;
}

pub fn random_event(
    event_code: core.event.EventCode,
    event_data: core.event.EventData,
    listener: ?*anyopaque,
    sender: ?*anyopaque,
) bool {
    _ = sender;
    if (listener) |l| {
        const game_state: *GameState = @ptrCast(@alignCast(l));
        game_state.log.trace("FROM GAME: {s}", .{@tagName(event_code)});
        game_state.log.trace("FROM GAME: {any}", .{event_data});
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
