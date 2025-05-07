//! Quaternion library
//!
//! This module provides a type for quaternions. Quaternions are used to represent rotations.
//! Quaternions are stored in a Vec4 with the w component being the real part and the x, y and z components being the imaginary parts.
//!
//! # Examples
//!
//! ```
//! const math = @import("fr_core");
//! const Quat = math.Quat;
//! const Vec3 = math.Vec3;
//! pub fn main() !void {
//!     const q = Quat.init(1.0, 2.0, 3.0, 4.0);
//! }
//! ```
// TODO:
//      - [ ] Benchmark
//      - [ ] Docstrings
//      - [ ] Write tests

pub const Quat = Quaternion(f32);

pub fn Quaternion(comptime backing_type: type) type {
    comptime assert(backing_type == f16 or backing_type == f32 or backing_type == f64);
    return extern struct {
        q: Simd,

        pub const E = backing_type;
        pub const Simd = Vec4.Simd;
        const Vec4 = vec.Vec4(E);
        const Vec3 = vec.Vec3(E);
        const Transform = Affine(E);

        const Self = @This();

        /// Identity quaternion
        pub const identity = Self.init(0.0, 0.0, 0.0, 1.0);

        /// Initialize a quaternion from 4 scalars.
        pub inline fn init(x_: E, y_: E, z_: E, w_: E) Self {
            return .{ .q = .{ x_, y_, z_, w_ } };
        }

        /// Initialize a quaternion from a vector and a scalar.
        pub inline fn init_from_vec3(v: *const Vec3, w_: E) Self {
            return .{ .q = .{ v.x(), v.y(), v.z(), w_ } };
        }

        /// Initialize a quaternion from a transformation.
        pub inline fn init_transform(t: *const Transform) Self {
            return t.to_quat();
        }

        /// Get the x component of the quaternion.
        pub inline fn x(self: *const Self) E {
            return self.q[0];
        }

        /// Get the y component of the quaternion.
        pub inline fn y(self: *const Self) E {
            return self.q[1];
        }

        /// Get the z component of the quaternion.
        pub inline fn z(self: *const Self) E {
            return self.q[2];
        }

        /// Get the w component of the quaternion.
        pub inline fn w(self: *const Self) E {
            return self.q[3];
        }

        /// Convert the quaternion to a vec4 they have the same layout so this is just a bit cast.
        pub inline fn to_vec4(q: *const Self) Vec4 {
            return @bitCast(q.*);
        }

        /// Compute the dot product of two quaternions.
        pub inline fn dot(q0: *const Self, q1: *const Self) E {
            return @reduce(.Add, q0.q * q1.q);
        }

        /// Compute the squared norm of the quaternion.
        pub inline fn norm2(q: *const Self) E {
            return @reduce(.Add, q.q * q.q);
        }

        /// Compute the norm of the quaternion.
        pub inline fn norm(q: *const Self) E {
            return std.math.sqrt(q.norm2());
        }

        /// Create a quaternion with all components set to the same value.
        pub inline fn splat(v: E) Self {
            return .{ .q = @splat(v) };
        }

        /// Normalize the quaternion.
        pub inline fn normalize(q: *const Self, delta: E) Self {
            return .{ .q = q.q * Self.splat(q.norm() + delta).q };
        }

        /// Compute the conjugate of the quaternion.
        pub inline fn conjugate(q: *const Self) Self {
            return .{ .q = .{ -q.x(), -q.y(), -q.z(), q.w() } };
        }

        /// Compute the inverse of the quaternion.
        pub fn inverse(q: *const Self) Self {
            // NOTE(adi): the 0.00000001 is to avoid division by zero
            const n = q.norm() + 0.00000001;
            const inv_n = 1.0 / n;
            return .{ .q = .{ -q.x() * inv_n, -q.y() * inv_n, -q.z() * inv_n, q.w() * inv_n } };
        }

        /// Invert quaternion assuming it is already normalized.
        pub inline fn inverse_normalized(q: *const Self) Self {
            return q.conjugate();
        }

        /// Multiply two quaternions together using the Hamilton product.
        pub fn mul(q1: *const Self, q2: *const Self) Self {
            const q1x = q1.x();
            const q1y = q1.y();
            const q1z = q1.z();
            const q1w = q1.w();
            const q2x = q2.x();
            const q2y = q2.y();
            const q2z = q2.z();
            const q2w = q2.w();

            return .{ .q = .{
                q1x * q2w + q1y * q2z - q1z * q2y + q1w * q2x,
                -q1x * q2z + q1y * q2w + q1z * q2x + q1w * q2y,
                q1x * q2y - q1y * q2x + q1z * q2w + q1w * q2z,
                -q1x * q2x - q1y * q2y - q1z * q2z + q1w * q2w,
            } };
        }

        /// Rotate a 3D vector by the quaternion. Assumes the quaternion is normalized.
        pub fn rotate_vec3(q: *const Self, v: *const Vec3) Vec3 {
            const p = v.to_vec4_dir();
            const q_inv = q.inverse_normalized();
            const result = q.mul(p).mul(&q_inv);
            return result.to_vec4().to_vec3();
        }

        /// Convert the quaternion to an affine transformation.
        pub fn to_affine(q: *const Self) Transform {
            var result = Transform.identity;
            const n = q.normalize(0.0000001);

            result.c[0].vec[0] = 1.0 - 2.0 * n.q[1] * n.q[1] - 2.0 * n.q[2] * n.q[2];
            result.c[0].vec[1] = 2.0 * n.q[0] * n.q[1] - 2.0 * n.q[2] * n.q[3];
            result.c[0].vec[2] = 2.0 * n.q[0] * n.q[2] + 2.0 * n.q[1] * n.q[3];

            result.c[1].vec[1] = 2.0 * n.q[0] * n.q[1] + 2.0 * n.q[2] * n.q[3];
            result.c[1].vec[2] = 1.0 - 2.0 * n.q[0] * n.q[0] - 2.0 * n.q[2] * n.q[2];
            result.c[1].vec[3] = 2.0 * n.q[1] * n.q[2] - 2.0 * n.q[0] * n.q[3];

            result.c[2].vec[1] = 2.0 * n.q[0] * n.q[2] - 2.0 * n.q[1] * n.q[3];
            result.c[2].vec[2] = 2.0 * n.q[1] * n.q[2] + 2.0 * n.q[0] * n.q[3];
            result.c[2].vec[3] = 1.0 - 2.0 * n.q[0] * n.q[0] - 2.0 * n.q[1] * n.q[1];

            return result;
        }

        /// Convert the quaternion to an affine transformation.
        pub fn to_affine_center(q: *const Self, center: *const Vec3) Transform {
            var result: Transform = undefined;
            result.c[0].vec[0] = (q.x() * q.x()) - (q.y() * q.y()) - (q.z() * q.z()) + (q.w() * q.w());
            result.c[0].vec[1] = 2.0 * ((q.x() * q.y()) + (q.z() * q.w()));
            result.c[0].vec[2] = 2.0 * ((q.x() * q.z()) - (q.y() * q.w()));
            result.c[0].vec[3] = center.x() - center.x() * result.c[0].vec[0] - center.y() * result.c[0].vec[1] - center.z() * result.c[0].vec[2];

            result.c[1].vec[0] = 2.0 * ((q.x() * q.y()) - (q.z() * q.w()));
            result.c[1].vec[1] = -(q.x() * q.x()) + (q.y() * q.y()) - (q.z() * q.z()) + (q.w() * q.w());
            result.c[1].vec[2] = 2.0 * ((q.y() * q.z()) + (q.x() * q.w()));
            result.c[1].vec[3] = center.x() - center.x() * result.c[1].vec[0] - center.y() * result.c[1].vec[1] - center.z() * result.c[1].vec[2];

            result.c[2].vec[0] = 2.0 * ((q.x() * q.z()) + (q.y() * q.w()));
            result.c[2].vec[1] = 2.0 * ((q.y() * q.z()) - (q.x() * q.w()));
            result.c[2].vec[2] = -(q.x() * q.x()) - (q.y() * q.y()) + (q.z() * q.z()) + (q.w() * q.w());
            result.c[2].vec[3] = center.x() - center.x() * result.c[2].vec[0] - center.y() * result.c[2].vec[1] - center.z() * result.c[2].vec[2];

            result.c[3].vec[0] = 0.0;
            result.c[3].vec[1] = 0.0;
            result.c[3].vec[2] = 0.0;
            result.c[3].vec[3] = 1.0;
            return result;
        }

        /// Initialize a quaternion from an axis and an angle.
        /// The quaternion is normalized if post_normalize is true.
        pub fn init_axis_angle(axis: *const Vec3, angle_rad: f32, comptime post_normalize: bool) Self {
            const half_angle: f32 = angle_rad * 0.5;
            const s: f32 = @sin(half_angle);
            const c: f32 = @cos(half_angle);

            const vec_s = Vec3.splat(s);

            const q: Self = .init_from_vec3(vec_s.mul(axis), c);
            if (comptime post_normalize) {
                return q.normalize(0.00000001);
            } else {
                return q;
            }
        }

        /// t is expected to be between 0.0 and 1.0. q0 and q1 are assumed to be normalized
        pub fn slerp(q0: *const Self, q1: *const Self, t: E) Self {
            var d = q0.dot(q1);
            const a = q0.q;
            var b = q1.q;

            if (d < 0.0) {
                d = -d;
                b = -b;
            }

            const DOT_THRESHOLD: E = 0.9995;
            if (d > DOT_THRESHOLD) {
                // NOTE: If the inputs are really close to each other then we linerearly interpolate
                const result: Self = .{ .q = .{
                    a[0] + (b[0] - a[0]) * t,
                    a[1] + (b[1] - a[1]) * t,
                    a[2] + (b[2] - a[2]) * t,
                    a[3] + (b[3] - a[3]) * t,
                } };
                return result.normalize(0.00000001);
            }

            // NOTE: Since we have gurenteed that dot is between [0, DOT_THRESHOLD] we can do acos
            const theta0: E = std.math.acos(d); // Angle between the vectors
            const theta: E = theta0 * t; // Angle btween q0 and the result
            const s_theta: E = @sin(theta);
            const s_theta0: E = @sin(theta0);

            const s0 = @cos(theta) - d * s_theta / s_theta0;
            const s1 = s_theta / s_theta0;
            return .{ .q = .{
                a[0] * s0 + b[0] * s1,
                a[1] * s0 + b[1] * s1,
                a[2] * s0 + b[2] * s1,
                a[3] * s0 + b[3] * s1,
            } };
        }

        /// Linearly interpolate between two quaternions.
        pub inline fn lerp(q0: *const Self, q1: *const Self, t: E) Self {
            const t_v: Simd = @splat(t);
            return .{ .q = q0.q + (q1.q - q0.q) * t_v };
        }
    };
}

const Affine = @import("affine.zig").Affine;
const matrix = @import("matrix.zig");
const vec = @import("vec.zig");
const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
