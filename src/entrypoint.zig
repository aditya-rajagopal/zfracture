const fracture = @import("fracture");
const platform = @import("platform");
const core = @import("fr_core");

// const root = @import("root");
// pub const app_start: *const fn (std.mem.Allocator) void = if (@hasDecl(root, "start"))
//     root.start
// else
//     @compileError("app.zig must define a pub fn start(std.mem.Allocator) void {}");

pub fn main() !void {
    // Allocator init
    // TODO: Get the allocator from somewhere else. Platform?
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    errdefer {
        const check = gpa.deinit();
        if (check == .leak) {
            @panic("memory leak");
        }
    }

    try fracture.application.init(allocator);
    errdefer fracture.application.deinit();
    fracture.core_log.info("Application has been initialized", .{});

    try fracture.application.run();

    fracture.application.deinit();

    const check = gpa.deinit();
    if (check == .leak) {
        @panic("memory leak");
    }
}

const std = @import("std");
