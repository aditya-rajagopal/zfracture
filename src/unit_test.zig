const app = @import("application.zig");
const platform = @import("platform/platform.zig");

test {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
