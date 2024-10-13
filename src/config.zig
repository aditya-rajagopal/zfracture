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

pub const client_memory_tags = if (@hasDecl(root, "config") and @hasDecl(root.config, "memory_tags"))
    root.config.memory_tags
else
    enum(u8) {};

pub const client_allocator_tags = if (@hasDecl(root, "config") and @hasDecl(root.config, "allocator_types"))
    root.config.allocator_tags
else
    enum(u8) {};

comptime {
    assert(@typeInfo(client_memory_tags).Enum.tag_type == u8);
    assert(@typeInfo(client_allocator_tags).Enum.tag_type == u8);
}
