const fracture = @import("fracture");
const core = @import("fr_core");
const app = fracture.config.app_api;

pub fn main() !void {
    try core.log.init();
    app.start();
    fracture.test_fn();
    core.log.deinit();
}
