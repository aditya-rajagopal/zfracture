const std = @import("std");

pub const EngineState = struct {
    input: InputState,
    permanent_allocator: std.mem.Allocator,
    transient_allocator: std.mem.Allocator,
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
    // TODO(adi): Controller support
    // TODO(adi): Support for multiple controllers/keyboards
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
