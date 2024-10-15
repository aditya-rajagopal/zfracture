const application = @import("application.zig");
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
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            @panic("memory leak");
        }
    }

    var app = try application.init(allocator);
    errdefer app.deinit();

    try app.run();

    app.deinit();
}

const std = @import("std");
