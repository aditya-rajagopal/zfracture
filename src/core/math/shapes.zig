///! Shapes library
///!
///! This module provides a set of shapes types and functions.
///! The shapes are used to represent geometric primitives.
///!
///! # Examples
///!
///! ```
///! const math = @import("fr_core");
///! const Shapes = math.Shapes;
///! pub fn main() !void {
///!     const q = Shapes.Quad.default;
///! }
///! ```
const m = @import("vec.zig");

/// A quad is a rectangle with a bottom left and top right corner points specified in 2D space.
pub const Quad = extern struct {
    bottom_left: m.Vec2,
    top_right: m.Vec2,

    /// Default is a 1x1 quad anchored at the origin on the bottom left
    pub const default = Quad{
        .bottom_left = .zeros,
        .top_right = .ones,
    };
};

/// A quad in 3D space is a rectangle with a bottom left and top right corner points specified in 3D space.
pub const Quad3D = extern struct {
    /// The bottom left corner of the quad in 3D space
    bottom_left: m.Vec3,
    /// The top right corner of the quad in 3D space
    top_right: m.Vec3,

    /// Default is a 1x1 quad anchored at the origin on the bottom left
    pub const default = Quad3D{
        .bottom_left = .zeros,
        .top_right = .ones,
    };
};

/// A circle is a circle with a center point and a radius specified in 2D space.
pub const Circle = extern struct {
    center: m.Vec2,
    radius: f32,

    /// Default is a circle with radius 1 centered at the origin
    pub const default = Circle{
        .center = .zeros,
        .radius = 1.0,
    };
};

/// A circle in 3D space is a circle with a center point and a radius specified in 3D space.
pub const Circle3D = extern struct {
    center: m.Vec3,
    radius: f32,

    /// Default is a circle with radius 1 centered at the origin
    pub const default = Circle3D{
        .center = .zeros,
        .radius = 1.0,
    };
};
