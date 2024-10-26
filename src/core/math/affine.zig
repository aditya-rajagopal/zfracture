pub fn Affine(comptime backing_type: type) type {
    return extern struct {
        c: [shape[1]]ColT,

        pub const shape: [2]usize = .{ 4, 4 };
        pub const E = backing_type;
        pub const ColT = Vec4(E);
        pub const RowT = Vec4(E);
        pub const MatT = Mat4x4(E);
        const V3 = Vec3(E);

        const Self = @This();

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

        pub inline fn init_trans(delta: *const V3) Self {
            return .{
                .c = .{
                    .{ .vec = .{ 1.0, 0.0, 0.0, 0.0 } },
                    .{ .vec = .{ 0.0, 1.0, 0.0, 0.0 } },
                    .{ .vec = .{ 0.0, 0.0, 1.0, 0.0 } },
                    .{ .vec = .{ delta.x(), delta.y(), delta.z(), 1.0 } },
                },
            };
        }

        pub inline fn init_scale(scale: *const V3) Self {
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

        pub inline fn init_rot_x(angle_rad: E) Self {
            const c = @cos(angle_rad);
            const s = @sin(angle_rad);
            return .{
                .c = .{
                    .{ .vec = .{ 1.0, 0.0, 0.0, 0.0 } },
                    .{ .vec = .{ 0.0, c, -s, 0.0 } },
                    .{ .vec = .{ 0.0, s, c, 0.0 } },
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
                    .{ .vec = .{ c, -s, 0.0, 0.0 } },
                    .{ .vec = .{ s, c, 0.0, 0.0 } },
                    .{ .vec = .{ 0.0, 0.0, 1.0, 0.0 } },
                    .{ .vec = .{ 0.0, 0.0, 0.0, 1.0 } },
                },
            };
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

const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const vec = @import("vec.zig");
const Vec3 = vec.Vec3;
const Vec4 = vec.Vec4;
const Mat4x4 = @import("matrix.zig").Mat4x4;
