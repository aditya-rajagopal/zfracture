const m = @import("fr_core").math;
const vk = @import("vulkan");
const T = @import("types.zig");

const Context = @import("context.zig");
const CommandBuffer = @import("command_buffer.zig");

const RenderPass = @This();

handle: vk.RenderPass,
state: T.RenderPassState = .not_allocated,
surface_rect: m.Rect,
clear_colour: m.Colour,
depth: f32,
stencil: u32,

pub const Error = T.LogicalDevice.CreateRenderPassError;

pub fn create(
    ctx: *const Context,
    window_rect: m.Rect,
    clear_colour: m.Colour,
    depth: f32,
    stencil: u32,
) !RenderPass {
    // HACK: Hardcoding it to 2 for now but this will need to be configurable
    const attachment_count: u32 = 2;

    const colour_attachement = vk.AttachmentDescription{
        .format = ctx.swapchain.image_format.format, // TODO: Make this configurable
        .samples = .{ .@"1_bit" = true },
        // NOTE: This means that we want to clear the colour attachment at the start of the pass.
        // .dont_care = we dont care what the previous contents were
        // .load = we want to preserve the previous contents.
        .load_op = .clear,
        // NOTE: At the end of the renderpass we want to store the contents of the colour attachment
        .store_op = .store,
        // We are not using the stencil so we set the load and store as dont care.
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        // NOTE: Undefined means we dont expect any previous contents here. We are not loading anything from a previous pass.
        .initial_layout = .undefined,
        // NOTE: Since the output of this is what we are going to present we want it to be in the right format in memory
        .final_layout = .present_src_khr,
        .flags = .{},
    };

    // NOTE: The attachments live in the main render pass but the subpass need a reference to these.
    const colour_attachment_ref = vk.AttachmentReference{
        // This is going to be used as the colour attachment so thats what we are going to set the layout to.
        .layout = .color_attachment_optimal,
        // NOTE: This is the index in the attachments array. We will put the colour attachment in the first position
        .attachment = 0,
    };

    const depth_attachment = vk.AttachmentDescription{
        .format = ctx.swapchain.depth_format, // TODO: Make this configurable
        .samples = .{ .@"1_bit" = true },
        // We are going to clear the depth buffer at the start of the render pass.
        .load_op = .clear,
        .store_op = .dont_care,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        // NOTE: Undefined means we dont expect any previous contents here.
        .initial_layout = .undefined,
        .final_layout = .depth_stencil_attachment_optimal,
        .flags = .{},
    };

    const depth_attachment_ref = vk.AttachmentReference{
        .layout = .depth_stencil_attachment_optimal,
        // NOTE: This will go into the second position of the attachments array
        .attachment = 1,
    };

    const attachments = [_]vk.AttachmentDescription{ colour_attachement, depth_attachment };

    // HACK: We are temporarily hardcoding that we will only have 1 subpasss
    // NOTE: There are other attachments that can be set here.
    const subpass = vk.SubpassDescription{
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&colour_attachment_ref),
        .p_depth_stencil_attachment = @ptrCast(&depth_attachment_ref),
        //NOTE: Input attachment is used for input from a shader.
        .input_attachment_count = 0,
        .p_input_attachments = null,
        // NOTE: Resolve attachment is used to multisample the colour attachment
        .p_resolve_attachments = null,
        // NOTE: Preserve attachments are used to preserve the results for the next subass. We currently dont have any more
        .preserve_attachment_count = 0,
        .p_preserve_attachments = null,
        .flags = .{}
    };

    const subpass_dependency = vk.SubpassDependency{
        // This is the first subpass so there is no source subpass. The binding is external.
        .src_subpass = vk.SUBPASS_EXTERNAL,
        // Since this is the only subpass there is no destination,
        .dst_subpass = 0,
        // We are going to use the colour attachment output stage as both the source and destination stage
        .src_stage_mask = .{ .color_attachment_output_bit = true },
        .src_access_mask = .{},
        .dst_stage_mask = .{ .color_attachment_output_bit = true },
        // We want to be able to read and write to the colour attachment. Describes what memory access we want
        .dst_access_mask = .{ .color_attachment_read_bit = true, .color_attachment_write_bit = true },
        .dependency_flags = .{},
    };

    const create_info = vk.RenderPassCreateInfo{
        .attachment_count = attachment_count,
        .p_attachments = &attachments,
        .subpass_count = 1,
        .p_subpasses = @ptrCast(&subpass),
        .dependency_count = 1,
        .p_dependencies = @ptrCast(&subpass_dependency),
        .flags = .{},
        .p_next = null,
    };

    const render_pass = try ctx.device.handle.createRenderPass(&create_info, null);

    return RenderPass{
        .handle = render_pass,
        .surface_rect = window_rect,
        .clear_colour = clear_colour,
        .depth = depth,
        .stencil = stencil,
    };
}

pub fn destroy(self: *RenderPass, ctx: *const Context) void {
    if (self.handle != .null_handle) {
        ctx.device.handle.destroyRenderPass(self.handle, null);
        self.handle = .null_handle;
    }
}

pub fn begin(self: *RenderPass, command_buffer: *CommandBuffer, frame_buffer: vk.Framebuffer) void {
    // TODO: make this configurable
    var clear_values: [2]vk.ClearValue = undefined;
    @memset(clear_values[0..2], 0);
    clear_values[0].color.float_32 = self.clear_colour;
    clear_values[1].depth_stencil.depth = self.depth;
    clear_values[1].depth_stencil.stencil = self.stencil;

    const begin_info = vk.RenderPassBeginInfo{
        .render_pass = self.handle,
        .framebuffer = frame_buffer,
        .render_area = .{
            .offset = .{
                .x = self.surface_rect[0],
                .y = self.surface_rect[1],
            },
            .extent = .{
                .width = self.surface_rect[2],
                .height = self.surface_rect[3],
            },
        },
        .clear_value_count = 2,
        .p_clear_values = &clear_values,
    };

    command_buffer.handle.beginRenderPass(&begin_info, .@"inline");
    command_buffer.state = .in_render_pass;
}

pub fn end(self: *RenderPass, command_buffer: *CommandBuffer) void {
    _ = self;
    command_buffer.handle.endRenderPass();
    command_buffer.state = .recording;
}
