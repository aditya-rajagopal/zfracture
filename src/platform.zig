//! Executable-owned native window and event helpers. Start with `.{}` and
//! initialize in place on the main thread. Callbacks borrow this address until window destruction.
//! The app owns its loop and pairs beginFrame/endFrame.
const std = @import("std");
const builtin = @import("builtin");

const Renderer = @import("software_renderer.zig");
const Event = @import("event.zig").Event;
const Platform = @This();
const backend = switch (builtin.os.tag) {
    .macos => @import("macos/platform.zig"),
    .windows => @import("windows/platform.zig"),
    else => @compileError("Unsupported platform"),
};

native: backend.State = .{},
initialized: bool = false,
window_live: bool = false,
frame_active: bool = false,

pub const WindowConfig = struct {
    title: [:0]const u8,
    frame_buffer: *Renderer.FrameBuffer,
    windowed_frame_margin: u16 = 10,
};

pub const WindowStatus = struct {
    quit_requested: bool,
    native_interaction_active: bool,
    interaction_ended: bool,
};

pub const InitError = backend.InitError;
pub const CreateWindowError = backend.CreateWindowError || error{InvalidFramebuffer};
pub const DynamicLibrary = backend.DynamicLibrary;
pub const processId = backend.processId;

pub fn init(self: *Platform) InitError!void {
    self.* = .{};
    try self.native.init();
    self.initialized = true;
}

pub fn deinit(self: *Platform) void {
    std.debug.assert(self.initialized);
    std.debug.assert(!self.window_live);
    std.debug.assert(!self.frame_active);
    self.native.deinit();
    self.initialized = false;
}

pub fn createWindow(self: *Platform, config: WindowConfig) CreateWindowError!void {
    std.debug.assert(self.initialized);
    std.debug.assert(!self.window_live);
    const buffer = config.frame_buffer;
    if (buffer.width == 0) return error.InvalidFramebuffer;
    if (buffer.height == 0) return error.InvalidFramebuffer;
    const required_bytes = @as(usize, buffer.width) * buffer.height * Renderer.bytes_per_pixel;
    if (buffer.data.len < required_bytes) return error.InvalidFramebuffer;
    try self.native.createWindow(config);
    self.window_live = true;
}

pub fn destroyWindow(self: *Platform) void {
    self.assertWindow();
    self.native.destroyWindow();
    self.window_live = false;
}

pub fn showWindow(self: *Platform) void {
    self.assertWindow();
    self.native.showWindow();
}

pub fn beginFrame(self: *Platform) void {
    std.debug.assert(self.initialized);
    std.debug.assert(!self.frame_active);
    self.native.beginFrame();
    self.frame_active = true;
}

pub fn endFrame(self: *Platform) void {
    std.debug.assert(self.initialized);
    std.debug.assert(self.frame_active);
    self.native.endFrame();
    self.frame_active = false;
}

pub fn pollEvents(self: *Platform) WindowStatus {
    self.assertWindow();
    std.debug.assert(self.frame_active);
    return self.native.pollEvents();
}

/// The slice remains valid until the next handoff or platform teardown.
pub fn takeEvents(self: *Platform) []const Event {
    self.assertWindow();
    return self.native.takeEvents();
}

pub fn present(self: *Platform) void {
    self.assertWindow();
    std.debug.assert(self.frame_active);
    self.native.present();
}

pub fn setCursorHidden(self: *Platform, hidden: bool) void {
    self.assertWindow();
    self.native.setCursorHidden(hidden);
}

pub fn toggleFullscreen(self: *Platform) void {
    self.assertWindow();
    self.native.toggleFullscreen();
}

fn assertWindow(self: *const Platform) void {
    std.debug.assert(self.initialized);
    std.debug.assert(self.window_live);
}

test "invalid framebuffer does not create a native window" {
    var platform: Platform = .{};
    try platform.init();
    defer platform.deinit();
    var pixels: [4]u8 align(4096) = @splat(0);
    var buffer: Renderer.FrameBuffer = .{ .width = 0, .height = 1, .data = &pixels };
    try std.testing.expectError(error.InvalidFramebuffer, platform.createWindow(.{ .title = "test", .frame_buffer = &buffer }));
    buffer.width = 1;
    buffer.height = 0;
    try std.testing.expectError(error.InvalidFramebuffer, platform.createWindow(.{ .title = "test", .frame_buffer = &buffer }));
    buffer.height = 2;
    try std.testing.expectError(error.InvalidFramebuffer, platform.createWindow(.{ .title = "test", .frame_buffer = &buffer }));
}

test {
    std.testing.refAllDecls(backend);
}
