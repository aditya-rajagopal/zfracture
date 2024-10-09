const fracture = @import("fracture");
const core = @import("fr_core");
const app = fracture.config.app_api;

pub fn main() !void {
    try core.logging.init();

    app.start();
    fracture.test_fn();

    core.logging.deinit();
}
