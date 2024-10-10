pub usingnamespace @import("entrypoint");
pub const config = @import("config.zig");

pub fn start(allocator: std.mem.Allocator) void {
    // If you need some startup code here.
    _ = allocator;
}

const std = @import("std");
