const T = @import("types.zig");
const Texture = @This();

id: T.ResourceHandle = .null_handle,
generation: T.Generation = .null_handle,
width: u32 = 0,
height: u32 = 0,
channel_count: u8 = 0,
has_transparency: u8 = 0,
data: ?*anyopaque = null,
