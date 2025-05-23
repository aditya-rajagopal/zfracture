const application = @import("application.zig");
const core = @import("fr_core");

// const root = @import("root");
// pub const app_start: *const fn (std.mem.Allocator) void = if (@hasDecl(root, "start"))
//     root.start
// else
//     @compileError("app.zig must define a pub fn start(std.mem.Allocator) void {}");

/// Entrypoint function for the application. The applictaion must forward this function as the main function.
pub fn entrypoint() !void {
    // Allocator init
    // TODO: Get the allocator from somewhere else. Platform?

    // const allocator = std.mem.Allocator{
    //     .ptr = undefined,
    //     .vtable = &std.heap.SmpAllocator.vtable,
    // };
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            @panic("memory leak");
        }
    }

    var app = switch (builtin.mode) {
        .Debug, .ReleaseSafe => try application.init(allocator),
        else => try application.init(std.heap.page_allocator),
    };
    errdefer app.deinit();

    try app.run();

    app.deinit();
}

const std = @import("std");
const builtin = @import("builtin");
