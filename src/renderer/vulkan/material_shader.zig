const vk = @import("vulkan");
const Context = @import("context.zig");
const builtin = @import("shaders").builtin;
const T = @import("types.zig");
const core = @import("fr_core");
const m = core.math;
const Texture = core.resource.Texture;

const Pipeline = @import("pipeline.zig");
const Buffer = @import("buffer.zig");

// vertex, frag
pub const MATERIAL_SHADER_STAGE_COUNT = 2;
pub const MAX_DESCRIPTOR_SETS = 3;
pub const NUM_SAMPLERS = 1;

const MaterialShader = @This();

stages: [MATERIAL_SHADER_STAGE_COUNT]ShaderStage,

// This is the actual buffer that holds our uniforms. And this buffer is attached to the descriptor set
global_uniform_buffer: Buffer,
global_uo: T.GlobalUO,
global_descriptor_pool: vk.DescriptorPool,
global_descriptor_set_layout: vk.DescriptorSetLayout,
// NOTE: one per frame with 3 max for triple buffering
global_descriptor_sets: [MAX_DESCRIPTOR_SETS]vk.DescriptorSet,

// NOTE: These are for the per object uniforms
local_descriptor_set_layout: vk.DescriptorSetLayout,
local_descriptor_pool: vk.DescriptorPool,
// This will store the uniforms for all the objects
local_uniform_buffer: Buffer,
// TODO: Make this a free list
object_free_list: u32,

// TODO: Make this dynamic
object_states: [T.MAX_MATERIAL_INSTANCES]T.ObjectShaderObjectState,

pipeline: Pipeline,

default_diffuse: *const Texture,

// HACK: Just to see something
accumulator: f32 = 0.0,

pub const ShaderStage = struct {
    create_info: vk.ShaderModuleCreateInfo,
    handle: vk.ShaderModule,
    stage_create_info: vk.PipelineShaderStageCreateInfo,
};

pub const Error = error{UnableToLoadShader} || Pipeline.Error;

pub fn create(ctx: *const Context, default_diffuse: *const Texture) Error!MaterialShader {
    const device = ctx.device.handle;
    const stage_types = [MATERIAL_SHADER_STAGE_COUNT]vk.ShaderStageFlags{
        .{ .vertex_bit = true },
        .{ .fragment_bit = true },
    };

    var out_shader: MaterialShader = undefined;

    var i: usize = 0;
    errdefer {
        for (0..i) |index| {
            ctx.device.handle.destroyShaderModule(out_shader.stages[index].handle, null);
        }
    }

    while (i < MATERIAL_SHADER_STAGE_COUNT) : (i += 1) {
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
    errdefer device.destroyDescriptorSetLayout(out_shader.global_descriptor_set_layout, null);

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
    errdefer device.destroyDescriptorPool(out_shader.global_descriptor_pool, null);

    // INFO: Local Descriptors

    const local_descriptor_types = [T.MATERIAL_SHADER_DESCRIPTOR_COUNT]vk.DescriptorType{
        .uniform_buffer, // binding = 0 is the uniform buffer
        .combined_image_sampler, // binding = 1 is the diffuse sample layout
    };

    var local_bindings: [T.MATERIAL_SHADER_DESCRIPTOR_COUNT]vk.DescriptorSetLayoutBinding = undefined;
    for (&local_bindings, 0..) |*binding, index| {
        binding.* = vk.DescriptorSetLayoutBinding{
            .binding = @truncate(index),
            .descriptor_count = 1,
            .descriptor_type = local_descriptor_types[index],
            .stage_flags = .{ .fragment_bit = true },
            .p_immutable_samplers = null,
        };
    }

    const local_layout_info = vk.DescriptorSetLayoutCreateInfo{
        .binding_count = T.MATERIAL_SHADER_DESCRIPTOR_COUNT,
        .p_bindings = @ptrCast(&local_bindings[0]),
    };

    out_shader.local_descriptor_set_layout = ctx.device.handle.createDescriptorSetLayout(&local_layout_info, null) catch unreachable;
    errdefer device.destroyDescriptorSetLayout(out_shader.local_descriptor_set_layout, null);

    const local_descriptor_pool_size = [T.MATERIAL_SHADER_DESCRIPTOR_COUNT]vk.DescriptorPoolSize{
        .{
            .type = .uniform_buffer,
            .descriptor_count = T.MAX_OBJECTS,
        },
        .{
            .type = .combined_image_sampler,
            .descriptor_count = T.MAX_OBJECTS * NUM_SAMPLERS,
        },
    };

    const local_pool_create_info = vk.DescriptorPoolCreateInfo{
        .max_sets = T.MAX_MATERIAL_INSTANCES * MAX_DESCRIPTOR_SETS,
        .pool_size_count = T.MATERIAL_SHADER_DESCRIPTOR_COUNT,
        .p_pool_sizes = @ptrCast(&local_descriptor_pool_size),
    };

    out_shader.local_descriptor_pool = ctx.device.handle.createDescriptorPool(&local_pool_create_info, null) catch unreachable;
    errdefer device.destroyDescriptorPool(out_shader.local_descriptor_pool, null);

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
    const attribute_count: u32 = 2;

    var attribute_descriptions: [attribute_count]vk.VertexInputAttributeDescription = undefined;

    const formats = [attribute_count]vk.Format{
        // The first element in the vertex is the position and it is a f32 vec3 so we use specify this is the format
        // it says colours but this is basically the vec3
        .r32g32b32_sfloat,
        // Next is texture coords
        .r32g32_sfloat,
    };

    const sizes = [attribute_count]u64{
        @sizeOf(m.Vec3.Array),
        @sizeOf(m.Vec2.Array),
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
    const descriptor_set_layout_count: usize = 2;
    const layouts = [descriptor_set_layout_count]vk.DescriptorSetLayout{
        out_shader.global_descriptor_set_layout,
        out_shader.local_descriptor_set_layout,
    };

    var stage_create_info: [MATERIAL_SHADER_STAGE_COUNT]vk.PipelineShaderStageCreateInfo = undefined;
    for (stage_create_info[0..MATERIAL_SHADER_STAGE_COUNT], 0..) |*info, index| {
        // info.s_type = out_shader.stages[i].stage_create_info.s_type;
        info.* = out_shader.stages[index].stage_create_info;
    }

    out_shader.pipeline = try Pipeline.create(
        ctx,
        ctx.main_render_pass.handle,
        attribute_descriptions[0..attribute_count],
        layouts[0..descriptor_set_layout_count],
        stage_create_info[0..MATERIAL_SHADER_STAGE_COUNT],
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
        .{
            .device_local_bit = ctx.device.supports_device_local_host_visable,
            .host_visible_bit = true,
            .host_coherent_bit = true,
        },
        true,
    ) catch |err| {
        ctx.log.err("Vulkan buffer creation frailed for global_uniform_buffer with error: {s}", .{@errorName(err)});
        return error.UnableToLoadShader;
    };
    errdefer out_shader.global_uniform_buffer.destroy(ctx);

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

    out_shader.local_uniform_buffer = Buffer.create(
        ctx,
        @sizeOf(T.ObjectUO) * T.MAX_MATERIAL_INSTANCES * MAX_DESCRIPTOR_SETS,
        .{ .transfer_dst_bit = true, .uniform_buffer_bit = true },
        // device_local_bit maybe not needed since this is updated every frame
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        true,
    ) catch |err| {
        ctx.log.err("Vulkan buffer creation frailed for local_uniform_buffer with error: {s}", .{@errorName(err)});
        return error.UnableToLoadShader;
    };

    out_shader.accumulator = 0.0;
    out_shader.object_free_list = 0;
    out_shader.default_diffuse = default_diffuse;

    return out_shader;
}

pub fn destroy(self: *MaterialShader, ctx: *const Context) void {
    const device = ctx.device.handle;

    // device.freeDescriptorSets(self.global_descriptor_pool, 3, @ptrCast(&self.global_descriptor_sets[0])) catch unreachable;

    self.local_uniform_buffer.destroy(ctx);

    self.global_uniform_buffer.destroy(ctx);

    self.pipeline.destroy(ctx);

    device.destroyDescriptorPool(self.local_descriptor_pool, null);

    device.destroyDescriptorSetLayout(self.local_descriptor_set_layout, null);

    device.destroyDescriptorPool(self.global_descriptor_pool, null);

    device.destroyDescriptorSetLayout(self.global_descriptor_set_layout, null);

    for (&self.stages) |*stage| {
        device.destroyShaderModule(stage.handle, null);
        stage.handle = .null_handle;
    }
}

pub fn use(self: *const MaterialShader, ctx: *const Context) void {
    const image_index = ctx.swapchain.current_image_index;
    self.pipeline.bind(ctx.graphics_command_buffers[image_index], .graphics);
}

pub fn update_global_state(self: *MaterialShader, ctx: *const Context) void {
    const image_index = ctx.swapchain.current_image_index;
    const command_buffer = ctx.graphics_command_buffers[image_index].handle;
    const global_descriptor = self.global_descriptor_sets[image_index];

    assert(image_index < MAX_DESCRIPTOR_SETS);

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

pub fn update_object(self: *MaterialShader, ctx: *const Context, geometry: T.RenderData) void {
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
        @ptrCast(&geometry.model),
    );

    assert(@intFromEnum(geometry.object_id) < self.object_states.len);

    const object_state = &self.object_states[@intFromEnum(geometry.object_id)];
    const descriptor_set = object_state.descriptor_sets[image_index];

    // We need to check if htis needs to be done
    var descriptor_writes: [T.MATERIAL_SHADER_DESCRIPTOR_COUNT]vk.WriteDescriptorSet = undefined;
    var descriptor_count: u32 = 0;
    var descriptor_index: u32 = 0;

    // Descriptor 0 is the uniform buffer
    const range: u64 = @sizeOf(T.ObjectUO);
    // We have location in the buffer per descriptor set per material instance
    // So the offset in memory will be id * MAX_SETS + image_index;
    const offset: u64 = @sizeOf(T.ObjectUO) * (@intFromEnum(geometry.object_id) * MAX_DESCRIPTOR_SETS + image_index);

    // HACK: JUst to see if the local buffer upload is working
    var object_uo: T.ObjectUO = undefined;
    self.accumulator += ctx.frame_delta_time;
    const s = (@sin(self.accumulator * m.pi) + 1.0) / 2.0;
    object_uo.diffuse_colour = m.vec4s(s, s, s, 1.0);

    self.local_uniform_buffer.load_data(offset, range, .{}, ctx, @ptrCast(&object_uo));

    if (object_state.descriptor_states[descriptor_index].generations[image_index] == .null_handle) {
        const buffer_info = vk.DescriptorBufferInfo{
            .buffer = self.local_uniform_buffer.handle,
            .range = range,
            .offset = offset,
        };

        const descriptor = vk.WriteDescriptorSet{
            .dst_set = descriptor_set,
            .dst_binding = descriptor_index,
            .dst_array_element = 0,
            .descriptor_type = .uniform_buffer,
            .descriptor_count = 1,
            .p_buffer_info = @ptrCast(&buffer_info),
            .p_texel_buffer_view = @ptrCast(&[_]vk.BufferView{}),
            .p_image_info = @ptrCast(&[_]vk.DescriptorImageInfo{}),
        };
        descriptor_writes[descriptor_count] = descriptor;
        descriptor_count += 1;

        // NOTE: We only need to do this once because once the memory is mapped we just need to update the buffer
        object_state.descriptor_states[descriptor_index].generations[image_index] = @enumFromInt(1);
    }
    descriptor_index += 1;

    var image_infos: [NUM_SAMPLERS]vk.DescriptorImageInfo = undefined;

    for (&image_infos, 0..) |*info, i| {
        var texture: ?*const Texture = geometry.textures[i];
        const generation = &object_state.descriptor_states[descriptor_index].generations[image_index];

        if (texture) |t| {
            if (t.id == .null_handle or t.generation == .null_handle) {
                // TODO: Handle other texture maps
                texture = self.default_diffuse;
                generation.* = .null_handle;
            }
        }

        if (texture) |t| {
            if (generation.* != t.generation or generation.* == .null_handle) {
                const internal_data = t.data.as_const(T.vkTextureData);
                // We expect this to be only used by the shader
                info.image_layout = .shader_read_only_optimal;
                info.image_view = internal_data.image.view;
                info.sampler = internal_data.sampler;

                const descriptor = vk.WriteDescriptorSet{
                    // Same descriptor set for all the uniforms relate to this object
                    .dst_set = descriptor_set,
                    // THis is in position 1
                    .dst_binding = descriptor_index,
                    .dst_array_element = 0,
                    .descriptor_count = 1,
                    .descriptor_type = .combined_image_sampler,
                    .p_image_info = @ptrCast(info),
                    .p_buffer_info = @ptrCast(&[_]vk.DescriptorBufferInfo{}),
                    .p_texel_buffer_view = @ptrCast(&[_]vk.BufferView{}),
                };
                descriptor_writes[descriptor_count] = descriptor;
                descriptor_count += 1;

                if (t.generation != .null_handle) {
                    generation.* = t.generation;
                }
                descriptor_index += 1;
            }
        }
    }

    if (descriptor_count > 0) {
        // INFO: if we have any descriptors that are invalid and need to be mapped
        ctx.device.handle.updateDescriptorSets(descriptor_count, @ptrCast(&descriptor_writes), 0, null);
    }

    command_buffer.bindDescriptorSets(.graphics, self.pipeline.layout, 1, 1, @ptrCast(&descriptor_set), 0, null);
}

pub fn acquire_resources(self: *MaterialShader, ctx: *const Context) T.MaterialInstanceID {
    const id = self.object_free_list;
    self.object_free_list += 1;
    assert(self.object_free_list < T.MAX_MATERIAL_INSTANCES);

    // Reset the object state
    const object_state = &self.object_states[id];
    for (&object_state.descriptor_states) |*state| {
        for (&state.generations) |*gen| {
            gen.* = .null_handle;
        }
    }

    // Allocate the descriptor sets
    const layouts = [_]vk.DescriptorSetLayout{
        self.local_descriptor_set_layout,
    } ** MAX_DESCRIPTOR_SETS;

    const alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = self.local_descriptor_pool,
        .descriptor_set_count = MAX_DESCRIPTOR_SETS,
        .p_set_layouts = @ptrCast(&layouts[0]),
    };

    ctx.device.handle.allocateDescriptorSets(
        &alloc_info,
        @ptrCast(&object_state.descriptor_sets[0]),
    ) catch |err| {
        @branchHint(.cold);
        ctx.log.err("Unable to allocate descriptor sets for object id: {d} with error: {s}", .{ id, @errorName(err) });
        unreachable;
    };

    return @enumFromInt(id);
}

pub fn release_resources(self: *MaterialShader, ctx: *const Context, object_id: T.MaterialInstanceID) void {
    const id: u32 = @intFromEnum(object_id);

    ctx.device.handle.freeDescriptorSets(
        self.local_descriptor_pool,
        MAX_DESCRIPTOR_SETS,
        @ptrCast(&self.object_states[id].descriptor_sets[0]),
    ) catch unreachable;
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
    .{ .tag = .vertex, .binary = builtin.MaterialShader.vert },
    .{ .tag = .fragment, .binary = builtin.MaterialShader.frag },
};

const std = @import("std");
const assert = std.debug.assert;
