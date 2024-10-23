const m = @import("fr_core").math;
const vk = @import("vulkan");
const T = @import("types.zig");

const Context = @import("context.zig");
pub const CommandBuffer = @This();

handle: T.CommandBufferProxy,
state: T.CommandBufferState,
pool: vk.CommandPool,

pub const Error =
    T.LogicalDevice.AllocateCommandBuffersError ||
    T.LogicalDevice.BeginCommandBufferError ||
    T.LogicalDevice.EndCommandBufferError ||
    T.LogicalDevice.QueueSubmitError ||
    T.LogicalDevice.QueueWaitIdleError;

pub fn allocate(ctx: *const Context, pool: vk.CommandPool, is_primary: bool) !CommandBuffer {
    const allocate_info = vk.CommandBufferAllocateInfo{
        .command_pool = pool,
        .command_buffer_count = 1,
        .level = if (is_primary) .primary else .secondary,
    };
    var handle: vk.CommandBuffer = .null_handle;
    try ctx.device.handle.allocateCommandBuffers(&allocate_info, @ptrCast(&handle));
    const cmd_proxy = T.CommandBufferProxy.init(handle, ctx.device.handle.wrapper);
    return CommandBuffer{
        .handle = cmd_proxy,
        .state = .ready,
        .pool = pool,
    };
}

pub fn free(self: *CommandBuffer, ctx: *const Context) void {
    if (self.handle.handle != .null_handle) {
        ctx.device.handle.freeCommandBuffers(self.pool, 1, @ptrCast(&self.handle.handle));
        self.handle.handle = .null_handle;
        self.state = .not_allocated;
    }
}

/// Start command buffer and allow it to record commands
/// Arguments:
///     is_single_use: True if you know for sure that you will reset this command buffer after submitting one time
///     is_renderpass_continuation: This is for secondary command buffers that will be executed within a renderpass
///                                 and is ignored for primary command buffers.
///     is_simultaneous_use: True when the command buffer can be submitted to the queue multiple times while it is in the
///                          pending state.
pub fn begin(
    self: *CommandBuffer,
    is_single_use: bool,
    is_renderpass_continuation: bool,
    is_simultaneous_use: bool,
) !void {
    const begin_info = vk.CommandBufferBeginInfo{
        .flags = .{
            .one_time_submit_bit = is_single_use,
            .render_pass_continue_bit = is_renderpass_continuation,
            .simultaneous_use_bit = is_simultaneous_use,
        },
        .p_next = null,
        .p_inheritance_info = null,
    };

    try self.handle.beginCommandBuffer(&begin_info);
    self.state = .recording;
}

pub fn end(self: *CommandBuffer) !void {
    // TODO: Check if the current state is valid to end
    try self.handle.endCommandBuffer();
    self.state = .recording_end;
}

pub inline fn update_submitted(self: *CommandBuffer) void {
    //TODO: Check if the command buffere is in a valid state to transition to submitted
    self.state = .submitted;
}

pub fn reset(self: *CommandBuffer) void {
    //TODO: Check if the command buffere is in a valid state to transition to ready
    self.state = .ready;
}

pub fn allocate_and_begin_single_use(ctx: *const Context, pool: vk.CommandPool) !CommandBuffer {
    // NOTE: Usually single use command buffers are primary
    var command_buffer = try allocate(ctx, pool, true);
    try command_buffer.begin(true, false, false);
    return command_buffer;
}

pub fn end_single_use(self: *CommandBuffer, ctx: *const Context, fence: vk.Fence, queue: vk.Queue) void {
    try self.end();
    const submit_info = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&self.handle.handle),
    };

    try ctx.device.handle.queueSubmit(queue, 1, &submit_info, fence);
    self.update_submitted();
    try ctx.device.handle.queueWaitIdle(queue);
    self.free(ctx);
}
