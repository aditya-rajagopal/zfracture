const core = @import("fr_core");
const game = @import("game.zig");

pub const app_api: core.API = .{
    .init = game.init,
    .deinit = game.deinit,
    .update_and_render = game.update_and_render,
    .on_resize = game.on_resize,
};

pub const app_config: core.AppConfig = .{
    .application_name = "Testbed",
    .window_pos = .{ .x = 0, .y = 0, .width = 1920, .height = 1080 },
    .frame_arena_preheat_size = .{ .MB = 512 },
};

pub const renderer_backend = @import("vulkan_backend");
