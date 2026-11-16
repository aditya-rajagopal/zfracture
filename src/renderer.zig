const std = @import("std");
const types = @import("types.zig");
const collision = @import("collision.zig");
const monogram = @import("monogram.zig");
const Color = types.Color;
const AABB = @import("shapes.zig").AABB;

pub const View = struct {
    meters_per_pixel: f32,
    camera_x: f32,
    camera_y: f32,
};

pub const TextureFilter = enum { bilinear, nearest };

/// A region in texture pixels, measured from the top-left.
pub const SourceRect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
};

pub const RectConfig = struct {
    /// Fractions measured from the unrotated top-left; values outside [0, 1]
    /// place the pivot outside the rectangle.
    pivot_fraction_x: f32 = 0.5,
    pivot_fraction_y: f32 = 0.5,
    /// Positive angles rotate clockwise in Y-down coordinates.
    angle_radians: f32 = 0,
    texture: ?Texture = null,
    /// Stretch this region over the destination. Null selects the whole texture.
    /// Empty or out-of-bounds regions skip the draw. Missing textures use the fallback color.
    source_rect: ?SourceRect = null,
    filter: TextureFilter = .bilinear,
    tint_srgb: ?Color = null,
};

pub const TextConfig = struct {
    scale: u16 = 1,
    /// Bounds in the same units as pushRect. Only whole glyph cells fit.
    width: ?f32 = null,
    height: ?f32 = null,
    /// Wrap continues at the next character. Clip skips to the next newline.
    mode: enum { wrap, clip } = .clip,
    tint_srgb: ?Color = null,
};

/// Measurement and playback consume the same rows, including explicit empty lines.
pub const TextLines = struct {
    lines: std.mem.SplitIterator(u8, .scalar),
    continuation: ?[]const u8 = null,
    columns: usize,
    rows_left: usize,
    mode: @FieldType(TextConfig, "mode"),
    glyph_width: f32,
    glyph_height: f32,

    pub fn init(text: []const u8, config: TextConfig) TextLines {
        const glyph_width: f32 = @floatFromInt(@as(u32, monogram.cell_width) * config.scale);
        const glyph_height: f32 = @floatFromInt(@as(u32, monogram.cell_height) * config.scale);
        return .{
            .lines = std.mem.splitScalar(u8, text, '\n'),
            .columns = cellsThatFit(config.width, glyph_width),
            .rows_left = cellsThatFit(config.height, glyph_height),
            .mode = config.mode,
            .glyph_width = glyph_width,
            .glyph_height = glyph_height,
        };
    }

    fn cellsThatFit(limit: ?f32, cell_size: f32) usize {
        if (cell_size == 0) return 0;
        const extent = limit orelse return std.math.maxInt(usize);
        return std.math.lossyCast(usize, @as(f64, extent) / cell_size);
    }

    pub fn next(self: *TextLines) ?[]const u8 {
        if (self.columns == 0 or self.rows_left == 0) return null;
        const line = self.continuation orelse self.lines.next() orelse return null;
        const count = @min(line.len, self.columns);
        self.continuation = if (self.mode == .wrap and count < line.len) line[count..] else null;
        self.rows_left -= 1;
        return line[0..count];
    }
};

pub fn measureText(text: []const u8, config: TextConfig) struct { width: f32, height: f32 } {
    var lines = TextLines.init(text, config);
    var columns: usize = 0;
    var rows: usize = 0;
    while (lines.next()) |line| {
        columns = @max(columns, line.len);
        rows += 1;
    }
    return .{
        .width = @as(f32, @floatFromInt(columns)) * lines.glyph_width,
        .height = @as(f32, @floatFromInt(rows)) * lines.glyph_height,
    };
}

/// Records one frame into borrowed storage. View changes affect subsequent pushes
/// and queries immediately. Keep commands and referenced textures alive until playback ends.
pub const CommandBuffer = struct {
    commands: std.ArrayList(Command),
    string_bytes: [4096]u8 = undefined,
    string_bytes_used: usize = 0,
    width: u16 = 0,
    height: u16 = 0,
    view: View = undefined,
    visible_bounds: AABB = undefined,

    pub fn reset(self: *CommandBuffer, width: u16, height: u16, clear_color: Color, view: View) void {
        if (width == 0 or height == 0) @panic("Command buffer viewport must be nonempty");
        self.width = width;
        self.height = height;
        self.string_bytes_used = 0;
        self.commands.clearRetainingCapacity();
        self.pushClear(clear_color);
        self.pushView(view);
    }

    pub fn pushView(self: *CommandBuffer, view: View) void {
        std.debug.assert(self.width > 0 and self.height > 0);
        std.debug.assert(view.meters_per_pixel > 0);
        const pixels_per_meter = 1.0 / view.meters_per_pixel;
        const half_width = @as(f32, @floatFromInt(self.width)) * view.meters_per_pixel / 2.0;
        const half_height = @as(f32, @floatFromInt(self.height)) * view.meters_per_pixel / 2.0;
        const bounds: AABB = .{
            .min_x = view.camera_x - half_width,
            .min_y = view.camera_y - half_height,
            .max_x = view.camera_x + half_width,
            .max_y = view.camera_y + half_height,
        };
        // This positive sum propagates NaN and bounds the reciprocal and all
        // camera/bounds arithmetic without checking every component separately.
        const coordinate_bound = pixels_per_meter + @abs(view.camera_x) + @abs(view.camera_y) + half_width + half_height;
        if (!std.math.isFinite(coordinate_bound)) @panic("Invalid renderer view");
        self.commands.appendBounded(.{ .set_view = view }) catch @panic("Frontend command buffer capacity exceeded");
        self.view = view;
        self.visible_bounds = bounds;
    }

    pub fn pushClear(self: *CommandBuffer, color: Color) void {
        self.commands.appendBounded(.{ .clear_screen = .{ .r = color.r, .g = color.g, .b = color.b } }) catch @panic("Frontend command buffer capacity exceeded");
    }

    pub fn pushRect(
        self: *CommandBuffer,
        pivot_world_x: f32,
        pivot_world_y: f32,
        width: f32,
        height: f32,
        config: RectConfig,
    ) void {
        std.debug.assert(self.width > 0 and self.height > 0);
        if (width <= 0 or height <= 0) return;
        const rectangle = RectangleGeometry.init(
            pivot_world_x,
            pivot_world_y,
            width,
            height,
            config.pivot_fraction_x,
            config.pivot_fraction_y,
            config.angle_radians,
        );
        const world_bounds = rectangle.bounds();
        if (!collision.overlapAABBAABB(world_bounds, self.visible_bounds)) return;
        self.commands.appendBounded(.{ .draw_rectangle = .{
            .rectangle = rectangle,
            .texture = config.texture,
            .source_rect = config.source_rect,
            .filter = config.filter,
            .tint_srgb = config.tint_srgb,
        } }) catch @panic("Frontend command buffer capacity exceeded");
    }

    /// Draw from the top-left using a Monogram atlas. Text is copied before returning.
    /// Exceeding the frame's 4096-byte string buffer panics, like exceeding the command buffer.
    pub fn pushText(
        self: *CommandBuffer,
        x: f32,
        y: f32,
        text: []const u8,
        font: Texture,
        config: TextConfig,
    ) void {
        std.debug.assert(self.width > 0 and self.height > 0);
        if (text.len == 0 or config.scale == 0) return;
        const start = self.string_bytes_used;
        if (text.len > self.string_bytes.len - start) @panic("Frame string buffer capacity exceeded");
        self.commands.appendBounded(.{ .draw_text = .{
            .x = x,
            .y = y,
            .string_offset = @intCast(start),
            .string_len = @intCast(text.len),
            .font = font,
            .config = config,
        } }) catch @panic("Frontend command buffer capacity exceeded");
        @memcpy(self.string_bytes[start..][0..text.len], text);
        self.string_bytes_used += text.len;
    }

    pub fn screenFromWorld(self: *const CommandBuffer, x: f32, y: f32) struct { x: f32, y: f32 } {
        return .{
            .x = (x - self.view.camera_x) / self.view.meters_per_pixel + @as(f32, @floatFromInt(self.width)) / 2.0,
            .y = (y - self.view.camera_y) / self.view.meters_per_pixel + @as(f32, @floatFromInt(self.height)) / 2.0,
        };
    }

    pub fn worldFromScreen(self: *const CommandBuffer, x: f32, y: f32) struct { x: f32, y: f32 } {
        return .{
            .x = (x - @as(f32, @floatFromInt(self.width)) / 2.0) * self.view.meters_per_pixel + self.view.camera_x,
            .y = (y - @as(f32, @floatFromInt(self.height)) / 2.0) * self.view.meters_per_pixel + self.view.camera_y,
        };
    }
};

pub const RectangleGeometry = struct {
    origin_x: f32,
    origin_y: f32,
    width: f32,
    height: f32,
    right_x: f32,
    right_y: f32,

    pub fn init(
        pivot_x: f32,
        pivot_y: f32,
        width: f32,
        height: f32,
        pivot_fraction_x: f32,
        pivot_fraction_y: f32,
        angle_radians: f32,
    ) RectangleGeometry {
        const offset_x = pivot_fraction_x * width;
        const offset_y = pivot_fraction_y * height;
        const right_x: f32 = if (angle_radians == 0) 1 else @cos(angle_radians);
        const right_y: f32 = if (angle_radians == 0) 0 else @sin(angle_radians);
        const origin_x = pivot_x - (offset_x * right_x - offset_y * right_y);
        const origin_y = pivot_y - (offset_x * right_y + offset_y * right_x);

        return .{
            .origin_x = origin_x,
            .origin_y = origin_y,
            .width = width,
            .height = height,
            .right_x = right_x,
            .right_y = right_y,
        };
    }

    /// Compute bounds in this geometry's coordinate space, including after a
    /// camera transform. Rotating a cached AABB instead would give looser bounds.
    pub fn bounds(self: RectangleGeometry) AABB {
        const x = self.origin_x;
        const y = self.origin_y;
        const down_x = -self.right_y;
        const down_y = self.right_x;
        const p1_x = x + self.width * self.right_x;
        const p1_y = y + self.width * self.right_y;
        const p2_x = x + self.height * down_x;
        const p2_y = y + self.height * down_y;
        const p3_x = x + self.height * down_x + self.width * self.right_x;
        const p3_y = y + self.height * down_y + self.width * self.right_y;

        return .{
            .min_x = @min(x, p1_x, p2_x, p3_x),
            .min_y = @min(y, p1_y, p2_y, p3_y),
            .max_x = @max(x, p1_x, p2_x, p3_x),
            .max_y = @max(y, p1_y, p2_y, p3_y),
        };
    }
};

pub const Command = union(CommandType) {
    set_view: View,
    clear_screen: ClearCommand,
    draw_rectangle: DrawRectangleCommand,
    draw_text: DrawTextCommand,
};

pub const CommandType = enum(u8) {
    set_view,
    clear_screen,
    draw_rectangle,
    draw_text,
};

pub const ClearCommand = struct {
    r: f32,
    g: f32,
    b: f32,
};

pub const DrawRectangleCommand = struct {
    rectangle: RectangleGeometry,
    texture: ?Texture = null,
    source_rect: ?SourceRect = null,
    filter: TextureFilter = .bilinear,
    tint_srgb: ?Color = null,
};

pub const DrawTextCommand = struct {
    x: f32,
    y: f32,
    string_offset: u16,
    string_len: u16,
    font: Texture,
    config: TextConfig,
};

pub const Texture = enum(u32) {
    missing_texture = 0,
    _,
};

test "measureText fits whole cells and counts spaces and explicit empty lines" {
    const Case = struct { text: []const u8, config: TextConfig, width: f32, height: f32 };
    const cases = [_]Case{
        .{ .text = "A B \nC", .config = .{ .scale = 2 }, .width = 48, .height = 48 },
        .{ .text = "ABCD", .config = .{ .width = 17.5, .mode = .wrap }, .width = 12, .height = 24 },
        .{ .text = "ABCD", .config = .{ .width = 17.5, .mode = .clip }, .width = 12, .height = 12 },
        .{ .text = "AB\n\nC\n", .config = .{ .width = 12, .mode = .wrap }, .width = 12, .height = 48 },
        .{ .text = "ABCD", .config = .{ .width = 6, .height = 35.5, .mode = .wrap }, .width = 6, .height = 24 },
        .{ .text = "A", .config = .{ .width = 5, .mode = .wrap }, .width = 0, .height = 0 },
        .{ .text = "A", .config = .{ .height = 11 }, .width = 0, .height = 0 },
        .{ .text = "A", .config = .{ .scale = 0 }, .width = 0, .height = 0 },
        .{ .text = "A", .config = .{ .scale = 65535 }, .width = 393210, .height = 786420 },
        .{ .text = "", .config = .{}, .width = 0, .height = 12 },
    };
    for (cases) |case| {
        const size = measureText(case.text, case.config);
        try std.testing.expectEqual(case.width, size.width);
        try std.testing.expectEqual(case.height, size.height);
    }
}
