const vk = @import("vulkan");
const T = @import("types.zig");

const Context = @import("context.zig");
const CommandBuffer = @import("command_buffer.zig");

pub const Pipeline = @This();

handle: vk.Pipeline = .null_handle,
layout: vk.PipelineLayout = .null_handle,

pub const Error =
    error{PipelineCreationFailed} ||
    T.LogicalDevice.CreatePipelineLayoutError ||
    T.LogicalDevice.CreateGraphicsPipelinesError;

pub fn create(
    ctx: *const Context,
    renderpass: vk.RenderPass,
    attributes: []const vk.VertexInputAttributeDescription,
    descriptor_set_layouts: ?[]const vk.DescriptorSetLayout,
    stages: []const vk.PipelineShaderStageCreateInfo,
    viewport: vk.Viewport,
    scissor: vk.Rect2D,
    is_wireframe: bool,
) Error!Pipeline {

    // NOTE: this is stating that this is the initial viewport and scissor of the pipeline. But it can be changed
    // By the dynamic state.
    const viewport_state = vk.PipelineViewportStateCreateInfo{
        .viewport_count = 1,
        .p_viewports = @ptrCast(&viewport),
        .scissor_count = 1,
        .p_scissors = @ptrCast(&scissor),
    };

    // NOTE: pipelines are immutable once created. So if you want a different polygon mode you need to create a new pipeline
    const raster_create_info = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = vk.FALSE,
        .rasterizer_discard_enable = vk.FALSE,
        .polygon_mode = if (is_wireframe) .line else .fill,
        .line_width = 1.0,
        .cull_mode = .{ .back_bit = true },
        // NOTE: Describing which face is going to be the front face. A triangle with positive area is considered
        // front face when set to counter clockwise. Mostly the order in which the vertices are drawn
        // https://registry.khronos.org/vulkan/specs/1.3-extensions/html/vkspec.html#VkFrontFace
        .front_face = .counter_clockwise,
        // NOTE: We dont really want to bias the depth value
        .depth_bias_enable = vk.FALSE,
        .depth_bias_constant_factor = 0.0,
        .depth_bias_clamp = 0.0,
        .depth_bias_slope_factor = 0.0,
    };

    // NOTE: We are not using this so just setting it to use single sample
    const multisample_create_info = vk.PipelineMultisampleStateCreateInfo{
        .sample_shading_enable = vk.FALSE,
        .rasterization_samples = .{ .@"1_bit" = true },
        .min_sample_shading = 1.0,
        .p_sample_mask = null,
        .alpha_to_coverage_enable = vk.FALSE,
        .alpha_to_one_enable = vk.FALSE,
    };

    // NOTE: We are enabling depth testing and using the less than op to compare depths i.e the point closer will be
    // rendered
    const stencil_op_state: vk.StencilOpState = std.mem.zeroes(vk.StencilOpState);
    const depth_stencil = vk.PipelineDepthStencilStateCreateInfo{
        .depth_test_enable = vk.TRUE,
        // Enabling writing to the depth buffer
        .depth_write_enable = vk.TRUE,
        .depth_compare_op = .less,
        .depth_bounds_test_enable = vk.FALSE,
        .stencil_test_enable = vk.FALSE,
        .front = stencil_op_state,
        .back = stencil_op_state,
        .min_depth_bounds = 0,
        .max_depth_bounds = 0,
    };

    const colour_blend_attachment_state = vk.PipelineColorBlendAttachmentState{
        .blend_enable = vk.TRUE,
        .src_color_blend_factor = .src_alpha,
        .dst_color_blend_factor = .one_minus_src_alpha,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .src_alpha,
        .dst_alpha_blend_factor = .one_minus_src_alpha,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    };

    const colour_blend_state = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = vk.FALSE,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&colour_blend_attachment_state),
        .blend_constants = .{ 0, 0, 0, 0 },
    };

    // NOTE: These are the states you can change dynamically once the pipeline has been created. To change something not
    // declared here we would have to create a new pipeline. We need these when we resize the window
    const dynamic_state_count: u32 = 3;
    const dynamic_states = [dynamic_state_count]vk.DynamicState{ .viewport, .scissor, .line_width };

    const dynamic_state_create_info = vk.PipelineDynamicStateCreateInfo{
        .dynamic_state_count = dynamic_state_count,
        .p_dynamic_states = @ptrCast(&dynamic_states),
    };

    const binding_description = vk.VertexInputBindingDescription{
        // The binding location in the shader?
        .binding = 0,
        // The stride to move to the next vertex
        .stride = @sizeOf(T.Vertex3D),
        // Move to the next vertex or instance
        .input_rate = .vertex,
    };

    const vertex_input_info = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = @ptrCast(&binding_description),
        .vertex_attribute_description_count = @truncate(attributes.len),
        .p_vertex_attribute_descriptions = @ptrCast(attributes.ptr),
    };

    const input_assembly = vk.PipelineInputAssemblyStateCreateInfo{
        // Describes how to interpret the lsit of verticies. This means we are providing a list of triangles where 3
        // consecutive indices are seperate triangles as opposed to .triangle_strip which will have triangles that share
        // edges. .triangle_fan will have all triangles share a vertex
        .topology = .triangle_list,
        // NOTE: This is for indexed draws and allows restarting the assembly when it encounters something like 0xFF
        .primitive_restart_enable = vk.FALSE,
    };

    const length = if (descriptor_set_layouts) |d| d.len else 0;
    const layouts = if (descriptor_set_layouts) |d| d.ptr else null;
    const pipeline_layout_create_info = vk.PipelineLayoutCreateInfo{
        .set_layout_count = @truncate(length),
        .p_set_layouts = layouts,
    };

    const pipeline_layout = try ctx.device.handle.createPipelineLayout(&pipeline_layout_create_info, null);
    errdefer ctx.device.handle.destroyPipelineLayout(pipeline_layout, null);

    const pipeline_create_info = vk.GraphicsPipelineCreateInfo{
        // THe shader stages
        .s_type = .graphics_pipeline_create_info,
        .stage_count = @truncate(stages.len),
        .p_stages = @ptrCast(stages.ptr),
        .p_vertex_input_state = &vertex_input_info,
        .p_input_assembly_state = &input_assembly,
        .p_viewport_state = &viewport_state,
        .p_rasterization_state = &raster_create_info,
        .p_multisample_state = &multisample_create_info,
        .p_color_blend_state = &colour_blend_state,
        .p_tessellation_state = null,
        .p_depth_stencil_state = &depth_stencil,
        .p_dynamic_state = &dynamic_state_create_info,
        .layout = pipeline_layout,
        .render_pass = renderpass,
        .subpass = 0,
        .base_pipeline_index = -1,
        .base_pipeline_handle = .null_handle,
    };

    var pipeline: vk.Pipeline = .null_handle;
    const result = try ctx.device.handle.createGraphicsPipelines(
        .null_handle,
        1,
        @ptrCast(&pipeline_create_info),
        null,
        @ptrCast(&pipeline),
    );

    if (result != .success) {
        ctx.log.err("Pipeline creation failed with result: {s}", .{@tagName(result)});
        return error.PipelineCreationFailed;
    }

    return .{
        .handle = pipeline,
        .layout = pipeline_layout,
    };
}

pub fn destroy(self: *Pipeline, ctx: *const Context) void {
    if (self.handle != .null_handle) {
        ctx.device.handle.destroyPipeline(self.handle, null);
        self.handle = .null_handle;
    }

    if (self.layout != .null_handle) {
        ctx.device.handle.destroyPipelineLayout(self.layout, null);
        self.layout = .null_handle;
    }
}

// TODO: This should move to the command buffer
/// Any command that runs while this pipeline is bound will be executed against that pipeline
pub fn bind(self: Pipeline, command_buffer: CommandBuffer, bind_point: vk.PipelineBindPoint) void {
    command_buffer.handle.bindPipeline(bind_point, &self.handle);
}

const std = @import("std");
