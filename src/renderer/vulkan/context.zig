// TODO:
//      - [ ] implement a custom vkAllocatorCallback
//      - [ ] Try to move all the creations of layers and extensions to be comptime
//      - [ ] This needs to be configurable from the engine/game
const vk = @import("vulkan");
const T = @import("types.zig");
const math = @import("fr_core").math;

const platform = @import("platform.zig");
const Device = @import("device.zig");
const Swapchain = @import("swapchain.zig");
const RenderPass = @import("renderpass.zig");
const CommandBuffer = @import("command_buffer.zig");
const Framebuffer = @import("framebuffer.zig");
const Fence = @import("fence.zig");

const ObjectShader = @import("object_shader.zig");

const Context = @This();

vkb: T.BaseDispatch,
allocator: std.mem.Allocator,
log: T.RendererLog,
vulkan_lib: std.DynLib,
vkGetInstanceProcAddr: vk.PfnGetInstanceProcAddr,

instance: T.Instance,
debug_messenger: vk.DebugUtilsMessengerEXT,
surface: vk.SurfaceKHR,
device: Device,
mem_props: vk.PhysicalDeviceMemoryProperties,
cached_framebuffer_extent: vk.Extent2D,
framebuffer_extent: vk.Extent2D,
framebuffer_size_generation: u32,
last_framebuffer_generation: u32,
swapchain: Swapchain,
recreating_swapchain: bool,
current_frame: u32,
main_render_pass: RenderPass,
graphics_command_buffers: []CommandBuffer,
framebuffers: []Framebuffer,
object_shader: ObjectShader,

pub const Error =
    error{ FailedProcAddrPFN, FailedToFindValidationLayer, FailedToFindDepthFormat, NotSuitableMemoryType } ||
    error{CommandLoadFailure} ||
    std.DynLib.Error ||
    T.BaseDispatch.EnumerateInstanceLayerPropertiesError ||
    T.Instance.CreateDebugUtilsMessengerEXTError ||
    T.Instance.CreateWin32SurfaceKHRError ||
    T.BaseDispatch.CreateInstanceError ||
    Device.Error ||
    Swapchain.Error ||
    RenderPass.Error ||
    CommandBuffer.Error ||
    Framebuffer.Error ||
    ObjectShader.Error;

pub fn init(
    self: *Context,
    allocator: std.mem.Allocator,
    application_name: [:0]const u8,
    plat_state: *anyopaque,
    log: T.RendererLog,
    framebuffer_extent: *const math.Extent2D,
) Error!void {
    const internal_plat_state: *T.VulkanPlatform = @ptrCast(@alignCast(plat_state));
    self.log = log;
    // ========================================== LOAD VULKAN =================================/

    self.vulkan_lib = try std.DynLib.open("vulkan-1.dll");
    errdefer self.vulkan_lib.close();

    self.vkGetInstanceProcAddr = self.vulkan_lib.lookup(
        vk.PfnGetInstanceProcAddr,
        "vkGetInstanceProcAddr",
    ) orelse return Error.FailedProcAddrPFN;
    self.log.info("Vulkan Library Opened Successfully", .{});

    // ========================================== SETUP BASICS =================================/

    self.vkb = try T.BaseDispatch.load(self.vkGetInstanceProcAddr);
    self.allocator = allocator;
    self.cached_framebuffer_extent = .{ .width = 0, .height = 0 };
    self.framebuffer_extent.width = if (framebuffer_extent.width != 0) framebuffer_extent.width else 800;
    self.framebuffer_extent.height = if (framebuffer_extent.height != 0) framebuffer_extent.height else 600;

    self.log.info("Loaded Base Dispatch", .{});

    // ============================================ INSTANCE ====================================/
    try self.create_instance(application_name);
    errdefer {
        self.instance.destroyInstance(null);
        self.allocator.destroy(self.instance.wrapper);
    }
    self.log.info("Instance Created", .{});

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
    self.log.info("Surface Created", .{});

    // ====================================== DEVICE ==========================================/
    self.device = try Device.create(self);
    errdefer self.device.destroy(self);
    self.log.info("Device created", .{});
    self.mem_props = self.instance.getPhysicalDeviceMemoryProperties(self.device.pdev);

    // ====================================== SWAPCHAIN ========================================/
    self.swapchain = try Swapchain.init(self, self.framebuffer_extent);
    self.current_frame = 0;
    self.framebuffers = try self.allocator.alloc(Framebuffer, self.swapchain.images.len);
    errdefer self.swapchain.deinit();
    self.recreating_swapchain = false;

    // self.images_in_flight = try self.allocator.alloc(?*Fence, self.swapchain.images.len);
    // for (self.images_in_flight) |*img| {
    //     img.* = null;
    // }

    // ==================================== MAIN RENDERPASS ====================================/
    self.main_render_pass = try RenderPass.create(
        self,
        [_]u32{ 0, 0, self.framebuffer_extent.width, self.framebuffer_extent.height },
        [_]f32{ 0.0, 0.0, 0.2, 1.0 },
        1.0,
        0.0,
    );
    errdefer self.main_render_pass.destroy(self);
    self.log.info("Main Renderpass Created", .{});

    // ==================================== FRAMEBUFFERS ====================================/
    try self.regen_framebuffers();
    errdefer self.destroy_framebuffers();
    self.log.info("Framebuffers Created", .{});

    // ==================================== GRAPHICS COMMANDBUFFER ============================/
    self.graphics_command_buffers = try self.allocate_command_buffers();
    errdefer self.free_commmand_buffers();
    self.log.info("Graphics CommandBuffers Allocated", .{});
    self.framebuffer_size_generation = 0;
    self.last_framebuffer_generation = 0;

    self.object_shader = try ObjectShader.create(self);
    self.log.info("Builtin Object Shader loaded Successfully", .{});
}

pub fn deinit(self: *Context) void {
    self.object_shader.destroy(self);
    self.swapchain.wait_for_all_fences();
    self.device.handle.deviceWaitIdle() catch unreachable;

    self.free_commmand_buffers();
    self.log.info("Graphics CommandBuffers Freed", .{});

    self.destroy_framebuffers();
    self.log.info("Framebuffers destroyed", .{});

    self.main_render_pass.destroy(self);
    self.log.info("Main Renderpass Destroyed", .{});

    // self.allocator.free(self.images_in_flight);
    self.swapchain.deinit();
    self.allocator.free(self.framebuffers);
    self.log.info("Swapchain Destroyed", .{});

    self.device.destroy(self);
    self.log.info("Device Destroyed", .{});

    if (self.surface != .null_handle) {
        self.instance.destroySurfaceKHR(self.surface, null);
        self.log.info("Surface Destroyed", .{});
    }

    self.destroy_debugger();

    self.instance.destroyInstance(null);
    self.allocator.destroy(self.instance.wrapper);
    self.log.info("Instance Destroyed", .{});

    self.vulkan_lib.close();
    self.log.info("Vulkan Library Closed", .{});
}

pub fn begin_frame(self: *Context, delta_time: f32) bool {
    _ = delta_time;

    if (self.recreating_swapchain) {
        @branchHint(.cold);
        self.device.handle.deviceWaitIdle() catch |err| {
            self.log.err("Vulkan Begin frame waitForIdle failed: {s}", .{@errorName(err)});
            return false;
        };

        self.log.info("Recreating Swapchain", .{});
        return false;
    }

    if (self.framebuffer_size_generation != self.last_framebuffer_generation) {
        @branchHint(.unlikely);
        self.device.handle.deviceWaitIdle() catch |err| {
            self.log.err("Vulkan Begin frame waitForIdle failed: {s}", .{@errorName(err)});
            return false;
        };

        // Swapchain recreation can fail because window was minimized
        _ = self.recreate_swapchain() catch |err| {
            self.log.err("Vulkan begin frame swapchain recreation failed: {s}", .{@errorName(err)});
            return false;
        };

        self.log.info("Swapchain resized. Skipping frame", .{});
        return false;
    }

    const current_image = self.swapchain.get_current_swap_image();
    if (!current_image.fence.wait(self, std.math.maxInt(u64))) {
        @branchHint(.cold);
        self.log.warn("In-flight fence wait failed", .{});
        return false;
    }
    current_image.fence.reset(self) catch |err| {
        @branchHint(.cold);
        self.log.err("Vulkan Begin frame current image fence reset failed: {s}", .{@errorName(err)});
        return false;
    };

    const command_buffer = &self.graphics_command_buffers[self.swapchain.current_image_index];
    command_buffer.reset();
    command_buffer.begin(false, false, false) catch |err| {
        @branchHint(.cold);
        self.log.err("Vulkan Begin frame command buffer failed failed: {s}", .{@errorName(err)});
        return false;
    };

    // NOTE: We are setting the y dimension here to the framebuffer height so that the bottom left is the 0, 0
    // to be consistent with OpenGL
    // TODO: Should this be 0, 0 on the top left?
    const viewport = vk.Viewport{
        .x = 0.0,
        .y = @floatFromInt(self.framebuffer_extent.height),
        .width = @floatFromInt(self.framebuffer_extent.width),
        .height = -@as(f32, @floatFromInt(self.framebuffer_extent.width)),
        .min_depth = 0.0,
        .max_depth = 1.0,
    };

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = self.framebuffer_extent,
    };

    command_buffer.handle.setViewport(0, 1, @ptrCast(&viewport));
    command_buffer.handle.setScissor(0, 1, @ptrCast(&scissor));

    // self.main_render_pass.surface_rect[2] = self.framebuffer_extent.width;
    // self.main_render_pass.surface_rect[3] = self.framebuffer_extent.height;

    self.main_render_pass.begin(
        command_buffer,
        self.framebuffers[self.swapchain.current_image_index].handle,
    );

    return true;
}

pub fn end_frame(self: *Context, delta_time: f32) bool {
    _ = delta_time;

    const command_buffer = &self.graphics_command_buffers[self.swapchain.current_image_index];

    self.main_render_pass.end(command_buffer);

    command_buffer.end() catch |err| {
        @branchHint(.cold);
        self.log.err("Vulkan end frame command buffer end failed: {s}", .{@errorName(err)});
        return false;
    };

    const res = self.swapchain.present(command_buffer) catch |err| {
        @branchHint(.cold);
        self.log.err("Vulkan swapchain present failed with error: {s}\n", .{@errorName(err)});
        return false;
    };

    // NOTE: Only false when swapchain needs to be recreated
    if (!res) {
        self.log.info("Swapchain out of date. Recreating swapchain and trying again.", .{});
        _ = self.recreate_swapchain() catch |err| {
            @branchHint(.cold);
            self.log.err("Vulkan begin frame swapchain recreation failed: {s}", .{@errorName(err)});
            return false;
        };
        return false;
    }

    return true;
}

pub fn on_resized(self: *Context, new_extent: math.Extent2D) void {
    self.cached_framebuffer_extent = @bitCast(new_extent);
    self.framebuffer_size_generation +%= 1;
    // self.log.info(
    //     "Vulkan on_resize: w/h/gen: {d}/{d}/{d}",
    //     .{ self.cached_framebuffer_extent.width, self.cached_framebuffer_extent.height, self.framebuffer_size_generation },
    // );
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
            ctx.device.pdev,
            candidate,
        );

        if (properties.linear_tiling_features.contains(flags) or properties.optimal_tiling_features.contains(flags)) {
            return candidate;
        }
    }

    return error.FailedToFindDepthFormat;
}

pub fn find_memory_index(self: *const Context, type_filter: u32, memory_flags: vk.MemoryPropertyFlags) error{NotSuitableMemoryType}!u32 {
    for (0..self.mem_props.memory_type_count) |i| {
        if ((type_filter & (@as(u32, 1) << @truncate(i))) != 0 and (self.mem_props.memory_types[i].property_flags.contains(memory_flags))) {
            return @truncate(i);
        }
    }

    self.log.info("WARNING: unable to find memory type", .{});
    return error.NotSuitableMemoryType;
}

fn recreate_swapchain(self: *Context) !bool {
    if (self.recreating_swapchain) {
        self.log.debug("Already recreating swapchain. Booting", .{});
        return false;
    }

    if (self.framebuffer_extent.width == 0 or self.framebuffer_extent.height == 0) {
        return false;
    }

    self.recreating_swapchain = true;

    self.device.handle.deviceWaitIdle() catch return false;

    if (self.cached_framebuffer_extent.width != 0 and self.cached_framebuffer_extent.height != 0) {
        self.framebuffer_extent = self.cached_framebuffer_extent;
    }

    try self.swapchain.recreate(self.framebuffer_extent);

    self.main_render_pass.surface_rect[2] = self.framebuffer_extent.width;
    self.main_render_pass.surface_rect[3] = self.framebuffer_extent.height;

    self.cached_framebuffer_extent = .{ .width = 0, .height = 0 };

    self.last_framebuffer_generation = self.framebuffer_size_generation;

    self.free_commmand_buffers();
    self.destroy_framebuffers();

    try self.regen_framebuffers();
    self.graphics_command_buffers = try self.allocate_command_buffers();

    self.recreating_swapchain = false;

    return true;
}

pub fn regen_framebuffers(self: *Context) Framebuffer.Error!void {
    var i: usize = 0;
    errdefer for (self.framebuffers[0..i]) |*fb| fb.destroy(self);

    for (self.swapchain.images) |*img| {
        const attachments = [_]vk.ImageView{
            img.view,
            self.swapchain.depth_attachement.view,
        };
        self.framebuffers[i] = try Framebuffer.create(
            self,
            &self.main_render_pass,
            self.framebuffer_extent,
            &attachments,
        );
        i += 1;
    }
}

fn destroy_framebuffers(self: *Context) void {
    for (self.framebuffers) |*fb| {
        fb.destroy(self);
    }
}

// TODO: make these array lists so that memory can be reused and not allocated and destroyed everytime swapchain is recreated
fn free_commmand_buffers(self: *Context) void {
    for (self.graphics_command_buffers) |*buf| {
        buf.free(self);
    }
    self.allocator.free(self.graphics_command_buffers);
}

fn allocate_command_buffers(self: *const Context) ![]CommandBuffer {
    // NOTE: We need 1 command buffer per swapchain image
    const cmd_buffers = try self.allocator.alloc(CommandBuffer, self.swapchain.images.len);
    errdefer self.allocator.free(cmd_buffers);

    for (cmd_buffers) |*buf| {
        buf.* = try CommandBuffer.allocate(self, self.device.graphics_command_pool, true);
    }

    return cmd_buffers;
}

fn destroy_debugger(self: *Context) void {
    switch (builtin.mode) {
        .Debug => {
            self.instance.destroyDebugUtilsMessengerEXT(self.debug_messenger, null);
            self.log.info("Debugger Destroyed", .{});
        },
        else => {},
    }
}

fn create_debugger(self: *Context) !void {
    switch (builtin.mode) {
        .Debug => {
            const log_severity = vk.DebugUtilsMessageSeverityFlagsEXT{
                .error_bit_ext = true,
                .warning_bit_ext = true,
                .info_bit_ext = true,
                // .verbose_bit_ext = true,
            };

            const message_type = vk.DebugUtilsMessageTypeFlagsEXT{
                .general_bit_ext = true,
                .validation_bit_ext = true,
                .performance_bit_ext = true,
                .device_address_binding_bit_ext = true,
            };

            const debug_info = vk.DebugUtilsMessengerCreateInfoEXT{
                .s_type = .debug_utils_messenger_create_info_ext,
                .message_severity = log_severity,
                .message_type = message_type,
                .pfn_user_callback = debug_callback,
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
        .api_version = vk.API_VERSION_1_3,
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
            self.log.info("Required Extensions: ", .{});
            for (required_extensions.items, 0..) |ext, i| {
                self.log.info("\t{d}. {s}", .{ i, ext });
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
            self.log.info("Enabled validations", .{});

            layers.appendAssumeCapacity("VK_LAYER_KHRONOS_validation");

            var available_count: u32 = 0;
            _ = try self.vkb.enumerateInstanceLayerProperties(&available_count, null);
            const available_layers = try self.allocator.alloc(vk.LayerProperties, available_count);
            defer self.allocator.free(available_layers);
            _ = try self.vkb.enumerateInstanceLayerProperties(&available_count, available_layers.ptr);

            for (layers.items) |layer| {
                self.log.info("\tSearching for: {s}...", .{layer});
                const length = std.mem.len(layer);
                var found: bool = false;
                for (available_layers) |avail_layer| {
                    const alength = std.mem.len(@as([*:0]const u8, @ptrCast(&avail_layer)));
                    if (alength != length) continue;
                    if (std.mem.eql(u8, layer[0..length], avail_layer.layer_name[0..length])) {
                        found = true;
                        self.log.info("FOUND!", .{});
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
    const vk_inst = try self.allocator.create(T.InstanceDispatch);
    errdefer self.allocator.destroy(vk_inst);
    vk_inst.* = try T.InstanceDispatch.load(instance, self.vkb.dispatch.vkGetInstanceProcAddr);
    self.instance = T.Instance.init(instance, vk_inst);
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
                const log: *T.RendererLog = @ptrCast(@alignCast(user_data));
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
