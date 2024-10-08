pub usingnamespace @import("entrypoint");

const fracture = @import("fracture");
const log = fracture.log;

pub const log_level = fracture.core.log.default_level;
pub const log_fn = fracture.core.log.default_log;

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
}

const std = @import("std");
const printf = std.debug.print;
