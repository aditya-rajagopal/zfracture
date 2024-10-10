const windows = std.os.windows;

/// The windows internal state
pub const InternalState = struct {
    /// Handel to the instance of the application
    h_instance: windows.HINSTANCE,
    /// Window handle
    hwnd: ?windows.HWND,
};

pub const TTYError = error{UnableToGetConsoleScreenBuffer};
pub const Error = error{ FailedHandleGet, WndRegistrationFailed };

const window_class_name: [*:0]const u8 = "fracture_window_class";

pub fn init(
    platform_state: *InternalState,
    application_name: [*:0]const u8,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
) Error!void {
    platform_state.h_instance = win32.GetModuleHandleA(null) orelse return Error.FailedHandleGet;

    const icon: ?windows.HICON = win32.LoadIconA(platform_state.h_instance, win32.IDI_APPLICATION);
    var wndclass: win32.WNDCLASSA = std.mem.zeroes(win32.WNDCLASSA);
    wndclass.style = win32.CS_DBLCLKS; // Get double clicks
    wndclass.lpfnWndProc = win32_process_message;
    wndclass.cbClsExtra = 0;
    wndclass.cbWndExtra = 0;
    wndclass.hInstance = platform_state.h_instance;
    wndclass.hIcon = icon;
    wndclass.hCursor = win32.LoadCursorA(null, win32.IDC_ARROW);
    wndclass.hbrBackground = null;
    wndclass.lpszMenuName = null;
    wndclass.lpszClassName = window_class_name; // "fracture_window_class";

    const res = win32.RegisterClassA(&wndclass);
    if (res == 0) {
        _ = win32.MessageBoxA(null, "Windows Registration Failed", "Error", win32.MB_ICONEXCLAMATION);
        return Error.WndRegistrationFailed;
    }

    var window_x: i32 = x;
    var window_y: i32 = y;
    var window_width: i32 = width;
    var window_height: i32 = height;

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

    platform_state.hwnd = win32.CreateWindowExA(
        @bitCast(window_style_ex),
        window_class_name,
        application_name,
        @bitCast(window_style),
        window_x,
        window_y,
        window_width,
        window_height,
        null,
        null,
        platform_state.h_instance,
        null,
    ) orelse {
        _ = win32.MessageBoxA(null, "Windows Registration Failed", "Error", win32.MB_ICONEXCLAMATION);
        return Error.WndRegistrationFailed;
    };

    const show_window_command_flags: u32 = win32.SW_SHOW;
    _ = win32.ShowWindow(platform_state.hwnd, @bitCast(show_window_command_flags));
}

pub fn deinit(platform_state: *InternalState) void {
    if (platform_state.hwnd) |hwnd| {
        _ = win32.DestroyWindow(hwnd);
        platform_state.hwnd = null;
    }
}

pub fn pump_messages(platform_state: *InternalState) void {
    _ = platform_state;
    var msg: win32.MSG = undefined;

    while (win32.PeekMessageA(&msg, null, 0, 0, win32.PM_REMOVE) != 0) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageA(&msg);
    }
}

pub fn get_tty_config(file: std.fs.File) TTYError!std.io.tty.Config {
    var info: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (std.os.windows.kernel32.GetConsoleScreenBufferInfo(file.handle, &info) != std.os.windows.TRUE) {
        return TTYError.UnableToGetConsoleScreenBuffer;
    }
    return std.io.tty.Config{ .windows_api = .{
        .handle = file.handle,
        .reset_attributes = info.wAttributes,
    } };
}

pub fn get_allocator() std.mem.Allocator {
    return std.heap.page_allocator;
}

test init {
    var state: InternalState = undefined;
    try init(&state, "Fracture Engine", 0, 0, 1280, 720);
}

// -------------------------------------- private functions -------------------------------------------/

fn win32_process_message(
    hwnd: windows.HWND,
    msg: u32,
    w_param: windows.WPARAM,
    l_param: windows.LPARAM,
) callconv(windows.WINAPI) windows.LRESULT {
    switch (msg) {
        // Erasing the backgroudn will be handled by the application. Stops flickering
        win32.WM_ERASEBKGND => return 1,
        // TODO: Fire event for application to quit
        win32.WM_CLOSE => return 0,
        win32.WM_DESTROY => {
            win32.PostQuitMessage(0);
            return 0;
        },
        win32.WM_SIZE => {
            var rect: windows.RECT = undefined;
            _ = win32.GetClientRect(hwnd, &rect);
            const width: i32 = rect.right - rect.left;
            const height: i32 = rect.bottom - rect.top;
            _ = width;
            _ = height;
            //TODO: fire resize event
        },
        win32.WM_KEYDOWN,
        win32.WM_SYSKEYDOWN,
        win32.WM_KEYUP,
        win32.WM_SYSKEYUP,
        => {
            const pressed = (msg == win32.WM_KEYDOWN or msg == win32.WM_SYSKEYDOWN);
            _ = pressed;
            //TODO: Input processing
        },
        win32.WM_MOUSEMOVE => {
            const x_pos: isize = l_param & 0xffff;
            const y_pos: isize = (l_param >> 16) & 0xffff;
            _ = x_pos;
            _ = y_pos;
            // TODO: Input processing
        },
        win32.WM_MOUSEWHEEL => {
            var z_delta = (w_param >> 16) & 0xffff;
            if (z_delta != 0) {
                z_delta = if (z_delta < 0) -1 else 1;
            }
            // TODO: Input processing
        },
        win32.WM_LBUTTONDOWN,
        win32.WM_LBUTTONUP,
        win32.WM_RBUTTONUP,
        win32.WM_RBUTTONDOWN,
        win32.WM_MBUTTONUP,
        win32.WM_MBUTTONDOWN,
        => {
            const pressed = (msg == win32.WM_LBUTTONDOWN or msg == win32.WM_RBUTTONDOWN or msg == win32.WM_MBUTTONDOWN);
            _ = pressed;
            // TODO: Input processing
        },
        else => {},
    }
    return win32.DefWindowProcA(hwnd, msg, w_param, l_param);
}

const win32 = @import("win32.zig");
const std = @import("std");
const testing = std.testing;
