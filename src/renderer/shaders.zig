pub const builtin = struct {
    pub const ObjectShader = struct {
        pub const frag: []align(4) const u8 = @alignCast(@embedFile("builtin.ObjectShader.frag"));
        pub const vert: []align(4) const u8 = @alignCast(@embedFile("builtin.ObjectShader.vert"));
    };
};
