const fracture = @import("fracture");
const core = @import("fr_core");
const game = @import("game.zig");

pub const app_api: fracture.config.API = .{
    .init = game.init,
    .deinit = game.deinit,
    .update = game.update,
    .render = game.render,
    .on_resize = game.on_resize,
};

pub const app_config: fracture.config.AppConfig = .{
    .application_name = "Testbed",
    .window_pos = .{ .x = 100, .y = 100, .width = 1280, .height = 720 },
};

pub const logger_config: core.logging.LogConfig = .{
    .log_fn = core.logging.default_log,
    .app_log_level = core.logging.default_level,
    .custom_scopes = &[_]core.logging.ScopeLevel{
        .{ .scope = .libfoo, .level = .warn },
    },
};
