const math = @import("math.zig");

const max_float: f64 = @floatFromInt(std.math.maxInt(u64));

pub fn main() void {
    @setFloatMode(.optimized);
    var xor = std.Random.DefaultPrng.init(0);
    var rand = xor.random();

    const vec = math.vec4s(rand.float(f32), rand.float(f32), rand.float(f32), rand.float(f32));
    const vec2 = math.vec4s(rand.float(f32), rand.float(f32), rand.float(f32), rand.float(f32));

    const vec3 = vec.normalize(0);
    const vec4 = vec2.negate();
    std.debug.print("{any}, {any}\n", .{ vec3, vec4 });
}

const std = @import("std");
