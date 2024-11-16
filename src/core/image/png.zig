const T = @import("types.zig");
const ImageLoadConfig = T.ImageLoadConfig;
const MAX_IMAGE_DIM = T.MAX_IMAGE_DIM;

pub const PNGError = error{
    OverflowImageSize,
    InvalidPNGHeader,
    InvalidPNG,
    InvalidPNGMalformed,
    InvalidPNGZlibHeader,
    InvalidPNGPresetDictionaryNotAllowed,
    InvalidPNGBadBlockType,
    InvalidPNGBadCompression,
    InvalidPNGNoIHDRFirst,
    InvalidPNGNoIDAT,
    InvalidPNGTooLarge,
    InvalidPNGZeroDimension,
    InvalidPNGBadBitDepth,
    InvalidPNGBadCtype,
    InvalidPNGCompression,
    InvalidPNGFilter,
    InvalidPNGInterlace,
    UnsupportedPNGFormat,
};

const PNGStackSize = 8;

const PNGInfo = struct {
    compression_method: u8,
    filter_method: u8,
    interlace_method: u8,
    bit_depth: u8,
    num_channels: u8,
    colour_type: ColourType,
    width: u32,
    height: u32,

    pub const ColourType = enum(u8) {
        grayscale = 0,
        rgb = 2,
        plte = 3,
        grayscale_alpha = 4,
        rgba = 6,

        pub inline fn get_num_channels(self: ColourType) u8 {
            return switch (self) {
                .grayscale, .plte => 1,
                .grayscale_alpha => 2,
                .rgb => 3,
                .rgba => 4,
            };
        }
    };
};

fn PNGType(comptime type_name: []const u8) u32 {
    comptime assert(type_name.len == 4);
    return (@as(u32, type_name[3]) << 24) + (@as(u32, type_name[2]) << 16) + (@as(u32, type_name[1]) << 8) + @as(u32, type_name[0]);
}

const ChunkType = enum(u32) {
    null_type = 0,
    // Critical
    IDAT = PNGType("IDAT"),
    IEND = PNGType("IEND"),
    IHDR = PNGType("IHDR"),
    PLTE = PNGType("PLTE"),

    // Optional
    bKGD = PNGType("bKGD"),
    cHRM = PNGType("cHRM"),
    dSIG = PNGType("dSIG"),
    fRAc = PNGType("fRAc"),
    gAMA = PNGType("gAMA"),
    gIFg = PNGType("gIFg"),
    gIFt = PNGType("gIFt"),
    gIFx = PNGType("gIFx"),
    hIST = PNGType("hIST"),
    iCCP = PNGType("iCCP"),
    iTXt = PNGType("iTXt"),
    oFFs = PNGType("oFFs"),
    pCAL = PNGType("pCAL"),
    pHYs = PNGType("pHYs"),
    sBIT = PNGType("sBIT"),
    sCAL = PNGType("sCAL"),
    sPLT = PNGType("sPLT"),
    sRGB = PNGType("sRGB"),
    sTER = PNGType("sTER"),
    tEXt = PNGType("tEXt"),
    tRNS = PNGType("tRNS"),
    zTXt = PNGType("zTXt"),

    // Public chunks
    _,
};

const PNGStates = enum(u8) {
    read_more_data,
    read_chunk,
    parse_chunk,
    end_chunk,
};

const PNGContext = struct {
    info: PNGInfo,
    current_chunk: struct {
        length: u32,
        tag: ChunkType,
    },
    data: []const u8,
    raw_data: std.ArrayList(u8),
    state: [PNGStackSize]PNGStates,
    state_ptr: u32,

    pub inline fn push_state(self: *PNGContext, state: PNGStates) void {
        assert(self.state_ptr < PNGStackSize);
        self.state[self.state_ptr] = state;
        self.state_ptr += 1;
    }

    pub inline fn pop_state(self: *PNGContext) PNGStates {
        assert(self.state_ptr != 0);
        self.state_ptr -= 1;
        return self.state[self.state_ptr];
    }

    pub fn current_state(self: *const PNGContext) PNGStates {
        assert(self.state_ptr != 0);
        return self.state[self.state_ptr - 1];
    }
};

// The standard PNG header that all PNG files should have
const PNGHeader: []const u8 = &[_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
const BufferSize = 4096 * 1;
comptime {
    assert(BufferSize > 8);
}

pub fn read(file: std.fs.File, allocator: Allocator, comptime config: ImageLoadConfig) !T.Image {
    var temp_buffer: [BufferSize]u8 = undefined;
    const reader = file.reader();
    var ctx: PNGContext = undefined;

    const header_len = try reader.read(temp_buffer[0..8]);
    if (header_len == 0) {
        return error.InvalidPNG;
    }
    ctx.data = temp_buffer[0..header_len];

    try test_png_header(ctx.data);

    ctx.current_chunk.tag = .null_type;
    ctx.state_ptr = 0;
    ctx.data.len = 0;
    ctx.raw_data = std.ArrayList(u8).init(allocator);
    defer ctx.raw_data.deinit();

    ctx.push_state(.read_chunk);
    ctx.push_state(.read_more_data);

    var first_chunk: bool = true;

    while (true) {
        switch (ctx.current_state()) {
            .read_more_data => {
                // std.debug.print("Reading data\n", .{});
                if (ctx.data.len == 0) {
                    const len = try reader.read(&temp_buffer);
                    if (len == 0) {
                        return error.InvalidPNG;
                    }
                    ctx.data = temp_buffer[0..len];
                } else {
                    std.mem.copyForwards(u8, &temp_buffer, ctx.data);
                    // var temp: [BufferSize]u8 = undefined;
                    // @memcpy(temp[0..ctx.data.len], ctx.data);
                    // @memcpy(buffer[0..ctx.data.len], temp[0..ctx.data.len]);
                    var len = try reader.read(temp_buffer[ctx.data.len..]);
                    if (len == 0) {
                        return error.InvalidPNG;
                    }
                    len += ctx.data.len;
                    ctx.data = temp_buffer[0..len];
                }
                _ = ctx.pop_state();
            },
            .read_chunk => {
                assert(ctx.current_chunk.tag == .null_type);
                if (ctx.data.len < 8) {
                    ctx.push_state(.read_more_data);
                    continue;
                }
                _ = ctx.pop_state();
                ctx.current_chunk.length = std.mem.readInt(u32, ctx.data[0..4], .big);
                ctx.current_chunk.tag = @enumFromInt(std.mem.readInt(u32, ctx.data[4..8], .little));

                ctx.push_state(.end_chunk);
                ctx.push_state(.parse_chunk);
                ctx.data = ctx.data[8..];
                if (ctx.data.len < ctx.current_chunk.length) {
                    ctx.push_state(.read_more_data);
                    continue;
                }
            },
            .parse_chunk => {
                // std.debug.print("Current chunk: {any}\n", .{ctx.current_chunk});
                switch (ctx.current_chunk.tag) {
                    .IHDR => {
                        assert(ctx.current_chunk.length == 13);
                        // We should always have this
                        if (ctx.data.len < 13) {
                            return error.InvalidPNG;
                        }
                        if (!first_chunk) {
                            return error.InvalidPNGNoIHDRFirst;
                        }
                        first_chunk = false;

                        ctx.info.width = std.mem.readInt(u32, ctx.data[0..4], .big);
                        ctx.info.height = std.mem.readInt(u32, ctx.data[4..8], .big);
                        if (ctx.info.width > MAX_IMAGE_DIM) {
                            return error.InvalidPNGTooLarge;
                        }
                        if (ctx.info.height > MAX_IMAGE_DIM) {
                            return error.InvalidPNGTooLarge;
                        }
                        if (ctx.info.height == 0) {
                            return error.InvalidPNGZeroDimension;
                        }
                        if (ctx.info.width == 0) {
                            return error.InvalidPNGZeroDimension;
                        }

                        const bit_depth = std.mem.readInt(u8, ctx.data[8..9], .little);
                        ctx.info.bit_depth = bit_depth;
                        if (bit_depth != 1 and bit_depth != 2 and bit_depth != 4 and bit_depth != 8 and bit_depth != 16) {
                            return error.InvalidPNGBadBitDepth;
                        }

                        const colour_type = std.mem.readInt(u8, ctx.data[9..10], .little);
                        if (colour_type > 6) {
                            return error.InvalidPNGBadCtype;
                        }
                        ctx.info.colour_type = @enumFromInt(colour_type);
                        ctx.info.num_channels = ctx.info.colour_type.get_num_channels();

                        ctx.info.compression_method = std.mem.readInt(u8, ctx.data[10..11], .little);
                        if (ctx.info.compression_method != 0) {
                            return error.InvalidPNGCompression;
                        }
                        ctx.info.filter_method = std.mem.readInt(u8, ctx.data[11..12], .little);
                        if (ctx.info.filter_method != 0) {
                            return error.InvalidPNGFilter;
                        }

                        ctx.info.interlace_method = std.mem.readInt(u8, ctx.data[12..13], .little);
                        if (ctx.info.interlace_method > 1) {
                            return error.InvalidPNGInterlace;
                        }
                        ctx.data = ctx.data[13..];
                        // NOTE: Trying to reserve some reasonable amount based on some example images
                        ctx.raw_data = try std.ArrayList(u8).initCapacity(
                            allocator,
                            (ctx.info.width + 1) * ctx.info.height * ctx.info.num_channels,
                        );

                        if (ctx.info.bit_depth != 8 or // WARN: Only suuport 8bit format
                            ctx.info.interlace_method != 0 or // WARN: Only non-interlaced images
                            ctx.info.colour_type == .plte // WARN: Cannot deal wth palletes
                        ) {
                            std.debug.print(
                                "Bit_depth: {d}, interlace: {d}, colour_type: {s}\n",
                                .{ ctx.info.bit_depth, ctx.info.interlace_method, @tagName(ctx.info.colour_type) },
                            );
                            return error.UnsupportedPNGFormat;
                        }
                    },
                    .IDAT => {
                        if (first_chunk) {
                            return error.InvalidPNGNoIHDRFirst;
                        }
                        if (ctx.data.len < ctx.current_chunk.length) {
                            ctx.current_chunk.length -= @truncate(ctx.data.len);
                            try ctx.raw_data.appendSlice(ctx.data);
                            ctx.data.len = 0;
                            ctx.push_state(.read_more_data);
                            continue;
                        }
                        try ctx.raw_data.appendSlice(ctx.data[0..ctx.current_chunk.length]);
                        ctx.data = ctx.data[ctx.current_chunk.length..];
                    },
                    .IEND => {
                        if (first_chunk) {
                            return error.InvalidPNGNoIHDRFirst;
                        }
                        if (ctx.raw_data.items.len == 0) {
                            return error.InvalidPNGNoIDAT;
                        }
                        assert(ctx.current_chunk.length == 0);
                        ctx.data = ctx.raw_data.items;
                        break;
                        // png_done = true;
                    },
                    else => {
                        if (first_chunk) {
                            return error.InvalidPNGNoIHDRFirst;
                        }
                        if (ctx.data.len < ctx.current_chunk.length) {
                            ctx.current_chunk.length -= @truncate(ctx.data.len);
                            ctx.data.len = 0;
                            ctx.push_state(.read_more_data);
                            continue;
                        }
                        ctx.data = ctx.data[ctx.current_chunk.length..];
                    },
                }
                _ = ctx.pop_state();
            },
            .end_chunk => {
                if (ctx.data.len < 4) {
                    ctx.push_state(.read_more_data);
                    continue;
                }
                _ = ctx.pop_state();
                ctx.data = ctx.data[4..];
                ctx.current_chunk.length = 0;
                ctx.current_chunk.tag = .null_type;
                // if (png_done) break;
                ctx.push_state(.read_chunk);
            },
        }
    }
    {
        // NOTE: Validate zlib header
        assert(ctx.data.len >= 2);
        const compression_mode_flags: u32 = ctx.data[0];
        const compression_mode: u32 = compression_mode_flags & 15;
        const flag: u32 = ctx.data[1];
        ctx.data = ctx.data[2..];
        {
            // NOTE: Zlib spec
            if (ctx.data.len == 0) {
                return error.InvalidPNG;
            }
            if ((compression_mode_flags * 256 + flag) % 31 != 0) {
                return error.InvalidPNGZlibHeader;
            }
        }

        {
            // NOTE: PNG spec preset directory not allowed
            if (flag & 32 != 0) {
                return error.InvalidPNGPresetDictionaryNotAllowed;
            }

            if (compression_mode != 8) {
                return error.InvalidPNGBadCompression;
            }
        }
    }

    var size = (ctx.info.width * ctx.info.bit_depth * ctx.info.num_channels + 7) >> 3;
    size = (size + 1) * ctx.info.height;
    var uncompressed_data = try std.ArrayList(u8).initCapacity(allocator, size);
    defer uncompressed_data.deinit();

    var z_ctx = ZlibContext{
        .data = ctx.data,
        .num_bits = 0,
        .bit_buffer = 0,
        .length = undefined,
        .distance = undefined,
    };

    var is_final_block: u32 = 0;
    var length_huffman: HuffmanTree = undefined;
    var distance_huffman: HuffmanTree = undefined;

    while (is_final_block == 0) {
        is_final_block = try z_ctx.consume(1);
        const block_type: ZlibBlockType = @enumFromInt(try z_ctx.consume(2));
        switch (block_type) {
            .uncompressed => {
                _ = try z_ctx.consume(5);
                // Drain out the existing data in the bit buffer.
                // It is assumed that the num bits is a multiple of 8 else it is a problem
                var k: usize = 0;
                var header: [4]u8 = undefined;
                while (z_ctx.num_bits > 0) {
                    header[k] = @truncate(z_ctx.bit_buffer & 255);
                    k += 1;
                    z_ctx.bit_buffer >>= 8;
                    z_ctx.num_bits -= 8;
                }

                // Fill the rest directly
                while (k < 4) {
                    header[k] = z_ctx.data[0];
                    z_ctx.data = z_ctx.data[1..];
                    k += 1;
                }

                const data_size: u16 = @as(u16, header[1]) * 256 + header[0];
                const ndata_size: u16 = @as(u16, header[3]) * 256 + header[2];

                if (ndata_size != data_size ^ 0xFFFF) {
                    return error.InvalidPNG;
                }
                if (data_size > z_ctx.data.len) {
                    return error.InvalidPNG;
                }
                try uncompressed_data.appendSlice(z_ctx.data[0..data_size]);
                z_ctx.data = z_ctx.data[data_size..];
                continue;
            },
            .fixed_huffman => {
                z_ctx.length = &default_length_huffman;
                z_ctx.distance = &default_distaces_huffman;
            },
            .dynamic_huffman => {
                // TODO: Compute the dynamic huffman
                const length_swizzle = [_]u8{ 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };

                const hlit = try z_ctx.consume(5) + 257;
                const hdist = try z_ctx.consume(5) + 1;
                const hclen = try z_ctx.consume(4) + 4;

                // NOTE: We can have codes from 1-18
                var sizes: [19]u8 = std.mem.zeroes([19]u8);

                for (0..hclen) |i| {
                    sizes[length_swizzle[i]] = @truncate(try z_ctx.consume(3));
                }

                var huffman_huffman: HuffmanTree = undefined;
                try huffman_huffman.init(&sizes);

                const total = hlit + hdist;
                // From stb_image. HLIT can be at most 286 and HDIST can be atmost 32. The last code could be 18
                // and repeat for 138 times. So pad it out for safety
                var dynamic_huffman_data: [286 + 32 + 137]u8 = undefined;

                var index: usize = 0;
                while (index < total) {
                    var code: u32 = z_ctx.decode(&huffman_huffman);
                    var fill: u8 = 0;
                    switch (code) {
                        0...15 => {
                            dynamic_huffman_data[index] = @truncate(code);
                            index += 1;
                            continue;
                        },
                        16 => {
                            code = try z_ctx.consume(2) + 3;
                            assert(index != 0);
                            fill = dynamic_huffman_data[index - 1];
                        },
                        17 => code = try z_ctx.consume(3) + 3,
                        18 => code = try z_ctx.consume(7) + 11,
                        else => return error.InvalidPNGMalformed,
                    }
                    if (index + code > total) return error.InvalidPNGMalformed;
                    @memset(dynamic_huffman_data[index .. index + code], fill);
                    index += code;
                }
                try length_huffman.init(dynamic_huffman_data[0..hlit]);
                try distance_huffman.init(dynamic_huffman_data[hlit .. hlit + hdist]);

                z_ctx.length = &length_huffman;
                z_ctx.distance = &distance_huffman;
            },
            .invalid_reserved => return error.InvalidPNGBadBlockType,
        }
        {
            // NOTE: Parse huffman block
            while (true) {
                var code: u32 = z_ctx.decode_length();
                switch (code) {
                    0...255 => {
                        try uncompressed_data.append(@truncate(code));
                    },
                    256 => {
                        // TODO: Check for malformed data that reads more than end of raw data
                        break;
                    },
                    257...285 => {
                        code = code - 257;
                        var length = length_base[code];
                        if (length_extra[code] != 0) {
                            length += try z_ctx.consume(@truncate(length_extra[code]));
                        }

                        code = z_ctx.decode_dist();
                        assert(code < 30);
                        var dist = dist_base[code];
                        if (dist_extra[code] != 0) {
                            dist += try z_ctx.consume(@truncate(dist_extra[code]));
                        }

                        if (uncompressed_data.items.len < dist) return error.InvalidPNGMalformed;

                        if (length != 0) {
                            if (dist == 1) {
                                try uncompressed_data.appendNTimes(uncompressed_data.items[uncompressed_data.items.len - 1], length);
                            } else {
                                const start = uncompressed_data.items.len;
                                const read_start = uncompressed_data.items.len - dist;
                                try uncompressed_data.resize(uncompressed_data.items.len + length);
                                // for (0..length) |i| {
                                //     uncompressed_data.items[start + i] = uncompressed_data.items[read_start + i];
                                // }
                                std.mem.copyForwards(
                                    u8,
                                    uncompressed_data.items[start..],
                                    uncompressed_data.items[read_start .. read_start + length],
                                );
                            }
                        }
                    },
                    else => return error.InvalidPNG,
                }
            }
        }
    }

    var num_channles = ctx.info.num_channels;
    if (config.requested_channels == ctx.info.num_channels + 1 and config.requested_channels != 3) {
        num_channles += 1;
    }

    // WARN: Only supporting 8 bits per channel
    const width_stride, var overflow = @mulWithOverflow(ctx.info.width, num_channles);
    var img_len: u32 = 0;
    if (overflow == 0) {
        img_len, overflow = @mulWithOverflow(width_stride, ctx.info.height);
        if (overflow != 0) {
            return error.OverflowImageSize;
        }
    } else {
        return error.OverflowImageSize;
    }
    const width_bytes, overflow = @mulWithOverflow(ctx.info.width, ctx.info.num_channels);
    if (overflow != 0) {
        return error.OverflowImageSize;
    }

    if (uncompressed_data.items.len < width_bytes * ctx.info.height) {
        return error.InvalidPNG;
    }

    const out_data = try allocator.alloc(u8, img_len);
    errdefer allocator.free(out_data);

    // NOTE: We crete 2 buffers for scanlines. But this one will use the channels of the read image
    const filter_buffer = try allocator.alloc(u8, width_bytes * 2);
    defer allocator.free(filter_buffer);
    const raw_channels = ctx.info.num_channels;

    {
        // INFO: Unfilter the uncompressed data
        const front_back_buffer = [_][]u8{ filter_buffer[0..width_bytes], filter_buffer[width_bytes..] };

        var unfiltered = uncompressed_data.items;

        const first_filter_map = [5]FilterTypes{ .none, .sub, .none, .average, .sub };

        for (0..ctx.info.height) |i| {
            const dest_buffer = out_data[width_stride * i .. width_stride * (i + 1)];
            const current_buffer = front_back_buffer[i & 1];
            const previous_buffer = front_back_buffer[~i & 1];

            // INFO: from stb_image: for the first scanline it is useful to redeine the filter type based on what the
            // filtering alogrithm transforms into assuming the previous scanline is all 0s
            const filter_type: FilterTypes = if (i == 0) first_filter_map[unfiltered[0]] else @enumFromInt(unfiltered[0]);
            // if (i == 24) {
            //     std.debug.print("i[{d}]:  [{d}], [{d}]\n", .{ i, i & 1, ~i & 1 });
            //     std.debug.print("Filter Type:{s}, {d}\n", .{ @tagName(filter_type), unfiltered[0] });
            // }
            unfiltered = unfiltered[1..];

            switch (filter_type) {
                .none => {
                    @memcpy(current_buffer, unfiltered[0..width_bytes]);
                },
                .sub => {
                    @memcpy(current_buffer[0..raw_channels], unfiltered[0..raw_channels]);
                    for (raw_channels..width_bytes) |pixel| {
                        current_buffer[pixel] = @truncate(
                            @as(u64, unfiltered[pixel]) + current_buffer[pixel - raw_channels],
                        );
                    }
                },
                .up => {
                    for (0..width_bytes) |pixel| {
                        current_buffer[pixel] = @truncate(
                            @as(u64, unfiltered[pixel]) + previous_buffer[pixel],
                        );
                    }
                },
                .average => {
                    for (0..raw_channels) |channel| {
                        // Previous in current buffer is 0
                        current_buffer[channel] = @truncate(
                            (@as(u64, unfiltered[channel]) + (previous_buffer[channel] >> 1)) & 255,
                        );
                    }

                    for (raw_channels..width_bytes) |pixel| {
                        current_buffer[pixel] = @truncate(
                            @as(u64, unfiltered[pixel]) +
                                ((@as(u64, previous_buffer[pixel]) + current_buffer[pixel - raw_channels]) >> 1),
                        );
                    }
                },
                .paeth => {
                    for (0..raw_channels) |channel| {
                        current_buffer[channel] = @truncate(
                            (@as(u64, unfiltered[channel]) + previous_buffer[channel]),
                        );
                    }
                    for (raw_channels..width_bytes) |pixel| {
                        current_buffer[pixel] =
                            @bitCast(
                            @as(
                                i8,
                                @truncate(
                                    @as(i32, unfiltered[pixel]) +
                                        stbi__paeth(
                                        current_buffer[pixel - raw_channels],
                                        previous_buffer[pixel],
                                        previous_buffer[pixel - raw_channels],
                                    ),
                                ),
                            ),
                        );
                    }
                },
                .average_first => {
                    @memcpy(current_buffer[0..raw_channels], unfiltered[0..raw_channels]);
                    for (raw_channels..width_bytes) |pixel| {
                        current_buffer[pixel] = @truncate(
                            @as(u32, unfiltered[pixel]) + (current_buffer[pixel - raw_channels] >> 1),
                        );
                    }
                },
            }
            unfiltered = unfiltered[width_bytes..];

            // WARN: Again this only accepts 8bit per channel images so we dont need any other checks
            if (raw_channels == num_channles) {
                @memcpy(dest_buffer, current_buffer);
            } else {
                // NOTE: add 255 to the alhpa channel
                if (raw_channels == 1) {
                    for (0..ctx.info.width) |col| {
                        dest_buffer[col * 2 + 0] = current_buffer[col];
                        dest_buffer[col * 2 + 1] = 255;
                    }
                } else {
                    assert(raw_channels == 3);
                    for (0..ctx.info.width) |col| {
                        dest_buffer[col * 4 + 0] = current_buffer[col * 3 + 0];
                        dest_buffer[col * 4 + 1] = current_buffer[col * 3 + 1];
                        dest_buffer[col * 4 + 2] = current_buffer[col * 3 + 2];
                        dest_buffer[col * 4 + 3] = 255;
                    }
                }
            }
        }
    }

    if (comptime config.flip_vertical_on_load) {
        for (0..ctx.info.height >> 1) |row| {
            var row0 = out_data[row * width_stride ..];
            var row1 = out_data[(ctx.info.height - row - 1) * width_stride ..];

            var bytes_to_write = width_stride;
            while (bytes_to_write > 0) {
                const current_copy = if (bytes_to_write <= 4096) bytes_to_write else 4096;
                @memcpy(temp_buffer[0..current_copy], row0[0..current_copy]);
                @memcpy(row0[0..current_copy], row1[0..current_copy]);
                @memcpy(row1[0..current_copy], temp_buffer[0..current_copy]);
                row0 = row0[current_copy..];
                row1 = row1[current_copy..];
                bytes_to_write -= current_copy;
            }
        }
    }

    return T.Image{
        .forced_transparency = raw_channels != num_channles,
        .data = out_data,
        .height = ctx.info.height,
        .width = ctx.info.width,
    };
}

/// Sraight up ripped from https://github.com/nothings/stb/blob/master/stb_image.h
fn stbi__paeth(a: i32, b: i32, c: i32) i32 {
    // This formulation looks very different from the reference in the PNG spec, but is
    // actually equivalent and has favorable data dependencies and admits straightforward
    // generation of branch-free code, which helps performance significantly.
    const thresh = c * 3 - (a + b);
    const lo = if (a < b) a else b;
    const hi = if (a < b) b else a;
    const t0 = if (hi <= thresh) lo else c;
    const t1 = if (thresh <= lo) hi else t0;
    return t1;
}

const FilterTypes = enum(u8) {
    none = 0,
    sub = 1,
    up = 2,
    average = 3,
    paeth = 4,
    // Idea from stb_image
    average_first = 5,
};

const default_length_sizes: [HuffmanTree.NUM_SYMBOLS]u8 =
    [_]u8{8} ** (144) ++
    [_]u8{9} ** (256 - 144) ++
    [_]u8{7} ** (280 - 256) ++
    [_]u8{8} ** (288 - 280);
const default_distances_sizes: [32]u8 = [_]u8{5} ** 32;

const default_length_huffman = blk: {
    @setEvalBranchQuota(100000);
    var tree: HuffmanTree = std.mem.zeroes(HuffmanTree);
    // tree.fast_table[0] = 0;
    tree.init(&default_length_sizes) catch unreachable;
    break :blk tree;
};
const default_distaces_huffman = blk: {
    @setEvalBranchQuota(100000);
    var tree: HuffmanTree = std.mem.zeroes(HuffmanTree);
    // tree.fast_table[0] = 0;
    tree.init(&default_distances_sizes) catch unreachable;
    break :blk tree;
};

const length_base = [31]u32{
    3,   4,   5,   6,   7,   8,  9,  10,
    11,  13,  15,  17,  19,  23, 27, 31,
    35,  43,  51,  59,  67,  83, 99, 115,
    131, 163, 195, 227, 258, 0,  0,
};

const length_extra = [31]u32{
    0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 2, 2, 2, 2,
    3, 3, 3, 3, 4, 4, 4, 4,
    5, 5, 5, 5, 0, 0, 0,
};

const dist_base = [32]u32{
    1,    2,    3,    4,     5,     7,     9,    13,
    17,   25,   33,   49,    65,    97,    129,  193,
    257,  385,  513,  769,   1025,  1537,  2049, 3073,
    4097, 6145, 8193, 12289, 16385, 24577, 0,    0,
};

const dist_extra = [32]u32{
    0,  0,  0,  0,  1,  1,  2,  2,
    3,  3,  4,  4,  5,  5,  6,  6,
    7,  7,  8,  8,  9,  9,  10, 10,
    11, 11, 12, 12, 13, 13, 0,  0,
};

comptime {
    assert(default_length_huffman.first_code[0] == 0);
    assert(default_distaces_huffman.first_code[0] == 0);
}

const HuffmanTree = struct {
    fast_table: [FAST_TABLE_SIZE]u16,
    first_code: [16]u16,
    first_symbol: [16]u16,
    max_codes: [17]u32,
    sizes: [NUM_SYMBOLS]u8,
    values: [NUM_SYMBOLS]u16,

    const MAX_FAST_BITS = 9;
    const FAST_CHECK_MASK = ((@as(u16, 1) << 9) - 1);
    const FAST_TABLE_SIZE = 1 << 9;
    const NUM_SYMBOLS = 288;

    pub fn init(self: *HuffmanTree, sizes: []const u8) !void {
        // 1. Create a list that counts the frequency of each bit length that represents a symbol
        // 1 - 16 + 0 = 17
        var size_counts: [17]u16 = [_]u16{0} ** 17;
        for (sizes) |s| {
            size_counts[s] += 1;
        }
        size_counts[0] = 0;
        // 2. X bits cannot have an occurance of more than (1 << X) bits. THat is not physicaly possible
        for (1..16) |i| {
            if (size_counts[i] > (@as(u16, 1) << @truncate(i))) return error.InvalidPNGMalformed;
        }
        // 3. The spec says you cannot have more than 16 bits. Starting from 1 bits(0 is not a thing) check how many
        //    codes are needed for all the bits lower than it.
        var next_code: [16]u32 = undefined;
        var code: u32 = 0;
        var num_symbols_per_bit: u32 = 0;
        for (1..16) |i| {
            next_code[i] = code;
            // Maintain a second list that is immuatble after
            self.first_code[i] = @truncate(code);
            // Location in the list of symbols where values are stored
            self.first_symbol[i] = @truncate(num_symbols_per_bit);
            // Increment to the final code that will be represented by this bit length. Symbols have to be consequtive
            code = code + size_counts[i];
            // We can also create a mask using this final value by shifting it up 16 - i. If you take a chunk of 16 bits
            // from the compressed stream and reverse the bits if that number is less than the defined number it must be
            // represented by i bits.
            self.max_codes[i] = code << @truncate(16 - i);
            if (size_counts[i] != 0) {
                if (code - 1 >= (@as(u32, 1) << @truncate(i))) return error.InvalidPNGMalformed;
            }
            code <<= 1;
            num_symbols_per_bit += size_counts[i];
        }
        self.max_codes[16] = 0x10000; // any 16 bit number will be less than this
        // 4. Then take these next codes and go through the list of bit lengths for each symbol and in order assign them
        //    the next available code for that bit size
        @memset(&self.fast_table, 0);
        for (sizes, 0..) |s, i| {
            if (s != 0) {
                // location inside the size and values array. We can find the size needed from the max_codes
                // and recreate this location when decoding
                const location = next_code[s] - self.first_code[s] + self.first_symbol[s];
                self.sizes[location] = s;
                self.values[location] = @truncate(i);
                const fast_value: u16 = (@as(u16, s) << HuffmanTree.MAX_FAST_BITS) | @as(u16, @truncate(i));
                if (s <= HuffmanTree.MAX_FAST_BITS) {
                    // Take the next available code and reverse it in place. Store the fast value in that location
                    // and all locations that have the lower s bits the same
                    var j: u32 = @bitReverse(@as(u16, @truncate(next_code[s]))) >> @truncate(16 - s);
                    while (j < HuffmanTree.FAST_TABLE_SIZE) {
                        self.fast_table[j] = fast_value;
                        j += (@as(u32, 1) << @truncate(s));
                    }
                }
                next_code[s] += 1;
            }
        }
    }
};

inline fn test_png_header(data: []const u8) PNGError!void {
    if (data.len < 8) {
        return error.InvalidPNGHeader;
    }

    if (!std.mem.eql(u8, data[0..8], PNGHeader)) {
        return error.InvalidPNGHeader;
    }
}

const ZlibContext = struct {
    done: bool = false,
    data: []const u8,
    num_bits: u8 = 0,
    bit_buffer: u32 = 0,
    length: *const HuffmanTree,
    distance: *const HuffmanTree,

    pub fn fill_buffer(self: *ZlibContext) void {
        while (self.num_bits <= 24) {
            if (self.data.len == 0) {
                self.done = true;
                return;
            }
            self.bit_buffer |= @as(u32, @intCast(self.data[0])) << @truncate(self.num_bits);
            self.data = self.data[1..];
            self.num_bits += 8;
        }
    }

    pub fn consume(self: *ZlibContext, num_bits: u5) !u32 {
        var result: u32 = undefined;
        while (self.num_bits < num_bits and self.data.len != 0) {
            self.bit_buffer |= @as(u32, @intCast(self.data[0])) << @truncate(self.num_bits);
            self.data = self.data[1..];
            self.num_bits += 8;
        }
        if (num_bits <= self.num_bits) {
            result = self.bit_buffer & ((@as(u32, 1) << num_bits) - 1);
            self.bit_buffer >>= num_bits;
            self.num_bits -%= num_bits;
        } else {
            return error.InvalidPNGMalformed;
        }
        return result;
    }

    pub inline fn decode_length(self: *ZlibContext) u16 {
        return self.decode(self.length);
    }

    pub inline fn decode_dist(self: *ZlibContext) u16 {
        return self.decode(self.distance);
    }

    pub fn decode(self: *ZlibContext, huffman: *const HuffmanTree) u16 {
        // 1. Fill in the bit buffer.
        if (self.num_bits < 16) {
            self.fill_buffer();
        }

        // 2. Check the next 9 bits to see if it is in the fast table already. If it is return the code
        const fast_value = huffman.fast_table[self.bit_buffer & HuffmanTree.FAST_CHECK_MASK];
        if (fast_value != 0) {
            const size = fast_value >> 9;
            self.bit_buffer >>= @truncate(size);
            self.num_bits -= @truncate(size);
            return fast_value & 511;
        }

        // NOTE: If we cant find it in the fast table then the encoding is more than MAX_FAST_BITS

        // We need to reverse the data as the data comes in a network byte order
        const data = @bitReverse(@as(u16, @truncate(self.bit_buffer)));
        var size: u8 = HuffmanTree.MAX_FAST_BITS + 1;
        for (size..17) |i| {
            if (data < huffman.max_codes[i]) {
                size = @truncate(i);
                break;
            }
        }
        assert(size < 16);

        const bytes = data >> @truncate(16 - size);
        // find the position in the vlaues and size array
        const location = bytes - huffman.first_code[size] + huffman.first_symbol[size];
        if (huffman.sizes[location] != size) {
            std.debug.print("Size: {d}, {d}", .{ huffman.sizes[location], size });
        }
        assert(huffman.sizes[location] == size);

        self.bit_buffer >>= @truncate(size);
        self.num_bits -= size;

        return huffman.values[location];
    }
};

pub const ZlibBlockType = enum(u8) {
    uncompressed = 0,
    fixed_huffman = 1,
    dynamic_huffman = 2,
    invalid_reserved = 3,
};

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
