///! This logging library is sort of a mirror of the std.log libarary.
///! The reason for this is I need additional logging levels and want to colour the logs
///!
///! There are 2 main exports from this library: core_log and log
///!    core_log: is the logger meant to be used within the enging
///!    log: is the logger intended to be used on the game side
///!
///! You can customize the logging library by creating a logger_config public constant in your root module of the
///! type LogConfig.
///! Here you can override the log_fn used by the logger and the log level for the app.
///!
///! You can create a new logging scope by calling the scope function. You can add those new scopes and their
///! corresponding log levels to the custom_scopes field in the logger_config.
///!
///!
///! ```
///! pub const libfoo = log.scoped(.libfoo);
///!
///! // ------ in app.zig -------
///!
///! const libfoo_level = switch (builtin.mode) {
///!    .Debug => .info,
///!    .ReleaseSafe => .err,
///!    .ReleaseFast, .ReleaseSmall => .fatal,
///! };
///!
///! pub const logger_config: fracture.core.log.LogConfig = .{
///!     .log_fn = fracture.core.log.default_log,
///!     .app_log_level = fracture.core.log.default_level,
///!     .custom_scopes = &[_]fracture.core.log.ScopeLevel{
///!         .{ .scope = .libfoo, .level = libfoo_level },
///!     },
///! };
///! ```
const platform = @import("platform");

// TODO(aditya):
// - [ ] Change the log function to also optionally write to a log file in addition to console
// - [ ] Seperate log thread? job?

/// The logger for the engine
pub const core_log = scoped(.Engine);
/// The logger for the Game
pub const log = scoped(.Game);

/// The default log level is based on build mode.
pub const default_level: Level = switch (builtin.mode) {
    .Debug => .trace,
    .ReleaseSafe => .warn,
    .ReleaseFast, .ReleaseSmall => .err,
};

/// The type of the logging function required
pub const LogFn = *const fn (comptime Level, comptime @Type(.EnumLiteral), comptime []const u8, anytype) void;

const engine_log_level = default_level;

/// The configuration for the logging system that can be set by the user in the root module with the variable name
/// logger_config
pub const LogConfig = struct {
    app_log_level: Level = .debug,
    log_fn: LogFn = default_log,
    custom_scopes: []const ScopeLevel = &.{},
};

const root = @import("root");
const logger_config: LogConfig = if (@hasDecl(root, "logger_config")) root.logger_config else .{};

const scope_levels: []const ScopeLevel = &[_]ScopeLevel{
    .{ .scope = .Engine, .level = engine_log_level },
    .{ .scope = .Game, .level = logger_config.app_log_level },
} ++ logger_config.custom_scopes;

const log_fn: LogFn = logger_config.log_fn;

const LogSystemData = struct {
    log_file: ?[]const u8 = null,
    tty_config: std.io.tty.Config,
    buffered_writer: std.io.BufferedWriter(8192, std.fs.File.Writer),
};

var log_system_data: LogSystemData = .{ .tty_config = undefined, .buffered_writer = undefined };
var system_initialized: bool = false;

/// Initializes the logging system by creating the buffered stderr writer
pub fn init() !void {
    if (system_initialized) {
        core_log.warn("Trying to reinitialize the logging system\n", .{});
        return;
    }

    // Output is to stderr
    const stderr = std.io.getStdErr();
    log_system_data.tty_config = try platform.get_tty_config(stderr);

    const stdwrite = stderr.writer();
    log_system_data.buffered_writer = .{ .unbuffered_writer = stdwrite };

    system_initialized = true;
}

/// Shutdown the logging system
pub fn deinit() void {
    if (!system_initialized) {
        return;
    }

    log_system_data.buffered_writer.flush() catch unreachable;
    system_initialized = false;
}

/// The default implementation for the log function, custom log functions may
/// forward log messages to this function.
pub fn default_log(
    comptime message_level: Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (!system_initialized) {
        return;
    }
    // TODO: Can this be more efficient
    const level_txt = comptime message_level.as_text();
    const prefix2 = @tagName(scope) ++ ": " ++ "(" ++ level_txt ++ "): ";

    const writer = log_system_data.buffered_writer.writer();
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();

    nosuspend {
        log_system_data.tty_config.setColor(writer, comptime message_level.colour()) catch return;
        writer.print(prefix2 ++ format ++ "\n", args) catch return;
        log_system_data.buffered_writer.flush() catch return;
        log_system_data.tty_config.setColor(writer, .reset) catch return;
    }
}

/// Function to be used to remove all logging everywhere.
/// straight up stole from tigerbeatle. Made sure to change the name.
/// Use this as the log_fn in the root module to disable all logging
pub fn nop_log(
    comptime message_level: Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = .{
        message_level,
        scope,
        format,
        args,
    };
}

/// Log current stack trace. This is only correct in debug builds. In non debug builds this will be incorrect due to
/// optimizations
pub fn dump_stack_trace() void {
    if (!system_initialized) {
        return;
    }
    const debug_info = std.debug.getSelfDebugInfo() catch |err| {
        core_log.fatal("\n Unable to print stack trace: {s}\n", .{@errorName(err)});
        return;
    };

    const writer = log_system_data.buffered_writer.writer();
    std.debug.writeCurrentStackTrace(writer, debug_info, log_system_data.tty_config, null) catch |err| {
        core_log.fatal("\n Unable to print stack trace: {s}\n", .{@errorName(err)});
        return;
    };
    log_system_data.buffered_writer.flush() catch unreachable;
}

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
            .fatal => "fatal",
            .err => "error",
            .warn => "warning",
            .info => "info",
            .debug => "debug",
            .trace => "trace",
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

/// Struct to define log levels of custom scopes defined in the app
pub const ScopeLevel = struct {
    scope: @Type(.EnumLiteral),
    level: Level,
};

fn logging(
    comptime message_level: Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (comptime !log_enabled(message_level, scope)) return;

    log_fn(message_level, scope, format, args);
}

/// Determine if a specific log message level and scope combination are enabled for logging.
pub fn log_enabled(comptime message_level: Level, comptime scope: @Type(.EnumLiteral)) bool {
    inline for (scope_levels) |scope_level| {
        if (scope_level.scope == scope) return @intFromEnum(message_level) <= @intFromEnum(scope_level.level);
    }
    return @intFromEnum(message_level) <= @intFromEnum(default_level);
}

/// Returns a scoped logging namespace that logs all messages using the scope
/// provided here.
pub fn scoped(comptime scope: @Type(.EnumLiteral)) type {
    return struct {
        /// Log an fatal error message. This log level is intended to be used
        /// when something has gone VERY wrong. This is usually an irrecoverable
        /// error and the program is most likely going to exit.
        pub fn fatal(
            comptime format: []const u8,
            args: anytype,
        ) void {
            @setCold(true);
            logging(.fatal, scope, format, args);
        }

        /// Log an error message. This log level is intended to be used
        /// when something has gone wrong. This might be recoverable or might
        /// be followed by the program exiting.
        pub fn err(
            comptime format: []const u8,
            args: anytype,
        ) void {
            @setCold(true);
            logging(.err, scope, format, args);
        }

        /// Log a warning message. This log level is intended to be used if
        /// it is uncertain whether something has gone wrong or not, but the
        /// circumstances would be worth investigating.
        pub fn warn(
            comptime format: []const u8,
            args: anytype,
        ) void {
            logging(.warn, scope, format, args);
        }

        /// Log an info message. This log level is intended to be used for
        /// general messages about the state of the program.
        pub fn info(
            comptime format: []const u8,
            args: anytype,
        ) void {
            logging(.info, scope, format, args);
        }

        /// Log a debug message. This log level is intended to be used for
        /// messages which are only useful for debugging.
        pub fn debug(
            comptime format: []const u8,
            args: anytype,
        ) void {
            logging(.debug, scope, format, args);
        }

        /// Log a trace message. This log level is intended to be used for
        /// messages which are useful for step by step debugging in specific parts
        /// of the application during debugging.
        pub fn trace(
            comptime format: []const u8,
            args: anytype,
        ) void {
            logging(.trace, scope, format, args);
        }
    };
}

const std = @import("std");
const builtin = @import("builtin");
