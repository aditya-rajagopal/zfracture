// TODO: Should these be distinct structs
pub const Vec4s = @Vector(4, f32);
pub const iVec4 = @Vector(4, u32);
pub const Colour = @Vector(4, f32);
pub const Rect = @Vector(4, u32);
pub const Quat = Vec4s;

pub const Extent = extern struct {
    width: u32,
    height: u32,
};
