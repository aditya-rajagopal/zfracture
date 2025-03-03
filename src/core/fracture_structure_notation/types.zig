pub const Version = packed struct(u32) {
    major: u4 = 0,
    minor: u12 = 0,
    patch: u16 = 0,

    pub fn init(major: u4, minor: u12, patch: u16) Version {
        return Version{
            .major = major,
            .minor = minor,
            .patch = patch,
        };
    }
};

pub const MaterialConfig = struct {
    data: u8 = 0,
    // data2: i8 = 0,
    // data3: f32 = 0,
    // data4: [3]f32 = [_]f32{ 0.0, 0.0, 0.0 },
    // data5: [4]f32 = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
    // data6: [2]f32 = [_]f32{ 0.0, 0.0 },
    // data7: [16]u8 = undefined,
    //
    // @data2: i8 = -10
    // @data3: f32 = 1.523425
    // @data4: vec3s = {1.23, 2522.2523, 5}
    // @data5: vec4s = {1.23, 2522.2523, 5, 32.2352}
    // @data6: vec2s = {1.23, 2522.2523}
    // @data7: string = "test_string"

    pub const version: Version = Version.init(0, 0, 1);
};
