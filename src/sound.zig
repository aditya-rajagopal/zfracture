//! Native, one-shot PCM playback. Initialize in place from executable-owned code
//! so callbacks survive game hot reload, and keep this address stable until deinit.
//! Call init/update/play/stop/deinit on the game thread. Buffers are borrowed, immutable
//! 44.1 kHz stereo signed 16-bit little-endian PCM; keep them alive until deinit.
//! Each play returns an independent handle. Stop is asynchronous, and expired or
//! repeatedly stopped handles are harmless. Play/stop and mixing do not allocate
//! engine memory; native resources are allocated during init and recovery in update.
const std = @import("std");
const builtin = @import("builtin");

const backend = switch (builtin.os.tag) {
    .windows => @import("windows/xaudio2.zig"),
    .macos => @import("macos/sound.zig"),
    else => @compileError("Unsupported audio platform"),
};

pool: Pool = .{},
native: backend.State = .{},

pub const InitError = backend.InitError;
pub const init = backend.init;
pub const deinit = backend.deinit;
/// Call once per frame from executable-owned code. Recover failed native voices;
/// may allocate native resources or wait for callbacks. Failed attempts retry later.
pub const update = backend.update;
/// Play a whole PCM buffer; reject invalid data or full capacity without interrupting playback.
pub const play = backend.play;
/// Request a stop for this playback only; the audio thread releases its slot.
pub const stop = backend.stop;

// Engine capacity, not a platform limit. Changing it requires an app restart.
pub const voice_capacity = 16;
pub const sample_rate_hz = 44100;
pub const channels = 2;
pub const bytes_per_frame = channels * @sizeOf(i16);
// XAudio2's maximum source buffer size; use the same contract on both platforms.
const max_buffer_bytes = 0x80000000;
const index_bits = std.math.log2_int_ceil(u64, voice_capacity);
const index_mask: u64 = (@as(u64, 1) << index_bits) - 1;
const max_generation = std.math.maxInt(u64) >> index_bits;

comptime {
    std.debug.assert(voice_capacity >= 2);
    std.debug.assert(index_bits < 64);
}

/// Identifies one playback in its originating SoundSystem's lifetime.
/// The representation is private; old handles never stop a reused slot.
pub const PlaybackHandle = enum(u64) { _ };
pub const PlayError = error{ InvalidData, NoFreeVoices, PlaybackFailed };

pub const State = enum(u8) { free, reserved, active, stop_requested, failed, retired };

pub const Slot = struct {
    state: std.atomic.Value(State) = .init(.free),
    // Only the game thread reads/writes generation.
    generation: u64 = 0,
    // Published by the game thread; immutable until completion.
    data: []const u8 = &.{},

    /// The callback must not access this slot after publishing completion.
    /// Preserve a concurrent stop request or a native failure during the transition.
    pub fn complete(self: *Slot) void {
        if (self.state.cmpxchgStrong(.active, .free, .release, .monotonic)) |state| {
            if (state == .stop_requested) {
                _ = self.state.cmpxchgStrong(.stop_requested, .free, .release, .monotonic);
            }
        }
    }
};

pub const Pool = struct {
    slots: [voice_capacity]Slot = @splat(.{}),

    pub const Reservation = struct { index: usize, handle: PlaybackHandle };

    /// Reserves but does not publish: finish preparing native context before activation.
    pub fn reserve(self: *Pool, data: []const u8) PlayError!Reservation {
        if (data.len == 0) return error.InvalidData;
        if (data.len % bytes_per_frame != 0) return error.InvalidData;
        if (data.len > max_buffer_bytes) return error.InvalidData;

        for (&self.slots, 0..) |*slot, index| {
            if (slot.state.load(.acquire) != .free) continue;
            std.debug.assert(slot.generation <= max_generation);
            if (slot.generation == max_generation) {
                slot.state.store(.retired, .monotonic);
                continue;
            }

            slot.generation += 1;
            slot.data = data;
            slot.state.store(.reserved, .monotonic);

            const generation_bits = slot.generation << index_bits;
            const slot_index: u64 = @intCast(index);
            const handle_bits = generation_bits | slot_index;
            return .{
                .index = index,
                .handle = @fromBackingInt(@intCast(handle_bits)),
            };
        }
        return error.NoFreeVoices;
    }

    pub fn requestStop(self: *Pool, handle: PlaybackHandle) ?usize {
        const bits = @backingInt(handle);
        const index: usize = @intCast(bits & index_mask);
        const generation = bits >> index_bits;
        if (index >= voice_capacity) return null;
        const slot = &self.slots[index];
        if (generation == 0) return null;
        if (generation != slot.generation) return null;

        if (slot.state.cmpxchgStrong(.active, .stop_requested, .acq_rel, .acquire) != null) {
            return null;
        }
        return index;
    }
};

test "pool exhaustion, completion, stop identity and generation retirement" {
    var system: @This() = .{};
    const pool = &system.pool;
    const data = [_]u8{ 0, 0, 0, 0 };
    try std.testing.expectError(error.InvalidData, pool.reserve(&.{}));
    try std.testing.expectError(error.InvalidData, pool.reserve(&.{0}));

    var handles: [voice_capacity]PlaybackHandle = undefined;
    for (&handles) |*handle| {
        const reservation = try pool.reserve(&data);
        handle.* = reservation.handle;
        pool.slots[reservation.index].state.store(.active, .release);
    }
    try std.testing.expectError(error.NoFreeVoices, pool.reserve(&data));

    try std.testing.expectEqual(@as(?usize, 0), pool.requestStop(handles[0]));
    try std.testing.expectEqual(null, pool.requestStop(handles[0]));
    try std.testing.expectError(error.NoFreeVoices, pool.reserve(&data));

    pool.slots[0].complete();
    _ = try pool.reserve(&data);
    pool.slots[0].state.store(.active, .release);
    try std.testing.expectEqual(null, pool.requestStop(handles[0]));
    try std.testing.expectEqual(State.active, pool.slots[0].state.load(.acquire));
    try std.testing.expectEqual(State.active, pool.slots[1].state.load(.acquire));

    pool.slots[0].complete();
    pool.slots[0].generation = max_generation;
    try std.testing.expectError(error.NoFreeVoices, pool.reserve(&data));
    try std.testing.expectEqual(State.retired, pool.slots[0].state.load(.acquire));

    pool.slots[1].complete();
    // Large generations must still reject handles from earlier playbacks.
    pool.slots[1].generation = std.math.maxInt(u32);
    const wide_handle = try pool.reserve(&data);
    pool.slots[1].state.store(.active, .release);
    try std.testing.expectEqual(null, pool.requestStop(handles[1]));
    try std.testing.expectEqual(@as(?usize, 1), pool.requestStop(wide_handle.handle));

    pool.slots[1].state.store(.failed, .release);
    pool.slots[1].complete();
    try std.testing.expectEqual(State.failed, pool.slots[1].state.load(.acquire));
    try std.testing.expectError(error.NoFreeVoices, pool.reserve(&data));
}
