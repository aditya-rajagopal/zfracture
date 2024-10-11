const fracture = @import("fracture");
const platform = @import("platform");
const core = @import("fr_core");

const root = @import("root");
pub const app_start: *const fn (std.mem.Allocator) void = if (@hasDecl(root, "start"))
    root.start
else
    @compileError("app.zig must define a pub fn start(std.mem.Allocator) void {}");

pub fn main() !void {
    const allocator = platform.get_allocator();

    core.logging.init();
    errdefer core.logging.deinit();
    fracture.core_log.info("Logging system has been initialized", .{});

    app_start(allocator);

    try fracture.application.init(allocator);
    errdefer fracture.application.deinit();

    try fracture.application.run();

    fracture.application.deinit();

    core.logging.deinit();
    fracture.core_log.info("Logging system has been shutdown", .{});
}

const std = @import("std");
