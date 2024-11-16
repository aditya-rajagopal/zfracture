pub const MAX_IMAGE_DIM: u32 = 1 << 24;
pub const ImageFileType = enum(u8) {
    png,
    _,
};

pub const ImageLoadConfig = struct {
    flip_vertical_on_load: bool = true,
    format: ImageFileType = .png,
    requested_channels: u8 = 0,
};

pub const Image = struct {
    forced_transparency: bool,
    width: u32,
    height: u32,
    data: []u8,
};
