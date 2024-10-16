const vk = @import("vulkan");
const Backend = @import("backend.zig");

const required_device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};

const Context = @This();

/// To construct base, instance and device wrappers for vulkan-zig, you need to pass a list of 'apis' to it.
const apis: []const vk.ApiInfo = &.{
    // You can either add invidiual functions by manually creating an 'api'
    .{
        .base_commands = .{
            .createInstance = true,
            .enumerateInstanceLayerProperties = true,
        },
        .instance_commands = .{
            // .createDevice = true,
            // .createXcbSurfaceKHR = true,
        },
    },
    // Or you can add entire feature sets or extensions
    vk.features.version_1_0,
    // vk.extensions.khr_surface,
    // vk.extensions.khr_swapchain,
    // vk.extensions.ext_debug_utils,
};

/// Next, pass the `apis` to the wrappers to create dispatch tables.
const BaseDispatch = vk.BaseWrapper(apis);
const InstanceDispatch = vk.InstanceWrapper(apis);
const DeviceDispatch = vk.DeviceWrapper(apis);

// Also create some proxying wrappers, which also have the respective handles
const Instance = vk.InstanceProxy(apis);
const Device = vk.DeviceProxy(apis);

pub const CommandBuffer = vk.CommandBufferProxy(apis);

// const vkGetInstanceProcAddr = @extern(vk.PfnGetInstanceProcAddr, .{
//     .name = "vkGetInstanceProcAddr",
//     .library_name = "vulkan-1",
// });

vkb: BaseDispatch,
instance: Instance,
allocator: std.mem.Allocator,
vulkan_lib: std.DynLib,
vkGetInstanceProcAddr: vk.PfnGetInstanceProcAddr,

pub const vkError = error{FailedProcAddrPFN};

pub fn init(self: *Context, allocator: std.mem.Allocator, application_name: [:0]const u8, plat_state: *anyopaque) !void {
    // _ = backend;
    _ = plat_state;

    self.vulkan_lib = try std.DynLib.open("vulkan-1.dll");
    self.vkGetInstanceProcAddr = self.vulkan_lib.lookup(
        vk.PfnGetInstanceProcAddr,
        "vkGetInstanceProcAddr",
    ) orelse return vkError.FailedProcAddrPFN;

    // const self: Context = undefined;
    self.vkb = try BaseDispatch.load(self.vkGetInstanceProcAddr);
    self.allocator = allocator;

    // setup vulkan info
    const info: vk.ApplicationInfo = .{
        .s_type = .application_info,
        .p_application_name = application_name,
        .application_version = vk.makeApiVersion(1, 0, 0, 0),
        .p_engine_name = "Fracture Engine",
        .engine_version = vk.makeApiVersion(1, 0, 0, 0),
        .p_next = null,
        .api_version = vk.API_VERSION_1_2,
    };

    const create_info: vk.InstanceCreateInfo = .{
        .s_type = .instance_create_info,
        .p_next = null,
        .p_application_info = &info,
        .enabled_extension_count = 0,
        .pp_enabled_extension_names = null,
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = null,
    };

    // TODO: Implement a custom allocator callback
    const instance = try self.vkb.createInstance(&create_info, null);

    // This creates the isntance dispatch tables
    const vk_inst = try allocator.create(InstanceDispatch);
    errdefer allocator.destroy(vk_inst);
    vk_inst.* = try InstanceDispatch.load(instance, self.vkb.dispatch.vkGetInstanceProcAddr);
    self.instance = Instance.init(instance, vk_inst);
    // TODO: custom allocator
    errdefer self.instance.destroyInstance(null);
    std.debug.print("Renderer Initialized\n", .{});
}

pub fn deinit(self: *Context) void {
    self.instance.destroyInstance(null);
    self.allocator.destroy(self.instance.wrapper);
    self.vulkan_lib.close();
    std.debug.print("Destroyed Instance\n", .{});
}

pub fn on_resize(self: *Context, width: u16, height: u16) void {
    _ = self;
    _ = width;
    _ = height;
}

pub fn begin_frame(self: *Context, delta_time: f32) bool {
    _ = self;
    _ = delta_time;
    return true;
}

pub fn end_frame(self: *Context, delta_time: f32) bool {
    _ = self;
    _ = delta_time;
    return true;
}

const std = @import("std");
// ----------------------------------------- TYPES ------------------------------------------- /
