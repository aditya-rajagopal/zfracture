// TODO:
//      - [ ] implement a custom vkAllocatorCallback
//      - [ ] Try to move all the creations of layers and extensions to be comptime
//      - [ ] Pass the engine here so that we can use the logger
//      - [ ] This needs to be configurable from the engine/game
const vk = @import("vulkan");

const RendererLog = @import("frontend.zig").RendererLog;
const platform = @import("platform.zig");
const dev = @import("device.zig");
const Swapchain = @import("swapchain.zig");

const required_device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};

const Context = @This();

const debug_apis = switch (builtin.mode) {
    .Debug => .{vk.extensions.ext_debug_utils},
    else => .{},
};

/// To construct base, instance and device wrappers for vulkan-zig, you need to pass a list of 'apis' to it.
const apis: []const vk.ApiInfo = &(.{
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
pub const DeviceDispatch = vk.DeviceWrapper(apis);

// Also create some proxying wrappers, which also have the respective handles
pub const Instance = vk.InstanceProxy(apis);
pub const Device = vk.DeviceProxy(apis);
pub const CommandBuffer = vk.CommandBufferProxy(apis);

vkb: BaseDispatch,
allocator: std.mem.Allocator,
log: RendererLog,
vulkan_lib: std.DynLib,
vkGetInstanceProcAddr: vk.PfnGetInstanceProcAddr,

instance: Instance,
debug_messenger: vk.DebugUtilsMessengerEXT,
surface: vk.SurfaceKHR,
device: Device,
physical_device: dev.PhycialDevice,
framebuffer_extent: vk.Extent2D,
swapchain: Swapchain,
recreating_swapchain: bool,
current_frame: u32,

pub const Error =
    error{ FailedProcAddrPFN, FailedToFindValidationLayer, FailedToFindDepthFormat } ||
    error{CommandLoadFailure} ||
    std.DynLib.Error ||
    BaseDispatch.EnumerateInstanceLayerPropertiesError ||
    Instance.CreateDebugUtilsMessengerEXTError ||
    Instance.CreateWin32SurfaceKHRError ||
    BaseDispatch.CreateInstanceError ||
    dev.Error ||
    Swapchain.Error;

pub fn init(
    self: *Context,
    allocator: std.mem.Allocator,
    application_name: [:0]const u8,
    plat_state: *anyopaque,
    log: RendererLog,
) Error!void {
    const internal_plat_state: *platform.VulkanPlatform = @ptrCast(@alignCast(plat_state));
    self.log = log;
    // ========================================== LOAD VULKAN =================================/

    self.vulkan_lib = try std.DynLib.open("vulkan-1.dll");
    errdefer self.vulkan_lib.close();

    self.vkGetInstanceProcAddr = self.vulkan_lib.lookup(
        vk.PfnGetInstanceProcAddr,
        "vkGetInstanceProcAddr",
    ) orelse return Error.FailedProcAddrPFN;
    self.log.debug("Vulkan Library Opened Successfully", .{});

    // ========================================== SETUP BASICS =================================/

    self.vkb = try BaseDispatch.load(self.vkGetInstanceProcAddr);
    self.allocator = allocator;
    self.framebuffer_extent = .{ .width = 1280, .height = 720 };
    self.log.debug("Loaded Base Dispatch", .{});

    // ============================================ INSTANCE ====================================/
    try self.create_instance(application_name);
    errdefer {
        self.instance.destroyInstance(null);
        self.allocator.destroy(self.instance.wrapper);
    }
    self.log.debug("Instance Created", .{});

    // ========================================== DEBUGGER ======================================/
    try self.create_debugger();
    errdefer self.destroy_debugger();

    // ========================================== SURFACE ======================================/
    self.surface = try platform.create_surface(self.instance, internal_plat_state);
    errdefer {
        if (self.surface != .null_handle) {
            self.instance.destroySurfaceKHR(self.surface, null);
        }
    }
    self.log.debug("Surface Created", .{});

    // ====================================== PHYSICAL DEVICE ==================================/
    try dev.create(self);
    errdefer dev.destroy(self);
    self.log.debug("Device created", .{});

    // ====================================== SWAPCHAIN ========================================/
    self.swapchain = try Swapchain.init(self, self.framebuffer_extent);
    self.current_frame = 0;
    errdefer self.swapchain.deinit();
}

pub fn deinit(self: *Context) void {
    self.swapchain.deinit();
    self.log.debug("Swapchain Destroyed", .{});

    dev.destroy(self);
    self.log.debug("Device Destroyed", .{});

    if (self.surface != .null_handle) {
        self.instance.destroySurfaceKHR(self.surface, null);
        self.log.debug("Surface Destroyed", .{});
    }

    self.destroy_debugger();

    self.instance.destroyInstance(null);
    self.allocator.destroy(self.instance.wrapper);
    self.log.debug("Instance Destroyed", .{});

    self.vulkan_lib.close();
    self.log.debug("Vulkan Library Closed", .{});
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

fn destroy_debugger(self: *Context) void {
    switch (builtin.mode) {
        .Debug => {
            self.instance.destroyDebugUtilsMessengerEXT(self.debug_messenger, null);
            self.log.debug("Debugger Destroyed", .{});
        },
        else => {},
    }
}

pub fn detect_depth_format(ctx: *const Context) !vk.Format {
    // NOTE: These are the candidate formats that we like in order of preference.
    // 1. VK_FORMAT_D32_SFLOAT = One component 32bit float depth buffer format that uses all 32 bits for depths
    // 2. VK_FORMAT_D32_SFLOAT_s8_uint = Combined depth and stencil buffer with 32bit for depth and 8bits for stencil
    // 3. VK_FORMAT_D24_UNORM_s8_uint = Combined depth and stencil buffer with 24bit for depth and 8bits for stencil
    const candidates = [_]vk.Format{ .d32_sfloat, .d32_sfloat_s8_uint, .d24_unorm_s8_uint };
    const flags = vk.FormatFeatureFlags{ .depth_stencil_attachment_bit = true };
    for (candidates) |candidate| {
        const properties = ctx.instance.getPhysicalDeviceFormatProperties(
            ctx.physical_device.handle,
            candidate,
        );

        if (properties.linear_tiling_features.contains(flags) or properties.optimal_tiling_features.contains(flags)) {
            return candidate;
        }
    }

    return error.FailedToFindDepthFormat;
}

pub fn find_memory_index(self: *const Context, type_filter: u32, memory_flags: vk.MemoryPropertyFlags) i32 {
    const memory_properties = self.instance.getPhysicalDeviceMemoryProperties(self.physical_device.handle);

    for (0..memory_properties.memory_type_count) |i| {
        if ((type_filter & (@as(u32, 1) << @truncate(i))) != 0 and (memory_properties.memory_types[i].property_flags.contains(memory_flags))) {
            return 1;
        }
    }

    self.log.debug("WARNING: unable to find memory type", .{});
    return -1;
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
                .p_user_data = &self.log,
            };

            self.debug_messenger = try self.instance.createDebugUtilsMessengerEXT(&debug_info, null);
        },
        else => {},
    }
}

fn create_instance(self: *Context, application_name: [:0]const u8) Error!void {
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
            self.log.debug("Required Extensions: ", .{});
            for (required_extensions.items, 0..) |ext, i| {
                self.log.debug("\t{d}. {s}", .{ i, ext });
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
            self.log.debug("Enabled validations", .{});

            layers.appendAssumeCapacity("VK_LAYER_KHRONOS_validation");

            var available_count: u32 = 0;
            _ = try self.vkb.enumerateInstanceLayerProperties(&available_count, null);
            const available_layers = try self.allocator.alloc(vk.LayerProperties, available_count);
            defer self.allocator.free(available_layers);
            _ = try self.vkb.enumerateInstanceLayerProperties(&available_count, available_layers.ptr);

            for (layers.items) |layer| {
                self.log.debug("\tSearching for: {s}...", .{layer});
                const length = std.mem.len(layer);
                var found: bool = false;
                for (available_layers) |avail_layer| {
                    const alength = std.mem.len(@as([*:0]const u8, @ptrCast(&avail_layer)));
                    if (alength != length) continue;
                    if (std.mem.eql(u8, layer[0..length], avail_layer.layer_name[0..length])) {
                        found = true;
                        self.log.debug("FOUND!", .{});
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
    const severity: u32 = @bitCast(message_severity);
    const debug_flag = vk.DebugUtilsMessageSeverityFlagsEXT;
    const err: u32 = @bitCast(debug_flag{ .error_bit_ext = true });
    const warn: u32 = @bitCast(debug_flag{ .warning_bit_ext = true });
    const info: u32 = @bitCast(debug_flag{ .info_bit_ext = true });
    const verbose: u32 = @bitCast(debug_flag{ .verbose_bit_ext = true });
    if (p_callback_data) |data| {
        if (data.p_message) |message| {
            if (p_user_data) |user_data| {
                const log: *RendererLog = @ptrCast(@alignCast(user_data));
                switch (severity) {
                    err => log.err("{s}", .{message}),
                    warn => log.warn("{s}", .{message}),
                    info => log.info("{s}", .{message}),
                    verbose => log.debug("{s}", .{message}),
                    else => log.err("{s}", .{message}),
                }
            }
        }
    }
    return vk.FALSE;
}

const std = @import("std");
const builtin = @import("builtin");
