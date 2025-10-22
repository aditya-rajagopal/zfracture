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

const AppState = struct {
    window: windows.HWND,
    instance: windows.HINSTANCE,
    device_context: windows.HDC,
    class_name: [*:0]const u8,
    running: bool,
    back_buffer: FrameBuffer,

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
        pumpMessages();

        {
            offset_x += 1;
            offset_y += 1;

            for (0..app_state.back_buffer.height) |y| {
                for (0..app_state.back_buffer.width) |x| {
                    const pixel_start: usize = (y * app_state.back_buffer.width + x) * FrameBuffer.bytes_per_pixel;
                    app_state.back_buffer.data[pixel_start] = @truncate(x + offset_x); // blue
                    app_state.back_buffer.data[pixel_start + 1] = @truncate(y + offset_y); // green
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
    hWnd: windows.HWND,
    uMsg: u32,
    wParam: windows.WPARAM,
    lParam: windows.LPARAM,
) callconv(.winapi) windows.LRESULT {
    var result: windows.LRESULT = 0;

    switch (uMsg) {
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
        else => {
            result = win32.DefWindowProcA(hWnd, uMsg, wParam, lParam);
        },
    }

    return result;
}
