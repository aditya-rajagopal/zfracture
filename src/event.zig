const std = @import("std");

const input = @import("input.zig");
const Key = input.Key;
const MouseButton = input.MouseButton;
const MousePosition = input.MousePosition;

pub const Event = union(enum(u8)) {
    key_pressed: Key,
    key_released: Key,
    key_repeat: Key,

    mouse_pressed: MouseButtonEvent,
    mouse_released: MouseButtonEvent,
    mouse_scroll: struct { value: i8, mouse_pos: MousePosition },
    reset_keyboard,
    reset_mouse,
    reset_all,
    mouse_move: MousePosition,

    pub const MouseButtonEvent = struct {
        button: MouseButton,
        pos: MousePosition,
    };
};
