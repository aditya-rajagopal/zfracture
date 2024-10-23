const vk = @import("vulkan");
const T = @import("types.zig");
const Context = @import("context.zig");

const Fence = @This();

handle: vk.Fence = .null_handle,
is_signaled: bool = false,

pub fn create(ctx: *const Context, create_signaled: bool) !Fence {
    const handle = try ctx.device.handle.createFence(
        &.{
            .flags = .{ .signaled_bit = create_signaled },
        },
        null,
    );

    return .{
        .handle = handle,
        .is_signaled = create_signaled,
    };
}

pub fn wait(self: *Fence, ctx: *const Context, timeout: u64) bool {
    if (!self.is_signaled) {
        const result = ctx.device.handle.waitForFences(
            1,
            @ptrCast(&self.handle),
            vk.TRUE,
            timeout,
        ) catch |err| switch (err) {
            error.OutOfHostMemory => {
                ctx.log.err("vk Fence wait: OUT_OF_HOST_MEMORY", .{});
                return false;
            },
            error.OutOfDeviceMemory => {
                ctx.log.err("vk Fence wait: OUT_OF_DEVICE_MEMORY", .{});
                return false;
            },
            error.DeviceLost => {
                ctx.log.err("vk Fence wait: DEVICE_LOST", .{});
                return false;
            },
            error.Unknown => {
                ctx.log.err("vk Fence wait: UNKOWN", .{});
                return false;
            },
        };
        switch (result) {
            .success => {
                self.is_signaled = true;
                return true;
            },
            .timeout => {
                ctx.log.err("vk Fence wait: Timed out", .{});
            },
            else => {},
        }
        return false;
    } else {
        // NOTE: If a fence is already signaled we dont have to wait on it.
        return true;
    }
}

pub fn reset(self: *Fence, ctx: *const Context) !void {
    if (self.is_signaled) {
        _ = try ctx.device.handle.resetFences(1, @ptrCast(&self.handle));
        self.is_signaled = false;
    }
}

pub fn destroy(self: *Fence, ctx: *const Context) void {
    if (self.handle != .null_handle) {
        ctx.device.handle.destroyFence(self.handle, null);
        self.handle = .null_handle;
        self.is_signaled = false;
    }
}
