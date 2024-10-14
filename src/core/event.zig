//  TODO:
//      - [ ] Create a static multiarrayList
//      - [ ] Create multiple lists for handling frame future events and timed events
//      - [ ] For now assume there is no listener and sender pointers. Maybe in the future.
//      - [ ] Structure the data to be data oriented
//      - [ ] Create an EventData pool for the deffered events storage
//      - [ ] Does the event system need the idea of layers so that certain handlers get first shot at handling events
//      - [ ] Do permanent events need a seperate structure?
//      - [ ] Priority queue for deferred events?

const Memory = @import("fracture.zig").mem.Memory;

pub const max_callbacks_per_event = 2048;
pub const max_event_types = std.math.maxInt(EventCodeBacking);

// const EventCallbackList = core.StaticArrayList(EventCallback, max_callbacks_per_event);
const CallbackFuncList = [max_callbacks_per_event * max_event_types]EventCallback;
const EventState = struct {
    callbacks: [max_event_types]std.ArrayListUnmanaged(EventCallback),
};

const Event = @This();

callback_list: CallbackFuncList = undefined,
event_state: EventState = undefined,
// local_arena: std.heap.ArenaAllocator = undefined,
// initialized: bool = false,

/// Initialize the event system
pub fn init(self: *Event) !void {
    // debug_assert_msg(
    //     !initialized,
    //     @src(),
    //     "Reinitializing Event system.",
    //     .{},
    // );
    // const allocator = ctx.gpa.get_type_allocator(.event);
    // local_arena = std.heap.ArenaAllocator.init(allocator);

    for (0..max_event_types) |i| {
        const start = i * max_callbacks_per_event;
        const end = start + max_callbacks_per_event;
        self.event_state.callbacks[i] = std.ArrayListUnmanaged(EventCallback).initBuffer(self.callback_list[start..end]);
    }
}

/// Cleanup the event system
pub fn deinit(self: *Event) void {
    // debug_assert_msg(
    //     initialized,
    //     @src(),
    //     "Reinitializing Event system.",
    //     .{},
    // );
    // initialized = false;
    _ = self;
}

// TODO: If we know an event is going to handle the event before hand can we place it in front of the callback queue?
/// Register a callback to handle a specific event.
/// The function pointer uniquely identifies a particular function and you can only have the callback registered
/// once per event code type.
/// You are forced to know event_code at compile time when registering for events
///
/// Arguments:
///     - event_code: Comptime known code for the type of event that needs to be listened for
///     - callback: Function to call when an event is fired
pub fn register(self: *Event, comptime event_code: EventCode, callback: EventCallback) bool {
    // debug_assert_msg(
    //     initialized,
    //     @src(),
    //     "Cannot register to the Event system. Not Initialized.",
    //     .{},
    // );

    const code: usize = @intFromEnum(event_code);
    const array_list = &self.event_state.callbacks[code];
    for (array_list.items) |c| {
        if (c == callback) {
            // never_msg(@src(), "Trying to register callback for event_code: {d} again", .{code});
            return false;
        }
    }

    array_list.appendAssumeCapacity(callback);
    return true;
}

/// Deregister an event.
/// This will check if the function actually exists and will return false if it could not find it. In debug builds
/// it will throw an error and breakpoint.
/// For now the event is removed from the list and the order of the remaining events are maintained.
///
/// Arguments:
///     - event_code: Comptime known code for the type of event that the callback was registered for
///     - callback: Function pointer that was registered
pub fn deregister(self: *Event, event_code: EventCode, callback: EventCallback) bool {
    // debug_assert_msg(
    //     initialized,
    //     @src(),
    //     "Cannot deregister from the Event system. Not Initialized.",
    //     .{},
    // );
    const code: usize = @intFromEnum(event_code);
    const array_list = &self.event_state.callbacks[code];
    for (array_list.items, 0..) |c, i| {
        if (c == callback) {
            // TODO: How do you deal with events that handle the event
            // What is the order we need to maintain. Do we need layers?
            // _ = array_list.swapRemove(i);
            _ = array_list.orderedRemove(i);
            return true;
        }
    }
    // never_msg(@src(), "Deregistering an event that was not registered", .{});
    return false;
}

pub fn dispatch_deffered(self: *Event) bool {
    _ = self;
    // not_implemented(@src());
    return false;
}

/// Fire an event with a specific event code.
/// The event is fired immediately and every callback is called. If a specific callback handles the event and returns
/// true then the remaining events in the list are not proccessed. So be aware of order of registrations.
///
/// Arguments:
///     - event_code: Comptime known code for the type of event that is being fired
///     - event_data: the packet that is forwarded to all callbacks
pub fn fire(self: *Event, comptime event_code: EventCode, event_data: EventData) bool {
    // debug_assert_msg(
    //     initialized,
    //     @src(),
    //     "Cannot fire an event. Event system not Initialized.",
    //     .{},
    // );
    const code: usize = @intFromEnum(event_code);
    const array_list = &self.event_state.callbacks[code];

    for (array_list.items) |callback| {
        if (callback(event_code, event_data)) {
            return true;
        }
    }
    return true;
}

pub fn fire_deffered(self: *Event) bool {
    // not_implemented(@src());
    _ = self;
    return false;
}

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

test "Event" {
    const event: *Event = try std.testing.allocator.create(Event);
    defer std.testing.allocator.destroy(event);
    try init(event);
    errdefer event.deinit();
    defer event.deinit();
    const key_data: KeyEventData = .{ .key_code = 1, .pressed = 1, .mouse_pos = .{ .x = 69, .y = 420 }, .is_repeated = 1 };

    const dispatcher = struct {
        pub fn dipatch(e: *Event) bool {
            return e.fire(EventCode.key_press, @bitCast(key_data));
        }
    };

    const listener = struct {
        pub fn listen(event_code: EventCode, event_data: EventData) bool {
            const in_data: KeyEventData = @bitCast(event_data);
            std.testing.expectEqual(event_code, EventCode.key_press) catch {
                std.debug.panic("Not a key press event. Got: {s}", .{@tagName(event_code)});
            };
            std.testing.expectEqual(in_data, key_data) catch {
                std.debug.panic("Event data is not all 0s", .{});
            };
            return true;
        }
    };

    var success = event.register(.key_press, listener.listen);
    try std.testing.expect(success);
    success = dispatcher.dipatch(event);
    try std.testing.expect(success);
}

const std = @import("std");
