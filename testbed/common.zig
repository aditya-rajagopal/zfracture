const std = @import("std");

const fr = @import("fracture");
const Renderer = fr.Renderer;

pub const max_fps = 60;
// Round up so the frame rate does not exceed the cap.
pub const frame_duration: std.Io.Duration = .fromNanoseconds(
    @divTrunc(std.time.ns_per_s + max_fps - 1, max_fps),
);

// Share the inset between window sizing and drawing to prevent framebuffer clipping.
pub const windowed_frame_margin = 10;

pub const HostControls = struct {
    pressed_this_frame: struct {
        ctrl: bool = false,
        enter: bool = false,
        @"3": bool = false,
    } = .{},
    down: struct {
        ctrl: bool = false,
        alt: bool = false,
    } = .{},

    // Retain each side so releasing one modifier does not release the other.
    modifier_down: u4 = 0,

    const left_ctrl: u4 = 1 << 0;
    const right_ctrl: u4 = 1 << 1;
    const left_alt: u4 = 1 << 2;
    const right_alt: u4 = 1 << 3;

    pub fn consumeFrame(self: *HostControls, events: []const fr.event.Event) void {
        self.pressed_this_frame = .{};
        for (events) |event| {
            switch (event) {
                .key_pressed => |key| {
                    self.setHeld(key, true);
                    switch (key) {
                        .lcontrol, .rcontrol => self.pressed_this_frame.ctrl = true,
                        .enter => self.pressed_this_frame.enter = true,
                        .@"3" => self.pressed_this_frame.@"3" = true,
                        else => {},
                    }
                },
                .key_repeat => |key| self.setHeld(key, true),
                .key_released => |key| self.setHeld(key, false),
                .reset_keyboard, .reset_all => {
                    self.down = .{};
                    self.modifier_down = 0;
                },
                else => {},
            }
        }
    }

    fn setHeld(self: *HostControls, key: fr.input.Key, is_down: bool) void {
        const mask: u4 = switch (key) {
            .lcontrol => left_ctrl,
            .rcontrol => right_ctrl,
            .lalt => left_alt,
            .ralt => right_alt,
            else => return,
        };
        if (is_down) {
            self.modifier_down |= mask;
        } else {
            self.modifier_down &= ~mask;
        }
        self.down.ctrl = (self.modifier_down & (left_ctrl | right_ctrl)) != 0;
        self.down.alt = (self.modifier_down & (left_alt | right_alt)) != 0;
    }
};

pub const EngineState = struct {
    io: std.Io,
    sound: fr.SoundSystem,
    permanent_allocator: std.mem.Allocator,
    transient_allocator: std.mem.Allocator,
    renderer: Renderer,

    delta_time: f32,
};
