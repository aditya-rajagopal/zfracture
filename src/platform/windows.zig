const core = @import("fr_core");
const windows = std.os.windows;
const Application = @import("../application.zig");

/// The windows internal state
pub const InternalState = struct {
    /// Handel to the instance of the application
    h_instance: windows.HINSTANCE,
    /// Window handle
    hwnd: ?windows.HWND,
};

pub const LibraryHandle = windows.HINSTANCE;

pub const Error = error{ FailedHandleGet, WndRegistrationFailed };

const window_class_name: [*:0]const u8 = "fracture_window_class";

var application_state: *Application = undefined;

pub fn init(
    app_state: *Application,
    platform_state: *InternalState,
    application_name: [*:0]const u8,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
) Error!void {
    application_state = app_state;
    platform_state.h_instance = win32.GetModuleHandleA(null) orelse return Error.FailedHandleGet;

    const icon: ?windows.HICON = win32.LoadIconA(platform_state.h_instance, win32.IDI_APPLICATION);
    var wndclass: win32.WNDCLASSA = std.mem.zeroes(win32.WNDCLASSA);
    wndclass.style = win32.WNDCLASS_STYLES{}; //win32.CS_DBLCLKS; // Get double clicks
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

pub fn load_library(name: [:0]const u8) ?LibraryHandle {
    const instance = win32.LoadLibraryA(name);
    return instance;
}

pub fn copy_file(name: [:0]const u8, new_name: [:0]const u8, overwrite: bool) bool {
    const result = win32.CopyFileA(name.ptr, new_name.ptr, @intFromBool(!overwrite));
    return result != 0;
}

pub fn library_lookup(handle: LibraryHandle, func_name: [:0]const u8, comptime T: type) ?T {
    if (win32.GetProcAddress(handle, func_name.ptr)) |f| {
        return @as(T, @ptrCast(@alignCast(f)));
    } else {
        return null;
    }
}

pub fn free_library(handle: LibraryHandle) bool {
    const result = win32.FreeLibrary(handle);
    return result != 0;
}

pub fn get_allocator() std.mem.Allocator {
    return std.heap.page_allocator;
}

// -------------------------------------- private functions -------------------------------------------/

fn win32_process_message(
    hwnd: windows.HWND,
    msg: u32,
    w_param: windows.WPARAM,
    l_param: windows.LPARAM,
) callconv(std.builtin.CallingConvention.winapi) windows.LRESULT {
    switch (msg) {
        // Erasing the backgroudn will be handled by the application. Stops flickering
        win32.WM_ERASEBKGND => return 1,
        win32.WM_CLOSE => {
            Application.on_event(application_state, .APPLICATION_QUIT, std.mem.zeroes([16]u8));
            return 0;
        },
        win32.WM_DESTROY => {
            win32.PostQuitMessage(0);
            return 0;
        },
        win32.WM_SIZE => {
            var rect: windows.RECT = undefined;
            _ = win32.GetClientRect(hwnd, &rect);
            const width: i32 = rect.right - rect.left;
            const height: i32 = rect.bottom - rect.top;
            const data: core.Event.WindowResizeEventData = .{
                .size = .{ .width = @intCast(width), .height = @intCast(height) },
            };
            application_state.on_event(.WINDOW_RESIZE, @bitCast(data));
            return 0;
        },
        win32.WM_KEYUP,
        win32.WM_SYSKEYUP,
        => {
            var key: core.Input.Key = @enumFromInt(w_param);
            const lparam: usize = @bitCast(l_param);
            const is_extended = @as(u32, @truncate(lparam)) & 0x01000000 != 0;

            switch (key) {
                .ALT => {
                    key = if (is_extended) .RALT else .LALT;
                },
                .SHIFT => {
                    key = @enumFromInt(win32.MapVirtualKeyA(@as(u8, @truncate(lparam >> 16)), win32.MAPVK_VSC_TO_VK_EX));
                },
                .CONTROL => {
                    key = if (is_extended) .RCONTROL else .LCONTROL;
                },
                else => {},
            }

            application_state.engine.input.process_key_event(&application_state.engine.event, key, 0);
            return 0;
        },
        win32.WM_KEYDOWN,
        win32.WM_SYSKEYDOWN,
        => {
            var key: core.Input.Key = @enumFromInt(w_param);
            const lparam: u32 = @truncate(@as(usize, @bitCast(l_param)));
            const is_extended = lparam & 0x01000000 != 0;

            switch (key) {
                .ALT => {
                    key = if (is_extended) .RALT else .LALT;
                },
                .SHIFT => {
                    key = @enumFromInt(win32.MapVirtualKeyA(@as(u8, @truncate(lparam >> 16)), win32.MAPVK_VSC_TO_VK_EX));
                },
                .CONTROL => {
                    key = if (is_extended) .RCONTROL else .LCONTROL;
                },
                else => {},
            }
            application_state.engine.input.process_key_event(&application_state.engine.event, key, 1);
            return 0;
        },
        win32.WM_MOUSEMOVE => {
            const x_pos: i16 = @truncate(l_param & 0xffff);
            const y_pos: i16 = @truncate((l_param >> 16) & 0xffff);
            application_state.engine.input.process_mouse_move_event(&application_state.engine.event, x_pos, y_pos);
            return 0;
        },
        win32.WM_MOUSEWHEEL => {
            //TODO: Do we want to parse the rest of the message
            const z_delta: i16 = @bitCast(@as(u16, @truncate((w_param >> 16) & 0xffff)));
            if (z_delta != 0) {
                const delta: i8 = if (z_delta < 0) -1 else 1;
                application_state.engine.input.process_mouse_wheel_event(
                    &application_state.engine.event,
                    delta,
                    @truncate(l_param),
                );
            }
        },
        win32.WM_LBUTTONDOWN => {
            const lparam: i32 = @truncate(l_param);
            application_state.engine.input.process_mouse_event(&application_state.engine.event, .LEFT, lparam, 1);
            return 1;
        },
        win32.WM_RBUTTONDOWN => {
            const lparam: i32 = @truncate(l_param);
            application_state.engine.input.process_mouse_event(&application_state.engine.event, .RIGHT, lparam, 1);
            return 1;
        },

        win32.WM_XBUTTONDOWN => {
            const lparam: i32 = @truncate(l_param);
            const x1: core.Input.Button = if (w_param & 0x100000000 != 0) .X1 else .X2;
            application_state.engine.input.process_xmouse_event(&application_state.engine.event, x1, lparam, 1);
            return 1;
        },

        win32.WM_MBUTTONDOWN => {
            const lparam: i32 = @truncate(l_param);
            application_state.engine.input.process_mouse_event(&application_state.engine.event, .MIDDLE, lparam, 1);
            return 1;
        },
        win32.WM_LBUTTONUP => {
            const lparam: i32 = @truncate(l_param);
            application_state.engine.input.process_mouse_event(&application_state.engine.event, .LEFT, lparam, 0);
            return 1;
        },

        win32.WM_RBUTTONUP => {
            const lparam: i32 = @truncate(l_param);
            application_state.engine.input.process_mouse_event(&application_state.engine.event, .RIGHT, lparam, 0);
            return 1;
        },

        win32.WM_MBUTTONUP => {
            const lparam: i32 = @truncate(l_param);
            application_state.engine.input.process_mouse_event(&application_state.engine.event, .MIDDLE, lparam, 0);
            return 1;
        },
        win32.WM_XBUTTONUP => {
            const lparam: i32 = @truncate(l_param);
            const x1: core.Input.Button = if (w_param & 0x100000000 != 0) .X1 else .X2;
            application_state.engine.input.process_xmouse_event(&application_state.engine.event, x1, lparam, 0);
            return 1;
        },

        else => {},
    }
    return win32.DefWindowProcA(hwnd, msg, w_param, l_param);
}

const win32 = @import("win32.zig");
const std = @import("std");
const testing = std.testing;
