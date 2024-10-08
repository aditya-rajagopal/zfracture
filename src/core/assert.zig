const core_log = @import("log.zig").core_log;

/// Asserts a condition. If it fails print an error and dump stack trace
pub fn assert(condition: bool) void {
    switch (builtin.mode) {
        .Debug, .ReleaseSafe => {
            if (condition) {} else {
                @setCold(true);
                core_log.fatal("Assertion failed\n", .{});
                const debug_info = std.debug.getSelfDebugInfo() catch |err| {
                    core_log.fatal("\n Unable to print stack trace: {s}\n", .{@errorName(err)});
                    @breakpoint();
                    return;
                };
                const stderr = std.io.getStdErr();
                const tty_config = std.io.tty.detectConfig(stderr);

                const writer = stderr.writer();
                std.debug.writeCurrentStackTrace(writer, debug_info, tty_config, null) catch |err| {
                    core_log.fatal("\n Unable to print stack trace: {s}\n", .{@errorName(err)});
                    @breakpoint();
                    return;
                };
                @breakpoint();
            }
        },
        else => {
            if (condition) {} else {
                @setCold(true);
                core_log.fatal("Assertion failed\n", .{});
            }
        },
    }
}

/// Asserts a condition only in debug builds. Dumps stack trace on failure and sets a breakpoint.
pub fn debug_assert(condition: bool) void {
    switch (builtin.mode) {
        .Debug => assert(condition),
        else => {},
    }
}

const builtin = @import("builtin");
const std = @import("std");
