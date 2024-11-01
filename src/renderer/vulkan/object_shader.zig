const vk = @import("vulkan");
const Context = @import("context.zig");
const builtin = @import("shaders").builtin;
const T = @import("types.zig");
const m = @import("fr_core").math;

const Pipeline = @import("pipeline.zig");

// vertex, frag
pub const OBJECT_SHADER_STAGE_COUNT = 2;

const ObjectShader = @This();

stages: [OBJECT_SHADER_STAGE_COUNT]ShaderStage,
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

    // TODO: Descriptiors

    // Create the pipeline

    const viewport = vk.Viewport{
        .x = 0,
        .y = @floatFromInt(ctx.framebuffer_extent.height),
        .width = @floatFromInt(ctx.framebuffer_extent.width),
        .height = -@as(f32, @floatFromInt(ctx.framebuffer_extent.height)),
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

    // TODO: Descriptor layouts go here

    var stage_create_info: [OBJECT_SHADER_STAGE_COUNT]vk.PipelineShaderStageCreateInfo = undefined;
    for (stage_create_info[0..OBJECT_SHADER_STAGE_COUNT], 0..) |*info, index| {
        // info.s_type = out_shader.stages[i].stage_create_info.s_type;
        info.* = out_shader.stages[index].stage_create_info;
    }

    out_shader.pipeline = try Pipeline.create(
        ctx,
        ctx.main_render_pass.handle,
        attribute_descriptions[0..attribute_count],
        null,
        stage_create_info[0..OBJECT_SHADER_STAGE_COUNT],
        viewport,
        scissor,
        false,
    );

    return out_shader;
}

pub fn destroy(self: *ObjectShader, ctx: *const Context) void {
    self.pipeline.destroy(ctx);

    for (&self.stages) |*stage| {
        ctx.device.handle.destroyShaderModule(stage.handle, null);
        stage.handle = .null_handle;
    }
}

pub fn use() void {}

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
