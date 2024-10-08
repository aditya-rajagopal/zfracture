pub const config = @import("config.zig");
pub const core = @import("fr_core");
pub const core_log = core.log.core_log;
pub const log = core.log.log;
pub const assert = core.assert;
pub const debug_assert = core.debug_assert;

pub fn test_fn() void {
    core_log.trace("All your {s} are belong to us.", .{"engines"});
    core_log.debug("All your {s} are belong to us.", .{"engines"});
    core_log.info("All your {s} are belong to us.", .{"engines"});
    core_log.warn("All your {s} are belong to us.", .{"engines"});
    core_log.err("All your {s} are belong to us.", .{"engines"});
    core_log.fatal("All your {s} are belong to us.", .{"engines"});
    debug_assert(1 == 1);
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

const std = @import("std");
