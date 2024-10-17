// TODO:
//      - [ ] implement a custom vkAllocatorCallback
//      - [ ] Try to move all the creations of layers and extensions to be comptime
//      - [ ] Pass the engine here so that we can use the logger
const vk = @import("vulkan");
const Backend = @import("backend.zig");
const platform = @import("platform.zig");

const required_device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};

const Context = @This();

const debug_apis = switch (builtin.mode) {
    .Debug => .{vk.extensions.ext_debug_utils},
    else => .{},
};

/// To construct base, instance and device wrappers for vulkan-zig, you need to pass a list of 'apis' to it.
const apis: []const vk.ApiInfo = &(.{
    // You can either add invidiual functions by manually creating an 'api'
    // .{
    //     .base_commands = .{
    //         .createInstance = true,
    //         .getInstanceProcAddr = true,
    //         // .enumerateInstanceLayerProperties = true,
    //     },
    //     .instance_commands = .{
    //         .destroyInstance = true,
    //         // .createDevice = true,
    //         // .createXcbSurfaceKHR = true,
    //     },
    // },
    vk.features.version_1_0,
    vk.features.version_1_1,
    vk.features.version_1_2,
    vk.extensions.khr_win_32_surface,
    // vk.extensions.khr_swapchain,
    // vk.extensions.ext_debug_utils,
} ++ debug_apis);

/// Next, pass the `apis` to the wrappers to create dispatch tables.
const BaseDispatch = vk.BaseWrapper(apis);
const InstanceDispatch = vk.InstanceWrapper(apis);
const DeviceDispatch = vk.DeviceWrapper(apis);

// Also create some proxying wrappers, which also have the respective handles
const Instance = vk.InstanceProxy(apis);
const Device = vk.DeviceProxy(apis);

pub const CommandBuffer = vk.CommandBufferProxy(apis);

vkb: BaseDispatch,
instance: Instance,
allocator: std.mem.Allocator,
vulkan_lib: std.DynLib,
vkGetInstanceProcAddr: vk.PfnGetInstanceProcAddr,
debug_messenger: vk.DebugUtilsMessengerEXT,

pub const vkError =
    error{ FailedProcAddrPFN, FailedToFindValidationLayer } ||
    BaseDispatch.EnumerateInstanceLayerPropertiesError ||
    Instance.CreateDebugUtilsMessengerEXTError;

pub fn init(
    self: *Context,
    allocator: std.mem.Allocator,
    application_name: [:0]const u8,
    plat_state: *anyopaque,
) !void {
    const internal_plat_state: *platform.VulkanPlatform = @ptrCast(@alignCast(plat_state));
    std.debug.print("{any}\n", .{internal_plat_state.h_instance});
    // ========================================== LOAD VULKAN =================================/

    self.vulkan_lib = try std.DynLib.open("vulkan-1.dll");
    self.vkGetInstanceProcAddr = self.vulkan_lib.lookup(
        vk.PfnGetInstanceProcAddr,
        "vkGetInstanceProcAddr",
    ) orelse return vkError.FailedProcAddrPFN;

    // ========================================== SETUP BASICS =================================/

    self.vkb = try BaseDispatch.load(self.vkGetInstanceProcAddr);
    self.allocator = allocator;

    // ============================================ INSTANCE ====================================/
    try self.create_instance(application_name);
    errdefer self.instance.destroyInstance(null);
    std.debug.print("Instance Created\n", .{});

    // ========================================== DEBUGGER ======================================/
    try self.create_debugger();
}

pub fn deinit(self: *Context) void {
    switch (builtin.mode) {
        .Debug => self.instance.destroyDebugUtilsMessengerEXT(self.debug_messenger, null),
        else => {},
    }
    self.instance.destroyInstance(null);
    self.allocator.destroy(self.instance.wrapper);
    self.vulkan_lib.close();
}

fn create_debugger(self: *Context) !void {
    switch (builtin.mode) {
        .Debug => {
            const log_severity = vk.DebugUtilsMessageSeverityFlagsEXT{
                .error_bit_ext = true,
                .warning_bit_ext = true,
                // .info_bit_ext = true,
                // .verbose_bit_ext = true,
            };

            const message_type = vk.DebugUtilsMessageTypeFlagsEXT{
                .general_bit_ext = true,
                .validation_bit_ext = true,
                .performance_bit_ext = true,
                // .device_address_binding_bit_ext = true,
            };
            const debug_info = vk.DebugUtilsMessengerCreateInfoEXT{
                .s_type = .debug_utils_messenger_create_info_ext,
                .message_severity = log_severity,
                .message_type = message_type,
                .pfn_user_callback = debug_callback,
                // TODO: Pass the engine pointer/logger pointer here.
                .p_user_data = null,
            };

            self.debug_messenger = try self.instance.createDebugUtilsMessengerEXT(&debug_info, null);
        },
        else => {},
    }
}

fn create_instance(self: *Context, application_name: [:0]const u8) !void {
    const info: vk.ApplicationInfo = .{
        .s_type = .application_info,
        .p_application_name = application_name,
        .application_version = vk.makeApiVersion(1, 0, 0, 0),
        .p_engine_name = "Fracture Engine",
        .engine_version = vk.makeApiVersion(1, 0, 0, 0),
        .p_next = null,
        .api_version = vk.API_VERSION_1_2,
    };

    var create_info: vk.InstanceCreateInfo = .{
        .s_type = .instance_create_info,
        .p_next = null,
        .p_application_info = &info,
        .enabled_extension_count = 0,
        .pp_enabled_extension_names = null,
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = null,
    };

    // NOTE(aditya): get the required extensions
    var required_extensions = try std.ArrayList([*:0]const u8).initCapacity(self.allocator, 10);
    required_extensions.appendAssumeCapacity("VK_KHR_surface");
    platform.get_requrired_instance_extensions(&required_extensions);
    switch (builtin.mode) {
        .Debug => {
            required_extensions.appendAssumeCapacity("VK_EXT_debug_utils");
            // TODO: Replace this with core_log
            std.debug.print("Required Extensions: \n", .{});
            for (required_extensions.items, 0..) |ext, i| {
                std.debug.print("\t{d}. {s}\n", .{ i, ext });
            }
        },
        else => {},
    }
    defer required_extensions.deinit();

    create_info.enabled_extension_count = @truncate(required_extensions.items.len);
    create_info.pp_enabled_extension_names = required_extensions.items.ptr;

    // NOTE: get validation layers. Mostly during debug builds
    var layers = try std.ArrayList([*:0]const u8).initCapacity(self.allocator, 10);
    defer layers.deinit();
    switch (builtin.mode) {
        .Debug => {
            // TODO: replace the prints with core_log somehow
            std.debug.print("Enabled validations\n", .{});

            layers.appendAssumeCapacity("VK_LAYER_KHRONOS_validation");

            var available_count: u32 = 0;
            _ = try self.vkb.enumerateInstanceLayerProperties(&available_count, null);
            const available_layers = try self.allocator.alloc(vk.LayerProperties, available_count);
            defer self.allocator.free(available_layers);
            _ = try self.vkb.enumerateInstanceLayerProperties(&available_count, available_layers.ptr);

            for (layers.items) |layer| {
                std.debug.print("\tSearching for: {s}...", .{layer});
                const length = std.mem.len(layer);
                var found: bool = false;
                for (available_layers) |avail_layer| {
                    const alength = std.mem.len(@as([*:0]const u8, @alignCast(avail_layer.layer_name[0..255 :0].ptr)));
                    if (alength != length) continue;
                    if (std.mem.eql(u8, layer[0..length], avail_layer.layer_name[0..length])) {
                        found = true;
                        std.debug.print("FOUND!\n", .{});
                        break;
                    }
                }
                if (!found) {
                    return error.FailedToFindValidationLayer;
                }
            }
            create_info.enabled_layer_count = @truncate(layers.items.len);
            create_info.pp_enabled_layer_names = layers.items.ptr;
        },
        else => {},
    }

    // TODO: Implement a custom allocator callback
    const instance = try self.vkb.createInstance(&create_info, null);

    // This creates the isntance dispatch tables
    const vk_inst = try self.allocator.create(InstanceDispatch);
    errdefer self.allocator.destroy(vk_inst);
    vk_inst.* = try InstanceDispatch.load(instance, self.vkb.dispatch.vkGetInstanceProcAddr);
    self.instance = Instance.init(instance, vk_inst);
}

fn debug_callback(
    message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    message_types: vk.DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    p_user_data: ?*anyopaque,
) callconv(vk.vulkan_call_conv) vk.Bool32 {
    _ = message_types;
    _ = p_user_data;
    const severity: u32 = @bitCast(message_severity);
    const debug_flag = vk.DebugUtilsMessageSeverityFlagsEXT;
    const err: u32 = @bitCast(debug_flag{ .error_bit_ext = true });
    const warn: u32 = @bitCast(debug_flag{ .warning_bit_ext = true });
    const info: u32 = @bitCast(debug_flag{ .info_bit_ext = true });
    const verbose: u32 = @bitCast(debug_flag{ .verbose_bit_ext = true });
    if (p_callback_data) |data| {
        if (data.p_message) |message| {
            switch (severity) {
                err => std.debug.print("VULKAN ERROR: {s}\n", .{message}),
                warn => std.debug.print("VULKAN WARN: {s}\n", .{message}),
                info => std.debug.print("VULKAN INFO: {s}\n", .{message}),
                verbose => std.debug.print("VULKAN VERBOS: {s}\n", .{message}),
                else => std.debug.print("VULKAN UNKOWN: {s}\n", .{message}),
            }
        }
    }
    return vk.FALSE;
}

const std = @import("std");
const builtin = @import("builtin");
