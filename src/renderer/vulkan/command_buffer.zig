const m = @import("fr_core").math;
const vk = @import("vulkan");
const T = @import("types.zig");

const Context = @import("context.zig");
pub const CommandBuffer = @This();

/// The handle to the command buffer
handle: T.CommandBufferProxy,
/// The state of the command buffer
state: T.CommandBufferState,
/// The command pool that the command buffer is allocated from
pool: vk.CommandPool,

pub const Error =
    T.LogicalDevice.AllocateCommandBuffersError ||
    T.LogicalDevice.BeginCommandBufferError ||
    T.LogicalDevice.EndCommandBufferError ||
    T.LogicalDevice.QueueSubmitError ||
    T.LogicalDevice.QueueWaitIdleError;

/// Allocates a command buffer from the provided pool.
pub fn allocate(
    ctx: *const Context,
    /// The command pool to allocate from
    pool: vk.CommandPool,
    /// Whether the command buffer is primary or secondary
    is_primary: bool,
) Error!CommandBuffer {
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
pub fn begin(
    self: *CommandBuffer,
    ///True if you know for sure that you will reset this command buffer after submitting one time
    is_single_use: bool,
    ///This is for secondary command buffers that will be executed within a renderpass
    ///and is ignored for primary command buffers.
    is_renderpass_continuation: bool,
    ///True when the command buffer can be submitted to the queue multiple times while it is in the
    ///pending state.
    is_simultaneous_use: bool,
) T.CommandBufferProxy.BeginCommandBufferError!void {
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

pub fn end(self: *CommandBuffer) T.CommandBufferProxy.EndCommandBufferError!void {
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
    self.handle.resetCommandBuffer(.{}) catch unreachable;
    self.state = .ready;
}

pub fn allocate_and_begin_single_use(ctx: *const Context, pool: vk.CommandPool) Error!CommandBuffer {
    // NOTE: Usually single use command buffers are primary
    var command_buffer = try allocate(ctx, pool, true);
    try command_buffer.begin(true, false, false);
    return command_buffer;
}

/// Ends a single use command buffer and submits it to the queue. It will wait
pub fn end_single_use(
    self: *CommandBuffer,
    /// The vulkan context
    ctx: *const Context,
    /// The fence to signal when the command buffer is finished
    fence: vk.Fence,
    /// The queue to submit to
    queue: vk.Queue,
) !void {
    try self.end();
    const submit_info = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&self.handle.handle),
    };

    try ctx.device.handle.queueSubmit(queue, 1, @ptrCast(&submit_info), fence);
    self.update_submitted();
    // Wait for the queu to finish. This is equivalent to providing a fence and waiting for it to be signaled
    // TODO: Should we use the fence to signal instead? or let the user do it?
    try ctx.device.handle.queueWaitIdle(queue);
    self.free(ctx);
}
