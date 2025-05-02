const std = @import("std");
const assert = std.debug.assert;
const time = std.time;
const root = @import("root");

const log = @import("log.zig");
pub const tsc = @import("perf/tsc.zig");

const TracerLog = log.ScopedLogger(log.default_log, .TRACER, log.default_level);

pub const TracerInfo = struct {
    hit_count: u64 = 0,
    scope_time_exclusive: u64 = 0,
    scope_time_inclusive: u64 = 0,
};

pub fn Tracer(comptime AnchorsEnum: type, comptime time_fn: *const fn () u64, comptime enabled: bool) type {
    const info = @typeInfo(AnchorsEnum);
    comptime assert(info == .@"enum");

    const enum_array_len = if (enabled) std.enums.directEnumArrayLen(AnchorsEnum, info.@"enum".fields.len) + 1 else 0;
    return struct {
        current_parent: usize = 0,
        tracer_anchors: [enum_array_len]TracerInfo,
        timer_frequency: f64 = 0,
        tracer_start: u64 = 0,
        tracer_end: u64 = 0,
        log: TracerLog,

        const Self = @This();

        pub const TraceHandle = if (enabled) struct {
            start_time: u64,
            inlcusive: u64,
            parent: u32,
            position: u32,
        } else void;

        pub fn init(self: *Self, calibration_time_ms: usize, log_config: *log.LogConfig) void {
            self.current_parent = 0;
            if (comptime enabled) {
                self.tracer_anchors = enum_array_default_plus_one(
                    AnchorsEnum,
                    TracerInfo,
                    TracerInfo{},
                    @typeInfo(AnchorsEnum).@"enum".fields.len,
                    .{},
                );
            }
            self.log = TracerLog.init(log_config);
            self.timer_frequency = tsc.calibrate_frequency(calibration_time_ms, time_fn);
            self.tracer_start = time_fn();
        }

        pub fn finish(self: *Self) void {
            self.tracer_end = time_fn();
        }

        pub fn start(self: *Self, comptime tag: AnchorsEnum) TraceHandle {
            if (comptime enabled) {
                const position = comptime (@as(u32, @intFromEnum(tag)) + 1);
                var local: TraceHandle = undefined;
                // NOTE: I think it is reasonable to assume i wont have more than 4billion nested calls and less than
                // 4 billion positions
                local.parent = @truncate(self.current_parent);
                self.current_parent = position;
                local.position = @truncate(position);

                local.inlcusive = self.tracer_anchors[position].scope_time_inclusive;
                local.start_time = time_fn();
                return local;
            }
        }

        pub fn end(self: *Self, handle: *const TraceHandle) void {
            if (comptime enabled) {
                const elapsed_time = time_fn() - handle.start_time;

                self.tracer_anchors[handle.parent].scope_time_exclusive -%= elapsed_time;

                self.tracer_anchors[handle.position].hit_count +%= 1;
                self.tracer_anchors[handle.position].scope_time_exclusive +%= elapsed_time;
                self.tracer_anchors[handle.position].scope_time_inclusive = handle.inlcusive +% elapsed_time;

                self.current_parent = handle.parent;
            }
        }

        /// WARNING: This will always run so use it sparingly. Prefer using start()
        /// Use self.duration, self.duration_ms, and self.duration_ns to convert to time
        pub fn time_start(self: *const Self) u64 {
            _ = self;
            return time_fn();
        }

        /// WARNING: This will always run so use it sparingly. Prefer using start()
        pub fn time_end(self: *const Self) u64 {
            _ = self;
            return time_fn();
        }

        pub fn tracer_print_stderr(self: *const Self) void {
            const full_time = self.duration_ms(self.tracer_end, self.tracer_start);
            self.log.debug("Total time: {d:.6} (CPU freq {d})", .{ full_time, self.timer_frequency });
            if (comptime enabled) {
                inline for (info.@"enum".fields) |field| {
                    const anchor = self.tracer_anchors[field.value + 1];
                    const mark_time = self.to_ms(anchor.scope_time_exclusive);
                    if (mark_time != 0) {
                        self.log.debug("\t{s}[{d}]", .{ field.name, anchor.hit_count });
                        self.log.debug(
                            "\t\t{d:.6} ms ({d:.2}%)\t{d:.6} ms/hit",
                            .{
                                mark_time,
                                mark_time * 100.0 / full_time,
                                mark_time / @as(f64, @floatFromInt(anchor.hit_count)),
                            },
                        );

                        if (anchor.scope_time_inclusive != anchor.scope_time_exclusive) {
                            const child_time = self.to_ms(anchor.scope_time_inclusive);
                            self.log.debug("\t\t( {d:.6} ms ({d:.2}%) with children)", .{
                                child_time,
                                child_time * 100.0 / full_time,
                            });
                        }
                    }
                }
            }
        }

        pub fn duration(self: *const Self, end_time: u64, start_time: u64) f64 {
            const diff: f64 = @floatFromInt(end_time -% start_time);
            return diff / self.timer_frequency;
        }

        pub fn duration_ms(self: *const Self, end_time: u64, start_time: u64) f64 {
            const diff: f64 = @floatFromInt(end_time -% start_time);
            return diff * 1000.0 / self.timer_frequency;
        }

        pub fn duration_ns(self: *const Self, end_time: u64, start_time: u64) f64 {
            const diff: f64 = @floatFromInt(end_time -% start_time);
            return diff * 1000.0 * 1000.0 / self.timer_frequency;
        }

        pub fn to_ms(self: *const Self, time_counter: u64) f64 {
            return @as(f64, @floatFromInt(time_counter)) * 1000.0 / self.timer_frequency;
        }
    };
}

pub fn enum_array_default_plus_one(
    comptime E: type,
    comptime Data: type,
    comptime default: ?Data,
    comptime max_unused_slots: comptime_int,
    init_values: std.enums.EnumFieldStruct(E, Data, default),
) [std.enums.directEnumArrayLen(E, max_unused_slots) + 1]Data {
    @setEvalBranchQuota(200000);
    const len = comptime std.enums.directEnumArrayLen(E, max_unused_slots) + 1;
    var result: [len]Data = if (default) |d| [_]Data{d} ** len else undefined;
    inline for (@typeInfo(@TypeOf(init_values)).@"struct".fields) |f| {
        const enum_value = @field(E, f.name);
        const index: usize = @intCast(@intFromEnum(enum_value));
        result[index] = @field(init_values, f.name);
    }
    return result;
}

test "Tracer" {
    const anchors = enum {
        anchor0,
        anchor1,
    };

    const T = Tracer(anchors, tsc.rdtsc, true);
    var tracer: T = undefined;
    var log_config: log.LogConfig = undefined;
    log_config.init();
    try log_config.stderr_init();
    tracer.init(50, &log_config);

    const v = tracer.start(.anchor1);
    tsc.sleep(100);
    tracer.end(&v);

    var v2 = tracer.start(.anchor1);
    tsc.sleep(200);
    tracer.end(&v2);

    tracer.finish();
    tracer.tracer_print_stderr();
    std.debug.print("Size of Tracer: {}, {}\n", .{ @sizeOf(T), @alignOf(T) });
}
