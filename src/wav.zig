const std = @import("std");
const assert = std.debug.assert;

// TODO(adi): Do we want to return more than just the data?
pub const WavData = struct {
    data: []u8,
};

// TODO(adi): Use IO interface maybe?
// TODO(adi): Do we want to parse chunks other than the data and format chunks?
pub fn decode(allocator: std.mem.Allocator, data: []const u8) std.mem.Allocator.Error!WavData {
    const wav_header: *const MasterRIFFChunk = @ptrCast(@alignCast(data.ptr));

    assert(wav_header.file_type_block_id == MasterRIFFChunk.block_id);
    assert(wav_header.format == MasterRIFFChunk.format_id);

    var read_head: []const u8 = data[@sizeOf(MasterRIFFChunk)..];

    const state: ReaderState = .parse_next_chunk_header;

    var found_format_chunk: bool = false;

    loop: switch (state) {
        .parse_next_chunk_header => {
            const chunk_header: *align(1) const ChunkHeader = @ptrCast(@alignCast(read_head.ptr));
            switch (chunk_header.block_id.toInt()) {
                FormatChunk.block_id.toInt() => continue :loop .parse_format_chunk,
                DataChunk.block_id.toInt() => continue :loop .parse_data_chunk,
                else => {
                    // TODO(adi): Do we want to log this?
                    read_head = read_head[@sizeOf(ChunkHeader) + chunk_header.block_size ..];
                    continue :loop .parse_next_chunk_header;
                },
            }
        },
        .parse_format_chunk => {
            // TODO(adi): We cant have more than one format chunks in the file. Should we return an
            // error instead?
            assert(!found_format_chunk);
            found_format_chunk = true;
            const format_header: *align(1) const ChunkHeader = @ptrCast(@alignCast(read_head.ptr));
            read_head = read_head[@sizeOf(ChunkHeader)..];
            const format_chunk: *align(1) const FormatChunk = @ptrCast(@alignCast(read_head.ptr));

            // TODO(adi): We should probably not be asserting these and instead return them?
            // for now this is just hardcoded because our engine does not support any other formats.
            // Maybe we should return an error instead since this is debug code only. For release
            // we will have our own audio format.
            assert(format_chunk.audio_format == .pcm);
            assert(format_chunk.num_channels == 2);
            assert(format_chunk.bits_per_sample == 16);
            assert(format_chunk.frequency == 44100);
            assert(format_chunk.byte_per_block == 4);
            assert(format_chunk.byte_per_second == 44100 * 4);

            read_head = read_head[format_header.block_size..];

            continue :loop .parse_next_chunk_header;
        },
        .parse_data_chunk => {
            // TODO(adi): Can a wav file contain more than one data chunk?
            const data_chunk: *align(1) const ChunkHeader = @ptrCast(@alignCast(read_head.ptr));
            read_head = read_head[@sizeOf(ChunkHeader)..];

            const wav_data = try allocator.alloc(u8, data_chunk.block_size);
            @memcpy(wav_data, read_head[0..data_chunk.block_size]);
            return WavData{
                .data = wav_data,
            };
        },
    }
    unreachable;
}

const MasterRIFFChunk = extern struct {
    file_type_block_id: FourCC,
    file_size: u32,
    format: FourCC,

    pub const block_id: FourCC = .{ .byte_1 = 'R', .byte_2 = 'I', .byte_3 = 'F', .byte_4 = 'F' };
    pub const format_id: FourCC = .{ .byte_1 = 'W', .byte_2 = 'A', .byte_3 = 'V', .byte_4 = 'E' };
};

const FourCC = packed struct(u32) {
    byte_1: u8,
    byte_2: u8,
    byte_3: u8,
    byte_4: u8,

    pub fn toInt(self: FourCC) u32 {
        return @bitCast(self);
    }
};

const ChunkHeader = extern struct {
    block_id: FourCC,
    block_size: u32,
};

const FormatChunk = extern struct {
    audio_format: AudioFormat,
    num_channels: u16,
    frequency: u32,
    byte_per_second: u32,
    byte_per_block: u16,
    bits_per_sample: u16,

    pub const block_id: FourCC = @bitCast([_]u8{ 'f', 'm', 't', ' ' });
};

const DataChunk = struct {
    pub const block_id: FourCC = @bitCast([_]u8{ 'd', 'a', 't', 'a' });
};

const AudioFormat = enum(u16) {
    pcm = 1,
    ieee_754_float = 3,
};

const ReaderState = enum(u8) {
    parse_next_chunk_header,
    parse_format_chunk,
    parse_data_chunk,
};

test "WAV decoding copies only the PCM data chunk" {
    // Two stereo PCM frames, with unrelated chunks before and after the samples.
    var wav_data align(4) = ("RIFF\x44\x00\x00\x00WAVE" ++
        "fmt \x10\x00\x00\x00" ++
        "\x01\x00\x02\x00\x44\xac\x00\x00\x10\xb1\x02\x00\x04\x00\x10\x00" ++
        "JUNK\x04\x00\x00\x00skip" ++
        "data\x08\x00\x00\x00\x01\x00\xff\x7f\x00\x80\xfe\xff" ++
        "JUNK\x04\x00\x00\x00tail").*;
    const decoded = try decode(std.testing.allocator, &wav_data);
    defer std.testing.allocator.free(decoded.data);

    // The returned samples must remain valid after the caller reuses the source.
    @memset(&wav_data, 0);
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x00, 0xff, 0x7f, 0x00, 0x80, 0xfe, 0xff }, decoded.data);
}
