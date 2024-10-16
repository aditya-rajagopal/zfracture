const core = @import("fr_core");
const types = @import("types.zig");
const Backend = @import("backend.zig");
const std = @import("std");

const Frontend = @This();

backend: Backend,

pub const FrontendError = error{ InitFailed, EndFrameFailed } || Backend.BackendError;

pub fn init(self: *Frontend, application_name: [:0]const u8, platform_state: *anyopaque) FrontendError!void {
    // TODO: Make this configurable
    self.backend = try Backend.create(.VULKAN, platform_state);

    self.backend.context.init(std.heap.page_allocator, application_name, platform_state) catch {
        return FrontendError.InitFailed;
    };

    return;
}

pub fn deinit(self: *Frontend) void {
    self.backend.context.deinit();
}

pub fn begin_frame(self: *Frontend, delta_time: f32) bool {
    return self.backend.context.begin_frame(delta_time);
}

pub fn end_frame(self: *Frontend, delta_time: f32) bool {
    self.backend.frame_number += 1;
    return self.backend.context.end_frame(delta_time);
}

// Does this need to be an error or can it just be a bool?
pub fn draw_frame(self: *Frontend, packet: types.Packet) FrontendError!void {
    // Only if the begin frame is successful can we continue with the mid frame operations
    if (self.begin_frame(packet.delta_time)) {
        // If the end frame fails it is likely irrecoverable
        if (!self.end_frame(packet.delta_time)) {
            return FrontendError.EndFrameFailed;
        }
    }
}

pub fn on_resize(width: u16, height: u16) void {
    _ = width;
    _ = height;
}