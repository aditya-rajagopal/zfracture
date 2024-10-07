const std = @import("std");

test "something" {
    const D = 8;
    try std.testing.expect(8 == D);
}
