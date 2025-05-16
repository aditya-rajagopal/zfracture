const std = @import("std");
const assert = std.debug.assert;
const vk = @import("vulkan");
const T = @import("types.zig");

const Context = @import("context.zig");
const CommandBuffer = @import("command_buffer.zig");
const Buffer = @import("buffer.zig");

const Image = @This();

/// The handle to the vulkan image
handle: vk.Image,
/// The memory handle to the vulkan image memory
memory: vk.DeviceMemory,
/// The image view handle to the vulkan image
view: vk.ImageView,
/// The extent of the image
extent: vk.Extent2D,

pub const Error =
    error{NotSuitableMemoryType} ||
    T.LogicalDevice.CreateImageViewError ||
    T.LogicalDevice.CreateImageError ||
    T.LogicalDevice.BindImageMemoryError ||
    T.LogicalDevice.AllocateMemoryError;

pub const ImageCreateInfo = struct {
    /// The image type
    image_type: vk.ImageType,
    /// The extent of the image. This is the size of the image in pixels
    extent: vk.Extent2D,
    /// The depth of the image
    /// TODO: Support depth more than 1
    depth: u32 = 1,
    /// The format of the image
    format: vk.Format,
    /// The tiling of the image
    tiling: vk.ImageTiling,
    /// The usage flags for the image
    usage: vk.ImageUsageFlags,
    /// The memory flags for the image memory allocation
    memory_flags: vk.MemoryPropertyFlags,
    /// Whether to create an image view
    create_view: bool,
    /// The aspects of the image view
    view_aspects: vk.ImageAspectFlags,
    /// The number of mipmap levels in the image
    /// TODO: Support mipmaps
    mip_levels: u32 = 1,
    /// The number of layers in the image
    /// TODO: More than 1 layer is not supported yet
    layer_count: u32 = 1,
    /// The number of samples in the image
    /// TODO: Support multiple samples
    samples: vk.SampleCountFlags = .{ .@"1_bit" = true },
    /// Sharing mode for the image
    /// TODO: Support sharing mode other than exclusive
    sharing_mode: vk.SharingMode = .exclusive,
};

/// Creates an image with the given parameters and also creates an image view if create_view is true
/// TODO: Need to provide configuration for depth, mipmaps and multiplayer images
pub fn create(
    /// The vulkan context
    ctx: *const Context,
    /// The image create info
    create_info: *const ImageCreateInfo,
) Error!Image {
    // TODO: Suppport depth more than 1
    assert(create_info.depth == 1);
    // TODO: Support multiple layers
    assert(create_info.layer_count == 1);
    // TODO: Support mipmaps
    assert(create_info.mip_levels == 1);
    // TODO: Support sharing mode other than exclusive
    assert(create_info.sharing_mode == .exclusive);

    var image: Image = undefined;
    image.extent = create_info.extent;

    const image_create_info = vk.ImageCreateInfo{
        .image_type = create_info.image_type,
        .extent = .{
            .width = create_info.extent.width,
            .height = create_info.extent.height,
            .depth = create_info.depth,
        },
        .mip_levels = create_info.mip_levels,
        // TODO: support multiple layers
        .array_layers = create_info.layer_count,
        .format = create_info.format,
        .tiling = create_info.tiling,
        .initial_layout = .undefined,
        .usage = create_info.usage,
        .samples = create_info.samples,
        .sharing_mode = create_info.sharing_mode,
    };

    image.handle = try ctx.device.handle.createImage(&image_create_info, null);
    errdefer ctx.device.handle.destroyImage(image.handle, null);

    const memory_requirements = ctx.device.handle.getImageMemoryRequirements(image.handle);

    const memory_type = try ctx.find_memory_index(memory_requirements.memory_type_bits, create_info.memory_flags);

    const allocate_info = vk.MemoryAllocateInfo{
        .allocation_size = memory_requirements.size,
        .memory_type_index = memory_type,
    };

    image.memory = try ctx.device.handle.allocateMemory(&allocate_info, null);
    errdefer ctx.device.handle.freeMemory(image.memory, null);

    // TODO: Configurable memory offset when using image pools
    try ctx.device.handle.bindImageMemory(image.handle, image.memory, 0);

    if (create_info.create_view) {
        image.view = try create_image_view(ctx, image.handle, create_info.format, create_info.view_aspects);
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
