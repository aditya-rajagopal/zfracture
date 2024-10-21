const vk = @import("vulkan");
const Context = @import("context.zig");

pub const Image = struct {
    handle: vk.Image,
    memory: vk.DeviceMemory,
    view: vk.ImageView,
    extent: vk.Extent2D,
};

pub const Error =
    Context.LogicalDevice.CreateImageViewError ||
    Context.LogicalDevice.CreateImageError ||
    Context.LogicalDevice.BindImageMemoryError ||
    Context.LogicalDevice.AllocateMemoryError;

pub fn create_image(
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
        .mip_levels = 4,
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

    const memory_type = ctx.find_memory_index(memory_requirements.memory_type_bits, memory_flags);
    if (memory_type == -1) {
        //TODO: ERROR
        std.debug.print("Required memory type not found\n", .{});
    }

    const allocate_info = vk.MemoryAllocateInfo{
        .allocation_size = memory_requirements.size,
        .memory_type_index = @bitCast(memory_type),
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

pub fn destroy_image(ctx: *const Context, image: *Image) void {
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
}

pub fn create_image_view(
    ctx: *const Context,
    image: vk.Image,
    format: vk.Format,
    aspect_mask: vk.ImageAspectFlags,
) Context.LogicalDevice.CreateImageViewError!vk.ImageView {
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

const std = @import("std");
