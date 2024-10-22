const m = @import("fr_core").math;
const vk = @import("vulkan");
const T = @import("types.zig");

const Context = @import("context.zig");
pub const CommandBuffer = @This();

handle: T.CommandBuffer,
state: T.CommandBufferState,
