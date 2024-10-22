const vk = @import("vulkan");

pub const RendererLog = @import("../types.zig").RendererLog;

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
pub const CommandBuffer = vk.CommandBufferProxy(apis);

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

pub const CommandBufferState = enum(u8) {
    ready,
    recording,
    in_render_pass,
    recording_end,
    submitted,
    not_allocated,
};

const builtin = @import("builtin");
const windows = @import("std").os.windows;
