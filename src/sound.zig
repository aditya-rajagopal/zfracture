const std = @import("std");
const builtin = @import("builtin");

pub const AudioEngine = switch (builtin.os.tag) {
    .windows => @import("windows/xaudio2.zig"),
    else => @compileError("Unsupported OS"),
};

ctx: AudioEngine,
pool: SoundPool,

const Self = @This();

pub fn init() AudioEngine.Error!Self {
    const ctx = try AudioEngine.init();
    return Self{ .ctx = ctx, .pool = undefined };
}

pub fn deinit(self: *Self) void {
    self.ctx.deinit();
}

pub fn storeSound(self: *Self, data: []const u8) SoundHandle {
    _ = self;
    _ = data;
    return SoundHandle{};
}

pub fn playSound(self: *Self, data: []const u8, params: AudioEngine.PlaybackParams) void {
    // _ = handle;
    self.ctx.playSound(data, params);
}

pub fn stopSound(self: *Self, handle: SoundHandle) void {
    _ = self;
    _ = handle;
}

pub const SoundHandle = enum(u32) { nullhandle = std.math.maxInt(u32), _ };
pub const Sound = struct {
    data: ?[]const u8,
};
pub const SoundPool = struct {
    pool: [32]Sound,
};
