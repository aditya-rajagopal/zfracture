//! Vector library
//!
//! This module provides a set of vector types and functions.
//!
//! # Examples
//!
//! ```
//! const math = @import("fr_core");
//! const Vec2 = math.Vec2;
//! pub fn main() !void {
//!     const v = Vec2.init(1.0, 2.0);
//!     const v2 = v.muls(2.0);
//!     std.debug.assert(v2.eql(&Vec2.init(2.0, 4.0)));
//! }
//! ```
// TODO:
//      - [ ] Step function
//      - [ ] Smooth step and interpolation
//      - [ ] Benchmark
//      - [ ] Docstrings
//      - [ ] Write tests

pub const Vec2 = Vector2(f32);
pub const Vec3 = Vector3(f32);
pub const Vec4 = Vector4(f32);

/// Enumeration of the components of a vector.
pub const Component = enum(u2) {
    x = 0,
    y = 1,
    z = 2,
    w = 3,
};

/// 2D vector type.
pub fn Vector2(comptime backing_type: type) type {
    return extern struct {
        vec: Simd,

        pub const dim = 2;
        pub const T = backing_type;
        pub const Simd = @Vector(dim, backing_type);
        pub const Array = [dim]backing_type;

        const Self = @This();
        const Mixins = VectorMixins(T, Self, dim);

        pub const zeros: Self = Mixins.zeros;
        pub const ones: Self = Mixins.ones;
        pub const x_basis: Self = Self.init(1.0, 0.0);
        pub const y_basis: Self = Self.init(0.0, 1.0);

        /// Initialize a vector from 2 scalars.
        pub inline fn init(_x: T, _y: T) Self {
            return .{ .vec = .{ _x, _y } };
        }

        /// Get the x component of the vector.
        pub inline fn x(self: *const Self) T {
            return self.vec[0];
        }

        /// Get the y component of the vector.
        pub inline fn y(self: *const Self) T {
            return self.vec[1];
        }

        /// Swizzle the vector components using the given component enumerations.
        pub inline fn swizzle(a: *const Self, x_comp: Component, y_comp: Component) Self {
            return .{ .vec = @shuffle(T, a.vec, undefined, [2]i32{ @intFromEnum(x_comp), @intFromEnum(y_comp) }) };
        }

        /// Transform a vec2 with a 3x3 trasform matrix of shape with m * v
        /// The transformation is assumed to be a 2D affine transformation with the following layout:
        /// |a, b, dx|
        /// |c, d, dy|
        /// |0, 0, 1 |
        /// If w is == 1 then please use transform_pos and for w == 0 please use transform_dir
        //TODO: Check if it is faster to conver to vec3 and do a loopd multiply
        pub inline fn transform(v: *const Self, w: T, m: *const Mat3x3(T)) Self {
            return .{ .vec = .{
                m.c[0].vec[0] * v.vec[0] + m.c[1].vec[0] * v.vec[1] + w * m.c[2].vec[0],
                m.c[0].vec[1] * v.vec[0] + m.c[1].vec[1] * v.vec[1] + w * m.c[3].vec[0],
            } };
        }

        /// Transform a the 2D vector by a 2D affine transformation matrix.
        /// The transformation is assumed to be a 2D affine transformation with the following layout:
        /// |a, b, dx|
        /// |c, d, dy|
        /// |0, 0, 1 |
        /// The w component of the transformation is assumed to be 1.
        /// Please use `transform` if you want to specify the w component of the transformation.
        pub inline fn transform_pos(v: *const Self, m: *const Mat3x3(T)) Self {
            return .{ .vec = .{
                m.c[0].vec[0] * v.vec[0] + m.c[1].vec[0] * v.vec[1] + m.c[2].vec[0],
                m.c[0].vec[1] * v.vec[0] + m.c[1].vec[1] * v.vec[1] + m.c[3].vec[0],
            } };
        }

        /// Transform a the 2D vector by a 2D affine transformation matrix.
        /// The transformation is assumed to be a 2D affine transformation with the following layout:
        /// |a, b, dx|
        /// |c, d, dy|
        /// |0, 0, 1 |
        /// The w component of the transformation is assumed to be 0.
        /// Please use `transform` if you want to specify the w component of the transformation.
        pub inline fn transform_dir(v: *const Self, m: *const Mat3x3(T)) Self {
            return .{ .vec = .{
                m.c[0].vec[0] * v.vec[0] + m.c[1].vec[0] * v.vec[1],
                m.c[0].vec[1] * v.vec[0] + m.c[1].vec[1] * v.vec[1],
            } };
        }

        /// Multiply a vector by a 2x2 matrix. This is the same as `v * m`.
        pub inline fn mat_mul(v: *const Self, m: *const Mat2x2(T)) Self {
            return .{ .vec = .{
                m.c[0].vec[0] * v.vec[0] + m.c[1].vec[0] * v.vec[1],
                m.c[0].vec[1] * v.vec[0] + m.c[1].vec[1] * v.vec[1],
            } };
        }

        /// Multiply a 2x2 matrix by a vector. This is the same as `m * v`.
        pub inline fn mat_vmul(v: *const Self, m: *const Mat2x2(T)) Self {
            return .{ .vec = .{
                m.c[0].vec[0] * v.vec[0] + m.c[0].vec[1] * v.vec[1],
                m.c[1].vec[0] * v.vec[0] + m.c[1].vec[1] * v.vec[1],
            } };
        }

        pub const init_slice = Mixins.init_slice;
        pub const to_slice = Mixins.to_slice;
        pub const init_array = Mixins.init_array;
        pub const to_array = Mixins.to_array;
        pub const add = Mixins.add;
        pub const sub = Mixins.sub;
        pub const mul = Mixins.mul;
        pub const div = Mixins.div;
        pub const fmadd = Mixins.fmadd;
        pub const fmadd2 = Mixins.fmadd2;
        pub const splat = Mixins.splat;
        pub const adds = Mixins.adds;
        pub const subs = Mixins.subs;
        pub const muls = Mixins.muls;
        pub const divs = Mixins.divs;
        pub const abs = Mixins.abs;
        pub const dot = Mixins.dot;
        pub const is_zero = Mixins.is_zero;
        pub const norm2 = Mixins.norm2;
        pub const norm = Mixins.norm;
        pub const reflect = Mixins.reflect;
        pub const inv_norm = Mixins.inv_norm;
        pub const normalize = Mixins.normalize;
        pub const dist = Mixins.dist;
        pub const dist2 = Mixins.dist2;
        pub const negate = Mixins.negate;
        pub const mid_point = Mixins.mid_point;
        pub const min = Mixins.min;
        pub const max = Mixins.max;
        pub const clamp = Mixins.clamp;
        pub const clamp01 = Mixins.clamp01;
        pub const lerp = Mixins.lerp;
        pub const lerp_clamped = Mixins.lerp_clamped;
        pub const project = Mixins.project;
        pub const eql = Mixins.eql;
        pub const eqls = Mixins.eqls;
        pub const eql_exact = Mixins.eql_exact;
        pub const eql_approx = Mixins.eql_appox;
        pub const less = Mixins.less;
        pub const less_eq = Mixins.less_eq;
        pub const greater = Mixins.greater;
        pub const greater_eq = Mixins.greater_eq;
    };
}

pub fn Vector3(comptime backing_type: type) type {
    return extern struct {
        vec: Simd,

        pub const dim = 3;
        pub const T = backing_type;
        pub const Simd = @Vector(dim, backing_type);
        pub const Array = [dim]backing_type;

        const Self = @This();

        const Mixins = VectorMixins(T, Self, dim);
        pub const zeros: Self = Mixins.zeros;
        pub const ones: Self = Mixins.ones;
        pub const x_basis: Self = Self.init(1.0, 0.0, 0.0);
        pub const y_basis: Self = Self.init(0.0, 1.0, 0.0);
        pub const z_basis: Self = Self.init(0.0, 0.0, 1.0);

        /// Initialize a vector from 3 scalars.
        pub inline fn init(_x: T, _y: T, _z: T) Self {
            return .{ .vec = .{ _x, _y, _z } };
        }

        /// Get the x component of the vector.
        pub inline fn x(self: *const Self) T {
            return self.vec[0];
        }

        /// Get the y component of the vector.
        pub inline fn y(self: *const Self) T {
            return self.vec[1];
        }

        /// Get the z component of the vector.
        pub inline fn z(self: *const Self) T {
            return self.vec[2];
        }

        /// Convert the vector to a 4D vector with the given w component.
        pub inline fn to_vec4w(self: *const Self, w: T) Vec4(T) {
            return .{ .vec = .{ self.vec[0], self.vec[1], self.vec[2], w } };
        }

        /// Convert to a 4D direction vector with the last element set to 0.
        pub inline fn to_vec4_dir(self: *const Self) Vec4(T) {
            return .{ .vec = .{ self.vec[0], self.vec[1], self.vec[2], 0.0 } };
        }

        /// Convert to a 4D vector with the last element set to 1.
        pub inline fn to_vec4(self: *const Self) Vec4(T) {
            return .{ .vec = .{ self.vec[0], self.vec[1], self.vec[2], 1.0 } };
        }

        /// Swizzle the vector components using the given component enumerations.
        pub inline fn swizzle(a: *const Self, x_comp: Component, y_comp: Component, z_comp: Component) Self {
            return .{ .vec = @shuffle(
                T,
                a.vec,
                undefined,
                [3]i32{ @intFromEnum(x_comp), @intFromEnum(y_comp), @intFromEnum(z_comp) },
            ) };
        }

        /// Get a vector with all components set to the x component.
        pub inline fn splat_x(self: *const Self) Self {
            return self.swizzle(.x, .x, .x);
        }

        /// Get a vector with all components set to the y component.
        pub inline fn splat_y(self: *const Self) Self {
            return self.swizzle(.y, .y, .y);
        }

        /// Get a vector with all components set to the z component.
        pub inline fn splat_z(self: *const Self) Self {
            return self.swizzle(.z, .z, .z);
        }

        /// Compute the cross product of two vectors.
        pub inline fn cross(v1: *const Self, v2: *const Self) Self {
            const x0 = v1.swizzle(.y, .z, .x);
            const x2 = x0.mul(v1).swizzle(.y, .z, .x);
            const x3 = x0.mul(&v2.swizzle(.z, .x, .y));
            return x3.sub(&x2);
        }

        /// Compute the angle between two vectors.
        pub inline fn angle_between(v1: *const Self, v2: *const Self) f32 {
            const dot_ = v1.dot(v2);
            const norm_ = v1.cross(v2).norm();
            return std.math.atan2(norm_, dot_);
        }

        /// Compute M * v
        pub inline fn mat_mul(vector: *const Self, m: *const Mat3x3(T)) Self {
            var result: Self = undefined;
            inline for (0..Self.dim) |r| {
                inline for (0..Self.dim) |c| {
                    result.vec[r] += vector.vec[c] * m.c[c].vec[r];
                }
            }
            return result;
        }

        /// Compute v * M
        pub inline fn mat_vmul(vector: *const Self, m: *const Mat3x3(T)) Self {
            var result: Self = undefined;
            inline for (0..Self.dim) |r| {
                inline for (0..Self.dim) |c| {
                    result.vec[r] += vector.vec[c] * m.c[r].vec[c];
                }
            }
            return result;
        }

        const AffT = Affine(T);
        /// Transform a vector by the affine transformation.
        pub inline fn transform(v: *const Self, m: *const AffT) Self {
            // TODO: Check on other processors if this is still much faster in Debug builds. 3.3sec for 400mil transforms
            // from 8sec
            // The conversion to vec4 and back to vec3 Is faster in release fast 0.20sec vs 0.32sec
            switch (builtin.mode) {
                .Debug => return v.transform_debug(m),
                else => return v.to_vec4().transform(m).to_vec3(),
            }
        }

        inline fn transform_debug(v: *const Self, m: *const AffT) Self {
            var result: Self = m.c[3].to_vec3();
            inline for (0..3) |r| {
                inline for (0..3) |c| {
                    result.vec[r] += v.vec[c] * m.c[c].vec[r];
                }
            }
            return result;
        }

        /// Transform a vector by the matrix.
        /// The vector is assumed to be a direction vector i.e. the w component is assumed to be 0.
        pub inline fn transform_dir(v: *const Self, m: *const AffT) Self {
            switch (builtin.mode) {
                .Debug => return v.transform_dir_debug(m),
                else => return v.to_vec4_dir().transform(m).to_vec3(),
            }
        }

        // TODO: Check on other processors if this is still much faster in Debug builds. 2.7sec for 400mil transforms
        // from 8sec
        // The conversion to vec4 and back to vec3 Is faster in release fast 0.20sec vs 0.32sec
        inline fn transform_dir_debug(v: *const Self, m: *const AffT) Self {
            var result: Self = Self.zeros;
            inline for (0..3) |r| {
                inline for (0..3) |c| {
                    result.vec[r] += v.vec[c] * m.c[c].vec[r];
                }
            }
            return result;
        }

        pub const init_slice = Mixins.init_slice;
        pub const to_slice = Mixins.to_slice;
        pub const init_array = Mixins.init_array;
        pub const to_array = Mixins.to_array;
        pub const add = Mixins.add;
        pub const sub = Mixins.sub;
        pub const mul = Mixins.mul;
        pub const div = Mixins.div;
        pub const fmadd = Mixins.fmadd;
        pub const fmadd2 = Mixins.fmadd2;
        pub const splat = Mixins.splat;
        pub const adds = Mixins.adds;
        pub const subs = Mixins.subs;
        pub const muls = Mixins.muls;
        pub const divs = Mixins.divs;
        pub const abs = Mixins.abs;
        pub const dot = Mixins.dot;
        pub const is_zero = Mixins.is_zero;
        pub const norm2 = Mixins.norm2;
        pub const norm = Mixins.norm;
        pub const reflect = Mixins.reflect;
        pub const inv_norm = Mixins.inv_norm;
        pub const normalize = Mixins.normalize;
        pub const dist = Mixins.dist;
        pub const dist2 = Mixins.dist2;
        pub const negate = Mixins.negate;
        pub const mid_point = Mixins.mid_point;
        pub const min = Mixins.min;
        pub const max = Mixins.max;
        pub const clamp = Mixins.clamp;
        pub const clamp01 = Mixins.clamp01;
        pub const lerp = Mixins.lerp;
        pub const lerp_clamped = Mixins.lerp_clamped;
        pub const project = Mixins.project;
        pub const eql = Mixins.eql;
        pub const eqls = Mixins.eqls;
        pub const eql_exact = Mixins.eql_exact;
        pub const eql_approx = Mixins.eql_appox;
        pub const less = Mixins.less;
        pub const less_eq = Mixins.less_eq;
        pub const greater = Mixins.greater;
        pub const greater_eq = Mixins.greater_eq;
    };
}

pub fn Vector4(comptime backing_type: type) type {
    return extern struct {
        vec: Simd,

        pub const dim = 4;
        pub const T = backing_type;
        pub const Simd = @Vector(dim, backing_type);
        pub const Array = [dim]backing_type;

        const Self = @This();

        const Mixins = VectorMixins(T, Self, dim);
        pub const zeros: Self = Mixins.zeros;
        pub const ones: Self = Mixins.ones;
        pub const x_basis: Self = Self.init(1.0, 0.0, 0.0, 0.0);
        pub const y_basis: Self = Self.init(0.0, 1.0, 0.0, 0.0);
        pub const z_basis: Self = Self.init(0.0, 0.0, 1.0, 0.0);
        pub const w_basis: Self = Self.init(0.0, 0.0, 0.0, 1.0);

        /// Initialize a vector from 4 scalars.
        pub inline fn init(_x: T, _y: T, _z: T, _w: T) Self {
            return .{ .vec = .{ _x, _y, _z, _w } };
        }

        /// Get the x component of the vector.
        pub inline fn x(self: *const Self) T {
            return self.vec[0];
        }

        /// Get the y component of the vector.
        pub inline fn y(self: *const Self) T {
            return self.vec[1];
        }

        /// Get the z component of the vector.
        pub inline fn z(self: *const Self) T {
            return self.vec[2];
        }

        /// Get the w component of the vector.
        pub inline fn w(self: *const Self) T {
            return self.vec[3];
        }

        /// Get a vector with all components set to the x component.
        pub inline fn splat_x(self: *const Self) Self {
            return self.swizzle(.x, .x, .x, .x);
        }

        /// Get a vector with all components set to the y component.
        pub inline fn splat_y(self: *const Self) Self {
            return self.swizzle(.y, .y, .y, .y);
        }

        /// Get a vector with all components set to the z component.
        pub inline fn splat_z(self: *const Self) Self {
            return self.swizzle(.z, .z, .z, .z);
        }

        /// Get a vector with all components set to the w component.
        pub inline fn splat_w(self: *const Self) Self {
            return self.swizzle(.w, .w, .w, .w);
        }

        /// Convert the vector to a 3D vector ignoring the w component.
        pub inline fn to_vec3(self: *const Self) Vec3(T) {
            return @bitCast(self.*);
        }

        /// Swizzle the vector components using the given component enumerations.
        pub inline fn swizzle(
            a: *const Self,
            x_comp: Component,
            y_comp: Component,
            z_comp: Component,
            w_comp: Component,
        ) Self {
            return .{ .vec = @shuffle(
                T,
                a.vec,
                undefined,
                [4]i32{ @intFromEnum(x_comp), @intFromEnum(y_comp), @intFromEnum(z_comp), @intFromEnum(w_comp) },
            ) };
        }

        /// Compute M * v
        pub inline fn mat_mul(vector: *const Self, m: *const Mat4x4(T)) Self {
            var result: Self = undefined;
            inline for (0..Self.dim) |r| {
                inline for (0..Self.dim) |c| {
                    result.vec[r] += vector.vec[c] * m.c[c].vec[r];
                }
            }
            return result;
        }

        /// Compute v * M
        pub inline fn mat_vmul(vector: *const Self, m: *const Mat4x4(T)) Self {
            var result: Self = undefined;
            inline for (0..Self.dim) |r| {
                inline for (0..Self.dim) |c| {
                    result.vec[r] += vector.vec[c] * m.c[r].vec[c];
                }
            }
            return result;
        }

        const AffT = Affine(T);

        /// Transform vector with an affine transformation => T * v
        pub inline fn transform(v: *const Self, m: *const AffT) Self {
            var result: Self = Self.zeros;
            inline for (0..AffT.shape[0]) |r| {
                inline for (0..AffT.shape[1]) |c| {
                    result.vec[r] += v.vec[c] * m.c[c].vec[r];
                }
            }
            return result;
        }

        /// t is expected to be between 0.0 and 1.0. q0 and q1 are assumed to be normalized
        pub fn slerp(v1: *const Self, v2: *const Self, t: T) Self {
            if (@typeInfo(T) == .float) {
                var d = v1.dot(v2);
                const a = v1.vec;
                var b = v2.vec;

                if (d < 0.0) {
                    d = -d;
                    b = -b;
                }

                const DOT_THRESHOLD: T = 0.9995;
                if (d > DOT_THRESHOLD) {
                    // NOTE: If the inputs are really close to each other then we linerearly interpolate
                    const result: Self = .{ .vec = .{
                        a[0] + (b[0] - a[0]) * t,
                        a[1] + (b[1] - a[1]) * t,
                        a[2] + (b[2] - a[2]) * t,
                        a[3] + (b[3] - a[3]) * t,
                    } };
                    return result.normalize(0.00000001);
                }

                // NOTE: Since we have gurenteed that dot is between [0, DOT_THRESHOLD] we can do acos
                const theta0: T = std.math.acos(d); // Angle between the vectors
                const theta: T = theta0 * t; // Angle btween q0 and the result
                const s_theta: T = @sin(theta);
                const s_theta0: T = @sin(theta0);

                const s0 = @cos(theta) - d * s_theta / s_theta0;
                const s1 = s_theta / s_theta0;
                return .{ .vec = .{
                    a[0] * s0 + b[0] * s1,
                    a[1] * s0 + b[1] * s1,
                    a[2] * s0 + b[2] * s1,
                    a[3] * s0 + b[3] * s1,
                } };
            } else {
                return v1.*;
            }
        }

        pub const init_slice = Mixins.init_slice;
        pub const to_slice = Mixins.to_slice;
        pub const init_array = Mixins.init_array;
        pub const to_array = Mixins.to_array;
        pub const add = Mixins.add;
        pub const sub = Mixins.sub;
        pub const mul = Mixins.mul;
        pub const div = Mixins.div;
        pub const fmadd = Mixins.fmadd;
        pub const fmadd2 = Mixins.fmadd2;
        pub const splat = Mixins.splat;
        pub const adds = Mixins.adds;
        pub const subs = Mixins.subs;
        pub const muls = Mixins.muls;
        pub const divs = Mixins.divs;
        pub const abs = Mixins.abs;
        pub const dot = Mixins.dot;
        pub const is_zero = Mixins.is_zero;
        pub const norm2 = Mixins.norm2;
        pub const norm = Mixins.norm;
        pub const inv_norm = Mixins.inv_norm;
        pub const normalize = Mixins.normalize;
        pub const dist = Mixins.dist;
        pub const dist2 = Mixins.dist2;
        pub const negate = Mixins.negate;
        pub const mid_point = Mixins.mid_point;
        pub const min = Mixins.min;
        pub const max = Mixins.max;
        pub const clamp = Mixins.clamp;
        pub const clamp01 = Mixins.clamp01;
        pub const lerp = Mixins.lerp;
        pub const lerp_clamped = Mixins.lerp_clamped;
        pub const project = Mixins.project;
        pub const eql = Mixins.eql;
        pub const eql_exact = Mixins.eql_exact;
        pub const eqls = Mixins.eqls;
        pub const eql_approx = Mixins.eql_appox;
        pub const less = Mixins.less;
        pub const less_eq = Mixins.less_eq;
        pub const greater = Mixins.greater;
        pub const greater_eq = Mixins.greater_eq;
    };
}

pub fn VectorMixins(comptime T: type, comptime VecT: type, comptime dim: usize) type {
    return struct {
        pub const zeros: VecT = VecT.splat(0.0);
        pub const ones: VecT = VecT.splat(1.0);
        pub const is_float = if (@typeInfo(T) == .float) true else false;

        /// Initialize a vector from a slice of data.
        /// The data must have at least `dim` elements.
        pub inline fn init_slice(data: []const T) VecT {
            assert(data.len >= dim);
            return .{ .vec = data[0..dim].* };
        }

        /// Initialize a vector from an array of data.
        pub inline fn init_array(data: VecT.Array) VecT {
            return .{ .vec = data };
        }

        /// Convert the vector to an array of data.
        pub inline fn to_array(a: *const VecT) VecT.Array {
            return a.vec;
        }

        /// Store the vector data in the given slice.
        pub inline fn to_slice(a: *const VecT, data: []T) void {
            assert(data.len >= dim);
            data[0..dim].* = a.vec;
        }

        /// Add two vectors.
        pub inline fn add(a: *const VecT, b: *const VecT) VecT {
            return .{ .vec = a.vec + b.vec };
        }

        /// Subtract two vectors.
        pub inline fn sub(a: *const VecT, b: *const VecT) VecT {
            return .{ .vec = a.vec - b.vec };
        }

        /// Multiply two vectors element wise.
        pub inline fn mul(a: *const VecT, b: *const VecT) VecT {
            return .{ .vec = a.vec * b.vec };
        }

        /// Divide two vectors element wise.
        pub inline fn div(a: *const VecT, b: *const VecT) VecT {
            return .{ .vec = a.vec / b.vec };
        }

        /// Create a vector with all components set to the same value.
        pub inline fn splat(s: T) VecT {
            return .{ .vec = @splat(s) };
        }

        /// Add a scalar to all components of the vector.
        pub inline fn adds(a: *const VecT, s: T) VecT {
            return .{ .vec = a.vec + VecT.splat(s).vec };
        }

        /// Subtract a scalar from all components of the vector.
        pub inline fn subs(a: *const VecT, s: T) VecT {
            return .{ .vec = a.vec - VecT.splat(s).vec };
        }

        /// Multiply a scalar to all components of the vector.
        pub inline fn muls(a: *const VecT, s: T) VecT {
            return .{ .vec = a.vec * VecT.splat(s).vec };
        }

        /// Divide a scalar from all components of the vector.
        pub inline fn divs(a: *const VecT, s: T) VecT {
            assert(s != 0);
            return .{ .vec = a.vec / VecT.splat(s).vec };
        }

        /// Compute the absolute value of the vector.
        pub inline fn abs(a: *const VecT) VecT {
            return .{ .vec = @abs(a.vec) };
        }

        /// Check if all components of the vector are zero.
        pub inline fn is_zero(a: *const VecT) bool {
            return a.eql(&VecT.zeros);
        }

        /// Compute the dot product of two vectors.
        pub inline fn dot(a: *const VecT, b: *const VecT) T {
            return @reduce(.Add, a.vec * b.vec);
        }

        /// Compute the squared norm of the vector.
        pub inline fn norm2(a: *const VecT) T {
            return switch (dim) {
                inline 2 => a.vec[0] * a.vec[0] + a.vec[1] * a.vec[1],
                inline 3, 4 => @reduce(.Add, a.vec * a.vec),
                else => @compileError("Type " ++ @typeName(VecT) ++ " not supported"),
            };
        }

        /// Compute the norm of the vector.
        pub inline fn norm(a: *const VecT) T {
            return std.math.sqrt(a.norm2());
        }

        /// Compute the inverse norm of the vector.
        pub inline fn inv_norm(a: *const VecT) VecT {
            return VecT.ones.divs(a.norm());
        }

        /// Normalize the vector.
        pub inline fn normalize(a: *const VecT, delta: T) VecT {
            return a.divs(a.norm() + delta);
        }

        /// Compute the squared distance between two vectors.
        pub inline fn dist2(a: *const VecT, b: *const VecT) T {
            return a.sub(b).norm2();
        }

        /// Compute the distance between two vectors.
        pub inline fn dist(a: *const VecT, b: *const VecT) T {
            return a.sub(b).norm();
        }

        /// Negate the vector.
        pub inline fn negate(a: *const VecT) VecT {
            return .{ .vec = -a.vec };
        }

        /// Compute the mid point between two vectors.
        pub inline fn mid_point(a: *const VecT, b: *const VecT) VecT {
            return a.add(b).muls(0.5);
        }

        /// Compute the minimum of two vectors.
        pub inline fn min(a: *const VecT, b: *const VecT) VecT {
            return .{ .vec = @min(a.vec, b.vec) };
        }

        /// Compute the maximum of two vectors.
        pub inline fn max(a: *const VecT, b: *const VecT) VecT {
            return .{ .vec = @max(a.vec, b.vec) };
        }

        /// Clamp the vector to the given min and max values.
        pub inline fn clamp(a: *const VecT, min_val: T, max_val: T) VecT {
            return .{ .vec = std.math.clamp(a.vec, VecT.splat(min_val).vec, VecT.splat(max_val).vec) };
        }

        /// Clamp the vector to the range [0, 1].
        pub inline fn clamp01(a: *const VecT) VecT {
            return a.clamp(0.0, 1.0);
        }

        /// Returns a * b + c
        pub inline fn fmadd(a: *const VecT, b: *const VecT, c: *const VecT) VecT {
            if (comptime is_float) {
                return .{ .vec = @mulAdd(VecT.Simd, a.vec, b.vec, c.vec) };
            } else {
                return a.mul(b).add(c);
            }
        }

        /// Returns a + b * c
        pub inline fn fmadd2(a: *const VecT, b: *const VecT, c: *const VecT) VecT {
            if (comptime is_float) {
                return .{ .vec = @mulAdd(VecT.Simd, b.vec, c.vec, a.vec) };
            } else {
                return b.mul(c).add(a);
            }
        }

        /// Linearly interpolate between two vectors.
        pub inline fn lerp(a: *const VecT, b: *const VecT, t: f32) VecT {
            if (comptime is_float) {
                return .{ .vec = std.math.lerp(a.vec, b.vec, VecT.splat(t).vec) };
            } else {
                @compileError("Cant use lerp for Integer Vector types");
            }
        }

        /// Linearly interpolate between two vectors but clamp t to the range [0, 1].
        pub inline fn lerp_clamped(a: *const VecT, b: *const VecT, t: f32) VecT {
            if (comptime is_float) {
                const amount = std.math.clamp(t, 0.0, 1.0);
                return a.lerp(b, amount);
            } else {
                @compileError("Cant use lerp for Integer Vector types");
            }
        }

        /// Project a vector onto another vector.
        pub inline fn project(a: *const VecT, b: *const VecT) VecT {
            const unit = a.normalize(0.00000001);
            const proj = a.dot(b);
            return unit.muls(proj);
        }

        /// Reflect a vector about a unit normal vector.
        pub inline fn reflect(incident: *const VecT, unit_normal: *const VecT) VecT {
            if (comptime dim >= 3) {
                @compileError("Reflect is only supported for Vec2 and Vec3");
            }
            const dot_product = incident.dot(unit_normal);
            return incident.sub(&unit_normal.muls(2 * dot_product));
        }

        /// For floats this function is only accurate for small float values in the vector
        pub inline fn eql(a: *const VecT, b: *const VecT) bool {
            if (comptime is_float) {
                return eql_appox(a, b, std.math.floatEps(T));
            } else {
                return @reduce(.And, a.vec == b.vec);
            }
        }

        pub inline fn eql_exact(a: *const VecT, b: *const VecT) bool {
            return @reduce(.And, a.vec == b.vec);
        }

        /// For floats this function is only accurate for small float values in the vector
        pub inline fn eql_appox(a: *const VecT, b: *const VecT, comptime tolarance: T) bool {
            const x0 = @abs(a.vec - b.vec);
            const mask = x0 < VecT.splat(tolarance).vec;
            return @reduce(.And, mask);
        }

        /// For floats this function is only accurate for small float values in the vector
        pub inline fn eqls(a: *const VecT, b: T) bool {
            const vec_b = VecT.splat(b);
            if (comptime is_float) {
                return eql_appox(a, &vec_b, std.math.floatEps(T));
            } else {
                return @reduce(.And, a.vec == vec_b.vec);
            }
        }

        /// Check if all components of the vector are less than the corresponding components of the other vector.
        // TODO: Should there be approximate versions of these?
        pub inline fn less(a: *const VecT, b: *const VecT) bool {
            return @reduce(.And, a.vec < b.vec);
        }

        /// Check if all components of the vector are less than or equal to the corresponding components of the other vector.
        pub inline fn less_eq(a: *const VecT, b: *const VecT) bool {
            return @reduce(.And, a.vec <= b.vec);
        }

        /// Check if all components of the vector are greater than or equal to the corresponding components of the other vector.
        pub inline fn greater_eq(a: *const VecT, b: *const VecT) bool {
            return @reduce(.And, a.vec >= b.vec);
        }

        /// Check if all components of the vector are greater than the corresponding components of the other vector.
        pub inline fn greater(a: *const VecT, b: *const VecT) bool {
            return @reduce(.And, a.vec > b.vec);
        }
    };
}
//
// test Vec4 {
//     const v = Vec3(f32).init(1.0, 0.0, 0.0);
//     const rot = Affine(f32).init_rot_z(std.math.pi / 2.0);
//     const translate = Affine(f32).init_trans(&Vec3(f32).init(0.0, 1.0, 0.0));
//     const transform = rot.mul(&translate);
//     // const transform = translate.mul(&rot);
//     std.debug.print("Transform: {any}\n", .{transform});
//     std.debug.print("Vector: {any}\n", .{v.transform_dir(&transform)});
//     std.debug.print("Vector: {any}\n", .{transform.transform_dir(&v)});
//     // std.debug.print("Vector: {any}\n", .{v.transform_dir_debug(&transform)});
// }

const Affine = @import("affine.zig").Affine;
const matrix = @import("matrix.zig");
const Mat2x2 = matrix.Mat2x2;
const Mat3x3 = matrix.Mat3x3;
const Mat4x4 = matrix.Mat4x4;
const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
