const builtin = @import("builtin");

pub fn query_performance_frequency() u64 {
    if (builtin.os.tag == .windows) {
        var result: LARGE_INTEGER = 0;
        _ = windows.ntdll.RtlQueryPerformanceFrequency(&result);
        return @bitCast(result);
    }

    @compileError("Platform not supported");
}

pub fn query_performance_counter() u64 {
    if (builtin.os.tag == .windows) {
        var result: LARGE_INTEGER = 0;
        _ = windows.ntdll.RtlQueryPerformanceCounter(&result);
        return @bitCast(result);
    }

    @compileError("Platform not supported");
}

pub fn InitializeOSMetrics() windows.HANDLE {
    if (builtin.os.tag == .windows) {
        return windows.kernel32.GetCurrentProcess();
    }

    @compileError("Platform not supported");
}

pub fn ReadOSPageFaultCount(handle: windows.HANDLE) windows.GetProcessMemoryInfoError!u64 {
    if (builtin.os.tag == .windows) {
        var memory_counters: windows.PROCESS_MEMORY_COUNTERS_EX = std.mem.zeroInit(windows.PROCESS_MEMORY_COUNTERS_EX, .{});
        memory_counters.cb = @sizeOf(windows.PROCESS_MEMORY_COUNTERS_EX);

        const counters = try windows.GetProcessMemoryInfo(handle);

        const result: u64 = @intCast(counters.PageFaultCount);
        return result;
    }

    @compileError("Platform not supported");
}

pub fn rdtsc() u64 {
    var low: u32 = 0;
    var hi: u32 = 0;

    asm (
        \\rdtsc
        : [low] "={eax}" (low),
          [hi] "={edx}" (hi),
    );
    return (@as(u64, @intCast(hi)) << 32) | @as(u64, @intCast(low));
}

/// NOTE: This function will spin your CPU while sleeping. For actual sleep you probably should use a syscall
pub fn sleep(ms: u64) void {
    const freq: u64 = query_performance_frequency();
    const ticks_to_run = ms * @divFloor(freq, 1000);
    const start = query_performance_counter();

    while (query_performance_counter() -% start < ticks_to_run) {}
}

pub fn calibrate_frequency(ms: u64, time_fn: *const fn () u64) f64 {
    const freq: u64 = query_performance_frequency();
    const ticks_to_run = ms * (freq / 1000);

    const cpu_start = time_fn();
    const start = query_performance_counter();

    while (query_performance_counter() -% start < ticks_to_run) {}

    const end = query_performance_counter();
    const cpu_end = time_fn();

    const cpu_elapsed = cpu_end -% cpu_start;
    const os_elpased = end -% start;

    const cpu_freq = freq * cpu_elapsed / os_elpased;
    return @floatFromInt(cpu_freq);
}

test rdtsc {
    _ = calibrate_frequency(50, rdtsc);
}

const std = @import("std");
const time = std.time;
const windows = std.os.windows;
const LARGE_INTEGER = windows.LARGE_INTEGER;
