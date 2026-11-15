pub const width: u16 = 96;
pub const height: u16 = 96;
pub const cell_width: u16 = 6;
pub const cell_height: u16 = 12;

pub fn glyphOrigin(character: u8) struct { x: u16, y: u16 } {
    const ascii = if (character >= ' ' and character <= '~') character else '?';
    const index: u16 = ascii - ' ';
    const columns = width / cell_width;
    return .{ .x = index % columns * cell_width, .y = index / columns * cell_height };
}

pub const pixel_count = @as(usize, width) * height;

const atlas_bytes: *const [pixel_count * 4]u8 = @embedFile("monogram_pixels");
pub const pixels: [pixel_count]u32 = @bitCast(atlas_bytes.*);
