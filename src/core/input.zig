// TODO:
//      - [ ] Think of using a bit set for the keys instead of an array
//      - [ ] Are the comptime versions of the functions necessary
//      - [ ] Remove reference to event system here. The platform/application should handle firing events. Or pass the engine.
const KeysArray = [std.math.maxInt(u8)]u8;
const ButtonsArray = [MAX_BUTTONS]u8;
const MousePosition = struct { x: i16 = 0, y: i16 = 0 };

const Input = @This();

buttons_previous_state: ButtonsArray = std.mem.zeroes(ButtonsArray),
keys_previous_state: KeysArray = std.mem.zeroes(KeysArray),

buttons_current_state: ButtonsArray = std.mem.zeroes(ButtonsArray),
keys_current_state: KeysArray = std.mem.zeroes(KeysArray),

previous_mouse_pos: MousePosition = .{},
current_mouse_pos: MousePosition = .{},

current_mouse_scroll: i8 = 0,

allow_repeats: bool = false,

pub fn init(self: *Input) void {
    self.* = std.mem.zeroes(Input);
    // self.allow_repeats = true;
}

pub fn update(self: *Input) void {
    self.keys_previous_state = self.keys_current_state;
    self.buttons_previous_state = self.buttons_current_state;
    self.previous_mouse_pos = self.current_mouse_pos;
    self.current_mouse_scroll = 0;
}

pub inline fn is_key_down(self: *const Input, key: Key) bool {
    return self.keys_current_state[@intFromEnum(key)] != 0;
}

pub inline fn was_key_down(self: *const Input, key: Key) bool {
    return self.keys_previous_state[@intFromEnum(key)] != 0;
}

pub inline fn is_key_up(self: *const Input, key: Key) bool {
    return self.keys_current_state[@intFromEnum(key)] == 0;
}

pub inline fn was_key_up(self: *const Input, key: Key) bool {
    return self.keys_previous_state[@intFromEnum(key)] == 0;
}

pub inline fn key_pressed_this_frame(self: *const Input, key: Key) bool {
    return self.keys_current_state[@intFromEnum(key)] != 0 and self.keys_previous_state[@intFromEnum(key)] == 0;
}

pub inline fn key_released_this_frame(self: *const Input, key: Key) bool {
    return self.keys_current_state[@intFromEnum(key)] == 0 and self.keys_previous_state[@intFromEnum(key)] != 0;
}

pub inline fn is_button_down(self: *const Input, button: Button) bool {
    return self.buttons_current_state[@intFromEnum(button)] != 0;
}

pub inline fn was_button_down(self: *const Input, button: Button) bool {
    return self.buttons_previous_state[@intFromEnum(button)] != 0;
}

pub inline fn is_button_up(self: *const Input, button: Button) bool {
    return self.buttons_current_state[@intFromEnum(button)] == 0;
}

pub inline fn was_button_up(self: *const Input, button: Button) bool {
    return self.buttons_previous_state[@intFromEnum(button)] == 0;
}

pub inline fn button_pressed_this_frame(self: *const Input, button: Button) bool {
    return (self.buttons_current_state[@intFromEnum(button)] != 0 and self.buttons_previous_state[@intFromEnum(button)] == 0);
}

pub inline fn button_released_this_frame(self: *const Input, button: Button) bool {
    return self.buttons_current_state[@intFromEnum(button)] == 0 and self.buttons_previous_state[@intFromEnum(button)] != 0;
}

pub inline fn mouse_pos(self: *const Input) MousePosition {
    return self.current_mouse_pos;
}

pub inline fn prev_mouse_pos(self: *const Input) MousePosition {
    return self.previous_mouse_pos;
}

pub inline fn is_mouse_moved(self: *const Input) bool {
    return self.current_mouse_pos.x != self.previous_mouse_pos.x or self.current_mouse_pos.y != self.previous_mouse_pos.y;
}

pub inline fn mouse_pos_delta(self: *const Input) struct { x_delta: i16, y_delta: i16 } {
    return .{
        .x_delta = self.current_mouse_pos.x - self.previous_mouse_pos.x,
        .y_delta = self.current_mouse_pos.y - self.previous_mouse_pos.y,
    };
}

pub inline fn is_scroll_down(self: *const Input) bool {
    return self.current_mouse_scroll < 0;
}

pub inline fn is_scroll_up(self: *const Input) bool {
    return self.current_mouse_scroll > 0;
}

pub inline fn is_scroll(self: *const Input) bool {
    return self.current_mouse_scroll != 0;
}

pub fn process_key_event(self: *Input, event_system: *Event, key: Key, comptime pressed: u8) void {
    const is_repeated = pressed & self.keys_current_state[@intFromEnum(key)];
    const key_state_change = pressed != self.keys_current_state[@intFromEnum(key)];
    if (self.allow_repeats or key_state_change) {
        self.keys_current_state[@intFromEnum(key)] = pressed;
        const data: Event.KeyEventData = .{
            .key = key,
            .is_repeated = is_repeated,
            .pressed = pressed,
            .mouse_pos = .{ .x = self.current_mouse_pos.x, .y = self.current_mouse_pos.y },
        };

        if (comptime pressed > 0) {
            _ = event_system.fire(.KEY_PRESS, null, @bitCast(data));
        } else {
            _ = event_system.fire(.KEY_RELEASE, null, @bitCast(data));
        }

        const event_code: Event.EventCode = @enumFromInt(@as(u8, @intFromEnum(key)));
        _ = event_system.fire(event_code, null, @bitCast(data));
    }
}

// Is it possible that we need to process cntrl or shift key here?
pub fn process_mouse_event(
    self: *Input,
    event_system: *Event,
    comptime button: Button,
    mousepos: i32,
    comptime pressed: u8,
) void {
    const is_repeated = pressed & self.buttons_current_state[@intFromEnum(button)];
    const key_state_change = pressed != self.buttons_current_state[@intFromEnum(button)];
    if ((self.allow_repeats and is_repeated != 0) or key_state_change) {
        self.buttons_current_state[@intFromEnum(button)] = pressed;
        const data: Event.MouseButtonEventData = .{
            .button_code = button,
            .is_repeated = is_repeated,
            .pressed = pressed,
            .mouse_pos = .{ .x = @truncate(mousepos), .y = @truncate(mousepos >> 16) },
        };

        if (comptime pressed > 0) {
            _ = event_system.fire(.MOUSE_BUTTON_PRESS, null, @bitCast(data));
        } else {
            _ = event_system.fire(.MOUSE_BUTTON_RELEASE, null, @bitCast(data));
        }

        const event_code: Event.EventCode = @enumFromInt(@as(u8, @intFromEnum(button)));
        _ = event_system.fire(event_code, null, @bitCast(data));
    }
}

pub fn process_xmouse_event(
    self: *Input,
    event_system: *Event,
    button: Button,
    mousepos: i32,
    comptime pressed: u8,
) void {
    const is_repeated = pressed & self.buttons_current_state[@intFromEnum(button)];
    const key_state_change = pressed != self.buttons_current_state[@intFromEnum(button)];
    if ((self.allow_repeats and is_repeated != 0) or key_state_change) {
        self.buttons_current_state[@intFromEnum(button)] = pressed;
        const data: Event.MouseButtonEventData = .{
            .button_code = button,
            .is_repeated = is_repeated,
            .pressed = pressed,
            .mouse_pos = .{ .x = @truncate(mousepos), .y = @truncate(mousepos >> 16) },
        };

        if (comptime pressed > 0) {
            _ = event_system.fire(.MOUSE_BUTTON_PRESS, null, @bitCast(data));
        } else {
            _ = event_system.fire(.MOUSE_BUTTON_RELEASE, null, @bitCast(data));
        }

        const event_code: Event.EventCode = @enumFromInt(@as(u8, @intFromEnum(button)));
        _ = event_system.fire(event_code, null, @bitCast(data));
    }
}

pub fn process_mouse_move(self: *Input, event_system: *Event, x: i16, y: i16) void {
    self.current_mouse_pos.x = x;
    self.current_mouse_pos.y = y;
    const mouse_move_data: Event.MouseMoveEventData = .{
        .mouse_pos = .{ .x = x, .y = y },
    };
    _ = event_system.fire(.MOUSE_MOVE, null, @bitCast(mouse_move_data));
}

pub fn process_mouse_wheel(self: *Input, event_system: *Event, z_delta: i8, mousepos: i32) void {
    self.current_mouse_scroll = z_delta;
    const data: Event.MouseScrollEventData = .{
        .z_delta = z_delta,
        .mouse_pos = .{ .x = @truncate(mousepos), .y = @truncate(mousepos >> 16) },
    };
    _ = event_system.fire(.MOUSE_SCROLL, null, @bitCast(data));
}

pub const MAX_BUTTONS = 6;
pub const Button = enum(u8) {
    UNKOWN = 0xFF,
    LEFT = 0x0,
    RIGHT = 0x1,
    MIDDLE = 0x2,
    X1 = 0x3,
    X2 = 0x4,
};

pub const Key = enum(u8) {
    UNKOWN = 0xFF,
    BACKSPACE = 0x08,

    TAB = 0x09,
    ENTER = 0x0D,
    SHIFT = 0x10,
    CONTROL = 0x11,
    ALT = 0x12,
    PAUSE = 0x13,
    CAPS = 0x14,

    ///
    KANA_HANGUL_MODE = 0x15,
    IME_ON = 0x16,
    JUNJA = 0x17,
    IME_FINAL = 0x18,
    KANJI_HANJA_MODE = 0x19,
    IME_OFF = 0x1A,

    ESCAPE = 0x1B,

    CONVERT = 0x1C,
    NONCONVERT = 0x1D,
    ACCEPT = 0x1E,
    MODECHANGE = 0x1F,

    SPACE = 0x20,
    PAGEUP = 0x21,
    PAGEDOWN = 0x22,
    END = 0x23,
    HOME = 0x24,

    LEFT = 0x25,
    UP = 0x26,
    RIGHT = 0x27,
    DOWN = 0x28,

    SELECT = 0x29,
    PRINT = 0x2A,
    EXECUTE = 0x2B,

    PRINTSCREEN = 0x2C,

    INSERT = 0x2D,

    DELETE = 0x2E,
    HELP = 0x2F,

    KEY_0 = 0x30,
    KEY_1 = 0x31,
    KEY_2 = 0x32,
    KEY_3 = 0x33,
    KEY_4 = 0x34,
    KEY_5 = 0x35,
    KEY_6 = 0x36,
    KEY_7 = 0x37,
    KEY_8 = 0x38,
    KEY_9 = 0x39,

    A = 0x41,
    B = 0x42,
    C = 0x43,
    D = 0x44,
    E = 0x45,
    F = 0x46,
    G = 0x47,
    H = 0x48,
    I = 0x49,
    J = 0x4A,
    K = 0x4B,
    L = 0x4C,
    M = 0x4D,
    N = 0x4E,
    O = 0x4F,
    P = 0x50,
    Q = 0x51,
    R = 0x52,
    S = 0x53,
    T = 0x54,
    U = 0x55,
    V = 0x56,
    W = 0x57,
    X = 0x58,
    Y = 0x59,
    Z = 0x5A,

    LSUPER = 0x5B,
    RSUPER = 0x5C,

    APPS = 0x5D,

    /// Put computer to sleep
    SLEEP = 0x5F,

    NUMPAD0 = 0x60,
    NUMPAD1 = 0x61,
    NUMPAD2 = 0x62,
    NUMPAD3 = 0x63,
    NUMPAD4 = 0x64,
    NUMPAD5 = 0x65,
    NUMPAD6 = 0x66,
    NUMPAD7 = 0x67,
    NUMPAD8 = 0x68,
    NUMPAD9 = 0x69,

    MULTIPLY = 0x6A,
    ADD = 0x6B,
    SEPARATOR = 0x6C,
    SUBTRACT = 0x6D,
    DECIMAL = 0x6E,
    DIVIDE = 0x6F,

    F1 = 0x70,
    F2 = 0x71,
    F3 = 0x72,
    F4 = 0x73,
    F5 = 0x74,
    F6 = 0x75,
    F7 = 0x76,
    F8 = 0x77,
    F9 = 0x78,
    F10 = 0x79,
    F11 = 0x7A,
    F12 = 0x7B,
    F13 = 0x7C,
    F14 = 0x7D,
    F15 = 0x7E,
    F16 = 0x7F,
    F17 = 0x80,
    F18 = 0x81,
    F19 = 0x82,
    F20 = 0x83,
    F21 = 0x84,
    F22 = 0x85,
    F23 = 0x86,
    F24 = 0x87,

    NUMLOCK = 0x90,
    SCROLL = 0x91,
    NUMPAD_EQUAL = 0x92,

    LSHIFT = 0xA0,
    RSHIFT = 0xA1,
    LCONTROL = 0xA2,
    RCONTROL = 0xA3,
    LALT = 0xA4,
    RALT = 0xA5,

    BROWSER_BACK = 0xA6,
    BROWSER_FORWARD = 0xA7,
    BROWSER_REFRESH = 0xA8,
    BROWSER_STOP = 0xA9,
    BROWSER_SEARCH = 0xAA,
    BROWSER_FAVOURITES = 0xAB,
    BROWSER_HOME = 0xAC,

    VOLUME_MUTE = 0xAD,
    VOLUME_DOWN = 0xAE,
    VOLUME_UP = 0xAF,

    MEDIA_NEXT_TRACK = 0xB0,
    MEDIA_PREV_TRACK = 0xB1,
    MEDIA_STOP = 0xB2,
    MEDIA_PLAY_PAUSE = 0xB3,

    LAUNCH_APP1 = 0xB6,
    LAUNCH_APP2 = 0xB7,

    SEMICOLON = 0x3B,
    COLON = 0xBA,
    EQUAL = 0xBB,
    COMMA = 0xBC,
    MINUS = 0xBD,
    PERIOD = 0xBE,
    SLASH = 0xBF,

    GRAVE = 0xC0,
    LBRACKET = 0xDB,
    BACKSLASH = 0xDC,
    RBRACKET = 0xDD,
    APOSTROPHE = 0xDE,

    IME_PROCESS = 0xE5,
};

const std = @import("std");
const Event = @import("event.zig");
