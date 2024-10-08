const fracture = @import("fracture");
const app = fracture.config.app_api;

pub fn main() !void {
    app.start();
    fracture.test_fn();
}
