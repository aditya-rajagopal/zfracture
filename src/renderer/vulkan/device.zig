// TODO:
//      - [ ] Get all the features from the engine/game
const vk = @import("vulkan");
const Context = @import("context.zig");

const T = @import("types.zig");

pub const Queue = struct {
    handle: vk.Queue = .null_handle,
    family: u32 = std.math.maxInt(u32),

    pub fn init(self: *Queue, device: T.LogicalDevice) void {
        // TODO: We might have more than 1 queueIndices.
        if (self.family != std.math.maxInt(u32)) {
            self.handle = device.getDeviceQueue(self.family, 0);
        } else {
            self.handle = .null_handle;
        }
    }
};

pub const QueueGroup = struct {
    graphics: Queue = .{},
    present: Queue = .{},
    transfer: Queue = .{},
    compute: Queue = .{},
};

const Device = @This();

pdev: vk.PhysicalDevice,
queues: QueueGroup,
graphics_command_pool: vk.CommandPool = .null_handle,
handle: T.LogicalDevice = undefined,
supports_device_local_host_visable: bool = false,

pub const Error =
    error{ NoPhysicalDeviceFound, CommandLoadFailure } ||
    T.LogicalDevice.CreateCommandPoolError ||
    T.Instance.CreateDeviceError ||
    T.Instance.EnumeratePhysicalDevicesError ||
    T.Instance.EnumerateDeviceExtensionPropertiesError ||
    T.Instance.GetPhysicalDeviceSurfaceSupportKHRError ||
    T.Instance.GetPhysicalDeviceSurfaceCapabilitiesKHRError ||
    T.Instance.GetPhysicalDeviceSurfaceFormatsKHRError ||
    T.Instance.GetPhysicalDeviceSurfacePresentModesKHRError ||
    std.mem.Allocator.Error;

pub fn create(ctx: *const Context) Error!Device {
    var device = try select_physical_device(ctx);
    device.handle = try device.create_logical_device(ctx);
    errdefer {
        device.handle.destroyDevice(null);
        ctx.allocator.destroy(device.handle.wrapper);
    }

    try device.create_queue_handles();
    device.graphics_command_pool = try device.create_graphics_command_pool();
    return device;
}

pub fn destroy(self: *Device, ctx: *const Context) void {
    self.handle.destroyCommandPool(self.graphics_command_pool, null);

    self.queues.graphics.handle = .null_handle;
    self.queues.present.handle = .null_handle;
    self.queues.transfer.handle = .null_handle;
    self.queues.compute.handle = .null_handle;

    self.handle.destroyDevice(null);
    ctx.allocator.destroy(self.handle.wrapper);

    self.pdev = .null_handle;
}

fn create_graphics_command_pool(self: Device) Error!vk.CommandPool {
    const create_info = vk.CommandPoolCreateInfo{
        .queue_family_index = self.queues.graphics.family,
        // NOTE: This flag indicates that we can reset the command buffers from this pool.
        // with either vkResetCommandBuffer or implictly within the vkBeginCommandBuffer calls.
        // If this flag is not set we must not call vkResetCommandBuffer. This is useful for performance reasons as
        // we can reuse the command buffer.
        .flags = .{ .reset_command_buffer_bit = true },
    };
    return self.handle.createCommandPool(&create_info, null);
}

fn create_queue_handles(self: *Device) Error!void {
    self.queues.graphics.init(self.handle);
    self.queues.present.init(self.handle);
    self.queues.transfer.init(self.handle);
    self.queues.compute.init(self.handle);
}

fn create_logical_device(self: Device, ctx: *const Context) Error!T.LogicalDevice {
    const p_shares_g = self.queues.present.family == self.queues.graphics.family;
    const t_shares_g = self.queues.transfer.family == self.queues.graphics.family;
    const c_shares_p = self.queues.compute.family == self.queues.present.family;

    var buffer: [4]u32 = undefined;
    var unique_queue_indices = std.ArrayListUnmanaged(u32).initBuffer(buffer[0..4]);
    // NOTE: We always need a graphics queue
    var index_count: u32 = 1;
    unique_queue_indices.appendAssumeCapacity(self.queues.graphics.family);
    if (!p_shares_g) {
        index_count += 1;
        unique_queue_indices.appendAssumeCapacity(self.queues.present.family);
    }
    if (!t_shares_g) {
        index_count += 1;
        unique_queue_indices.appendAssumeCapacity(self.queues.transfer.family);
    }
    if (!c_shares_p) {
        index_count += 1;
        unique_queue_indices.appendAssumeCapacity(self.queues.compute.family);
    }

    const queue_create_info = try ctx.allocator.alloc(vk.DeviceQueueCreateInfo, index_count);
    defer ctx.allocator.free(queue_create_info);

    const queue_priority = [_]f32{1.0};

    for (queue_create_info, 0..) |*info, i| {
        info.s_type = .device_queue_create_info;
        info.queue_family_index = unique_queue_indices.items[i];
        info.queue_count = 1;
        // TODO: Check if we need more than 1 queue for the graphics family
        // Some graphics cards might not have more than 1 queue
        // if (unique_queue_indices.items[i] == self.queues.graphics_family_index) {
        //     info.queue_count = 2;
        // }
        info.flags = .{};
        info.p_next = null;
        info.p_queue_priorities = &queue_priority;
    }

    // TODO: Get the device features from the engine
    const device_features = vk.PhysicalDeviceFeatures{
        .sampler_anisotropy = vk.TRUE,
    };

    const extension_names = [_][*:0]const u8{vk.extensions.khr_swapchain.name};

    const device_create_info = vk.DeviceCreateInfo{
        .p_next = null,
        .flags = .{},
        .queue_create_info_count = index_count,
        .p_queue_create_infos = queue_create_info.ptr,
        .p_enabled_features = &device_features,
        .enabled_extension_count = 1,
        .pp_enabled_extension_names = @ptrCast(&extension_names),
        // NOTE: Layers here are not a thing anymore?
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = null,
    };

    // NOTE: Create logical device. Phycial devices are not created directly, instead you request for a handle.
    // We create a logical device with queue familes. In most cases we work with the logical device.
    const device = try ctx.instance.createDevice(self.pdev, &device_create_info, null);
    const vkd = try ctx.allocator.create(T.LogicalDeviceDispatch);
    errdefer ctx.allocator.destroy(vkd);

    vkd.* = T.LogicalDeviceDispatch.load(device, ctx.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
    return T.LogicalDevice.init(device, vkd);
}

fn select_physical_device(ctx: *const Context) Error!Device {
    const physical_devices = try ctx.instance.enumeratePhysicalDevicesAlloc(ctx.allocator);
    defer ctx.allocator.free(physical_devices);

    // TODO: make this customizable
    var requirements = Requirements{
        .graphics = true,
        .present = true,
        .compute = true,
        .transfer = true,
        .discrete_gpu = true,
        .sample_anisotropy = true,
        .device_extension_names = std.ArrayList([*:0]const u8).init(ctx.allocator),
    };
    try requirements.device_extension_names.append(vk.extensions.khr_swapchain.name);
    defer requirements.device_extension_names.deinit();

    for (physical_devices) |candidate| {
        if (try check_device_requirements(
            ctx,
            candidate,
            &requirements,
        )) |queue_group| {
            ctx.log.debug("FOUND", .{});
            var supports_device_local_host_visable: bool = false;
            const memory_properties = ctx.instance.getPhysicalDeviceMemoryProperties(candidate);
            for (memory_properties.memory_types[0..memory_properties.memory_type_count]) |mem_type| {
                if (mem_type.property_flags.contains(.{ .host_visible_bit = true, .device_local_bit = true })) {
                    supports_device_local_host_visable = true;
                    break;
                }
            }
            return Device{
                .pdev = candidate,
                .queues = queue_group,
                .supports_device_local_host_visable = supports_device_local_host_visable,
            };
        }
    }

    return Error.NoPhysicalDeviceFound;
}

fn check_device_requirements(
    ctx: *const Context,
    device: vk.PhysicalDevice,
    requirements: *const Requirements,
) !?QueueGroup {
    const properties = ctx.instance.getPhysicalDeviceProperties(device);
    const features = ctx.instance.getPhysicalDeviceFeatures(device);
    const uint32_max = std.math.maxInt(u32);
    var dqfamilies: QueueGroup = .{};

    if (requirements.discrete_gpu and properties.device_type != .discrete_gpu) {
        ctx.log.debug("GPU found is not discrete. Skipping", .{});
        return null;
    }

    const queue_families = try ctx.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(device, ctx.allocator);
    defer ctx.allocator.free(queue_families);

    ctx.log.debug("Queue family count: {d}", .{queue_families.len});
    ctx.log.debug("G | P | C | T | Name", .{});
    var min_transfer_score: u8 = 255;
    for (queue_families, 0..) |family, i| {
        var current_tranfer_score: u8 = 0;
        if (family.queue_flags.contains(.{ .graphics_bit = true })) {
            if (requirements.graphics) {
                dqfamilies.graphics.family = @intCast(i);
                current_tranfer_score += 1;
            }
        }

        if (family.queue_flags.contains(.{ .compute_bit = true })) {
            if (requirements.graphics) {
                dqfamilies.compute.family = @intCast(i);
                current_tranfer_score += 1;
            }
        }

        if (family.queue_flags.contains(.{ .transfer_bit = true })) {
            if (requirements.transfer) {
                if (current_tranfer_score < min_transfer_score) {
                    // NOTE: For the transfer queue we want to choose the family with the lowest number of collisions
                    min_transfer_score = current_tranfer_score;
                    dqfamilies.transfer.family = @intCast(i);
                }
            }
        }

        const present_support = try ctx.instance.getPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), ctx.surface);
        if (present_support != 0) {
            if (requirements.present) {
                dqfamilies.present.family = @intCast(i);
            }
        }
    }

    ctx.log.debug("{d} | {d} | {d} | {d} | {s}", .{
        @intFromBool(dqfamilies.graphics.family != uint32_max),
        @intFromBool(dqfamilies.present.family != uint32_max),
        @intFromBool(dqfamilies.compute.family != uint32_max),
        @intFromBool(dqfamilies.transfer.family != uint32_max),
        std.mem.sliceTo(&properties.device_name, 0),
    });

    if ((!requirements.graphics or (requirements.graphics and dqfamilies.graphics.family != uint32_max)) and
        (!requirements.present or (requirements.present and dqfamilies.present.family != uint32_max)) and
        (!requirements.compute or (requirements.compute and dqfamilies.compute.family != uint32_max)) and
        (!requirements.transfer or (requirements.transfer and dqfamilies.transfer.family != uint32_max)))
    {
        ctx.log.debug("Device meets all requirements", .{});
        ctx.log.debug(
            "Queue family indicies: G: {d}, P: {d}, C: {d}, T: {d}",
            .{
                dqfamilies.graphics.family,
                dqfamilies.present.family,
                dqfamilies.compute.family,
                dqfamilies.transfer.family,
            },
        );

        if (try query_swapchain_support(ctx, device)) |_| {} else {
            // NOTE: We do not have either enough formats or present modes
            return null;
        }

        if (!(try query_extension_support(ctx, device, requirements))) {
            // NOTE: We do not have either enough formats or present modes
            return null;
        }

        if (requirements.sample_anisotropy and (features.sampler_anisotropy == vk.FALSE)) {
            return null;
        }

        // NOTE: we have satisfied all the requirements
        return dqfamilies;
    }

    return null;
}

fn query_extension_support(ctx: *const Context, device: vk.PhysicalDevice, requirements: *const Requirements) Error!bool {
    if (requirements.device_extension_names.items.len > 0) {
        const extensions = try ctx.instance.enumerateDeviceExtensionPropertiesAlloc(device, null, ctx.allocator);
        defer ctx.allocator.free(extensions);
        for (requirements.device_extension_names.items) |req_ext| {
            for (extensions) |ext| {
                if (std.mem.eql(u8, std.mem.span(req_ext), std.mem.sliceTo(&ext.extension_name, 0))) {
                    break;
                }
            } else {
                ctx.log.debug(
                    "Device: does not support the required extnsion: {s}",
                    .{req_ext},
                );
                return false;
            }
        }
    }

    return true;
}

fn query_swapchain_support(ctx: *const Context, device: vk.PhysicalDevice) Error!?void {
    const formats = try ctx.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(
        device,
        ctx.surface,
        ctx.allocator,
    );
    defer ctx.allocator.free(formats);
    if (formats.len == 0) {
        return null;
    }

    const present_modes = try ctx.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(
        device,
        ctx.surface,
        ctx.allocator,
    );
    defer ctx.allocator.free(present_modes);
    if (present_modes.len == 0) {
        return null;
    }
}

const Requirements = struct {
    graphics: bool,
    present: bool,
    compute: bool,
    transfer: bool,
    sample_anisotropy: bool,
    discrete_gpu: bool,
    device_extension_names: std.ArrayList([*:0]const u8),
};

const std = @import("std");
const assert = std.debug.assert;
