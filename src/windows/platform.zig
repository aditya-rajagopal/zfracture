const std = @import("std");
const windows = std.os.windows;
const Platform = @import("../platform.zig");
const Renderer = @import("../software_renderer.zig");
const win32 = @import("win32.zig");
const event_types = @import("../event.zig");
const Key = event_types.Key;
const Event = event_types.Event;
const MouseButton = event_types.MouseButton;
const max_messages_per_frame = 4096;

pub const State = struct {
    instance: windows.HINSTANCE = undefined,
    window: ?windows.HWND = null,
    device_context: windows.HDC = undefined,
    window_placement: win32.WINDOWPLACEMENT = undefined,
    fullscreen: bool = false,
    event_storage: [2][1024]Event = undefined,
    event_lists: [2]std.ArrayList(Event) = undefined,
    pending_event_buffer: u1 = 0,
    focused: bool = false,
    quit_requested: bool = false,
    modal_depth: u32 = 0,
    client_mouse_buttons: u8 = 0,
    owns_mouse_capture: bool = false,
    reset_frame_clock: bool = false,

    back_buffer: *Renderer.FrameBuffer = undefined,

    buffer_info: win32.BITMAPINFO = undefined,
    windowed_frame_margin: u16 = 10,
    cursor: ?windows.HCURSOR = null,
    cursor_hidden: bool = true,

    const Self = @This();

    pub fn init(self: *Self) InitError!void {
        self.* = .{};
        self.cursor = win32.LoadCursorA(null, win32.IDC_ARROW) orelse return error.FailedToLoadCursor;
    }
    pub fn deinit(_: *Self) void {}
    pub fn beginFrame(_: *Self) void {}
    pub fn endFrame(_: *Self) void {}

    pub fn pollEvents(self: *Self) Platform.WindowStatus {
        pumpMessages(self);
        return self.takeWindowStatus();
    }

    fn takeWindowStatus(self: *Self) Platform.WindowStatus {
        const active = self.modal_depth != 0;
        var ended = false;
        if (!active) {
            ended = self.reset_frame_clock;
            self.reset_frame_clock = false;
        }
        return .{
            .quit_requested = self.quit_requested,
            .native_interaction_active = active,
            .interaction_ended = ended,
        };
    }

    pub fn setCursorHidden(self: *Self, hidden: bool) void {
        self.cursor_hidden = hidden;
    }

    pub fn present(self: *Self) void {
        // Presentation dimensions must match the cached top-down bitmap header.
        const buffer = self.back_buffer;
        std.debug.assert(@as(i32, buffer.width) == self.buffer_info.bmiHeader.biWidth);
        std.debug.assert(-@as(i32, buffer.height) == self.buffer_info.bmiHeader.biHeight);
        const required_bytes = @as(usize, buffer.width) * buffer.height * Renderer.bytes_per_pixel;
        std.debug.assert(buffer.data.len >= required_bytes);

        var rect: win32.RECT = undefined;
        if (!win32.GetClientRect(self.window, &rect).toBool()) return;
        stretchBlitBits(self.device_context, 0, 0, rect.right - rect.left, rect.bottom - rect.top, 0, 0, self.back_buffer.width, self.back_buffer.height, self.back_buffer.data.ptr, &self.buffer_info, self.fullscreen, self.windowed_frame_margin);
    }

    // The slice stays immutable until the next handoff. Native callbacks append to the other list.
    pub fn takeEvents(self: *Self) []const Event {
        const ready = self.pending_event_buffer;
        const next = ready ^ 1;
        self.event_lists[next].clearRetainingCapacity();
        self.pending_event_buffer = next;
        return self.event_lists[ready].items;
    }

    // Initialize in place: GWLP_USERDATA retains this address until destruction.
    pub fn createWindow(platform_state: *State, config: Platform.WindowConfig) CreateWindowError!void {
        const window_title = config.title.ptr;
        const window_width = @as(i32, config.frame_buffer.width) + 2 * @as(i32, config.windowed_frame_margin);
        const window_height = @as(i32, config.frame_buffer.height) + 2 * @as(i32, config.windowed_frame_margin);
        platform_state.back_buffer = config.frame_buffer;
        platform_state.windowed_frame_margin = config.windowed_frame_margin;
        platform_state.buffer_info = std.mem.zeroes(win32.BITMAPINFO);
        platform_state.buffer_info.bmiHeader = .{
            .biSize = @sizeOf(win32.BITMAPINFOHEADER),
            .biWidth = config.frame_buffer.width,
            .biHeight = -@as(i32, config.frame_buffer.height),
            .biPlanes = 1,
            .biBitCount = 32,
            .biCompression = win32.BI_RGB,
            .biSizeImage = 0,
            .biXPelsPerMeter = 0,
            .biYPelsPerMeter = 0,
            .biClrUsed = 0,
            .biClrImportant = 0,
        };
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
        if (result == 0 and windows.GetLastError() != .CLASS_ALREADY_EXISTS) {
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
        errdefer {
            _ = win32.SetWindowLongPtrA(platform_state.window.?, win32.GWLP_USERDATA, 0);
            _ = win32.DestroyWindow(platform_state.window);
            platform_state.window = null;
        }

        platform_state.device_context = win32.GetDC(platform_state.window) orelse
            return error.FailedToGetDeviceContext;
        errdefer _ = win32.ReleaseDC(platform_state.window, platform_state.device_context);
        platform_state.window_placement.length = @sizeOf(win32.WINDOWPLACEMENT);
        platform_state.fullscreen = false;
        platform_state.focused = false;
        platform_state.quit_requested = false;
        platform_state.modal_depth = 0;
        platform_state.client_mouse_buttons = 0;
        platform_state.owns_mouse_capture = false;
        platform_state.pending_event_buffer = 0;
        for (&platform_state.event_lists, &platform_state.event_storage) |*list, *storage| {
            list.* = std.ArrayList(Event).initBuffer(storage);
        }
        platform_state.reset_frame_clock = false;

        // Creation callbacks see null user data until the platform is ready.
        const user_data: isize = @bitCast(@intFromPtr(platform_state));
        _ = win32.SetWindowLongPtrA(platform_state.window.?, win32.GWLP_USERDATA, user_data);
        // A zero return can mean success or failure; verify the stored pointer.
        if (win32.GetWindowLongPtrA(platform_state.window.?, win32.GWLP_USERDATA) != user_data) {
            return error.FailedToSetWindowUserData;
        }
    }

    pub fn destroyWindow(self: *State) void {
        const window = self.window orelse return;
        _ = win32.SetWindowLongPtrA(window, win32.GWLP_USERDATA, 0);
        _ = win32.ReleaseDC(window, self.device_context);
        self.window = null;
        _ = win32.DestroyWindow(window);
    }

    pub fn showWindow(self: *State) void {
        const show_window_command_flags: u32 = win32.SW_SHOW;
        _ = win32.ShowWindow(self.window, @bitCast(show_window_command_flags));
    }

    pub fn toggleFullscreen(self: *Self) void {
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

pub const CreateWindowError = error{
    FailedToCreateWindow,
    FailedToGetModuleHandle,
    FailedToRegisterWindowClass,
    FailedToGetDeviceContext,
    FailedToSetWindowUserData,
};

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
    margin: u16,
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
        const top: i32 = margin;
        const left: i32 = margin;

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

fn pumpMessages(platform: *State) void {
    if (platform.quit_requested) return;
    var msg: win32.MSG = undefined;
    for (0..max_messages_per_frame) |_| {
        if (!win32.PeekMessageA(&msg, null, 0, 0, win32.PM_REMOVE).toBool()) break;
        if (platform.quit_requested) return;
        if (msg.message == win32.WM_QUIT) {
            platform.quit_requested = true;
            return;
        }
        _ = win32.DispatchMessageA(&msg);
        if (platform.quit_requested) return;
    }
}

fn windowProc(
    window: windows.HWND,
    message: u32,
    w_param: win32.WPARAM,
    l_param: windows.LPARAM,
) callconv(.winapi) win32.LRESULT {
    const user_data: usize = @bitCast(win32.GetWindowLongPtrA(window, win32.GWLP_USERDATA));
    // Creation/teardown callbacks can arrive without an attached platform.
    const platform: *State = @as(?*State, @ptrFromInt(user_data)) orelse
        return win32.DefWindowProcA(window, message, w_param, l_param);

    switch (message) {
        win32.WM_ENTERSIZEMOVE, win32.WM_ENTERMENULOOP => {
            if (platform.modal_depth == 0) {
                platform.event_lists[platform.pending_event_buffer].appendBounded(.reset_keyboard) catch
                    @panic("event buffer overflow");
            }
            platform.modal_depth = std.math.add(u32, platform.modal_depth, 1) catch
                @panic("native modal nesting overflow");
            return 0;
        },
        win32.WM_EXITSIZEMOVE, win32.WM_EXITMENULOOP => {
            if (platform.modal_depth != 0) platform.modal_depth -= 1;
            if (platform.modal_depth == 0) platform.reset_frame_clock = true;
            return 0;
        },
        win32.WM_SETFOCUS => platform.focused = true,
        win32.WM_KILLFOCUS, win32.WM_ACTIVATEAPP => {
            const lost_focus = message == win32.WM_KILLFOCUS or w_param == 0;
            if (lost_focus) {
                if (platform.focused) {
                    platform.focused = false;
                    platform.event_lists[platform.pending_event_buffer].appendBounded(.reset_all) catch
                        @panic("event buffer overflow");
                }
                platform.client_mouse_buttons = 0;
                // Clear ownership before ReleaseCapture reenters this procedure.
                platform.owns_mouse_capture = false;
                if (win32.GetCapture() == window) _ = win32.ReleaseCapture();
            }
        },
        win32.WM_CAPTURECHANGED => {
            if (platform.owns_mouse_capture) {
                platform.owns_mouse_capture = false;
                platform.client_mouse_buttons = 0;
                platform.event_lists[platform.pending_event_buffer].appendBounded(.reset_mouse) catch
                    @panic("event buffer overflow");
            }
        },
        win32.WM_KEYDOWN, win32.WM_SYSKEYDOWN, win32.WM_KEYUP, win32.WM_SYSKEYUP => {
            if (platform.focused) {
                if (w_param <= std.math.maxInt(u8)) {
                    var key: Key = @fromBackingInt(@as(u8, @intCast(w_param)));
                    const info: win32.KeyMessageLParam = @bitCast(l_param);
                    key = switch (key) {
                        .alt => if (info.is_extended) .ralt else .lalt,
                        .control => if (info.is_extended) .rcontrol else .lcontrol,
                        .shift => if (info.scan_code == .left_shift) .lshift else .rshift,
                        else => key,
                    };
                    const down = message == win32.WM_KEYDOWN or message == win32.WM_SYSKEYDOWN;
                    const translated: Event = if (!down)
                        .{ .key_released = key }
                    else if (info.was_down)
                        .{ .key_repeat = key }
                    else
                        .{ .key_pressed = key };
                    platform.event_lists[platform.pending_event_buffer].appendBounded(translated) catch
                        @panic("event buffer overflow");
                    return 0;
                }
            }
        },
        win32.WM_MOUSEMOVE => {
            if (platform.focused) {
                const position: win32.MousePositionLParam = @bitCast(l_param);
                platform.event_lists[platform.pending_event_buffer].appendBounded(.{
                    .mouse_move = .{ .x = position.x, .y = position.y },
                }) catch @panic("event buffer overflow");
                return 0;
            }
        },
        win32.WM_MOUSEWHEEL => {
            if (platform.focused) {
                const wheel: win32.MouseWheelWParam = @bitCast(w_param);
                if (wheel.delta != 0) {
                    const position: win32.MousePositionLParam = @bitCast(l_param);
                    var client: win32.POINT = .{ .x = position.x, .y = position.y };
                    if (win32.ScreenToClient(window, &client).toBool()) {
                        platform.event_lists[platform.pending_event_buffer].appendBounded(.{
                            .mouse_scroll = .{
                                .value = if (wheel.delta > 0) 1 else -1,
                                .mouse_pos = .{
                                    .x = @intCast(std.math.clamp(client.x, std.math.minInt(i16), std.math.maxInt(i16))),
                                    .y = @intCast(std.math.clamp(client.y, std.math.minInt(i16), std.math.maxInt(i16))),
                                },
                            },
                        }) catch @panic("event buffer overflow");
                    }
                }
                return 0;
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
            if (platform.focused) {
                const button: ?MouseButton = switch (message) {
                    win32.WM_LBUTTONDOWN, win32.WM_LBUTTONUP => .left,
                    win32.WM_RBUTTONDOWN, win32.WM_RBUTTONUP => .right,
                    win32.WM_MBUTTONDOWN, win32.WM_MBUTTONUP => .middle,
                    else => extra: {
                        const extra_button: win32.XButtonWParam = @bitCast(w_param);
                        break :extra switch (extra_button.button) {
                            .x1 => .x1,
                            .x2 => .x2,
                            else => null,
                        };
                    },
                };
                if (button) |mapped| {
                    const down = message == win32.WM_LBUTTONDOWN or message == win32.WM_RBUTTONDOWN or
                        message == win32.WM_MBUTTONDOWN or message == win32.WM_XBUTTONDOWN;
                    const position: win32.MousePositionLParam = @bitCast(l_param);
                    const payload: Event.MouseButtonEvent = .{
                        .button = mapped,
                        .pos = .{ .x = position.x, .y = position.y },
                    };
                    const translated: Event = if (down) .{ .mouse_pressed = payload } else .{ .mouse_released = payload };
                    platform.event_lists[platform.pending_event_buffer].appendBounded(translated) catch
                        @panic("event buffer overflow");
                    const mask = @as(u8, 1) << @as(u3, @intCast(@backingInt(mapped)));

                    // NOTE(adi): Tracking the clicks if they start inside the window and continueing to do so even if
                    // it is dragged outside the window till it is released.
                    if (down) {
                        platform.client_mouse_buttons |= mask;
                        if (win32.GetCapture() != window) {
                            _ = win32.SetCapture(window);
                        }
                        platform.owns_mouse_capture = win32.GetCapture() == window;
                    } else {
                        platform.client_mouse_buttons &= ~mask;
                        if (platform.client_mouse_buttons == 0) {
                            platform.owns_mouse_capture = false;
                            if (win32.GetCapture() == window) _ = win32.ReleaseCapture();
                        }
                    }
                    if (message == win32.WM_XBUTTONDOWN or message == win32.WM_XBUTTONUP) return 1;
                    return 0;
                }
            }
        },
        win32.WM_ERASEBKGND => return 1,
        win32.WM_DESTROY, win32.WM_CLOSE => {
            // The application decides whether to exit or create another window.
            platform.quit_requested = true;
            return 0;
        },
        win32.WM_NCDESTROY => {
            _ = win32.SetWindowLongPtrA(window, win32.GWLP_USERDATA, 0);
            platform.window = null;
        },
        win32.WM_SETCURSOR => {
            if (!platform.cursor_hidden) {
                _ = win32.SetCursor(platform.cursor);
            } else {
                _ = win32.SetCursor(null);
            }
            return 0;
        },
        else => {},
    }

    return win32.DefWindowProcA(window, message, w_param, l_param);
}

const TestWindow = struct {
    platform: State,
    buffer: Renderer.FrameBuffer,
    pixels: [320 * 180 * 4]u8 align(4096),

    fn init(self: *TestWindow) !void {
        self.buffer = .{ .width = 320, .height = 180, .data = &self.pixels };
        try self.platform.init();
        errdefer self.platform.deinit();
        try self.platform.createWindow(.{ .title = "Fracture event test", .frame_buffer = &self.buffer });
        self.platform.focused = true;
    }

    fn deinit(self: *TestWindow) void {
        defer self.platform.deinit();
        self.platform.destroyWindow();
        var message: win32.MSG = undefined;
        for (0..max_messages_per_frame) |_| {
            if (!win32.PeekMessageA(&message, null, 0, 0, win32.PM_REMOVE).toBool()) break;
        }
    }
};

test "WndProc records outside the pump exactly once" {
    var fixture: TestWindow = undefined;
    try fixture.init();
    defer fixture.deinit();
    const platform = &fixture.platform;
    const window = platform.window.?;
    _ = windowProc(window, win32.WM_KEYDOWN, @backingInt(Key.space), 0);
    const first = platform.takeEvents();
    _ = windowProc(window, win32.WM_KEYUP, @backingInt(Key.space), 0);
    try std.testing.expectEqualDeep(&[_]Event{.{ .key_pressed = .space }}, first);
    try std.testing.expectEqualDeep(&[_]Event{.{ .key_released = .space }}, platform.takeEvents());
    try std.testing.expectEqual(@as(usize, 0), platform.takeEvents().len);
}

test "closing a window does not quit a recreated window" {
    var fixture: TestWindow = undefined;
    try fixture.init();
    defer fixture.deinit();
    const platform = &fixture.platform;
    _ = windowProc(platform.window.?, win32.WM_CLOSE, 0, 0);
    try std.testing.expect(platform.pollEvents().quit_requested);
    platform.destroyWindow();
    try platform.createWindow(.{ .title = "Recreated window", .frame_buffer = &fixture.buffer });
    try std.testing.expect(!platform.pollEvents().quit_requested);
    // A real thread quit still stops this window and remains latched.
    win32.PostQuitMessage(0);
    try std.testing.expect(platform.pollEvents().quit_requested);
    try std.testing.expect(platform.pollEvents().quit_requested);
}

test "nested modal callbacks reset once and resume only after the outer exit" {
    var fixture: TestWindow = undefined;
    try fixture.init();
    defer fixture.deinit();
    const platform = &fixture.platform;
    const window = platform.window.?;
    // Injected callbacks test our nesting policy, not OS input delivery in a modal loop.
    _ = windowProc(window, win32.WM_ENTERSIZEMOVE, 0, 0);
    _ = windowProc(window, win32.WM_ENTERMENULOOP, 0, 0);
    _ = windowProc(window, win32.WM_KEYDOWN, @backingInt(Key.f1), 0);
    _ = windowProc(window, win32.WM_EXITMENULOOP, 0, 0);
    const nested = platform.takeWindowStatus();
    try std.testing.expect(nested.native_interaction_active);
    try std.testing.expect(!nested.interaction_ended);
    _ = windowProc(window, win32.WM_EXITSIZEMOVE, 0, 0);
    try std.testing.expectEqualDeep(&[_]Event{ .reset_keyboard, .{ .key_pressed = .f1 } }, platform.takeEvents());
    // Do not consume the prior end while another native interaction is active.
    _ = windowProc(window, win32.WM_ENTERSIZEMOVE, 0, 0);
    const active = platform.takeWindowStatus();
    try std.testing.expect(active.native_interaction_active);
    try std.testing.expect(!active.interaction_ended);
    _ = windowProc(window, win32.WM_EXITSIZEMOVE, 0, 0);
    const ended = platform.takeWindowStatus();
    try std.testing.expect(!ended.native_interaction_active);
    try std.testing.expect(ended.interaction_ended);
    try std.testing.expect(!platform.takeWindowStatus().interaction_ended);
}

test "focus loss emits one reset_all" {
    var fixture: TestWindow = undefined;
    try fixture.init();
    defer fixture.deinit();
    const platform = &fixture.platform;
    const window = platform.window.?;
    _ = windowProc(window, win32.WM_KILLFOCUS, 0, 0);
    _ = windowProc(window, win32.WM_ACTIVATEAPP, 0, 0);
    try std.testing.expectEqualDeep(&[_]Event{.reset_all}, platform.takeEvents());
    _ = windowProc(window, win32.WM_SETFOCUS, 0, 0);
    _ = windowProc(window, win32.WM_KILLFOCUS, 0, 0);
    try std.testing.expectEqualDeep(&[_]Event{.reset_all}, platform.takeEvents());
}

test "capture release distinguishes completion from cancellation" {
    var fixture: TestWindow = undefined;
    try fixture.init();
    defer fixture.deinit();
    const platform = &fixture.platform;
    const window = platform.window.?;
    _ = windowProc(window, win32.WM_LBUTTONDOWN, 0, 0);
    _ = windowProc(window, win32.WM_RBUTTONDOWN, 0, 0);
    _ = platform.takeEvents();
    _ = windowProc(window, win32.WM_LBUTTONUP, 0, 0);
    try std.testing.expectEqual(window, win32.GetCapture().?);
    _ = windowProc(window, win32.WM_RBUTTONUP, 0, 0);
    try std.testing.expect(win32.GetCapture() != window);
    const released = platform.takeEvents();
    try std.testing.expectEqual(@as(usize, 2), released.len);
    try std.testing.expectEqual(MouseButton.left, released[0].mouse_released.button);
    try std.testing.expectEqual(MouseButton.right, released[1].mouse_released.button);
    _ = windowProc(window, win32.WM_LBUTTONDOWN, 0, 0);
    _ = platform.takeEvents();
    _ = win32.ReleaseCapture(); // Simulates unexpected loss while a client button is still held.
    try std.testing.expectEqualDeep(&[_]Event{.reset_mouse}, platform.takeEvents());
    _ = windowProc(window, win32.WM_CAPTURECHANGED, 0, 0);
    try std.testing.expectEqual(@as(usize, 0), platform.takeEvents().len);
    _ = windowProc(window, win32.WM_LBUTTONDOWN, 0, 0);
    _ = platform.takeEvents();
    _ = windowProc(window, win32.WM_KILLFOCUS, 0, 0);
    try std.testing.expectEqualDeep(&[_]Event{.reset_all}, platform.takeEvents());
}

pub const InitError = error{FailedToLoadCursor};
pub fn processId() u32 {
    return std.os.windows.GetCurrentProcessId();
}

pub const DynamicLibrary = struct {
    handle: windows.HINSTANCE,
    pub fn open(path: [:0]const u8) error{FailedToLoadLibrary}!DynamicLibrary {
        var path_buffer: [windows.PATH_MAX_WIDE + 1]u16 = undefined;
        const wide_path = try libraryPathW(&path_buffer, path);
        const handle = win32.LoadLibraryW(wide_path.ptr) orelse return error.FailedToLoadLibrary;
        return .{ .handle = handle };
    }
    pub fn lookup(self: *DynamicLibrary, comptime T: type, name: [:0]const u8) ?T {
        const address = win32.GetProcAddress(self.handle, name.ptr) orelse return null;
        return @ptrCast(address);
    }
    pub fn close(self: *DynamicLibrary) void {
        _ = win32.FreeLibrary(self.handle);
        self.* = undefined;
    }
};

// Windows file APIs use WTF-8 at the Zig boundary and UTF-16 at the OS boundary.
fn libraryPathW(buffer: []u16, path: [:0]const u8) error{FailedToLoadLibrary}![:0]u16 {
    const length = std.unicode.calcWtf16LeLen(path) catch return error.FailedToLoadLibrary;
    if (length >= buffer.len) return error.FailedToLoadLibrary;
    const written = std.unicode.wtf8ToWtf16Le(buffer[0..length], path) catch return error.FailedToLoadLibrary;
    std.debug.assert(written == length);
    buffer[length] = 0;
    return buffer[0..length :0];
}

test "Windows library paths preserve Unicode and bound UTF-16 storage" {
    var buffer: [64]u16 = undefined;
    const path = try libraryPathW(&buffer, "C:\\d\xc3\xa9v\\\xf0\x9f\x8e\xae.dll");
    const expected = [_]u16{ 'C', ':', '\\', 'd', 0xe9, 'v', '\\', 0xd83c, 0xdfae, '.', 'd', 'l', 'l' };
    try std.testing.expectEqualSlices(u16, &expected, path);
    try std.testing.expectEqual(@as(u16, 0), path.ptr[path.len]);
    const surrogate = try libraryPathW(&buffer, "\xed\xa0\x80");
    try std.testing.expectEqualSlices(u16, &.{0xd800}, surrogate);
    var exact: [2]u16 = undefined;
    try std.testing.expectEqualSlices(u16, &.{0xe9}, try libraryPathW(&exact, "\xc3\xa9"));
    try std.testing.expectError(error.FailedToLoadLibrary, libraryPathW(exact[0..1], "\xc3\xa9"));
    try std.testing.expectError(error.FailedToLoadLibrary, libraryPathW(&buffer, "\xff"));
}
