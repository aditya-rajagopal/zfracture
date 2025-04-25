// TODO:
//      - [ ] Benchmark
//      - [ ] Docstrings
//      - [ ] Write tests

pub const Mat2 = Mat2x2(f32);
pub const Mat3 = Mat3x3(f32);
pub const Mat4 = Mat4x4(f32);

pub fn Mat2x2(comptime backing_type: type) type {
    return extern struct {
        /// the backing data. For 2x2 the backing is stored as a column major Vec4
        c: [shape[1]]ColT,

        pub const Backing = Vector4(backing_type);
        pub const shape: [2]usize = .{ 2, 2 };
        pub const E = backing_type;
        pub const ColT = Vector2(E);
        pub const RowT = Vector2(E);

        pub const identity = Self.init(&ColT.init(1.0, 0.0), &ColT.init(0.0, 1.0));
        pub const zeros = Self.init(&ColT.init(0.0, 0.0), &ColT.init(0.0, 0.0));

        const Self = @This();

        pub inline fn init(c0: *const ColT, c1: *const ColT) Self {
            return .{ .c = .{ c0.*, c1.* } };
        }

        pub inline fn init_slice(data: []const E) Self {
            assert(data.len >= 4);
            return .{
                .c = .{
                    .{ .vec = .{ data[0], data[1] } },
                    .{ .vec = .{ data[2], data[3] } },
                },
            };
        }

        pub inline fn T(m: *const Self) Self {
            return .{ .c = .{
                .{ .vec = .{ m.c[0].x(), m.c[1].x() } },
                .{ .vec = .{ m.c[0].y(), m.c[1].y() } },
            } };
        }

        pub inline fn mul_left(m1: *const Self, m2: *const Self) Self {
            return m2.mul(m1);
        }

        pub inline fn muls(m: *const Self, s: E) Self {
            return .{ .c = m.c.muls(s) };
        }

        pub inline fn mulv(m: *const Self, v: *const ColT) ColT {
            return .{ .vec = .{
                m.c[0].vec[0] * v.x() + m.c[1].vec[0] * v.y(),
                m.c[0].vec[1] * v.x() + m.c[1].vec[1] * v.y(),
            } };
        }

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

        pub inline fn init(c1: *const ColT, c2: *const ColT, c3: *const ColT) Self {
            return .{ .c = .{ c1.*, c2.*, c3.* } };
        }

        pub inline fn init_slice(data: []const E) Self {
            assert(data.len >= 9);
            return .{ .c = .{
                ColT.init_slice(data[0..3]),
                ColT.init_slice(data[3..6]),
                ColT.init_slice(data[6..9]),
            } };
        }

        pub inline fn row(m: *const Self, r: usize) RowT {
            assert(r < shape[0]);
            return .{ .vec = .{
                m.c[0].vec[r],
                m.c[1].vec[r],
                m.c[2].vec[r],
            } };
        }

        pub inline fn col(m: *const Self, c: usize) ColT {
            assert(c < shape[1]);
            return .{ .vec = m.c[c].vec };
        }

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
        c: [shape[1]]ColT,

        pub const shape: [2]usize = .{ 4, 4 };
        pub const E = backing_type;
        pub const ColT = Vector4(E);
        pub const RowT = Vector4(E);
        pub const AffT = Affine(E);
        const V3 = Vector3(E);

        const Self = @This();

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

        pub inline fn init(c1: *const ColT, c2: *const ColT, c3: *const ColT, c4: *const ColT) Self {
            return .{ .c = .{ c1.*, c2.*, c3.*, c4.* } };
        }

        pub inline fn init_slice(data: []const E) Self {
            assert(data.len >= 16);
            return .{ .c = .{
                ColT.init_slice(data[0..4]),
                ColT.init_slice(data[4..8]),
                ColT.init_slice(data[8..12]),
                ColT.init_slice(data[12..16]),
            } };
        }

        pub inline fn to_affine(self: *const Self) AffT {
            return @bitCast(self.*);
        }

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

        /// Inverse
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
        // NOTE(aditya): The compiler is a better programmer than you will be
        pub inline fn mul(m1: *const MatT, m2: *const MatT) MatT {
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

        pub inline fn add(m1: *const MatT, m2: *const MatT) MatT {
            @setFloatMode(.optimized);
            var result: MatT = undefined;
            inline for (0..MatT.shape[1]) |c| {
                result.c[c] = m1.c[c].vec + m2.c[c].vec;
            }
            return result;
        }

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
