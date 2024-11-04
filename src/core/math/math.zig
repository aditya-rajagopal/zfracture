pub const Extent2D = extern struct {
    width: u32,
    height: u32,
};

pub const Rect2D = extern struct {
    position: extern struct { x: u32, y: u32 },
    extent: Extent2D,
};

pub const Vec2 = vec.Vec2(f32);
pub const Vec3 = vec.Vec3(f32);
pub const Vec4 = vec.Vec4(f32);
pub const vec2s = Vec2.init;
pub const vec3s = Vec3.init;
pub const vec4s = Vec4.init;

pub const Quat = quaternion.Quaternion(f32);
pub const quat = Quat.init;

pub const Rectangle = shapes.Rectangle;

pub const Transform = affine.Affine(f32);
pub const transform = Transform.init;
pub const Mat2 = mat.Mat2x2(f32);
pub const mat2x2 = Mat2.init;
pub const Mat3 = mat.Mat3x3(f32);
pub const mat3x3 = Mat3.init;
pub const Mat4 = mat.Mat4x4(f32);
pub const mat4x4 = Mat4.init;

// pub const Vec2i = vec.Vec2(i32);
// pub const Vec3i = vec.Vec3(i32);
// pub const Vec4i = vec.Vec4(i32);
// pub const vec2i = Vec2i.init;
// pub const vec3i = Vec3i.init;
// pub const vec4i = Vec4i.init;
//
// pub const Vec2u = vec.Vec2(u32);
// pub const Vec3u = vec.Vec3(u32);
// pub const Vec4u = vec.Vec4(u32);
// pub const vec2u = Vec2u.init;
// pub const vec3u = Vec3u.init;
// pub const vec4u = Vec4u.init;
//
// pub const Vec2d = vec.Vec2(f64);
// pub const Vec3d = vec.Vec3(f64);
// pub const Vec4d = vec.Vec4(f64);
// pub const vec2d = Vec2d.init;
// pub const vec3d = Vec3d.init;
// pub const vec4d = Vec4d.init;

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
