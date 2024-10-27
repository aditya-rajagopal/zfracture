pub const builtin = struct {
    pub const ObjectShader = struct {
        pub const frag: []const u8 = @embedFile("builtin.ObjectShader.frag");
        pub const vert: []const u8 = @embedFile("builtin.ObjectShader.vert");
    };
};
