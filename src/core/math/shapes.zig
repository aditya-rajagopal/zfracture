pub const Rectangle = extern struct {
    pos: m.Vec2,
    size: m.Vec2,
};

const m = @import("math.zig");
