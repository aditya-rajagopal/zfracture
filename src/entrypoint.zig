const std = @import("std");
const root = @import("root");
const fracture = @import("fracture");
const printf = std.debug.print;

pub const API = struct {
    start: *const fn () void,
};

const api = if (@hasDecl(root, "api")) root.api else @compileError("The root app must declare API");

pub fn main() !void {
    api.start();
    fracture.test_fn();
}
