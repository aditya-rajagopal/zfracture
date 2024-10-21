// TODO(aditya): Figure out a better way to handle this. I dont want to have platform here.
const vk = @import("vulkan");
const Instance = @import("context.zig").Instance;

pub const VulkanPlatform = struct {
    /// Handel to the instance of the application
    h_instance: windows.HINSTANCE,
    /// Window handle
    hwnd: ?windows.HWND,
};

pub fn get_requrired_instance_extensions(array_list: *std.ArrayList([*:0]const u8)) void {
    array_list.appendAssumeCapacity("VK_KHR_win32_surface");
}

pub fn create_surface(instance: Instance, platform_state: *const VulkanPlatform) !vk.SurfaceKHR {
    const create_info = vk.Win32SurfaceCreateInfoKHR{
        .hinstance = platform_state.h_instance,
        .hwnd = platform_state.hwnd.?,
    };

    return instance.createWin32SurfaceKHR(&create_info, null);
}

const std = @import("std");
const windows = std.os.windows;
const builtin = @import("builtin");
