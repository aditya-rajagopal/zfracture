//! Native output for fracture's one-shot PCM playback. See fracture.SoundSystem
//! for thread ownership, stable-address and sample-buffer lifetime requirements.
const std = @import("std");
const SoundSystem = @import("../sound.zig");
const c = @import("audio-c");

pub const InitError = error{
    OutputComponentUnavailable,
    FailedToCreateOutput,
    FailedToConfigureOutput,
    FailedToInitializeOutput,
    FailedToStartOutput,
};
pub const PlayError = SoundSystem.PlayError;

pub const State = struct {
    unit: c.AudioUnit = null,
    // Play initializes before publication; the callback owns them until completion.
    cursors_bytes: [SoundSystem.voice_capacity]usize = @splat(0),
};

/// Call in executable-owned code, so the native callback outlives game hot reload.
/// AudioToolbox owns any native allocations; no allocator is needed for the pool.
pub fn init(self: *SoundSystem) InitError!void {
    self.* = .{};
    var description = c.AudioComponentDescription{
        .componentType = c.kAudioUnitType_Output,
        .componentSubType = c.kAudioUnitSubType_DefaultOutput,
        .componentManufacturer = c.kAudioUnitManufacturer_Apple,
        .componentFlags = 0,
        .componentFlagsMask = 0,
    };
    const component = c.AudioComponentFindNext(null, &description) orelse
        return error.OutputComponentUnavailable;
    if (c.AudioComponentInstanceNew(component, &self.native.unit) != 0) {
        return error.FailedToCreateOutput;
    }
    errdefer {
        _ = c.AudioComponentInstanceDispose(self.native.unit);
        self.native.unit = null;
    }

    var format = std.mem.zeroes(c.AudioStreamBasicDescription);
    format.mSampleRate = SoundSystem.sample_rate_hz;
    format.mFormatID = c.kAudioFormatLinearPCM;
    format.mFormatFlags = c.kAudioFormatFlagIsFloat | c.kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = SoundSystem.channels * @sizeOf(f32);
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = SoundSystem.channels * @sizeOf(f32);
    format.mChannelsPerFrame = SoundSystem.channels;
    format.mBitsPerChannel = 32;
    if (c.AudioUnitSetProperty(
        self.native.unit,
        c.kAudioUnitProperty_StreamFormat,
        c.kAudioUnitScope_Input,
        0,
        &format,
        @sizeOf(@TypeOf(format)),
    ) != 0) {
        return error.FailedToConfigureOutput;
    }
    var callback = c.AURenderCallbackStruct{ .inputProc = render, .inputProcRefCon = self };
    if (c.AudioUnitSetProperty(
        self.native.unit,
        c.kAudioUnitProperty_SetRenderCallback,
        c.kAudioUnitScope_Input,
        0,
        &callback,
        @sizeOf(@TypeOf(callback)),
    ) != 0) {
        return error.FailedToConfigureOutput;
    }

    if (c.AudioUnitInitialize(self.native.unit) != 0) return error.FailedToInitializeOutput;
    errdefer _ = c.AudioUnitUninitialize(self.native.unit);

    if (c.AudioOutputUnitStart(self.native.unit) != 0) return error.FailedToStartOutput;
}

pub fn deinit(self: *SoundSystem) void {
    _ = c.AudioOutputUnitStop(self.native.unit);
    _ = c.AudioUnitUninitialize(self.native.unit);
    _ = c.AudioComponentInstanceDispose(self.native.unit);
    self.native.unit = null;
}

pub fn update(_: *SoundSystem) void {}

pub fn play(self: *SoundSystem, data: []const u8) PlayError!SoundSystem.PlaybackHandle {
    const reservation = try self.pool.reserve(data);
    self.native.cursors_bytes[reservation.index] = 0;
    self.pool.slots[reservation.index].state.store(.active, .release);
    return reservation.handle;
}

pub fn stop(self: *SoundSystem, handle: SoundSystem.PlaybackHandle) void {
    _ = self.pool.requestStop(handle);
}

fn render(
    context: ?*anyopaque,
    _: [*c]c.AudioUnitRenderActionFlags,
    _: [*c]const c.AudioTimeStamp,
    _: c.UInt32,
    frames: c.UInt32,
    buffers: [*c]c.AudioBufferList,
) callconv(.c) c.OSStatus {
    const self: *SoundSystem = @ptrCast(@alignCast(context));
    // We requested one interleaved stereo buffer; never cast or write an
    // unexpected native buffer layout. AudioUnit treats failure as no output.
    if (buffers == null) return c.kAudio_ParamError;
    if (buffers.*.mNumberBuffers != 1) return c.kAudio_ParamError;
    const buffer = &buffers.*.mBuffers[0];
    const samples = @as(usize, frames) * SoundSystem.channels;
    if (buffer.mNumberChannels != SoundSystem.channels) return c.kAudio_ParamError;
    if (buffer.mData == null) return c.kAudio_ParamError;
    if (buffer.mDataByteSize < samples * @sizeOf(f32)) return c.kAudio_ParamError;
    const output: [*]f32 = @ptrCast(@alignCast(buffer.mData));
    mix(self, output[0..samples]);
    return 0;
}

/// Audio thread only. Output is interleaved stereo float PCM at SoundSystem.sample_rate_hz.
fn mix(self: *SoundSystem, output: []f32) void {
    std.debug.assert(output.len % SoundSystem.channels == 0);
    @memset(output, 0);
    for (&self.pool.slots, &self.native.cursors_bytes) |*slot, *cursor_bytes| {
        switch (slot.state.load(.acquire)) {
            .stop_requested => {
                slot.complete();
                continue;
            },
            .active => {},
            else => continue,
        }
        std.debug.assert(slot.data.len > 0);
        std.debug.assert(slot.data.len % SoundSystem.bytes_per_frame == 0);
        std.debug.assert(cursor_bytes.* <= slot.data.len);
        std.debug.assert(cursor_bytes.* % SoundSystem.bytes_per_frame == 0);
        const sample_count = @min(output.len, (slot.data.len - cursor_bytes.*) / @sizeOf(i16));
        for (output[0..sample_count], 0..) |*sample, index| {
            const offset = cursor_bytes.* + index * @sizeOf(i16);
            const pcm = std.mem.readInt(i16, slot.data[offset..][0..2], .little);
            sample.* += @as(f32, @floatFromInt(pcm)) / 32768.0;
        }
        cursor_bytes.* += sample_count * @sizeOf(i16);
        if (cursor_bytes.* == slot.data.len) slot.complete();
    }
    for (output) |*sample| sample.* = std.math.clamp(sample.*, -1, 1);
}

test "mixer overlap, stereo conversion, partial completion and stop requests" {
    var sound: SoundSystem = .{};
    // Two stereo frames: (+0.5, -0.5), (+0.25, -1).
    const data = [_]u8{ 0, 0x40, 0, 0xc0, 0, 0x20, 0, 0x80 };
    const first = try sound.play(&data);
    _ = try sound.play(&data);
    var frame: [2]f32 = undefined;
    mix(&sound, &frame);
    try std.testing.expectEqualSlices(f32, &.{ 1, -1 }, &frame);
    sound.stop(first);
    var tail: [4]f32 = undefined;
    mix(&sound, &tail);
    try std.testing.expectEqualSlices(f32, &.{ 0.25, -1, 0, 0 }, &tail);
    try std.testing.expectEqual(SoundSystem.State.free, sound.pool.slots[0].state.load(.acquire));
    try std.testing.expectEqual(SoundSystem.State.free, sound.pool.slots[1].state.load(.acquire));
    // A stop before the first render contributes nothing.
    const stopped = try sound.play(&data);
    sound.stop(stopped);
    mix(&sound, &tail);
    try std.testing.expectEqualSlices(f32, &.{ 0, 0, 0, 0 }, &tail);
    // Reused stopped/completed slots restart from the first frame; three voices saturate.
    for (0..3) |_| _ = try sound.play(&data);
    mix(&sound, &tail);
    try std.testing.expectEqualSlices(f32, &.{ 1, -1, 0.75, -1 }, &tail);
}
