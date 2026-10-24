const std = @import("std");
const AABB = @This();

min_x: f32,
min_y: f32,
max_x: f32,
max_y: f32,

pub const Axis = enum { x, y };

pub const Contact = struct {
    fraction: f32,
    /// Null for an initial overlap, where no entering surface exists.
    axis: ?Axis,
};

pub const empty = AABB{ .min_x = 0, .min_y = 0, .max_x = 0, .max_y = 0 };

pub fn sweptAABB(moving: AABB, target: AABB, movement_x: f32, movement_y: f32) ?Contact {
    const interval_x = sweepAxis(
        moving.min_x,
        moving.max_x,
        target.min_x,
        target.max_x,
        movement_x,
    ) orelse return null;
    const interval_y = sweepAxis(
        moving.min_y,
        moving.max_y,
        target.min_y,
        target.max_y,
        movement_y,
    ) orelse return null;

    const enter_unclamped = @max(interval_x.enter, interval_y.enter);
    const enter = @max(0.0, enter_unclamped);
    const exit = @min(1.0, interval_x.exit, interval_y.exit);
    // NOTE(adi): If exit is 0 (i.e enter is also 0), then the AABBs are touching but the movement
    // would not cause them to intersect. This is a valid result. prevents bodies getting stuck to
    // each other.
    if (exit <= 0) return null;
    if (enter > exit) return null;
    var axis: ?Axis = null;
    if (enter_unclamped >= 0) {
        // The later entry determines the blocking axis. Exact corner ties choose X.
        axis = if (interval_x.enter >= interval_y.enter) .x else .y;
    }
    return .{ .fraction = enter, .axis = axis };
}

const IntersectionInterval = struct {
    enter: f32,
    exit: f32,
};

fn sweepAxis(
    moving_min: f32,
    moving_max: f32,
    target_min: f32,
    target_max: f32,
    movement: f32,
) ?IntersectionInterval {
    if (movement == 0) {
        // NOTE(adi): target_min > moving_max indicates no point in this axis movement do these
        // AABBs intersect. the == case indicates that they are touching the whole axis. This is not
        // a valid collision.
        if (target_min >= moving_max) return null;
        if (target_max <= moving_min) return null;
        // An overlapping stationary axis cannot determine the entering surface.
        return .{ .enter = -std.math.inf(f32), .exit = std.math.inf(f32) };
    }

    const first = (target_min - moving_max) / movement;
    const second = (target_max - moving_min) / movement;

    return .{ .enter = @min(first, second), .exit = @max(first, second) };
}
