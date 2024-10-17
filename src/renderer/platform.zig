// TODO(aditya): Figure out a better way to handle this. I dont want to have platform here.
pub const VulkanPlatform = struct {
    /// Handel to the instance of the application
    h_instance: windows.HINSTANCE,
    /// Window handle
    hwnd: ?windows.HWND,
};

pub fn get_requrired_instance_extensions(array_list: *std.ArrayList([*:0]const u8)) void {
    array_list.appendAssumeCapacity("VK_KHR_win32_surface");
}

const std = @import("std");
const windows = std.os.windows;
const builtin = @import("builtin");
