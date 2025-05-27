pub fn Generation(comptime T: type) type {
    const info = @typeInfo(T);
    comptime assert(info == .int);
    comptime assert(info.int.signedness == .unsigned);

    const max_int = std.math.maxInt(T);

    return enum(T) {
        null_handle = max_int,
        _,

        const Self = @This();
        pub fn increment(self: Self) Self {
            assert(@intFromEnum(self) != max_int - 1);
            return @enumFromInt(@as(T, @intFromEnum(self)) + 1);
        }
    };
}

const max_u32 = @import("std").math.maxInt(u32);
const std = @import("std");
const assert = std.debug.assert;
