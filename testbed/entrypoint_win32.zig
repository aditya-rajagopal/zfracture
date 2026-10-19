// @TODO: Move most things into fracture.
const std = @import("std");
const windows = std.os.windows;
const builtin = @import("builtin");

const fr = @import("fracture");
const Renderer = fr.Renderer;
const KB = fr.KB;
const MB = fr.MB;
const GB = fr.GB;
const win32 = fr.win32;
const game = @import("game.zig");
const common = @import("common.zig");
const EngineState = common.EngineState;
const Key = fr.input.Key;
const MouseButton = fr.input.MouseButton;

const Win32Platform = struct {
    instance: windows.HINSTANCE,
    window: ?windows.HWND,
    device_context: windows.HDC,
    window_placement: win32.WINDOWPLACEMENT,
    fullscreen: bool = false,
    input: *fr.input.InputState,
    focused: bool = false,
    quit_requested: bool = false,
    input_suspended: bool = false,
    reset_frame_clock: bool = false,
    discard_input_before: ?u32 = null,

    const Self = @This();

    // Initialize in place: GWLP_USERDATA retains this address until destruction.
    fn createWindow(
        platform_state: *Win32Platform,
        window_title: [*:0]const u8,
        window_width: i32,
        window_height: i32,
        input: *fr.input.InputState,
    ) WindowCreateError!void {
        const engine_name: [*:0]const u8 = "zfracture";

        platform_state.instance = win32.GetModuleHandleA(null) orelse
            return error.FailedToGetModuleHandle;

        var window_class: win32.WNDCLASSA = .zero;
        window_class.style = .{ .OWNDC = 1 };
        window_class.lpfnWndProc = windowProc;
        window_class.hInstance = platform_state.instance;
        window_class.lpszClassName = engine_name;
        // window_class.hCursor = win32.LoadCursorA(null, win32.IDC_ARROW) orelse return
        // error.FailedToLoadCursor;

        const result = win32.RegisterClassA(&window_class);
        if (result == 0) {
            _ = win32.MessageBoxA(
                null,
                "Windows Registration Failed",
                "Error",
                win32.MB_ICONEXCLAMATION,
            );
            return error.FailedToRegisterWindowClass;
        }

        var window_x: i32 = 50;
        var window_y: i32 = 50;
        var window_final_width: i32 = window_width;
        var window_final_height: i32 = window_height;

        var window_style: u32 = win32.WS_SYSMENU | win32.WS_CAPTION | win32.WS_OVERLAPPED;
        const window_style_ex: u32 = win32.WS_EX_APPWINDOW;

        window_style |= win32.WS_MINIMIZEBOX;
        window_style |= win32.WS_MAXIMIZEBOX;
        window_style |= win32.WS_THICKFRAME;

        var border_rect: win32.RECT = std.mem.zeroes(win32.RECT);
        _ = win32.AdjustWindowRectEx(
            &border_rect,
            @bitCast(window_style),
            .FALSE,
            @bitCast(window_style_ex),
        );

        window_x += border_rect.left;
        window_y += border_rect.top;

        window_final_width += border_rect.right - border_rect.left;
        window_final_height += border_rect.bottom - border_rect.top;

        platform_state.window = win32.CreateWindowExA(
            @bitCast(window_style_ex),
            engine_name,
            window_title,
            @bitCast(window_style),
            window_x,
            window_y,
            window_final_width,
            window_final_height,
            null,
            null,
            platform_state.instance,
            null,
        ) orelse {
            _ = win32.MessageBoxA(
                null,
                "Windows Creation Failed",
                "Error",
                win32.MB_ICONEXCLAMATION,
            );
            return error.FailedToCreateWindow;
        };
        errdefer _ = win32.DestroyWindow(platform_state.window);

        platform_state.device_context = win32.GetDC(platform_state.window) orelse
            return error.FailedToGetDeviceContext;
        platform_state.window_placement.length = @sizeOf(win32.WINDOWPLACEMENT);
        platform_state.fullscreen = false;
        platform_state.input = input;
        platform_state.focused = false;
        platform_state.quit_requested = false;
        platform_state.input_suspended = false;
        platform_state.reset_frame_clock = false;
        platform_state.discard_input_before = null;

        // Creation callbacks see null user data until the platform is ready.
        const user_data: isize = @bitCast(@intFromPtr(platform_state));
        _ = win32.SetWindowLongPtrA(platform_state.window.?, win32.GWLP_USERDATA, user_data);
        // A zero return can mean success or failure; verify the stored pointer.
        if (win32.GetWindowLongPtrA(platform_state.window.?, win32.GWLP_USERDATA) != user_data) {
            return error.FailedToSetWindowUserData;
        }
    }

    fn destroyWindow(self: *Win32Platform) void {
        const window = self.window orelse return;
        _ = win32.SetWindowLongPtrA(window, win32.GWLP_USERDATA, 0);
        self.window = null;
        _ = win32.DestroyWindow(window);
    }

    fn showWindow(self: *Win32Platform) void {
        const show_window_command_flags: u32 = win32.SW_SHOW;
        _ = win32.ShowWindow(self.window, @bitCast(show_window_command_flags));
    }

    fn toggleFullscreen(self: *Self) void {
        const window_style = win32.GetWindowLongA(self.window, win32.GWL_STYLE);
        const WS_OVERLAPPEDWINDOW = @as(i32, @bitCast(win32.WS_OVERLAPPEDWINDOW));

        if ((window_style & WS_OVERLAPPEDWINDOW) != 0) {
            self.fullscreen = true;
            var monitor_info: win32.MONITORINFO = .{
                .cbSize = @sizeOf(win32.MONITORINFO),
                .rcMonitor = undefined,
                .rcWork = undefined,
                .dwFlags = 0,
            };

            // NOTE: Save the current window placement so we can restore it later.
            const placement_result = win32.GetWindowPlacement(self.window, &self.window_placement);
            // If Windows cannot find the closest monitor, use the primary monitor.
            const monitor = win32.MonitorFromWindow(self.window, win32.MONITOR_DEFAULTTOPRIMARY);
            const monitor_result = win32.GetMonitorInfoA(monitor, &monitor_info);
            if (placement_result.toBool() and monitor_result.toBool()) {
                // NOTE: We are changing the window style so that it has no borders or title bar and
                // then
                // setting the window position and size to be the top left corner of the monitor and
                // the size of the monitor
                _ = win32.SetWindowLongA(
                    self.window,
                    win32.GWL_STYLE,
                    window_style & ~WS_OVERLAPPEDWINDOW,
                );

                const monitor_width = monitor_info.rcMonitor.right - monitor_info.rcMonitor.left;
                const monitor_height = monitor_info.rcMonitor.bottom - monitor_info.rcMonitor.top;
                _ = win32.SetWindowPos(
                    self.window,
                    win32.HWND_TOPMOST,
                    monitor_info.rcMonitor.left,
                    monitor_info.rcMonitor.top,
                    monitor_width,
                    monitor_height,
                    @bitCast(win32.SWP_NOOWNERZORDER | win32.SWP_FRAMECHANGED),
                );
            }
        } else {
            self.fullscreen = false;
            _ = win32.SetWindowLongA(
                self.window,
                win32.GWL_STYLE,
                window_style | WS_OVERLAPPEDWINDOW,
            );
            _ = win32.SetWindowPlacement(self.window, &self.window_placement);

            const restore_flags = win32.SWP_NOMOVE | win32.SWP_NOSIZE |
                win32.SWP_NOOWNERZORDER | win32.SWP_FRAMECHANGED;
            _ = win32.SetWindowPos(
                self.window,
                win32.HWND_NOTOPMOST,
                0,
                0,
                0,
                0,
                @bitCast(restore_flags),
            );
        }
    }
};

const WindowCreateError = error{
    FailedToCreateWindow,
    FailedToGetModuleHandle,
    FailedToRegisterWindowClass,
    FailedToGetDeviceContext,
    FailedToLoadCursor,
    FailedToSetWindowUserData,
} || std.mem.Allocator.Error;

/// Indirect calls let debug builds replace game code without restarting the engine.
pub const DebugGameDLLApi = struct {
    pub const InitFn = *const fn (engine: *EngineState) callconv(.c) ?*anyopaque;
    pub const DeinitFn = *const fn (engine: *EngineState, game_state: *anyopaque) callconv(.c) void;
    pub const UpdateAndRenderFn = *const fn (
        engine: *EngineState,
        game_state: *anyopaque,
    ) callconv(.c) bool;

    init: InitFn,
    deinit: DeinitFn,
    updateAndRender: UpdateAndRenderFn,
};

const DebugGame = switch (builtin.mode) {
    .debug => struct {
        instance: windows.HINSTANCE,
        is_loaded: bool = false,
        temp_index: u1 = 0,
        time_stamp: i96 align(8),
        game_api: DebugGameDLLApi,
    },
    else => void,
};

pub const AppState = struct {
    engine: EngineState,
    debug_game: DebugGame,
};

const game_api_default = DebugGameDLLApi{
    .init = game.init,
    .deinit = game.deinit,
    .updateAndRender = game.updateAndRender,
};

const dll_name = "./zig-out/bin/dynamic_game.dll";

// TODO: Only have these in internal builds
var DBG_cursor: ?windows.HCURSOR = null;
var DBG_show_cursor: bool = false;

// LEFTOFF: Implement WAV file loading and decoding. Complete audio system
// TODO: We currently have 2 arenas. One is for permanent allocations which is the static lifetime
// arena.
// The ther is the transient arena which has the lifetime of a frame. We probably want more arenas
// with potentially
// different lifetimes such as a scene or game level arena. It is possible the renderer will need to
// allocate stuff
// when it is performing the rendering pass. We could also have fixed size arena pools for each
// thread/task that can be
// requested when one is run out.
pub fn main(init: std.process.Init) void {
    // TODO: Figure out the correct io for the platform
    const io = init.io;
    DBG_cursor = win32.LoadCursorA(null, win32.IDC_ARROW) orelse {
        _ = win32.MessageBoxA(null, "Failed to load cursor", "Error", win32.MB_ICONEXCLAMATION);
        return;
    };

    var running: bool = false;

    // TODO: What do we do about the back buffer? This is a renderer specific thing
    var buffer_info: win32.BITMAPINFO = undefined;

    // TODO: We need to figure out if I want to use the debug allocator since we are using fixed
    // buffer arenas
    const allocator = std.heap.page_allocator;

    // NOTE: We want to gaurantee that the game can run in a fixed amount of memory. We can bump
    // this up
    // dpeneding on if we ever see us running out of memory.
    const permanenent_memory_size = MB(128);
    const transient_memory_size = MB(128);
    const total_game_memory_size = permanenent_memory_size + transient_memory_size;

    // TODO: We may need more arenas depending on how the game goes.
    // TODO: We can just use VirtualAlloc to allocate a large virtual address space and then map
    // parts of it
    // into the different arenas so they can potentially grow? Maybe we want this sometimes.
    // Especially if we want
    // to allocate new arenas when some run out.
    // TODO: Create an arena allocator that we can use everywhere instead of passing the Allocator
    // struct around
    // since we only need alloc/push/pop and not free/realloc and stuff. We can create a allocator
    // if we really need it.
    // out of this one.
    const game_memory: []u8 = allocator.alloc(u8, total_game_memory_size) catch {
        _ = win32.MessageBoxA(
            null,
            "Failed to allocate game memory",
            "Error",
            win32.MB_ICONEXCLAMATION,
        );
        return;
    };

    const permanent_memory = game_memory[0..permanenent_memory_size];
    var permanent_fixed_buffer = std.heap.FixedBufferAllocator.init(permanent_memory);
    const permanent_allocator = permanent_fixed_buffer.allocator();

    const transient_memory = game_memory[permanenent_memory_size..total_game_memory_size];
    var transient_fixed_buffer = std.heap.FixedBufferAllocator.init(transient_memory);
    const transient_allocator = transient_fixed_buffer.allocator();

    const app_state: *AppState = permanent_allocator.create(AppState) catch {
        _ = win32.MessageBoxA(
            null,
            "Failed to allocate engine state",
            "Error",
            win32.MB_ICONEXCLAMATION,
        );
        return;
    };

    // TODO: Figure out why the engine pointer does not showup in raddebugger when allocated
    // directly vs
    // making a new type AppState and then allocating it.
    const engine_state: *EngineState = &app_state.engine;
    engine_state.io = io;

    engine_state.sound.init() catch |err| {
        var buffer: [1024]u8 = undefined;
        const msg = std.mem.printSentinel(
            &buffer,
            "Failed to initialize sound system: {s}",
            .{@errorName(err)},
            0,
        ) catch unreachable;
        _ = win32.MessageBoxA(null, msg.ptr, "Error", win32.MB_ICONEXCLAMATION);
        return;
    };

    engine_state.permanent_allocator = permanent_allocator;
    engine_state.transient_allocator = transient_allocator;
    engine_state.input = .init;

    // NOTE: We allocate a large enough back buffer such that we do not need to reallocate it. If
    // the window
    // size becomes larger than this we will just throw an error and disallow it. Especially if we
    // are rendering to a
    // smaller back buffer and stretching it to fit the window.
    // TODO: We need to make this configurable globally by the game.
    // TODO: We might lower this if we want a smaller memory footprint
    const max_window_width = 4096;
    const max_window_height = 2048;
    const window_buffer_max_size = max_window_width * max_window_height * Renderer.bytes_per_pixel;

    // TODO: Move to the renderer
    engine_state.renderer.back_buffer.width = 1280;
    engine_state.renderer.back_buffer.height = 720;
    engine_state.renderer.back_buffer.data = permanent_allocator.alignedAlloc(
        u8,
        .fromByteUnits(4096),
        window_buffer_max_size,
    ) catch {
        _ = win32.MessageBoxA(
            null,
            "Out of memory for back buffer allocation",
            "Error",
            win32.MB_ICONEXCLAMATION,
        );
        return;
    };
    engine_state.renderer.clearScreen(0, 0, 0);

    buffer_info = .{
        .bmiHeader = .{
            .biSize = @sizeOf(win32.BITMAPINFOHEADER),
            .biWidth = @intCast(engine_state.renderer.back_buffer.width),
            .biHeight = -@as(i32, @intCast(engine_state.renderer.back_buffer.height)),
            .biPlanes = 1,
            .biBitCount = 32,
            .biCompression = win32.BI_RGB,
            .biSizeImage = 0,
            .biXPelsPerMeter = 0,
            .biYPelsPerMeter = 0,
            .biClrUsed = 0,
            .biClrImportant = 0,
        },
        .bmiColors = .{
            .{ .rgbBlue = 0, .rgbGreen = 0, .rgbRed = 0, .rgbReserved = 0 },
        },
    };

    var platform_state: Win32Platform = undefined;
    const buffer_width: i32 = engine_state.renderer.back_buffer.width;
    const initial_window_width = buffer_width + 2 * common.windowed_frame_margin;
    const buffer_height: i32 = engine_state.renderer.back_buffer.height;
    const initial_window_height = buffer_height + 2 * common.windowed_frame_margin;

    platform_state.createWindow(
        "Testbed",
        initial_window_width,
        initial_window_height,
        &engine_state.input,
    ) catch |err| {
        var buffer: [1024]u8 = undefined;
        const msg = std.mem.printSentinel(
            &buffer,
            "Failed to initialize window: {s}",
            .{@errorName(err)},
            0,
        ) catch unreachable;
        _ = win32.MessageBoxA(null, msg.ptr, "Error", win32.MB_ICONEXCLAMATION);
        return;
    };

    defer platform_state.destroyWindow();
    platform_state.showWindow();

    switch (builtin.mode) {
        .debug => {
            app_state.debug_game.is_loaded = false;
            app_state.debug_game.temp_index = 0;
            app_state.debug_game.time_stamp = 0;
            const loaded = reloadLibrary(io, &app_state.debug_game) catch |err| {
                var buffer: [1024]u8 = undefined;
                const msg = std.mem.printSentinel(
                    &buffer,
                    "Failed to reload dynamic game library: {s}",
                    .{@errorName(err)},
                    0,
                ) catch unreachable;
                _ = win32.MessageBoxA(null, msg.ptr, "Error", win32.MB_ICONEXCLAMATION);
                return;
            };
            if (!loaded) {
                _ = win32.MessageBoxA(
                    null,
                    "Failed to reload dynamic game library",
                    "Error",
                    win32.MB_ICONEXCLAMATION,
                );
                return;
            }
        },
        else => {},
    }

    const game_state: *anyopaque = switch (builtin.mode) {
        .debug => app_state.debug_game.game_api.init(engine_state) orelse {
            _ = win32.MessageBoxA(
                null,
                "Failed to initialize game",
                "Error",
                win32.MB_ICONEXCLAMATION,
            );
            return;
        },
        else => game.init(engine_state),
    };

    running = true;

    var frame_timestamp = std.Io.Clock.awake.now(io);
    const s_per_ns: f32 = 1.0 / @as(f32, std.time.ns_per_s);

    var dll_timestamp = frame_timestamp;

    while (running) {
        const frame_start = std.Io.Clock.awake.now(io);
        defer {
            if (running and !platform_state.quit_requested) {
                fr.paceFrame(io, frame_start, common.frame_duration) catch {
                    running = false;
                };
            }
        }

        defer transient_fixed_buffer.reset();

        engine_state.input.update();
        if (!pumpMessages(&platform_state)) {
            running = false;
            break;
        }
        engine_state.sound.update();

        // The pump can spend an arbitrary amount of time in native window tracking.
        const now = std.Io.Clock.awake.now(io);
        if (platform_state.input_suspended) {
            frame_timestamp = now;
            continue;
        }

        if (platform_state.reset_frame_clock) {
            engine_state.delta_time = 0;
        } else {
            const elapsed = frame_timestamp.durationTo(now);
            const elapsed_ns: f32 = @floatFromInt(elapsed.toNanoseconds());
            engine_state.delta_time = elapsed_ns * s_per_ns;
        }
        platform_state.reset_frame_clock = false;
        frame_timestamp = now;

        running = switch (builtin.mode) {
            .debug => app_state.debug_game.game_api.updateAndRender(engine_state, game_state),
            else => game.updateAndRender(engine_state, game_state),
        };

        // TODO: this should be done in the renderer
        var rect: win32.RECT = undefined;
        _ = win32.GetClientRect(platform_state.window, &rect);
        const window_width = rect.right - rect.left;
        const window_height = rect.bottom - rect.top;

        stretchBlitBits(
            platform_state.device_context,
            0,
            0,
            window_width,
            window_height,
            0,
            0,
            engine_state.renderer.back_buffer.width,
            engine_state.renderer.back_buffer.height,
            engine_state.renderer.back_buffer.data.ptr,
            &buffer_info,
            platform_state.fullscreen,
        );

        const input = &engine_state.input;
        const control = input.isKeyDown(.lcontrol) or input.isKeyDown(.rcontrol) or
            input.keyPressedThisFrame(.lcontrol) or input.keyPressedThisFrame(.rcontrol);
        if (engine_state.input.keyPressedThisFrame(.@"3") and !control) {
            DBG_show_cursor = !DBG_show_cursor;
        }

        // @HACK:
        // @TODO: We need allow the game to decide when it wants to toggle full screen
        if (input.isKeyDown(.lalt) and input.keyPressedThisFrame(.enter)) {
            std.log.info("Toggle fullscreen", .{});
            platform_state.toggleFullscreen();
        }

        // TODO: Reload library every X seconds instead of on every frame
        // TODO: Build in a fail-safe stub functions for when the reload fails so the game can still
        // run
        // without crashing and we can try to recover.
        switch (builtin.mode) {
            .debug => {
                // Replace this with rdtsc maybe? Since this is for internal builds only
                if (dll_timestamp.durationTo(now).toNanoseconds() > std.time.ns_per_s / 30) {
                    dll_timestamp = now;
                    _ = reloadLibrary(io, &app_state.debug_game) catch |err| {
                        std.log.err(
                            "Failed to reload dynamic game library: {s}",
                            .{@errorName(err)},
                        );
                    };
                }
            },
            else => {},
        }
    }

    switch (builtin.mode) {
        .debug => {
            app_state.debug_game.game_api.deinit(engine_state, game_state);
            _ = win32.FreeLibrary(app_state.debug_game.instance);
        },
        else => game.deinit(engine_state, game_state),
    }

    platform_state.destroyWindow();

    // NOTE: Destroy the sound system after the window is destroyed for some reason there seeems to
    // be an exception thrown
    // when destroying the window after the sound system has been deinitialized. This is probably
    // some intercation with
    // the COM being deinitialized before the window is destroyed?
    // TODO: We need to figure out why this is happening and if this is the intended behavior.
    engine_state.sound.deinit();

    // NOTE: Technically this free is not really needed as the OS will clean up after the
    // application exits.
    // But it is nice to do it anyway.
    allocator.free(game_memory);

    // const alloc_result = debug_allocator.deinit();
    // if (alloc_result != .ok) return error.MemoryLeak;
}

// @TODO: Thsis needs to be moved to the renderer
inline fn stretchBlitBits(
    device_context: windows.HDC,
    dest_x: i32,
    dest_y: i32,
    dest_width: i32,
    dest_height: i32,
    src_x: i32,
    src_y: i32,
    src_width: i32,
    src_height: i32,
    frame_data: [*]const u8,
    frame_buffer_info: *const win32.BITMAPINFO,
    fullscreen: bool,
) void {
    // TODO: We might want to blit to a zone that maintains the aspect ration of the rendered image.
    // NOTE: When we are in full screen mode we want to blit to the entire screen. But
    // when we are in windowed mode we only want to blit to the exact size of the frame buffer.

    const blit_result = if (fullscreen) blk: {
        break :blk win32.StretchDIBits(
            device_context,
            dest_x,
            dest_y,
            dest_width,
            dest_height,
            src_x,
            src_y,
            src_width,
            src_height,
            @ptrCast(frame_data),
            frame_buffer_info,
            @backingInt(win32.DIB_RGB_COLORS),
            @bitCast(win32.SRCCOPY),
        );
    } else blk: {
        const top: i32 = common.windowed_frame_margin;
        const left: i32 = common.windowed_frame_margin;

        _ = win32.PatBlt(device_context, 0, 0, dest_width, top, @bitCast(win32.BLACKNESS));
        _ = win32.PatBlt(device_context, 0, top, left, src_height, @bitCast(win32.BLACKNESS));
        _ = win32.PatBlt(
            device_context,
            0,
            top + src_height,
            dest_width,
            dest_height - top - src_height,
            @bitCast(win32.BLACKNESS),
        );
        _ = win32.PatBlt(
            device_context,
            left + src_width,
            top,
            dest_width - left - src_width,
            src_height,
            @bitCast(win32.BLACKNESS),
        );

        break :blk win32.StretchDIBits(
            device_context,
            top,
            left,
            src_width,
            src_height,
            0,
            0,
            src_width,
            src_height,
            @ptrCast(frame_data),
            frame_buffer_info,
            @backingInt(win32.DIB_RGB_COLORS),
            @bitCast(win32.SRCCOPY),
        );
    };

    if (blit_result == 0) {
        // TODO: Log or return error. But we dont need to stop the program.
    }
}

fn pumpMessages(platform: *Win32Platform) bool {
    if (platform.quit_requested) return false;

    var msg: win32.MSG = undefined;
    for (0..fr.input.InputState.max_events_per_frame) |_| {
        if (!win32.PeekMessageA(&msg, null, 0, 0, win32.PM_REMOVE).toBool()) {
            platform.discard_input_before = null;
            break;
        }
        if (platform.quit_requested or msg.message == win32.WM_QUIT) return false;

        // Ignore input left queued by a native move/resize loop. MSG.time and
        // GetTickCount share a wrapping millisecond clock; compare the difference.
        const stale = if (platform.discard_input_before) |cutoff|
            @as(i32, @bitCast(msg.time -% cutoff)) <= 0
        else
            false;
        const accept_input = msg.hwnd == platform.window and platform.focused and
            !platform.input_suspended and !stale;

        switch (msg.message) {
            win32.WM_KEYDOWN,
            win32.WM_SYSKEYDOWN,
            win32.WM_KEYUP,
            win32.WM_SYSKEYUP,
            => {
                if (accept_input) {
                    const key_code: usize = @bitCast(msg.wParam);
                    if (key_code > std.math.maxInt(u8)) continue;
                    var key: Key = @fromBackingInt(@as(u8, @intCast(key_code)));
                    const key_info: win32.KeyMessageLParam = @bitCast(msg.lParam);
                    key = switch (key) {
                        .alt => if (key_info.is_extended) .ralt else .lalt,
                        .control => if (key_info.is_extended) .rcontrol else .lcontrol,
                        .shift => if (key_info.scan_code == .left_shift) .lshift else .rshift,
                        else => key,
                    };

                    const down = msg.message == win32.WM_KEYDOWN or
                        msg.message == win32.WM_SYSKEYDOWN;
                    platform.input.keyEvent(key, down, down and key_info.was_down);
                    continue;
                }
            },
            win32.WM_MOUSEMOVE => {
                if (accept_input) {
                    const position: win32.MousePositionLParam = @bitCast(msg.lParam);
                    platform.input.mouse_position_current = .{ .x = position.x, .y = position.y };
                    continue;
                }
            },
            win32.WM_MOUSEWHEEL => {
                if (accept_input) {
                    const wheel: win32.MouseWheelWParam = @bitCast(msg.wParam);
                    platform.input.wheelEvent(@floatFromInt(wheel.delta));
                    continue;
                }
            },
            win32.WM_LBUTTONDOWN,
            win32.WM_LBUTTONUP,
            win32.WM_RBUTTONDOWN,
            win32.WM_RBUTTONUP,
            win32.WM_MBUTTONDOWN,
            win32.WM_MBUTTONUP,
            win32.WM_XBUTTONDOWN,
            win32.WM_XBUTTONUP,
            => {
                if (accept_input) {
                    const button: ?MouseButton = switch (msg.message) {
                        win32.WM_LBUTTONDOWN, win32.WM_LBUTTONUP => .left,
                        win32.WM_RBUTTONDOWN, win32.WM_RBUTTONUP => .right,
                        win32.WM_MBUTTONDOWN, win32.WM_MBUTTONUP => .middle,
                        else => extra: {
                            const extra_button: win32.XButtonWParam = @bitCast(msg.wParam);
                            break :extra switch (extra_button.button) {
                                .x1 => .x1,
                                .x2 => .x2,
                                else => null,
                            };
                        },
                    };
                    if (button) |mapped| {
                        const down = msg.message == win32.WM_LBUTTONDOWN or
                            msg.message == win32.WM_RBUTTONDOWN or
                            msg.message == win32.WM_MBUTTONDOWN or
                            msg.message == win32.WM_XBUTTONDOWN;
                        platform.input.mouseButtonEvent(mapped, down);
                    }

                    // Capture keeps button releases observable after a drag leaves the window.
                    const any_button_down = std.mem.indexOfScalar(
                        u8,
                        &platform.input.mouse_buttons_ended_down,
                        1,
                    ) != null;
                    if (any_button_down) {
                        if (win32.GetCapture() != platform.window) {
                            _ = win32.SetCapture(platform.window.?);
                        }
                    } else if (win32.GetCapture() == platform.window) {
                        _ = win32.ReleaseCapture();
                    }
                    continue;
                }
            },
            else => {},
        }
        // Native window management remains in windowProc. Game input is only
        // recorded by this pump, never by Windows-owned modal loops.
        _ = win32.DispatchMessageA(&msg);
        if (platform.quit_requested) return false;
    }
    return !platform.quit_requested;
}

fn windowProc(
    window: windows.HWND,
    message: u32,
    w_param: win32.WPARAM,
    l_param: windows.LPARAM,
) callconv(.winapi) win32.LRESULT {
    const user_data: usize = @bitCast(win32.GetWindowLongPtrA(window, win32.GWLP_USERDATA));
    // Creation/teardown callbacks can arrive without an attached platform.
    const platform: *Win32Platform = @as(?*Win32Platform, @ptrFromInt(user_data)) orelse
        return win32.DefWindowProcA(window, message, w_param, l_param);

    switch (message) {
        win32.WM_ENTERSIZEMOVE => {
            platform.input_suspended = true;
            platform.input.releaseAll();
            platform.input.update();
            // Windows owns mouse capture while tracking the window border/title bar.
            return 0;
        },
        win32.WM_EXITSIZEMOVE => {
            platform.input.releaseAll();
            platform.input.update();
            platform.input_suspended = false;
            platform.discard_input_before = win32.GetTickCount();
            platform.reset_frame_clock = true;
            return 0;
        },
        win32.WM_SETFOCUS => platform.focused = true,
        win32.WM_KILLFOCUS, win32.WM_ACTIVATEAPP => {
            if (message == win32.WM_KILLFOCUS or w_param == 0) {
                platform.focused = false;
                platform.input.releaseAll();
                if (win32.GetCapture() == window) _ = win32.ReleaseCapture();
            }
        },
        win32.WM_CAPTURECHANGED => platform.input.releaseMouseButtons(),
        win32.WM_ERASEBKGND => return 1,
        win32.WM_DESTROY, win32.WM_CLOSE => {
            platform.quit_requested = true;
            win32.PostQuitMessage(0);
            return 0;
        },
        win32.WM_NCDESTROY => {
            _ = win32.SetWindowLongPtrA(window, win32.GWLP_USERDATA, 0);
            platform.window = null;
        },
        win32.WM_SETCURSOR => {
            if (DBG_show_cursor) {
                _ = win32.SetCursor(DBG_cursor);
            } else {
                _ = win32.SetCursor(null);
            }
            return 0;
        },
        // TODO: We might not want to resize the back buffer every time the window is resized.
        // We might want the backbuffer to stay at a fixed resolution and just rely on stretchDIBits
        // to scale it.
        // We could figure out a way to keep the aspect ration the same, but that might be tricky.
        // win32.WM_SIZE => {
        // var rect: win32.RECT = undefined;
        // _ = win32.GetClientRect(app_state.window, &rect);
        // app_state.back_buffer.width = @intCast(rect.right - rect.left);
        // app_state.back_buffer.height = @intCast(rect.bottom - rect.top);
        //
        // app_state.back_buffer.info.bmiHeader.biWidth = @intCast(app_state.back_buffer.width);
        // app_state.back_buffer.info.bmiHeader.biHeight = -@as(i32,
        // @intCast(app_state.back_buffer.height));
        //
        // const bytes_per_pixel: usize = 4;
        // const new_bitmap_size: usize = @as(usize, app_state.back_buffer.width) * @as(usize,
        // app_state.back_buffer.height) * bytes_per_pixel;
        // app_state.back_buffer.data = app_state.allocator.realloc(app_state.back_buffer.data,
        // new_bitmap_size) catch unreachable;
        // },

        else => {},
    }

    return win32.DefWindowProcA(window, message, w_param, l_param);
}

fn reloadLibrary(io: std.Io, debug_game: *DebugGame) !bool {
    const stats = try std.Io.Dir.cwd().statFile(io, dll_name, .{});
    if (debug_game.is_loaded and debug_game.time_stamp == stats.mtime.nanoseconds) {
        return false;
    }

    // Keep the current DLL loaded until its replacement and all symbols are ready.
    const next_index = debug_game.temp_index ^ 1;
    const temp_names = [_][:0]const u8{ dll_name ++ "_tmp0", dll_name ++ "_tmp1" };
    const new_name = temp_names[next_index];

    if (!win32.CopyFileA(dll_name.ptr, new_name.ptr, .FALSE).toBool()) {
        return error.FailedToCopyFile;
    }

    const new_instance = win32.LoadLibraryA(new_name.ptr) orelse return error.FailedToLoadLibrary;
    errdefer _ = win32.FreeLibrary(new_instance);

    const init_address = win32.GetProcAddress(new_instance, "init") orelse
        return error.FailedToLookupInitFn;
    const init_fn: DebugGameDLLApi.InitFn = @ptrCast(init_address);
    const deinit_address = win32.GetProcAddress(new_instance, "deinit") orelse
        return error.FailedToLookupDeinitFn;
    const deinit_fn: DebugGameDLLApi.DeinitFn = @ptrCast(deinit_address);
    const update_address = win32.GetProcAddress(new_instance, "updateAndRender") orelse
        return error.FailedToLookupUpdateAndRenderFn;
    const update_and_render: DebugGameDLLApi.UpdateAndRenderFn = @ptrCast(update_address);

    if (debug_game.is_loaded) {
        _ = win32.FreeLibrary(debug_game.instance);
    }

    debug_game.instance = new_instance;
    debug_game.game_api.init = init_fn;
    debug_game.game_api.deinit = deinit_fn;
    debug_game.game_api.updateAndRender = update_and_render;
    debug_game.is_loaded = true;
    debug_game.temp_index = next_index;
    debug_game.time_stamp = stats.mtime.nanoseconds;

    return true;
}
