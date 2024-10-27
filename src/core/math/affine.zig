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

        pub inline fn to_mat(t: *const Self) MatT {
            return @bitCast(t.*);
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
                        .{ .vec = .{ tv.x() * axis_n.z() + sv.y(), tv.y() * axis_n.z() - sv.x(), tv.z() * axis_n.z() + c, 1.0 } },
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
                    .{ .vec = .{ 0.0, 0.0, -(far_clip + near_clip) * nf, -2.0 * near_clip * far_clip * nf } },
                    .{ .vec = .{ 0.0, 0.0, -1.0, 0.0 } },
                },
            };
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
    };
}

// test Affine {
//     const Transform = Affine(f32);
//     const t = Transform.init_rotation(&Vec3(f32).init(0.678597, 0.28109, 0.678597), 1.49750);
//     std.debug.print("Rotation: {any}\n", .{t});
//     const v3 = Vec3(f32).init(1, 2, 3);
//     const vec4: Vec4(f32) = @bitCast(v3);
//     std.debug.print("Vec3: {any}\n", .{v3.to_vec4()});
//     std.debug.print("Vec3: {any}\n", .{vec4});
//     // std.debug.print("Rotation: {any}\n", .{t.T().mul(&t)});
// }

const pi = std.math.pi;

const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const vec = @import("vec.zig");
const Mat4x4 = @import("matrix.zig").Mat4x4;
