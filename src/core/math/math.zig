//! Math library
//!
//! This module provides a set of math functions and types.
//!
//! # Math
//! The math library provides a set of math functions and types.
//!
//! # Examples
//!
//! build.zig
//! ```zig
//! const math_lib = b.addModule("fr_math", .{
//!     .root_source_file = b.path("src/core/math/math.zig"),
//!     .target = target,
//!     .optimize = optimize,
//! });
//!  ...
//! exe.root_module.addImport("fr_math", math_lib);
//! ```
//!
//! ```zig
//! const math = @import("fr_core");
//! const Vec3 = math.Vec3;
//! pub fn main() !void {
//!     const v = Vec3.init(1.0, 2.0, 3.0);
//!     const v2 = v.muls(2.0);
//!     std.debug.print("v: {any}\n", .{v});
//!     std.debug.print("v2: {any}\n", .{v2});
//! }
//! ```
const builtin = @import("builtin");
const assert = std.debug.assert;

pub const pi = std.math.pi;
pub const e = std.math.e;

/// 2D extent
pub const Extent2D = extern struct {
    /// width of the extent
    width: u32,
    /// height of the extent
    height: u32,

    pub const default = Extent2D{ .width = 1, .height = 1 };
};

/// 2D rectangle defined by a position and an extent
pub const Rect2D = extern struct {
    /// position in the 2D space of the left-top corner
    position: extern struct { x: u32, y: u32 },
    /// extent of the rectangle
    extent: Extent2D,

    pub const default = Rect2D{
        .position = .{ .x = 0, .y = 0 },
        .extent = .default,
    };
};

pub const Vec2 = vec.Vec2;
pub const Vec3 = vec.Vec3;
pub const Vec4 = vec.Vec4;
pub const vec2s = Vec2.init;
pub const vec3s = Vec3.init;
pub const vec4s = Vec4.init;

pub const Quat = quaternion.Quat;
pub const quat = Quat.init;

pub const Quad = shapes.Quad;

pub const Transform = affine.Transform;
pub const transform = Transform.init;
pub const Mat2 = mat.Mat2;
pub const Mat3 = mat.Mat3;
pub const Mat4 = mat.Mat4;
pub const mat2x2 = Mat2.init;
pub const mat3x3 = Mat3.init;
pub const mat4x4 = Mat4.init;

pub const deg_to_rad = std.math.degreesToRadians;
pub const clamp = std.math.clamp;

pub const vec = @import("vec.zig");
pub const mat = @import("matrix.zig");
pub const affine = @import("affine.zig");
pub const quaternion = @import("quat.zig");
pub const shapes = @import("shapes.zig");

test "Math" {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
