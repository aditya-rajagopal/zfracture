// TODO: Should the buffer return even if the bind failed?
// For bind to fail the device must run out of memory. That is so unlikely
const vk = @import("vulkan");
const T = @import("types.zig");

const Context = @import("context.zig");
const CommandBuffer = @import("command_buffer.zig");

const Buffer = @This();

// is_locked: bool,
total_size: u64,
handle: vk.Buffer,
usage: vk.BufferUsageFlags,
memory: vk.DeviceMemory,
// memory_flags: vk.MemoryPropertyFlags,
memory_index: u32,

pub const Error =
    error{NotSuitableMemoryType} ||
    T.LogicalDevice.CreateBufferError ||
    T.LogicalDevice.AllocateMemoryError;

pub fn create(
    ctx: *const Context,
    total_size: u64,
    usage: vk.BufferUsageFlags,
    flags: vk.MemoryPropertyFlags,
    bind_on_create: bool,
) Error!Buffer {
    const create_info = vk.BufferCreateInfo{
        .size = total_size,
        .usage = usage,
        // NOTE: WE are assuming that the buffer is only used in 1 queue. Can be something we can change later
        .sharing_mode = .exclusive,
    };

    const buffer = try ctx.device.handle.createBuffer(&create_info, null);
    errdefer ctx.device.handle.destroyBuffer(buffer, null);

    const memory_requirements = ctx.device.handle.getBufferMemoryRequirements(buffer);

    const memory_index = try ctx.find_memory_index(memory_requirements.memory_type_bits, flags);

    const allocate_info = vk.MemoryAllocateInfo{
        .allocation_size = memory_requirements.size,
        .memory_type_index = memory_index,
    };

    const memory = try ctx.device.handle.allocateMemory(&allocate_info, null);

    if (bind_on_create) {
        ctx.device.handle.bindBufferMemory(buffer, memory, 0) catch unreachable;
    }

    return .{
        // .is_locked = false,
        .total_size = total_size,
        .handle = buffer,
        .usage = usage,
        .memory = memory,
        // .memory_flags = flags,
        .memory_index = memory_index,
    };
}

pub fn destroy(self: *Buffer, ctx: *const Context) void {
    ctx.device.handle.freeMemory(self.memory, null);
    self.memory = .null_handle;
    ctx.device.handle.destroyBuffer(self.handle, null);
    self.handle = .null_handle;
}

pub fn resize(
    self: *Buffer,
    ctx: *const Context,
    new_size: u64,
    queue: vk.Queue,
    pool: vk.CommandPool,
) !void {
    const create_info = vk.BufferCreateInfo{
        .size = new_size,
        .usage = self.usage,
        // NOTE: WE are assuming that the buffer is only used in 1 queue. Can be something we can change later
        .sharing_mode = .exclusive,
    };

    const new_buffer = try ctx.device.handle.createBuffer(&create_info, null);
    errdefer ctx.device.handle.destroyBuffer(new_buffer, null);

    const memory_requirements = ctx.device.handle.getBufferMemoryRequirements(new_buffer);

    const allocate_info = vk.MemoryAllocateInfo{
        .allocation_size = memory_requirements.size,
        .memory_type_index = self.memory_index,
    };

    const memory = try ctx.device.handle.allocateMemory(&allocate_info, null);
    errdefer ctx.device.handle.freeMemory(memory, null);

    ctx.device.handle.bindBufferMemory(new_buffer, memory, 0) catch unreachable;

    self.copy_to(ctx, pool, .null_handle, queue, new_buffer, 0, 0, self.total_size);

    ctx.device.handle.deviceWaitIdle() catch unreachable;

    self.destroy(ctx);
    self.total_size = new_size;
    self.handle = new_buffer;
    self.memory = memory;
}

pub fn bind(self: *Buffer, ctx: *const Context, offset: u64) void {
    ctx.device.handle.bindBufferMemory(self.handle, self.memory, offset) catch unreachable;
}

pub inline fn lock(self: *Buffer, offset: u64, size: u64, flags: vk.MemoryMapFlags, ctx: *const Context) ?*anyopaque {
    // NOTE: This will only fail if there is not enough virtual address space left. Which is highly unlikely
    return ctx.device.handle.mapMemory(self.memory, offset, size, flags) catch null;
}

pub inline fn unlock(self: *Buffer, ctx: *const Context) void {
    ctx.device.handle.unmapMemory(self.memory);
}

pub fn load_data(self: *Buffer, offset: u64, size: u64, flags: u32, ctx: *const Context, data: []const u8) void {
    const data_ptr = self.lock(offset, size, flags, ctx);
    if (data_ptr) |ptr| {
        // NOTE: only copy if the data_ptr is not null else we just continue doing nothing.
        // TODO: Shoudl there be an error for when you get a null pointer;
        const dest: [*]u8 = @ptrCast(ptr);
        @memcpy(dest[0..size], data);
    } else {
        unreachable;
    }
    self.unlock(ctx);
}

pub fn copy_to(
    self: *const Buffer,
    ctx: *const Context,
    pool: vk.CommandPool,
    fence: vk.Fence,
    queue: vk.Queue,
    dest: vk.Buffer,
    src_offset: u64,
    dest_offset: u64,
    size: u64,
) CommandBuffer.Error!void {
    ctx.device.handle.queueWaitIdle(queue) catch unreachable;

    // We create a one time use command buffer
    const temp_command_buffer = try CommandBuffer.allocate_and_begin_single_use(ctx, pool);
    errdefer temp_command_buffer.free(ctx);

    const copy_region = vk.BufferCopy{
        .src_offset = src_offset,
        .dst_offset = dest_offset,
        .size = size,
    };

    temp_command_buffer.handle.copyBuffer(self.handle, dest, 1, @ptrCast(&copy_region));
    try temp_command_buffer.end_single_use(ctx, fence, queue);
}
