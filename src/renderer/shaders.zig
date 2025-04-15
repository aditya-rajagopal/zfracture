pub const builtin = struct {
    pub const MaterialShader = struct {
        pub const frag: []align(4) const u8 = @alignCast(@embedFile("builtin.MaterialShader.frag"));
        pub const vert: []align(4) const u8 = @alignCast(@embedFile("builtin.MaterialShader.vert"));
    };
};
