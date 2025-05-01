const vk = @import("vulkan");
const T = @import("types.zig");
const Context = @import("context.zig");
const Image = @import("image.zig");
const Framebuffer = @import("framebuffer.zig");
const CommandBuffer = @import("command_buffer.zig");
const Fence = @import("fence.zig");

const Swapchain = @This();

/// Reference to the context
ctx: *const Context,
/// The handle to the swapchain
handle: vk.SwapchainKHR,
/// Format of the image we are going to render to
image_format: vk.SurfaceFormatKHR,
present_mode: vk.PresentModeKHR,
/// Total maximum number of frames in flight.
max_frames_in_flight: u8,
/// Images we will use to render to
images: []SwapImage,
/// Semaphore for acquiring the next image from the swapchain
next_image_acquired: vk.Semaphore,
/// Current image index
current_image_index: u32,

depth_attachement: Image,
depth_format: vk.Format,

pub const Error =
    error{ ImageAcquiredFailed, FailedToPresentSwapchain } ||
    T.LogicalDevice.AcquireNextImageKHRError ||
    T.LogicalDevice.CreateSemaphoreError ||
    Image.Error ||
    T.LogicalDevice.CreateSwapchainKHRError ||
    T.LogicalDevice.GetSwapchainImagesAllocKHRError ||
    T.Instance.GetPhysicalDeviceSurfaceFormatsAllocKHRError ||
    T.Instance.GetPhysicalDeviceSurfacePresentModesKHRError;

pub fn init(ctx: *const Context, extent: vk.Extent2D) !Swapchain {
    return create(ctx, extent, .null_handle);
}

pub fn deinit(self: *Swapchain) void {
    self.destroy_all_but_swapchain();
    self.ctx.device.handle.destroySwapchainKHR(self.handle, null);
}

pub fn wait_for_all_fences(self: *Swapchain) void {
    for (self.images) |*si| _ = si.fence.wait(self.ctx, std.math.maxInt(u64));
}

fn create(ctx: *const Context, extent: vk.Extent2D, old_handle: vk.SwapchainKHR) !Swapchain {
    var swapchain: Swapchain = undefined;

    swapchain.image_format = try find_surface_format(ctx);
    swapchain.present_mode = try find_present_mode(ctx);

    const capabilities = try ctx.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(
        ctx.device.pdev,
        ctx.surface,
    );

    var actual_extent = extent;

    if (capabilities.current_extent.width != std.math.maxInt(u32)) {
        actual_extent = capabilities.current_extent;
    }

    actual_extent.width = std.math.clamp(
        actual_extent.width,
        capabilities.min_image_extent.width,
        capabilities.max_image_extent.width,
    );
    actual_extent.height = std.math.clamp(
        actual_extent.height,
        capabilities.min_image_extent.height,
        capabilities.max_image_extent.height,
    );

    var image_count = capabilities.min_image_count + 1;
    if (capabilities.max_image_count > 0 and image_count > capabilities.max_image_count) {
        image_count = capabilities.max_image_count;
    }

    const graphics_family = ctx.device.queues.graphics.family;
    const present_family = ctx.device.queues.present.family;
    const queue_family_indices = [_]u32{ graphics_family, present_family };

    const sharing_mode: vk.SharingMode = if (graphics_family != present_family) .concurrent else .exclusive;
    const len: u32 = if (graphics_family != present_family) queue_family_indices.len else 0;

    const create_info = vk.SwapchainCreateInfoKHR{
        .surface = ctx.surface,
        .min_image_count = image_count,
        .image_format = swapchain.image_format.format,
        .image_color_space = swapchain.image_format.color_space,
        .image_extent = actual_extent,
        .image_array_layers = 1,
        // NOTE: Here we are saying we are going to use these images as a colour buffer
        .image_usage = .{ .color_attachment_bit = true },
        .image_sharing_mode = sharing_mode,
        .queue_family_index_count = len,
        .p_queue_family_indices = @ptrCast(&queue_family_indices),
        .pre_transform = capabilities.current_transform,
        // NOTE: Opaque bit here means we do not want to blend with the OS.
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = swapchain.present_mode,
        .clipped = vk.TRUE,
        // TODO: SHould this always be null? according to kohi tutorial it is?
        .old_swapchain = old_handle,
    };
    const handle = try ctx.device.handle.createSwapchainKHR(&create_info, null);
    errdefer ctx.device.handle.destroySwapchainKHR(handle, null);

    if (old_handle != .null_handle) {
        // NOTE: We must destroy the old swapchain
        ctx.device.handle.destroySwapchainKHR(old_handle, null);
    }

    swapchain.handle = handle;
    swapchain.max_frames_in_flight = @truncate(image_count - 1);

    swapchain.images = try init_swapchain_images(ctx, swapchain.handle, swapchain.image_format.format);
    errdefer {
        for (swapchain.images) |*swap_image| {
            swap_image.deinit(ctx);
        }
        ctx.allocator.free(swapchain.images);
    }

    swapchain.next_image_acquired = try ctx.device.handle.createSemaphore(&.{}, null);
    errdefer ctx.device.handle.destroySemaphore(swapchain.next_image_acquired, null);

    const result = try ctx.device.handle.acquireNextImageKHR(
        swapchain.handle,
        std.math.maxInt(u64),
        swapchain.next_image_acquired,
        .null_handle,
    );

    if (result.result != .success) {
        return error.ImageAcquiredFailed;
    }

    std.mem.swap(
        vk.Semaphore,
        &swapchain.images[result.image_index].image_available_semephore,
        &swapchain.next_image_acquired,
    );

    swapchain.current_image_index = result.image_index;

    // TODO: Is this something we can recover from?
    swapchain.depth_format = try ctx.detect_depth_format();

    swapchain.depth_attachement = try Image.create(
        ctx,
        .@"2d",
        actual_extent,
        swapchain.depth_format,
        .optimal,
        .{ .depth_stencil_attachment_bit = true },
        .{ .device_local_bit = true },
        true,
        .{ .depth_bit = true },
    );
    ctx.log.debug("Swapchain Created Successfully!: present mode: {s}", .{@tagName(swapchain.present_mode)});
    swapchain.ctx = ctx;
    return swapchain;
}

fn destroy_all_but_swapchain(self: *Swapchain) void {
    self.depth_attachement.destroy(self.ctx);
    for (self.images) |*swap_image| {
        swap_image.deinit(self.ctx);
    }
    self.ctx.allocator.free(self.images);
    self.ctx.device.handle.destroySemaphore(self.next_image_acquired, null);
}

pub fn recreate(self: *Swapchain, new_extent: vk.Extent2D) !void {
    const old_handle = self.handle;
    self.destroy_all_but_swapchain();
    self.* = try create(self.ctx, new_extent, old_handle);
}

pub const SwapchainPresentError =
    T.LogicalDevice.QueuePresentKHRError || T.LogicalDevice.QueueSubmitError || error{FailedToPresentSwapchain};

pub fn present(self: *Swapchain, command_buffer: *CommandBuffer) SwapchainPresentError!bool {
    // NOTE: We need to return the image to the swapchain for presentation
    const current_image = self.get_current_swap_image();

    const wait_stage: vk.PipelineStageFlags = .{ .color_attachment_output_bit = true };
    const queue_submit_info = vk.SubmitInfo{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&current_image.image_available_semephore),
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&command_buffer.handle.handle),
        .signal_semaphore_count = 1,
        .p_signal_semaphores = @ptrCast(&current_image.queue_complete_semephore),
        .p_wait_dst_stage_mask = @ptrCast(&wait_stage),
    };

    try self.ctx.device.handle.queueSubmit(
        self.ctx.device.queues.graphics.handle,
        1,
        @ptrCast(&queue_submit_info),
        current_image.fence.handle,
    );

    command_buffer.update_submitted();

    const present_info = vk.PresentInfoKHR{
        .p_next = null,
        .p_results = null,
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&current_image.queue_complete_semephore),
        .swapchain_count = 1,
        .p_swapchains = @ptrCast(&self.handle),
        .p_image_indices = @ptrCast(&self.current_image_index),
    };

    const present_queue_handle = self.ctx.device.queues.present.handle;

    const result = self.ctx.device.handle.queuePresentKHR(present_queue_handle, &present_info) catch |err| switch (err) {
        error.OutOfDateKHR => .suboptimal_khr,
        else => |overflow| return overflow,
    };

    switch (result) {
        .success => {
            @branchHint(.likely);
        },
        .suboptimal_khr => return false,
        else => {
            return error.FailedToPresentSwapchain;
        },
    }

    // TODO: Understand the mechanics of this
    // LEFTOFF: How does this mechanic work of swapping semephores
    const next_image = self.ctx.device.handle.acquireNextImageKHR(
        self.handle,
        std.math.maxInt(u64),
        self.next_image_acquired,
        .null_handle,
    ) catch |err| switch (err) {
        error.OutOfDateKHR => T.LogicalDevice.AcquireNextImageKHRResult{ .result = .suboptimal_khr, .image_index = 0 },
        else => {
            self.ctx.log.err("Vulkan swapchain present failed getting next image: {s}", .{@errorName(err)});
            return false;
        },
    };

    switch (next_image.result) {
        .success => {},
        .suboptimal_khr => return false,
        else => unreachable,
    }

    std.mem.swap(
        vk.Semaphore,
        &self.images[next_image.image_index].image_available_semephore,
        &self.next_image_acquired,
    );
    self.current_image_index = next_image.image_index;
    return true;
}

pub fn get_current_swap_image(self: *Swapchain) *SwapImage {
    return &self.images[self.current_image_index];
}

const SwapImage = struct {
    image: vk.Image,
    // NOTE: In vulkan we work with image views
    view: vk.ImageView,
    image_available_semephore: vk.Semaphore,
    queue_complete_semephore: vk.Semaphore,
    fence: Fence,

    pub fn init(ctx: *const Context, image_handle: vk.Image, format: vk.Format) !SwapImage {
        const view = try Image.create_image_view(ctx, image_handle, format, .{ .color_bit = true });
        errdefer ctx.device.handle.destroyImageView(view, null);

        const image_available_sem = try ctx.device.handle.createSemaphore(&.{}, null);
        errdefer ctx.device.handle.destroySemaphore(image_available_sem, null);

        const render_complete_sem = try ctx.device.handle.createSemaphore(&.{}, null);
        errdefer ctx.device.handle.destroySemaphore(render_complete_sem, null);

        // NOTE: We create the fence in the signaled state indicating that this image has already been "rendered"
        // this is to prevent the application waiting indefinitely to get the first frame since you cant render to
        // a frame until it has been rendered to already and the fence is signaled
        const fence = try Fence.create(ctx, true);

        return SwapImage{
            .image = image_handle,
            .view = view,
            .image_available_semephore = image_available_sem,
            .queue_complete_semephore = render_complete_sem,
            .fence = fence,
        };
    }

    pub fn deinit(self: *SwapImage, ctx: *const Context) void {
        // NOTE: We wait for all the fences on all images to be unlocked before we start destroying images
        if (!self.fence.wait(ctx, std.math.maxInt(u64))) return;
        ctx.device.handle.destroyImageView(self.view, null);
        self.view = .null_handle;
        ctx.device.handle.destroySemaphore(self.image_available_semephore, null);
        self.image_available_semephore = .null_handle;
        ctx.device.handle.destroySemaphore(self.queue_complete_semephore, null);
        self.queue_complete_semephore = .null_handle;
        self.fence.destroy(ctx);
    }
};

fn init_swapchain_images(ctx: *const Context, swapchain: vk.SwapchainKHR, format: vk.Format) ![]SwapImage {
    // NOTE: Swapchain images are not created but gotten handles for
    const images = try ctx.device.handle.getSwapchainImagesAllocKHR(swapchain, ctx.allocator);
    defer ctx.allocator.free(images);

    const swap_images = try ctx.allocator.alloc(SwapImage, images.len);
    errdefer ctx.allocator.free(swap_images);

    var i: usize = 0;
    errdefer for (swap_images[0..i]) |*si| si.deinit(ctx);

    for (images) |image_handle| {
        swap_images[i] = try SwapImage.init(ctx, image_handle, format);
        i += 1;
    }

    return swap_images;
}

fn find_surface_format(ctx: *const Context) !vk.SurfaceFormatKHR {
    // NOTE: This should really not fail. All graphics cards should have this
    const preferred_format = vk.SurfaceFormatKHR{
        .format = .b8g8r8a8_unorm,
        .color_space = .srgb_nonlinear_khr,
    };

    const surface_formats = try ctx.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(
        ctx.device.pdev,
        ctx.surface,
        ctx.allocator,
    );
    defer ctx.allocator.free(surface_formats);

    for (surface_formats) |sfmt| {
        if (std.meta.eql(sfmt, preferred_format)) {
            return preferred_format;
        }
    }

    ctx.log.debug(
        "WARNING: Could not find the preffered format. Going with {s} and hoping for the best",
        .{@tagName(surface_formats[0].format)},
    );

    return surface_formats[0]; // There must always be at least one supported surface format
}

fn find_present_mode(ctx: *const Context) !vk.PresentModeKHR {
    const present_modes = try ctx.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(
        ctx.device.pdev,
        ctx.surface,
        ctx.allocator,
    );
    defer ctx.allocator.free(present_modes);

    // TODO: Get this from enginge/game settings
    const preferred = [_]vk.PresentModeKHR{
        .mailbox_khr,
        .immediate_khr,
    };

    for (preferred) |mode| {
        if (std.mem.indexOfScalar(vk.PresentModeKHR, present_modes, mode) != null) {
            ctx.log.info("Found and selected present mode: {s}\n", .{@tagName(mode)});
            return mode;
        }
    }

    // NOTE: If we dont find any of our preferred modes we return with fifo which should exist on all cards according
    // to the vulkan spec
    ctx.log.info("Could not find preferred presentation modes defaulting to fifo", .{});
    return .fifo_khr;
}

const std = @import("std");
