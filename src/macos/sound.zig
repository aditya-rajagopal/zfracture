//! Silent macOS backend until native audio is implemented.
const Self = @This();

pub const PlaybackParams = struct {
    play_begin: u32 = 0,
    play_length: u32 = 0,
    loop_begin: u32 = 0,
    loop_length: u32 = 0,
    loop_count: u32 = 0,
};

pub const Error = error{};

pub fn init(self: *Self) Error!void {
    self.* = .{};
}

pub fn deinit(_: *Self) void {}

/// Accept and discard playback requests without retaining the sample data.
pub fn playSound(_: *Self, _: []const u8, _: PlaybackParams) bool {
    return true;
}

pub fn stopSound(_: *Self, _: []const u8) void {}
