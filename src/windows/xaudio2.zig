const std = @import("std");
const SoundSystem = @import("../sound.zig");
const win = std.os.windows;
const Guid = win.GUID;
const win32 = @import("win32.zig");
const IUnknown = win32.IUnknown;
const HRESULT = win32.HRESULT;
const BOOL = win.BOOL;
const HINSTANCE = win.HINSTANCE;

pub const PlayError = SoundSystem.PlayError;

pub const State = struct {
    dll: ?HINSTANCE = null,
    x_audio2: ?*IXAudio2 = null,
    mastering_voice: ?*IXAudio2MasteringVoice = null,
    com_initialized: bool = false,
    voices: [SoundSystem.voice_capacity]XAudioVoice = @splat(.{}),
    callback: VoiceCallback = .{},
};

pub const XAudioVoice = struct {
    source: ?*IXAudio2SourceVoice = null,
    slot: *SoundSystem.Slot = undefined,
};

pub const InitError = error{
    FailedToInitializeCOM,
    FailedToLoadXAudio2DLL,
    FailedToCreateXAudio2,
    FailedToCreateMasteringVoice,
    FailedToCreateVoice,
};

const PFNXAudio2Create = *const fn (
    ppXaudio2: *?*IXAudio2,
    flags: FLAGS,
    XAudio2Processor: win.UINT,
) callconv(.winapi) HRESULT;

// TODO(sound): Do we need any other type of callbacks for different kinds of voices?
const VoiceCallback = extern struct {
    vtable: *const IXAudio2VoiceCallback.VTable = &default,

    pub const default = IXAudio2VoiceCallback.VTable{
        .OnStreamEnd = _onStreamEnd,
        .OnBufferStart = _onBufferStart,
        .OnVoiceProcessingPassStart = _onVoiceProcessingPassStart,
        .OnVoiceProcessingPassEnd = _onVoiceProcessingPassEnd,
        .OnBufferEnd = _onBufferEnd,
        .OnLoopEnd = _onLoopEnd,
        .OnVoiceError = _onVoiceError,
    };

    fn _onBufferEnd(_: *IXAudio2VoiceCallback, context: ?*anyopaque) callconv(.winapi) void {
        const voice: *XAudioVoice = @ptrCast(@alignCast(context));
        // A source with no queued buffers is silent. Don't issue a delayed native
        // Stop here that could interfere with a subsequent playback.
        voice.slot.complete();
    }

    fn _onBufferStart(_: *IXAudio2VoiceCallback, _: ?*anyopaque) callconv(.winapi) void {}
    fn _onStreamEnd(_: *IXAudio2VoiceCallback) callconv(.winapi) void {}
    fn _onVoiceProcessingPassStart(_: *IXAudio2VoiceCallback, _: u32) callconv(.winapi) void {}
    fn _onVoiceProcessingPassEnd(_: *IXAudio2VoiceCallback) callconv(.winapi) void {}
    fn _onLoopEnd(_: *IXAudio2VoiceCallback, _: ?*anyopaque) callconv(.winapi) void {}
    fn _onVoiceError(
        _: *IXAudio2VoiceCallback,
        context: ?*anyopaque,
        _: HRESULT,
    ) callconv(.winapi) void {
        if (context) |ptr| {
            const voice: *XAudioVoice = @ptrCast(@alignCast(ptr));
            // The game thread will destroy the failed native voice. Never block
            // or log from the callback, or make this slot available for reuse.
            voice.slot.state.store(.failed, .release);
        }
    }
};

/// Initialize in place from executable-owned code; callbacks must survive hot reload.
/// Preallocate native voices here; fracture does not allocate during play/stop.
pub fn init(audio_engine: *SoundSystem) InitError!void {
    audio_engine.* = .{};

    const com_result = win32.CoInitializeEx(
        null,
        win32.COINIT_MULTITHREADED | win32.COINIT_SPEED_OVER_MEMORY,
    );
    // S_FALSE is also success and still requires a matching CoUninitialize.
    if (com_result < 0) return error.FailedToInitializeCOM;
    audio_engine.native.com_initialized = true;
    errdefer audio_engine.deinit();

    audio_engine.native.dll = win32.LoadLibraryA("xaudio2_9.dll") orelse
        return error.FailedToLoadXAudio2DLL;
    const create_address = win32.GetProcAddress(
        audio_engine.native.dll.?,
        "XAudio2Create",
    ) orelse return error.FailedToLoadXAudio2DLL;
    const xAudio2Create: PFNXAudio2Create = @ptrCast(create_address);

    const create_result = xAudio2Create(
        &audio_engine.native.x_audio2,
        FLAGS{},
        XAUDIO2_ANY_PROCESSOR,
    );
    if (create_result < 0 or audio_engine.native.x_audio2 == null) {
        return error.FailedToCreateXAudio2;
    }

    const mastering_result = audio_engine.native.x_audio2.?.CreateMasteringVoice(
        &audio_engine.native.mastering_voice,
        SoundSystem.channels,
        SoundSystem.sample_rate_hz,
        0,
        null,
        null,
        AUDIO_STREAM_CATEGORY.GameEffects,
    );
    if (mastering_result < 0) return error.FailedToCreateMasteringVoice;
    if (audio_engine.native.mastering_voice == null) return error.FailedToCreateMasteringVoice;

    for (&audio_engine.native.voices, &audio_engine.pool.slots) |*voice, *slot| {
        voice.slot = slot;
        try createVoice(audio_engine, voice);
    }
}

fn createVoice(self: *SoundSystem, voice: *XAudioVoice) error{FailedToCreateVoice}!void {
    std.debug.assert(voice.source == null);

    const wave_format: WAVEFORMATEX = .default;
    const result = self.native.x_audio2.?.CreateSourceVoice(
        &voice.source,
        &wave_format,
        0,
        XAUDIO2_DEFAULT_FREQ_RATIO,
        @ptrCast(@alignCast(&self.native.callback)),
        null,
        null,
    );
    if (result < 0 or voice.source == null) {
        if (voice.source) |source| source.IXAudio2Voice.DestroyVoice();
        voice.source = null;
        return error.FailedToCreateVoice;
    }
}

pub fn deinit(self: *SoundSystem) void {
    if (self.native.x_audio2) |engine| engine.StopEngine();
    for (&self.native.voices) |*voice| {
        if (voice.source) |source| source.IXAudio2Voice.DestroyVoice();
        voice.source = null;
    }

    if (self.native.mastering_voice) |voice| voice.IXAudio2Voice.DestroyVoice();
    if (self.native.x_audio2) |engine| engine.Relese();
    if (self.native.dll) |dll| _ = win32.FreeLibrary(dll);
    if (self.native.com_initialized) win32.CoUninitialize();

    self.* = .{};
}

/// Game thread, executable-owned code only. Retry each failed voice once per call.
pub fn update(self: *SoundSystem) void {
    for (&self.pool.slots, &self.native.voices, 0..) |*slot, *voice, index| {
        if (slot.state.load(.acquire) != .failed) continue;

        if (voice.source) |source| {
            // DestroyVoice waits for all callbacks and sample reads to finish.
            // Keep the slot failed throughout teardown and recreation.
            source.IXAudio2Voice.DestroyVoice();
            voice.source = null;
            std.log.warn("Audio voice {d} failed; attempting recovery", .{index});
        }

        createVoice(self, voice) catch continue;
        // Preserve the generation so the next play cannot revive an old handle.
        slot.state.store(.free, .release);
    }
}

/// Game thread only. Borrow immutable PCM until sound-system shutdown.
pub fn play(self: *SoundSystem, data: []const u8) PlayError!SoundSystem.PlaybackHandle {
    const reservation = try self.pool.reserve(data);
    const voice = &self.native.voices[reservation.index];
    const source = voice.source.?;

    // Completion may run as soon as playback starts, including before Start returns.
    voice.slot.state.store(.active, .release);

    const x_audio_buffer = XAUDIO2_BUFFER{
        .Flags = XAUDIO2_END_OF_STREAM,
        .AudioBytes = @intCast(data.len),
        .pAudioData = @ptrCast(data.ptr),
        .PlayBegin = 0,
        .PlayLength = 0,
        .LoopBegin = 0,
        .LoopLength = 0,
        .LoopCount = 0,
        .pContext = @ptrCast(voice),
    };
    if (source.SubmitSourceBuffer(&x_audio_buffer, null) < 0) {
        voice.slot.state.store(.failed, .release);
        return error.PlaybackFailed;
    }

    if (source.Start(0, XAUDIO2_COMMIT_NOW) < 0) {
        voice.slot.state.store(.failed, .release);
        return error.PlaybackFailed;
    }
    return reservation.handle;
}

/// Requests a stop. Only completion releases the slot; stale handles are ignored.
pub fn stop(self: *SoundSystem, handle: SoundSystem.PlaybackHandle) void {
    const index = self.pool.requestStop(handle) orelse return;
    const source = self.native.voices[index].source.?;
    if (source.Stop(0, XAUDIO2_COMMIT_NOW) < 0) {
        self.pool.slots[index].state.store(.failed, .release);
        return;
    }

    if (source.FlushSourceBuffers() < 0) {
        self.pool.slots[index].state.store(.failed, .release);
    }
}

const TestSourceVoice = struct {
    source: IXAudio2SourceVoice = .{ .vtable = &vtable },
    engine: IXAudio2 = .{ .vtable = &engine_vtable },
    callback: *VoiceCallback = undefined,
    context: ?*anyopaque = null,
    complete_on_start: bool = false,
    fail_start: bool = false,
    fail_stop: bool = false,
    fail_create: bool = false,
    create_count: usize = 0,
    stop_count: usize = 0,
    flush_count: usize = 0,
    destroy_count: usize = 0,

    const vtable: IXAudio2SourceVoice.VTable = blk: {
        var table: IXAudio2SourceVoice.VTable = undefined;
        table.SubmitSourceBuffer = submit;
        table.Start = start;
        table.Stop = TestSourceVoice.stop;
        table.FlushSourceBuffers = flush;
        table.base.DestroyVoice = destroy;
        break :blk table;
    };

    const engine_vtable: IXAudio2.VTable = blk: {
        var table: IXAudio2.VTable = undefined;
        table.CreateSourceVoice = create;
        break :blk table;
    };

    fn initAudio(self: *TestSourceVoice, audio: *SoundSystem) void {
        audio.* = .{};
        audio.native.x_audio2 = &self.engine;
        audio.native.callback = .{};
        self.callback = &audio.native.callback;

        // Keep the other slots occupied so premature reuse or a leaked slot is observable.
        for (&audio.pool.slots) |*slot| slot.state.store(.retired, .monotonic);
        audio.pool.slots[0].state.store(.free, .monotonic);
        audio.native.voices[0] = .{ .source = &self.source, .slot = &audio.pool.slots[0] };
    }

    fn create(
        engine: *const IXAudio2,
        source: ?*?*IXAudio2SourceVoice,
        _: ?*const WAVEFORMATEX,
        _: u32,
        _: f32,
        callback: ?*IXAudio2VoiceCallback,
        _: ?*const XAUDIO2_VOICE_SENDS,
        _: ?*const XAUDIO2_EFFECT_CHAIN,
    ) callconv(.winapi) HRESULT {
        const self: *TestSourceVoice = @fieldParentPtr("engine", @constCast(engine));
        self.create_count += 1;
        if (self.fail_create) return @bitCast(@as(u32, 0x80004005)); // E_FAIL
        std.debug.assert(self.context == null);
        self.callback = @ptrCast(@alignCast(callback.?));
        source.?.* = &self.source;
        return win32.S_OK;
    }

    fn complete(self: *TestSourceVoice) void {
        const context = self.context orelse return;
        self.context = null;
        self.callback.vtable.OnBufferEnd(@ptrCast(self.callback), context);
    }

    fn submit(
        source: *IXAudio2SourceVoice,
        buffer: ?*const XAUDIO2_BUFFER,
        _: ?*const XAUDIO2_BUFFER_WMA,
    ) callconv(.winapi) HRESULT {
        const self: *TestSourceVoice = @fieldParentPtr("source", source);
        std.debug.assert(self.context == null);
        self.context = buffer.?.pContext;
        return win32.S_OK;
    }

    fn start(source: *IXAudio2SourceVoice, _: u32, _: u32) callconv(.winapi) HRESULT {
        const self: *TestSourceVoice = @fieldParentPtr("source", source);
        if (self.fail_start) return @bitCast(@as(u32, 0x80004005)); // E_FAIL
        if (self.complete_on_start) self.complete();
        return win32.S_OK;
    }

    fn stop(source: *const IXAudio2SourceVoice, _: u32, _: u32) callconv(.winapi) HRESULT {
        const self: *TestSourceVoice = @fieldParentPtr("source", @constCast(source));
        self.stop_count += 1;
        if (self.fail_stop) return @bitCast(@as(u32, 0x80004005)); // E_FAIL
        return win32.S_OK;
    }

    fn flush(source: *const IXAudio2SourceVoice) callconv(.winapi) HRESULT {
        const self: *TestSourceVoice = @fieldParentPtr("source", @constCast(source));
        self.flush_count += 1;
        // Tests deliver the pending completion explicitly, after stop returns.
        return win32.S_OK;
    }

    fn destroy(base: *const IXAudio2Voice) callconv(.winapi) void {
        const source: *IXAudio2SourceVoice = @ptrCast(@constCast(base));
        const self: *TestSourceVoice = @fieldParentPtr("source", source);
        self.destroy_count += 1;
        // Exercise a final completion during teardown, before native callbacks cease.
        self.complete();
    }
};

test "completion_before_start_returns_and_failed_voice_recovery" {
    var audio: SoundSystem = undefined;
    var source: TestSourceVoice = .{ .complete_on_start = true };
    source.initAudio(&audio);
    var old_handle: SoundSystem.PlaybackHandle = undefined;
    for (0..SoundSystem.voice_capacity + 1) |_| {
        old_handle = try audio.play(&.{ 0, 0, 0, 0 });
        try std.testing.expectEqual(.free, audio.pool.slots[0].state.load(.acquire));
    }
    // Play only quarantines; update owns native destruction and recreation.
    source.complete_on_start = false;
    source.fail_start = true;
    try std.testing.expectError(error.PlaybackFailed, audio.play(&.{ 0, 0, 0, 0 }));
    try std.testing.expectEqual(@as(usize, 0), source.destroy_count);
    try std.testing.expectEqual(@as(usize, 0), source.create_count);
    try std.testing.expectEqual(.failed, audio.pool.slots[0].state.load(.acquire));
    try std.testing.expectError(error.NoFreeVoices, audio.play(&.{ 0, 0, 0, 0 }));
    const generation = audio.pool.slots[0].generation;
    source.fail_create = true;
    audio.update();
    try std.testing.expectEqual(@as(usize, 1), source.destroy_count);
    try std.testing.expectEqual(null, source.context);
    try std.testing.expectEqual(null, audio.native.voices[0].source);
    try std.testing.expectEqual(.failed, audio.pool.slots[0].state.load(.acquire));
    audio.update();
    try std.testing.expectEqual(@as(usize, 1), source.destroy_count);
    try std.testing.expectEqual(@as(usize, 2), source.create_count);
    try std.testing.expectError(error.NoFreeVoices, audio.play(&.{ 0, 0, 0, 0 }));
    source.fail_create = false;
    source.fail_start = false;
    audio.update();
    try std.testing.expectEqual(.free, audio.pool.slots[0].state.load(.acquire));
    try std.testing.expectEqual(generation, audio.pool.slots[0].generation);
    const recovered = try audio.play(&.{ 0, 0, 0, 0 });
    audio.stop(old_handle);
    try std.testing.expect(recovered != old_handle);
    try std.testing.expectEqual(@as(usize, 0), source.stop_count);
    // Errors reported asynchronously use the same recovery path.
    source.callback.vtable.OnVoiceError(
        @ptrCast(source.callback),
        source.context,
        @bitCast(@as(u32, 0x80004005)),
    );
    try std.testing.expectEqual(.failed, audio.pool.slots[0].state.load(.acquire));
    audio.update();
    try std.testing.expectEqual(@as(usize, 2), source.destroy_count);
    try std.testing.expectEqual(@as(usize, 4), source.create_count);
    _ = try audio.play(&.{ 0, 0, 0, 0 });
    audio.stop(recovered);
    try std.testing.expectEqual(.active, audio.pool.slots[0].state.load(.acquire));
    source.complete();
}

test "stopped_voice_waits_for_flush_completion_before_reuse" {
    var audio: SoundSystem = undefined;
    var source: TestSourceVoice = .{};
    source.initAudio(&audio);
    const data = [_]u8{ 0, 0, 0, 0 };
    const handle = try audio.play(&data);
    audio.stop(handle);
    audio.stop(handle);
    try std.testing.expectEqual(@as(usize, 1), source.stop_count);
    try std.testing.expectEqual(@as(usize, 1), source.flush_count);
    try std.testing.expectError(error.NoFreeVoices, audio.play(&data));
    source.complete();
    const replacement = try audio.play(&data);
    try std.testing.expect(replacement != handle);
    audio.stop(handle);
    try std.testing.expectEqual(@as(usize, 1), source.stop_count);
    try std.testing.expectEqual(.active, audio.pool.slots[0].state.load(.acquire));
    source.fail_stop = true;
    audio.stop(replacement);
    try std.testing.expectEqual(.failed, audio.pool.slots[0].state.load(.acquire));
    try std.testing.expectEqual(@as(usize, 0), source.destroy_count);
    try std.testing.expectEqual(@as(usize, 0), source.create_count);
    source.fail_stop = false;
    audio.update();
    try std.testing.expectEqual(@as(usize, 1), source.destroy_count);
    try std.testing.expectEqual(@as(usize, 1), source.create_count);
    _ = try audio.play(&data);
    audio.stop(replacement);
    try std.testing.expectEqual(.active, audio.pool.slots[0].state.load(.acquire));
    source.complete();
}

test "handles_stop_only_the_requested_instance" {
    var audio: SoundSystem = undefined;
    var first: TestSourceVoice = .{};
    first.initAudio(&audio);
    var second: TestSourceVoice = .{ .callback = &audio.native.callback };
    audio.pool.slots[1].state.store(.free, .monotonic);
    audio.native.voices[1] = .{ .source = &second.source, .slot = &audio.pool.slots[1] };
    const data = [_]u8{ 0, 0, 0, 0 };
    const first_handle = try audio.play(&data);
    const second_handle = try audio.play(&data);

    audio.stop(second_handle);
    audio.stop(second_handle);
    try std.testing.expectEqual(@as(usize, 0), first.stop_count);
    audio.stop(first_handle);
    try std.testing.expectEqual(@as(usize, 1), first.stop_count);
    try std.testing.expectEqual(@as(usize, 1), first.flush_count);
    try std.testing.expectEqual(@as(usize, 1), second.stop_count);
    try std.testing.expectEqual(@as(usize, 1), second.flush_count);
    try std.testing.expectError(error.NoFreeVoices, audio.play(&data));

    first.complete();
    _ = try audio.play(&data);
    try std.testing.expectError(error.NoFreeVoices, audio.play(&data));
    second.complete();
    _ = try audio.play(&data);
    audio.stop(first_handle);
    audio.stop(second_handle);
    try std.testing.expectEqual(@as(usize, 1), first.stop_count);
    try std.testing.expectEqual(@as(usize, 1), second.stop_count);
    first.complete();
    second.complete();
}

// -------------------------------------------------------------------------------------------------
// XAudio2 Win32 API
// -------------------------------------------------------------------------------------------------

// TODO(adi): Do we need XAPO?
// https://github.com/marlersoft/zigwin32/blob/main/win32/media/audio/xaudio2.zig

pub const WAVE_FORMAT_PCM = @as(u32, 1);

const WAVEFORMATEX = extern struct {
    wFormatTag: win.WORD,
    nChannels: win.WORD,
    nSamplesPerSec: win.DWORD,
    nAvgBytesPerSec: win.DWORD,
    nBlockAlign: win.WORD,
    wBitsPerSample: win.WORD,
    cbSize: win.WORD,

    pub const default: WAVEFORMATEX = .{
        .wFormatTag = WAVE_FORMAT_PCM,
        .nChannels = SoundSystem.channels,
        .nSamplesPerSec = SoundSystem.sample_rate_hz,
        .nAvgBytesPerSec = SoundSystem.bytes_per_frame * SoundSystem.sample_rate_hz,
        .nBlockAlign = SoundSystem.bytes_per_frame,
        .wBitsPerSample = 16,
        .cbSize = 0,
    };
};

pub const FLAGS = packed struct(c_uint) {
    DEBUG_ENGINE: bool = false,
    VOICE_NOPITCH: bool = false,
    VOICE_NOSRC: bool = false,
    VOICE_USEFILTER: bool = false,
    __unused4: bool = false,
    PLAY_TAILS: bool = false,
    END_OF_STREAM: bool = false,
    SEND_USEFILTER: bool = false,
    VOICE_NOSAMPLESPLAYED: bool = false,
    __unused9: bool = false,
    __unused10: bool = false,
    __unused11: bool = false,
    __unused12: bool = false,
    STOP_ENGINE_WHEN_IDLE: bool = false,
    __unused14: bool = false,
    @"1024_QUANTUM": bool = false,
    NO_VIRTUAL_AUDIO_CLIENT: bool = false,
    __unused: u15 = 0,
};

pub const AUDIO_STREAM_CATEGORY = enum(i32) {
    Other = 0,
    ForegroundOnlyMedia = 1,
    Communications = 3,
    Alerts = 4,
    SoundEffects = 5,
    GameEffects = 6,
    GameMedia = 7,
    GameChat = 8,
    Speech = 9,
    Movie = 10,
    Media = 11,
    FarFieldSpeech = 12,
    UniformSpeech = 13,
    VoiceTyping = 14,
};
pub const AudioCategory_Other = AUDIO_STREAM_CATEGORY.Other;
pub const AudioCategory_ForegroundOnlyMedia = AUDIO_STREAM_CATEGORY.ForegroundOnlyMedia;
pub const AudioCategory_Communications = AUDIO_STREAM_CATEGORY.Communications;
pub const AudioCategory_Alerts = AUDIO_STREAM_CATEGORY.Alerts;
pub const AudioCategory_SoundEffects = AUDIO_STREAM_CATEGORY.SoundEffects;
pub const AudioCategory_GameEffects = AUDIO_STREAM_CATEGORY.GameEffects;
pub const AudioCategory_GameMedia = AUDIO_STREAM_CATEGORY.GameMedia;
pub const AudioCategory_GameChat = AUDIO_STREAM_CATEGORY.GameChat;
pub const AudioCategory_Speech = AUDIO_STREAM_CATEGORY.Speech;
pub const AudioCategory_Movie = AUDIO_STREAM_CATEGORY.Movie;
pub const AudioCategory_Media = AUDIO_STREAM_CATEGORY.Media;
pub const AudioCategory_FarFieldSpeech = AUDIO_STREAM_CATEGORY.FarFieldSpeech;
pub const AudioCategory_UniformSpeech = AUDIO_STREAM_CATEGORY.UniformSpeech;
pub const AudioCategory_VoiceTyping = AUDIO_STREAM_CATEGORY.VoiceTyping;

const XAUDIO2_COMMIT_NOW = 0;

pub const XAUDIO2_VOICE_DETAILS = extern struct {
    CreationFlags: u32 align(1),
    ActiveFlags: u32 align(1),
    InputChannels: u32 align(1),
    InputSampleRate: u32 align(1),
};

pub const XAUDIO2_SEND_DESCRIPTOR = extern struct {
    Flags: u32 align(1),
    pOutputVoice: ?*IXAudio2Voice align(1),
};

pub const XAUDIO2_VOICE_SENDS = extern struct {
    SendCount: u32 align(1),
    pSends: ?*XAUDIO2_SEND_DESCRIPTOR align(1),
};

pub const XAUDIO2_EFFECT_DESCRIPTOR = extern struct {
    pEffect: ?*IUnknown align(1),
    InitialState: BOOL align(1),
    OutputChannels: u32 align(1),
};

pub const XAUDIO2_EFFECT_CHAIN = extern struct {
    EffectCount: u32 align(1),
    pEffectDescriptors: ?*XAUDIO2_EFFECT_DESCRIPTOR align(1),
};

pub const XAUDIO2_FILTER_TYPE = enum(i32) {
    LowPassFilter = 0,
    BandPassFilter = 1,
    HighPassFilter = 2,
    NotchFilter = 3,
    LowPassOnePoleFilter = 4,
    HighPassOnePoleFilter = 5,
};
pub const LowPassFilter = XAUDIO2_FILTER_TYPE.LowPassFilter;
pub const BandPassFilter = XAUDIO2_FILTER_TYPE.BandPassFilter;
pub const HighPassFilter = XAUDIO2_FILTER_TYPE.HighPassFilter;
pub const NotchFilter = XAUDIO2_FILTER_TYPE.NotchFilter;
pub const LowPassOnePoleFilter = XAUDIO2_FILTER_TYPE.LowPassOnePoleFilter;
pub const HighPassOnePoleFilter = XAUDIO2_FILTER_TYPE.HighPassOnePoleFilter;

pub const XAUDIO2_FILTER_PARAMETERS = extern struct {
    Type: XAUDIO2_FILTER_TYPE align(1),
    Frequency: f32 align(1),
    OneOverQ: f32 align(1),
};

const XAUDIO2_MAX_LOOP_COUNT = 254; // Maximum non-infinite XAUDIO2_BUFFER.LoopCount
pub const XAUDIO2_BUFFER = extern struct {
    Flags: u32 align(1),
    AudioBytes: u32 align(1),
    pAudioData: ?*const u8 align(1),
    PlayBegin: u32 align(1),
    PlayLength: u32 align(1),
    LoopBegin: u32 align(1),
    LoopLength: u32 align(1),
    LoopCount: u32 align(1),
    pContext: ?*anyopaque align(1),
};

pub const XAUDIO2_BUFFER_WMA = extern struct {
    pDecodedPacketCumulativeBytes: ?*const u32 align(1),
    PacketCount: u32 align(1),
};

pub const XAUDIO2_VOICE_STATE = extern struct {
    pCurrentBufferContext: ?*anyopaque align(1),
    BuffersQueued: u32 align(1),
    SamplesPlayed: u64 align(1),
};

pub const XAUDIO2_PERFORMANCE_DATA = extern struct {
    AudioCyclesSinceLastQuery: u64 align(1),
    TotalCyclesSinceLastQuery: u64 align(1),
    MinimumCyclesPerQuantum: u32 align(1),
    MaximumCyclesPerQuantum: u32 align(1),
    MemoryUsageInBytes: u32 align(1),
    CurrentLatencyInSamples: u32 align(1),
    GlitchesSinceEngineStarted: u32 align(1),
    ActiveSourceVoiceCount: u32 align(1),
    TotalSourceVoiceCount: u32 align(1),
    ActiveSubmixVoiceCount: u32 align(1),
    ActiveResamplerCount: u32 align(1),
    ActiveMatrixMixCount: u32 align(1),
    ActiveXmaSourceVoices: u32 align(1),
    ActiveXmaStreams: u32 align(1),
};

pub const XAUDIO2_DEBUG_CONFIGURATION = extern struct {
    TraceMask: u32 align(1),
    BreakMask: u32 align(1),
    LogThreadID: BOOL align(1),
    LogFileline: BOOL align(1),
    LogFunctionName: BOOL align(1),
    LogTiming: BOOL align(1),
};

const XAUDIO2_ANY_PROCESSOR = 0xffffffff;
const XAUDIO2_USE_DEFAULT_PROCESSOR = 0x00000000;
const XAUDIO2_DEFAULT_FREQ_RATIO = 2.0;

const XAUDIO2_END_OF_STREAM = 0x0040; // Used in XAUDIO2_BUFFER.Flags

pub const IID_IXAudio2_Value = Guid.parse("2b02e3cf-2e0b-4ec3-be45-1b2a3fe7210d");
pub const IXAudio2 = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        RegisterForCallbacks: *const fn (
            self: *const IXAudio2,
            pCallback: ?*IXAudio2EngineCallback,
        ) callconv(.winapi) HRESULT,
        UnregisterForCallbacks: *const fn (
            self: *const IXAudio2,
            pCallback: ?*IXAudio2EngineCallback,
        ) callconv(.winapi) void,
        CreateSourceVoice: *const fn (
            self: *const IXAudio2,
            ppSourceVoice: ?*?*IXAudio2SourceVoice,
            pSourceFormat: ?*const WAVEFORMATEX,
            Flags: u32,
            MaxFrequencyRatio: f32,
            pCallback: ?*IXAudio2VoiceCallback,
            pSendList: ?*const XAUDIO2_VOICE_SENDS,
            pEffectChain: ?*const XAUDIO2_EFFECT_CHAIN,
        ) callconv(.winapi) HRESULT,
        CreateSubmixVoice: *const fn (
            self: *const IXAudio2,
            ppSubmixVoice: ?*?*IXAudio2SubmixVoice,
            InputChannels: u32,
            InputSampleRate: u32,
            Flags: u32,
            ProcessingStage: u32,
            pSendList: ?*const XAUDIO2_VOICE_SENDS,
            pEffectChain: ?*const XAUDIO2_EFFECT_CHAIN,
        ) callconv(.winapi) HRESULT,
        CreateMasteringVoice: *const fn (
            self: *const IXAudio2,
            ppMasteringVoice: ?*?*IXAudio2MasteringVoice,
            InputChannels: u32,
            InputSampleRate: u32,
            Flags: u32,
            szDeviceId: ?[*:0]const u16,
            pEffectChain: ?*const XAUDIO2_EFFECT_CHAIN,
            StreamCategory: AUDIO_STREAM_CATEGORY,
        ) callconv(.winapi) HRESULT,
        StartEngine: *const fn (
            self: *const IXAudio2,
        ) callconv(.winapi) HRESULT,
        StopEngine: *const fn (
            self: *const IXAudio2,
        ) callconv(.winapi) void,
        CommitChanges: *const fn (
            self: *const IXAudio2,
            OperationSet: u32,
        ) callconv(.winapi) HRESULT,
        GetPerformanceData: *const fn (
            self: *const IXAudio2,
            pPerfData: ?*XAUDIO2_PERFORMANCE_DATA,
        ) callconv(.winapi) void,
        SetDebugConfiguration: *const fn (
            self: *const IXAudio2,
            pDebugConfiguration: ?*const XAUDIO2_DEBUG_CONFIGURATION,
            pReserved: ?*anyopaque,
        ) callconv(.winapi) void,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
    pub inline fn RegisterForCallbacks(
        self: *const IXAudio2,
        pCallback: ?*IXAudio2EngineCallback,
    ) HRESULT {
        return self.vtable.RegisterForCallbacks(self, pCallback);
    }
    pub inline fn UnregisterForCallbacks(
        self: *const IXAudio2,
        pCallback: ?*IXAudio2EngineCallback,
    ) void {
        return self.vtable.UnregisterForCallbacks(self, pCallback);
    }
    pub inline fn CreateSourceVoice(
        self: *const IXAudio2,
        ppSourceVoice: ?*?*IXAudio2SourceVoice,
        pSourceFormat: ?*const WAVEFORMATEX,
        Flags: u32,
        MaxFrequencyRatio: f32,
        pCallback: ?*IXAudio2VoiceCallback,
        pSendList: ?*const XAUDIO2_VOICE_SENDS,
        pEffectChain: ?*const XAUDIO2_EFFECT_CHAIN,
    ) HRESULT {
        return self.vtable.CreateSourceVoice(
            self,
            ppSourceVoice,
            pSourceFormat,
            Flags,
            MaxFrequencyRatio,
            pCallback,
            pSendList,
            pEffectChain,
        );
    }
    pub inline fn CreateSubmixVoice(
        self: *const IXAudio2,
        ppSubmixVoice: ?*?*IXAudio2SubmixVoice,
        InputChannels: u32,
        InputSampleRate: u32,
        Flags: u32,
        ProcessingStage: u32,
        pSendList: ?*const XAUDIO2_VOICE_SENDS,
        pEffectChain: ?*const XAUDIO2_EFFECT_CHAIN,
    ) HRESULT {
        return self.vtable.CreateSubmixVoice(
            self,
            ppSubmixVoice,
            InputChannels,
            InputSampleRate,
            Flags,
            ProcessingStage,
            pSendList,
            pEffectChain,
        );
    }
    pub inline fn CreateMasteringVoice(
        self: *const IXAudio2,
        ppMasteringVoice: ?*?*IXAudio2MasteringVoice,
        InputChannels: u32,
        InputSampleRate: u32,
        Flags: u32,
        szDeviceId: ?[*:0]const u16,
        pEffectChain: ?*const XAUDIO2_EFFECT_CHAIN,
        StreamCategory: AUDIO_STREAM_CATEGORY,
    ) HRESULT {
        return self.vtable.CreateMasteringVoice(
            self,
            ppMasteringVoice,
            InputChannels,
            InputSampleRate,
            Flags,
            szDeviceId,
            pEffectChain,
            StreamCategory,
        );
    }
    pub inline fn StartEngine(self: *const IXAudio2) HRESULT {
        return self.vtable.StartEngine(self);
    }
    pub inline fn StopEngine(self: *const IXAudio2) void {
        return self.vtable.StopEngine(self);
    }
    pub inline fn CommitChanges(self: *const IXAudio2, OperationSet: u32) HRESULT {
        return self.vtable.CommitChanges(self, OperationSet);
    }
    pub inline fn GetPerformanceData(
        self: *const IXAudio2,
        pPerfData: ?*XAUDIO2_PERFORMANCE_DATA,
    ) void {
        return self.vtable.GetPerformanceData(self, pPerfData);
    }
    pub inline fn SetDebugConfiguration(
        self: *const IXAudio2,
        pDebugConfiguration: ?*const XAUDIO2_DEBUG_CONFIGURATION,
        pReserved: ?*anyopaque,
    ) void {
        return self.vtable.SetDebugConfiguration(self, pDebugConfiguration, pReserved);
    }
    pub inline fn Relese(self: *const IXAudio2) void {
        _ = self.vtable.base.Release(&self.IUnknown);
    }
};

pub const IXAudio2EngineCallback = extern union {
    pub const VTable = extern struct {
        OnProcessingPassStart: *const fn (
            self: *const IXAudio2EngineCallback,
        ) callconv(.winapi) void,
        OnProcessingPassEnd: *const fn (
            self: *const IXAudio2EngineCallback,
        ) callconv(.winapi) void,
        OnCriticalError: *const fn (
            self: *const IXAudio2EngineCallback,
            Error: HRESULT,
        ) callconv(.winapi) void,
    };
    vtable: *const VTable,
    pub inline fn OnProcessingPassStart(self: *const IXAudio2EngineCallback) void {
        return self.vtable.OnProcessingPassStart(self);
    }
    pub inline fn OnProcessingPassEnd(self: *const IXAudio2EngineCallback) void {
        return self.vtable.OnProcessingPassEnd(self);
    }
    pub inline fn OnCriticalError(self: *const IXAudio2EngineCallback, err: HRESULT) void {
        return self.vtable.OnCriticalError(self, err);
    }
};

pub const IXAudio2Voice = extern union {
    pub const VTable = extern struct {
        GetVoiceDetails: *const fn (
            self: *const IXAudio2Voice,
            pVoiceDetails: ?*XAUDIO2_VOICE_DETAILS,
        ) callconv(.winapi) void,
        SetOutputVoices: *const fn (
            self: *const IXAudio2Voice,
            pSendList: ?*const XAUDIO2_VOICE_SENDS,
        ) callconv(.winapi) HRESULT,
        SetEffectChain: *const fn (
            self: *const IXAudio2Voice,
            pEffectChain: ?*const XAUDIO2_EFFECT_CHAIN,
        ) callconv(.winapi) HRESULT,
        EnableEffect: *const fn (
            self: *const IXAudio2Voice,
            EffectIndex: u32,
            OperationSet: u32,
        ) callconv(.winapi) HRESULT,
        DisableEffect: *const fn (
            self: *const IXAudio2Voice,
            EffectIndex: u32,
            OperationSet: u32,
        ) callconv(.winapi) HRESULT,
        GetEffectState: *const fn (
            self: *const IXAudio2Voice,
            EffectIndex: u32,
            pEnabled: ?*BOOL,
        ) callconv(.winapi) void,
        SetEffectParameters: *const fn (
            self: *const IXAudio2Voice,
            EffectIndex: u32,
            // TODO: what to do with BytesParamIndex 2?
            pParameters: ?*const anyopaque,
            ParametersByteSize: u32,
            OperationSet: u32,
        ) callconv(.winapi) HRESULT,
        GetEffectParameters: *const fn (
            self: *const IXAudio2Voice,
            EffectIndex: u32,
            // TODO: what to do with BytesParamIndex 2?
            pParameters: ?*anyopaque,
            ParametersByteSize: u32,
        ) callconv(.winapi) HRESULT,
        SetFilterParameters: *const fn (
            self: *const IXAudio2Voice,
            pParameters: ?*const XAUDIO2_FILTER_PARAMETERS,
            OperationSet: u32,
        ) callconv(.winapi) HRESULT,
        GetFilterParameters: *const fn (
            self: *const IXAudio2Voice,
            pParameters: ?*XAUDIO2_FILTER_PARAMETERS,
        ) callconv(.winapi) void,
        SetOutputFilterParameters: *const fn (
            self: *const IXAudio2Voice,
            pDestinationVoice: ?*IXAudio2Voice,
            pParameters: ?*const XAUDIO2_FILTER_PARAMETERS,
            OperationSet: u32,
        ) callconv(.winapi) HRESULT,
        GetOutputFilterParameters: *const fn (
            self: *const IXAudio2Voice,
            pDestinationVoice: ?*IXAudio2Voice,
            pParameters: ?*XAUDIO2_FILTER_PARAMETERS,
        ) callconv(.winapi) void,
        SetVolume: *const fn (
            self: *IXAudio2Voice,
            Volume: f32,
            OperationSet: u32,
        ) callconv(.winapi) HRESULT,
        GetVolume: *const fn (
            self: *const IXAudio2Voice,
            pVolume: ?*f32,
        ) callconv(.winapi) void,
        SetChannelVolumes: *const fn (
            self: *const IXAudio2Voice,
            Channels: u32,
            pVolumes: [*]const f32,
            OperationSet: u32,
        ) callconv(.winapi) HRESULT,
        GetChannelVolumes: *const fn (
            self: *const IXAudio2Voice,
            Channels: u32,
            pVolumes: [*]f32,
        ) callconv(.winapi) void,
        SetOutputMatrix: *const fn (
            self: *const IXAudio2Voice,
            pDestinationVoice: ?*IXAudio2Voice,
            SourceChannels: u32,
            DestinationChannels: u32,
            pLevelMatrix: ?*const f32,
            OperationSet: u32,
        ) callconv(.winapi) HRESULT,
        GetOutputMatrix: *const fn (
            self: *const IXAudio2Voice,
            pDestinationVoice: ?*IXAudio2Voice,
            SourceChannels: u32,
            DestinationChannels: u32,
            pLevelMatrix: ?*f32,
        ) callconv(.winapi) void,
        DestroyVoice: *const fn (
            self: *const IXAudio2Voice,
        ) callconv(.winapi) void,
    };
    vtable: *const VTable,
    pub inline fn GetVoiceDetails(
        self: *const IXAudio2Voice,
        pVoiceDetails: ?*XAUDIO2_VOICE_DETAILS,
    ) void {
        return self.vtable.GetVoiceDetails(self, pVoiceDetails);
    }
    pub inline fn SetOutputVoices(
        self: *const IXAudio2Voice,
        pSendList: ?*const XAUDIO2_VOICE_SENDS,
    ) HRESULT {
        return self.vtable.SetOutputVoices(self, pSendList);
    }
    pub inline fn SetEffectChain(
        self: *const IXAudio2Voice,
        pEffectChain: ?*const XAUDIO2_EFFECT_CHAIN,
    ) HRESULT {
        return self.vtable.SetEffectChain(self, pEffectChain);
    }
    pub inline fn EnableEffect(
        self: *const IXAudio2Voice,
        EffectIndex: u32,
        OperationSet: u32,
    ) HRESULT {
        return self.vtable.EnableEffect(self, EffectIndex, OperationSet);
    }
    pub inline fn DisableEffect(
        self: *const IXAudio2Voice,
        EffectIndex: u32,
        OperationSet: u32,
    ) HRESULT {
        return self.vtable.DisableEffect(self, EffectIndex, OperationSet);
    }
    pub inline fn GetEffectState(
        self: *const IXAudio2Voice,
        EffectIndex: u32,
        pEnabled: ?*BOOL,
    ) void {
        return self.vtable.GetEffectState(self, EffectIndex, pEnabled);
    }
    pub inline fn SetEffectParameters(
        self: *const IXAudio2Voice,
        EffectIndex: u32,
        pParameters: ?*const anyopaque,
        ParametersByteSize: u32,
        OperationSet: u32,
    ) HRESULT {
        return self.vtable.SetEffectParameters(
            self,
            EffectIndex,
            pParameters,
            ParametersByteSize,
            OperationSet,
        );
    }
    pub inline fn GetEffectParameters(
        self: *const IXAudio2Voice,
        EffectIndex: u32,
        pParameters: ?*anyopaque,
        ParametersByteSize: u32,
    ) HRESULT {
        return self.vtable.GetEffectParameters(self, EffectIndex, pParameters, ParametersByteSize);
    }
    pub inline fn SetFilterParameters(
        self: *const IXAudio2Voice,
        pParameters: ?*const XAUDIO2_FILTER_PARAMETERS,
        OperationSet: u32,
    ) HRESULT {
        return self.vtable.SetFilterParameters(self, pParameters, OperationSet);
    }
    pub inline fn GetFilterParameters(
        self: *const IXAudio2Voice,
        pParameters: ?*XAUDIO2_FILTER_PARAMETERS,
    ) void {
        return self.vtable.GetFilterParameters(self, pParameters);
    }
    pub inline fn SetOutputFilterParameters(
        self: *const IXAudio2Voice,
        pDestinationVoice: ?*IXAudio2Voice,
        pParameters: ?*const XAUDIO2_FILTER_PARAMETERS,
        OperationSet: u32,
    ) HRESULT {
        return self.vtable.SetOutputFilterParameters(
            self,
            pDestinationVoice,
            pParameters,
            OperationSet,
        );
    }
    pub inline fn GetOutputFilterParameters(
        self: *const IXAudio2Voice,
        pDestinationVoice: ?*IXAudio2Voice,
        pParameters: ?*XAUDIO2_FILTER_PARAMETERS,
    ) void {
        return self.vtable.GetOutputFilterParameters(self, pDestinationVoice, pParameters);
    }
    pub inline fn SetVolume(self: *IXAudio2Voice, Volume: f32, OperationSet: u32) HRESULT {
        return self.vtable.SetVolume(self, Volume, OperationSet);
    }
    pub inline fn GetVolume(self: *const IXAudio2Voice, pVolume: ?*f32) void {
        return self.vtable.GetVolume(self, pVolume);
    }
    pub inline fn SetChannelVolumes(
        self: *const IXAudio2Voice,
        Channels: u32,
        pVolumes: [*]const f32,
        OperationSet: u32,
    ) HRESULT {
        return self.vtable.SetChannelVolumes(self, Channels, pVolumes, OperationSet);
    }
    pub inline fn GetChannelVolumes(
        self: *const IXAudio2Voice,
        Channels: u32,
        pVolumes: [*]f32,
    ) void {
        return self.vtable.GetChannelVolumes(self, Channels, pVolumes);
    }
    pub inline fn SetOutputMatrix(
        self: *const IXAudio2Voice,
        pDestinationVoice: ?*IXAudio2Voice,
        SourceChannels: u32,
        DestinationChannels: u32,
        pLevelMatrix: ?*const f32,
        OperationSet: u32,
    ) HRESULT {
        return self.vtable.SetOutputMatrix(
            self,
            pDestinationVoice,
            SourceChannels,
            DestinationChannels,
            pLevelMatrix,
            OperationSet,
        );
    }
    pub inline fn GetOutputMatrix(
        self: *const IXAudio2Voice,
        pDestinationVoice: ?*IXAudio2Voice,
        SourceChannels: u32,
        DestinationChannels: u32,
        pLevelMatrix: ?*f32,
    ) void {
        return self.vtable.GetOutputMatrix(
            self,
            pDestinationVoice,
            SourceChannels,
            DestinationChannels,
            pLevelMatrix,
        );
    }
    pub inline fn DestroyVoice(self: *const IXAudio2Voice) void {
        return self.vtable.DestroyVoice(self);
    }
};

pub const IXAudio2SourceVoice = extern union {
    pub const VTable = extern struct {
        base: IXAudio2Voice.VTable,
        Start: *const fn (
            self: *IXAudio2SourceVoice,
            Flags: u32,
            OperationSet: u32,
        ) callconv(.winapi) HRESULT,
        Stop: *const fn (
            self: *const IXAudio2SourceVoice,
            Flags: u32,
            OperationSet: u32,
        ) callconv(.winapi) HRESULT,
        SubmitSourceBuffer: *const fn (
            self: *IXAudio2SourceVoice,
            pBuffer: ?*const XAUDIO2_BUFFER,
            pBufferWMA: ?*const XAUDIO2_BUFFER_WMA,
        ) callconv(.winapi) HRESULT,
        FlushSourceBuffers: *const fn (
            self: *const IXAudio2SourceVoice,
        ) callconv(.winapi) HRESULT,
        Discontinuity: *const fn (
            self: *const IXAudio2SourceVoice,
        ) callconv(.winapi) HRESULT,
        ExitLoop: *const fn (
            self: *const IXAudio2SourceVoice,
            OperationSet: u32,
        ) callconv(.winapi) HRESULT,
        GetState: *const fn (
            self: *const IXAudio2SourceVoice,
            pVoiceState: ?*XAUDIO2_VOICE_STATE,
            Flags: u32,
        ) callconv(.winapi) void,
        SetFrequencyRatio: *const fn (
            self: *const IXAudio2SourceVoice,
            Ratio: f32,
            OperationSet: u32,
        ) callconv(.winapi) HRESULT,
        GetFrequencyRatio: *const fn (
            self: *const IXAudio2SourceVoice,
            pRatio: ?*f32,
        ) callconv(.winapi) void,
        SetSourceSampleRate: *const fn (
            self: *const IXAudio2SourceVoice,
            NewSourceSampleRate: u32,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IXAudio2Voice: IXAudio2Voice,
    pub inline fn Start(self: *IXAudio2SourceVoice, Flags: u32, OperationSet: u32) HRESULT {
        return self.vtable.Start(self, Flags, OperationSet);
    }
    pub inline fn Stop(self: *const IXAudio2SourceVoice, Flags: u32, OperationSet: u32) HRESULT {
        return self.vtable.Stop(self, Flags, OperationSet);
    }
    pub inline fn SubmitSourceBuffer(
        self: *IXAudio2SourceVoice,
        pBuffer: ?*const XAUDIO2_BUFFER,
        pBufferWMA: ?*const XAUDIO2_BUFFER_WMA,
    ) HRESULT {
        return self.vtable.SubmitSourceBuffer(self, pBuffer, pBufferWMA);
    }
    pub inline fn FlushSourceBuffers(self: *const IXAudio2SourceVoice) HRESULT {
        return self.vtable.FlushSourceBuffers(self);
    }
    pub inline fn Discontinuity(self: *const IXAudio2SourceVoice) HRESULT {
        return self.vtable.Discontinuity(self);
    }
    pub inline fn ExitLoop(self: *const IXAudio2SourceVoice, OperationSet: u32) HRESULT {
        return self.vtable.ExitLoop(self, OperationSet);
    }
    pub inline fn GetState(
        self: *const IXAudio2SourceVoice,
        pVoiceState: ?*XAUDIO2_VOICE_STATE,
        Flags: u32,
    ) void {
        return self.vtable.GetState(self, pVoiceState, Flags);
    }
    pub inline fn SetFrequencyRatio(
        self: *const IXAudio2SourceVoice,
        Ratio: f32,
        OperationSet: u32,
    ) HRESULT {
        return self.vtable.SetFrequencyRatio(self, Ratio, OperationSet);
    }
    pub inline fn GetFrequencyRatio(self: *const IXAudio2SourceVoice, pRatio: ?*f32) void {
        return self.vtable.GetFrequencyRatio(self, pRatio);
    }
    pub inline fn SetSourceSampleRate(
        self: *const IXAudio2SourceVoice,
        NewSourceSampleRate: u32,
    ) HRESULT {
        return self.vtable.SetSourceSampleRate(self, NewSourceSampleRate);
    }

    pub inline fn SetVolume(self: *IXAudio2SourceVoice, Volume: f32, OperationSet: u32) HRESULT {
        return self.IXAudio2Voice.SetVolume(Volume, OperationSet);
    }
};

pub const IXAudio2SubmixVoice = extern union {
    pub const VTable = extern struct {
        base: IXAudio2Voice.VTable,
    };
    vtable: *const VTable,
    IXAudio2Voice: IXAudio2Voice,
};

pub const IXAudio2MasteringVoice = extern union {
    pub const VTable = extern struct {
        base: IXAudio2Voice.VTable,
        GetChannelMask: *const fn (
            self: *const IXAudio2MasteringVoice,
            pChannelmask: ?*u32,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IXAudio2Voice: IXAudio2Voice,
    pub inline fn GetChannelMask(self: *const IXAudio2MasteringVoice, pChannelmask: ?*u32) HRESULT {
        return self.vtable.GetChannelMask(self, pChannelmask);
    }
};

pub const IXAudio2VoiceCallback = extern union {
    pub const VTable = extern struct {
        OnVoiceProcessingPassStart: *const fn (
            self: *IXAudio2VoiceCallback,
            BytesRequired: u32,
        ) callconv(.winapi) void = _onVoiceProcessingPassStart,
        OnVoiceProcessingPassEnd: *const fn (
            self: *IXAudio2VoiceCallback,
        ) callconv(.winapi) void = _onVoiceProcessingPassEnd,
        OnStreamEnd: *const fn (
            self: *IXAudio2VoiceCallback,
        ) callconv(.winapi) void = _onStreamEnd,
        OnBufferStart: *const fn (
            self: *IXAudio2VoiceCallback,
            pBufferContext: ?*anyopaque,
        ) callconv(.winapi) void = _onBufferStart,
        OnBufferEnd: *const fn (
            self: *IXAudio2VoiceCallback,
            pBufferContext: ?*anyopaque,
        ) callconv(.winapi) void = _onBufferEnd,
        OnLoopEnd: *const fn (
            self: *IXAudio2VoiceCallback,
            pBufferContext: ?*anyopaque,
        ) callconv(.winapi) void = _onLoopEnd,
        OnVoiceError: *const fn (
            self: *IXAudio2VoiceCallback,
            pBufferContext: ?*anyopaque,
            Error: HRESULT,
        ) callconv(.winapi) void = _onVoiceError,
    };
    vtable: *const VTable,
    pub inline fn OnVoiceProcessingPassStart(
        self: *IXAudio2VoiceCallback,
        BytesRequired: u32,
    ) void {
        return self.vtable.OnVoiceProcessingPassStart(self, BytesRequired);
    }
    pub inline fn OnVoiceProcessingPassEnd(self: *IXAudio2VoiceCallback) void {
        return self.vtable.OnVoiceProcessingPassEnd(self);
    }
    pub inline fn OnStreamEnd(self: *IXAudio2VoiceCallback) void {
        return self.vtable.OnStreamEnd(self);
    }
    pub inline fn OnBufferStart(self: *IXAudio2VoiceCallback, pBufferContext: ?*anyopaque) void {
        return self.vtable.OnBufferStart(self, pBufferContext);
    }
    pub inline fn OnBufferEnd(self: *IXAudio2VoiceCallback, pBufferContext: ?*anyopaque) void {
        return self.vtable.OnBufferEnd(self, pBufferContext);
    }
    pub inline fn OnLoopEnd(self: *IXAudio2VoiceCallback, pBufferContext: ?*anyopaque) void {
        return self.vtable.OnLoopEnd(self, pBufferContext);
    }
    pub inline fn OnVoiceError(
        self: *IXAudio2VoiceCallback,
        pBufferContext: ?*anyopaque,
        err: HRESULT,
    ) void {
        return self.vtable.OnVoiceError(self, pBufferContext, err);
    }

    fn _onVoiceProcessingPassStart(_: *IXAudio2VoiceCallback, _: u32) callconv(.winapi) void {}
    fn _onVoiceProcessingPassEnd(_: *IXAudio2VoiceCallback) callconv(.winapi) void {}
    fn _onStreamEnd(_: *IXAudio2VoiceCallback) callconv(.winapi) void {}
    fn _onBufferStart(_: *IXAudio2VoiceCallback, _: ?*anyopaque) callconv(.winapi) void {}
    fn _onBufferEnd(_: *IXAudio2VoiceCallback, _: ?*anyopaque) callconv(.winapi) void {}
    fn _onLoopEnd(_: *IXAudio2VoiceCallback, _: ?*anyopaque) callconv(.winapi) void {}
    fn _onVoiceError(
        _: *IXAudio2VoiceCallback,
        _: ?*anyopaque,
        _: HRESULT,
    ) callconv(.winapi) void {}
};
