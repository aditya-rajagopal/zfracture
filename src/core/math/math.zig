pub const Extent = extern struct {
    width: u32,
    height: u32,
};

pub const Rect2D = extern struct {
    position: extern struct { width: u32, height: u32 },
    extent: Extent,
};

pub const Vec2s = vec.Vec2(f32);
pub const Vec3s = vec.Vec3(f32);
pub const Vec4s = vec.Vec4(f32);
pub const vec2s = Vec2s.init;
pub const vec3s = Vec3s.init;
pub const vec4s = Vec4s.init;

pub const iVec2 = vec.Vec2(i32);
pub const iVec3 = vec.Vec3(i32);
pub const iVec4 = vec.Vec4(i32);
pub const ivec2 = iVec2.init;
pub const ivec3 = iVec3.init;
pub const ivec4 = iVec4.init;

pub const uVec2 = vec.Vec2(u32);
pub const uVec3 = vec.Vec3(u32);
pub const uVec4 = vec.Vec4(u32);
pub const uvec2 = uVec2.init;
pub const uvec3 = uVec3.init;
pub const uvec4 = uVec4.init;

pub const Vec2d = vec.Vec2(f64);
pub const Vec3d = vec.Vec3(f64);
pub const Vec4d = vec.Vec4(f64);
pub const vec2d = Vec2d.init;
pub const vec3d = Vec3d.init;
pub const vec4d = Vec4d.init;

const vec = @import("vec.zig");
