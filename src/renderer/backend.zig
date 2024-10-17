const Context = @import("context.zig");
const platform = @import("../platform/platform.zig");

pub const Tag = enum {
    VULKAN,
    OPENGL,
    DIRECTX,
};

const Backend = @This();

platform_state: *anyopaque,
frame_number: u64,
context: Context,

pub const BackendError = error{UnsupportedBackend};

pub fn create(
    comptime renderer_tag: Tag,
    platform_state: *anyopaque,
) BackendError!Backend {
    var backend: Backend = undefined;
    backend.platform_state = platform_state;
    backend.frame_number = 0;
    switch (renderer_tag) {
        .VULKAN => {
            backend.context = undefined;
        },
        else => @compileError("Unsupported renderer " ++ @tagName(renderer_tag)),
    }
    return backend;
}

pub fn destroy(self: *Backend) void {
    _ = self;
}

pub fn on_resize(self: *Backend, width: u16, height: u16) void {
    _ = self;
    _ = width;
    _ = height;
}

pub fn begin_frame(self: *Backend, delta_time: f32) bool {
    _ = self;
    _ = delta_time;
    return true;
}

pub fn end_frame(self: *Backend, delta_time: f32) bool {
    _ = self;
    _ = delta_time;
    return true;
}

const std = @import("std");
