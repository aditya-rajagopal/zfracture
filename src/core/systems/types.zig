pub const ResourceHandle = enum(u32) { null_handle = std.math.maxInt(u32), _ };

pub const Generation = enum(u32) {
    null_handle = max_u32,
    _,
    pub fn increment(self: Generation) Generation {
        assert(@intFromEnum(self) != max_u32 - 1);
        return @enumFromInt(@as(u32, @intFromEnum(self)) +% 1);
    }
};

//TODO: Make the generation part of the systems. This does not need to be in teh handle? Or keep it and add the UUID
// The UUID can be the thing that is used in the hash map instead of the string
pub const Handle = extern struct {
    id: ResourceHandle = .null_handle,
    generation: Generation = .null_handle,
};

pub const ResourceTypes = enum(u4) {
    binary,
    image,
    // texture,
    // material,
    // sound,
    // static_mesh,
    // dynamic_mesh,
    // custom = 15,
};

const max_u32 = @import("std").math.maxInt(u32);
const std = @import("std");
const assert = std.debug.assert;
