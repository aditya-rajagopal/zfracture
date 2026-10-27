const std = @import("std");

const shapes = @import("shapes.zig");
const AABB = shapes.AABB;
const Circle = shapes.Circle;

pub fn overlapCircleCircle(a: Circle, b: Circle) bool {
    const dx = a.centre_x - b.centre_x;
    const dy = a.centre_y - b.centre_y;
    const total_radius = a.radius + b.radius;
    const distance_squared = dx * dx + dy * dy;
    return distance_squared <= total_radius * total_radius;
}

test overlapCircleCircle {
    const cases = [_]struct { a: Circle, b: Circle, expected: bool }{
        // Touching counts as overlap
        .{
            .a = .{ .centre_x = -4, .centre_y = -6, .radius = 2 },
            .b = .{ .centre_x = -1, .centre_y = -2, .radius = 3 },
            .expected = true,
        },
        // Separated circles do not overlap
        .{
            .a = .{ .centre_x = -4, .centre_y = -6, .radius = 2 },
            .b = .{ .centre_x = -1, .centre_y = -1.75, .radius = 3 },
            .expected = false,
        },
        // Partial overlap counts as overlap
        .{
            .a = .{ .centre_x = 0, .centre_y = 0, .radius = 2 },
            .b = .{ .centre_x = 3, .centre_y = 0, .radius = 3 },
            .expected = true,
        },
        // Circles with the same centre overlap
        .{
            .a = .{ .centre_x = 0, .centre_y = 0, .radius = 0.25 },
            .b = .{ .centre_x = 0, .centre_y = 0, .radius = 2 },
            .expected = true,
        },
    };
    for (cases, 0..) |case, index| {
        errdefer std.debug.print("case {d}: {any}\n", .{ index + 1, case });
        try std.testing.expectEqual(case.expected, overlapCircleCircle(case.a, case.b));
        try std.testing.expectEqual(case.expected, overlapCircleCircle(case.b, case.a));
    }
}

pub fn overlapCircleAABB(a: Circle, b: AABB) bool {
    const px = std.math.clamp(a.centre_x, b.min_x, b.max_x);
    const py = std.math.clamp(a.centre_y, b.min_y, b.max_y);
    const dx = px - a.centre_x;
    const dy = py - a.centre_y;
    const distance_squared = dx * dx + dy * dy;
    return distance_squared <= a.radius * a.radius;
}

test overlapCircleAABB {
    const cases = [_]struct { a: Circle, b: AABB, expected: bool }{
        // A circle inside the box overlaps
        .{
            .a = .{ .centre_x = 0.5, .centre_y = 1.5, .radius = 0.25 },
            .b = .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 4 },
            .expected = true,
        },
        // Touching an edge counts as overlap
        .{
            .a = .{ .centre_x = -1, .centre_y = 2, .radius = 1 },
            .b = .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 4 },
            .expected = true,
        },
        // A circle outside the edge does not overlap
        .{
            .a = .{ .centre_x = 1, .centre_y = 5.25, .radius = 1 },
            .b = .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 4 },
            .expected = false,
        },
        // Touching a corner counts as overlap
        .{
            .a = .{ .centre_x = 5, .centre_y = 8, .radius = 5 },
            .b = .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 4 },
            .expected = true,
        },
        // A circle that misses the corner does not overlap
        .{
            .a = .{ .centre_x = 3, .centre_y = -1, .radius = 1.25 },
            .b = .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 4 },
            .expected = false,
        },
    };
    for (cases, 0..) |case, index| {
        errdefer std.debug.print("case {d}: {any}\n", .{ index + 1, case });
        try std.testing.expectEqual(case.expected, overlapCircleAABB(case.a, case.b));
    }
}

pub fn overlapAABBAABB(a: AABB, b: AABB) bool {
    const d0 = b.max_x < a.min_x;
    const d1 = a.max_x < b.min_x;
    const d2 = b.max_y < a.min_y;
    const d3 = a.max_y < b.min_y;
    return !(d0 or d1 or d2 or d3);
}

test overlapAABBAABB {
    const cases = [_]struct { a: AABB, b: AABB, expected: bool }{
        // Boxes separated on X do not overlap
        .{
            .a = .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 },
            .b = .{ .min_x = 2, .min_y = 0, .max_x = 3, .max_y = 1 },
            .expected = false,
        },
        // Boxes separated on Y do not overlap
        .{
            .a = .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 },
            .b = .{ .min_x = 0, .min_y = 2, .max_x = 1, .max_y = 3 },
            .expected = false,
        },
        // Touching an edge counts as overlap
        .{
            .a = .{ .min_x = -2, .min_y = -1, .max_x = -1, .max_y = 1 },
            .b = .{ .min_x = -1, .min_y = -0.5, .max_x = 1, .max_y = 0.5 },
            .expected = true,
        },
        // Touching a corner counts as overlap
        .{
            .a = .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 },
            .b = .{ .min_x = 1, .min_y = 1, .max_x = 2, .max_y = 2 },
            .expected = true,
        },
        // Crossing boxes overlap
        .{
            .a = .{ .min_x = -2, .min_y = -0.5, .max_x = 2, .max_y = 0.5 },
            .b = .{ .min_x = -0.5, .min_y = -2, .max_x = 0.5, .max_y = 2 },
            .expected = true,
        },
        // One box inside another counts as overlap
        .{
            .a = .{ .min_x = 1, .min_y = 1, .max_x = 2, .max_y = 2 },
            .b = .{ .min_x = 0, .min_y = 0, .max_x = 4, .max_y = 4 },
            .expected = true,
        },
    };
    for (cases, 0..) |case, index| {
        errdefer std.debug.print("case {d}: {any}\n", .{ index + 1, case });
        try std.testing.expectEqual(case.expected, overlapAABBAABB(case.a, case.b));
        try std.testing.expectEqual(case.expected, overlapAABBAABB(case.b, case.a));
    }
}

pub const Contact = struct {
    fraction: f32,
    /// Unit normal from the target toward the moving shape, when defined.
    normal: ?struct { x: f32, y: f32 },
    kind: Kind,

    pub const empty = Contact{ .fraction = 0, .normal = null, .kind = .overlapping };

    pub const Kind = enum {
        /// Movement crosses into the target at this contact.
        entering,
        /// The shapes touch without entering, including stationary touching.
        grazing,
        /// The shapes strictly overlap at the start, regardless of movement.
        overlapping,
    };
};

/// NOTE(adi): if the centers are M and T, with radii r1 and r2 andthe relative velocity is \delta.
/// Then at some time t the center of the moving circle is M + \delta * t.
/// We enlarge the stationary circly to be of radius r1 + r2 and find the intersection points of the line segment
/// form M to M + \delta and the new circle.
/// || M + \delta * t - T || = r1 + r2. Solve for t.
/// => (M + \delta * t - T) . (M + \delta * t - T) = R^2 where R = r1 + r2
/// => \delta.\delta * t^2 + 2 * \delta.Ct + C.C = R^2 where C = M - T
/// This is of the form a * t^2 + b * t + c = 0.
///
/// However there are precision issues with doing it this way.
/// When C.C >> R^2 the value of c = C.C - R^2 is approximately C.C
/// Take the example of:
/// Moving circle: centre (0, 0), radius 0.001.
/// Target circle: centre (100, 0), radius 0.001.
/// Movement: (200, 0).
///
/// a = movement · movement = 200²          = 40,000
/// b = 2 × (offset · movement) = 2×(-100)×200 = -40,000
/// c = 10,000 − 0.000004  → rounds to 10,000 because f32 cannot distinguish between 9999.999996 and 10000.
/// This means discriminant = b² - 4a c = 40,000² - 4× 40,000 * 10,000 = 0
/// if we  had exact arithemtic we should have discriminant = 0.64
///
/// This causes us to get NaN for the normal vector.
///
/// Instead we can try to find the closest apprach to the target circle. This still has some issues if you have large
/// movements of very small radii but that is just a limitation I am willing to accept.
pub fn sweepCircleCircle(moving: Circle, target: Circle, movement_x: f32, movement_y: f32) ?Contact {
    const origin_offset_x = moving.centre_x - target.centre_x;
    const origin_offset_y = moving.centre_y - target.centre_y;
    const total_radius = moving.radius + target.radius;
    const total_radius_squared = total_radius * total_radius;
    const distance_squared = origin_offset_x * origin_offset_x + origin_offset_y * origin_offset_y;
    if (distance_squared < total_radius_squared) {
        // The circles are already overlapping.
        if (distance_squared == 0) {
            return .{ .fraction = 0, .normal = null, .kind = .overlapping };
        }
        return .{ .fraction = 0, .normal = .{
            .x = origin_offset_x / @sqrt(distance_squared),
            .y = origin_offset_y / @sqrt(distance_squared),
        }, .kind = .overlapping };
    }

    if (distance_squared == total_radius_squared) {
        const dot = origin_offset_x * movement_x + origin_offset_y * movement_y;
        if (dot > 0) {
            // The touching circles are moving apart.
            return null;
        }
        const inv_length = 1.0 / @sqrt(distance_squared);
        return .{ .fraction = 0, .normal = .{
            .x = origin_offset_x * inv_length,
            .y = origin_offset_y * inv_length,
        }, .kind = if (dot == 0) .grazing else .entering };
    }

    return sweepRayCircleInner(origin_offset_x, origin_offset_y, total_radius_squared, movement_x, movement_y);
}

fn sweepRayCircleInner(
    /// Ray origin minus circle centre in x; the origin must start outside the circle.
    origin_offset_x: f32,
    /// Ray origin minus circle centre in y.
    origin_offset_y: f32,
    radius_squared: f32,
    movement_x: f32,
    movement_y: f32,
) ?Contact {
    const dot = origin_offset_x * movement_x + origin_offset_y * movement_y;
    if (dot >= 0) {
        // The circles are moving away from each other, are stationary or  moving tangentially.
        return null;
    }

    const a = movement_x * movement_x + movement_y * movement_y;
    // NOTE(adi): Geometrically what we want is to find the point where the ray that is the movement of the moving circle
    // is closest to the center of the target circle. Given the offset C = M - T and movement \delta, the closest
    // approach occurs at t_closest = -(C . \delta) / |\delta|^2 = -dot / a, with perpendicular offset
    // P = C + t_closest * \delta.
    //
    // Dividing by a = |\delta|^2 up front introduces rounding when a has non-power-of-two factors (e.g. 7 or 9).
    // Scaling P by a keeps the closest-approach check division-free:
    //   a * P = (C_x * \delta_y - C_y * \delta_x) * (\delta_y, -\delta_x) = cross * (\delta_y, -\delta_x)
    //   a * |P|^2 = cross^2
    // So the closest approach is inside the enlarged target circle (|P|^2 <= R^2) iff a * R^2 - cross^2 >= 0.
    const cross = origin_offset_x * movement_y - origin_offset_y * movement_x;
    const discriminant_quarter = a * radius_squared - cross * cross;
    if (discriminant_quarter < 0) {
        // The circles will never intersect.
        return null;
    }

    // NOTE(adi): If the closest approach is inside the target circle, there are two symmetric intersection points
    // along the line of the movement vector. By Pythagoras, the half-chord distance back from closest approach is
    // \sqrt(R^2 - |P|^2), and its movement fraction is back_step = \sqrt((R^2 - |P|^2) / a).
    //
    // Scaling by a gives a * back_step = \sqrt(a * R^2 - cross^2), which lets us combine t_closest - back_step
    // over the common denominator a so a single division happens at the end. Likewise, we compute the contact
    // normal scaled by a:
    //   a * N = a * P - (a * back_step) * \delta
    // since the positive scale factor a cancels out during normalization.
    const back_step_scaled = @sqrt(discriminant_quarter);
    const enter = @max(0, (-dot - back_step_scaled) / a);
    if (enter > 1) return null;

    const normal_x = cross * movement_y - back_step_scaled * movement_x;
    const normal_y = -cross * movement_x - back_step_scaled * movement_y;
    const inv_length = 1.0 / @sqrt(normal_x * normal_x + normal_y * normal_y);

    return .{
        .fraction = enter,
        .normal = .{ .x = normal_x * inv_length, .y = normal_y * inv_length },
        .kind = if (discriminant_quarter == 0) .grazing else .entering,
    };
}

test sweepCircleCircle {
    const cases = [_]struct {
        moving: Circle,
        target: Circle,
        movement_x: f32,
        movement_y: f32,
        expected: ?Contact,
    }{
        // Ending up inside the targt circle has an entry fraction
        .{
            .moving = .{ .centre_x = -9, .centre_y = -12, .radius = 0.5 },
            .target = .{ .centre_x = 0, .centre_y = 0, .radius = 4.5 },
            .movement_x = 7.5,
            .movement_y = 10,
            .expected = .{ .kind = .entering, .fraction = 0.8, .normal = .{ .x = -0.6, .y = -0.8 } },
        },
        // Horizontal movement can produce a diagonal contact normal
        .{
            .moving = .{ .centre_x = 5, .centre_y = 1.2, .radius = 1.5 },
            .target = .{ .centre_x = 0, .centre_y = 0, .radius = 0.5 },
            .movement_x = -10,
            .movement_y = 0,
            .expected = .{ .kind = .entering, .fraction = 0.34, .normal = .{ .x = 0.8, .y = 0.6 } },
        },
        // Touching circles moving inward hit at t = 0
        .{
            .moving = .{ .centre_x = 0, .centre_y = 0, .radius = 2 },
            .target = .{ .centre_x = 3, .centre_y = 4, .radius = 3 },
            .movement_x = 3,
            .movement_y = 4,
            .expected = .{ .kind = .entering, .fraction = 0, .normal = .{ .x = -0.6, .y = -0.8 } },
        },
        // Touching circles moving apart do not hit
        .{
            .moving = .{ .centre_x = 0, .centre_y = 0, .radius = 1 },
            .target = .{ .centre_x = 2, .centre_y = 0, .radius = 1 },
            .movement_x = -1,
            .movement_y = 0,
            .expected = null,
        },
        // Touching circles moving tangentially are grazing
        .{
            .moving = .{ .centre_x = 0, .centre_y = 0, .radius = 1 },
            .target = .{ .centre_x = 2, .centre_y = 0, .radius = 1 },
            .movement_x = 0,
            .movement_y = 1,
            .expected = .{ .kind = .grazing, .fraction = 0, .normal = .{ .x = -1, .y = 0 } },
        },
        // Overlapping circles moving apart still hit at t = 0
        .{
            .moving = .{ .centre_x = 0, .centre_y = 0, .radius = 1 },
            .target = .{ .centre_x = 0.3, .centre_y = 0.4, .radius = 1 },
            .movement_x = -1,
            .movement_y = -1,
            .expected = .{ .kind = .overlapping, .fraction = 0, .normal = .{ .x = -0.6, .y = -0.8 } },
        },
        // Overlapping stationary circles hit at t = 0
        .{
            .moving = .{ .centre_x = 0, .centre_y = 0, .radius = 0.25 },
            .target = .{ .centre_x = 1, .centre_y = 0, .radius = 2 },
            .movement_x = 0,
            .movement_y = 0,
            .expected = .{ .kind = .overlapping, .fraction = 0, .normal = .{ .x = -1, .y = 0 } },
        },
        // Identical centres return no normal
        .{
            .moving = .{ .centre_x = 0, .centre_y = 0, .radius = 1 },
            .target = .{ .centre_x = 0, .centre_y = 0, .radius = 1 },
            .movement_x = 1,
            .movement_y = 0,
            .expected = .{ .kind = .overlapping, .fraction = 0, .normal = null },
        },
        // Stationary separated circles do not hit
        .{
            .moving = .{ .centre_x = 0, .centre_y = 0, .radius = 1 },
            .target = .{ .centre_x = 5, .centre_y = 0, .radius = 1 },
            .movement_x = 0,
            .movement_y = 0,
            .expected = null,
        },
        // Tangent contact at t = 1 counts as a hit
        .{
            .moving = .{ .centre_x = 0, .centre_y = 0, .radius = 1 },
            .target = .{ .centre_x = 3, .centre_y = 2, .radius = 1 },
            .movement_x = 3,
            .movement_y = 0,
            .expected = .{ .kind = .grazing, .fraction = 1, .normal = .{ .x = 0, .y = -1 } },
        },
        // Tangency at t = 1/7 must not be missed when the closest-point projection rounds outward.
        .{
            .moving = .{ .centre_x = -9, .centre_y = 13, .radius = 2 },
            .target = .{ .centre_x = 0, .centre_y = 0, .radius = 3 },
            .movement_x = 84,
            .movement_y = -63,
            .expected = .{ .kind = .grazing, .fraction = 1.0 / 7.0, .normal = .{ .x = 0.6, .y = 0.8 } },
        },
        // Tangency at t = 1/7 must not become entering when the projection rounds inward.
        .{
            .moving = .{ .centre_x = -1, .centre_y = 7, .radius = 2 },
            .target = .{ .centre_x = 0, .centre_y = 0, .radius = 3 },
            .movement_x = 28,
            .movement_y = -21,
            .expected = .{ .kind = .grazing, .fraction = 1.0 / 7.0, .normal = .{ .x = 0.6, .y = 0.8 } },
        },
        // Widening the old projection to f64 still rounds this t = 9/14 tangent inward.
        .{
            .moving = .{ .centre_x = -33, .centre_y = 31, .radius = 2 },
            .target = .{ .centre_x = 0, .centre_y = 0, .radius = 3 },
            .movement_x = 56,
            .movement_y = -42,
            .expected = .{ .kind = .grazing, .fraction = 9.0 / 14.0, .normal = .{ .x = 0.6, .y = 0.8 } },
        },
        // Widening the old projection to f64 still rounds this t = 15/26 tangent outward.
        .{
            .moving = .{ .centre_x = -57, .centre_y = 49, .radius = 2 },
            .target = .{ .centre_x = 0, .centre_y = 0, .radius = 3 },
            .movement_x = 104,
            .movement_y = -78,
            .expected = .{ .kind = .grazing, .fraction = 15.0 / 26.0, .normal = .{ .x = 0.6, .y = 0.8 } },
        },
        // The same tangent path misses when the combined radius is reduced from 5 to 4.875.
        .{
            .moving = .{ .centre_x = -9, .centre_y = 13, .radius = 2 },
            .target = .{ .centre_x = 0, .centre_y = 0, .radius = 2.875 },
            .movement_x = 84,
            .movement_y = -63,
            .expected = null,
        },
        // Contact at t = 1 counts as a hit
        .{
            .moving = .{ .centre_x = 0, .centre_y = 0, .radius = 1 },
            .target = .{ .centre_x = 5, .centre_y = 0, .radius = 1 },
            .movement_x = 3,
            .movement_y = 0,
            .expected = .{ .kind = .entering, .fraction = 1, .normal = .{ .x = -1, .y = 0 } },
        },
        // Separate quotients rounded this endpoint beyond t = 1 in f32: 24/9 - 15/9.
        .{
            .moving = .{ .centre_x = 0, .centre_y = 0, .radius = 2 },
            .target = .{ .centre_x = 8, .centre_y = 0, .radius = 3 },
            .movement_x = 3,
            .movement_y = 0,
            .expected = .{ .kind = .entering, .fraction = 1, .normal = .{ .x = -1, .y = 0 } },
        },
        // Separate quotients can also reject an exact endpoint in f64: 21/9 - 12/9.
        .{
            .moving = .{ .centre_x = 0, .centre_y = 0, .radius = 2 },
            .target = .{ .centre_x = 7, .centre_y = 0, .radius = 2 },
            .movement_x = 3,
            .movement_y = 0,
            .expected = .{ .kind = .entering, .fraction = 1, .normal = .{ .x = -1, .y = 0 } },
        },
        // Contact after t = 1 does not count as a hit
        .{
            .moving = .{ .centre_x = 0, .centre_y = 0, .radius = 1 },
            .target = .{ .centre_x = 5, .centre_y = 0, .radius = 1 },
            .movement_x = 2.5,
            .movement_y = 0,
            .expected = null,
        },
        // Long sweeps against small circles return a finite normal. This would have caused a NaN if
        // using the naive quadratic formula
        .{
            .moving = .{ .centre_x = 0, .centre_y = 0, .radius = 0.001 },
            .target = .{ .centre_x = 100, .centre_y = 0, .radius = 0.001 },
            .movement_x = 200,
            .movement_y = 0,
            .expected = .{ .kind = .entering, .fraction = 0.49999, .normal = .{ .x = -1, .y = 0 } },
        },
        // Near-misses do not count as hits. This would have caused a hit if using the naive quadratic formula
        .{
            .moving = .{ .centre_x = 0, .centre_y = 0, .radius = 0.125 },
            .target = .{ .centre_x = 100, .centre_y = 0.2505, .radius = 0.125 },
            .movement_x = 200,
            .movement_y = 0,
            .expected = null,
        },
        // Long diagonal sweeps return an accurate normal. Would have given us the wrong normal if using the naive
        // quadratic formula
        .{
            .moving = .{ .centre_x = 0, .centre_y = 0, .radius = 0.0015 },
            .target = .{ .centre_x = 60, .centre_y = 80, .radius = 0.0015 },
            .movement_x = 120,
            .movement_y = 160,
            .expected = .{ .kind = .entering, .fraction = 0.499985, .normal = .{ .x = -0.6, .y = -0.8 } },
        },
    };
    for (cases, 0..) |case, index| {
        errdefer std.debug.print("case {d}: {any}\n", .{ index + 1, case });
        const actual = sweepCircleCircle(case.moving, case.target, case.movement_x, case.movement_y);
        try expectContact(case.expected, actual);
    }
}

pub fn sweepAABBAABB(moving: AABB, target: AABB, movement_x: f32, movement_y: f32) ?Contact {
    const interval_x = sweepAxis(
        moving.min_x,
        moving.max_x,
        target.min_x,
        target.max_x,
        movement_x,
    ) orelse return null;
    if (interval_x.exit < 0 or interval_x.enter > 1) return null;

    const interval_y = sweepAxis(
        moving.min_y,
        moving.max_y,
        target.min_y,
        target.max_y,
        movement_y,
    ) orelse return null;

    const enter_unclamped = @max(interval_x.enter, interval_y.enter);
    const exit_unclamped = @min(interval_x.exit, interval_y.exit);
    if (exit_unclamped < 0 or enter_unclamped > 1) return null;
    if (enter_unclamped > exit_unclamped) return null;
    // A touch that is only exiting at t = 0 is moving apart.
    if (exit_unclamped == 0 and enter_unclamped < 0) return null;

    const enter = @max(0.0, enter_unclamped);
    // A stationary axis on a boundary prevents interior overlap even if the
    // other axis has a positive overlap interval. Its face supplies the normal.
    const sliding_x = movement_x == 0 and (moving.max_x == target.min_x or moving.min_x == target.max_x);
    if (sliding_x) {
        return .{
            .fraction = enter,
            .normal = .{ .x = if (moving.max_x == target.min_x) -1 else 1, .y = 0 },
            .kind = .grazing,
        };
    }
    const sliding_y = movement_y == 0 and (moving.max_y == target.min_y or moving.min_y == target.max_y);
    if (sliding_y) {
        return .{
            .fraction = enter,
            .normal = .{ .x = 0, .y = if (moving.max_y == target.min_y) -1 else 1 },
            .kind = .grazing,
        };
    }

    if (enter_unclamped >= 0) {
        // Compare raw times so entering at t = 1 is not mistaken for grazing.
        const kind: Contact.Kind = if (enter_unclamped == exit_unclamped) .grazing else .entering;
        // The later entry determines the face normal. Exact corner ties choose X.
        if (interval_x.enter >= interval_y.enter) {
            return .{ .fraction = enter, .normal = .{ .x = if (movement_x > 0) -1 else 1, .y = 0 }, .kind = kind };
        } else {
            return .{ .fraction = enter, .normal = .{ .x = 0, .y = if (movement_y > 0) -1 else 1 }, .kind = kind };
        }
    }
    return .{ .fraction = enter, .normal = null, .kind = .overlapping };
}

fn sweepAxis(
    moving_min: f32,
    moving_max: f32,
    target_min: f32,
    target_max: f32,
    movement: f32,
) ?struct { enter: f32, exit: f32 } {
    if (movement == 0) {
        // Keep boundary touching so the caller can report grazing contacts.
        if (target_min > moving_max) return null;
        if (target_max < moving_min) return null;
        // An overlapping stationary axis cannot determine the entering surface.
        return .{ .enter = -std.math.inf(f32), .exit = std.math.inf(f32) };
    }

    const first = (target_min - moving_max) / movement;
    const second = (target_max - moving_min) / movement;

    return .{ .enter = @min(first, second), .exit = @max(first, second) };
}

test sweepAABBAABB {
    const cases = [_]struct {
        moving: AABB,
        target: AABB,
        movement_x: f32,
        movement_y: f32,
        expected: ?Contact,
    }{
        // Moving right hits a thin wall
        .{
            .moving = .{ .min_x = 0, .min_y = 0, .max_x = 0.5, .max_y = 2 },
            .target = .{ .min_x = 2, .min_y = 0, .max_x = 2.125, .max_y = 3 },
            .movement_x = 3,
            .movement_y = 0,
            .expected = .{ .kind = .entering, .fraction = 0.5, .normal = .{ .x = -1, .y = 0 } },
        },
        // Moving left returns a right-facing normal
        .{
            .moving = .{ .min_x = 4, .min_y = 4, .max_x = 5, .max_y = 5 },
            .target = .{ .min_x = 2, .min_y = 2, .max_x = 3, .max_y = 3 },
            .movement_x = -2,
            .movement_y = -4,
            .expected = .{ .kind = .entering, .fraction = 0.5, .normal = .{ .x = 1, .y = 0 } },
        },
        // Entering on Y last returns a Y normal
        .{
            .moving = .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 },
            .target = .{ .min_x = 2, .min_y = 2, .max_x = 3, .max_y = 3 },
            .movement_x = 4,
            .movement_y = 2,
            .expected = .{ .kind = .entering, .fraction = 0.5, .normal = .{ .x = 0, .y = -1 } },
        },
        // Moving in negative Y returns a positive Y normal
        .{
            .moving = .{ .min_x = 0, .min_y = 4, .max_x = 1, .max_y = 5 },
            .target = .{ .min_x = 0, .min_y = 2, .max_x = 1, .max_y = 3 },
            .movement_x = 0,
            .movement_y = -2,
            .expected = .{ .kind = .entering, .fraction = 0.5, .normal = .{ .x = 0, .y = 1 } },
        },
        // Separated on X with no X movement means no hit
        .{
            .moving = .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 },
            .target = .{ .min_x = 2, .min_y = 2, .max_x = 3, .max_y = 3 },
            .movement_x = 0,
            .movement_y = 10,
            .expected = null,
        },
        // Separated on Y with no Y movement means no hit
        .{
            .moving = .{ .min_x = 0, .min_y = 4, .max_x = 1, .max_y = 5 },
            .target = .{ .min_x = 0, .min_y = 2, .max_x = 1, .max_y = 3 },
            .movement_x = 1,
            .movement_y = 0,
            .expected = null,
        },
        // Sliding along a vertical edge is grazing
        .{
            .moving = .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 },
            .target = .{ .min_x = 1, .min_y = 0, .max_x = 2, .max_y = 1 },
            .movement_x = 0,
            .movement_y = 1,
            .expected = .{ .kind = .grazing, .fraction = 0, .normal = .{ .x = -1, .y = 0 } },
        },
        // Reaching a horizontal edge while sliding is grazing
        .{
            .moving = .{ .min_x = 0, .min_y = 2, .max_x = 1, .max_y = 3 },
            .target = .{ .min_x = 2, .min_y = 1, .max_x = 3, .max_y = 2 },
            .movement_x = 10,
            .movement_y = 0,
            .expected = .{ .kind = .grazing, .fraction = 0.1, .normal = .{ .x = 0, .y = 1 } },
        },
        // Overlapping stationary boxes hit at t = 0 with no normal
        .{
            .moving = .{ .min_x = 1, .min_y = 1, .max_x = 2, .max_y = 2 },
            .target = .{ .min_x = 0, .min_y = 0, .max_x = 4, .max_y = 4 },
            .movement_x = 0,
            .movement_y = 0,
            .expected = .{ .kind = .overlapping, .fraction = 0, .normal = null },
        },
        // Overlapping boxes moving apart hit at t = 0 with no normal
        .{
            .moving = .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 },
            .target = .{ .min_x = 0.5, .min_y = 0.5, .max_x = 1.5, .max_y = 1.5 },
            .movement_x = -2,
            .movement_y = -1,
            .expected = .{ .kind = .overlapping, .fraction = 0, .normal = null },
        },
        // Touching boxes moving inward hit at t = 0
        .{
            .moving = .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 },
            .target = .{ .min_x = 1, .min_y = 0, .max_x = 2, .max_y = 1 },
            .movement_x = 1,
            .movement_y = 0,
            .expected = .{ .kind = .entering, .fraction = 0, .normal = .{ .x = -1, .y = 0 } },
        },
        // Crossing past a touching corner is grazing
        .{
            .moving = .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 },
            .target = .{ .min_x = 1, .min_y = 1, .max_x = 2, .max_y = 2 },
            .movement_x = 1,
            .movement_y = -1,
            .expected = .{ .kind = .grazing, .fraction = 0, .normal = .{ .x = -1, .y = 0 } },
        },
        // Corner grazes count as hits
        .{
            .moving = .{ .min_x = 0, .min_y = 1.5, .max_x = 1, .max_y = 2.5 },
            .target = .{ .min_x = 2, .min_y = 2, .max_x = 3, .max_y = 3 },
            .movement_x = 2,
            .movement_y = -1,
            .expected = .{ .kind = .grazing, .fraction = 0.5, .normal = .{ .x = -1, .y = 0 } },
        },
        // Corner grazes at t = 1 count as hits
        .{
            .moving = .{ .min_x = 0, .min_y = 1.5, .max_x = 1, .max_y = 2.5 },
            .target = .{ .min_x = 2, .min_y = 2, .max_x = 3, .max_y = 3 },
            .movement_x = 1,
            .movement_y = -0.5,
            .expected = .{ .kind = .grazing, .fraction = 1, .normal = .{ .x = -1, .y = 0 } },
        },
        // Entering a face at t = 1 counts as a hit
        .{
            .moving = .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 },
            .target = .{ .min_x = 2, .min_y = 0, .max_x = 3, .max_y = 1 },
            .movement_x = 1,
            .movement_y = 0,
            .expected = .{ .kind = .entering, .fraction = 1, .normal = .{ .x = -1, .y = 0 } },
        },
        // Entering a corner at t = 1 chooses the X normal
        .{
            .moving = .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 },
            .target = .{ .min_x = 2, .min_y = 2, .max_x = 3, .max_y = 3 },
            .movement_x = 1,
            .movement_y = 1,
            .expected = .{ .kind = .entering, .fraction = 1, .normal = .{ .x = -1, .y = 0 } },
        },
        // X contact after t = 1 does not count as a hit
        .{
            .moving = .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 },
            .target = .{ .min_x = 2, .min_y = 0, .max_x = 3, .max_y = 1 },
            .movement_x = 0.5,
            .movement_y = 0,
            .expected = null,
        },
        // Y contact after t = 1 does not count as a hit
        .{
            .moving = .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 },
            .target = .{ .min_x = 0, .min_y = 2, .max_x = 1, .max_y = 3 },
            .movement_x = 0,
            .movement_y = 0.5,
            .expected = null,
        },
        // Both axes must overlap at the same time
        .{
            .moving = .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 },
            .target = .{ .min_x = 2, .min_y = 2, .max_x = 3, .max_y = 3 },
            .movement_x = 10,
            .movement_y = 1,
            .expected = null,
        },
        // Touching boxes moving apart do not hit
        .{
            .moving = .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 },
            .target = .{ .min_x = 1, .min_y = 0, .max_x = 2, .max_y = 1 },
            .movement_x = -1,
            .movement_y = 0,
            .expected = null,
        },
        // Stationary corner touching is grazing and chooses the X normal
        .{
            .moving = .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 },
            .target = .{ .min_x = 1, .min_y = 1, .max_x = 2, .max_y = 2 },
            .movement_x = 0,
            .movement_y = 0,
            .expected = .{ .kind = .grazing, .fraction = 0, .normal = .{ .x = -1, .y = 0 } },
        },
    };
    for (cases, 0..) |case, index| {
        errdefer std.debug.print("case {d}: {any}\n", .{ index + 1, case });
        const actual = sweepAABBAABB(case.moving, case.target, case.movement_x, case.movement_y);
        try expectContact(case.expected, actual);
    }
}

pub fn sweepCircleAABB(moving: Circle, target: AABB, movement_x: f32, movement_y: f32) ?Contact {
    const closest_x = std.math.clamp(moving.centre_x, target.min_x, target.max_x);
    const closest_y = std.math.clamp(moving.centre_y, target.min_y, target.max_y);
    const dx = moving.centre_x - closest_x;
    const dy = moving.centre_y - closest_y;
    const distance_squared = dx * dx + dy * dy;
    const radius_squared = moving.radius * moving.radius;

    if (distance_squared < radius_squared) {
        // The circle already overlaps the AABB.
        if (distance_squared == 0) {
            return .{ .fraction = 0, .normal = null, .kind = .overlapping };
        }
        const inv_length = 1.0 / @sqrt(distance_squared);
        return .{ .fraction = 0, .normal = .{ .x = dx * inv_length, .y = dy * inv_length }, .kind = .overlapping };
    }

    const dot = dx * movement_x + dy * movement_y;
    if (distance_squared == radius_squared) {
        if (dot > 0) return null;
        const inv_length = 1.0 / @sqrt(distance_squared);
        return .{
            .fraction = 0,
            .normal = .{ .x = dx * inv_length, .y = dy * inv_length },
            .kind = if (dot == 0) .grazing else .entering,
        };
    }
    // Separated shapes that are not approaching cannot make contact.
    if (dot >= 0) return null;

    // NOTE(adi): We can first assume the circle is replaced by an AABB which it inscribes. And check for
    // intersection with the AABB. If these two do not interset then we already know the circle is never going
    // to intersect the AABB. If they do intersect then we can test if it is the sides or the rounded corners
    // of the minkowski sum.
    const point_box: AABB = .{
        .min_x = moving.centre_x,
        .min_y = moving.centre_y,
        .max_x = moving.centre_x,
        .max_y = moving.centre_y,
    };
    const expanded_target: AABB = .{
        .min_x = target.min_x - moving.radius,
        .min_y = target.min_y - moving.radius,
        .max_x = target.max_x + moving.radius,
        .max_y = target.max_y + moving.radius,
    };
    const contact = sweepAABBAABB(point_box, expanded_target, movement_x, movement_y) orelse return null;

    const hit_x = moving.centre_x + contact.fraction * movement_x;
    const hit_y = moving.centre_y + contact.fraction * movement_y;

    const horizontal_hit = hit_x >= target.min_x and hit_x <= target.max_x;
    const vertical_hit = hit_y >= target.min_y and hit_y <= target.max_y;

    if (horizontal_hit or vertical_hit) {
        // The candidate lies on a straight section of the expanded boundary.
        return contact;
    }

    // NOTE(adi): If we get here it means the intersection happens in one of the corners of the AABB.
    // which are quarter-circles. We can then use the sweepRayCircleInner to find the intersection.
    const corner_centre_x = if (hit_x < target.min_x) target.min_x else target.max_x;
    const corner_centre_y = if (hit_y < target.min_y) target.min_y else target.max_y;
    return sweepRayCircleInner(
        moving.centre_x - corner_centre_x,
        moving.centre_y - corner_centre_y,
        radius_squared,
        movement_x,
        movement_y,
    );
}

test sweepCircleAABB {
    const cases = [_]struct {
        moving: Circle,
        target: AABB,
        movement_x: f32,
        movement_y: f32,
        expected: ?Contact,
    }{
        // Entering a face at t = 1 counts as a hit
        .{
            .moving = .{ .centre_x = -2, .centre_y = 1, .radius = 1 },
            .target = .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 2 },
            .movement_x = 1,
            .movement_y = 0,
            .expected = .{ .kind = .entering, .fraction = 1, .normal = .{ .x = -1, .y = 0 } },
        },
        // Entering a rounded corner returns a diagonal normal
        .{
            .moving = .{ .centre_x = 5, .centre_y = -4, .radius = 1 },
            .target = .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 2 },
            .movement_x = -3,
            .movement_y = 4,
            .expected = .{ .kind = .entering, .fraction = 0.8, .normal = .{ .x = 0.6, .y = -0.8 } },
        },
        // Starting in an expanded-box corner gap is not initial overlap
        .{
            .moving = .{ .centre_x = -0.75, .centre_y = 2.75, .radius = 1 },
            .target = .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 2 },
            .movement_x = 0.75,
            .movement_y = -0.75,
            .expected = .{ .kind = .entering, .fraction = 0.05719096, .normal = .{ .x = -0.70710677, .y = 0.70710677 } },
        },
        // Reaching the expanded box without reaching the rounded corner is a miss
        .{
            .moving = .{ .centre_x = -2, .centre_y = -2, .radius = 1 },
            .target = .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 2 },
            .movement_x = 1.25,
            .movement_y = 1.25,
            .expected = null,
        },
        // Reaching a face while moving parallel to it is grazing
        .{
            .moving = .{ .centre_x = -2, .centre_y = -1, .radius = 1 },
            .target = .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 2 },
            .movement_x = 3,
            .movement_y = 0,
            .expected = .{ .kind = .grazing, .fraction = 0.6666667, .normal = .{ .x = 0, .y = -1 } },
        },
        // Touching a rounded corner tangentially is grazing
        .{
            .moving = .{ .centre_x = -3.5, .centre_y = -0.5, .radius = 2.5 },
            .target = .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 2 },
            .movement_x = 4,
            .movement_y = -3,
            .expected = .{ .kind = .grazing, .fraction = 0.5, .normal = .{ .x = -0.6, .y = -0.8 } },
        },
        // Rounded-corner tangency at t = 1/7. This is a regression test against f32 rounding issues that
        // was fixed with a reformulation of how the sweptRayCircleInner computes the contact time.
        .{
            .moving = .{ .centre_x = -9, .centre_y = 13, .radius = 5 },
            .target = .{ .min_x = -2, .min_y = -2, .max_x = 0, .max_y = 0 },
            .movement_x = 84,
            .movement_y = -63,
            .expected = .{ .kind = .grazing, .fraction = 1.0 / 7.0, .normal = .{ .x = 0.6, .y = 0.8 } },
        },
        // The centre reaches (-3, -4), exactly radius 5 from the corner, at t = 1.
        // The old projection and separate quotients rounded this entry beyond the segment.
        .{
            .moving = .{ .centre_x = -4, .centre_y = -8, .radius = 5 },
            .target = .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 2 },
            .movement_x = 1,
            .movement_y = 4,
            .expected = .{ .kind = .entering, .fraction = 1, .normal = .{ .x = -0.6, .y = -0.8 } },
        },
        // An overlapping circle moving apart still hits at t = 0
        .{
            .moving = .{ .centre_x = -0.5, .centre_y = 1, .radius = 1 },
            .target = .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 2 },
            .movement_x = -1,
            .movement_y = 0,
            .expected = .{ .kind = .overlapping, .fraction = 0, .normal = .{ .x = -1, .y = 0 } },
        },
        // A centre inside the box returns no normal
        .{
            .moving = .{ .centre_x = 1, .centre_y = 1, .radius = 0.5 },
            .target = .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 2 },
            .movement_x = 0,
            .movement_y = 0,
            .expected = .{ .kind = .overlapping, .fraction = 0, .normal = null },
        },
        // Touching and moving inward is entering at t = 0
        .{
            .moving = .{ .centre_x = -1, .centre_y = 1, .radius = 1 },
            .target = .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 2 },
            .movement_x = 1,
            .movement_y = 0,
            .expected = .{ .kind = .entering, .fraction = 0, .normal = .{ .x = -1, .y = 0 } },
        },
        // Stationary touching is grazing
        .{
            .moving = .{ .centre_x = -1, .centre_y = 1, .radius = 1 },
            .target = .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 2 },
            .movement_x = 0,
            .movement_y = 0,
            .expected = .{ .kind = .grazing, .fraction = 0, .normal = .{ .x = -1, .y = 0 } },
        },
        // Touching and moving apart is a miss
        .{
            .moving = .{ .centre_x = -1, .centre_y = 1, .radius = 1 },
            .target = .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 2 },
            .movement_x = -1,
            .movement_y = 0,
            .expected = null,
        },
        // Stationary separated shapes do not hit
        .{
            .moving = .{ .centre_x = -2, .centre_y = 1, .radius = 1 },
            .target = .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 2 },
            .movement_x = 0,
            .movement_y = 0,
            .expected = null,
        },
    };
    for (cases, 0..) |case, index| {
        errdefer std.debug.print("case {d}: {any}\n", .{ index + 1, case });
        const actual = sweepCircleAABB(case.moving, case.target, case.movement_x, case.movement_y);
        try expectContact(case.expected, actual);
    }
}

fn expectContact(expected: ?Contact, actual: ?Contact) !void {
    const tolerance: f32 = 0.00001;
    if (expected) |wanted| {
        const hit = actual orelse return error.ExpectedContact;
        try std.testing.expectEqual(wanted.kind, hit.kind);
        try std.testing.expect(std.math.isFinite(hit.fraction));
        try std.testing.expect(hit.fraction >= 0 and hit.fraction <= 1);
        if (hit.normal) |normal| {
            try std.testing.expect(std.math.isFinite(normal.x) and std.math.isFinite(normal.y));
            try std.testing.expectApproxEqAbs(@as(f32, 1), normal.x * normal.x + normal.y * normal.y, tolerance);
        }
        try std.testing.expectApproxEqAbs(wanted.fraction, hit.fraction, tolerance);
        if (wanted.normal) |normal| {
            const actual_normal = hit.normal orelse return error.ExpectedNormal;
            try std.testing.expectApproxEqAbs(normal.x, actual_normal.x, tolerance);
            try std.testing.expectApproxEqAbs(normal.y, actual_normal.y, tolerance);
        } else {
            try std.testing.expect(hit.normal == null);
        }
    } else {
        try std.testing.expect(actual == null);
    }
}
