pub const ResourceHandle = enum(u32) { null_handle = max_u32, _ };
pub const Generation = enum(u32) { null_handle = max_u32, _ };

const max_u32 = @import("std").math.maxInt(u32);
