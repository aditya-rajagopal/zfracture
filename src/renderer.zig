const std = @import("std");
const types = @import("types.zig");
const collision = @import("collision.zig");
const Color = types.Color;
const AABB = @import("shapes.zig").AABB;

pub const View = struct {
    meters_per_pixel: f32,
    camera_x: f32,
    camera_y: f32,
};

pub const RectConfig = struct {
    /// Fractions measured from the unrotated top-left; values outside [0, 1]
    /// place the pivot outside the rectangle.
    pivot_fraction_x: f32 = 0.5,
    pivot_fraction_y: f32 = 0.5,
    /// Positive angles rotate clockwise in Y-down coordinates.
    angle_radians: f32 = 0,
    texture: ?Texture = null,
    tint_srgb: ?Color = null,
};

/// Records one frame into borrowed storage. View changes affect subsequent pushes
/// and queries immediately. Keep commands and referenced textures alive until playback ends.
pub const CommandBuffer = struct {
    commands: std.ArrayList(Command),
    width: u16 = 0,
    height: u16 = 0,
    view: View = undefined,
    visible_bounds: AABB = undefined,

    pub fn reset(self: *CommandBuffer, width: u16, height: u16, clear_color: Color, view: View) void {
        if (width == 0 or height == 0) @panic("Command buffer viewport must be nonempty");
        self.width = width;
        self.height = height;
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
            .tint_srgb = config.tint_srgb,
        } }) catch @panic("Frontend command buffer capacity exceeded");
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
};

pub const CommandType = enum(u8) {
    set_view,
    clear_screen,
    draw_rectangle,
};

pub const ClearCommand = struct {
    r: f32,
    g: f32,
    b: f32,
};

pub const DrawRectangleCommand = struct {
    rectangle: RectangleGeometry,
    texture: ?Texture = null,
    tint_srgb: ?Color = null,
};

pub const Texture = enum(u32) {
    missing_texture = 0,
    _,
};
