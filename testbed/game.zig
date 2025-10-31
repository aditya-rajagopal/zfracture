const std = @import("std");
const fracture = @import("fracture");
const EngineState = fracture.EngineState;
const FrameBuffer = fracture.FrameBuffer;

pub const GameState = struct {
    offset_x: usize,
    offset_y: usize,
    impact_sound: fracture.wav.WavData,
    pop_sound: fracture.wav.WavData,
};

pub fn init(engine: *EngineState) *anyopaque {
    const game_state = engine.permanent_allocator.create(GameState) catch unreachable;
    game_state.offset_x = 0;
    game_state.offset_y = 0;
    const impact_sound = std.fs.cwd().readFileAlloc(
        "assets/sounds/impactMetal_medium_000-converted.wav",
        engine.transient_allocator,
        .unlimited,
    ) catch unreachable;
    game_state.impact_sound = fracture.wav.decode(engine.permanent_allocator, impact_sound) catch unreachable;
    const pop_sound = std.fs.cwd().readFileAlloc(
        "assets/sounds/pop.wav",
        engine.transient_allocator,
        .unlimited,
    ) catch unreachable;
    game_state.pop_sound = fracture.wav.decode(engine.permanent_allocator, pop_sound) catch unreachable;
    return @ptrCast(game_state);
}

pub fn deinit(_: *EngineState, _: *anyopaque) void {}

pub fn updateAndRender(
    engine: *EngineState,
    game_state: *anyopaque,
    /// TODO(adi): This is temporary until we have a proper renderer
    back_buffer: FrameBuffer,
) bool {
    const state: *GameState = @ptrCast(@alignCast(game_state));
    var running: bool = true;
    if (engine.input.isKeyDown(.escape)) {
        running = false;
    }

    if (engine.input.isKeyDown(.a)) {
        state.offset_x -%= 1;
    }
    if (engine.input.isKeyDown(.d)) {
        state.offset_x +%= 1;
    }
    if (engine.input.isKeyDown(.w)) {
        state.offset_y -%= 1;
    }
    if (engine.input.isKeyDown(.s)) {
        state.offset_y +%= 1;
    }

    if (engine.input.mouseButtonPressedThisFrame(.left)) {
        _ = engine.sound.playSound(state.pop_sound.data, .{});
    }

    if (engine.input.keyPressedThisFrame(.a)) {
        _ = engine.sound.playSound(@ptrCast(&a_note), .{});
    }
    if (engine.input.keyPressedThisFrame(.b)) {
        _ = engine.sound.playSound(@ptrCast(&b_note), .{});
    }
    if (engine.input.keyPressedThisFrame(.c)) {
        _ = engine.sound.playSound(@ptrCast(&c_note), .{});
    }
    if (engine.input.keyPressedThisFrame(.space)) {
        _ = engine.sound.playSound(state.impact_sound.data, .{});
    }

    for (0..back_buffer.height) |y| {
        for (0..back_buffer.width) |x| {
            const pixel_start: usize = (y * back_buffer.width + x) * FrameBuffer.bytes_per_pixel;
            back_buffer.data[pixel_start] = @truncate(x +% state.offset_x); // blue
            back_buffer.data[pixel_start + 1] = @truncate(y +% state.offset_y); // green
            back_buffer.data[pixel_start + 2] = 0x00; // red
            back_buffer.data[pixel_start + 3] = 0x00; // padding
        }
    }
    return running;
}

// DEBUG SOUDS
pub const a_note = blk: {
    @setEvalBranchQuota(500000);
    const sample_rate: u32 = 44100;
    const num_channels: u32 = 2;
    // const bits_per_sample: u32 = 16;
    const seconds_of_data: f32 = 0.2;
    const frequency: f32 = 440.0;
    const num_samples: u32 = sample_rate * seconds_of_data;
    var data = std.mem.zeroes([num_samples * num_channels]i16);
    var i: u32 = 0;
    while (i < num_samples) : (i += 1) {
        const sample: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_samples));
        const sample_value: i16 = @intFromFloat(std.math.sin(sample * std.math.pi * 2 * frequency) * std.math.maxInt(i16));
        var j: u32 = 0;
        while (j < num_channels) : (j += 1) {
            const offset: u32 = i * num_channels + j;
            data[offset] = sample_value;
        }
    }
    break :blk data;
};

pub const b_note = blk: {
    @setEvalBranchQuota(500000);
    const sample_rate: u32 = 44100;
    const num_channels: u32 = 2;
    // const bits_per_sample: u32 = 16;
    const seconds_of_data: f32 = 0.2;
    const frequency: f32 = 493.88;
    const num_samples: u32 = sample_rate * seconds_of_data;
    var data = std.mem.zeroes([num_samples * num_channels]i16);
    var i: u32 = 0;
    while (i < num_samples) : (i += 1) {
        const sample: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_samples));
        const sample_value: i16 = @intFromFloat(std.math.sin(sample * std.math.pi * 2 * frequency) * std.math.maxInt(i16));
        var j: u32 = 0;
        while (j < num_channels) : (j += 1) {
            const offset: u32 = i * num_channels + j;
            data[offset] = sample_value;
        }
    }
    break :blk data;
};

pub const c_note = blk: {
    @setEvalBranchQuota(5000000);
    const sample_rate: u32 = 44100;
    const num_channels: u32 = 2;
    // const bits_per_sample: u32 = 16;
    const seconds_of_data: f32 = 3;
    const frequency: f32 = 523.251;
    const num_samples: u32 = sample_rate * seconds_of_data;
    var data = std.mem.zeroes([num_samples * num_channels]i16);
    var i: u32 = 0;
    while (i < num_samples) : (i += 1) {
        const sample: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_samples));
        const sample_value: i16 = @intFromFloat(std.math.sin(sample * std.math.pi * 2 * frequency) * std.math.maxInt(i16));
        var j: u32 = 0;
        while (j < num_channels) : (j += 1) {
            const offset: u32 = i * num_channels + j;
            data[offset] = sample_value;
        }
    }
    break :blk data;
};
