pub const ResourceHandle = enum(u32) { null_handle = max_u32, _ };

pub const Generation = enum(u32) {
    null_handle = max_u32,
    _,
    pub fn increment(self: Generation) Generation {
        assert(@intFromEnum(self) != max_u32 - 1);
        return @enumFromInt(@as(u32, @intFromEnum(self)) +% 1);
    }
};

pub const Handle = extern struct {
    id: ResourceHandle = .null_handle,
    generation: Generation = .null_handle,
};

const max_u32 = @import("std").math.maxInt(u32);
const std = @import("std");
const assert = std.debug.assert;
