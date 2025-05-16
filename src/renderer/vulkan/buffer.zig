// TODO: Should the buffer return even if the bind failed?
// For bind to fail the device must run out of memory. That is so unlikely
const vk = @import("vulkan");
const T = @import("types.zig");

const Context = @import("context.zig");
const CommandBuffer = @import("command_buffer.zig");

const Buffer = @This();

// is_locked: bool,
/// The memory index describing the type of memory that the buffer is allocated from
memory_index: u32,
/// The usage flags for the buffer
// usage: vk.BufferUsageFlags,
/// The total size of the buffer
total_size: u64,
/// The handle to the vulkan buffer
handle: vk.Buffer,
/// The memory handle to the vulkan buffer
memory: vk.DeviceMemory,
// memory_flags: vk.MemoryPropertyFlags,

pub const Error =
    error{NotSuitableMemoryType} ||
    T.LogicalDevice.CreateBufferError ||
    T.LogicalDevice.AllocateMemoryError;

/// Create a buffer. For now we assume that the buffer is only used in one queue
pub fn create(
    /// The vulkan context
    ctx: *const Context,
    /// The total size of the buffer
    total_size: u64,
    /// The usage flags for the buffer
    usage: vk.BufferUsageFlags,
    /// Flags for the memory properties of the buffer
    flags: vk.MemoryPropertyFlags,
    /// Whether to bind the buffer on creation
    comptime bind_on_create: bool,
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

    if (comptime bind_on_create) {
        ctx.device.handle.bindBufferMemory(buffer, memory, 0) catch unreachable;
    }

    return .{
        // .is_locked = false,
        .total_size = total_size,
        .handle = buffer,
        // .usage = usage,
        .memory = memory,
        // .memory_flags = flags,
        .memory_index = memory_index,
    };
}

/// Destroys the buffer and frees the memory
pub fn destroy(self: *Buffer, ctx: *const Context) void {
    ctx.device.handle.freeMemory(self.memory, null);
    self.memory = .null_handle;
    ctx.device.handle.destroyBuffer(self.handle, null);
    self.handle = .null_handle;
}

/// Resizes the buffer. This will copy the data from the old buffer to the new buffer
pub fn resize(
    self: *Buffer,
    /// The vulkan context
    ctx: *const Context,
    /// The new size of the buffer
    new_size: u64,
    /// The queue to submit to use for the copy operation
    queue: vk.Queue,
    /// The command pool to allocate the command buffer from for the copy operation
    pool: vk.CommandPool,
) !void {
    // TODO: Use Buffer.create instead of doing it inline
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

    // copy_to already waits for the queue to finish
    // ctx.device.handle.deviceWaitIdle() catch unreachable;

    self.destroy(ctx);
    self.total_size = new_size;
    self.handle = new_buffer;
    self.memory = memory;
}

pub fn bind(
    self: *Buffer,
    /// The vulkan context
    ctx: *const Context,
    /// The start of the memory region that is bound to the buffer
    offset: u64,
) void {
    // TODO: The offset should always be 0 since we allocate memory for the buffer in one go
    ctx.device.handle.bindBufferMemory(self.handle, self.memory, offset) catch unreachable;
}

/// Locks the memory of the buffer and returns a pointer to it.
/// The pointer is only valid until the buffer is unlocked.
/// It is an application error to memory map a buffer that is already mapped.
/// NOTE: This will only fail if there is not enough virtual address space left. Which is highly unlikely
pub inline fn lock(
    self: *const Buffer,
    /// Offset of the memory region to lock from the start of the memory region
    offset: u64,
    /// Size of the memory region to lock
    size: u64,
    /// Flags for the memory mapping
    flags: vk.MemoryMapFlags,
    /// The vulkan context
    ctx: *const Context,
) ?*anyopaque {
    return ctx.device.handle.mapMemory(self.memory, offset, size, flags) catch null;
}

/// Unlocks the memory of the buffer
pub inline fn unlock(self: *const Buffer, ctx: *const Context) void {
    ctx.device.handle.unmapMemory(self.memory);
}

/// Loads the given data into the buffer
pub fn load_data(
    self: *const Buffer,
    /// Offset of the memory region to load the data into
    offset: u64,
    /// Size of the memory region to load the data into
    size: u64,
    /// Flags for the memory mapping
    flags: vk.MemoryMapFlags,
    /// The vulkan context
    ctx: *const Context,
    /// The data to load into the buffer. This must have atleast size bytes of data
    data: [*]const u8,
) void {
    const data_ptr = self.lock(offset, size, flags, ctx);
    if (data_ptr) |ptr| {
        // NOTE: only copy if the data_ptr is not null else we just continue doing nothing.
        // TODO: Shoudl there be an error for when you get a null pointer;
        const dest: [*]u8 = @ptrCast(ptr);
        @memcpy(dest[0..size], data[0..size]);
    } else {
        unreachable;
    }
    self.unlock(ctx);
}

/// Copies the data from the buffer to another buffer
pub fn copy_to(
    /// The buffer to copy from
    self: *const Buffer,
    /// The vulkan context
    ctx: *const Context,
    /// The command pool to allocate the command buffer from for the copy operation
    pool: vk.CommandPool,
    /// The fence to signal when the command buffer is finished
    fence: vk.Fence,
    /// The queue to submit to use for the copy operation
    queue: vk.Queue,
    /// The destination buffer
    dest: vk.Buffer,
    /// The offset of the source buffer
    src_offset: u64,
    /// The offset of the destination buffer
    dest_offset: u64,
    /// The size of the data to copy
    size: u64,
) CommandBuffer.Error!void {
    ctx.device.handle.queueWaitIdle(queue) catch unreachable;

    // We create a one time use command buffer
    var temp_command_buffer = try CommandBuffer.allocate_and_begin_single_use(ctx, pool);
    errdefer temp_command_buffer.free(ctx);

    const copy_region = vk.BufferCopy{
        .src_offset = src_offset,
        .dst_offset = dest_offset,
        .size = size,
    };

    temp_command_buffer.handle.copyBuffer(self.handle, dest, 1, @ptrCast(&copy_region));
    try temp_command_buffer.end_single_use(ctx, fence, queue);
}
