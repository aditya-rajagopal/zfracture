const root = @import("root");
const std = @import("std");

pub const API = struct {
    init: *const fn (allocator: std.mem.Allocator) bool,
    deinit: *const fn () void,
    update: *const fn (delta_time: f64) bool,
    render: *const fn (delta_time: f64) bool,
    on_resize: *const fn (width: u32, height: u32) void,
};

pub const app_api: API = if (@hasDecl(root, "config") and @hasDecl(root.config, "app_api"))
    root.config.app_api
else
    @compileError("The root.config app must declare app_api");

pub const app_start: *const fn (std.mem.Allocator) void = if (@hasDecl(root, "start"))
    root.start
else
    @compileError("app.zig must define a pub fn start(std.mem.Allocator) void {}");

pub const AppConfig = struct {
    application_name: [:0]const u8,
    window_pos: struct { x: i32, y: i32, width: i32, height: i32 },
};
pub const app_config: AppConfig = if (@hasDecl(root, "config") and @hasDecl(root.config, "app_config"))
    root.config.app_config
else
    @compileError("The root.conig app must declare app_config");
