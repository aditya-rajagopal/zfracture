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
    .ReleaseSafe => .info,
    .ReleaseFast, .ReleaseSmall => .err,
};

/// The type of the logging function required
pub const LogFn = *const fn (comptime Level, comptime @Type(.EnumLiteral), comptime []const u8, anytype) void;

const engine_log_level = default_level;

const root = @import("root");
const game_log_level: Level = if (@hasDecl(root, "log_level")) root.log_level else .debug;

const scope_levels: []const ScopeLevel = &[_]ScopeLevel{
    .{ .scope = .Engine, .level = engine_log_level },
    .{ .scope = .Game, .level = game_log_level },
};

const log_fn: LogFn = if (@hasDecl(root, "log_fn")) root.log_fn else default_log;

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

const LogSystemData = struct {
    log_file: ?[]const u8 = null,
    tty_config: std.io.tty.Config,
    buffered_writer: std.io.BufferedWriter(8192, std.fs.File.Writer),
};

var log_system_data: LogSystemData = .{ .tty_config = undefined, .buffered_writer = undefined };
var system_initialized: bool = false;

pub const LogError = error{UnableToGetConsoleScreenBuffer};

/// Initializes the logging system by creating the buffered stderr writer
pub fn init() LogError!void {
    if (system_initialized) {
        core_log.warn("Trying to reinitialize the logging system\n", .{});
        return;
    }

    // Output is to stderr
    const stderr = std.io.getStdErr();
    var info: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (std.os.windows.kernel32.GetConsoleScreenBufferInfo(stderr.handle, &info) != std.os.windows.TRUE) {
        return LogError.UnableToGetConsoleScreenBuffer;
    }
    log_system_data.tty_config = std.io.tty.Config{ .windows_api = .{
        .handle = stderr.handle,
        .reset_attributes = info.wAttributes,
    } };

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
    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    nosuspend {
        log_system_data.tty_config.setColor(writer, comptime message_level.colour()) catch return;
        writer.print(prefix2 ++ format ++ "\n", args) catch return;
        log_system_data.buffered_writer.flush() catch return;
        log_system_data.tty_config.setColor(writer, .reset) catch return;
    }
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
            .fatal => .bright_cyan,
            .err => .bright_red,
            .warn => .yellow,
            .info => .magenta,
            .debug => .green,
            .trace => .white,
        };
    }
};

const ScopeLevel = struct {
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
