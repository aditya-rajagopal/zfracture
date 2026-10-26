pub const AABB = struct {
    min_x: f32,
    min_y: f32,
    max_x: f32,
    max_y: f32,

    pub const empty: AABB = .{ .min_x = 0, .min_y = 0, .max_x = 0, .max_y = 0 };
};

pub const Circle = struct {
    centre_x: f32,
    centre_y: f32,
    radius: f32,
};
