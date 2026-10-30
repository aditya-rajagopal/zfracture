const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;

//https://github.com/ghostty-org/ghostty/blob/26e243a9194f8653e0b44cf00b600629fcee8f46/src/quirks.zig
const assert = switch (builtin.mode) {
    .debug => std.debug.assert,
    .fast, .safe, .small => struct {
        inline fn assert(_: bool) void {}
    }.assert,
};

/// Initialize with .empty and pair scopes on the same tracer in strict LIFO order.
///
/// ```zig
/// const Anchors = enum { work, sub_work };
/// var tracer: Tracer(Anchors, defaultTimer, true) = .empty;
/// // Alternative: Tracer(Anchors, queryPerformanceCounter, true)
/// tracer.init(50);
/// {
///     const work = tracer.startTrace(.work);
///     defer tracer.end(&work);
///     {
///         const sub_work = tracer.startTrace(.sub_work);
///         defer tracer.end(&sub_work);
///     }
///     // Simulation work, optionally with nested scopes.
/// }
/// tracer.finish();
/// tracer.writeReportStdout(io);
/// ```
pub fn Tracer(
    comptime AnchorsEnum: type,
    comptime time_fn: *const fn () u64,
    comptime enabled: bool,
) type {
    const info = @typeInfo(AnchorsEnum);
    comptime std.debug.assert(info == .@"enum");
    if (info.@"enum".mode == .nonexhaustive) @compileError("Tracer anchors must be an exhaustive enum");
    const anchor_count = std.enums.directEnumArrayLen(AnchorsEnum, info.@"enum".field_names.len) + 1;

    return struct {
        inner: if (enabled) State else void,

        pub const empty: Self = if (enabled) .{ .inner = .{} } else .{ .inner = {} };

        const Self = @This();
        const State = struct {
            current_parent: u32 = 0,
            frequency_hz: f64 = 0,
            tracer_anchors: [anchor_count]TracerInfo = @splat(.{}),
            tracer_start: u64 = 0,
            tracer_end: u64 = 0,
            running: bool = false,
        };

        pub const Snapshot = if (enabled) struct {
            anchors: [anchor_count]TracerInfo = @splat(.{}),
            start: u64 = 0,
            end: u64 = 0,
        } else void;

        pub const TracerInfo = struct {
            hit_count: u64 = 0,
            scope_time_exclusive: u64 = 0,
            scope_time_inclusive: u64 = 0,
        };

        pub const TraceHandle = if (enabled) struct {
            anchor: AnchorsEnum,
            parent: u32,
            start_time: u64,
            inclusive_before: u64,
        } else void;

        /// Calibrate once outside the measured workload. Reinitialization clears
        /// statistics and requires every old scope to have ended.
        pub fn init(self: *Self, calibration_time_ms: u64) void {
            if (!enabled) return;
            const frequency = calibrateFrequency(calibration_time_ms, time_fn);
            self.initWithFrequency(frequency);
        }

        /// Use an already known/calibrated tick frequency without another calibration.
        pub fn initWithFrequency(self: *Self, frequency: f64) void {
            if (!enabled) return;
            assert(frequency > 0);
            self.inner.frequency_hz = frequency;
            self.reset();
        }

        pub fn finish(self: *Self) void {
            if (!enabled) return;
            assert(self.inner.running);
            assert(self.inner.current_parent == 0);
            const now = time_fn();
            assert(now >= self.inner.tracer_start);
            self.inner.tracer_end = now;
            self.inner.running = false;
        }

        pub fn snapshot(self: *const Self) Snapshot {
            if (!enabled) return;
            var s: Snapshot = undefined;
            s.anchors = self.inner.tracer_anchors;
            s.start = self.inner.tracer_start;
            s.end = self.inner.tracer_end;
            return s;
        }

        pub fn reset(self: *Self) void {
            if (!enabled) return;
            assert(self.inner.frequency_hz > 0);
            self.inner.tracer_anchors = @splat(.{});
            self.inner.tracer_end = 0;
            self.inner.tracer_start = time_fn();
            self.inner.running = true;
            self.inner.current_parent = 0;
        }

        pub fn snapshotAndReset(self: *Self) Snapshot {
            const s = self.snapshot();
            self.reset();
            return s;
        }

        pub fn startTrace(self: *Self, comptime tag: AnchorsEnum) TraceHandle {
            if (!enabled) return {};
            const in = &self.inner;
            assert(in.running);
            const position = comptime @as(u32, @intCast(@backingInt(tag))) + 1;
            const handle: TraceHandle = .{
                .anchor = tag,
                .parent = in.current_parent,
                .start_time = time_fn(),
                .inclusive_before = in.tracer_anchors[position].scope_time_inclusive,
            };
            in.current_parent = position;
            return handle;
        }

        /// End the most recently started scope on this tracer, exactly once.
        pub fn end(self: *Self, handle: *const TraceHandle) void {
            if (!enabled) return;
            const now = time_fn();
            const in = &self.inner;
            const position = @as(u32, @intCast(@backingInt(handle.anchor))) + 1;
            assert(in.running);
            assert(in.current_parent == position);
            const anchor = &in.tracer_anchors[position];
            assert(now >= handle.start_time);
            const elapsed = now - handle.start_time;

            // An open parent's exclusive accumulator can temporarily be negative.
            // wrapping subtraction/addition cancels this when that parent closes.
            // Slot zero is a sentinel, not a measured root scope.
            if (handle.parent != 0) in.tracer_anchors[handle.parent].scope_time_exclusive -%= elapsed;
            anchor.hit_count += 1;
            anchor.scope_time_exclusive +%= elapsed;
            anchor.scope_time_inclusive = handle.inclusive_before + elapsed;
            in.current_parent = handle.parent;
        }

        pub fn timeStart(_: *const Self) u64 {
            if (!enabled) return 0;
            return time_fn();
        }

        pub fn timeEnd(_: *const Self) u64 {
            if (!enabled) return 0;
            return time_fn();
        }

        /// Report through the caller's writer; no dependency on log filtering.
        pub fn writeReport(self: *const Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            if (!enabled) return;
            const in = &self.inner;
            assert(!in.running);
            assert(in.frequency_hz > 0);
            const full_time = self.durationMS(in.tracer_end, in.tracer_start);
            try writer.print("Total time: {d:.6} ms (timer frequency {d} Hz)\n", .{ full_time, in.frequency_hz });
            inline for (info.@"enum".field_names, info.@"enum".field_values) |name, value| {
                const anchor = in.tracer_anchors[value + 1];
                if (anchor.hit_count != 0) {
                    const exclusive = self.toMS(anchor.scope_time_exclusive);
                    const inclusive = self.toMS(anchor.scope_time_inclusive);
                    const percentage = if (full_time > 0) exclusive * 100.0 / full_time else 0;
                    try writer.print("  {s}[{d}]: {d:.6} ms exclusive ({d:.2}%), {d:.6} ms inclusive, {d:.6} ms/hit\n", .{
                        name,                                                  anchor.hit_count, exclusive, percentage, inclusive,
                        exclusive / @as(f64, @floatFromInt(anchor.hit_count)),
                    });
                }
            }
        }

        pub fn writeReportStdout(self: *const Self, io: std.Io) void {
            if (!enabled) return;
            var buffer: [1024]u8 = undefined;
            var writer = std.Io.File.stdout().writer(io, &buffer);
            self.writeReport(&writer.interface) catch return;
            writer.interface.flush() catch return;
        }

        pub fn duration(self: *const Self, end_time: u64, start_time: u64) f64 {
            if (!enabled) return 0;
            assert(self.inner.frequency_hz > 0);
            assert(end_time >= start_time);
            return @as(f64, @floatFromInt(end_time - start_time)) / self.inner.frequency_hz;
        }

        pub fn durationMS(self: *const Self, end_time: u64, start_time: u64) f64 {
            return self.duration(end_time, start_time) * std.time.ms_per_s;
        }

        pub fn durationNS(self: *const Self, end_time: u64, start_time: u64) f64 {
            return self.duration(end_time, start_time) * std.time.ns_per_s;
        }

        pub fn toMS(self: *const Self, ticks: u64) f64 {
            return self.durationMS(ticks, 0);
        }
    };
}

pub fn queryPerformanceFrequency() u64 {
    switch (builtin.os.tag) {
        .windows => {
            var result: windows.LARGE_INTEGER = 0;
            const success = windows.ntdll.RtlQueryPerformanceFrequency(&result);
            if (!success.toBool()) @panic("QPC frequency query failed");
            if (result <= 0) @panic("invalid QPC frequency");
            return @intCast(result);
        },
        .macos => {
            var timebase: std.c.mach_timebase_info_data = undefined;
            if (std.c.mach_timebase_info(&timebase) != 0) @panic("Mach timebase query failed");
            if (timebase.numer == 0) @panic("invalid Mach timebase");
            if (timebase.denom == 0) @panic("invalid Mach timebase");
            return @as(u64, std.time.ns_per_s) * timebase.denom / timebase.numer;
        },
        else => @compileError("Unsupported profiling platform"),
    }
}

pub fn queryPerformanceCounter() u64 {
    switch (builtin.os.tag) {
        .windows => {
            var result: windows.LARGE_INTEGER = 0;
            const success = windows.ntdll.RtlQueryPerformanceCounter(&result);
            if (!success.toBool()) @panic("QPC query failed");
            if (result < 0) @panic("invalid QPC timestamp");
            return @intCast(result);
        },
        .macos => return std.c.mach_absolute_time(),
        else => @compileError("Unsupported profiling platform"),
    }
}

pub fn rdtsc() u64 {
    if (builtin.cpu.arch != .x86_64) @compileError("rdtsc requires x86_64; use defaultTimer on Apple Silicon");
    var low: u32 = undefined;
    var high: u32 = undefined;
    asm volatile (
        \\lfence
        \\rdtsc
        \\lfence
        : [low] "={eax}" (low),
          [high] "={edx}" (high),
        :
        : .{ .memory = true });
    return (@as(u64, high) << 32) | low;
}

pub fn defaultTimer() u64 {
    switch (builtin.cpu.arch) {
        .x86_64 => return rdtsc(),
        .aarch64 => {
            // NOTE(adi): AFAIK for CNTVCT_EL0, backed by Arm’s fixed-frequency system counter.
            // CPU power-saving, performance changes, and thermal throttling do not change its rate.
            if (builtin.os.tag != .macos) @compileError("Arm profiling counter is supported on macOS only");
            return asm volatile (
                \\isb
                \\mrs %[ticks], cntvct_el0
                \\isb
                : [ticks] "=r" (-> u64),
                :
                : .{ .memory = true });
        },
        else => @compileError("Unsupported profiling architecture"),
    }
}

fn millisecondsToTicks(ms: u64, frequency: u64) error{ InvalidFrequency, Overflow }!u64 {
    if (frequency == 0) return error.InvalidFrequency;
    const ticks = (@as(u128, ms) * frequency + 999) / 1000;
    return std.math.cast(u64, ticks) orelse error.Overflow;
}

/// Busy wait for development timing experiments, not game frame pacing.
pub fn sleep(ms: u64) void {
    if (ms == 0) return;
    const ticks = millisecondsToTicks(ms, queryPerformanceFrequency()) catch @panic("invalid spin duration");
    const start = queryPerformanceCounter();
    while (queryPerformanceCounter() - start < ticks) std.atomic.spinLoopHint();
}

/// Calibration runs outside measured work, with up to three 1..1000 ms attempts.
/// Interrupted samples are retried; repeated interruptions fail initialization.
/// Cache its result when initializing several collectors with the same clock.
pub fn calibrateFrequency(ms: u64, time_fn: *const fn () u64) f64 {
    if (ms == 0) @panic("calibration duration must be positive");
    if (ms > 1000) @panic("calibration duration must not exceed one second");
    const frequency = queryPerformanceFrequency();
    const ticks = millisecondsToTicks(ms, frequency) catch @panic("invalid calibration duration");
    return calibrateWithReference(ticks, frequency, time_fn, queryPerformanceCounter);
}

fn calibrateWithReference(
    ticks: u64,
    frequency: u64,
    time_fn: *const fn () u64,
    comptime reference_fn: *const fn () u64,
) f64 {
    const max_sample_gap = @max(1, ticks / 100);
    for (0..3) |_| {
        const start_before = reference_fn();
        const counter_start = time_fn();
        const start_after = reference_fn();
        const start_gap = start_after - start_before;
        if (start_gap > max_sample_gap) continue;
        const reference_start = start_before + start_gap / 2;

        var end_before = start_after;
        while (end_before - reference_start < ticks) {
            std.atomic.spinLoopHint();
            end_before = reference_fn();
        }
        const counter_end = time_fn();
        const end_after = reference_fn();
        const end_gap = end_after - end_before;
        if (end_gap > max_sample_gap - start_gap) continue;
        const reference_end = end_before + end_gap / 2;

        if (counter_end <= counter_start) @panic("profiling counter did not advance");
        // Convert before multiplying: frequency * elapsed can overflow u64.
        return @as(f64, @floatFromInt(frequency)) *
            @as(f64, @floatFromInt(counter_end - counter_start)) /
            @as(f64, @floatFromInt(reference_end - reference_start));
    }
    @panic("profiling calibration repeatedly interrupted");
}

const TestClock = struct {
    var now: u64 = 0;
    var reads: usize = 0;

    fn read() u64 {
        reads += 1;
        return now;
    }
};

const TestAnchors = enum { outer, child, leaf };
const TestTracer = Tracer(TestAnchors, TestClock.read, true);

test "nested scopes attribute inclusive and exclusive time across siblings" {
    TestClock.now = 0;
    var tracer: TestTracer = .empty;
    tracer.initWithFrequency(1000);
    const outer = tracer.startTrace(.outer);
    TestClock.now = 10;
    const child = tracer.startTrace(.child);
    TestClock.now = 20;
    const leaf = tracer.startTrace(.leaf);
    TestClock.now = 30;
    tracer.end(&leaf);
    TestClock.now = 40;
    tracer.end(&child);
    TestClock.now = 50;
    const sibling = tracer.startTrace(.child);
    TestClock.now = 60;
    tracer.end(&sibling);
    TestClock.now = 70;
    tracer.end(&outer);
    tracer.finish();

    const anchors = tracer.inner.tracer_anchors;
    try std.testing.expectEqual(70, anchors[1].scope_time_inclusive);
    try std.testing.expectEqual(30, anchors[1].scope_time_exclusive);
    try std.testing.expectEqual(40, anchors[2].scope_time_inclusive);
    try std.testing.expectEqual(30, anchors[2].scope_time_exclusive);
    try std.testing.expectEqual(2, anchors[2].hit_count);
    try std.testing.expectEqual(10, anchors[3].scope_time_exclusive);
}

test "nested repeated anchors count their outermost inclusive interval once" {
    TestClock.now = 0;
    var tracer: TestTracer = .empty;
    tracer.initWithFrequency(1000);
    const outer = tracer.startTrace(.outer);
    TestClock.now = 10;
    const inner = tracer.startTrace(.outer);
    TestClock.now = 20;
    tracer.end(&inner);
    TestClock.now = 30;
    tracer.end(&outer);
    const next = tracer.startTrace(.outer);
    TestClock.now = 40;
    tracer.end(&next);
    tracer.finish();

    const anchor = tracer.inner.tracer_anchors[1];
    try std.testing.expectEqual(3, anchor.hit_count);
    try std.testing.expectEqual(40, anchor.scope_time_inclusive);
    try std.testing.expectEqual(40, anchor.scope_time_exclusive);
}

test "millisecond conversion rounds up and detects invalid frequencies and overflow" {
    try std.testing.expectEqual(0, try millisecondsToTicks(0, 32768));
    try std.testing.expectEqual(33, try millisecondsToTicks(1, 32768));
    try std.testing.expectEqual(32768, try millisecondsToTicks(1000, 32768));
    try std.testing.expectError(error.InvalidFrequency, millisecondsToTicks(1, 0));
    try std.testing.expectError(error.Overflow, millisecondsToTicks(std.math.maxInt(u64), std.math.maxInt(u64)));
}

test "calibration preserves frequency across interrupted endpoint reads" {
    const Clock = struct {
        var now: u64 = 0;
        var reads: usize = 0;
        var interrupted_read: usize = 0;

        fn reference() u64 {
            now += 1;
            return now;
        }

        fn read() u64 {
            reads += 1;
            if (reads == interrupted_read) now += 250;
            return now * 3;
        }
    };
    // A 1000 Hz reference and a counter advancing three times as fast must
    // calibrate to 3000 Hz, including after a pause at either endpoint.
    for ([_]usize{ 0, 1, 2 }) |interrupted_read| {
        Clock.now = 0;
        Clock.reads = 0;
        Clock.interrupted_read = interrupted_read;
        const actual = calibrateWithReference(1000, 1000, Clock.read, Clock.reference);
        try std.testing.expectEqual(3000.0, actual);
    }
}
