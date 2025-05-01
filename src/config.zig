const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
const root = @import("root");

const core = @import("fr_core");

/// HACK: Hard coded DLL name for the game.
/// TODO: Make this configurable
pub const dll_name = "./zig-out/bin/dynamic_game.dll";

pub const app_api: core.API = if (@hasDecl(root, "config") and @hasDecl(root.config, "app_api"))
    root.config.app_api
else
    @compileError("The root.config app must declare app_api");

pub const app_config: core.AppConfig = if (@hasDecl(root, "config") and @hasDecl(root.config, "app_config"))
    root.config.app_config
else
    core.AppConfig{};

comptime {
    assert(app_config.window_pos.width > 0);
    assert(app_config.application_name.len > 0);
    assert(app_config.window_pos.height > 0);
}
