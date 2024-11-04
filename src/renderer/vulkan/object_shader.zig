const vk = @import("vulkan");
const Context = @import("context.zig");
const builtin = @import("shaders").builtin;
const T = @import("types.zig");
const m = @import("fr_core").math;

const Pipeline = @import("pipeline.zig");
const Buffer = @import("buffer.zig");

// vertex, frag
pub const OBJECT_SHADER_STAGE_COUNT = 2;
pub const MAX_DESCRIPTOR_SETS = 5;

const ObjectShader = @This();

stages: [OBJECT_SHADER_STAGE_COUNT]ShaderStage,

// This is the actual buffer that holds our uniforms. And this buffer is attached to the descriptor set
global_uniform_buffer: Buffer,
global_uo: T.GlobalUO,
global_descriptor_pool: vk.DescriptorPool,
global_descriptor_set_layout: vk.DescriptorSetLayout,
// NOTE: one per frame with 3 max for triple buffering
global_descriptor_sets: [MAX_DESCRIPTOR_SETS]vk.DescriptorSet,

pipeline: Pipeline,

pub const ShaderStage = struct {
    create_info: vk.ShaderModuleCreateInfo,
    handle: vk.ShaderModule,
    stage_create_info: vk.PipelineShaderStageCreateInfo,
};

pub const Error = error{UnableToLoadShader} || Pipeline.Error;

pub fn create(ctx: *const Context) Error!ObjectShader {
    const stage_types = [OBJECT_SHADER_STAGE_COUNT]vk.ShaderStageFlags{
        .{ .vertex_bit = true },
        .{ .fragment_bit = true },
    };

    var out_shader: ObjectShader = undefined;

    var i: usize = 0;
    errdefer {
        for (0..i) |index| {
            ctx.device.handle.destroyShaderModule(out_shader.stages[index].handle, null);
        }
    }

    while (i < OBJECT_SHADER_STAGE_COUNT) : (i += 1) {
        out_shader.stages[i] = create_shader_module(ctx, stage_types[i], shaders[i]) catch {
            ctx.log.err("Unable to create {s} shader module for Builtin.ObjectShader", .{@tagName(shaders[i].tag)});
            return error.UnableToLoadShader;
        };
    }

    // INFO: Global Descriptiors
    // NOTE: Descriptors are not created bu allocated from a pool
    // A Descriptor Set is a grouping of uniforms. That is what the set=0 in the vertex shader means

    const global_ubo_layout_binding = vk.DescriptorSetLayoutBinding{
        .binding = 0, // This means this is the first binding. this is what binding=0 in the vert shader indicates
        .descriptor_count = 1, // We only have 1 object
        .descriptor_type = .uniform_buffer,
        .p_immutable_samplers = null,
        // This means this uniform is attached to the vertex shader
        .stage_flags = .{ .vertex_bit = true },
    };

    // NOTE: We are only binding one ubo. If we have more we can add more
    const global_layout_info = vk.DescriptorSetLayoutCreateInfo{
        .binding_count = 1,
        .p_bindings = @ptrCast(&global_ubo_layout_binding),
    };

    out_shader.global_descriptor_set_layout = ctx.device.handle.createDescriptorSetLayout(&global_layout_info, null) catch unreachable;

    // INFO: The global Descriptor pool
    const global_pool_size = vk.DescriptorPoolSize{
        .type = .uniform_buffer,
        // NOTE: We pass the same number as the number of images we have in the swapchain. So we make one set for each
        // image
        .descriptor_count = MAX_DESCRIPTOR_SETS,
    };

    const global_pool_info = vk.DescriptorPoolCreateInfo{
        .pool_size_count = 1,
        .p_pool_sizes = @ptrCast(&global_pool_size),
        .max_sets = MAX_DESCRIPTOR_SETS,
    };

    out_shader.global_descriptor_pool = ctx.device.handle.createDescriptorPool(&global_pool_info, null) catch unreachable;

    // Create the pipeline
    const viewport = vk.Viewport{
        .x = 0.0,
        .y = @floatFromInt(ctx.framebuffer_extent.height),
        .width = @floatFromInt(ctx.framebuffer_extent.width),
        .height = -@as(f32, @floatFromInt(ctx.framebuffer_extent.width)),
        .min_depth = 0.0,
        .max_depth = 1.0,
    };

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = ctx.framebuffer_extent,
    };

    // Atributes
    // TODO: Make this configurable
    var offset: u64 = 0;
    const attribute_count: u32 = 1;

    var attribute_descriptions: [attribute_count]vk.VertexInputAttributeDescription = undefined;

    const formats = [attribute_count]vk.Format{
        // The first element in the vertex is the position and it is a f32 vec3 so we use specify this is the format
        // it says colours but this is basically the vec3
        .r32g32b32_sfloat,
    };

    const sizes = [attribute_count]u64{
        @sizeOf(m.Vec3.Array),
    };

    for (0..attribute_count) |index| {
        attribute_descriptions[index].binding = 0;
        attribute_descriptions[index].location = @truncate(index); // The attribute location. This maps to the location index in the shader
        attribute_descriptions[index].format = formats[index];
        attribute_descriptions[index].offset = @truncate(offset);
        offset += sizes[index];
    }

    // INFO: Descriptor layouts

    // NOTE: We only have 1 for now
    const descriptor_set_layout_count: usize = 1;
    const layouts = [descriptor_set_layout_count]vk.DescriptorSetLayout{
        out_shader.global_descriptor_set_layout,
    };

    var stage_create_info: [OBJECT_SHADER_STAGE_COUNT]vk.PipelineShaderStageCreateInfo = undefined;
    for (stage_create_info[0..OBJECT_SHADER_STAGE_COUNT], 0..) |*info, index| {
        // info.s_type = out_shader.stages[i].stage_create_info.s_type;
        info.* = out_shader.stages[index].stage_create_info;
    }

    out_shader.pipeline = try Pipeline.create(
        ctx,
        ctx.main_render_pass.handle,
        attribute_descriptions[0..attribute_count],
        layouts[0..descriptor_set_layout_count],
        stage_create_info[0..OBJECT_SHADER_STAGE_COUNT],
        viewport,
        scissor,
        false,
    );

    // TODO: NOt all devices have the ability to have device local + host visible. Check for this support
    out_shader.global_uniform_buffer = Buffer.create(
        ctx,
        @sizeOf(T.GlobalUO) * MAX_DESCRIPTOR_SETS,
        // The buffer is the destination of writing the uniform data
        .{ .transfer_dst_bit = true, .uniform_buffer_bit = true },
        // The buffer is in the device and not CPU. But we can upload to it directly so we set host visible and coherent
        .{ .device_local_bit = true, .host_visible_bit = true, .host_coherent_bit = true },
        true,
    ) catch |err| {
        ctx.log.err("Vulkan buffer creation frailed for global_uniform_buffer with error: {s}", .{@errorName(err)});
        return error.UnableToLoadShader;
    };

    // Allocate Descriptor Sets
    // NOTE: We are using the same layout for all 3 sets which are associated with each swapchain image
    const global_layouts = [_]vk.DescriptorSetLayout{
        out_shader.global_descriptor_set_layout,
        // out_shader.global_descriptor_set_layout,
        // out_shader.global_descriptor_set_layout,
    } ** MAX_DESCRIPTOR_SETS;

    const alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = out_shader.global_descriptor_pool,
        .descriptor_set_count = MAX_DESCRIPTOR_SETS,
        .p_set_layouts = @ptrCast(&global_layouts[0]),
    };

    ctx.device.handle.allocateDescriptorSets(
        &alloc_info,
        @ptrCast(&out_shader.global_descriptor_sets[0]),
    ) catch unreachable;

    return out_shader;
}

pub fn destroy(self: *ObjectShader, ctx: *const Context) void {
    const device = ctx.device.handle;

    // device.freeDescriptorSets(self.global_descriptor_pool, 3, @ptrCast(&self.global_descriptor_sets[0])) catch unreachable;

    self.global_uniform_buffer.destroy(ctx);

    self.pipeline.destroy(ctx);

    device.destroyDescriptorPool(self.global_descriptor_pool, null);

    device.destroyDescriptorSetLayout(self.global_descriptor_set_layout, null);

    for (&self.stages) |*stage| {
        device.destroyShaderModule(stage.handle, null);
        stage.handle = .null_handle;
    }
}

pub fn use(self: *const ObjectShader, ctx: *const Context) void {
    const image_index = ctx.swapchain.current_image_index;
    self.pipeline.bind(ctx.graphics_command_buffers[image_index], .graphics);
}

pub fn update_global_state(self: *ObjectShader, ctx: *const Context) void {
    const image_index = ctx.swapchain.current_image_index;
    const command_buffer = ctx.graphics_command_buffers[image_index].handle;
    const global_descriptor = self.global_descriptor_sets[image_index];

    // 2. Configure the descriptor for the given index.
    const range: u32 = @sizeOf(T.GlobalUO);
    const offset: u64 = @sizeOf(T.GlobalUO) * image_index;

    // 3. Upload data to the buffer
    self.global_uniform_buffer.load_data(offset, range, .{}, ctx, @ptrCast(&self.global_uo));

    // 4. We need to tell the descriptor that the data has changed.
    const buffer_info = vk.DescriptorBufferInfo{
        .offset = offset,
        .range = range,
        .buffer = self.global_uniform_buffer.handle,
    };

    const descriptor_write = vk.WriteDescriptorSet{
        .dst_set = global_descriptor,
        .dst_binding = 0,
        .dst_array_element = 0,
        .descriptor_type = .uniform_buffer,
        .descriptor_count = 1,
        .p_buffer_info = @ptrCast(&buffer_info),
        .p_texel_buffer_view = @ptrCast(&[_]vk.BufferView{}),
        .p_image_info = @ptrCast(&[_]vk.DescriptorImageInfo{}),
    };

    ctx.device.handle.updateDescriptorSets(1, @ptrCast(&descriptor_write), 0, null);

    // 1. Bind global descriptor set that needs to be updated
    command_buffer.bindDescriptorSets(
        .graphics,
        self.pipeline.layout,
        0,
        1,
        @ptrCast(&global_descriptor),
        0,
        null,
    );
}

pub fn update_object(self: *ObjectShader, ctx: *const Context, model: m.Transform) void {
    const image_index = ctx.swapchain.current_image_index;
    const command_buffer = ctx.graphics_command_buffers[image_index].handle;

    // NOTE: Push constants are used for constantly changing data. We dont need to create a descriptor set for this
    // They have a size limitation. THey have a limit for 128 bytes. Because the driver is guarnteed to have atleast 128
    // but there is no guarentee there will be more.
    command_buffer.pushConstants(
        self.pipeline.layout,
        .{ .vertex_bit = true },
        0,
        @sizeOf(m.Transform),
        @ptrCast(&model),
    );
}

fn create_shader_module(
    ctx: *const Context,
    stage_type: vk.ShaderStageFlags,
    shader: Shader,
) T.LogicalDevice.CreateShaderModuleError!ShaderStage {
    const create_info = vk.ShaderModuleCreateInfo{
        .p_code = @alignCast(@ptrCast(shader.binary)),
        .code_size = shader.binary.len,
    };
    const shader_module = try ctx.device.handle.createShaderModule(&create_info, null);

    return ShaderStage{
        .stage_create_info = vk.PipelineShaderStageCreateInfo{
            .stage = stage_type,
            .module = shader_module,
            .p_name = "main", // NOTE: THe entry point of the shader. Can try to make this customizable
        },
        .handle = shader_module,
        .create_info = create_info,
    };
}

pub const ShaderType = enum {
    vertex,
    fragment,
};

pub const Shader = struct {
    tag: ShaderType,
    binary: []align(4) const u8,
};

const shaders: []const Shader = &.{
    .{ .tag = .vertex, .binary = builtin.ObjectShader.vert },
    .{ .tag = .fragment, .binary = builtin.ObjectShader.frag },
};

const std = @import("std");
