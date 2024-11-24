const vk = @import("vulkan");
const core = @import("fr_core");
const Image = @import("image.zig");

const T = @import("../types.zig");
pub const RendererLog = T.RendererLog;
pub const MaterialInstanceID = T.MaterialInstanceID;
pub const Vertex3D = T.Vertex3D;
pub const GlobalUO = T.GlobalUO;
pub const ObjectUO = T.ObjectUO;
pub const RenderData = T.RenderData;

pub const Generation = core.resource.Generation;

pub const MAX_MATERIAL_INSTANCES = T.MAX_MATERIAL_INSTANCES;

pub const MAX_OBJECTS = 1024;

pub const required_device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};
const debug_apis = switch (builtin.mode) {
    .Debug => .{vk.extensions.ext_debug_utils},
    else => .{},
};

pub const VulkanPlatform = struct {
    /// Handel to the instance of the application
    h_instance: windows.HINSTANCE,
    /// Window handle
    hwnd: ?windows.HWND,
};

/// To construct base, instance and device wrappers for vulkan-zig, you need to pass a list of 'apis' to it.
pub const apis: []const vk.ApiInfo = &(.{
    vk.features.version_1_0,
    vk.features.version_1_1,
    vk.features.version_1_2,
    vk.extensions.khr_surface,
    vk.extensions.khr_win_32_surface,
    vk.extensions.khr_swapchain,
} ++ debug_apis);

/// Next, pass the `apis` to the wrappers to create dispatch tables.
pub const BaseDispatch = vk.BaseWrapper(apis);
pub const InstanceDispatch = vk.InstanceWrapper(apis);
pub const LogicalDeviceDispatch = vk.DeviceWrapper(apis);

// Also create some proxying wrappers, which also have the respective handles
pub const Instance = vk.InstanceProxy(apis);
pub const LogicalDevice = vk.DeviceProxy(apis);
pub const CommandBufferProxy = vk.CommandBufferProxy(apis);

pub const RenderPassState = enum(u8) {
    /// Ready to being
    ready,
    recording,
    in_render_pass,
    recording_end,
    submitted,
    /// Default when nothing has been allocated
    not_allocated,
};

/// When a command buffer starts it is in the not_allocated state. Command buffers are not created but rather
/// allocated from commandPools. So the command buffer usually starts with the not_allocated state. We switch to ready
/// after it is allocated.
/// It can transition from ready -> recording. In recoding you can issue commands to the command buffer. When you are done
/// you transition to recording_end. Once you are there you can submit the command buffer for execution. It is in this state
/// till the command buffer has finished executing and it returns to the ready state.
/// the in_render_pass is only used for command_buffers that are used in a render pass
pub const CommandBufferState = enum(u8) {
    ready,
    recording,
    in_render_pass,
    recording_end,
    submitted,
    not_allocated,
};

// TODO: Seperate file?
pub const vkTextureData = struct {
    image: Image,
    sampler: vk.Sampler,
};

// TODO: Should this be somehting universal?

pub const MATERIAL_SHADER_DESCRIPTOR_COUNT = 2;

pub const DescriptorState = extern struct {
    // One per frame
    generations: [MAX_DESCRIPTOR_SETS]Generation,
};

pub const ObjectShaderObjectState = extern struct {
    descriptor_sets: [MAX_DESCRIPTOR_SETS]vk.DescriptorSet,
    descriptor_states: [MATERIAL_SHADER_DESCRIPTOR_COUNT]DescriptorState,
};

const MAX_DESCRIPTOR_SETS = @import("material_shader.zig").MAX_DESCRIPTOR_SETS;
const std = @import("std");
const builtin = @import("builtin");
const windows = @import("std").os.windows;
