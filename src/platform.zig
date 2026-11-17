//! Executable-owned native window and event helpers. Start with `.empty` and
//! initialize in place on the main thread. Callbacks borrow this address until window destruction.
const std = @import("std");
const builtin = @import("builtin");

const FrameBuffer = @import("FrameBuffer.zig");
const Event = @import("event.zig").Event;
const Platform = @This();
const backend = switch (builtin.os.tag) {
    .macos => @import("macos/platform.zig"),
    .windows => @import("windows/platform.zig"),
    else => @compileError("Unsupported platform"),
};

native: backend.State,
initialized: bool,
window_live: bool,

pub const empty: Platform = .{
    .native = .{},
    .initialized = false,
    .window_live = false,
};

pub const PixelSize = struct { width: u16, height: u16 };

pub const WindowConfig = struct {
    title: [:0]const u8,
    /// Requested drawable size in pixels.
    width: u16,
    height: u16,
};

pub const WindowStatus = struct {
    quit_requested: bool,
    /// Informational: returning polls may still update and render while this is true.
    native_interaction_active: bool,
    /// A known blocking interaction completed. Consume independently of active tracking.
    blocking_interaction_ended: bool,
};

pub const InitError = backend.InitError || backend.CreateWindowError || error{InvalidWindowSize};
pub const PaceFrameError = std.Io.Cancelable || backend.WaitError || error{InvalidFrameDuration};
pub const DynamicLibrary = backend.DynamicLibrary;
pub const processId = backend.processId;

/// A config creates a hidden window. Pass null for windowless platform services.
pub fn init(self: *Platform, window_config: ?WindowConfig) InitError!void {
    self.* = .empty;
    try self.native.init();
    errdefer self.native.deinit();
    if (window_config) |config| {
        if (config.width == 0 or config.height == 0) return error.InvalidWindowSize;
        try self.native.createWindow(config);
        self.window_live = true;
    }
    self.initialized = true;
}

pub fn deinit(self: *Platform) void {
    std.debug.assert(self.initialized);
    if (self.window_live) {
        self.native.destroyWindow();
        self.window_live = false;
    }
    self.native.deinit();
    self.initialized = false;
}

pub fn showWindow(self: *Platform) void {
    self.assertWindow();
    self.native.showWindow();
}

pub fn drawableSize(self: *Platform) PixelSize {
    self.assertWindow();
    return self.native.drawableSize();
}

/// Paces the frame until frame_start + frame_duration on Clock.awake.
/// Call on this platform's owning thread. No window is required.
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
    var now_ns: i128 = std.Io.Clock.awake.now(io).nanoseconds;
    if (now_ns >= deadline_ns) return;

    // As in SDL_DelayPrecise, measure short sleeps during this wait and
    // leave room for their observed overshoot on the final sleep.
    const short_sleep_ns = std.time.ns_per_ms;
    var spin_reserve_ns: i128 = 0;
    while (true) {
        const sleep_ns = @min(short_sleep_ns, deadline_ns - now_ns - spin_reserve_ns);
        if (sleep_ns <= 0) break;
        const wake = std.Io.Timestamp.fromNanoseconds(@intCast(now_ns + sleep_ns));
        try self.native.waitUntil(io, wake);
        try io.checkCancel();
        now_ns = std.Io.Clock.awake.now(io).nanoseconds;
        // A scheduling stall should never turn into a multi-millisecond spin.
        spin_reserve_ns = @min(short_sleep_ns, @max(spin_reserve_ns, now_ns - wake.nanoseconds));
    }
    while (std.Io.Clock.awake.now(io).nanoseconds < deadline_ns) {
        std.atomic.spinLoopHint();
    }
    try io.checkCancel();
}

pub fn pollEvents(self: *Platform) WindowStatus {
    self.assertWindow();
    return self.native.pollEvents();
}

/// Drain after every returned poll, including native interactions.
/// The slice remains valid until the next handoff or platform teardown.
pub fn takeEvents(self: *Platform) []const Event {
    self.assertWindow();
    return self.native.takeEvents();
}

/// Submit a completed frame. The caller may reuse or free its pixels on return.
pub fn softwarePresent(self: *Platform, buffer: *const FrameBuffer) void {
    self.assertWindow();
    validateSoftwareFramebuffer(buffer) catch @panic("Cannot present an invalid framebuffer");
    self.native.softwarePresent(buffer);
}

fn validateSoftwareFramebuffer(buffer: *const FrameBuffer) error{InvalidFramebuffer}!void {
    if (buffer.width == 0 or buffer.height == 0) return error.InvalidFramebuffer;
    const required_bytes = @as(usize, buffer.width) * buffer.height * FrameBuffer.bytes_per_pixel;
    if (buffer.data.len < required_bytes) return error.InvalidFramebuffer;
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
    var pixels: [4]u8 align(4096) = @splat(0);
    var cases = [_]FrameBuffer{
        .{ .width = 0, .height = 1, .data = &pixels },
        .{ .width = 1, .height = 0, .data = &pixels },
        .{ .width = 1, .height = 2, .data = &pixels }, // Storage fits only one pixel.
    };
    for (&cases) |*buffer| {
        try std.testing.expectError(error.InvalidFramebuffer, validateSoftwareFramebuffer(buffer));
    }
}

test {
    std.testing.refAllDecls(backend);
}

test "frame pacing rejects overflow and preserves independent timer lifetimes" {
    var first: Platform = .empty;
    try first.init(null);
    defer first.deinit();
    var second: Platform = .empty;
    try second.init(null);
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
    const start = std.Io.Clock.awake.now(io);
    try first.paceFrame(io, start, duration);
    try std.testing.expect(std.Io.Clock.awake.now(io).nanoseconds >= start.nanoseconds + duration.nanoseconds);
}
