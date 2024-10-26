pub fn Mat2x2(comptime backing_type: type) type {
    return extern struct {
        /// the backing data. For 2x2 the backing is stored as a column major Vec4
        c: [shape[1]]ColT,

        pub const Backing = Vec4(backing_type);
        pub const shape: [2]usize = .{ 2, 2 };
        pub const E = backing_type;
        pub const ColT = Vec2(E);
        pub const RowT = Vec2(E);

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

        // TODO: Check benchmark with naive implementation
        // Again the inline for loop implementation wins out even though this should be "smarter"
        // NOTE(aditya): Again the compiler is a better programmer than you will ever be
        //
        // pub inline fn mul(m1: *const Self, m2: *const Self) Self {
        //     const x0 = m2.c.swizzle(.x, .x, .w, .w);
        //     const x1 = m2.c.swizzle(.y, .y, .z, .z);
        //     const x2 = m1.c.swizzle(.z, .w, .x, .y);
        //     return .{ .c = x0.mul(&m1.c).add(&x1.mul(&x2)) };
        // }

        pub inline fn mul(m1: *const Self, m2: *const Self) Self {
            @setFloatMode(.optimized);
            var result: Self = undefined;
            inline for (0..RowT.dim) |row| {
                inline for (0..ColT.dim) |col| {
                    var sum: E = 0.0;
                    inline for (0..RowT.dim) |i| {
                        sum += m1.c[i].vec[row] * m2.c[col].vec[i];
                    }
                    result.c[col].vec[row] = sum;
                }
            }
            return result;
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
    };
}

pub fn Mat3x3(comptime backing_type: type) type {
    return extern struct {
        c: [shape[1]]ColT,

        pub const shape: [2]usize = .{ 3, 3 };
        pub const E = backing_type;
        pub const ColT = Vec3(E);
        pub const RowT = Vec3(E);

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

        pub inline fn mul(m1: *const Self, m2: *const Self) Self {
            @setFloatMode(.optimized);
            var result: Self = undefined;
            inline for (0..shape[0]) |r| {
                inline for (0..shape[1]) |c| {
                    var sum: E = 0.0;
                    inline for (0..RowT.dim) |i| {
                        sum += m1.c[i].vec[r] * m2.c[c].vec[i];
                    }
                    result.c[c].vec[r] = sum;
                }
            }
            return result;
        }
    };
}

pub fn Mat4x4(comptime backing_type: type) type {
    return extern struct {
        c: [shape[1]]ColT,

        pub const shape: [2]usize = .{ 4, 4 };
        pub const E = backing_type;
        pub const ColT = Vec4(E);
        pub const RowT = Vec4(E);
        pub const AffT = Affine(E);
        const V3 = Vec3(E);

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

        // NOTE(aditya): The compiler is a better programmer than you will be
        pub inline fn mul(m1: *const Self, m2: *const Self) Self {
            @setFloatMode(.optimized);
            var result: Self = undefined;
            inline for (0..shape[0]) |r| {
                inline for (0..shape[1]) |c| {
                    var sum: E = 0.0;
                    inline for (0..RowT.dim) |i| {
                        sum += m1.c[i].vec[r] * m2.c[c].vec[i];
                    }
                    result.c[c].vec[r] = sum;
                }
            }
            return result;
        }
    };
}

const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const vec = @import("vec.zig");
const Vec2 = vec.Vec2;
const Vec3 = vec.Vec3;
const Vec4 = vec.Vec4;
const Affine = @import("affine.zig").Affine;
