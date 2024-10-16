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
    state.delta_time = 1.0;
    // const callback: core.event.EventCallback = .{ .listener = engine, .function = random_event };
    _ = engine.event.register(.KEY_PRESS, engine, random_event);
    _ = engine.event.register(.KEY_RELEASE, engine, random_event);
    _ = engine.event.register(.KEY_ESCAPE, engine, random_event);
    _ = engine.event.register(.MOUSE_BUTTON_PRESS, engine, random_event);
    _ = engine.event.register(.MOUSE_BUTTON_RELEASE, engine, random_event);
    return state;
}

pub fn deinit(engine: *core.Fracture, game_state: *anyopaque) void {
    const state: *GameState = @ptrCast(@alignCast(game_state));
    const foo_allocator = engine.memory.gpa.get_type_allocator(.game);
    foo_allocator.destroy(state);
    _ = engine.event.deregister(.KEY_PRESS, engine, random_event);
    _ = engine.event.deregister(.KEY_RELEASE, engine, random_event);
    _ = engine.event.deregister(.KEY_ESCAPE, engine, random_event);
    _ = engine.event.deregister(.MOUSE_BUTTON_PRESS, engine, random_event);
    _ = engine.event.deregister(.MOUSE_BUTTON_RELEASE, engine, random_event);
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
    if (engine.input.key_pressed_this_frame(.A)) {
        engine.log.trace("A was pressed this frame", .{});
    }

    if (engine.input.key_released_this_frame(.A)) {
        engine.log.trace("A was released this frame", .{});
    }

    // if (engine.input.is_key_down(.A)) {
    //     engine.log.trace("A is being pressed", .{});
    // }

    if (engine.input.is_scroll_down()) {
        engine.log.trace("Scrolled down!", .{});
    }

    // if (engine.input.is_mouse_moved()) {
    //     engine.log.trace("Mouse moved!", .{});
    // }

    // core.log.GameLog.err(&engine.log, "Hi ramani", .{});
    // engine.log.warn("Hi ramani", .{});
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
        const engine: *core.Fracture = @ptrCast(@alignCast(l));
        engine.log.trace("FROM GAME: {s}", .{@tagName(event_code)});
        engine.log.trace("FROM GAME: {any}", .{event_data});
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
