pub const app = @import("application.zig");
pub const platform = @import("platform/platform.zig");
pub const frontend = @import("renderer/frontend.zig");

test "Unit tests" {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
