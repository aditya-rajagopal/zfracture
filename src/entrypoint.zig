const fracture = @import("fracture");
const core = @import("fr_core");
const app = fracture.config.app_api;
const platform = @import("platform");

pub fn main() !void {
    try core.logging.init();

    var state: platform.PlatformState = undefined;

    try platform.init(&state, "SoulCat", 100, 100, 1280, 720);

    app.start();
    while (true) {
        platform.pump_messages(&state);
    }

    platform.deinit(&state);
    core.logging.deinit();
}
