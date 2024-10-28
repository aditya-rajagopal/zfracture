const vk = @import("vulkan");
const Context = @import("context.zig");
const builtin = @import("shaders").builtin;
const T = @import("types.zig");

// vertex, frag
pub const OBJECT_SHADER_STAGE_COUNT = 2;

pub const ShaderType = enum {
    vertex,
    fragment,
};

pub const Shader = struct {
    tag: ShaderType,
    binary: []align(4) const u8,
};

pub const ShaderStage = struct {
    create_info: vk.ShaderModuleCreateInfo,
    handle: vk.ShaderModule,
    stage_create_info: vk.PipelineShaderStageCreateInfo,
};

pub const Pipeline = struct {
    handle: vk.Pipeline,
    layout: vk.PipelineLayout,
};

const shaders: []const Shader = &.{
    .{ .tag = .vertex, .binary = builtin.ObjectShader.vert },
    .{ .tag = .fragment, .binary = builtin.ObjectShader.frag },
};

const ObjectShader = @This();

stages: [OBJECT_SHADER_STAGE_COUNT]ShaderStage,
pipeline: Pipeline,

pub const Error = error{UnableToLoadShader};

pub fn create(ctx: *const Context) !ObjectShader {
    const stage_types = [OBJECT_SHADER_STAGE_COUNT]vk.ShaderStageFlags{
        .{ .vertex_bit = true },
        .{ .fragment_bit = true },
    };

    var out_shader: ObjectShader = undefined;

    for (0..OBJECT_SHADER_STAGE_COUNT) |i| {
        out_shader.stages[i] = create_shader_module(ctx, stage_types[i], shaders[i]) catch {
            ctx.log.err("Unable to create {s} shader module for Builtin.ObjectShader", .{@tagName(shaders[i].tag)});
            return error.UnableToLoadShader;
        };
    }

    // TODO: Descriptiors

    return out_shader;
}

pub fn destroy(self: ObjectShader, ctx: *const Context) void {
    for (self.stages) |stage| {
        ctx.device.handle.destroyShaderModule(stage.handle, null);
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

    var stage: ShaderStage = undefined;
    stage.stage_create_info = .{
        .s_type = .pipeline_shader_stage_create_info,
        .stage = stage_type,
        .module = shader_module,
        .p_name = "main", // NOTE: THe entry point of the shader. Can try to make this customizable
    };
    stage.handle = shader_module;
    stage.create_info = create_info;

    return stage;
}

const std = @import("std");
