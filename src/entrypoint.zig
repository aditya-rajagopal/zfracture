const fracture = @import("fracture");
const platform = @import("platform");
const core = @import("fr_core");

pub fn main() !void {
    const allocator = platform.get_allocator();

    core.logging.init();
    errdefer core.logging.deinit();
    fracture.core_log.info("Logging system has been initialized", .{});

    fracture.config.app_start(allocator);

    try fracture.application.init(allocator);
    errdefer fracture.application.deinit();

    try fracture.application.run();

    fracture.application.deinit();

    core.logging.deinit();
    fracture.core_log.info("Logging system has been shutdown", .{});
}
