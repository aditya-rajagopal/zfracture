const platform = @import("core_platform.zig");

/// Struct to define log levels of custom scopes defined in the app
// pub const ScopeLevel = struct {
//     scope: @Type(.enum_literal),
//     level: Level,
// };

/// The levels of logging that are avilable within the engine
pub const Level = enum {
    /// Fatal: Something has gone terribly wrong. This is irrecoverable and the program
    /// should exit.
    fatal,
    /// Error: something has gone wrong. This might be recoverable or might
    /// be followed by the program exiting.
    err,
    /// Warning: it is uncertain if something has gone wrong or not, but the
    /// circumstances would be worth investigating.
    warn,
    /// Info: general messages about the state of the program.
    info,
    /// Debug: messages only useful for debugging.
    debug,
    /// Trace: messages for temporary logging
    trace,

    /// Returns a string literal of the given level in full text form.
    pub fn as_text(comptime self: Level) []const u8 {
        return switch (self) {
            .fatal => "FATAL",
            .err => "ERROR",
            .warn => "WARNING",
            .info => "INFO",
            .debug => "DEBUG",
            .trace => "TRACE",
        };
    }

    /// Returns a string literal of the given level in full text form.
    pub fn colour(comptime self: Level) std.io.tty.Color {
        return switch (self) {
            .fatal => .bright_magenta,
            .err => .bright_red,
            .warn => .yellow,
            .info => .cyan,
            .debug => .green,
            .trace => .white,
        };
    }
};

/// The default log level is based on build mode.
pub const default_level: Level = switch (builtin.mode) {
    .Debug => .trace,
    .ReleaseSafe => .info,
    .ReleaseFast, .ReleaseSmall => .info,
};

/// The type of the logging function required
pub const LogFn = *const fn (*LogConfig, comptime Level, comptime @Type(.enum_literal), comptime []const u8, anytype) void;

/// The configuration of a logger that is passed to log functions
pub const LogConfig = struct {
    /// UNUSED RIGHT NOW
    // log_file: ?[]const u8 = null,
    log_file: ?std.fs.File = null,
    file_writer: std.io.BufferedWriter(4096, std.fs.File.Writer) = undefined,
    /// Terminal configuration for colouring
    tty_config: std.io.tty.Config = undefined,
    /// The buffered writer to which to write to in the LogFn
    buffered_writer: std.io.BufferedWriter(8192, std.fs.File.Writer) = undefined,

    pub fn init(self: *LogConfig) void {
        self.* = LogConfig{};
    }

    /// Initializes the logger to print to stderr
    pub fn stderr_init(self: *LogConfig) LoggerError!void {
        const stderr = std.io.getStdErr();
        self.tty_config = platform.get_tty_config(stderr) catch return LoggerError.TTYConfigFailed;

        const stdwrite = stderr.writer();
        self.buffered_writer = .{ .unbuffered_writer = stdwrite };
    }

    /// Initialize the logger to print to a file
    pub fn file_init(self: *LogConfig) LoggerError!void {
        self.log_file = std.fs.cwd().openFile("./Logs/debug_log.txt", .{ .mode = .write_only }) catch |e| switch (e) {
            std.fs.File.OpenError.FileNotFound => blk: {
                @branchHint(.cold);
                try std.fs.cwd().makePath("./Logs/");
                break :blk try std.fs.cwd().createFile("./Logs/debug_log.txt", .{});
            },
            else => |overflow| return overflow,
        };
        self.log_file.?.seekFromEnd(0) catch unreachable;
        const writer = self.log_file.?.writer();
        self.file_writer = .{ .unbuffered_writer = writer };
    }

    pub fn deinit(self: *LogConfig) void {
        if (self.log_file) |file| {
            self.file_writer.flush() catch unreachable;
            file.close();
        }
        self.buffered_writer.flush() catch unreachable;
    }
};

pub const LoggerError = error{TTYConfigFailed} || std.fs.File.OpenError || std.fs.Dir.MakeError || std.fs.Dir.StatFileError;

pub fn ScopedLogger(comptime log_function: LogFn, comptime scope: @Type(.enum_literal), comptime log_level: Level) type {
    return struct {
        const Self = @This();
        config: *LogConfig,

        pub fn init(config: *LogConfig) Self {
            return .{ .config = config };
        }

        inline fn logging(
            self: Self,
            comptime message_level: Level,
            comptime format: []const u8,
            args: anytype,
        ) void {
            if (comptime @intFromEnum(message_level) > @intFromEnum(log_level)) return;

            log_function(self.config, message_level, scope, format, args);
        }

        /// Log an fatal error message. This log level is intended to be used
        /// when something has gone VERY wrong. This is usually an irrecoverable
        /// error and the program is most likely going to exit.
        pub fn fatal(
            self: Self,
            comptime format: []const u8,
            args: anytype,
        ) void {
            self.logging(.fatal, format, args);
        }

        /// Log an error message. This log level is intended to be used
        /// when something has gone wrong. This might be recoverable or might
        /// be followed by the program exiting.
        pub fn err(
            self: Self,
            comptime format: []const u8,
            args: anytype,
        ) void {
            self.logging(.err, format, args);
        }

        /// Log a warning message. This log level is intended to be used if
        /// it is uncertain whether something has gone wrong or not, but the
        /// circumstances would be worth investigating.
        pub fn warn(
            self: Self,
            comptime format: []const u8,
            args: anytype,
        ) void {
            self.logging(.warn, format, args);
        }

        /// Log an info message. This log level is intended to be used for
        /// general messages about the state of the program.
        pub fn info(
            self: Self,
            comptime format: []const u8,
            args: anytype,
        ) void {
            self.logging(.info, format, args);
        }

        /// Log a debug message. This log level is intended to be used for
        /// messages which are only useful for debugging.
        pub fn debug(
            self: Self,
            comptime format: []const u8,
            args: anytype,
        ) void {
            self.logging(.debug, format, args);
        }

        /// Log a trace message. This log level is intended to be used for
        /// messages which are useful for step by step debugging in specific parts
        /// of the application during debugging.
        pub fn trace(
            self: Self,
            comptime format: []const u8,
            args: anytype,
        ) void {
            self.logging(.trace, format, args);
        }

        /// Log current stack trace. This is only correct in debug builds. In non debug builds this will be incorrect due to
        /// optimizations
        pub fn dump_stack_trace(self: Self) void {
            const debug_info = std.debug.getSelfDebugInfo() catch |e| {
                self.fatal("\n Unable to print stack trace: {s}\n", .{@errorName(e)});
                return;
            };

            const writer = self.config.buffered_writer.writer();
            std.debug.writeCurrentStackTrace(writer, debug_info, self.config.tty_config, null) catch |e| {
                self.fatal("\n Unable to print stack trace: {s}\n", .{@errorName(e)});
                return;
            };
            self.config.buffered_writer.flush() catch unreachable;
        }

        /// Asserts a condition. If it fails print an error along with user provided context and dumps a stack trace
        /// Example:
        /// ```
        /// assert_msg(1 == 0, @src(), "Number system is consistent: {d} != {d}", .{1, 0});
        /// ```
        pub fn assert_msg(self: Self, condition: bool, comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
            if (!condition) {
                @branchHint(.cold);
                self.fatal(
                    "Assertion failed: {s}:{d} in file {s}",
                    .{ src.fn_name, src.line, src.file },
                );
                if (comptime fmt.len != 0) {
                    self.fatal(fmt, args);
                }
                dump_stack_trace();

                switch (builtin.mode) {
                    .Debug, .ReleaseSafe => @breakpoint(),
                    else => {},
                }
                unreachable;
            }
        }

        /// Asserts a condition. If it fails print an error and dump stack trace
        /// Example:
        /// ```
        /// assert(1 == 0, @src());
        /// ```
        pub fn assert(self: Self, condition: bool, comptime src: std.builtin.SourceLocation) void {
            self.assert_msg(condition, src, "", .{});
        }

        /// Asserts a condition only in debug builds. Dumps stack trace on failure and sets a breakpoint.
        /// Example:
        /// ```
        /// debug_assert(1 == 0, @src());
        /// ```
        pub fn debug_assert(self: Self, condition: bool, comptime src: std.builtin.SourceLocation) void {
            switch (builtin.mode) {
                .Debug, .ReleaseSafe => self.assert_msg(condition, src, "", .{}),
                else => {},
            }
        }

        /// Asserts a condition only in debug builds along with a message. Dumps stack trace on failure and sets a breakpoint.
        /// Example:
        /// ```
        /// debug_assert_msg(1 == 0, @src(), "Number system is consistent: {d} != {d}", .{1, 0});
        /// ```
        pub fn debug_assert_msg(
            self: Self,
            condition: bool,
            comptime src: std.builtin.SourceLocation,
            comptime fmt: []const u8,
            args: anytype,
        ) void {
            switch (builtin.mode) {
                .Debug, .ReleaseSafe => self.assert_msg(condition, src, fmt, args),
                else => {},
            }
        }

        /// Equivalent to unreachable but with logging and breakpoints. Accepts custom print data.
        /// Example:
        /// ```
        /// never_msg(@src(), "I should have never reached this place. The number must not be {d}", .{42});
        /// ```
        pub fn never_msg(self: Self, comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
            @branchHint(.cold);
            self.fatal(
                "Assertion failed: {s}:{d} in file {s}",
                .{ src.fn_name, src.line, src.file },
            );
            if (comptime fmt.len != 0) {
                self.fatal(fmt, args);
            }
            dump_stack_trace();

            switch (builtin.mode) {
                .Debug, .ReleaseSafe => @breakpoint(),
                else => {},
            }
            unreachable;
        }

        /// Equivalent to unreachable but with some logging
        /// Example:
        /// ```
        /// never(@src());
        /// ```
        pub fn never(comptime src: std.builtin.SourceLocation) void {
            @branchHint(.cold);
            never_msg(src, "", .{});
        }
    };
}

/// The default implementation for the log function, custom log functions may
/// forward log messages to this function.
pub fn default_log(
    logger: *LogConfig,
    comptime message_level: Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    // TODO: Can this be more efficient
    const level_txt = comptime message_level.as_text();
    const prefix2 = level_txt ++ " [" ++ @tagName(scope) ++ "]: ";

    if (logger.log_file) |_| {
        const writer = logger.file_writer.writer();
        writer.print(prefix2 ++ format ++ "\n", args) catch return;
        // logger.buffered_writer.flush() catch return;
    }

    const writer = logger.buffered_writer.writer();
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();

    nosuspend {
        logger.tty_config.setColor(writer, comptime message_level.colour()) catch return;
        writer.print(prefix2 ++ format ++ "\n", args) catch return;
        logger.buffered_writer.flush() catch return;
        logger.tty_config.setColor(writer, .reset) catch return;
    }
}

/// Function to be used to remove all logging everywhere.
/// straight up stole from tigerbeatle. Made sure to change the name.
/// Use this as the log_fn in the root module to disable all logging
pub fn nop_log(
    logger: *LogConfig,
    comptime message_level: Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = .{
        logger,
        message_level,
        scope,
        format,
        args,
    };
}

const std = @import("std");
const builtin = @import("builtin");
