const std = @import("std");

// NOTE: We dont need this to be a simd structure because we realistically only want to use
// structure of arrays where each array is 1 colour channel.
pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    const Self = @This();

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
