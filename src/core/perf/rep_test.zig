const root = @import("root");

const MAX_TRIES = 10_000_000;

const options: Options = if (@hasDecl(root, "rep_test_options")) root.rep_test_options else .{};

// TODO(aditya): Maybe we can have configurable metrics
pub const MetricsFunction = *const fn (test_times: *Result) f64;
pub const Options = struct {
    /// Can setup a function that returns u64 time stamp counter
    time_fn: *const fn () u64 = tsc.rdtsc,
    reset_each_iter: bool = false,
    metrics: []MetricsFunction = &[_]MetricsFunction{},
};

pub const RepType = union(enum) {
    fixed_len: u32, // contains number of steps
    min: f32, // contains time to spend before new min candidate
    fixed_time: f32, // containst the time to spend on the test
};

pub const TestFn = *const fn (*Ctx) anyerror!void;
pub const TestConfig = struct {
    reset_each_iter: bool = options.reset_each_iter,
    mode: RepType,
    // metrics: []MetricsFunction
};
pub const TestCase = struct {
    name: []const u8,
    function: TestFn,
    config: TestConfig,
};

pub const TestCases: []const TestCase = if (@hasDecl(root, "rep_test_cases"))
    root.rep_test_cases
else
    @compileError("Using repetition tester without defining test_cases");

// TODO: Create min, max, total for all 3 metrics
pub const ResTypes = enum {
    test_count,
    cpu_time,
    page_fault,
    byte_count,
};

// fn ResultValue type {
//     if (options.metrics.len > 0) {
//         struct {
//             Val: [ResTypesCount]u64 = [_]u64{0} ** ResTypesCount,
//             collection: [MAX_TRIES]u64 = [_]u64{0} ** MAX_TRIES,
//         };
//         @compileError("Not implemented metrics yet\n");
//     } else {
//     struct {
//         Val: [ResTypesCount]u64 = [_]u64{0} ** ResTypesCount,
//     };
//     }
// }

pub const ResTypesCount = std.enums.directEnumArrayLen(ResTypes, 0);
pub const ResultValue = struct {
    Val: [ResTypesCount]u64 = [_]u64{0} ** ResTypesCount,
};

pub const Result = struct {
    calibrated_freq: f64 = 0,
    min: ResultValue = .{},
    max: ResultValue = .{},
    total: ResultValue = .{},
};

pub const Ctx = struct {
    init: bool = false,
    state: State = .IDLE,
    test_start_time: u64 = 0,

    test_min_check_time: u64 = 0,
    mode: RepType,
    reset_each_iter: bool,

    num_blk_started: u32 = 0,
    num_blk_ended: u32 = 0,

    payload: ?*anyopaque = null,

    expected_bytes: u64 = 0,

    current_test_result: ResultValue = .{},
    result: Result = .{},

    pub const State = enum {
        IDLE,
        RUNNING,
        ERROR,
    };

    pub fn reset(self: *Ctx) void {
        if (self.reset_each_iter or !self.init) {
            self.num_blk_ended = 0;
            self.num_blk_started = 0;

            self.current_test_result = .{};
            self.current_test_result.Val[@intFromEnum(ResTypes.test_count)] = 1;
            self.result.min = .{};
            self.result.min.Val[@intFromEnum(ResTypes.cpu_time)] = std.math.maxInt(u64);
            self.result.max = .{};
            self.result.total = .{};
            self.init = true;
        }

        self.test_start_time = options.time_fn();
        self.test_min_check_time = options.time_fn();
    }

    pub fn begin(self: *Ctx) void {
        self.num_blk_started += 1;
        self.current_test_result.Val[@intFromEnum(ResTypes.page_fault)] -%= tsc.ReadOSPageFaultCount(Process.handle) catch 0;
        self.current_test_result.Val[@intFromEnum(ResTypes.cpu_time)] -%= options.time_fn();
    }

    pub fn end(self: *Ctx) void {
        self.current_test_result.Val[@intFromEnum(ResTypes.cpu_time)] +%= options.time_fn();
        self.current_test_result.Val[@intFromEnum(ResTypes.page_fault)] +%= tsc.ReadOSPageFaultCount(Process.handle) catch 0;
        self.num_blk_ended += 1;
    }

    pub fn data(self: *Ctx, bytes: u64) void {
        self.current_test_result.Val[@intFromEnum(ResTypes.byte_count)] +%= bytes;
    }

    pub fn is_running(self: *Ctx) bool {
        std.debug.assert(Process.init);

        if (self.state == .IDLE) {
            self.reset();
            self.state = .RUNNING;
            return true;
        }

        if (self.state == .RUNNING) {
            if (self.num_blk_started > 0) {
                if (self.num_blk_started != self.num_blk_ended) {
                    self.report_error(
                        "Mismatch of number of blocks started and ended in Run: started: {d} vs ended: {d}\n",
                        .{ self.num_blk_started, self.num_blk_ended },
                    );
                }

                if (self.current_test_result.Val[@intFromEnum(ResTypes.byte_count)] != self.expected_bytes) {
                    self.report_error(
                        "Mimsatch in number of bytes flowing through test in Run: expected: {d} vs actual: {d}\n",
                        .{ self.expected_bytes, self.current_test_result.Val[@intFromEnum(ResTypes.byte_count)] },
                    );
                }
            }
        }

        if (self.state == .RUNNING) {
            const current_time = options.time_fn();

            const total_time = self.current_test_result.Val[@intFromEnum(ResTypes.cpu_time)];

            inline for (@typeInfo(ResTypes).@"enum".fields) |field| {
                self.result.total.Val[field.value] +%= self.current_test_result.Val[field.value];
            }

            if (total_time > self.result.max.Val[@intFromEnum(ResTypes.cpu_time)]) {
                self.result.max = self.current_test_result;
            }
            if (total_time < self.result.min.Val[@intFromEnum(ResTypes.cpu_time)]) {
                self.test_min_check_time = current_time;
                self.result.min = self.current_test_result;

                const stdout = std.io.getStdOut().writer();
                print_time("New min", self.current_test_result, self.result.calibrated_freq, stdout) catch unreachable;
                stdout.print("                                        \r", .{}) catch unreachable;
            }

            self.num_blk_ended = 0;
            self.num_blk_started = 0;

            self.current_test_result = .{};
            self.current_test_result.Val[@intFromEnum(ResTypes.test_count)] = 1;

            if (options.metrics.len > 0) {
                if (self.result.num_tries >= MAX_TRIES) {
                    std.log.warn(
                        "Reached maximum number of tries 10 mil. Try changing the problem statement or change the max tries\n",
                        .{},
                    );
                    self.state = .IDLE;
                    return false;
                }
            }

            switch (self.mode) {
                .fixed_len => |len| {
                    if (self.result.total.Val[@intFromEnum(ResTypes.test_count)] < len) {
                        return true;
                    }
                },
                .min => |reset_time| {
                    const time_since_last_min = @as(f64, @floatFromInt(current_time -% self.test_min_check_time)) / self.result.calibrated_freq;
                    if (time_since_last_min < reset_time) {
                        return true;
                    }
                },
                .fixed_time => |time| {
                    const time_since_start = @as(f64, @floatFromInt(current_time -% self.test_start_time)) / self.result.calibrated_freq;
                    if (time_since_start < time) {
                        return true;
                    }
                },
            }
            self.state = .IDLE;
        }

        return false;
    }

    pub fn report_error(self: *Ctx, comptime fmt: []const u8, args: anytype) void {
        self.state = .ERROR;
        std.log.err(fmt, args);
    }
};

pub const TestRunner = struct {
    name: []const u8,
    function: TestFn,
    context: Ctx,
};

var Tests: [TestCases.len]TestRunner = blk: {
    var runners: [TestCases.len]TestRunner = undefined;
    for (0..runners.len) |i| {
        runners[i].name = TestCases[i].name;
        runners[i].function = TestCases[i].function;
        runners[i].context = Ctx{
            .mode = TestCases[i].config.mode,
            .reset_each_iter = TestCases[i].config.reset_each_iter,
        };
    }
    break :blk runners;
};
var calibrated_freq: f64 = 0;
var Process: struct { handle: windows.HANDLE, init: bool } = .{ .handle = undefined, .init = false };

pub fn initialize() void {
    if (Process.init) {
        return;
    }
    Process.handle = tsc.InitializeOSMetrics();
    Process.init = true;
    std.debug.print("Rep Test initialized\n", .{});
}

pub fn run_tests() !void {
    var is_running = true;
    var stdout = std.io.getStdOut().writer();
    var stdin = std.io.getStdIn().reader();
    var buffer: [1024]u8 = undefined;
    calibrated_freq = tsc.calibrate_frequency(50, options.time_fn);
    var round: usize = 0;
    while (is_running) {
        for (&Tests) |*case| {
            try stdout.print("-" ** 10 ++ "{s}-{d}" ++ "-" ** 10 ++ "\n", .{ case.name, round });
            case.context.result.calibrated_freq = (calibrated_freq);

            try case.function(&case.context);

            if (case.context.state == .IDLE) {
                try stdout.print("                                                 \r", .{});
                try print_results(&case.context.result);
            }
            if (case.context.state == .ERROR) {
                case.context.state = .IDLE;
            }
        }
        try stdout.print("Do you want to continue? [Y/N] ", .{});
        const confirmation = try stdin.readUntilDelimiter(&buffer, '\n');
        if (confirmation.len != 2) {
            std.log.err("Unrecognized response: {s}\n", .{confirmation});
            break;
        } else if (confirmation.len == 2 and 'N' == confirmation[0]) {
            is_running = false;
        } else if (confirmation.len == 2 and confirmation[0] != 'Y') {
            std.log.err("Unrecognized response: {s}\n", .{confirmation});
            break;
        }
        round += 1;
    }
}

pub fn print_results(result: *const Result) !void {
    const stdout = std.io.getStdOut().writer();
    try print_time("Min", result.min, result.calibrated_freq, stdout);
    try stdout.print("\n", .{});
    try print_time("Max", result.max, result.calibrated_freq, stdout);
    try stdout.print("\n", .{});
    try print_time("Average", result.total, result.calibrated_freq, stdout);
    try stdout.print("\n", .{});
}

pub fn print_time(label: []const u8, result: ResultValue, freq: f64, stdout: anytype) !void {
    const num_tries: f64 = @floatFromInt(result.Val[@intFromEnum(ResTypes.test_count)]);
    const time_in_s = as_second(result.Val[@intFromEnum(ResTypes.cpu_time)], freq) / num_tries;

    const bytes_f: f64 = @as(f64, @floatFromInt(result.Val[@intFromEnum(ResTypes.byte_count)])) / num_tries;
    const page_faults: f64 = @as(f64, @floatFromInt(result.Val[@intFromEnum(ResTypes.page_fault)])) / num_tries;

    try stdout.print(
        "{s}: {d:.6} ms ( {d:.4} gb/s)",
        .{ label, time_in_s, bytes_f / (1024.0 * 1024.0 * 1024.0 * time_in_s) },
    );
    if (page_faults != 0) {
        try stdout.print(": {d} pf,  {d:.2}k bytes/fault", .{ page_faults, bytes_f / (page_faults * 1024.0) });
    }
}

pub fn as_second(time_counter: u64, cpu_freq: f64) f64 {
    return @as(f64, @floatFromInt(time_counter)) / cpu_freq;
}

pub fn prepare_test(id: usize, payload: ?*anyopaque, expected_bytes: u64) void {
    Tests[id].context.payload = payload;
    Tests[id].context.expected_bytes = expected_bytes;
}

pub fn prepare_all(payload: ?*anyopaque, expected_bytes: u64) void {
    for (&Tests) |*case| {
        case.context.payload = payload;
        case.context.expected_bytes = expected_bytes;
    }
}

const std = @import("std");
const tsc = @import("tsc.zig");
const windows = std.os.windows;
