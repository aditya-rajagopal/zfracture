//! The event system
//!
//! The event system is a simple implmentation of an structure that stores callbacks for specific event types and
//! allows firing events.
//!
//! Currently events are fired sequentially and the order of callbacks is garunteed to be the same as the order of
//! registration. You can register the same callback with different listener payloads for the same event type.
//!
//! There is a limit of max_callbacks_per_event and max_event_types. The max_callbacks_per_event is the maximum number
//! of callbacks that can be registered for a single event type. The max_event_types is the maximum number of event
//! types that can be registered. The default values are 512 and 512 respectively.
//! To increase these values change the global constants.
//!
//! For user defined events use integers codes converted to the EventCode enum with values greater than EVENT_CODE_USER_START.
//!
//! WARN: The event system does not support events that are fired from multiple threads currently. This is undefined behavior.
//!
//! # Examples
//!
//! ```zig
//! const std = @import("std");
//! const assert = std.debug.assert;
//! const Event = @import("fr_core").Event;
//! const EventCode = Event.EventCode;
//! const KeyEventData = Event.KeyEventData;
//!
//! pub fn main() !void {
//!     var event_system = Event.init(std.heap.page_allocator);
//!     defer event_system.deinit();
//!
//!     const key_data: KeyEventData = .{ .key = .A, .pressed = 1, .mouse_pos = .{ .x = 69, .y = 420 }, .is_repeated = 1 };
//!
//!     const dispatcher = struct {
//!         pub fn dipatch(e: *Event) bool {
//!             return e.fire(EventCode.KEY_PRESS, null, @bitCast(key_data));
//!         }
//!     };
//!
//!     const listener = struct {
//!         pub fn listen(event_code: EventCode, event_data: EventData, _: ?*anyopaque, _: ?*anyopaque) bool {
//!             const in_data: KeyEventData = @bitCast(event_data);
//!             assert(event_code == EventCode.KEY_PRESS) // Not a key press event.
//!             assert(in_data == key_data) // Event data is the same as the data sent by the dispatcher
//!             return true;
//!         }
//!     };
//!
//!     var success = event.register(.KEY_PRESS, null, listener.listen);
//!     assert(success);
//!     success = dispatcher.dipatch(event);
//!     assert(success);
//!     success = event.deregister(.KEY_PRESS, null, listener.listen);
//!     assert(success);
//! }
//! ```
//  TODO:
//      - [ ] Create a static multiarrayList
//      - [ ] Check if we need SoA or AoS for the event data.
//      - [ ] Are the static versions of the functions necessary
//      - [ ] Create multiple lists for handling frame future events and timed events
//      - [ ] Structure the data to be data oriented
//      - [ ] Create an EventData pool for the deffered events storage
//      - [ ] Does the event system need the idea of layers so that certain handlers get first shot at handling events
//      - [ ] Do permanent events need a seperate structure?
//      - [ ] Priority queue for deferred events?

const Memory = @import("fracture.zig").mem.Memory;

pub const max_callbacks_per_event = 512;
pub const max_event_types = 512;

// TODO: Does this need to be SoA or AoS
const Listeners = [max_callbacks_per_event * max_event_types]?*anyopaque;
const CallbackFuncList = [max_callbacks_per_event * max_event_types]EventCallback;

const Event = @This();

/// The list of listerners for all event types. The index is the event_code * max_callbacks_per_event + callback_index
listeners_list: [max_callbacks_per_event * max_event_types]?*anyopaque = undefined,
/// The list of callbacks for all event types. The index is the event_code * max_callbacks_per_event + callback_index
callback_list: [max_callbacks_per_event * max_event_types]EventCallback = undefined,
/// The number of listeners for each event type
lens: [max_event_types]usize,

/// Initialize the event system
pub fn init(self: *Event) !void {
    @memset(self.lens[0..max_event_types], 0);
    @memset(self.listeners_list[0 .. max_event_types * max_callbacks_per_event], null);
}

/// Cleanup the event system
pub fn deinit(self: *Event) void {
    _ = self;
}

/// Register a callback to handle a specific event.
/// The function pointer uniquely identifies a particular function and you can only have the callback registered
/// once per event code type.
/// You are forced to know event_code at compile time when registering for events
pub fn register(
    self: *Event,
    /// The code for which the callback will be called
    event_code: EventCode,
    /// Pointer to data the listener wants to pass to the callback function
    listener: ?*anyopaque,
    /// Function to call when an event is fired
    callback: EventCallback,
) bool {
    // TODO: If we know an event is going to handle the event before hand can we place it in front of the callback queue?
    const code: usize = @intFromEnum(event_code);
    const len = self.lens[code];
    assert(len <= max_callbacks_per_event);
    assert(code < max_event_types);

    const start = code * max_callbacks_per_event;
    const end = start + len;
    for (start..end) |i| {
        if (self.listeners_list[i] == listener and self.callback_list[i] == callback) {
            switch (builtin.mode) {
                .Debug => {
                    unreachable;
                },
                else => return false,
            }
        }
    }

    self.listeners_list[end] = listener;
    self.callback_list[end] = callback;
    self.lens[code] += 1;

    return true;
}

/// Comptime version of the register function. This expects you to know the event_code at compile time.
/// Not really needed but if you are registering and deregistering events rapidly you might want to use this one.
pub fn register_static(
    self: *Event,
    /// The code for which the callback will be called
    comptime event_code: EventCode,
    /// Pointer to data the listener wants to pass to the callback function
    listener: ?*anyopaque,
    /// Function to call when an event is fired
    callback: EventCallback,
) bool {
    const code: usize = @intFromEnum(event_code);
    const start = code * max_callbacks_per_event;
    comptime assert(code < max_event_types);

    const len = self.lens[code];
    assert(len < max_callbacks_per_event);

    const end = start + len;
    for (start..end) |i| {
        if (self.listeners_list[i] == listener and self.callback_list[i] == callback) {
            switch (builtin.mode) {
                .Debug => {
                    unreachable;
                },
                else => return false,
            }
        }
    }

    self.listeners_list[end] = listener;
    self.callback_list[end] = callback;
    self.lens[code] += 1;

    return true;
}

/// Deregister an event.
/// This will check if the function actually exists and will return false if it could not find it. In debug builds
/// it will throw an error and breakpoint.
/// For now the event is removed from the list and the order of the remaining events are maintained.
pub fn deregister(
    self: *Event,
    /// The code for which the callback will be called
    event_code: EventCode,
    /// Pointer to data the listener had registered for the callback
    listener: ?*anyopaque,
    /// Function to call when an event is fired
    callback: EventCallback,
) bool {
    const code: usize = @intFromEnum(event_code);
    const len = self.lens[code];
    assert(code < max_event_types);

    const start = code * max_callbacks_per_event;
    const end = start + len;
    for (start..end) |i| {
        if (self.listeners_list[i] == listener and self.callback_list[i] == callback) {
            // TODO: How do you deal with events that handle the event
            // What is the order we need to maintain. Do we need layers?
            // _ = array_list.swapRemove(i);
            for (self.listeners_list[i .. end - 1], self.listeners_list[i + 1 .. end]) |*d, s| d.* = s;
            for (self.callback_list[i .. end - 1], self.callback_list[i + 1 .. end]) |*d, s| d.* = s;
            self.listeners_list[end] = undefined;
            self.callback_list[end] = undefined;
            self.lens[code] -= 1;
            return true;
        }
    }

    switch (builtin.mode) {
        .Debug => {
            unreachable;
        },
        else => return false,
    }
}

/// WARNING: NOT IMPLEMENTED
pub fn dispatch_deffered(self: *Event) bool {
    _ = self;
    return false;
}

/// Fire an event with a specific event code.
/// The event is fired immediately and every callback is called. If a specific callback handles the event and returns
/// true then the remaining events in the list are not proccessed. So be aware of order of registrations.
pub fn fire(
    self: *const Event,
    /// The even to be fired
    event_code: EventCode,
    /// Pointer to data the sender wants to send to all the callbacks
    sender: ?*anyopaque,
    /// The payload that is forwarded to all callbacks
    event_data: EventData,
) bool {
    const code: usize = @intFromEnum(event_code);
    const start = code * max_callbacks_per_event;

    const len = self.lens[code];
    assert(code < max_event_types);

    if (len == 0) return true;

    const end = start + len;
    for (start..end) |i| {
        if (self.callback_list[i](event_code, event_data, self.listeners_list[i], sender)) {
            return true;
        }
    }
    return true;
}

/// Comptime version of the fire function. This is more useful than register_static. You probably are firing events
/// every frame from many places and if you know the event code at compile time this should save a few clock cycles
/// and allow the compiler to optimize a bit more.
///
/// THough i am not sure if it is truly better as you get a lot of different functions that will hit the icache
pub fn fire_static(
    self: *const Event,
    /// The even to be fired
    comptime event_code: EventCode,
    /// Pointer to data the sender wants to send to all the callbacks
    sender: ?*anyopaque,
    /// The payload that is forwarded to all callbacks
    event_data: EventData,
) bool {
    const code: usize = @intFromEnum(event_code);
    const len = self.lens[code];
    comptime assert(code < max_event_types);

    if (len == 0) return true;

    const start = code * max_callbacks_per_event;
    const end = start + len;
    for (start..end) |i| {
        if (self.callback_list[i](event_code, event_data, self.listeners_list[i], sender)) {
            return true;
        }
    }
    return true;
}

/// WARNING: NOT IMPLEMENTED
pub fn fire_deffered(self: *Event) bool {
    _ = self;
    return false;
}

/// WARNING: NOT IMPLEMENTED
pub fn fire_deffered_static(self: *Event) bool {
    // not_implemented(@src());
    _ = self;
    return false;
}

/// The function signature that any event handler must satisfy.
pub const EventCallback = *const fn (
    /// The code of the even that the callback is handling
    event_code: EventCode,
    /// The opaque event payload that must be interpreted based on the event code
    data: EventData,
    /// Pointer to data registed with the callback
    listener: ?*anyopaque,
    /// Pointer to data the sender wants to send to the callback
    sender: ?*anyopaque,
) bool;

/// The data that will be recieved by the handlers. The data is opaque and is interpreted based on the event code.
pub const EventData = [16]u8;

pub const MousePosition = packed struct(i32) { x: i16 = 0, y: i16 = 0 };

/// Representation of EventData for KeyEvents.
pub const KeyEventData = packed struct(u128) {
    /// The position of the mouse when the key event was triggered.
    /// This is passed as a convinience and removes a query to the input system.
    mouse_pos: MousePosition = .{},
    /// The code of the key that was pressed.
    key: input.Key = .UNKOWN,
    /// "bool" representing if this is a key press or release event
    pressed: u8 = 0,
    /// "bool" representing if this key was a repeated press
    is_repeated: u16 = 0,
    _unused: u64 = 0,
};

/// Representation of EventData for MouseButtonEvents
pub const MouseButtonEventData = packed struct(u128) {
    /// The position of the mouse when the mouse event was triggered.
    /// This is passed as a convinience and removes a query to the input system.
    mouse_pos: MousePosition = .{},
    /// The button code that was pressed. Cast this to MouseButtonCode
    button_code: input.Button = .UNKOWN,
    /// "bool" representing if this is a key press or release event
    pressed: u8 = 0,
    /// "bool" representing if this key was a repeated press
    is_repeated: u16 = 0,
    _unused: u64 = 0,
};

/// Representation of EventData for MouseScrollEventData
pub const MouseScrollEventData = packed struct(u128) {
    /// The position of the mouse when the mouse event was triggered.
    /// This is passed as a convinience and removes a query to the input system.
    mouse_pos: MousePosition = .{},
    /// The direction of the scroll is represented by the sign and the scroll amount by the magnitude
    z_delta: i16 = 0,
    _unused: u80 = 0,
};

/// Representation of EventData for MouseMoveEvent
pub const MouseMoveEventData = packed struct(u128) {
    /// The mouse position
    mouse_pos: MousePosition = .{},
    _unused: u96 = 0,
};

/// Representation of EventData for WindowResize
pub const WindowResizeEventData = packed struct(u128) {
    /// The new window size
    size: packed struct(u64) { width: u32 = 0, height: u32 = 0 },
    _unused: u64 = 0,
};

/// When the application wants to send around custom data they can either manage it on the application side
/// Or use this structure to send anonymous packets
pub const CustomData = packed struct(u128) {
    /// The length of the data that is represented by the pointer
    len: usize,
    /// Pointer to some unknown data
    data: *anyopaque,
};

comptime {
    assert(@sizeOf(KeyEventData) == 16);
    assert(@sizeOf(CustomData) == 16);
}

pub const EventCodeBacking = u16;

/// The event codes that uniquely identify the event.
///
/// The ones defined here are the ones that are used by the engine and usually are not meant to be fired by the application.
/// For user defined events use integers codes converted to this enum with values greater than EVENT_CODE_USER_START
pub const EventCode = enum(EventCodeBacking) {
    BUTTON_LEFT = 0x0,
    BUTTON_RIGHT = 0x1,
    BUTTON_MIDDLE = 0x2,
    BUTTON_X1 = 0x3,
    BUTTON_X2 = 0x4,

    KEY_BACKSPACE = 0x08,

    KEY_TAB = 0x09,
    KEY_ENTER = 0x0D,
    KEY_SHIFT = 0x10,
    KEY_CONTROL = 0x11,
    KEY_ALT = 0x12,
    KEY_PAUSE = 0x13,
    KEY_CAPS = 0x14,

    ///
    KEY_KANA_HANGUL_MODE = 0x15,
    KEY_IME_ON = 0x16,
    KEY_JUNJA = 0x17,
    KEY_IME_FINAL = 0x18,
    KEY_KANJI_HANJA_MODE = 0x19,
    KEY_IME_OFF = 0x1A,

    KEY_ESCAPE = 0x1B,

    KEY_CONVERT = 0x1C,
    KEY_NONCONVERT = 0x1D,
    KEY_ACCEPT = 0x1E,
    KEY_MODECHANGE = 0x1F,

    KEY_SPACE = 0x20,
    KEY_PAGEUP = 0x21,
    KEY_PAGEDOWN = 0x22,
    KEY_END = 0x23,
    KEY_HOME = 0x24,

    KEY_LEFT = 0x25,
    KEY_UP = 0x26,
    KEY_RIGHT = 0x27,
    KEY_DOWN = 0x28,

    KEY_SELECT = 0x29,
    KEY_PRINT = 0x2A,
    KEY_EXECUTE = 0x2B,

    KEY_PRINTSCREEN = 0x2C,

    KEY_INSERT = 0x2D,

    KEY_DELETE = 0x2E,
    KEY_HELP = 0x2F,

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

    KEY_A = 0x41,
    KEY_B = 0x42,
    KEY_C = 0x43,
    KEY_D = 0x44,
    KEY_E = 0x45,
    KEY_F = 0x46,
    KEY_G = 0x47,
    KEY_H = 0x48,
    KEY_I = 0x49,
    KEY_J = 0x4A,
    KEY_K = 0x4B,
    KEY_L = 0x4C,
    KEY_M = 0x4D,
    KEY_N = 0x4E,
    KEY_O = 0x4F,
    KEY_P = 0x50,
    KEY_Q = 0x51,
    KEY_R = 0x52,
    KEY_S = 0x53,
    KEY_T = 0x54,
    KEY_U = 0x55,
    KEY_V = 0x56,
    KEY_W = 0x57,
    KEY_X = 0x58,
    KEY_Y = 0x59,
    KEY_Z = 0x5A,

    KEY_LSUPER = 0x5B,
    KEY_RSUPER = 0x5C,

    KEY_APPS = 0x5D,

    /// Put computer to sleep
    KEY_SLEEP = 0x5F,

    KEY_NUMPAD0 = 0x60,
    KEY_NUMPAD1 = 0x61,
    KEY_NUMPAD2 = 0x62,
    KEY_NUMPAD3 = 0x63,
    KEY_NUMPAD4 = 0x64,
    KEY_NUMPAD5 = 0x65,
    KEY_NUMPAD6 = 0x66,
    KEY_NUMPAD7 = 0x67,
    KEY_NUMPAD8 = 0x68,
    KEY_NUMPAD9 = 0x69,

    KEY_MULTIPLY = 0x6A,
    KEY_ADD = 0x6B,
    KEY_SEPARATOR = 0x6C,
    KEY_SUBTRACT = 0x6D,
    KEY_DECIMAL = 0x6E,
    KEY_DIVIDE = 0x6F,

    KEY_F1 = 0x70,
    KEY_F2 = 0x71,
    KEY_F3 = 0x72,
    KEY_F4 = 0x73,
    KEY_F5 = 0x74,
    KEY_F6 = 0x75,
    KEY_F7 = 0x76,
    KEY_F8 = 0x77,
    KEY_F9 = 0x78,
    KEY_F10 = 0x79,
    KEY_F11 = 0x7A,
    KEY_F12 = 0x7B,
    KEY_F13 = 0x7C,
    KEY_F14 = 0x7D,
    KEY_F15 = 0x7E,
    KEY_F16 = 0x7F,
    KEY_F17 = 0x80,
    KEY_F18 = 0x81,
    KEY_F19 = 0x82,
    KEY_F20 = 0x83,
    KEY_F21 = 0x84,
    KEY_F22 = 0x85,
    KEY_F23 = 0x86,
    KEY_F24 = 0x87,

    KEY_NUMLOCK = 0x90,
    KEY_SCROLL = 0x91,
    KEY_NUMPAD_EQUAL = 0x92,

    KEY_LSHIFT = 0xA0,
    KEY_RSHIFT = 0xA1,
    KEY_LCONTROL = 0xA2,
    KEY_RCONTROL = 0xA3,
    KEY_LALT = 0xA4,
    KEY_RALT = 0xA5,

    KEY_BROWSER_BACK = 0xA6,
    KEY_BROWSER_FORWARD = 0xA7,
    KEY_BROWSER_REFRESH = 0xA8,
    KEY_BROWSER_STOP = 0xA9,
    KEY_BROWSER_SEARCH = 0xAA,
    KEY_BROWSER_FAVOURITES = 0xAB,
    KEY_BROWSER_HOME = 0xAC,

    KEY_VOLUME_MUTE = 0xAD,
    KEY_VOLUME_DOWN = 0xAE,
    KEY_VOLUME_UP = 0xAF,

    KEY_MEDIA_NEXT_TRACK = 0xB0,
    KEY_MEDIA_PREV_TRACK = 0xB1,
    KEY_MEDIA_STOP = 0xB2,
    KEY_MEDIA_PLAY_PAUSE = 0xB3,

    KEY_LAUNCH_APP1 = 0xB6,
    KEY_LAUNCH_APP2 = 0xB7,

    KEY_SEMICOLON = 0x3B,
    KEY_COLON = 0xBA,
    KEY_EQUAL = 0xBB,
    KEY_COMMA = 0xBC,
    KEY_MINUS = 0xBD,
    KEY_PERIOD = 0xBE,
    KEY_SLASH = 0xBF,

    KEY_GRAVE = 0xC0,
    KEY_LBRACKET = 0xDB,
    KEY_BACKSLASH = 0xDC,
    KEY_RBRACKET = 0xDD,
    KEY_APOSTROPHE = 0xDE,

    KEY_IME_PROCESS = 0xE5,
    INPUT_LAST = 0xE6,

    APPLICATION_QUIT = 0xFF,
    KEY_PRESS = 0x100,
    KEY_RELEASE = 0x101,
    MOUSE_BUTTON_PRESS = 0x102,
    MOUSE_BUTTON_RELEASE = 0x103,
    MOUSE_MOVE = 0x104,
    MOUSE_SCROLL = 0x105,
    WINDOW_RESIZE = 0x106,

    /// Debug events that are used for debugging and testing. Do not use these in production.
    /// They have no defined behaviour and are purely used for debugging specific parts of the engine.
    DEBUG0 = 0x107,
    DEBUG1 = 0x108,
    DEBUG2 = 0x109,
    DEBUG3 = 0x10a,
    DEBUG4 = 0x10b,

    /// The first event code that is reserved for application specific events.
    APPLICATION_EVENTS_START = 0x144,
    _,

    pub fn from_int(val: EventCodeBacking) EventCode {
        return @enumFromInt(val);
    }
};

const assert = @import("std").debug.assert;

test "Event" {
    const event: *Event = try std.testing.allocator.create(Event);
    defer std.testing.allocator.destroy(event);
    try init(event);
    defer event.deinit();
    const key_data: KeyEventData = .{ .key = .A, .pressed = 1, .mouse_pos = .{ .x = 69, .y = 420 }, .is_repeated = 1 };

    const dispatcher = struct {
        pub fn dipatch(e: *Event) bool {
            return e.fire(EventCode.KEY_PRESS, null, @bitCast(key_data));
        }
    };

    const listener = struct {
        pub fn listen(event_code: EventCode, event_data: EventData, _: ?*anyopaque, _: ?*anyopaque) bool {
            const in_data: KeyEventData = @bitCast(event_data);
            std.testing.expectEqual(event_code, EventCode.KEY_PRESS) catch {
                std.debug.panic("Not a key press event. Got: {s}", .{@tagName(event_code)});
            };
            std.testing.expectEqual(in_data, key_data) catch {
                std.debug.panic("Event data is not all 0s", .{});
            };
            return true;
        }
    };

    var success = event.register(.KEY_PRESS, null, listener.listen);
    try std.testing.expect(success);
    success = dispatcher.dipatch(event);
    try std.testing.expect(success);
}

const std = @import("std");
const builtin = @import("builtin");
const input = @import("input.zig");
