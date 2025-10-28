const std = @import("std");
const windows = std.os.windows;
const win32 = @import("win32.zig");

const FrameBuffer = struct {
    // TODO(adi): We might want to make the back buffer resolution independent of the window resolution.
    width: u16,
    height: u16,
    data: []u8,
    info: win32.BITMAPINFO,

    pub const bytes_per_pixel: usize = 4;
};

/// Enumeration of the keyboard keys and mouse buttons. The values are the same as the values in the windows API
///
/// Platforms other than windows will have to map the platform specific values to the Key enum values.
pub const Key = enum(u8) {
    mouse_left = 0x00,
    mouse_right = 0x01,
    mouse_middle = 0x02,
    mouse_x1 = 0x03,
    mouse_x2 = 0x04,

    backspace = 0x08,

    tab = 0x09,
    enter = 0x0d,
    shift = 0x10,
    control = 0x11,
    alt = 0x12,
    pause = 0x13,
    caps = 0x14,

    kana_hangul_mode = 0x15,
    ime_on = 0x16,
    junja = 0x17,
    ime_final = 0x18,
    kanji_hanja_mode = 0x19,
    ime_off = 0x1a,

    escape = 0x1b,

    convert = 0x1c,
    nonconvert = 0x1d,
    accept = 0x1e,
    modechange = 0x1f,

    space = 0x20,
    pageup = 0x21,
    pagedown = 0x22,
    end = 0x23,
    home = 0x24,

    left = 0x25,
    up = 0x26,
    right = 0x27,
    down = 0x28,

    select = 0x29,
    print = 0x2a,
    execute = 0x2b,

    printscreen = 0x2c,

    insert = 0x2d,

    delete = 0x2e,
    help = 0x2f,

    @"0" = 0x30,
    @"1" = 0x31,
    @"2" = 0x32,
    @"3" = 0x33,
    @"4" = 0x34,
    @"5" = 0x35,
    @"6" = 0x36,
    @"7" = 0x37,
    @"8" = 0x38,
    @"9" = 0x39,

    a = 0x41,
    b = 0x42,
    c = 0x43,
    d = 0x44,
    e = 0x45,
    f = 0x46,
    g = 0x47,
    h = 0x48,
    i = 0x49,
    j = 0x4a,
    k = 0x4b,
    l = 0x4c,
    m = 0x4d,
    n = 0x4e,
    o = 0x4f,
    p = 0x50,
    q = 0x51,
    r = 0x52,
    s = 0x53,
    t = 0x54,
    u = 0x55,
    v = 0x56,
    w = 0x57,
    x = 0x58,
    y = 0x59,
    z = 0x5a,

    lsuper = 0x5b,
    rsuper = 0x5c,

    apps = 0x5d,

    /// put computer to sleep
    sleep = 0x5f,

    numpad0 = 0x60,
    numpad1 = 0x61,
    numpad2 = 0x62,
    numpad3 = 0x63,
    numpad4 = 0x64,
    numpad5 = 0x65,
    numpad6 = 0x66,
    numpad7 = 0x67,
    numpad8 = 0x68,
    numpad9 = 0x69,

    multiply = 0x6a,
    add = 0x6b,
    separator = 0x6c,
    subtract = 0x6d,
    decimal = 0x6e,
    divide = 0x6f,

    f1 = 0x70,
    f2 = 0x71,
    f3 = 0x72,
    f4 = 0x73,
    f5 = 0x74,
    f6 = 0x75,
    f7 = 0x76,
    f8 = 0x77,
    f9 = 0x78,
    f10 = 0x79,
    f11 = 0x7a,
    f12 = 0x7b,
    f13 = 0x7c,
    f14 = 0x7d,
    f15 = 0x7e,
    f16 = 0x7f,
    f17 = 0x80,
    f18 = 0x81,
    f19 = 0x82,
    f20 = 0x83,
    f21 = 0x84,
    f22 = 0x85,
    f23 = 0x86,
    f24 = 0x87,

    numlock = 0x90,
    scroll = 0x91,
    numpad_equal = 0x92,

    lshift = 0xa0,
    rshift = 0xa1,
    lcontrol = 0xa2,
    rcontrol = 0xa3,
    lalt = 0xa4,
    ralt = 0xa5,

    browser_back = 0xa6,
    browser_forward = 0xa7,
    browser_refresh = 0xa8,
    browser_stop = 0xa9,
    browser_search = 0xaa,
    browser_favourites = 0xab,
    browser_home = 0xac,

    volume_mute = 0xad,
    volume_down = 0xae,
    volume_up = 0xaf,

    media_next_track = 0xb0,
    media_prev_track = 0xb1,
    media_stop = 0xb2,
    media_play_pause = 0xb3,

    launch_app1 = 0xb6,
    launch_app2 = 0xb7,

    semicolon = 0x3b,
    colon = 0xba,
    equal = 0xbb,
    comma = 0xbc,
    minus = 0xbd,
    period = 0xbe,
    slash = 0xbf,

    grave = 0xc0,
    lbracket = 0xdb,
    backslash = 0xdc,
    rbracket = 0xdd,
    apostrophe = 0xde,

    ime_process = 0xe5,
};

/// TODO(adi): Figure out how to include more than 2 extra mouse buttons.
pub const MouseButton = enum(u8) {
    left = 0x00,
    right = 0x01,
    middle = 0x02,
    x1 = 0x03,
    x2 = 0x04,
};

// TODO(adi): Do we want to track the half transitions?
// We could use that to determine if the button is pressed and released within the same frame.
const InputState = struct {
    keys_ended_down: [NumKeys]u8,
    keys_half_transition_count: [NumKeys]u8,
    mouse_buttons_ended_down: [NumMouseButtons]u8,
    mouse_buttons_half_transition_count: [NumMouseButtons]u8,
    mouse_position_current: MousePosition,
    mouse_position_previous: MousePosition,
    mouse_wheel_delta: i8,

    pub const MousePosition = struct { x: i16, y: i16 };
    pub const NumKeys = 256;
    pub const NumMouseButtons = 5;

    pub const init = std.mem.zeroes(InputState);

    pub inline fn update(self: *InputState) void {
        self.mouse_position_previous = self.mouse_position_current;
        self.keys_half_transition_count = @splat(0);
        self.mouse_buttons_half_transition_count = @splat(0);
    }

    pub inline fn isKeyDown(self: *const InputState, key: Key) bool {
        return self.keys_ended_down[@intFromEnum(key)] != 0;
    }

    pub inline fn isMouseButtonDown(self: *const InputState, button: MouseButton) bool {
        return self.mouse_buttons_ended_down[@intFromEnum(button)] != 0;
    }

    pub inline fn isKeyUp(self: *const InputState, key: Key) bool {
        return self.keys_ended_down[@intFromEnum(key)] == 0;
    }

    pub inline fn isMouseButtonUp(self: *const InputState, button: MouseButton) bool {
        return self.mouse_buttons_ended_down[@intFromEnum(button)] == 0;
    }

    pub inline fn keyPressedThisFrame(self: *const InputState, key: Key) bool {
        // NOTE(adi): a key was pressed this frame if it ended down but started up i.e the transition count is odd and it ended down.
        // or it started down and ended down but the transition count is even.
        // This effectively means that if the key ended down and there was any transition it was pressed this frame.
        // TODO(adi): Should we consider button was pressed this frame if any point in the frame the button was down?
        // For example, if the button was down at the start of the frame and somewhere in the middle of the frame
        // the button was released, should we consider the button as pressed?
        // FIX(adi): This is not correct. We need to check if the key ended down as well
        return self.keys_ended_down[@intFromEnum(key)] != 0 and self.keys_half_transition_count[@intFromEnum(key)] >= 1;
    }

    pub inline fn mouseButtonPressedThisFrame(self: *const InputState, button: MouseButton) bool {
        return self.mouse_buttons_ended_down[@intFromEnum(button)] != 0 or self.mouse_buttons_half_transition_count[@intFromEnum(button)] >= 1;
    }

    pub inline fn keyReleasedThisFrame(self: *const InputState, key: Key) bool {
        // NOTE(adi): a key was released within a frame if it ended up and it had more than 1 transitions.
        return self.keys_ended_down[@intFromEnum(key)] == 0 and self.keys_half_transition_count[@intFromEnum(key)] >= 1;
    }

    pub inline fn mouseButtonReleasedThisFrame(self: *const InputState, button: MouseButton) bool {
        return self.mouse_buttons_ended_down[@intFromEnum(button)] == 0 and self.mouse_buttons_half_transition_count[@intFromEnum(button)] >= 1;
    }
};

const AppState = struct {
    window: windows.HWND,
    instance: windows.HINSTANCE,
    device_context: windows.HDC,
    class_name: [*:0]const u8,
    running: bool,
    back_buffer: FrameBuffer,
    input: InputState,

    allocator: std.mem.Allocator,
};

var app_state: AppState = undefined;

fn createWindow(allocator: std.mem.Allocator) !void {
    app_state.class_name = "zfracture";
    app_state.instance = win32.GetModuleHandleA(null) orelse return error.FailedToGetModuleHandle;

    var window_class: win32.WNDCLASSA = .zero;
    window_class.style = .{ .OWNDC = 1 };
    window_class.lpfnWndProc = windowProc;
    window_class.hInstance = app_state.instance;
    window_class.lpszClassName = app_state.class_name;

    const result = win32.RegisterClassA(&window_class);
    if (result == 0) {
        _ = win32.MessageBoxA(null, "Windows Registration Failed", "Error", win32.MB_ICONEXCLAMATION);
        return error.FailedToRegisterWindowClass;
    }

    app_state.back_buffer.width = 1280;
    app_state.back_buffer.height = 720;

    app_state.input = .init;

    const bitmap_size: usize = @as(usize, app_state.back_buffer.width) * @as(usize, app_state.back_buffer.height) * FrameBuffer.bytes_per_pixel;
    app_state.back_buffer.data = try allocator.alloc(u8, bitmap_size);

    var window_x: i32 = 0;
    var window_y: i32 = 0;
    var window_width: i32 = app_state.back_buffer.width;
    var window_height: i32 = app_state.back_buffer.height;

    var window_style: u32 = win32.WS_SYSMENU | win32.WS_CAPTION | win32.WS_OVERLAPPED;
    const window_style_ex: u32 = win32.WS_EX_APPWINDOW;

    window_style |= win32.WS_MINIMIZEBOX;
    window_style |= win32.WS_MAXIMIZEBOX;
    window_style |= win32.WS_THICKFRAME;

    var border_rect: windows.RECT = std.mem.zeroes(windows.RECT);
    _ = win32.AdjustWindowRectEx(&border_rect, @bitCast(window_style), 0, @bitCast(window_style_ex));

    window_x += border_rect.left;
    window_y += border_rect.right;

    window_width += border_rect.right - border_rect.left;
    window_height += border_rect.bottom - border_rect.top;

    app_state.window = win32.CreateWindowExA(
        @bitCast(window_style_ex),
        app_state.class_name,
        "Game",
        @bitCast(window_style),
        window_x,
        window_y,
        window_width,
        window_height,
        null,
        null,
        app_state.instance,
        null,
    ) orelse {
        _ = win32.MessageBoxA(null, "Windows Creation Failed", "Error", win32.MB_ICONEXCLAMATION);
        return error.FailedToCreateWindow;
    };

    app_state.device_context = win32.GetDC(app_state.window) orelse return error.FailedToGetDeviceContext;
}

fn destroyWindow() void {
    _ = win32.DestroyWindow(app_state.window);
}

fn showWindow() void {
    const show_window_command_flags: u32 = win32.SW_SHOW;
    _ = win32.ShowWindow(app_state.window, @bitCast(show_window_command_flags));
}

fn pumpMessages() void {
    var msg: win32.MSG = undefined;
    while (win32.PeekMessageA(&msg, null, 0, 0, win32.PM_REMOVE) != 0) {
        if (msg.message == win32.WM_QUIT) {
            app_state.running = false;
        }
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageA(&msg);
    }
}

pub fn main() anyerror!void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};

    const allocator = debug_allocator.allocator();
    app_state.allocator = allocator;

    try createWindow(allocator);

    showWindow();

    var offset_x: usize = 0;
    var offset_y: usize = 0;

    app_state.back_buffer.info = .{
        .bmiHeader = .{
            .biSize = @sizeOf(win32.BITMAPINFOHEADER),
            .biWidth = @intCast(app_state.back_buffer.width),
            .biHeight = -@as(i32, @intCast(app_state.back_buffer.height)),
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

    app_state.running = true;
    while (app_state.running) {
        app_state.input.update();

        pumpMessages();

        {
            if (app_state.input.isKeyDown(.escape)) {
                app_state.running = false;
            }
            if (app_state.input.isMouseButtonDown(.left)) {
                std.log.info(
                    "Mouse button pressed at {d}, {d}",
                    .{ app_state.input.mouse_position_current.x, app_state.input.mouse_position_current.y },
                );
            }

            if (app_state.input.isKeyDown(.a)) {
                offset_x +%= 1;
            }
            if (app_state.input.isKeyDown(.d)) {
                offset_x -%= 1;
            }
            if (app_state.input.isKeyDown(.w)) {
                offset_y +%= 1;
            }
            if (app_state.input.isKeyDown(.s)) {
                offset_y -%= 1;
            }

            if (app_state.input.keyPressedThisFrame(.a)) {
                std.log.info("Key a pressed this frame", .{});
            }
            if (app_state.input.keyReleasedThisFrame(.a)) {
                std.log.info("Key a released this frame", .{});
            }

            for (0..app_state.back_buffer.height) |y| {
                for (0..app_state.back_buffer.width) |x| {
                    const pixel_start: usize = (y * app_state.back_buffer.width + x) * FrameBuffer.bytes_per_pixel;
                    app_state.back_buffer.data[pixel_start] = @truncate(x +% offset_x); // blue
                    app_state.back_buffer.data[pixel_start + 1] = @truncate(y +% offset_y); // green
                    app_state.back_buffer.data[pixel_start + 2] = 0x00; // red
                    app_state.back_buffer.data[pixel_start + 3] = 0x00; // padding
                }
            }
        }

        var rect: windows.RECT = undefined;
        _ = win32.GetClientRect(app_state.window, &rect);

        const window_width = rect.right - rect.left;
        const window_height = rect.bottom - rect.top;

        // TODO(adi): We might want to blit to a zone that maintains the aspect ration of the rendered image.
        const blit_result = win32.StretchDIBits(
            app_state.device_context,
            0,
            0,
            window_width,
            window_height,
            0,
            0,
            app_state.back_buffer.width,
            app_state.back_buffer.height,
            @ptrCast(app_state.back_buffer.data.ptr),
            &app_state.back_buffer.info,
            @intFromEnum(win32.DIB_RGB_COLORS),
            @bitCast(win32.SRCCOPY),
        );

        if (blit_result == 0) {
            // TODO(adi): Log error. But we dont need to stop the program.
        }
    }

    // Destroy the window
    destroyWindow();

    allocator.free(app_state.back_buffer.data);

    const alloc_result = debug_allocator.deinit();
    if (alloc_result != .ok) return error.MemoryLeak;
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
        win32.WM_SIZE => {
            // TODO(adi): We might not want to resize the back buffer every time the window is resized.
            // We might want the backbuffer to stay at a fixed resolution and just rely on stretchDIBits to scale it.
            // We could figure out a way to keep the aspect ration the same, but that might be tricky.
            var rect: windows.RECT = undefined;
            _ = win32.GetClientRect(app_state.window, &rect);
            app_state.back_buffer.width = @intCast(rect.right - rect.left);
            app_state.back_buffer.height = @intCast(rect.bottom - rect.top);

            app_state.back_buffer.info.bmiHeader.biWidth = @intCast(app_state.back_buffer.width);
            app_state.back_buffer.info.bmiHeader.biHeight = -@as(i32, @intCast(app_state.back_buffer.height));

            const bytes_per_pixel: usize = 4;
            const new_bitmap_size: usize = @as(usize, app_state.back_buffer.width) * @as(usize, app_state.back_buffer.height) * bytes_per_pixel;
            app_state.back_buffer.data = app_state.allocator.realloc(app_state.back_buffer.data, new_bitmap_size) catch unreachable;
        },
        // TODO(adi): When we lose focus we should reset the input state so that the game does not react to input in anyway
        // win32.WM_KILLFOCUS => {},
        // win32.WM_SETFOCUS => {},
        win32.WM_MOUSEMOVE => {
            app_state.input.mouse_position_current.x = @truncate(l_param & 0xffff);
            app_state.input.mouse_position_current.y = @truncate(l_param >> 16);
        },
        win32.WM_MOUSEWHEEL => {
            // TODO: Do we want to parse the rest of the message? l_param has the mouse position
            // https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-mousehwheel
            const z_delta: i16 = @bitCast(@as(u16, @truncate(w_param >> 16)));
            // NOTE(adi): We are compressing the delta into just 1 direction.
            const delta: i8 = if (z_delta < 0) -1 else 1;
            // TODO(adi): We are only storing the last delta. Could we do better?
            app_state.input.mouse_wheel_delta = delta;
        },
        win32.WM_LBUTTONDOWN => {
            app_state.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.left)] = 1;
        },
        win32.WM_LBUTTONUP => {
            app_state.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.left)] = 0;
        },
        win32.WM_RBUTTONDOWN => {
            app_state.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.right)] = 1;
        },
        win32.WM_RBUTTONUP => {
            app_state.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.right)] = 0;
        },
        win32.WM_MBUTTONDOWN => {
            app_state.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.middle)] = 1;
        },
        win32.WM_MBUTTONUP => {
            app_state.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.middle)] = 0;
        },
        win32.WM_XBUTTONDOWN => {
            if (w_param & 0x100000000 != 0) {
                app_state.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.x1)] = 1;
            } else {
                app_state.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.x2)] = 1;
            }
        },
        win32.WM_XBUTTONUP => {
            if (w_param & 0x100000000 != 0) {
                app_state.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.x1)] = 0;
            } else {
                app_state.input.mouse_buttons_ended_down[@intFromEnum(MouseButton.x2)] = 0;
            }
        },
        win32.WM_KEYDOWN,
        win32.WM_SYSKEYDOWN,
        => {
            var key: Key = @enumFromInt(w_param);

            const lparam: usize = @bitCast(l_param);
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
            app_state.input.keys_half_transition_count[key_code] += is_half_transition;
            app_state.input.keys_ended_down[key_code] = 1;
        },
        win32.WM_KEYUP,
        win32.WM_SYSKEYUP,
        => {
            var key: Key = @enumFromInt(w_param);

            const lparam: usize = @bitCast(l_param);
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
            app_state.input.keys_half_transition_count[key_code] += 1;
            app_state.input.keys_ended_down[key_code] = 0;
        },

        else => {
            result = win32.DefWindowProcA(window, message, w_param, l_param);
        },
    }

    return result;
}
