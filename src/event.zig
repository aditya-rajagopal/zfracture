//  TODO:
//      - [ ] Create a static multiarrayList
//      - [ ] Create multiple lists for handling frame future events and timed events
//      - [ ] For now assume there is no listener and sender pointers. Maybe in the future.
//      - [ ] Structure the data to be data oriented
//      - [ ] Create an EventData pool for the deffered events storage
//      - [ ] Does the event system need the idea of layers so that certain handlers get first shot at handling events
//      - [ ] Do permanent events need a seperate structure?
//      - [ ] Priority queue for deferred events?
const core = @import("fr_core");

const types = @import("types/types.zig");

pub const max_callbacks_per_event = 2048;
pub const max_event_types = std.math.maxInt(types.EventCodeBacking);

// const EventCallbackList = core.StaticArrayList(types.EventCallback, max_callbacks_per_event);
const CallbackFuncList = [max_callbacks_per_event * max_event_types]types.EventCallback;
const EventState = struct {
    callbacks: [max_event_types]std.ArrayListUnmanaged(types.EventCallback),
};

// TODO: Should this be a static lifetime var or should we allocate it at init
var callback_list: CallbackFuncList = undefined;
var event_state: EventState = undefined;
var local_arena: std.heap.ArenaAllocator = undefined;
var initialized: bool = false;

/// Initialize the event system
pub fn init(ctx: *types.Memory) !void {
    // debug_assert_msg(
    //     !initialized,
    //     @src(),
    //     "Reinitializing Event system.",
    //     .{},
    // );
    _ = ctx;
    // const allocator = ctx.gpa.get_type_allocator(.event);
    // local_arena = std.heap.ArenaAllocator.init(allocator);

    for (0..max_event_types) |i| {
        const start = i * max_callbacks_per_event;
        const end = start + max_callbacks_per_event;
        event_state.callbacks[i] = std.ArrayListUnmanaged(types.EventCallback).initBuffer(callback_list[start..end]);
    }
    initialized = true;
}

/// Cleanup the event system
pub fn deinit() void {
    // debug_assert_msg(
    //     initialized,
    //     @src(),
    //     "Reinitializing Event system.",
    //     .{},
    // );
    initialized = false;
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
pub fn register(comptime event_code: types.EventCode, callback: types.EventCallback) bool {
    // debug_assert_msg(
    //     initialized,
    //     @src(),
    //     "Cannot register to the Event system. Not Initialized.",
    //     .{},
    // );

    const code: usize = @intFromEnum(event_code);
    const array_list = &event_state.callbacks[code];
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
pub fn deregister(event_code: types.EventCode, callback: types.EventCallback) bool {
    // debug_assert_msg(
    //     initialized,
    //     @src(),
    //     "Cannot deregister from the Event system. Not Initialized.",
    //     .{},
    // );
    const code: usize = @intFromEnum(event_code);
    const array_list = &event_state.callbacks[code];
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

pub fn dispatch_deffered() bool {
    core.not_implemented("");
}

/// Fire an event with a specific event code.
/// The event is fired immediately and every callback is called. If a specific callback handles the event and returns
/// true then the remaining events in the list are not proccessed. So be aware of order of registrations.
///
/// Arguments:
///     - event_code: Comptime known code for the type of event that is being fired
///     - event_data: the packet that is forwarded to all callbacks
pub fn fire(comptime event_code: types.EventCode, event_data: types.EventData) bool {
    // debug_assert_msg(
    //     initialized,
    //     @src(),
    //     "Cannot fire an event. Event system not Initialized.",
    //     .{},
    // );
    const code: usize = @intFromEnum(event_code);
    const array_list = &event_state.callbacks[code];

    for (array_list.items) |callback| {
        if (callback(event_code, event_data)) {
            return true;
        }
    }
    return true;
}

pub fn fire_deffered() bool {
    core.not_implemented("");
}

test "Event" {
    var app_context: types.Memory = undefined;
    try init(&app_context);
    errdefer deinit();
    defer deinit();
    const key_data: types.KeyEventData = .{ .key_code = 1, .pressed = 1, .mouse_pos = .{ .x = 69, .y = 420 }, .is_repeated = 1 };

    const dispatcher = struct {
        pub fn dipatch() bool {
            return fire(types.EventCode.key_press, @bitCast(key_data));
        }
    };

    const listener = struct {
        pub fn listen(event_code: types.EventCode, event_data: types.EventData) bool {
            const in_data: types.KeyEventData = @bitCast(event_data);
            std.testing.expectEqual(event_code, types.EventCode.key_press) catch {
                std.debug.panic("Not a key press event. Got: {s}", .{@tagName(event_code)});
            };
            std.testing.expectEqual(in_data, key_data) catch {
                std.debug.panic("Event data is not all 0s", .{});
            };
            return true;
        }
    };

    var success = register(.key_press, listener.listen);
    try std.testing.expect(success);
    success = dispatcher.dipatch();
    try std.testing.expect(success);
}

const std = @import("std");
