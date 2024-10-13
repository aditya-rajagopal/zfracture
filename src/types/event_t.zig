const core = @import("fr_core");

/// The function signature that any event handler must satisfy.
pub const EventCallback = *const fn (
    event_code: EventCode,
    data: EventData,
    // sender: *anyopaque,
    // listener: *anyopaque,
) bool;

pub const EventHandle = struct {
    index: usize,
    generation: usize,
};

/// The data that will be recieved by the handlers
pub const EventData = [16]u8;

const MousePosition = packed struct(u32) { x: u16, y: u16 };

/// Representation of EventData for KeyEvents
pub const KeyEventData = packed struct(u128) {
    /// The position of the mouse when the key event was triggered.
    /// This is passed as a convinience and removes a query to the input system.
    mouse_pos: MousePosition,
    /// The code of the key that was pressed. Cast this to KeyCode enum.
    key_code: u16,
    /// "bool" representing if this key was a repeated press
    is_repeated: u16,
    /// "bool" representing if this is a key press or release event
    pressed: u16,
    _unused: u48 = 0,
};

/// Representation of EventData for MouseButtonEvents
pub const MouseButtonEventData = packed struct(u128) {
    /// The position of the mouse when the mouse event was triggered.
    /// This is passed as a convinience and removes a query to the input system.
    mouse_pos: MousePosition,
    /// The button code that was pressed. Cast this to MouseButtonCode
    button_code: u16,
    _unused: u80 = 0,
};

/// Representation of EventData for MouseScrollEventData
pub const MouseScrollEventData = packed struct(u128) {
    /// The position of the mouse when the mouse event was triggered.
    /// This is passed as a convinience and removes a query to the input system.
    mouse_pos: MousePosition,
    /// The direction of the scroll is represented by the sign and the scroll amount by the magnitude
    z_delta: i16,
    _unused: u80 = 0,
};

/// Representation of EventData for MouseMoveEvent
pub const MouseMoveEventData = packed struct(u128) {
    /// The mouse position
    mouse_pos: MousePosition,
    _unused: u96 = 0,
};

/// Representation of EventData for WindowResize
pub const WindowResizeEventData = packed struct(u128) {
    /// The new window size
    size: packed struct(u32) { width: u16, height: u16 },
    _unused: u96 = 0,
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

pub const EventCodeBacking = u12;

pub const EventCode = enum(EventCodeBacking) {
    application_quit,
    key_press,
    key_release,
    mouse_button_press,
    mouse_button_release,
    mouse_scroll,
    window_resize,
    _,
};

const assert = @import("std").debug.assert;
