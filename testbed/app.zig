pub usingnamespace @import("entrypoint");

const fracture = @import("fracture");
const core = @import("fr_core");
const log = fracture.log;

pub const logger_config: core.logging.LogConfig = .{
    .log_fn = core.logging.default_log,
    .app_log_level = core.logging.default_level,
    .custom_scopes = &[_]core.logging.ScopeLevel{
        .{ .scope = .libfoo, .level = .warn },
    },
};

pub const libfoo_logger = core.logging.scoped(.libfoo);

pub const app_api = .{
    .start = start,
};

fn start() void {
    log.trace("All your {s} are belong to us.", .{"games"});
    log.debug("All your {s} are belong to us.", .{"games"});
    log.info("All your {s} are belong to us.", .{"games"});
    log.warn("All your {s} are belong to us.", .{"games"});
    log.err("All your {s} are belong to us.", .{"games"});
    log.fatal("All your {s} are belong to us.", .{"games"});
    libfoo_logger.trace("All your {s} are belong to us.", .{"games"});
    libfoo_logger.fatal("All your {s} are belong to us.", .{"games"});
}

const std = @import("std");
const printf = std.debug.print;
