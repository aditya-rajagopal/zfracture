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
    /// Informational: returning polls may still update and render while this is true.
    native_interaction_active: bool,
    /// A known blocking interaction completed. Consume independently of active tracking.
    blocking_interaction_ended: bool,
};

pub const InitError = backend.InitError;
pub const PaceFrameError = std.Io.Cancelable || backend.WaitError || error{InvalidFrameDuration};
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

/// Caps this frame at frame_start + frame_duration on Clock.awake.
/// Call on this platform's owning thread, including after endFrame. No window is required.
/// Windows cancellation is checked at wait boundaries; it does not interrupt a native wait.
pub fn paceFrame(
    self: *Platform,
    io: std.Io,
    frame_start: std.Io.Timestamp,
    frame_duration: std.Io.Duration,
) PaceFrameError!void {
    std.debug.assert(self.initialized);
    try io.checkCancel();
    if (frame_duration.nanoseconds <= 0) return;
    const deadline_ns = std.math.add(i96, frame_start.nanoseconds, frame_duration.nanoseconds) catch
        return error.InvalidFrameDuration;
    const deadline = std.Io.Timestamp.fromNanoseconds(deadline_ns);

    while (std.Io.Clock.awake.now(io).nanoseconds < deadline_ns) {
        try self.native.waitUntil(io, deadline);
        try io.checkCancel();
    }
}

pub fn pollEvents(self: *Platform) WindowStatus {
    self.assertWindow();
    std.debug.assert(self.frame_active);
    return self.native.pollEvents();
}

/// Drain after every returned poll, including native interactions.
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

test "invalid framebuffer dimensions and storage are rejected" {
    var platform: Platform = .{};
    try platform.init();
    defer platform.deinit();
    var pixels: [4]u8 align(4096) = @splat(0);
    var cases = [_]Renderer.FrameBuffer{
        .{ .width = 0, .height = 1, .data = &pixels },
        .{ .width = 1, .height = 0, .data = &pixels },
        .{ .width = 1, .height = 2, .data = &pixels }, // Storage fits only one pixel.
    };
    for (&cases) |*buffer| {
        try std.testing.expectError(error.InvalidFramebuffer, platform.createWindow(.{ .title = "test", .frame_buffer = buffer }));
    }
}

test {
    std.testing.refAllDecls(backend);
}

test "frame pacing rejects overflow and preserves independent timer lifetimes" {
    var first: Platform = .{};
    try first.init();
    defer first.deinit();
    var second: Platform = .{};
    try second.init();
    if (builtin.os.tag == .windows) {
        try std.testing.expect(first.native.frame_timer != second.native.frame_timer);
    }
    second.deinit();
    const io = std.testing.io;
    try std.testing.expectError(error.InvalidFrameDuration, first.paceFrame(
        io,
        .fromNanoseconds(std.math.maxInt(i96)),
        .fromNanoseconds(1),
    ));
    const duration: std.Io.Duration = .fromMilliseconds(2);
    first.beginFrame();
    first.endFrame();
    const start = std.Io.Clock.awake.now(io);
    try first.paceFrame(io, start, duration);
    try std.testing.expect(std.Io.Clock.awake.now(io).nanoseconds >= start.nanoseconds + duration.nanoseconds);
}
