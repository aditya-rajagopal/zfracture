//! Matrix library
//!
//! This module provides a set of matrix types and functions. The matrices are stored in column major order.
//!
//! # Examples
//!
//! ```
//! const math = @import("fr_core");
//! const Mat4 = math.Mat4;
//! pub fn main() !void {
//!     const m = Mat4.init(
//!         vec.Vec4.init(1.0, 2.0, 3.0, 4.0),
//!         vec.Vec4.init(5.0, 6.0, 7.0, 8.0),
//!         vec.Vec4.init(9.0, 10.0, 11.0, 12.0),
//!         vec.Vec4.init(13.0, 14.0, 15.0, 16.0),
//!     );
//!     const m2 = m.mul(&m);
//!     std.debug.print("m2: {any}\n", .{m2});
//! }
//! ```
// TODO:
//      - [ ] Benchmark
//      - [ ] Docstrings
//      - [ ] Write tests

pub const Mat2 = Mat2x2(f32);
pub const Mat3 = Mat3x3(f32);
pub const Mat4 = Mat4x4(f32);

pub fn Mat2x2(comptime backing_type: type) type {
    return extern struct {
        /// the backing data. For 2x2 the backing is stored as 2 column Vec2
        c: [shape[1]]ColT,

        pub const shape: [2]usize = .{ 2, 2 };
        pub const E = backing_type;
        pub const ColT = Vector2(E);
        pub const RowT = Vector2(E);

        pub const identity = Self.init(&ColT.init(1.0, 0.0), &ColT.init(0.0, 1.0));
        pub const zeros = Self.init(&ColT.init(0.0, 0.0), &ColT.init(0.0, 0.0));

        const Self = @This();

        /// Initialize a matrix from 2 column vectors.
        pub inline fn init(c0: *const ColT, c1: *const ColT) Self {
            return .{ .c = .{ c0.*, c1.* } };
        }

        /// Initialize a matrix from a slice of data.
        /// The data must be in column major order and must be at least 16 elements long.
        pub inline fn init_slice(data: []const E) Self {
            assert(data.len >= 4);
            return .{
                .c = .{
                    .{ .vec = .{ data[0], data[1] } },
                    .{ .vec = .{ data[2], data[3] } },
                },
            };
        }

        /// Create the transpose of the matrix.
        pub inline fn T(m: *const Self) Self {
            return .{ .c = .{
                .{ .vec = .{ m.c[0].x(), m.c[1].x() } },
                .{ .vec = .{ m.c[0].y(), m.c[1].y() } },
            } };
        }

        /// Multiply a matrix with a matrix on the left. This is the same as `m2 * m1`.
        /// This is the same as calling `m2.mul(m1)`.
        pub inline fn mul_left(m1: *const Self, m2: *const Self) Self {
            return m2.mul(m1);
        }

        /// Multiply a matrix with a scalar. This is the same as `m * s`.
        pub inline fn muls(m: *const Self, s: E) Self {
            return .{ .c = .{ m.c[0].muls(s), m.c[1].muls(s) } };
        }

        /// Multiply a vector with a matrix. This is the same as `v * m`.
        pub inline fn mulv(m: *const Self, v: *const ColT) ColT {
            return .{ .vec = .{
                m.c[0].vec[0] * v.x() + m.c[1].vec[0] * v.y(),
                m.c[0].vec[1] * v.x() + m.c[1].vec[1] * v.y(),
            } };
        }

        /// Multiply a matrix with a vector. This is the same as `m * v`.
        pub inline fn vmul(m: *const Self, v: *const ColT) ColT {
            return .{ .vec = .{
                m.c[0].dot(v),
                m.c[1].dot(v),
            } };
        }

        const Mixins = MatrixMixins(Self);

        pub const mul = Mixins.mul;
        pub const add = Mixins.add;
        pub const eql = Mixins.eql;
    };
}

pub fn Mat3x3(comptime backing_type: type) type {
    return extern struct {
        /// the backing data. For 3x3 the backing is stored as 3 column Vec3
        c: [shape[1]]ColT,

        pub const shape: [2]usize = .{ 3, 3 };
        pub const E = backing_type;
        pub const ColT = Vector3(E);
        pub const RowT = Vector3(E);

        const Self = @This();

        pub const identity = Self.init(
            &ColT.x_basis,
            &ColT.y_basis,
            &ColT.z_basis,
        );

        pub const zero = Self.init(
            &ColT.zeros,
            &ColT.zeros,
            &ColT.zeros,
        );

        /// Initialize a matrix from 3 column vectors.
        pub inline fn init(c1: *const ColT, c2: *const ColT, c3: *const ColT) Self {
            return .{ .c = .{ c1.*, c2.*, c3.* } };
        }

        /// Initialize a matrix from a slice of data.
        /// The data must be in column major order and must be at least 9 elements long.
        pub inline fn init_slice(data: []const E) Self {
            assert(data.len >= 9);
            return .{ .c = .{
                ColT.init_slice(data[0..3]),
                ColT.init_slice(data[3..6]),
                ColT.init_slice(data[6..9]),
            } };
        }

        /// Get the row vector of the matrix.
        pub inline fn row(m: *const Self, r: usize) RowT {
            assert(r < shape[0]);
            return .{ .vec = .{
                m.c[0].vec[r],
                m.c[1].vec[r],
                m.c[2].vec[r],
            } };
        }

        /// Get the column vector of the matrix.
        pub inline fn col(m: *const Self, c: usize) ColT {
            assert(c < shape[1]);
            return .{ .vec = m.c[c].vec };
        }

        /// Create the transpose of the matrix.
        pub inline fn T(m: *const Self) Self {
            return .{ .c = .{
                .{ .vec = .{ m.c[0].vec[0], m.c[1].vec[0], m.c[2].vec[0] } },
                .{ .vec = .{ m.c[0].vec[1], m.c[1].vec[1], m.c[2].vec[1] } },
                .{ .vec = .{ m.c[0].vec[2], m.c[1].vec[2], m.c[2].vec[2] } },
            } };
        }

        /// Compute M * v
        pub inline fn mulv(m: *const Self, vector: *const Vector3(E)) Vector3(E) {
            return vector.mat_mul(m);
        }

        /// Compute v * M
        pub inline fn vmul(m: *const Self, vector: *const Vector3(E)) Vector3(E) {
            return vector.mat_vmul(m);
        }

        const Mixins = MatrixMixins(Self);

        pub const mul = Mixins.mul;
        pub const add = Mixins.add;
        pub const eql = Mixins.eql;
    };
}

pub fn Mat4x4(comptime backing_type: type) type {
    return extern struct {
        /// the backing data. For 4x4 the backing is stored as 4 Vec4
        c: [shape[1]]ColT,

        pub const shape: [2]usize = .{ 4, 4 };
        pub const E = backing_type;
        pub const ColT = Vector4(E);
        pub const RowT = Vector4(E);
        pub const AffT = Affine(E);
        const V3 = Vector3(E);

        const Self = @This();

        /// Identity matrix
        pub const identity = Self.init(
            &ColT.x_basis,
            &ColT.y_basis,
            &ColT.z_basis,
            &ColT.w_basis,
        );

        pub const zero = Self.init(
            &ColT.zeros,
            &ColT.zeros,
            &ColT.zeros,
            &ColT.zeros,
        );

        /// Initialize a matrix from 4 column vectors.
        pub inline fn init(c1: *const ColT, c2: *const ColT, c3: *const ColT, c4: *const ColT) Self {
            return .{ .c = .{ c1.*, c2.*, c3.*, c4.* } };
        }

        /// Initialize a matrix from a slice of data.
        /// The data must be in column major order and must be at least 16 elements long.
        pub inline fn init_slice(data: []const E) Self {
            assert(data.len >= 16);
            return .{ .c = .{
                ColT.init_slice(data[0..4]),
                ColT.init_slice(data[4..8]),
                ColT.init_slice(data[8..12]),
                ColT.init_slice(data[12..16]),
            } };
        }

        /// Convert the matrix to an affine transformation.
        /// The matrix is assumed to be a TRS transformation and no checks are made to ensure this is the case.
        pub inline fn to_affine(self: *const Self) AffT {
            return @bitCast(self.*);
        }

        /// Create the transpose of the matrix.
        pub inline fn T(m: *const Self) Self {
            return .{ .c = .{
                .{ .vec = .{ m.c[0].vec[0], m.c[1].vec[0], m.c[2].vec[0], m.c[3].vec[0] } },
                .{ .vec = .{ m.c[0].vec[1], m.c[1].vec[1], m.c[2].vec[1], m.c[3].vec[1] } },
                .{ .vec = .{ m.c[0].vec[2], m.c[1].vec[2], m.c[2].vec[2], m.c[3].vec[2] } },
                .{ .vec = .{ m.c[0].vec[3], m.c[1].vec[3], m.c[2].vec[3], m.c[3].vec[3] } },
            } };
        }

        /// Compute M * v
        pub inline fn mulv(m: *const Self, vector: *const Vector4(E)) Vector4(E) {
            return vector.mat_mul(m);
        }

        /// Compute v * M
        pub inline fn vmul(m: *const Self, vector: *const Vector4(E)) Vector4(E) {
            return vector.mat_vmul(m);
        }

        /// Initialize an orthographic projection matrix.
        /// # Examples
        ///
        /// ```
        /// const math = @import("fr_core");
        /// const Mat4 = math.Mat4;
        /// pub fn main() !void {
        ///     const m = Mat4.orthographic(0.0, 100.0, 0.0, 100.0, 0.1, 100.0);
        ///     std.debug.print("m: {any}\n", .{m});
        /// }
        /// ```
        pub inline fn orthographic(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Self {
            const lr: f32 = 1.0 / (right - left);
            const bt: f32 = 1.0 / (top - bottom);
            const nf: f32 = 1.0 / (far - near);
            return .{
                .c = .{
                    .{ .vec = .{ 2.0 * lr, 0.0, 0.0, -(right + left) * lr } },
                    .{ .vec = .{ 1.0, 2.0 * bt, 0.0, -(top + bottom) * bt } },
                    .{ .vec = .{ 1.0, 0.0, 2.0 * nf, -(near + far) * nf } },
                    .{ .vec = .{ 1.0, 0.0, 0.0, 1.0 } },
                },
            };
        }

        /// Initialize a perspective projection matrix.
        /// # Examples
        ///
        /// ```
        /// const math = @import("fr_core");
        /// const Mat4 = math.Mat4;
        /// const Vec2 = math.Vec2;
        /// pub fn main() !void {
        ///     const window_size: Vec2 = .init(1920.0, 1080.0);
        ///     const aspect_ratio = window_size.x() / window_size.y();
        ///     const m = Mat4.perspective(math.pi / 4.0, aspect_ratio, 0.1, 100.0);
        ///     std.debug.print("m: {any}\n", .{m});
        /// }
        /// ```
        pub inline fn perspective(fov_rad: f32, aspect_ratio: f32, near_clip: f32, far_clip: f32) Self {
            // const inv_half_tan_fov = 1 / @tan(fov_rad * 0.5);
            const half_tan_fov = @tan(fov_rad * 0.5);
            // const nf = 1.0 / (near_clip - far_clip);
            return .{
                .c = .{
                    .{ .vec = .{ 1.0 / (aspect_ratio * half_tan_fov), 0.0, 0.0, 0.0 } },
                    .{ .vec = .{ 0.0, 1.0 / half_tan_fov, 0.0, 0.0 } },
                    .{ .vec = .{ 0.0, 0.0, -((far_clip + near_clip) / (far_clip - near_clip)), -1.0 } },
                    .{ .vec = .{ 0.0, 0.0, -(2.0 * near_clip * far_clip / (far_clip - near_clip)), 0.0 } },
                },
            };
        }

        /// Inverse of a matrix.
        pub inline fn inv(m: *const Self) Self {
            const Ty = Vector4(E).T;
            const c0 = m.c[0].vec;
            const c1 = m.c[1].vec;
            const c2 = m.c[2].vec;
            const c3 = m.c[3].vec;

            var e0 = @shuffle(Ty, c2, c3, [_]i32{ 2, 3, -3, -4 });
            var e1 = @shuffle(Ty, c2, c3, [_]i32{ 0, 1, ~@as(i32, 0), -2 });

            var e2 = @shuffle(Ty, e0, undefined, [_]i32{ 3, 3, 3, 1 });
            var e3 = @shuffle(Ty, e0, undefined, [_]i32{ 2, 2, 2, 0 });
            var e4 = @shuffle(Ty, e1, undefined, [_]i32{ 3, 3, 3, 1 });
            var e5 = @shuffle(Ty, e1, undefined, [_]i32{ 2, 2, 2, 0 });

            e0 = @shuffle(Ty, c1, c2, [_]i32{ -1, -1, 0, 0 });
            e1 = @shuffle(Ty, c1, c2, [_]i32{ -2, -2, 1, 1 });
            const e6 = @shuffle(Ty, c1, c2, [_]i32{ -3, -3, 2, 2 });
            const e7 = @shuffle(Ty, c1, c2, [_]i32{ -4, -4, 3, 3 });

            var d0 = e6 * e2;
            var d1 = e1 * e2;
            var d2 = e1 * e3;
            var d3 = e0 * e2;
            var d4 = e0 * e3;
            var d5 = e0 * e4;

            d0 -= e3 * e7;
            d1 -= e4 * e7;
            d2 -= e4 * e6;
            d3 -= e5 * e7;
            d4 -= e5 * e6;
            d5 -= e5 * e1;

            // 3x3 determinants
            e0 = @shuffle(Ty, c0, c1, [_]i32{ 2, 3, -3, -4 });
            e1 = @shuffle(Ty, c0, c1, [_]i32{ 0, 1, ~@as(i32, 0), -2 });

            e2 = @shuffle(Ty, e1, undefined, [_]i32{ 2, 0, 0, 0 });
            e3 = @shuffle(Ty, e1, undefined, [_]i32{ 3, 1, 1, 1 });
            e4 = @shuffle(Ty, e0, undefined, [_]i32{ 2, 0, 0, 0 });
            e5 = @shuffle(Ty, e0, undefined, [_]i32{ 3, 1, 1, 1 });

            var inv0 = e3 * d0;
            var inv1 = e2 * d0;
            var inv2 = e2 * d1;
            var inv3 = e2 * d2;

            inv0 -= e4 * d1;
            inv1 -= e4 * d3;
            inv2 -= e3 * d3;
            inv3 -= e3 * d4;

            inv0 += e5 * d2;
            inv1 += e5 * d4;
            inv2 += e5 * d5;
            inv3 += e4 * d5;

            const Vec4u = @Vector(4, u32);
            const mask: Vec4u = [_]u32{ 0.0, @bitCast(@as(u32, 0x80000000)), 0.0, @bitCast(@as(u32, 0x80000000)) };
            const inv_mask: Vec4u = [_]u32{ @bitCast(@as(u32, 0x80000000)), 0.0, @bitCast(@as(u32, 0x80000000)), 0.0 };

            inv0 = @as(Vector4(E).Simd, @bitCast(@as(Vec4u, @bitCast(inv0)) ^ mask));
            inv1 = @as(Vector4(E).Simd, @bitCast(@as(Vec4u, @bitCast(inv1)) ^ inv_mask));
            inv2 = @as(Vector4(E).Simd, @bitCast(@as(Vec4u, @bitCast(inv2)) ^ mask));
            inv3 = @as(Vector4(E).Simd, @bitCast(@as(Vec4u, @bitCast(inv3)) ^ inv_mask));

            e0 = @shuffle(Ty, inv0, inv1, [_]i32{ 0, 0, -1, -1 });
            e1 = @shuffle(Ty, inv2, inv3, [_]i32{ 0, 0, -1, -1 });
            e0 = @shuffle(Ty, e0, e1, [_]i32{ 0, 2, -1, -3 });

            e0 = @splat(1.0 / @reduce(.Add, e0 * c0));

            return .{
                .c = .{
                    .{ .vec = inv0 * e0 },
                    .{ .vec = inv1 * e0 },
                    .{ .vec = inv2 * e0 },
                    .{ .vec = inv3 * e0 },
                },
            };
        }

        const Mixins = MatrixMixins(Self);

        pub const mul = Mixins.mul;
        pub const add = Mixins.add;
        pub const eql = Mixins.eql;
    };
}

pub fn MatrixMixins(comptime MatT: type) type {
    return struct {
        /// Multiply two matrices. This is the same as `m1 * m2`.
        pub inline fn mul(m1: *const MatT, m2: *const MatT) MatT {
            // NOTE(aditya): The compiler is a better programmer than you will be
            @setEvalBranchQuota(10000);
            @setFloatMode(.optimized);
            var result: MatT = undefined;
            inline for (0..MatT.shape[0]) |r| {
                inline for (0..MatT.shape[1]) |c| {
                    var sum: MatT.E = 0.0;
                    inline for (0..MatT.RowT.dim) |i| {
                        sum += m1.c[i].vec[r] * m2.c[c].vec[i];
                    }
                    result.c[c].vec[r] = sum;
                }
            }
            return result;
        }

        /// Add two matrices. This is the same as `m1 + m2`.
        pub inline fn add(m1: *const MatT, m2: *const MatT) MatT {
            @setFloatMode(.optimized);
            var result: MatT = undefined;
            inline for (0..MatT.shape[1]) |c| {
                result.c[c] = m1.c[c].vec + m2.c[c].vec;
            }
            return result;
        }

        /// Check if two matrices are equal. For floats this function is only accurate for small float values in the matrix.
        pub inline fn eql(m1: *const MatT, m2: *const MatT) bool {
            inline for (0..MatT.shape[1]) |col| {
                if (!m1.c[col].eql(&m2.c[col])) {
                    return false;
                }
            }
            return true;
        }
    };
}

// test "inverse" {
//     const t = Mat4x4(f32).identity;
//     std.debug.print("Inv: {any}\n", .{t.inv()});
// }

const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const vec = @import("vec.zig");
const Vector2 = vec.Vector2;
const Vector3 = vec.Vector3;
const Vector4 = vec.Vector4;
const Affine = @import("affine.zig").Affine;
