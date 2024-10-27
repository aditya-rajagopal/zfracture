// TODO:
//      - [ ] Slerp
//      - [ ] Step function
//      - [ ] Smooth step and interpolation
pub const Component = enum { x, y, z, w };

pub fn Vec2(comptime backing_type: type) type {
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
        // pub const basis: Mat2x2(T) = Mat2x2(T).init(.{1.0, 0.0}, .{0.0, 1.0});

        pub inline fn init(_x: T, _y: T) Self {
            return .{ .vec = .{ _x, _y } };
        }

        pub inline fn x(self: *const Self) T {
            return self.vec[0];
        }

        pub inline fn y(self: *const Self) T {
            return self.vec[1];
        }

        pub inline fn swizzle(a: *const Self, x_comp: Component, y_comp: Component) Self {
            return .{ .vec = @shuffle(T, a.vec, undefined, [2]i32{ @intFromEnum(x_comp), @intFromEnum(y_comp) }) };
        }

        /// Transform a vec2 with a 3x3 trasform matrix of shape with m * v
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

        pub inline fn transform_pos(v: *const Self, m: *const Mat3x3(T)) Self {
            return .{ .vec = .{
                m.c[0].vec[0] * v.vec[0] + m.c[1].vec[0] * v.vec[1] + m.c[2].vec[0],
                m.c[0].vec[1] * v.vec[0] + m.c[1].vec[1] * v.vec[1] + m.c[3].vec[0],
            } };
        }

        pub inline fn transform_dir(v: *const Self, m: *const Mat3x3(T)) Self {
            return .{ .vec = .{
                m.c[0].vec[0] * v.vec[0] + m.c[1].vec[0] * v.vec[1],
                m.c[0].vec[1] * v.vec[0] + m.c[1].vec[1] * v.vec[1],
            } };
        }

        pub inline fn mul_mat(v: *const Self, m: *const Mat2x2(T)) Self {
            return .{ .vec = .{
                m.c[0].vec[0] * v.vec[0] + m.c[1].vec[0] * v.vec[1],
                m.c[0].vec[1] * v.vec[0] + m.c[1].vec[1] * v.vec[1],
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

pub fn Vec3(comptime backing_type: type) type {
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

        pub inline fn init(_x: T, _y: T, _z: T) Self {
            return .{ .vec = .{ _x, _y, _z } };
        }

        pub inline fn x(self: *const Self) T {
            return self.vec[0];
        }

        pub inline fn y(self: *const Self) T {
            return self.vec[1];
        }

        pub inline fn z(self: *const Self) T {
            return self.vec[2];
        }

        pub inline fn to_vec4w(self: *const Self, w: T) Vec4(T) {
            return .{ .vec = .{ self.vec[0], self.vec[1], self.vec[2], w } };
        }

        /// The last element will be set to 0
        pub inline fn to_vec4_dir(self: *const Self) Vec4(T) {
            return .{ .vec = .{ self.vec[0], self.vec[1], self.vec[2], 0.0 } };
        }

        pub inline fn to_vec4(self: *const Self) Vec4(T) {
            return .{ .vec = .{ self.vec[0], self.vec[1], self.vec[2], 1.0 } };
        }

        pub inline fn swizzle(a: *const Self, x_comp: Component, y_comp: Component, z_comp: Component) Self {
            return .{ .vec = @shuffle(
                T,
                a.vec,
                undefined,
                [3]i32{ @intFromEnum(x_comp), @intFromEnum(y_comp), @intFromEnum(z_comp) },
            ) };
        }

        pub inline fn splat_x(self: *const Self) Self {
            return self.swizzle(.x, .x, .x);
        }

        pub inline fn splat_y(self: *const Self) Self {
            return self.swizzle(.y, .y, .y);
        }

        pub inline fn splat_z(self: *const Self) Self {
            return self.swizzle(.z, .z, .z);
        }

        pub inline fn cross(v1: *const Self, v2: *const Self) Self {
            const x0 = v1.swizzle(.y, .z, .x);
            const x2 = x0.mul(v1).swizzle(.y, .z, .x);
            const x3 = x0.mul(&v2.swizzle(.z, .x, .y));
            return x3.sub(&x2);
        }

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
        pub inline fn transform(v: *const Self, m: *const AffT) Self {
            switch (builtin.mode) {
                .Debug => return v.transform_debug(m),
                else => return v.to_vec4().transform(m).to_vec3(),
            }
        }

        // TODO: Check on other processors if this is still much faster in Debug builds. 3.3sec for 400mil transforms
        // from 8sec
        // The conversion to vec4 and back to vec3 Is faster in release fast 0.20sec vs 0.32sec
        inline fn transform_debug(v: *const Self, m: *const AffT) Self {
            var result: Self = m.c[3].to_vec3();
            inline for (0..3) |r| {
                inline for (0..3) |c| {
                    result.vec[r] += v.vec[c] * m.c[c].vec[r];
                }
            }
            return result;
        }

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

pub fn Vec4(comptime backing_type: type) type {
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

        pub inline fn init(_x: T, _y: T, _z: T, _w: T) Self {
            return .{ .vec = .{ _x, _y, _z, _w } };
        }

        pub inline fn x(self: *const Self) T {
            return self.vec[0];
        }

        pub inline fn y(self: *const Self) T {
            return self.vec[1];
        }

        pub inline fn z(self: *const Self) T {
            return self.vec[2];
        }

        pub inline fn w(self: *const Self) T {
            return self.vec[3];
        }

        pub inline fn splat_x(self: *const Self) Self {
            return self.swizzle(.x, .x, .x, .x);
        }

        pub inline fn splat_y(self: *const Self) Self {
            return self.swizzle(.y, .y, .y, .y);
        }

        pub inline fn splat_z(self: *const Self) Self {
            return self.swizzle(.z, .z, .z, .z);
        }

        pub inline fn splat_w(self: *const Self) Self {
            return self.swizzle(.w, .w, .w, .w);
        }

        pub inline fn to_vec3(self: *const Self) Vec3(T) {
            return @bitCast(self.*);
        }

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
        pub const eqlApprox = Mixins.eqlApprox;
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

        pub inline fn init_slice(data: []const T) VecT {
            assert(data.len >= dim);
            return .{ .vec = data[0..dim].* };
        }

        pub inline fn init_array(data: VecT.Array) VecT {
            return .{ .vec = data };
        }

        pub inline fn to_array(a: *const VecT) VecT.Array {
            return a.vec;
        }

        pub inline fn to_slice(a: *const VecT, data: []T) void {
            assert(data.len >= dim);
            data[0..dim].* = a.vec;
        }

        pub inline fn add(a: *const VecT, b: *const VecT) VecT {
            return .{ .vec = a.vec + b.vec };
        }

        pub inline fn sub(a: *const VecT, b: *const VecT) VecT {
            return .{ .vec = a.vec - b.vec };
        }

        pub inline fn mul(a: *const VecT, b: *const VecT) VecT {
            return .{ .vec = a.vec * b.vec };
        }

        pub inline fn div(a: *const VecT, b: *const VecT) VecT {
            return .{ .vec = a.vec / b.vec };
        }

        pub inline fn splat(s: T) VecT {
            return .{ .vec = @splat(s) };
        }

        pub inline fn adds(a: *const VecT, s: T) VecT {
            return .{ .vec = a.vec + VecT.splat(s).vec };
        }
        pub inline fn subs(a: *const VecT, s: T) VecT {
            return .{ .vec = a.vec - VecT.splat(s).vec };
        }

        pub inline fn muls(a: *const VecT, s: T) VecT {
            return .{ .vec = a.vec * VecT.splat(s).vec };
        }

        pub inline fn divs(a: *const VecT, s: T) VecT {
            return .{ .vec = a.vec / VecT.splat(s).vec };
        }

        pub inline fn abs(a: *const VecT) VecT {
            return .{ .vec = @abs(a.vec) };
        }

        pub inline fn is_zero(a: *const VecT) bool {
            return a.eql(&VecT.zeros);
        }

        pub inline fn dot(a: *const VecT, b: *const VecT) T {
            return @reduce(.Add, a.vec * b.vec);
        }

        pub inline fn norm2(a: *const VecT) T {
            return switch (dim) {
                inline 2 => a.vec[0] * a.vec[0] + a.vec[1] * a.vec[1],
                inline 3, 4 => @reduce(.Add, a.vec * a.vec),
                else => @compileError("Type " ++ @typeName(VecT) ++ " not supported"),
            };
        }

        pub inline fn norm(a: *const VecT) T {
            return std.math.sqrt(a.norm2());
        }

        pub inline fn inv_norm(a: *const VecT) VecT {
            return VecT.ones.divs(a.norm());
        }

        pub inline fn normalize(a: *const VecT, delta: T) VecT {
            return a.divs(a.norm() + delta);
        }

        pub inline fn dist2(a: *const VecT, b: *const VecT) T {
            return a.sub(b).norm2();
        }

        pub inline fn dist(a: *const VecT, b: *const VecT) T {
            return a.sub(b).norm();
        }

        pub inline fn negate(a: *const VecT) VecT {
            return .{ .vec = -a.vec };
        }

        pub inline fn mid_point(a: *const VecT, b: *const VecT) VecT {
            return a.add(b).muls(0.5);
        }

        pub inline fn min(a: *const VecT, b: *const VecT) VecT {
            return .{ .vec = @min(a.vec, b.vec) };
        }

        pub inline fn max(a: *const VecT, b: *const VecT) VecT {
            return .{ .vec = @max(a.vec, b.vec) };
        }

        pub inline fn clamp(a: *const VecT, min_val: T, max_val: T) VecT {
            return .{ .vec = std.math.clamp(a.vec, VecT.splat(min_val).vec, VecT.splat(max_val).vec) };
        }

        pub inline fn clamp01(a: *const VecT) VecT {
            return a.clamp(0.0, 1.0);
        }

        /// Returns a.fmadd(&b, &c) => a * b + c
        pub inline fn fmadd(a: *const VecT, b: *const VecT, c: *const VecT) VecT {
            if (comptime is_float) {
                return @mulAdd(VecT.Simd, a, b, c);
            } else {
                return a.mul(b).add(c);
            }
        }

        /// Returns a.fmadd2(&b, &c) => a + b * c
        pub inline fn fmadd2(a: *const VecT, b: *const VecT, c: *const VecT) VecT {
            if (comptime is_float) {
                return @mulAdd(VecT.Simd, b, c, a);
            } else {
                return b.mul(c).add(a);
            }
        }

        pub inline fn lerp(a: *const VecT, b: *const VecT, t: f32) VecT {
            if (comptime is_float) {
                return .{ .vec = std.math.lerp(a.vec, b.vec, VecT.splat(t).vec) };
            } else {
                @compileError("Cant use lerp for Integer Vector types");
            }
        }

        pub inline fn lerp_clamped(a: *const VecT, b: *const VecT, t: f32) VecT {
            if (comptime is_float) {
                const amount = std.math.clamp(t, 0.0, 1.0);
                return a.lerp(b, amount);
            } else {
                @compileError("Cant use lerp for Integer Vector types");
            }
        }

        pub inline fn project(a: *const VecT, b: *const VecT) VecT {
            const unit = a.normalize(0.00000001);
            const proj = a.dot(b);
            return unit.muls(proj);
        }

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
            const xmm0 = @abs(a.vec - b.vec);
            const mask = xmm0 < VecT.splat(tolarance).vec;
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

        // TODO: Should there be approximate versions of these?
        pub inline fn less(a: *const VecT, b: *const VecT) bool {
            return @reduce(.And, a.vec < b.vec);
        }

        pub inline fn less_eq(a: *const VecT, b: *const VecT) bool {
            return @reduce(.And, a.vec <= b.vec);
        }

        pub inline fn greater_eq(a: *const VecT, b: *const VecT) bool {
            return @reduce(.And, a.vec >= b.vec);
        }

        pub inline fn greater(a: *const VecT, b: *const VecT) bool {
            return @reduce(.And, a.vec > b.vec);
        }
    };
}

test Vec4 {
    const v = Vec3(f32).init(1.0, 0.0, 0.0);
    const rot = Affine(f32).init_rot_z(std.math.pi / 2.0);
    const translate = Affine(f32).init_trans(&Vec3(f32).init(0.0, 1.0, 0.0));
    const transform = rot.mul(&translate);
    // const transform = translate.mul(&rot);
    std.debug.print("Transform: {any}\n", .{transform});
    std.debug.print("Vector: {any}\n", .{v.transform_dir(&transform)});
    std.debug.print("Vector: {any}\n", .{transform.transform_dir(&v)});
    // std.debug.print("Vector: {any}\n", .{v.transform_dir_debug(&transform)});
}

const Affine = @import("affine.zig").Affine;
const matrix = @import("matrix.zig");
const Mat2x2 = matrix.Mat2x2;
const Mat3x3 = matrix.Mat3x3;
const Mat4x4 = matrix.Mat4x4;
const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
