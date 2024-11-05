const Texture = @This();

id: u32 = 0,
generation: u32 = 0,
width: u32 = 0,
height: u32 = 0,
channel_count: u8 = 0,
has_transparency: u8 = 0,
data: ?*anyopaque = null,
