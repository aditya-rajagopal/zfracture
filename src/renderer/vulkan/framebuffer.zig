const vk = @import("vulkan");
const T = @import("types.zig");

const Context = @import("context.zig");
const RenderPass = @import("renderpass.zig");

const Framebuffer = @This();

/// The handle to the vulkan framebuffer
handle: vk.Framebuffer,
/// The attachments of the framebuffer
attachments: []vk.ImageView,
/// The renderpass that the framebuffer is associated with
renderpass: *const RenderPass,
/// The extent of the framebuffer
extent: vk.Extent2D,

pub const Error = T.LogicalDevice.CreateFramebufferError || std.mem.Allocator.Error;

pub fn create(
    ctx: *const Context,
    /// The renderpass that the framebuffer is associated with
    renderpass: *const RenderPass,
    /// The extent of the framebuffer
    extent: vk.Extent2D,
    /// The attachments of the framebuffer
    attachments: []const vk.ImageView,
) Error!Framebuffer {
    // TODO: Make this not a random heap allocation if possible
    const attachments_cpy = try ctx.allocator.dupe(vk.ImageView, attachments);
    const create_info = vk.FramebufferCreateInfo{
        .render_pass = renderpass.handle,
        .flags = .{},
        .width = extent.width,
        .height = extent.height,
        .layers = 1,
        .attachment_count = @truncate(attachments.len),
        .p_attachments = attachments_cpy.ptr,
    };

    const handle = try ctx.device.handle.createFramebuffer(&create_info, null);
    return .{
        .handle = handle,
        .attachments = attachments_cpy,
        .renderpass = renderpass,
        .extent = extent,
    };
}

pub fn destroy(self: *Framebuffer, ctx: *const Context) void {
    if (self.handle != .null_handle) {
        ctx.device.handle.destroyFramebuffer(self.handle, null);
        self.handle = .null_handle;
        ctx.allocator.free(self.attachments);
        self.attachments.len = 0;
    }
}

const std = @import("std");
