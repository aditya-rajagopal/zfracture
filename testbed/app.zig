pub usingnamespace @import("entrypoint");

pub const api = .{
    .start = start,
};

fn start() void {
    printf("All your {s} are belong to us.\n", .{"games"});
}

const std = @import("std");
const printf = std.debug.print;
