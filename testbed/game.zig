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

    if (engine.input.keyPressedThisFrame(.space)) {
        _ = engine.sound.playSound(state.impact_sound.data, .{});
    }

    // Clear the back buffer
    const total_pixels: usize = @as(u64, @intCast(engine.back_buffer.width)) * @as(u64, @intCast(engine.back_buffer.height)) * FrameBuffer.bytes_per_pixel;
    for (0..total_pixels) |i| {
        engine.back_buffer.data[i] = 0x00;
    }

    // Draw a rectangle
    // TODO: We should draw rectangle with floating point coordinates and then map that to pixles
    const x: usize = engine.back_buffer.width / 4;
    const y: usize = engine.back_buffer.height / 4;
    const width: usize = engine.back_buffer.width / 2;
    const height: usize = engine.back_buffer.height / 2;
    // TODO: use floating point colours
    const colour: u32 = 0x00FF0000;
    for (0..height) |j| {
        for (0..width) |i| {
            const pixel_start: usize = ((y + j) * engine.back_buffer.width + x + i) * FrameBuffer.bytes_per_pixel;
            engine.back_buffer.data[pixel_start] = 0xFF & colour; // blue
            engine.back_buffer.data[pixel_start + 1] = 0xFF & (colour >> 8); // green
            engine.back_buffer.data[pixel_start + 2] = 0xFF & (colour >> 16); // red
            engine.back_buffer.data[pixel_start + 3] = 0x00; // padding
        }
    }

    return running;
}

// DEBUG SOUDS
// pub const a_note = blk: {
//     @setEvalBranchQuota(500000);
//     const sample_rate: u32 = 44100;
//     const num_channels: u32 = 2;
//     // const bits_per_sample: u32 = 16;
//     const seconds_of_data: f32 = 0.2;
//     const frequency: f32 = 440.0;
//     const num_samples: u32 = sample_rate * seconds_of_data;
//     var data = std.mem.zeroes([num_samples * num_channels]i16);
//     var i: u32 = 0;
//     while (i < num_samples) : (i += 1) {
//         const sample: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_samples));
//         const sample_value: i16 = @intFromFloat(std.math.sin(sample * std.math.pi * 2 * frequency) * std.math.maxInt(i16));
//         var j: u32 = 0;
//         while (j < num_channels) : (j += 1) {
//             const offset: u32 = i * num_channels + j;
//             data[offset] = sample_value;
//         }
//     }
//     break :blk data;
// };
//
// pub const b_note = blk: {
//     @setEvalBranchQuota(500000);
//     const sample_rate: u32 = 44100;
//     const num_channels: u32 = 2;
//     // const bits_per_sample: u32 = 16;
//     const seconds_of_data: f32 = 0.2;
//     const frequency: f32 = 493.88;
//     const num_samples: u32 = sample_rate * seconds_of_data;
//     var data = std.mem.zeroes([num_samples * num_channels]i16);
//     var i: u32 = 0;
//     while (i < num_samples) : (i += 1) {
//         const sample: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_samples));
//         const sample_value: i16 = @intFromFloat(std.math.sin(sample * std.math.pi * 2 * frequency) * std.math.maxInt(i16));
//         var j: u32 = 0;
//         while (j < num_channels) : (j += 1) {
//             const offset: u32 = i * num_channels + j;
//             data[offset] = sample_value;
//         }
//     }
//     break :blk data;
// };
//
// pub const c_note = blk: {
//     @setEvalBranchQuota(5000000);
//     const sample_rate: u32 = 44100;
//     const num_channels: u32 = 2;
//     // const bits_per_sample: u32 = 16;
//     const seconds_of_data: f32 = 3;
//     const frequency: f32 = 523.251;
//     const num_samples: u32 = sample_rate * seconds_of_data;
//     var data = std.mem.zeroes([num_samples * num_channels]i16);
//     var i: u32 = 0;
//     while (i < num_samples) : (i += 1) {
//         const sample: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_samples));
//         const sample_value: i16 = @intFromFloat(std.math.sin(sample * std.math.pi * 2 * frequency) * std.math.maxInt(i16));
//         var j: u32 = 0;
//         while (j < num_channels) : (j += 1) {
//             const offset: u32 = i * num_channels + j;
//             data[offset] = sample_value;
//         }
//     }
//     break :blk data;
// };
