pub const Quad = extern struct {
    bottom_left: m.Vec2,
    top_right: m.Vec2,

    /// Default is a 1x1 quad anchored at the origin on the bottom left
    pub const default = Quad{
        .bottom_left = .zeros,
        .top_right = .ones,
    };
};

pub const Circle = extern struct {};

const m = @import("vec.zig");
