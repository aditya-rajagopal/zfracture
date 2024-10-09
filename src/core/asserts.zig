const core_log = @import("logging.zig").core_log;
const dump_stack_trace = @import("logging.zig").dump_stack_trace;

/// Asserts a condition. If it fails print an error along with user provided context and dumps a stack trace
pub fn assert_msg(condition: bool, comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    switch (builtin.mode) {
        .Debug, .ReleaseSafe => {
            if (condition) {} else {
                @setCold(true);
                core_log.fatal(
                    "Assertion failed: {s}:{d} in file {s}",
                    .{ src.fn_name, src.line, src.file },
                );
                if (fmt.len != 0) {
                    core_log.fatal(fmt, args);
                }
                dump_stack_trace();
                @breakpoint();
            }
        },
        else => {
            if (condition) {} else {
                @setCold(true);
                core_log.fatal(
                    "Assertion failed: {s}:{d} in file {s}",
                    .{ src.fn_name, src.line, src.file },
                );
                if (fmt.len != 0) {
                    core_log.fatal(fmt, args);
                }
            }
        },
    }
}

/// Asserts a condition. If it fails print an error and dump stack trace
pub fn assert(condition: bool, comptime src: std.builtin.SourceLocation) void {
    assert_msg(condition, src, "", .{});
}

/// Asserts a condition only in debug builds. Dumps stack trace on failure and sets a breakpoint.
pub fn debug_assert(condition: bool, comptime src: std.builtin.SourceLocation) void {
    switch (builtin.mode) {
        .Debug => assert_msg(condition, src, "", .{}),
        else => {},
    }
}

/// Asserts a condition only in debug builds along with a message. Dumps stack trace on failure and sets a breakpoint.
pub fn debug_assert_msg(
    condition: bool,
    comptime src: std.builtin.SourceLocation,
    comptime fmt: []const u8,
    args: anytype,
) void {
    switch (builtin.mode) {
        .Debug => assert(condition, src, fmt, args),
        else => {},
    }
}

/// Equivalent to unreachable but with logging and breakpoints. Accepts custom print data.
pub fn never_msg(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    @setCold(true);
    core_log.fatal("Reached somewhere I should never have: {s}:{d} in file {s}", .{ src.fn_name, src.line, src.file });
    if (fmt.len != 0) {
        core_log.fatal(fmt, args);
    }
    dump_stack_trace();

    switch (builtin.mode) {
        .Debug, .ReleaseSafe => @breakpoint(),
        else => {},
    }
}

/// Equivalent to unreachable but with some logging
pub fn never(comptime src: std.builtin.SourceLocation) void {
    @setCold(true);
    never_msg(src, "", .{});
}

const builtin = @import("builtin");
const std = @import("std");
