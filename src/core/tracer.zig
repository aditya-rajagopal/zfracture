const std = @import("std");
const assert = std.debug.assert;
const time = std.time;
const root = @import("root");

const log = @import("log.zig");
pub const tsc = @import("perf/tsc.zig");

const TracerLog = log.ScopedLogger(log.default_log, .TRACER, log.default_level);

/// Creates a tracer for a given enum type which provides the anchors for the tracer.
///
/// if enabled the type will contain statistics for each anchor as defined by the enum and store time information.
///
/// There are two types of time stored:
///     - Exclusive time: Time spent just in the anchor and not in any of its children
///     - Inclusive time: Time spent in the anchor and all of its children
///
/// The timing function used will be clocked in the tracer init function and that is used to calculate actual time.
///
/// # Usage
/// ```zig
/// const std = @import("std");
/// const assert = std.debug.assert;
/// const Tracer = @import("fr_core").Tracer;
/// const tsc = Tracer.tsc;
///
/// const Anchors = enum(u8) {
///     anchor0,
///     anchor1,
/// };
///
/// pub fn main() !void {
///     var log_config: log.LogConfig = undefined;
///     log_config.init();
///     try log_config.stdout_init();
///
///     var tracer: Tracer(Anchors, tsc.rdtsc, true) = undefined;
///     try tracer.init(50, &log_config);
///     defer tracer.deinit();
///
///     const v = tracer.start(.anchor1);
///     tsc.sleep(100);
///     tracer.end(.anchor1, &v);
///
///     const v2 = tracer.start(.anchor1);
///     tsc.sleep(200);
///     tracer.end(.anchor2, &v2);
///
///     tracer.finish();
///     tracer.tracer_print_stderr();
///
///     assert(std.math.approxEqAbs(f64, tracer.tracer_anchors[0].scope_time_exclusive, 100.0, 0.1));
///     assert(std.math.approxEqAbs(f64, tracer.tracer_anchors[1].scope_time_exclusive, 200.0, 0.1));
///
///     assert(std.math.approxEqAbs(f64, tracer.duration_ms(tracer.tracer_end, tracer.tracer_start), 300.0, 0.1));
///
///     tracer.print_stdout();
/// }
/// ```
pub fn Tracer(
    /// The enum that contains the anchors that can be provided as a scope
    comptime AnchorsEnum: type,
    /// A function that returns a performance counter. This is clocked against the system clock.
    comptime time_fn: *const fn () u64,
    /// Whether the tracer is enabled or not. This will globally disable all tracing and make them no-ops
    comptime enabled: bool,
) type {
    const info = @typeInfo(AnchorsEnum);
    comptime assert(info == .@"enum");

    const enum_array_len = if (enabled) std.enums.directEnumArrayLen(AnchorsEnum, info.@"enum".fields.len) + 1 else 0;
    return struct {
        /// The parent anchor of the current scope
        current_parent: usize = 0,
        /// The tracer anchors for each anchor in the enum
        tracer_anchors: [enum_array_len]TracerInfo,
        /// The frequency of the timer
        timer_frequency: f64 = 0,
        /// The start time of the tracer
        tracer_start: u64 = 0,
        /// The end time of the tracer
        tracer_end: u64 = 0,
        /// The log for the tracer
        log: TracerLog,

        const Self = @This();

        /// The tracer info for each anchor. This is a void type if the tracer is disabled
        pub const TracerInfo = if (enabled) struct {
            /// The number of times the anchor was hit
            hit_count: u64 = 0,
            /// The exclusive time spent in the anchor
            scope_time_exclusive: u64 = 0,
            /// The inclusive time spent in the anchor and all of its children
            scope_time_inclusive: u64 = 0,
        } else void;

        /// The handle for a tracer anchor. This is a void type if the tracer is disabled
        pub const TraceHandle = if (enabled) struct {
            // TODO: Does this need to change?
            /// The parent anchor of the current scope
            parent: u32,
            /// The start time of the tracer
            start_time: u64,
            /// The inclusive time spent in the anchor and all of its children
            inlcusive: u64,
        } else void;

        /// Initialize the tracer
        pub fn init(
            self: *Self,
            /// The time in milliseconds to calibrate the timer for
            calibration_time_ms: usize,
            /// The log config to use for the tracer
            log_config: *log.LogConfig,
        ) void {
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

        /// Finish the tracer
        pub fn finish(self: *Self) void {
            self.tracer_end = time_fn();
        }

        /// Start a tracer anchor. This is a no-op if the tracer is disabled
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

        /// End a tracer anchor. This is a no-op if the tracer is disabled
        pub fn end(self: *Self, comptime tag: AnchorsEnum, handle: *const TraceHandle) void {
            if (comptime enabled) {
                const position = comptime (@as(u32, @intFromEnum(tag)) + 1);
                const elapsed_time = time_fn() - handle.start_time;

                self.tracer_anchors[handle.parent].scope_time_exclusive -%= elapsed_time;

                self.tracer_anchors[position].hit_count +%= 1;
                self.tracer_anchors[position].scope_time_exclusive +%= elapsed_time;
                self.tracer_anchors[position].scope_time_inclusive = handle.inlcusive +% elapsed_time;

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

        /// Print the tracer to stdout. This will only print the total time and the anchors if the tracer is disabled
        pub fn tracer_print_stdout(self: *const Self) void {
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

        /// Calculate the duration of a time period in seconds
        pub fn duration(self: *const Self, end_time: u64, start_time: u64) f64 {
            const diff: f64 = @floatFromInt(end_time -% start_time);
            return diff / self.timer_frequency;
        }

        /// Calculate the duration of a time period in milliseconds
        pub fn duration_ms(self: *const Self, end_time: u64, start_time: u64) f64 {
            const diff: f64 = @floatFromInt(end_time -% start_time);
            return diff * 1000.0 / self.timer_frequency;
        }

        /// Calculate the duration of a time period in nanoseconds
        pub fn duration_ns(self: *const Self, end_time: u64, start_time: u64) f64 {
            const diff: f64 = @floatFromInt(end_time -% start_time);
            return diff * 1000.0 * 1000.0 / self.timer_frequency;
        }

        /// Convert a time counter to milliseconds
        pub fn to_ms(self: *const Self, time_counter: u64) f64 {
            return @as(f64, @floatFromInt(time_counter)) * 1000.0 / self.timer_frequency;
        }
    };
}

/// Create a default enum array with one extra element
fn enum_array_default_plus_one(
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

test Tracer {
    const anchors = enum {
        anchor0,
        anchor1,
    };

    const T = Tracer(anchors, tsc.rdtsc, true);
    var tracer: T = undefined;
    var log_config: log.LogConfig = undefined;
    log_config.init();
    try log_config.stdout_init();
    tracer.init(50, &log_config);

    const v = tracer.start(.anchor1);
    tsc.sleep(100);
    tracer.end(&v);

    var v2 = tracer.start(.anchor1);
    tsc.sleep(200);
    tracer.end(&v2);

    tracer.finish();
    tracer.tracer_print_stderr();
}
