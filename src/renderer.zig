const types = @import("types.zig");
const Color = types.Color;

pub const Command = union(CommandType) {
    set_view: SetViewCommand,
    clear_screen: ClearCommand,
    draw_rectangle: DrawRectangleCommand,
};

pub const CommandType = enum(u8) {
    set_view,
    clear_screen,
    draw_rectangle,
};

pub const SetViewCommand = struct {
    meters_per_pixel: f32,
    camera_x: f32,
    camera_y: f32,
};

pub const ClearCommand = struct {
    r: f32,
    g: f32,
    b: f32,
};

pub const DrawRectangleCommand = struct {
    /// World position that stays fixed during rotation.
    pivot_world_x: f32,
    pivot_world_y: f32,
    width: f32,
    height: f32,
    /// Fraction of width/height measured from the unrotated top-left corner.
    /// Values outside [0, 1] place the pivot outside the rectangle.
    pivot_fraction_x: f32 = 0.5,
    pivot_fraction_y: f32 = 0.5,
    /// Positive angles rotate clockwise in the renderer's Y-down coordinates.
    angle_radians: f32 = 0,
    texture: ?Texture = null,
    tint_srgb: ?Color = null,
};

pub const Texture = enum(u32) {
    missing_texture = 0,
    _,
};
