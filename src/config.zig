const root = @import("root");
const std = @import("std");
const assert = std.debug.assert;
const types = @import("types/types.zig");

pub const app_api: types.API = if (@hasDecl(root, "config") and @hasDecl(root.config, "app_api"))
    root.config.app_api
else
    @compileError("The root.config app must declare app_api");

pub const app_config: types.AppConfig = if (@hasDecl(root, "config") and @hasDecl(root.config, "app_config"))
    root.config.app_config
else
    types.AppConfig{};

comptime {
    assert(app_config.window_pos.width > 0);
    assert(app_config.application_name.len > 0);
    assert(app_config.window_pos.height > 0);
}
