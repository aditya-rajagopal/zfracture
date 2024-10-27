pub fn Affine(comptime backing_type: type) type {
    return extern struct {
        c: [shape[1]]ColT,

        const Vec3 = vec.Vec3(E);
        const Vec4 = vec.Vec4(E);

        pub const shape: [2]usize = .{ 4, 4 };
        pub const E = backing_type;
        pub const ColT = Vec4;
        pub const RowT = Vec4;
        pub const MatT = Mat4x4(E);

        const Self = @This();

        pub const identity: Self = @bitCast(MatT.identity);

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

        pub inline fn T(m: *const Self) Self {
            return .{ .c = .{
                .{ .vec = .{ m.c[0].vec[0], m.c[1].vec[0], m.c[2].vec[0], m.c[3].vec[0] } },
                .{ .vec = .{ m.c[0].vec[1], m.c[1].vec[1], m.c[2].vec[1], m.c[3].vec[1] } },
                .{ .vec = .{ m.c[0].vec[2], m.c[1].vec[2], m.c[2].vec[2], m.c[3].vec[2] } },
                .{ .vec = .{ m.c[0].vec[3], m.c[1].vec[3], m.c[2].vec[3], m.c[3].vec[3] } },
            } };
        }

        pub inline fn mul(m1: *const Self, m2: *const Self) Self {
            switch (builtin.mode) {
                .Debug => return m1.mul_debug(m2),
                else => return m1.mul_fast(m2),
            }
        }

        pub inline fn transform(m: *const Self, v: *const Vec4) Vec4 {
            return v.transform(m);
        }

        pub inline fn transform_dir(m: *const Self, v: *const Vec3) Vec3 {
            return v.transform_dir(m);
        }

        pub inline fn transform_pos(m: *const Self, v: *const Vec3) Vec3 {
            return v.transform(m);
        }

        pub inline fn to_mat(t: *const Self) MatT {
            return @bitCast(t.*);
        }

        pub inline fn init_trans(delta: *const Vec3) Self {
            return .{
                .c = .{
                    .{ .vec = .{ 1.0, 0.0, 0.0, 0.0 } },
                    .{ .vec = .{ 0.0, 1.0, 0.0, 0.0 } },
                    .{ .vec = .{ 0.0, 0.0, 1.0, 0.0 } },
                    .{ .vec = .{ delta.x(), delta.y(), delta.z(), 1.0 } },
                },
            };
        }

        pub inline fn init_scale(scale: *const Vec3) Self {
            return .{
                .c = .{
                    .{ .vec = .{ scale.x(), 0.0, 0.0, 0.0 } },
                    .{ .vec = .{ 0.0, scale.y(), 0.0, 0.0 } },
                    .{ .vec = .{ 0.0, 0.0, scale.z(), 0.0 } },
                    .{ .vec = .{ 0.0, 0.0, 0.0, 1.0 } },
                },
            };
        }

        pub inline fn init_scale_s(scale: E) Self {
            return .{
                .c = .{
                    .{ .vec = .{ scale, 0.0, 0.0, 0.0 } },
                    .{ .vec = .{ 0.0, scale, 0.0, 0.0 } },
                    .{ .vec = .{ 0.0, 0.0, scale, 0.0 } },
                    .{ .vec = .{ 0.0, 0.0, 0.0, 1.0 } },
                },
            };
        }

        pub inline fn init_rotation(axis: *const Vec3, angle: E) Self {
            const c = @cos(angle);
            const s = @sin(angle);
            const t = 1 - c;
            const axis_n = axis.normalize(0.00000001).to_vec4();
            const tv = axis_n.muls(t);
            const sv = axis_n.muls(s);

            switch (builtin.mode) {
                .Debug => {
                    return .{ .c = .{
                        .{ .vec = .{ tv.x() * axis_n.x() + c, tv.y() * axis_n.x() + sv.z(), tv.z() * axis_n.x() - sv.y(), 0.0 } },
                        .{ .vec = .{ tv.x() * axis_n.y() - sv.z(), tv.y() * axis_n.y() + c, tv.z() * axis_n.y() + sv.x(), 0.0 } },
                        .{ .vec = .{ tv.x() * axis_n.z() + sv.y(), tv.y() * axis_n.z() - sv.x(), tv.z() * axis_n.z() + c, 0.0 } },
                        .{ .vec = .{ 0.0, 0.0, 0.0, 1.0 } },
                    } };
                },
                else => {
                    const x = axis_n.mul(&ColT.splat(tv.x()));
                    const y = axis_n.mul(&ColT.splat(tv.y()));
                    const z = axis_n.mul(&ColT.splat(tv.z()));

                    return .{ .c = .{
                        x.add(&ColT.init(c, sv.z(), -sv.y(), 0.0)),
                        y.add(&ColT.init(-sv.z(), c, sv.x(), 0.0)),
                        z.add(&ColT.init(sv.y(), -sv.x(), c, 0.0)),
                        .{ .vec = .{ 0.0, 0.0, 0.0, 1.0 } },
                    } };
                }
            }
        }

        // TODO: This seems to be faster in debug builds for multiplying only rotation matrices
        // Figure out why this is is slower in release builds
        pub inline fn mul_rot(m1: *const Self, m2: *const Self) Self {
            // switch (builtin.mode) {
            //     .Debug => {
            var result: Self = Self.identity;
            inline for (0..shape[0] - 1) |r| {
                inline for (0..shape[1] - 1) |c| {
                    var sum: E = 0.0;
                    inline for (0..RowT.dim) |i| {
                        sum += m1.c[i].vec[r] * m2.c[c].vec[i];
                    }
                    result.c[c].vec[r] = sum;
                }
            }
            result.c[3] = m1.c[3];
            return result;
            //     },
            //     else => return m1.mul_fast(m2),
            // }
        }

        pub inline fn init_rot_x(angle_rad: E) Self {
            const c = @cos(angle_rad);
            const s = @sin(angle_rad);
            return .{
                .c = .{
                    .{ .vec = .{ 1.0, 0.0, 0.0, 0.0 } },
                    .{ .vec = .{ 0.0, c, s, 0.0 } },
                    .{ .vec = .{ 0.0, -s, c, 0.0 } },
                    .{ .vec = .{ 0.0, 0.0, 0.0, 1.0 } },
                },
            };
        }

        pub inline fn init_rot_y(angle_rad: E) Self {
            const c = @cos(angle_rad);
            const s = @sin(angle_rad);
            return .{
                .c = .{
                    .{ .vec = .{ c, 0.0, -s, 0.0 } },
                    .{ .vec = .{ 0.0, 1.0, 0.0, 0.0 } },
                    .{ .vec = .{ s, 0.0, c, 0.0 } },
                    .{ .vec = .{ 0.0, 0.0, 0.0, 1.0 } },
                },
            };
        }

        pub inline fn init_rot_z(angle_rad: E) Self {
            const c = @cos(angle_rad);
            const s = @sin(angle_rad);
            return .{
                .c = .{
                    .{ .vec = .{ c, s, 0.0, 0.0 } },
                    .{ .vec = .{ -s, c, 0.0, 0.0 } },
                    .{ .vec = .{ 0.0, 0.0, 1.0, 0.0 } },
                    .{ .vec = .{ 0.0, 0.0, 0.0, 1.0 } },
                },
            };
        }

        pub inline fn init_rot_xyz(x_rad: E, y_rad: E, z_rad: E) Self {
            return Self.init_rot_x(x_rad).mul(&Self.init_rot_y(y_rad)).mul(&Self.init_rot_z(z_rad));
        }

        pub inline fn init_pivot_rotation(pivot: *const Vec3, axis: *const Vec3, angle: E) Self {
            return Self.init_trans(pivot)
                .mul(&Self.init_rotation(axis, angle))
                .mul(Self.init_trans(&pivot.negate()));
        }

        pub inline fn get_forward(m: *const Self) Vec3 {
            const forward: Vec3 = .{ .vec = .{ -m.c[0].vec[2], -m.c[1].vec[2], -m.c[2].vec[2] } };
            return forward.normalize(0.00000001);
        }

        pub inline fn get_backward(m: *const Self) Vec3 {
            const backward: Vec3 = .{ .vec = .{ m.c[0].vec[2], m.c[1].vec[2], m.c[2].vec[2] } };
            return backward.normalize(0.00000001);
        }

        pub inline fn get_up(m: *const Self) Vec3 {
            const up: Vec3 = .{ .vec = .{ m.c[0].vec[1], m.c[1].vec[1], m.c[2].vec[1] } };
            return up.normalize(0.00000001);
        }

        pub inline fn get_down(m: *const Self) Vec3 {
            const down: Vec3 = .{ .vec = .{ -m.c[0].vec[1], -m.c[1].vec[1], -m.c[2].vec[1] } };
            return down.normalize(0.00000001);
        }

        pub inline fn get_left(m: *const Self) Vec3 {
            const left: Vec3 = .{ .vec = .{ -m.c[0].vec[0], -m.c[1].vec[0], -m.c[2].vec[0] } };
            return left.normalize(0.00000001);
        }

        pub inline fn get_right(m: *const Self) Vec3 {
            const right: Vec3 = .{ .vec = .{ m.c[0].vec[0], m.c[1].vec[0], m.c[2].vec[0] } };
            return right.normalize(0.00000001);
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
            const inv_half_tan_fov = 1 / @tan(fov_rad * 0.5);
            const nf = 1.0 / (near_clip - far_clip);
            return .{
                .c = .{
                    .{ .vec = .{ inv_half_tan_fov / aspect_ratio, 0.0, 0.0, 0.0 } },
                    .{ .vec = .{ 0.0, inv_half_tan_fov, 0.0, 0.0 } },
                    .{ .vec = .{ 0.0, 0.0, -((far_clip + near_clip) * nf), -1.0 } },
                    .{ .vec = .{ 0.0, 0.0, -2.0 * near_clip * far_clip * nf, 0.0 } },
                },
            };
        }

        /// Calculate the look at matrix in the right handed co-ordinate system
        pub inline fn look_at(pos: *const Vec3, target: *const Vec3, up: *const Vec3) Self {
            const z_axis = target.sub(pos).normalize(0.00000001);
            const x_axis = z_axis.cross(up).normalize(0.00000001);
            const y_axis = x_axis.cross(z_axis);

            return .{
                .c = .{
                    .{ .vec = .{ x_axis.x(), y_axis.x(), -z_axis.x(), 0.0 } },
                    .{ .vec = .{ x_axis.y(), y_axis.y(), -z_axis.y(), 0.0 } },
                    .{ .vec = .{ x_axis.z(), y_axis.z(), -z_axis.z(), 0.0 } },
                    .{ .vec = .{ -x_axis.dot(pos), -y_axis.dot(pos), -z_axis.dot(pos), 1.0 } },
                },
            };
        }

        pub inline fn inv_tr(m: *const Self) Self {
            var rot_mat = m.*;
            rot_mat.c[3].vec = Vec4.w_basis.vec;
            rot_mat = rot_mat.T();

            var x = m.c[3].splat_x();
            var y = m.c[3].splat_y();
            var z = m.c[3].splat_z();

            x = rot_mat.c[0].mul(&x);
            y = rot_mat.c[1].mul(&y);
            z = rot_mat.c[2].mul(&z);
            rot_mat.c[3].vec -= (x.vec + y.vec + z.vec);
            // const x = m.c[3].splat_x();
            // const y = m.c[3].splat_y();
            // const z = m.c[3].splat_z();
            // var trans = rot_mat.c[0].mul(&x);
            // trans = rot_mat.c[1].fmadd(&y, &trans);
            // trans = rot_mat.c[2].fmadd(&z, &trans);
            // trans = trans.negate();
            // trans = trans.add(&rot_mat.c[3]);
            //
            // rot_mat.c[3] = trans;

            return rot_mat;
        }

        pub inline fn inv_trs(m: *const Self, scale: *const Vec3) Self {
            var rot_mat = m.*;
            const inv_scale = Vec3.ones.div(&scale.mul(scale));
            rot_mat.c[0] = rot_mat.c[0].mul(&inv_scale.splat_x().to_vec4_dir());
            rot_mat.c[1] = rot_mat.c[1].mul(&inv_scale.splat_y().to_vec4_dir());
            rot_mat.c[2] = rot_mat.c[2].mul(&inv_scale.splat_z().to_vec4_dir());

            rot_mat.c[3].vec = Vec4.w_basis.vec;
            rot_mat = rot_mat.T();

            var x = m.c[3].splat_x();
            var y = m.c[3].splat_y();
            var z = m.c[3].splat_z();

            x = rot_mat.c[0].mul(&x);
            y = rot_mat.c[1].mul(&y);
            z = rot_mat.c[2].mul(&z);
            rot_mat.c[3].vec -= (x.vec + y.vec + z.vec);
            // var trans = rot_mat.c[0].mul(&x);
            // trans = rot_mat.c[1].fmadd(&y, &trans);
            // trans = rot_mat.c[2].fmadd(&z, &trans);
            // trans = trans.negate();
            // trans = trans.add(&rot_mat.c[3]);
            //
            // rot_mat.c[3] = trans;

            return rot_mat;
        }

        // TODO: This seems to be faster in debug builds for multiplying only rotation matrices
        // Figure out why this is is slower in release builds
        // pub inline fn mul_rot(m1: *const Self, m2: *const Self) Self {
        //     // switch (builtin.mode) {
        //     //     .Debug => {
        //     var result: Self = Self.identity;
        //     inline for (0..shape[0] - 1) |r| {
        //         inline for (0..shape[1] - 1) |c| {
        //             var sum: E = 0.0;
        //             inline for (0..RowT.dim) |i| {
        //                 sum += m1.c[i].vec[r] * m2.c[c].vec[i];
        //             }
        //             result.c[c].vec[r] = sum;
        //         }
        //     }
        //     result.c[3] = m1.c[3];
        //     return result;
        //     //     },
        //     //     else => return m1.mul_fast(m2),
        //     // }
        // }

        inline fn mul_fast(m1: *const Self, m2: *const Self) Self {
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

        pub inline fn inv(m: *const Self) Self {
            const Ty = Vec4.T;
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

            inv0 = @as(Vec4.Simd, @bitCast(@as(Vec4u, @bitCast(inv0)) ^ mask));
            inv1 = @as(Vec4.Simd, @bitCast(@as(Vec4u, @bitCast(inv1)) ^ inv_mask));
            inv2 = @as(Vec4.Simd, @bitCast(@as(Vec4u, @bitCast(inv2)) ^ mask));
            inv3 = @as(Vec4.Simd, @bitCast(@as(Vec4u, @bitCast(inv3)) ^ inv_mask));

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

        inline fn mul_debug(m1: *const Self, m2: *const Self) Self {
            @setFloatMode(.optimized);
            var result: Self = undefined;
            inline for (0..shape[0] - 1) |r| {
                inline for (0..shape[1]) |c| {
                    var sum: E = 0.0;
                    inline for (0..RowT.dim) |i| {
                        sum += m1.c[i].vec[r] * m2.c[c].vec[i];
                    }
                    result.c[c].vec[r] = sum;
                }
            }
            result.c[0].vec[3] = 0.0;
            result.c[1].vec[3] = 0.0;
            result.c[2].vec[3] = 0.0;
            result.c[3].vec[3] = 1.0;
            return result;
        }

        pub inline fn eql(m1: *const Self, m2: *const Self) bool {
            inline for (0..Self.shape[1]) |col| {
                if (!m1.c[col].eql(&m2.c[col])) {
                    return false;
                }
            }
            return true;
        }

        pub inline fn eql_approx(m1: *const Self, m2: *const Self, tolerance: f32) bool {
            inline for (0..Self.shape[1]) |col| {
                if (!m1.c[col].eql_approx(&m2.c[col], tolerance)) {
                    return false;
                }
            }
            return true;
        }
    };
}

test Affine {
    // const Transform = Affine(f32);
    // const s1 = vec.Vec3(f32).init(1.5, 2.2, 1.3);
    // const s2 = vec.Vec3(f32).init(1.5, 2.2, 1.3);
    // const t = Transform
    //     .init_rotation(&vec.Vec3(f32).init(0.678597, 0.28109, 0.678597), 1.49750)
    //     .mul(&Transform.init_scale(&s1))
    //     .mul(&Transform.init_trans(&vec.Vec3(f32).init(2.0, 1.0, 3.0)))
    //     .mul(&Transform.init_scale(&s2));
    // const s3 = s1.mul(&s2);
    //
    // std.debug.print("Rotation: {any}\n\n", .{t});
    // std.debug.print("Inv: {any}\n\n", .{t.inv_trs(&s3)});
    // std.debug.print("Float accuracy: {d}\n\n", .{std.math.floatEps(f32)});
    // std.debug.print("mul: {any}\n\n\n", .{t.mul(&t.inv_trs(&s3))});
    // std.debug.print("mul: {any}\n\n\n", .{t.mul(&t.inv_trs(&s3)).eql_approx(&Transform.identity, 0.000001)});
    // const v3 = vec.Vec3(f32).init(1, 2, 3);
    // const vec4: vec.Vec4(f32) = @bitCast(v3);

    // std.debug.print("Forward: {any}, {d}\n", .{ t.get_forward(), t.get_forward().norm() });
    // std.debug.print("Rotation: {any}\n", .{t.T().mul(&t)});
    // const t = Transform.init_slice(&.{
    //     1.0,  2.0,  3.0,  4.0,
    //     2.0,  6.0,  7.0,  7.0,
    //     9.0,  10.0, 11.0, 12.0,
    //     13.0, 14.0, 15.0, 11.0,
    // });
    // // const t = Transform.identity;
    // std.debug.print("t: {any}\n", .{t.inv().mul(&t)});
    // std.debug.print("t: {any}\n", .{t.inv().mul(&t).eql_approx(&Transform.identity, 1.19e-7)});
}

const pi = std.math.pi;

const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const vec = @import("vec.zig");
const Mat4x4 = @import("matrix.zig").Mat4x4;
