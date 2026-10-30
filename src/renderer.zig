const std = @import("std");

const types = @import("types.zig");
const Color = types.Color;

pub const Command = union(CommandType) {
    set_view: SetViewCommand,
    clear_screen: ClearCommand,
    draw_rectangle: DrawRectangleCommand,
    draw_sprite: DrawSpriteCommand,
    draw_textured_rectangle: DrawTexturedRectangleCommand,
};

pub const CommandType = enum(u8) {
    set_view,
    clear_screen,
    draw_rectangle,
    draw_sprite,
    draw_textured_rectangle,
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

pub const DrawTexturedRectangleCommand = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    angle_radians: f32,
    texture: Texture,
    tint_srgb: ?Color,
};

pub const DrawSpriteCommand = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    texture: Texture,
};

pub const DrawRectangleCommand = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    angle_radians: f32,
    color_srgb: Color,
};

pub const Texture = enum(u32) { _ };
