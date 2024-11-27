const vk = @import("vulkan");
const T = @import("types.zig");

const Context = @import("context.zig");
const CommandBuffer = @import("command_buffer.zig");
const Buffer = @import("buffer.zig");

const Image = @This();

handle: vk.Image,
memory: vk.DeviceMemory,
view: vk.ImageView,
extent: vk.Extent2D,

pub const Error =
    error{NotSuitableMemoryType} ||
    T.LogicalDevice.CreateImageViewError ||
    T.LogicalDevice.CreateImageError ||
    T.LogicalDevice.BindImageMemoryError ||
    T.LogicalDevice.AllocateMemoryError;

pub fn create(
    ctx: *const Context,
    image_type: vk.ImageType,
    extent: vk.Extent2D,
    format: vk.Format,
    tiling: vk.ImageTiling,
    usage: vk.ImageUsageFlags,
    memory_flags: vk.MemoryPropertyFlags,
    create_view: bool,
    view_aspects: vk.ImageAspectFlags,
) Error!Image {
    var image: Image = undefined;
    image.extent = extent;

    const create_info = vk.ImageCreateInfo{
        .image_type = image_type,
        .extent = .{
            .width = extent.width,
            .height = extent.height,
            // TODO: Support configurable depth
            .depth = 1,
        },
        // TODO: Need to support mipmapping
        .mip_levels = 1,
        // TODO: support multiple layers
        .array_layers = 1,
        .format = format,
        .tiling = tiling,
        .initial_layout = .undefined,
        .usage = usage,
        // TODO: Make this configurable
        .samples = .{ .@"1_bit" = true },
        // TODO: Make this configurable
        .sharing_mode = .exclusive,
    };

    image.handle = try ctx.device.handle.createImage(&create_info, null);
    errdefer ctx.device.handle.destroyImage(image.handle, null);

    const memory_requirements = ctx.device.handle.getImageMemoryRequirements(image.handle);

    const memory_type = try ctx.find_memory_index(memory_requirements.memory_type_bits, memory_flags);

    const allocate_info = vk.MemoryAllocateInfo{
        .allocation_size = memory_requirements.size,
        .memory_type_index = memory_type,
    };

    image.memory = try ctx.device.handle.allocateMemory(&allocate_info, null);
    errdefer ctx.device.handle.freeMemory(image.memory, null);

    // TODO: Configurable memory offset when using image pools
    try ctx.device.handle.bindImageMemory(image.handle, image.memory, 0);

    if (create_view) {
        image.view = try create_image_view(ctx, image.handle, format, view_aspects);
    } else {
        image.view = .null_handle;
    }

    return image;
}

pub fn destroy(image: *Image, ctx: *const Context) void {
    if (image.view != .null_handle) {
        ctx.device.handle.destroyImageView(image.view, null);
        image.view = .null_handle;
    }

    if (image.memory != .null_handle) {
        ctx.device.handle.freeMemory(image.memory, null);
        image.memory = .null_handle;
    }

    if (image.handle != .null_handle) {
        ctx.device.handle.destroyImage(image.handle, null);
        image.handle = .null_handle;
    }

    image.extent = .{ .width = 0, .height = 0 };
}

pub fn create_image_view(
    ctx: *const Context,
    image: vk.Image,
    format: vk.Format,
    aspect_mask: vk.ImageAspectFlags,
) T.LogicalDevice.CreateImageViewError!vk.ImageView {
    const create_info = vk.ImageViewCreateInfo{
        .image = image,
        .view_type = .@"2d",
        .format = format,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = aspect_mask,
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    };
    return ctx.device.handle.createImageView(&create_info, null);
}

pub fn transition_layout(
    self: *const Image,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
    ctx: *const Context,
    cmd: *const CommandBuffer,
) void {
    // NOTE: This is used to inform the pipeline that any command executed before this barrier must use the old layout
    // and any after should use the new format and must wait till the transition is done. This is sort of like a syncroniztion
    // step
    var barrier = vk.ImageMemoryBarrier{
        .old_layout = old_layout,
        .new_layout = new_layout,
        .src_queue_family_index = ctx.device.queues.graphics.family,
        .dst_queue_family_index = ctx.device.queues.graphics.family,
        .image = self.handle,
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .dst_access_mask = .{},
        .src_access_mask = .{},
    };

    var source_stage = vk.PipelineStageFlags{};
    var dst_stage = vk.PipelineStageFlags{};

    // .undefined means we dont care what the old layout is
    if (old_layout == .undefined and new_layout == .transfer_dst_optimal) {
        // NOTE: We dont care about the old layout and are transitioninig to a layout that is optimal for the underlying
        // implementation
        barrier.src_access_mask = .{};
        // Sinc we are setting the new layout to be transfer_dst_optimal then we want to set the write bit for the dst_access_mask
        barrier.dst_access_mask = .{ .transfer_write_bit = true };

        // Doht care what stage the pipeline is at the start
        source_stage = .{ .top_of_pipe_bit = true };
        // Dest stage is used for copying
        dst_stage = .{ .transfer_bit = true };
    } else if (old_layout == .transfer_dst_optimal and new_layout == .shader_read_only_optimal) {
        barrier.src_access_mask = .{ .transfer_write_bit = true };
        barrier.dst_access_mask = .{ .shader_read_bit = true };

        source_stage = .{ .transfer_bit = true };
        // We are using this image in the fragment shader as a texture
        dst_stage = .{ .fragment_shader_bit = true };
    } else {
        ctx.log.fatal("Unsupported layout transition for image", .{});
        return;
    }

    cmd.handle.pipelineBarrier(source_stage, dst_stage, .{}, 0, null, 0, null, 1, @ptrCast(&barrier));
}

// TODO: Should this be in the command buffer
pub fn copy_from_buffer(
    self: *const Image,
    buffer: vk.Buffer,
    cmd: *const CommandBuffer,
) void {
    const copy = vk.BufferImageCopy{
        .buffer_offset = 0,
        .buffer_row_length = 0,
        .buffer_image_height = 0,
        .image_extent = .{
            .width = self.extent.width,
            .height = self.extent.height,
            .depth = 1,
        },
        .image_offset = .{ .x = 0, .y = 0, .z = 0 },
        .image_subresource = .{
            .mip_level = 0,
            .aspect_mask = .{ .color_bit = true },
            .base_array_layer = 0,
            .layer_count = 1,
        },
    };

    cmd.handle.copyBufferToImage(buffer, self.handle, .transfer_dst_optimal, 1, @ptrCast(&copy));
}

const std = @import("std");
