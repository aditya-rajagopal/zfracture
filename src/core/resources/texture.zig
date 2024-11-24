const T = @import("types.zig");

pub const Texture = struct {
    pub const DataSize = 8;

    id: T.ResourceHandle = .null_handle,
    generation: T.Generation = .null_handle,
    width: u32 = 0,
    height: u32 = 0,
    channel_count: u8 = 0,
    has_transparency: u8 = 0,
    data: Data,

    /// Opaque data that is managed by the renderer
    pub const Data = struct {
        data: [DataSize]u64,

        pub fn as(self: *Data, comptime E: type) *E {
            const size = @sizeOf(E);
            comptime assert(size <= DataSize * 8);
            return @alignCast(std.mem.bytesAsValue(E, &self.data[0]));
        }

        pub fn as_const(self: *const Data, comptime E: type) *const E {
            const size = @sizeOf(E);
            comptime assert(size <= DataSize * 8);
            return @alignCast(std.mem.bytesAsValue(E, &self.data[0]));
        }
    };
};

const std = @import("std");
const assert = std.debug.assert;
