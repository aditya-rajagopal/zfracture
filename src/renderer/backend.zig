const types = @import("types.zig");
const VulkanContext = @import("vulkan_backend.zig");
const Backend = @This();

platform_state: *anyopaque,
frame_number: u64,
context: VulkanContext,
// init: *const fn (backend: *Backend, application_name: []const u8, plat_state: *anyopaque) bool,
// deinit: *const fn (backend: *Backend) void,
// on_resize: *const fn (backend: *Backend, width: u16, height: u16) void,
// begin_frame: *const fn (backend: *Backend, delta_time: f32) bool,
// end_frame: *const fn (backend: *Backend, delta_time: f32) bool,

pub const BackendError = error{UnsupportedBackend};

pub fn create(renderer_tag: types.Tag, platform_state: *anyopaque) BackendError!Backend {
    var backend: Backend = undefined;
    backend.platform_state = platform_state;
    backend.frame_number = 0;
    switch (renderer_tag) {
        .VULKAN => {
            backend.context = undefined;
        },
        else => return BackendError.UnsupportedBackend,
    }
    return backend;
}

pub fn destroy(self: *Backend) void {
    _ = self;
}

const std = @import("std");
