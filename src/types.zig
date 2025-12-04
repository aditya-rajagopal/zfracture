const std = @import("std");

// NOTE: We dont need this to be a simd structure because we realistically only want to use
// structure of arrays where each array is 1 colour channel.
pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    const Self = @This();

    pub const white = Self{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
    pub const black = Self{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 };
    pub const magenta = Self{ .r = 0.961, .g = 0.259, .b = 0.741, .a = 1.0 };

    /// Grey that is 50% as bright as full white gamma corrected. Light grey is 75% as bright and dark grey is 25% as bright.
    /// Gamma power used is 2.2
    pub const grey = Self{ .r = 0.730, .g = 0.730, .b = 0.730, .a = 1.0 };
    pub const light_grey = Self{ .r = 0.877, .g = 0.877, .b = 0.877, .a = 1.0 };
    pub const dark_grey = Self{ .r = 0.533, .g = 0.533, .b = 0.533, .a = 1.0 };

    pub const pure_red = Self{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 };
    pub const red = Self{ .r = 0.902, .g = 0.161, .b = 0.216, .a = 1.0 };
    pub const dark_red = Self{ .r = 0.388, .g = 0.0, .b = 0.027, .a = 1.0 };
    pub const light_red = Self{ .r = 0.98, .g = 0.482, .b = 0.522, .a = 1.0 };
    pub const bright_red = Self{ .r = 0.992, .g = 0.702, .b = 0.722, .a = 1.0 };

    pub const pure_green = Self{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 };
    pub const green = Self{ .r = 0.224, .g = 0.765, .b = 0.137, .a = 1.0 };
    pub const dark_green = Self{ .r = 0.043, .g = 0.329, .b = 0.0, .a = 1.0 };
    pub const light_green = Self{ .r = 0.494, .g = 0.875, .b = 0.431, .a = 1.0 };
    pub const bright_green = Self{ .r = 0.702, .g = 0.937, .b = 0.663, .a = 1.0 };

    pub const pure_blue = Self{ .r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0 };
    pub const blue = Self{ .r = 0.18, .g = 0.243, .b = 0.635, .a = 1.0 };
    pub const dark_blue = Self{ .r = 0.02, .g = 0.055, .b = 0.275, .a = 1.0 };
    pub const light_blue = Self{ .r = 0.435, .g = 0.482, .b = 0.776, .a = 1.0 };
    pub const bright_blue = Self{ .r = 0.663, .g = 0.69, .b = 0.886, .a = 1.0 };

    pub const pure_yellow = Self{ .r = 1.0, .g = 1.0, .b = 0.0, .a = 1.0 };
    pub const yellow = Self{ .r = 0.925, .g = 0.71, .b = 0.165, .a = 1.0 };
    pub const dark_yellow = Self{ .r = 0.400, .g = 0.286, .b = 0.0, .a = 1.0 };
    pub const light_yellow = Self{ .r = 1.0, .g = 0.855, .b = 0.494, .a = 1.0 };
    pub const bright_yellow = Self{ .r = 1.0, .g = 0.918, .b = 0.706, .a = 1.0 };

    pub const pure_purple = Self{ .r = 1.0, .g = 0.0, .b = 1.0, .a = 1.0 };
    pub const purple = Self{ .r = 0.627, .g = 0.125, .b = 0.941, .a = 1.0 };
    pub const brown = Self{ .r = 0.52, .g = 0.415, .b = 0.30, .a = 1.0 };
    pub const dark_brown = Self{ .r = 0.286, .g = 0.216, .b = 0.145, .a = 1.0 };

    // const shifts: @Vector(4, u32) = .{ std.math.pow(u32, 2, 16), std.math.pow(u32, 2, 8), 1, std.math.pow(u32, 2, 24) };
    // const scale: @Vector(4, f32) = @splat(255.0);
    // const lower_8bits_mask: @Vector(4, u32) = .{ 0xFF, 0xFF, 0xFF, 0xFF };

    // @TODO: inline?
    pub fn a8r8g8b8(self: Self) u32 {
        // @TODO: Should this can be simded?
        // var vec4: @Vector(4, f32) = .{ self.r, self.g, self.b, self.a };
        // vec4 = vec4 * scale;
        // const vec4_ints: @Vector(4, u32) = @intFromFloat(vec4);
        // const vec4_shifted = (vec4_ints & lower_8bits_mask) * shifts;
        // const colour: u32 = @reduce(.Or, vec4_shifted);

        const r_int: u8 = @truncate(@as(u32, @intFromFloat(@round(self.r * 255.0))));
        const g_int: u8 = @truncate(@as(u32, @intFromFloat(@round(self.g * 255.0))));
        const b_int: u8 = @truncate(@as(u32, @intFromFloat(@round(self.b * 255.0))));
        const a_int: u8 = @truncate(@as(u32, @intFromFloat(@round(self.a * 255.0))));
        const colour: u32 =
            (@as(u32, @intCast(a_int)) << 24) |
            (@as(u32, @intCast(r_int)) << 16) |
            (@as(u32, @intCast(g_int)) << 8) |
            @as(u32, @intCast(b_int));
        return colour;
    }
};
