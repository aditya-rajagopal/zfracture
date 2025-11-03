const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;

const engine = @import("fracture");
const EngineState = engine.EngineState;
const MouseButton = engine.MouseButton;
const Key = engine.Key;
const KB = engine.KB;
const MB = engine.MB;
const GB = engine.GB;
const FrameBuffer = engine.FrameBuffer;

const win32 = engine.win32;

const Game = @import("game");
const DebugGame = switch (builtin.mode) {
    .Debug => struct {
        instance: std.DynLib,
        is_loaded: bool = false,
        time_stamp: i128 align(8),
        game_api: engine.DebugGameDLLApi,
    },
    else => void,
};

const Win32PlatformState = struct {
    instance: windows.HINSTANCE,
    window: windows.HWND,
    device_context: windows.HDC,
};

const WindowCreateError = error{
    FailedToCreateWindow,
    FailedToGetModuleHandle,
    FailedToRegisterWindowClass,
    FailedToGetDeviceContext,
} || std.mem.Allocator.Error;

pub const AppState = struct {
    engine: EngineState,
    debug_game: DebugGame,
};

const game_api_default = engine.DebugGameDLLApi{
    .init = Game.init,
    .deinit = Game.deinit,
    .updateAndRender = Game.updateAndRender,
};

const dll_name = "./zig-out/bin/dynamic_game.dll";

// LEFTOFF(adi): Implement WAV file loading and decoding. Complete audio system
// TODO(adi): We currently have 2 arenas. One is for permanent allocations which is the static lifetime arena.
// The ther is the transient arena which has the lifetime of a frame. We probably want more arenas with potentially
// different lifetimes such as a scene or game level arena. It is possible the renderer will need to allocate stuff
// when it is performing the rendering pass. We could also have fixed size arena pools for each thread/task that can be
// requested when one is run out.
pub fn main() void {
    // Platform specific state
    var platform_state: Win32PlatformState = undefined;
    var running: bool = false;

    // TODO(adi): What do we do about the back buffer? This is a renderer specific thing
    var buffer_info: win32.BITMAPINFO = undefined;

    // TODO(adi): We need to figure out if I want to use the debug allocator since we are using fixed buffer arenas
    const allocator = std.heap.page_allocator;

    // NOTE(adi): We want to gaurantee that the game can run in a fixed amount of memory. We can bump this up
    // dpeneding on if we ever see us running out of memory.
    const permanenent_memory_size = MB(128);
    const transient_memory_size = MB(128);
    const total_game_memory_size = permanenent_memory_size + transient_memory_size;

    // TODO(adi): We may need more arenas depending on how the game goes.
    const game_memory: []u8 = allocator.alloc(u8, total_game_memory_size) catch {
        _ = win32.MessageBoxA(null, "Failed to allocate game memory", "Error", win32.MB_ICONEXCLAMATION);
        return;
    };

    var permanent_fixed_buffer = std.heap.FixedBufferAllocator.init(game_memory[0..permanenent_memory_size]);
    const permanent_allocator = permanent_fixed_buffer.allocator();

    var transient_fixed_buffer = std.heap.FixedBufferAllocator.init(game_memory[permanenent_memory_size .. permanenent_memory_size + transient_memory_size]);
    const transient_allocator = transient_fixed_buffer.allocator();

    const app_state: *AppState = permanent_allocator.create(AppState) catch {
        _ = win32.MessageBoxA(null, "Failed to allocate engine state", "Error", win32.MB_ICONEXCLAMATION);
        return;
    };

    // TODO(adi): Figure out why the engine pointer does not showup in raddebugger when allocated directly vs
    // making a new type AppState and then allocating it.
    const engine_state: *EngineState = &app_state.engine;

    engine_state.sound.init() catch |err| {
        var buffer: [1024]u8 = undefined;
        const msg = std.fmt.bufPrintZ(&buffer, "Failed to initialize sound system: {s}", .{@errorName(err)}) catch unreachable;
        _ = win32.MessageBoxA(null, msg.ptr, "Error", win32.MB_ICONEXCLAMATION);
        return;
    };

    engine_state.permanent_allocator = permanent_allocator;
    engine_state.transient_allocator = transient_allocator;
    engine_state.input = .init;

    // NOTE(adi): We allocate a large enough back buffer such that we do not need to reallocate it. If the window
    // size becomes larger than this we will just throw an error and disallow it. Especially if we are rendering to a
    // smaller back buffer and stretching it to fit the window.
    // TODO(adi): We need to make this configurable globally by the game.
    // TODO(adi): We might lower this if we want a smaller memory footprint
    const max_window_width = 4096;
    const max_window_height = 2048;
    const window_buffer_max_size = max_window_width * max_window_height * FrameBuffer.bytes_per_pixel;

    engine_state.back_buffer.width = 1280;
    engine_state.back_buffer.height = 720;
    engine_state.back_buffer.data = permanent_allocator.alloc(u8, window_buffer_max_size) catch {
        _ = win32.MessageBoxA(null, "Out of memory for back buffer allocation", "Error", win32.MB_ICONEXCLAMATION);
        return;
    };

    buffer_info = .{
        .bmiHeader = .{
            .biSize = @sizeOf(win32.BITMAPINFOHEADER),
            .biWidth = @intCast(engine_state.back_buffer.width),
            .biHeight = -@as(i32, @intCast(engine_state.back_buffer.height)),
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
    platform_state = createWindow(
        "Testbed",
        engine_state.back_buffer.width,
        engine_state.back_buffer.height,
    ) catch |err| {
        var buffer: [1024]u8 = undefined;
        const msg = std.fmt.bufPrintZ(&buffer, "Failed to initialize window: {s}", .{@errorName(err)}) catch unreachable;
        _ = win32.MessageBoxA(null, msg.ptr, "Error", win32.MB_ICONEXCLAMATION);
        return;
    };

    showWindow(platform_state.window);

    switch (builtin.mode) {
        .Debug => {
            app_state.debug_game.is_loaded = false;
            app_state.debug_game.time_stamp = 0;
            if (!(reload_library(&app_state.debug_game) catch |err| {
                var buffer: [1024]u8 = undefined;
                const msg = std.fmt.bufPrintZ(&buffer, "Failed to reload dynamic game library: {s}", .{@errorName(err)}) catch unreachable;
                _ = win32.MessageBoxA(null, msg.ptr, "Error", win32.MB_ICONEXCLAMATION);
                return;
            })) {
                _ = win32.MessageBoxA(null, "Failed to reload dynamic game library", "Error", win32.MB_ICONEXCLAMATION);
                return;
            }
        },
        else => {},
    }

    const game_state: *anyopaque = switch (builtin.mode) {
        .Debug => app_state.debug_game.game_api.init(engine_state),
        else => Game.init(engine_state),
    };

    running = true;

    while (running) {
        engine_state.input.update();

        running = pumpMessages(engine_state);

        running &= switch (builtin.mode) {
            .Debug => app_state.debug_game.game_api.updateAndRender(engine_state, game_state),
            else => Game.updateAndRender(engine_state, game_state),
        };

        // TODO(adi): this should be done in the renderer
        var rect: windows.RECT = undefined;
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
            engine_state.back_buffer.width,
            engine_state.back_buffer.height,
            engine_state.back_buffer.data.ptr,
            &buffer_info,
        );

        transient_fixed_buffer.reset();

        // TODO(adi): Reload library every X seconds instead of on every frame
        // TODO(adi): Build in a fail-safe stub functions for when the reload fails so the game can still run
        // without crashing and we can try to recover.
        switch (builtin.mode) {
            .Debug => {
                _ = reload_library(&app_state.debug_game) catch |err| {
                    std.log.err("Failed to reload dynamic game library: {s}", .{@errorName(err)});
                };
            },
            else => {},
        }
    }

    switch (builtin.mode) {
        .Debug => {
            app_state.debug_game.game_api.deinit(engine_state, game_state);
            app_state.debug_game.instance.close();
        },
        else => Game.deinit(engine_state, game_state),
    }

    // Destroy the window
    destroyWindow(platform_state.window);

    // NOTE(adi): Destroy the sound system after the window is destroyed for some reason there seeems to be an exception thrown
    // when destroying the window after the sound system has been deinitialized. This is probably some intercation with
    // the COM being deinitialized before the window is destroyed?
    // TODO(adi): We need to figure out why this is happening and if this is the intended behavior.
    engine_state.sound.deinit();

    // NOTE(adi): Technically this free is not really needed as the OS will clean up after the application exits.
    // But it is nice to do it anyway.
    allocator.free(game_memory);

    // const alloc_result = debug_allocator.deinit();
    // if (alloc_result != .ok) return error.MemoryLeak;
}

fn createWindow(
    window_title: [*:0]const u8,
    window_width: i32,
    window_height: i32,
) WindowCreateError!Win32PlatformState {
    const engine_name: [*:0]const u8 = "zfracture";
    var platform_state: Win32PlatformState = undefined;

    platform_state.instance = win32.GetModuleHandleA(null) orelse return error.FailedToGetModuleHandle;

    var window_class: win32.WNDCLASSA = .zero;
    window_class.style = .{ .OWNDC = 1 };
    window_class.lpfnWndProc = windowProc;
    window_class.hInstance = platform_state.instance;
    window_class.lpszClassName = engine_name;

    const result = win32.RegisterClassA(&window_class);
    if (result == 0) {
        _ = win32.MessageBoxA(null, "Windows Registration Failed", "Error", win32.MB_ICONEXCLAMATION);
        return error.FailedToRegisterWindowClass;
    }

    var window_x: i32 = 0;
    var window_y: i32 = 0;
    var window_final_width: i32 = window_width;
    var window_final_height: i32 = window_height;

    var window_style: u32 = win32.WS_SYSMENU | win32.WS_CAPTION | win32.WS_OVERLAPPED;
    const window_style_ex: u32 = win32.WS_EX_APPWINDOW;

    window_style |= win32.WS_MINIMIZEBOX;
    window_style |= win32.WS_MAXIMIZEBOX;
    window_style |= win32.WS_THICKFRAME;

    var border_rect: windows.RECT = std.mem.zeroes(windows.RECT);
    _ = win32.AdjustWindowRectEx(&border_rect, @bitCast(window_style), 0, @bitCast(window_style_ex));

    window_x += border_rect.left;
    window_y += border_rect.right;

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
        _ = win32.MessageBoxA(null, "Windows Creation Failed", "Error", win32.MB_ICONEXCLAMATION);
        return error.FailedToCreateWindow;
    };
    errdefer _ = win32.DestroyWindow(platform_state.window);

    platform_state.device_context = win32.GetDC(platform_state.window) orelse return error.FailedToGetDeviceContext;

    return platform_state;
}

fn destroyWindow(window: windows.HWND) void {
    _ = win32.DestroyWindow(window);
}

fn showWindow(window: windows.HWND) void {
    const show_window_command_flags: u32 = win32.SW_SHOW;
    _ = win32.ShowWindow(window, @bitCast(show_window_command_flags));
}

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
) void {
    // TODO(adi): We might want to blit to a zone that maintains the aspect ration of the rendered image.
    const blit_result = win32.StretchDIBits(
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
        @intFromEnum(win32.DIB_RGB_COLORS),
        @bitCast(win32.SRCCOPY),
    );

    if (blit_result == 0) {
        // TODO(adi): Log or return error. But we dont need to stop the program.
    }
}

fn pumpMessages(eng: *EngineState) bool {
    var msg: win32.MSG = undefined;
    while (win32.PeekMessageA(&msg, null, 0, 0, win32.PM_REMOVE) != 0) {
        const lparam: usize = @bitCast(msg.lParam);
        const wparam: usize = @bitCast(msg.wParam);
        switch (msg.message) {
            win32.WM_QUIT => {
                return false;
            },
            win32.WM_MOUSEMOVE => {
                eng.input.mouse_position_current.x = @truncate(msg.lParam & 0xffff);
                eng.input.mouse_position_current.y = @truncate(msg.lParam >> 16);
            },
            win32.WM_MOUSEWHEEL => {
                // TODO: Do we want to parse the rest of the message? l_param has the mouse position
                // https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-mousehwheel
                const z_delta: i16 = @bitCast(@as(u16, @truncate(wparam >> 16)));
                // NOTE(adi): We are compressing the delta into just 1 direction.
                const delta: i8 = if (z_delta < 0) -1 else 1;
                // TODO(adi): We are only storing the last delta. Could we do better?
                eng.input.mouse_wheel_delta = delta;
            },
            win32.WM_LBUTTONDOWN => {
                eng.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.left)] = 1;
                eng.input.mouse_buttons_half_transition_count[@intFromEnum(MouseButton.left)] += 1;
            },
            win32.WM_LBUTTONUP => {
                eng.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.left)] = 0;
                eng.input.mouse_buttons_half_transition_count[@intFromEnum(MouseButton.left)] += 1;
            },
            win32.WM_RBUTTONDOWN => {
                eng.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.right)] = 1;
                eng.input.mouse_buttons_half_transition_count[@intFromEnum(MouseButton.right)] += 1;
            },
            win32.WM_RBUTTONUP => {
                eng.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.right)] = 0;
                eng.input.mouse_buttons_half_transition_count[@intFromEnum(MouseButton.right)] += 1;
            },
            win32.WM_MBUTTONDOWN => {
                eng.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.middle)] = 1;
                eng.input.mouse_buttons_half_transition_count[@intFromEnum(MouseButton.middle)] += 1;
            },
            win32.WM_MBUTTONUP => {
                eng.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.middle)] = 0;
                eng.input.mouse_buttons_half_transition_count[@intFromEnum(MouseButton.middle)] += 1;
            },
            win32.WM_XBUTTONDOWN => {
                if (wparam & 0x100000000 != 0) {
                    eng.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.x1)] = 1;
                    eng.input.mouse_buttons_half_transition_count[@intFromEnum(MouseButton.x1)] += 1;
                } else {
                    eng.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.x2)] = 1;
                    eng.input.mouse_buttons_half_transition_count[@intFromEnum(MouseButton.x2)] += 1;
                }
            },
            win32.WM_XBUTTONUP => {
                if (wparam & 0x100000000 != 0) {
                    eng.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.x1)] = 0;
                    eng.input.mouse_buttons_half_transition_count[@intFromEnum(MouseButton.x1)] += 1;
                } else {
                    eng.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.x2)] = 0;
                    eng.input.mouse_buttons_half_transition_count[@intFromEnum(MouseButton.x2)] += 1;
                }
            },
            win32.WM_KEYDOWN,
            win32.WM_SYSKEYDOWN,
            => {
                var key: Key = @enumFromInt(wparam);

                const is_extended: bool = lparam & 0x01000000 != 0;

                switch (key) {
                    .alt => key = if (is_extended) .ralt else .lalt,
                    .control => key = if (is_extended) .rcontrol else .lcontrol,
                    .shift => {
                        // NOTE(adi): This scan code is defined by windows for left shift.
                        // https://learn.microsoft.com/en-us/windows/win32/inputdev/about-keyboard-input#keystroke-message-flags
                        const left_shift: u8 = 0x2A;
                        const scan_code: u8 = @truncate(lparam >> 16);
                        key = if (scan_code == left_shift) .lshift else .rshift;
                    },
                    else => {},
                }

                const key_code: u8 = @intFromEnum(key);

                // NOTE(adi): For (sys)KeyDown messages this bit is set to 1 if the key was down before this message and 0 if it was up.
                // this means for key down messages we need to check if this is 0 for transition count and 1 if it is sysUp message
                const is_half_transition: u8 = @intFromBool(lparam & 0x40000000 == 0);
                eng.input.keys_half_transition_count[key_code] += is_half_transition;
                eng.input.keys_ended_down[key_code] = 1;
            },
            win32.WM_KEYUP,
            win32.WM_SYSKEYUP,
            => {
                var key: Key = @enumFromInt(wparam);

                const is_extended: bool = lparam & 0x01000000 != 0;

                switch (key) {
                    .alt => key = if (is_extended) .ralt else .lalt,
                    .control => key = if (is_extended) .rcontrol else .lcontrol,
                    .shift => {
                        // NOTE(adi): This scan code is defined by windows for left shift.
                        // https://learn.microsoft.com/en-us/windows/win32/inputdev/about-keyboard-input#keystroke-message-flags
                        const left_shift: u8 = 0x2A;
                        const scan_code: u8 = @truncate(lparam >> 16);
                        key = if (scan_code == left_shift) .lshift else .rshift;
                    },
                    else => {},
                }

                const key_code: u8 = @intFromEnum(key);

                // NOTE(adi): The 30th bit is always 1 for (sys)KeyUp messages. Since we only get up messages from the down state.
                // this message always means a transition
                eng.input.keys_half_transition_count[key_code] += 1;
                eng.input.keys_ended_down[key_code] = 0;
            },
            win32.WM_SIZE => {
                // We have handled the resize event here.
                // TODO(adi): Check if we get resize events when not parsing the message queue.
                std.log.info("WM_SIZE", .{});
            },
            else => {
                _ = win32.TranslateMessage(&msg);
                _ = win32.DispatchMessageA(&msg);
            },
        }
    }
    return true;
}

fn windowProc(
    window: windows.HWND,
    message: u32,
    w_param: windows.WPARAM,
    l_param: windows.LPARAM,
) callconv(.winapi) windows.LRESULT {
    var result: windows.LRESULT = 0;

    switch (message) {
        win32.WM_ERASEBKGND => result = 1,
        win32.WM_DESTROY => {
            _ = win32.PostQuitMessage(0);
        },
        win32.WM_CLOSE => {
            _ = win32.PostQuitMessage(0);
        },
        // TODO(adi): We might not want to resize the back buffer every time the window is resized.
        // We might want the backbuffer to stay at a fixed resolution and just rely on stretchDIBits to scale it.
        // We could figure out a way to keep the aspect ration the same, but that might be tricky.
        // win32.WM_SIZE => {
        // var rect: windows.RECT = undefined;
        // _ = win32.GetClientRect(app_state.window, &rect);
        // app_state.back_buffer.width = @intCast(rect.right - rect.left);
        // app_state.back_buffer.height = @intCast(rect.bottom - rect.top);
        //
        // app_state.back_buffer.info.bmiHeader.biWidth = @intCast(app_state.back_buffer.width);
        // app_state.back_buffer.info.bmiHeader.biHeight = -@as(i32, @intCast(app_state.back_buffer.height));
        //
        // const bytes_per_pixel: usize = 4;
        // const new_bitmap_size: usize = @as(usize, app_state.back_buffer.width) * @as(usize, app_state.back_buffer.height) * bytes_per_pixel;
        // app_state.back_buffer.data = app_state.allocator.realloc(app_state.back_buffer.data, new_bitmap_size) catch unreachable;
        // },

        // TODO(adi): When we lose focus we should reset the input state so that the game does not react to input in anyway
        // win32.WM_KILLFOCUS => {},
        // win32.WM_SETFOCUS => {},
        else => {
            result = win32.DefWindowProcA(window, message, w_param, l_param);
        },
    }

    return result;
}

fn reload_library(debug_game: *DebugGame) !bool {
    const cwd = std.fs.cwd();
    const file: std.fs.File = cwd.openFile(dll_name, .{}) catch {
        return error.FailedToOpenFile;
    };
    const stats = try file.stat();
    file.close();
    if (debug_game.time_stamp == stats.mtime) {
        return false;
    }

    const new_name = dll_name ++ "_tmp";

    // TODO(adi): Is this better than using CopyFileA?
    // try cwd.copyFile(dll_name, cwd, new_name, .{});
    if (debug_game.is_loaded) {
        debug_game.instance.close();
    }

    if (win32.CopyFileA(dll_name.ptr, new_name.ptr, 0) == 0) {
        return error.FailedToCopyFile;
    }

    var new_instance = std.DynLib.open(new_name) catch return false;
    errdefer new_instance.close();
    const init_fn = new_instance.lookup(engine.DebugGameDLLApi.InitFn, "init") orelse return error.FailedToLookupInitFn;
    const deinit_fn = new_instance.lookup(engine.DebugGameDLLApi.DeinitFn, "deinit") orelse return error.FailedToLookupDeinitFn;
    const update_and_render = new_instance.lookup(
        engine.DebugGameDLLApi.UpdateAndRenderFn,
        "updateAndRender",
    ) orelse return error.FailedToLookupUpdateAndRenderFn;

    debug_game.instance = new_instance;
    debug_game.game_api.init = init_fn;
    debug_game.game_api.deinit = deinit_fn;
    debug_game.game_api.updateAndRender = update_and_render;
    debug_game.is_loaded = true;
    debug_game.time_stamp = stats.mtime;

    return true;
}
