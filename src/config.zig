const root = @import("root");

pub const API = struct {
    start: *const fn () void,
};
pub const app_api: API = if (@hasDecl(root, "app_api")) root.app_api else @compileError("The root app must declare API");
