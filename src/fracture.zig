pub const config = @import("config.zig");
const core = @import("fr_core");
pub const core_log = core.logging.core_log;
pub const log = core.logging.log;
const assert = core.asserts.assert;
const assert_msg = core.asserts.assert_msg;
const debug_assert = core.asserts.debug_assert;
const never = core.asserts.never;

pub fn test_fn() void {
    core_log.trace("All your {s} are belong to us.", .{"engines"});
    core_log.debug("All your {s} are belong to us.", .{"engines"});
    core_log.info("All your {s} are belong to us.", .{"engines"});
    core_log.warn("All your {s} are belong to us.", .{"engines"});
    core_log.err("All your {s} are belong to us.", .{"engines"});
    core_log.fatal("All your {s} are belong to us.", .{"engines"});
    debug_assert(1 == 1, @src());
    assert_msg(1 == 1, @src(), "Failed to have 1 and 2 equal : {d}", .{1});
    if (1 == 0) {
        never(@src());
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

const std = @import("std");
