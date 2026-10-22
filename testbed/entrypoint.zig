const std = @import("std");
const builtin = @import("builtin");
const options = @import("build_options");
const fr = @import("fracture");
const game = @import("game.zig");
const common = @import("common.zig");
const EngineState = common.EngineState;
const Renderer = fr.Renderer;
const Event = fr.event.Event;

pub const DebugGameDLLApi = struct {
    pub const InitFn = *const fn (*EngineState) callconv(.c) ?*anyopaque;
    pub const DeinitFn = *const fn (*EngineState, *anyopaque) callconv(.c) void;
    pub const UpdateAndRenderFn = *const fn (*EngineState, *anyopaque, [*]const Event, usize) callconv(.c) bool;
    init: InitFn,
    deinit: DeinitFn,
    updateAndRender: UpdateAndRenderFn,
};

const DebugGame = struct {
    instance: ?fr.Platform.DynamicLibrary = null,
    generation: u64 = 0,
    time_stamp: i96 = 0,
    file_size: u64 = 0,
    rejected_file: ?struct { time_stamp: i96, file_size: u64 } = null,
    temp_name: [4096]u8 = undefined,
    temp_name_len: usize = 0,
    game_api: DebugGameDLLApi = undefined,

    fn unload(self: *DebugGame, io: std.Io) void {
        std.debug.assert(self.temp_name_len <= self.temp_name.len);
        std.debug.assert((self.instance != null) == (self.temp_name_len != 0));
        if (self.instance) |*instance| instance.close();
        if (self.temp_name_len != 0) {
            std.Io.Dir.cwd().deleteFile(
                io,
                self.temp_name[0..self.temp_name_len],
            ) catch |err| std.log.warn("Failed to remove game library copy: {s}", .{@errorName(err)});
        }
        self.instance = null;
        self.temp_name_len = 0;
    }
};

pub const AppState = struct {
    engine: EngineState,
    debug_game: if (builtin.mode == .debug) DebugGame else void,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var platform: fr.Platform = .{};
    try platform.init();
    defer platform.deinit();

    const allocator = std.heap.page_allocator;
    const permanent_memory_size = fr.MB(128);
    const transient_memory_size = fr.MB(128);
    const game_memory = try allocator.alloc(u8, permanent_memory_size + transient_memory_size);
    defer allocator.free(game_memory);

    const permanent_memory = game_memory[0..permanent_memory_size];
    var permanent_fixed_buffer = std.heap.FixedBufferAllocator.init(permanent_memory);
    const transient_memory = game_memory[permanent_memory_size..];
    var transient_fixed_buffer = std.heap.FixedBufferAllocator.init(transient_memory);
    const permanent_allocator = permanent_fixed_buffer.allocator();

    const app_state = try permanent_allocator.create(AppState);
    const engine_state = &app_state.engine;
    engine_state.io = io;
    engine_state.permanent_allocator = permanent_allocator;
    engine_state.transient_allocator = transient_fixed_buffer.allocator();
    engine_state.delta_time = 0;

    try engine_state.sound.init();
    defer engine_state.sound.deinit();

    engine_state.renderer.back_buffer = .{
        .width = 1280,
        .height = 720,
        .data = try permanent_allocator.alignedAlloc(
            u8,
            .fromByteUnits(4096),
            4096 * 2048 * Renderer.bytes_per_pixel,
        ),
    };
    engine_state.renderer.clearScreen(0, 0, 0);

    try platform.createWindow(.{
        .title = "Testbed",
        .frame_buffer = &engine_state.renderer.back_buffer,
        .windowed_frame_margin = common.windowed_frame_margin,
    });
    defer platform.destroyWindow();
    platform.showWindow();

    if (builtin.mode == .debug) {
        app_state.debug_game = .{};
        _ = try reloadLibrary(io, &app_state.debug_game, options.game_library_path);
    }
    defer if (builtin.mode == .debug) app_state.debug_game.unload(io);

    const game_state = if (builtin.mode == .debug)
        app_state.debug_game.game_api.init(engine_state) orelse
            return error.GameInitializationFailed
    else
        game.init(engine_state);
    defer {
        if (builtin.mode == .debug) {
            app_state.debug_game.game_api.deinit(engine_state, game_state);
        } else {
            game.deinit(engine_state, game_state);
        }
    }

    var running = true;
    var pacing_error: ?fr.Platform.PaceFrameError = null;
    var cursor_hidden = true;
    var host_controls: common.HostControls = .{};
    var frame_timestamp = std.Io.Clock.awake.now(io);
    var dll_timestamp = frame_timestamp;
    var last_reload_error: ?anyerror = null;

    while (running) {
        const frame_start = std.Io.Clock.awake.now(io);
        var pacing_start = frame_start;
        defer {
            if (running) {
                platform.paceFrame(io, pacing_start, common.frame_duration) catch |err| {
                    running = false;
                    if (err != error.Canceled) pacing_error = err;
                };
            }
        }

        platform.beginFrame();
        defer platform.endFrame();
        defer transient_fixed_buffer.reset();

        const status = platform.pollEvents();
        if (status.quit_requested) {
            running = false;
            break;
        }
        engine_state.sound.update();

        const now = std.Io.Clock.awake.now(io);
        if (status.blocking_interaction_ended) {
            engine_state.delta_time = 0;
            pacing_start = now;
        } else {
            const elapsed_ns = frame_timestamp.durationTo(now).toNanoseconds();
            std.debug.assert(elapsed_ns >= 0);
            engine_state.delta_time = @as(f32, @floatFromInt(elapsed_ns)) / std.time.ns_per_s;
        }
        frame_timestamp = now;

        const events = platform.takeEvents();
        host_controls.consumeFrame(events);
        running = if (builtin.mode == .debug)
            app_state.debug_game.game_api.updateAndRender(engine_state, game_state, events.ptr, events.len)
        else
            game.updateAndRender(engine_state, game_state, events);

        platform.present();

        const control = host_controls.down.ctrl or host_controls.pressed_this_frame.ctrl;
        if (host_controls.pressed_this_frame.@"3" and !control) {
            cursor_hidden = !cursor_hidden;
            platform.setCursorHidden(cursor_hidden);
        }

        const alt = host_controls.down.alt or host_controls.pressed_this_frame.alt;
        const toggle_fullscreen = alt and host_controls.pressed_this_frame.enter;
        if (toggle_fullscreen) {
            platform.toggleFullscreen();
        }

        if (builtin.mode == .debug) {
            if (dll_timestamp.durationTo(now).toNanoseconds() > std.time.ns_per_s / 30) {
                dll_timestamp = now;
                _ = reloadLibrary(
                    io,
                    &app_state.debug_game,
                    options.game_library_path,
                ) catch |err| {
                    if (last_reload_error == null or last_reload_error.? != err) {
                        std.log.err(
                            "Failed to reload game library: {s}",
                            .{@errorName(err)},
                        );
                    }
                    last_reload_error = err;
                    continue;
                };
                last_reload_error = null;
            }
        }
    }
    if (pacing_error) |err| return err;
}

fn reloadLibrary(io: std.Io, debug_game: *DebugGame, library_path: []const u8) !bool {
    const dir = std.Io.Dir.cwd();
    const stats = try dir.statFile(io, library_path, .{});
    if (debug_game.instance != null) {
        if (debug_game.time_stamp == stats.mtime.nanoseconds and debug_game.file_size == stats.size) {
            return false;
        }
    }

    // NOTE(adi): If we a dll fails because it did not have the required functions we rejected the last time and
    // if the same file exists still we dont try to read it again and just exit early
    if (debug_game.rejected_file) |rejected| {
        if (rejected.time_stamp == stats.mtime.nanoseconds and rejected.file_size == stats.size) {
            return false;
        }
        debug_game.rejected_file = null;
    }

    debug_game.generation = std.math.add(
        u64,
        debug_game.generation,
        1,
    ) catch return error.ReloadGenerationOverflow;
    // Avoid reusing copies left by crashed processes, even after PID reuse.
    var copy_nonce: u128 = undefined;
    io.random(std.mem.asBytes(&copy_nonce));
    var temp_name_buffer: [debug_game.temp_name.len]u8 = undefined;
    const temp_name = try std.fmt.bufPrintSentinel(
        &temp_name_buffer,
        "{s}.{d}.{d}.{x}",
        .{ library_path, fr.Platform.processId(), debug_game.generation, copy_nonce },
        0,
    );
    try dir.copyFile(library_path, dir, temp_name, io, .{ .replace = false });
    errdefer dir.deleteFile(io, temp_name) catch |err| {
        std.log.warn("Failed to remove candidate copy: {s}", .{@errorName(err)});
    };

    const copied_stats = try dir.statFile(io, library_path, .{});
    if (stats.mtime.nanoseconds != copied_stats.mtime.nanoseconds or
        stats.size != copied_stats.size)
    {
        return error.LibraryChangedDuringCopy;
    }

    var instance = try fr.Platform.DynamicLibrary.open(temp_name);
    // Only export validation can fail from here. Do not repeatedly load a rejected
    // build: macOS keeps TLS-bearing images mapped even after close.
    errdefer {
        debug_game.rejected_file = .{ .time_stamp = stats.mtime.nanoseconds, .file_size = stats.size };
        instance.close();
    }

    const init_fn = instance.lookup(DebugGameDLLApi.InitFn, "init") orelse return error.FailedToLookupInitFn;
    const deinit_fn = instance.lookup(DebugGameDLLApi.DeinitFn, "deinit") orelse return error.FailedToLookupDeinitFn;
    const update_fn = instance.lookup(DebugGameDLLApi.UpdateAndRenderFn, "updateAndRender") orelse return error.FailedToLookupUpdateAndRenderFn;

    // A failed reload must leave the old game callable, so validate before unloading it.
    debug_game.unload(io);
    debug_game.instance = instance;
    debug_game.game_api = .{ .init = init_fn, .deinit = deinit_fn, .updateAndRender = update_fn };
    debug_game.time_stamp = stats.mtime.nanoseconds;
    debug_game.file_size = stats.size;
    @memcpy(debug_game.temp_name[0..temp_name.len], temp_name);
    debug_game.temp_name_len = temp_name.len;
    std.log.info("Loaded game library generation {d}", .{debug_game.generation});
    return true;
}
