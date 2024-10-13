pub usingnamespace @import("application_t.zig");

pub usingnamespace @import("event_t.zig");

pub const Fracture = struct {
    memory: app_t.Memory,
    core_log: core.log.CoreLog,
    log: core.log.GameLog,
    is_suspended: bool = false,
    is_running: bool = false,
    width: i32 = 1280,
    height: i32 = 720,
    last_time: f64 = 0,
};

const std = @import("std");
const app_t = @import("application_t.zig");
const event_t = @import("event_t.zig");
const core = @import("fr_core");
