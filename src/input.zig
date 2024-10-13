const core_log = @import("fr_core").logging.core_log;

pub fn test_fn() void {
    core_log.trace("Event!", .{});
}
