const math = @import("math.zig");
const max_float: f64 = @floatFromInt(std.math.maxInt(u64));

pub fn main() !void {
    // try benchmark_mat2();
    // try benchmark_mat4();
    // try benchmark_affine();
    // try benchmark_cross();
    // try benchmark_eql();
    // try benchmark_vmul();
    // try benchmark_affine_rot();
    // try benchmark_affine_rotation();
    try benchmark_vec3_transform();
}

const Vec4 = @import("vec.zig").Vec4(f32);

fn benchmark_eql() !void {
    @setFloatMode(.optimized);
    var xor = std.Random.DefaultPrng.init(0);
    var random = xor.random();
    const count = 100_000;

    const allocator = std.heap.page_allocator;
    var data0 = try std.ArrayList(Vec4).initCapacity(allocator, 64);
    defer data0.deinit();
    var data1 = try std.ArrayList(Vec4).initCapacity(allocator, 64);
    defer data1.deinit();

    var i: usize = 0;
    while (i < 64) : (i += 1) {
        data0.appendAssumeCapacity(Vec4.init(random.float(f32), random.float(f32), random.float(f32), random.float(f32)));
        data1.appendAssumeCapacity(Vec4.init(random.float(f32), random.float(f32), random.float(f32), random.float(f32)));
    }

    const tol = std.math.floatEps(f32);
    i = 0;
    while (i < 1024) : (i += 1) {
        for (data1.items) |b| {
            for (data0.items) |a| {
                const r = a.eql_approx(&b, tol);
                std.mem.doNotOptimizeAway(&r);
            }
        }
    }

    // {
    //     i = 0;
    //     var timer = try Timer.start();
    //     const start = timer.lap();
    //     while (i < count) : (i += 1) {
    //         for (data1.items) |b| {
    //             for (data0.items) |a| {
    //                 const r = a.eqlApprox(&b, tol);
    //                 std.mem.doNotOptimizeAway(&r);
    //             }
    //         }
    //     }
    //     const end = timer.read();
    //     const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;
    //
    //     std.debug.print("my version: {d:.4}s, ", .{elapsed_s});
    // }
    {
        i = 0;
        var timer = try Timer.start();
        const start = timer.lap();
        while (i < count) : (i += 1) {
            for (data1.items) |b| {
                for (data0.items) |a| {
                    const r = a.eql_approx(&b, tol);
                    std.mem.doNotOptimizeAway(&r);
                }
            }
        }
        const end = timer.read();
        const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;

        std.debug.print("my version: {d:.4}s, ", .{elapsed_s});
    }
}

const Vec3 = @import("vec.zig").Vec3(f32);

fn benchmark_cross() !void {
    @setFloatMode(.optimized);
    var xor = std.Random.DefaultPrng.init(0);
    var random = xor.random();
    const count = 100_000;

    const allocator = std.heap.page_allocator;
    var data0 = try std.ArrayList(Vec3).initCapacity(allocator, 64);
    defer data0.deinit();
    var data1 = try std.ArrayList(Vec3).initCapacity(allocator, 64);
    defer data1.deinit();

    var i: usize = 0;
    while (i < 64) : (i += 1) {
        data0.appendAssumeCapacity(Vec3.init(random.float(f32), random.float(f32), random.float(f32)));
        data1.appendAssumeCapacity(Vec3.init(random.float(f32), random.float(f32), random.float(f32)));
    }

    i = 0;
    while (i < 1024) : (i += 1) {
        for (data1.items) |b| {
            for (data0.items) |a| {
                const r = a.cross(&b);
                std.mem.doNotOptimizeAway(&r);
            }
        }
    }

    {
        i = 0;
        var timer = try Timer.start();
        const start = timer.lap();
        while (i < count) : (i += 1) {
            for (data1.items) |b| {
                for (data0.items) |a| {
                    const r = a.cross(&b);
                    std.mem.doNotOptimizeAway(&r);
                }
            }
        }
        const end = timer.read();
        const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;

        std.debug.print("my version: {d:.4}s, ", .{elapsed_s});
    }
}

const Mat3 = @import("matrix.zig").Mat3x3(f32);

fn benchmark_vmul() !void {
    @setFloatMode(.optimized);
    var xor = std.Random.DefaultPrng.init(0);
    var random = xor.random();
    const count = 100_000;

    const allocator = std.heap.page_allocator;
    var data0 = try std.ArrayList(Vec3).initCapacity(allocator, 64);
    defer data0.deinit();
    var data1 = try std.ArrayList(Mat3).initCapacity(allocator, 64);
    defer data1.deinit();

    var i: usize = 0;
    while (i < 64) : (i += 1) {
        data0.appendAssumeCapacity(Vec3.init(random.float(f32), random.float(f32), random.float(f32)));
        data1.appendAssumeCapacity(Mat3.init_slice(&.{
            random.float(f32), random.float(f32), random.float(f32),
            random.float(f32), random.float(f32), random.float(f32),
            random.float(f32), random.float(f32), random.float(f32),
            random.float(f32), random.float(f32), random.float(f32),
        }));
    }

    i = 0;
    while (i < 1024) : (i += 1) {
        for (data1.items) |b| {
            for (data0.items) |a| {
                const r = a.mat_mul(&b);
                std.mem.doNotOptimizeAway(&r);
            }
        }
    }

    {
        i = 0;
        var timer = try Timer.start();
        const start = timer.lap();
        while (i < count) : (i += 1) {
            for (data1.items) |b| {
                for (data0.items) |a| {
                    const r = a.mat_mul(&b);
                    std.mem.doNotOptimizeAway(&r);
                }
            }
        }
        const end = timer.read();
        const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;

        std.debug.print("my version: {d:.4}s, \n", .{elapsed_s});
    }

    // {
    //     i = 0;
    //     var timer = try Timer.start();
    //     const start = timer.lap();
    //     while (i < count) : (i += 1) {
    //         for (data1.items) |b| {
    //             for (data0.items) |a| {
    //                 const r = a.mulMat2(&b);
    //                 std.mem.doNotOptimizeAway(&r);
    //             }
    //         }
    //     }
    //     const end = timer.read();
    //     const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;
    //
    //     std.debug.print("Mach version: {d:.4}s, \n", .{elapsed_s});
    // }
}

const Mat2x2 = @import("matrix.zig").Mat2x2;
const Mat2 = Mat2x2(f32);

fn benchmark_mat2() !void {
    @setFloatMode(.optimized);
    var xor = std.Random.DefaultPrng.init(0);
    var random = xor.random();
    const count = 100_000;

    const allocator = std.heap.page_allocator;
    var data0 = try std.ArrayList(Mat2).initCapacity(allocator, 64);
    defer data0.deinit();
    var data1 = try std.ArrayList(Mat2).initCapacity(allocator, 64);
    defer data1.deinit();

    var i: usize = 0;
    while (i < 64) : (i += 1) {
        data0.appendAssumeCapacity(Mat2.init_slice(&.{
            random.float(f32), random.float(f32), random.float(f32), random.float(f32),
        }));
        data1.appendAssumeCapacity(Mat2.init_slice(&.{
            random.float(f32), random.float(f32), random.float(f32), random.float(f32),
        }));
    }

    i = 0;
    while (i < 1024) : (i += 1) {
        for (data1.items) |b| {
            for (data0.items) |a| {
                const r = a.mul(&b);
                std.mem.doNotOptimizeAway(&r);
            }
        }
    }

    {
        i = 0;
        var timer = try Timer.start();
        const start = timer.lap();
        while (i < count) : (i += 1) {
            for (data1.items) |b| {
                for (data0.items) |a| {
                    const r = a.mul(&b);
                    std.mem.doNotOptimizeAway(&r);
                }
            }
        }
        const end = timer.read();
        const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;

        std.debug.print("simd version: {d:.4}s, ", .{elapsed_s});
    }

    // {
    //     i = 0;
    //     var timer = try Timer.start();
    //     const start = timer.lap();
    //     while (i < count) : (i += 1) {
    //         for (data1.items) |b| {
    //             for (data0.items) |a| {
    //                 const r = a.mul_naive(&b);
    //                 std.mem.doNotOptimizeAway(&r);
    //             }
    //         }
    //     }
    //     const end = timer.read();
    //     const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;
    //
    //     std.debug.print("naive version: {d:.4}s, ", .{elapsed_s});
    // }
}

const Mat4x4 = @import("matrix.zig").Mat4x4;
const Mat4 = Mat4x4(f32);

fn benchmark_mat4() !void {
    @setFloatMode(.optimized);
    var xor = std.Random.DefaultPrng.init(0);
    var random = xor.random();
    const count = 100_000;

    const allocator = std.heap.page_allocator;
    var data0 = try std.ArrayList(Mat4).initCapacity(allocator, 64);
    defer data0.deinit();
    var data1 = try std.ArrayList(Mat4).initCapacity(allocator, 64);
    defer data1.deinit();

    var i: usize = 0;
    while (i < 64) : (i += 1) {
        data0.appendAssumeCapacity(Mat4.init_slice(&.{
            random.float(f32), random.float(f32), random.float(f32), random.float(f32),
            random.float(f32), random.float(f32), random.float(f32), random.float(f32),
            random.float(f32), random.float(f32), random.float(f32), random.float(f32),
            random.float(f32), random.float(f32), random.float(f32), random.float(f32),
        }));
        data1.appendAssumeCapacity(Mat4.init_slice(&.{
            random.float(f32), random.float(f32), random.float(f32), random.float(f32),
            random.float(f32), random.float(f32), random.float(f32), random.float(f32),
            random.float(f32), random.float(f32), random.float(f32), random.float(f32),
            random.float(f32), random.float(f32), random.float(f32), random.float(f32),
        }));
    }

    i = 0;
    while (i < 1024) : (i += 1) {
        for (data1.items) |b| {
            for (data0.items) |a| {
                const r = a.mul(&b);
                std.mem.doNotOptimizeAway(&r);
            }
        }
    }

    {
        i = 0;
        var timer = try Timer.start();
        const start = timer.lap();
        while (i < count) : (i += 1) {
            for (data1.items) |b| {
                for (data0.items) |a| {
                    const r = a.mul(&b);
                    std.mem.doNotOptimizeAway(&r);
                }
            }
        }
        const end = timer.read();
        const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;

        std.debug.print("simd version: {d:.4}s, ", .{elapsed_s});
    }
}

const Affine = @import("affine.zig").Affine;
const Transform = Affine(f32);

fn benchmark_affine() !void {
    @setFloatMode(.optimized);
    var xor = std.Random.DefaultPrng.init(0);
    var random = xor.random();
    const count = 100_000;

    const allocator = std.heap.page_allocator;
    var data0 = try std.ArrayList(Transform).initCapacity(allocator, 64);
    defer data0.deinit();
    var data1 = try std.ArrayList(Transform).initCapacity(allocator, 64);
    defer data1.deinit();

    var i: usize = 0;
    while (i < 64) : (i += 1) {
        data0.appendAssumeCapacity(Transform.init_slice(&.{
            random.float(f32), random.float(f32), random.float(f32), 0.0,
            random.float(f32), random.float(f32), random.float(f32), 0.0,
            random.float(f32), random.float(f32), random.float(f32), 0.0,
            random.float(f32), random.float(f32), random.float(f32), 1.0,
        }));
        data1.appendAssumeCapacity(Transform.init_slice(&.{
            random.float(f32), random.float(f32), random.float(f32), 0.0,
            random.float(f32), random.float(f32), random.float(f32), 0.0,
            random.float(f32), random.float(f32), random.float(f32), 0.0,
            random.float(f32), random.float(f32), random.float(f32), 1.0,
        }));
    }

    i = 0;
    while (i < 1024) : (i += 1) {
        for (data1.items) |b| {
            for (data0.items) |a| {
                const r = a.mul(&b);
                std.mem.doNotOptimizeAway(&r);
            }
        }
    }

    {
        i = 0;
        var timer = try Timer.start();
        const start = timer.lap();
        while (i < count) : (i += 1) {
            for (data1.items) |b| {
                for (data0.items) |a| {
                    const r = a.mul(&b);
                    std.mem.doNotOptimizeAway(&r);
                }
            }
        }
        const end = timer.read();
        const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;

        std.debug.print("simd version: {d:.4}s, ", .{elapsed_s});
    }

    // {
    //     i = 0;
    //     var timer = try Timer.start();
    //     const start = timer.lap();
    //     while (i < count) : (i += 1) {
    //         for (data1.items) |b| {
    //             for (data0.items) |a| {
    //                 const r = a.mul2(&b);
    //                 std.mem.doNotOptimizeAway(&r);
    //             }
    //         }
    //     }
    //     const end = timer.read();
    //     const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;
    //
    //     std.debug.print("simd version: {d:.4}s, ", .{elapsed_s});
    // }
}

fn benchmark_vec3_transform() !void {
    @setFloatMode(.optimized);
    var xor = std.Random.DefaultPrng.init(0);
    var random = xor.random();
    const count = 100_000;

    const allocator = std.heap.page_allocator;
    var data0 = try std.ArrayList(Vec3).initCapacity(allocator, 64);
    defer data0.deinit();
    var data1 = try std.ArrayList(Transform).initCapacity(allocator, 64);
    defer data1.deinit();

    var i: usize = 0;
    while (i < 64) : (i += 1) {
        data0.appendAssumeCapacity(Vec3.init(random.float(f32), random.float(f32), random.float(f32)));
        data1.appendAssumeCapacity(Transform.init_slice(&.{
            random.float(f32), random.float(f32), random.float(f32), random.float(f32),
            random.float(f32), random.float(f32), random.float(f32), random.float(f32),
            random.float(f32), random.float(f32), random.float(f32), random.float(f32),
            0.0,               0.0,               0.0,               1.0,
        }));
    }

    i = 0;
    while (i < 1024) : (i += 1) {
        for (data1.items) |b| {
            for (data0.items) |a| {
                const r = b.transform_dir(&a);
                std.mem.doNotOptimizeAway(&r);
            }
        }
    }

    {
        i = 0;
        var timer = try Timer.start();
        const start = timer.lap();
        while (i < count) : (i += 1) {
            for (data1.items) |b| {
                for (data0.items) |a| {
                    const r = b.transform_pos(&a);
                    std.mem.doNotOptimizeAway(&r);
                }
            }
        }
        const end = timer.read();
        const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;

        std.debug.print("literal version: {d:.4}s, ", .{elapsed_s});
    }

    {
        i = 0;
        var timer = try Timer.start();
        const start = timer.lap();
        while (i < count) : (i += 1) {
            for (data1.items) |b| {
                for (data0.items) |a| {
                    const r = b.transform_dir(&a);
                    std.mem.doNotOptimizeAway(&r);
                }
            }
        }
        const end = timer.read();
        const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;

        std.debug.print("simd version: {d:.4}s, ", .{elapsed_s});
    }
}

fn benchmark_affine_rot() !void {
    @setFloatMode(.optimized);
    var xor = std.Random.DefaultPrng.init(0);
    var random = xor.random();
    const count = 100_000;

    const allocator = std.heap.page_allocator;
    var data0 = try std.ArrayList(Transform).initCapacity(allocator, 64);
    defer data0.deinit();
    var data1 = try std.ArrayList(Transform).initCapacity(allocator, 64);
    defer data1.deinit();

    var i: usize = 0;
    while (i < 64) : (i += 1) {
        data0.appendAssumeCapacity(Transform.init_slice(&.{
            random.float(f32), random.float(f32), random.float(f32), 0.0,
            random.float(f32), random.float(f32), random.float(f32), 0.0,
            random.float(f32), random.float(f32), random.float(f32), 0.0,
            0.0,               0.0,               0.0,               1.0,
        }));
        data1.appendAssumeCapacity(Transform.init_slice(&.{
            random.float(f32), random.float(f32), random.float(f32), 0.0,
            random.float(f32), random.float(f32), random.float(f32), 0.0,
            random.float(f32), random.float(f32), random.float(f32), 0.0,
            0.0,               0.0,               0.0,               1.0,
        }));
    }

    i = 0;
    while (i < 1024) : (i += 1) {
        for (data1.items) |b| {
            for (data0.items) |a| {
                const r = a.mul(&b);
                std.mem.doNotOptimizeAway(&r);
            }
        }
    }

    {
        i = 0;
        var timer = try Timer.start();
        const start = timer.lap();
        while (i < count) : (i += 1) {
            for (data1.items) |b| {
                for (data0.items) |a| {
                    const r = a.mul(&b);
                    std.mem.doNotOptimizeAway(&r);
                }
            }
        }
        const end = timer.read();
        const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;

        std.debug.print("simd version: {d:.4}s, ", .{elapsed_s});
    }

    {
        i = 0;
        var timer = try Timer.start();
        const start = timer.lap();
        while (i < count) : (i += 1) {
            for (data1.items) |b| {
                for (data0.items) |a| {
                    const r = a.mul_rot(&b);
                    std.mem.doNotOptimizeAway(&r);
                }
            }
        }
        const end = timer.read();
        const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;

        std.debug.print("simd version: {d:.4}s, ", .{elapsed_s});
    }
}

fn benchmark_affine_rotation() !void {
    @setFloatMode(.optimized);
    var xor = std.Random.DefaultPrng.init(0);
    var random = xor.random();
    const count = 100_000;

    const allocator = std.heap.page_allocator;
    var data0 = try std.ArrayList(Vec3).initCapacity(allocator, 64);
    defer data0.deinit();
    var data1 = try std.ArrayList(f32).initCapacity(allocator, 64);
    defer data1.deinit();

    var i: usize = 0;
    while (i < 64) : (i += 1) {
        data0.appendAssumeCapacity(Vec3.init_slice(&.{
            random.float(f32), random.float(f32), random.float(f32),
        }));
        data1.appendAssumeCapacity(random.float(f32));
    }

    i = 0;
    while (i < 1024) : (i += 1) {
        for (data1.items) |b| {
            for (data0.items) |a| {
                const r = Transform.init_rotation(&a, b);
                std.mem.doNotOptimizeAway(&r);
            }
        }
    }

    {
        i = 0;
        var timer = try Timer.start();
        const start = timer.lap();
        while (i < count) : (i += 1) {
            for (data1.items) |b| {
                for (data0.items) |a| {
                    const r = Transform.init_rotation(&a, b);
                    std.mem.doNotOptimizeAway(&r);
                }
            }
        }
        const end = timer.read();
        const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;

        std.debug.print("simd version: {d:.4}s, ", .{elapsed_s});
    }

    {
        i = 0;
        var timer = try Timer.start();
        const start = timer.lap();
        while (i < count) : (i += 1) {
            for (data1.items) |b| {
                for (data0.items) |a| {
                    const r = Transform.init_rotation2(&a, b);
                    std.mem.doNotOptimizeAway(&r);
                }
            }
        }
        const end = timer.read();
        const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;

        std.debug.print("simd version2: {d:.4}s, ", .{elapsed_s});
    }
}

const std = @import("std");
const Timer = std.time.Timer;
const time = std.time;
