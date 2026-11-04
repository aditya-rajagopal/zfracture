const std = @import("std");
const assert = std.debug.assert;
const profile = @import("profiling.zig");

const types = @import("types.zig");
const Color = types.Color;
const Bitmap = @import("bitmap.zig");
const png = @import("stdx/png.zig");

const AABB = @import("shapes.zig").AABB;
const FrameBuffer = @import("FrameBuffer.zig");

const Renderer = @import("renderer.zig");

const Self = @This();

back_buffer: FrameBuffer,
front_face_winding_order: @FieldType(Config, "front_face_winding_order") = .clockwise,
cull_mode: @FieldType(Config, "cull_mode") = .back,
textures: [32]Bitmap,
head: u8 = 1,
prepared_commands: PreparedCommandBuffer,
command_buffer: Renderer.CommandBuffer,

const render_tile_size: u64 = 64;

const Tile = [render_tile_size * render_tile_size]u32;
const tile_alignment = std.heap.page_size_max;

const TileBounds = struct {
    min_x: u16,
    min_y: u16,
    max_x: u16,
    max_y: u16,

    fn init(bounds: AABB) TileBounds {
        const min_x: u16 = @intFromFloat(bounds.min_x);
        const min_y: u16 = @intFromFloat(bounds.min_y);
        const max_x: u16 = @intFromFloat(bounds.max_x);
        const max_y: u16 = @intFromFloat(bounds.max_y);
        assert(min_x < max_x);
        assert(min_y < max_y);
        return .{
            .min_x = @intCast(min_x / render_tile_size),
            .min_y = @intCast(min_y / render_tile_size),
            .max_x = @intCast((max_x - 1) / render_tile_size + 1),
            .max_y = @intCast((max_y - 1) / render_tile_size + 1),
        };
    }
};

const TileBins = struct {
    offsets: []usize,
    headers: []PreparedCommandBuffer.Header,
};

const PreparedCommandBuffer = struct {
    pub const data_alignment = @max(
        @alignOf(Internal.ClearCommand),
        @alignOf(Internal.DrawRectangleCommand),
        @alignOf(Internal.DrawSpriteCommand),
        @alignOf(Internal.DrawTexturedRectangleCommand),
    );

    const Header = struct {
        tag: Internal.CommandType,
        offset: u32,
    };

    headers: []Header,
    data: []align(data_alignment) u8,
    tile_bounds: []TileBounds,

    fn bin(self: PreparedCommandBuffer, cols: usize, rows: usize, arena: std.mem.Allocator) !TileBins {
        assert(self.headers.len == self.tile_bounds.len);
        assert(self.headers.len <= MAX_COMMANDS);
        assert(cols <= 1024 and rows <= 1024); // ceil(maxInt(u16) / 64)
        const tile_count = cols * rows;
        const counts = try arena.alloc(u16, tile_count);
        @memset(counts, 0);

        for (self.tile_bounds) |bounds| {
            assert(bounds.min_x <= bounds.max_x and bounds.max_x <= cols);
            assert(bounds.min_y <= bounds.max_y and bounds.max_y <= rows);
            for (bounds.min_y..bounds.max_y) |row| {
                for (bounds.min_x..bounds.max_x) |col| {
                    counts[row * cols + col] += 1;
                }
            }
        }

        const offsets = try arena.alloc(usize, tile_count + 1);
        offsets[0] = 0;
        for (counts, 0..) |count, tile| {
            assert(count <= self.headers.len);
            offsets[tile + 1] = offsets[tile] + count;
        }
        const headers = try arena.alloc(Header, offsets[tile_count]);

        // Reuse the counts as write cursors. Walking commands in submission order
        // preserves blending and clear barriers without sorting each tile's bin.
        @memset(counts, 0);
        for (self.tile_bounds, self.headers) |bounds, header| {
            for (bounds.min_y..bounds.max_y) |row| {
                for (bounds.min_x..bounds.max_x) |col| {
                    const tile = row * cols + col;
                    const destination = offsets[tile] + counts[tile];
                    assert(destination < offsets[tile + 1]);
                    headers[destination] = header;
                    counts[tile] += 1;
                }
            }
        }
        return .{ .offsets = offsets, .headers = headers };
    }
};

pub const Config = struct {
    width: u16,
    height: u16,
    missing_texture_color: Color,
    front_face_winding_order: enum { clockwise, anticlockwise } = .clockwise,
    cull_mode: enum { none, front, back } = .back,
};

const MAX_COMMANDS = 4096;
const MAX_FRONTEND_COMMANDS = 8192;
const max_command_size = std.mem.alignForward(
    usize,
    @max(
        @sizeOf(Internal.ClearCommand),
        @sizeOf(Internal.DrawRectangleCommand),
        @sizeOf(Internal.DrawSpriteCommand),
        @sizeOf(Internal.DrawTexturedRectangleCommand),
    ),
    PreparedCommandBuffer.data_alignment,
);
// HACK: Figure out a better estimate. We should proabbly use stdx.GrowingBuffer
const MAX_DATA = MAX_COMMANDS * max_command_size;

pub fn init(
    self: *Self,
    gpa: std.mem.Allocator,
    config: Config,
) !void {
    self.back_buffer = try .initCapacity(config.width, config.height, gpa);
    errdefer self.back_buffer.deinit(gpa);

    const headers = try gpa.alloc(PreparedCommandBuffer.Header, MAX_COMMANDS);
    errdefer gpa.free(headers);

    const tile_bounds = try gpa.alloc(TileBounds, MAX_COMMANDS);
    errdefer gpa.free(tile_bounds);

    const data = try gpa.alignedAlloc(
        u8,
        .fromByteUnits(PreparedCommandBuffer.data_alignment),
        MAX_DATA,
    );
    errdefer gpa.free(data);

    var commands = try std.ArrayList(Renderer.Command).initCapacity(gpa, MAX_FRONTEND_COMMANDS);
    errdefer commands.deinit(gpa);

    const missing_pixels = try gpa.alloc(u32, 1);
    missing_pixels[0] = config.missing_texture_color.toARGB();

    self.prepared_commands = .{ .headers = headers, .data = data, .tile_bounds = tile_bounds };
    self.prepared_commands.headers.len = 0;
    self.prepared_commands.data.len = 0;
    self.prepared_commands.tile_bounds.len = 0;
    self.command_buffer = .{ .commands = commands };
    self.front_face_winding_order = config.front_face_winding_order;
    self.cull_mode = config.cull_mode;
    self.textures = @splat(.{ .width = 1, .height = 1, .pixels = missing_pixels });
    self.head = 1;
}

pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
    gpa.free(self.back_buffer.data);
    self.command_buffer.commands.deinit(gpa);
    self.prepared_commands.headers.len = MAX_COMMANDS;
    self.prepared_commands.data.len = MAX_DATA;
    self.prepared_commands.tile_bounds.len = MAX_COMMANDS;
    gpa.free(self.prepared_commands.headers);
    gpa.free(self.prepared_commands.data);
    gpa.free(self.prepared_commands.tile_bounds);
    for (self.textures[0..self.head]) |texture| {
        gpa.free(texture.pixels);
    }
}

const Internal = struct {
    pub const CommandType = enum(u8) {
        clear_screen,
        draw_rectangle,
        draw_sprite,
        draw_textured_rectangle,
    };

    pub const ClearCommand = struct {
        color: u32,
    };

    pub const DrawTexturedRectangleCommand = struct {
        rectangle: PreparedRectangle,
        texture: Bitmap,
        tint: LinearColor,
        texels_per_pixel_x: f32,
        texels_per_pixel_y: f32,
    };

    pub const DrawSpriteCommand = struct {
        rectangle: PreparedSprite,
        texture: Bitmap,
        texels_per_pixel_x: f32,
        texels_per_pixel_y: f32,
    };

    pub const DrawRectangleCommand = struct {
        rectangle: PreparedRectangle,
        color: PreparedSolidColor,
    };
};

/// Gamma-2 decoded RGB, premultiplied by alpha
const LinearColor = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    fn init(color: Color) LinearColor {
        @setFloatMode(.optimized);
        return .{
            .r = color.r * color.r * color.a,
            .g = color.g * color.g * color.a,
            .b = color.b * color.b * color.a,
            .a = color.a,
        };
    }
};

const PreparedSolidColor = struct {
    linear: LinearColor,
    opaque_pixel: u32,

    fn init(color: Color) PreparedSolidColor {
        @setFloatMode(.optimized);
        const linear = LinearColor.init(color);
        return .{
            .linear = linear,
            // Preserve the rasterizer's gamma-2 round trip and quantization.
            .opaque_pixel = if (linear.a == 1) @bitCast([_]u8{
                @truncate(@as(u32, @intFromFloat(@round(@sqrt(linear.b) * 255.0)))),
                @truncate(@as(u32, @intFromFloat(@round(@sqrt(linear.g) * 255.0)))),
                @truncate(@as(u32, @intFromFloat(@round(@sqrt(linear.r) * 255.0)))),
                255,
            }) else 0,
        };
    }
};

/// The returned recorder borrows renderer-owned storage until the next frame.
pub fn beginDrawing(self: *Self, clear_color: Color, view: Renderer.View) *Renderer.CommandBuffer {
    self.command_buffer.reset(self.back_buffer.width, self.back_buffer.height, clear_color, view);
    return &self.command_buffer;
}

fn prepareCommands(self: *Self, command_buffer: *const Renderer.CommandBuffer) void {
    assert(command_buffer.width == self.back_buffer.width and command_buffer.height == self.back_buffer.height);
    const commands = command_buffer.commands.items;
    assert(commands.len >= 2);
    assert(commands[0] == .clear_screen and commands[1] == .set_view);

    self.prepared_commands.headers.len = 0;
    self.prepared_commands.data.len = 0;
    self.prepared_commands.tile_bounds.len = 0;
    var view = commands[1].set_view;
    var pixels_per_meter = 1.0 / view.meters_per_pixel;
    for (commands) |command| {
        assert(self.prepared_commands.headers.len == self.prepared_commands.tile_bounds.len);

        const tag_head = self.prepared_commands.headers.len;
        var header: PreparedCommandBuffer.Header = undefined;
        var tile_bounds: TileBounds = undefined;

        switch (command) {
            .clear_screen => |cc| {
                if (tag_head >= MAX_COMMANDS) @panic("Prepared command buffer capacity exceeded");
                tile_bounds = .{
                    .min_x = 0,
                    .min_y = 0,
                    .max_x = @intCast((self.back_buffer.width + render_tile_size - 1) / render_tile_size),
                    .max_y = @intCast((self.back_buffer.height + render_tile_size - 1) / render_tile_size),
                };
                const bytes = std.mem.asBytes(&Internal.ClearCommand{ .color = packClear(cc.r, cc.g, cc.b) });
                const start = std.mem.alignForward(usize, self.prepared_commands.data.len, @alignOf(Internal.ClearCommand));
                self.prepared_commands.data.len = start + bytes.len;
                assert(self.prepared_commands.data.len <= MAX_DATA);
                const dest: []align(@alignOf(Internal.ClearCommand)) u8 = @alignCast(self.prepared_commands.data[start..][0..bytes.len]);
                @memcpy(dest, bytes);
                header = .{ .tag = .clear_screen, .offset = @truncate(start) };
            },
            .set_view => |next| {
                view = next;
                pixels_per_meter = 1.0 / next.meters_per_pixel;
                continue;
            },
            .draw_rectangle => |rect| {
                const world = rect.rectangle;
                const screen: Renderer.RectangleGeometry = .{
                    .origin_x = (world.origin_x - view.camera_x) * pixels_per_meter + @as(f32, @floatFromInt(self.back_buffer.width)) / 2.0,
                    .origin_y = (world.origin_y - view.camera_y) * pixels_per_meter + @as(f32, @floatFromInt(self.back_buffer.height)) / 2.0,
                    .width = world.width * pixels_per_meter,
                    .height = world.height * pixels_per_meter,
                    .right_x = world.right_x,
                    .right_y = world.right_y,
                };
                const axis_aligned = screen.right_x == 1 and screen.right_y == 0;
                var rounding: PreparedRectangle.BoundsRounding = .outward;
                if (rect.texture == null and axis_aligned) rounding = .pixel_centres;
                const rectangle = PreparedRectangle.init(self.back_buffer, screen, rounding) orelse continue;

                if (tag_head >= MAX_COMMANDS) @panic("Prepared command buffer capacity exceeded");
                tile_bounds = TileBounds.init(rectangle.bounds);

                if (rect.texture) |texture| {
                    @setFloatMode(.optimized);
                    const bitmap = self.getTexture(texture);
                    assert(rectangle.width > 0 and rectangle.height > 0);
                    const texels_per_pixel_x = @as(f32, @floatFromInt(bitmap.width)) / rectangle.width;
                    const texels_per_pixel_y = @as(f32, @floatFromInt(bitmap.height)) / rectangle.height;
                    if (axis_aligned and rect.tint_srgb == null) {
                        const bytes = std.mem.asBytes(&Internal.DrawSpriteCommand{
                            .rectangle = PreparedSprite.fromRectangle(rectangle),
                            .texture = bitmap,
                            .texels_per_pixel_x = texels_per_pixel_x,
                            .texels_per_pixel_y = texels_per_pixel_y,
                        });
                        const start = std.mem.alignForward(usize, self.prepared_commands.data.len, @alignOf(Internal.DrawSpriteCommand));
                        self.prepared_commands.data.len = start + bytes.len;
                        assert(self.prepared_commands.data.len <= MAX_DATA);
                        const dest: []align(@alignOf(Internal.DrawSpriteCommand)) u8 = @alignCast(self.prepared_commands.data[start..][0..bytes.len]);
                        @memcpy(dest, bytes);
                        header = .{ .tag = .draw_sprite, .offset = @truncate(start) };
                    } else {
                        const bytes = std.mem.asBytes(&Internal.DrawTexturedRectangleCommand{
                            .rectangle = rectangle,
                            .texture = bitmap,
                            .texels_per_pixel_x = texels_per_pixel_x,
                            .texels_per_pixel_y = texels_per_pixel_y,
                            .tint = LinearColor.init(rect.tint_srgb orelse .white),
                        });
                        const start = std.mem.alignForward(usize, self.prepared_commands.data.len, @alignOf(Internal.DrawTexturedRectangleCommand));
                        self.prepared_commands.data.len = start + bytes.len;
                        assert(self.prepared_commands.data.len <= MAX_DATA);
                        const dest: []align(@alignOf(Internal.DrawTexturedRectangleCommand)) u8 = @alignCast(self.prepared_commands.data[start..][0..bytes.len]);
                        @memcpy(dest, bytes);
                        header = .{ .tag = .draw_textured_rectangle, .offset = @truncate(start) };
                    }
                } else {
                    const colour = if (rect.tint_srgb) |tint| tint else Color.magenta;
                    const bytes = std.mem.asBytes(&Internal.DrawRectangleCommand{
                        .rectangle = rectangle,
                        .color = PreparedSolidColor.init(colour),
                    });
                    const start = std.mem.alignForward(usize, self.prepared_commands.data.len, @alignOf(Internal.DrawRectangleCommand));
                    self.prepared_commands.data.len = start + bytes.len;
                    assert(self.prepared_commands.data.len <= MAX_DATA);
                    const dest: []align(@alignOf(Internal.DrawRectangleCommand)) u8 = @alignCast(self.prepared_commands.data[start..][0..bytes.len]);
                    @memcpy(dest, bytes);
                    header = .{ .tag = .draw_rectangle, .offset = @truncate(start) };
                }
            },
        }
        self.prepared_commands.headers.len += 1;
        self.prepared_commands.tile_bounds.len += 1;
        self.prepared_commands.headers[tag_head] = header;
        self.prepared_commands.tile_bounds[tag_head] = tile_bounds;
    }
}

/// Render and copy one tile using private stack scratch. Tile IDs are zero-based
/// column/row coordinates; shared command data stays in screen space. Keep headers,
/// payloads and referenced textures immutable and alive until all tile calls finish.
pub fn renderTile(
    back_buffer: FrameBuffer,
    tile_id: struct { x: usize, y: usize },
    headers: []const PreparedCommandBuffer.Header,
    command_data: []align(PreparedCommandBuffer.data_alignment) const u8,
) void {
    const tile_x: f32 = @floatFromInt(tile_id.x * render_tile_size);
    const tile_y: f32 = @floatFromInt(tile_id.y * render_tile_size);
    const tile_bounds: AABB = .{
        .min_x = tile_x,
        .max_x = @as(f32, @floatFromInt((tile_id.x + 1) * render_tile_size)),
        .min_y = tile_y,
        .max_y = @as(f32, @floatFromInt((tile_id.y + 1) * render_tile_size)),
    };
    const range = clipped(
        back_buffer.width,
        back_buffer.height,
        tile_bounds.min_x,
        tile_bounds.min_y,
        tile_bounds.max_x,
        tile_bounds.max_y,
    ) orelse unreachable;

    const x_min: usize = @intFromFloat(range.min_x);
    const y_min: usize = @intFromFloat(range.min_y);
    const x_max: usize = @intFromFloat(range.max_x);
    const y_max: usize = @intFromFloat(range.max_y);

    const destination_pixels = back_buffer.pixels();
    const copy_width = x_max - x_min;
    if (headers.len == 1 and headers[0].tag == .clear_screen) {
        const trace = profile.begin(.renderer_clear);
        defer profile.end(trace);
        const cc = readClearCommand(headers[0], command_data);
        for (y_min..y_max) |y| {
            const start = y * @as(usize, back_buffer.width) + x_min;
            @memset(destination_pixels[start..][0..copy_width], cc.color);
        }
        return;
    }

    var tile_pixels: Tile align(tile_alignment) = undefined;
    for (headers) |header| {
        switch (header.tag) {
            .clear_screen => {
                const trace = profile.begin(.renderer_clear);
                defer profile.end(trace);
                const cc = readClearCommand(header, command_data);
                @memset(&tile_pixels, cc.color);
            },
            .draw_rectangle => {
                const size = @sizeOf(Internal.DrawRectangleCommand);
                assert(command_data.len >= header.offset);
                assert(command_data.len - header.offset >= size);
                const rect: *const Internal.DrawRectangleCommand = @ptrCast(@alignCast(command_data[header.offset..][0..size]));
                const rectangle = rect.rectangle.forTile(tile_x, tile_y) orelse continue;
                drawRectangle(&tile_pixels, rectangle, rect.color);
            },
            .draw_sprite => {
                const size = @sizeOf(Internal.DrawSpriteCommand);
                assert(command_data.len >= header.offset);
                assert(command_data.len - header.offset >= size);
                const sprite: *const Internal.DrawSpriteCommand = @ptrCast(@alignCast(command_data[header.offset..][0..size]));
                const rectangle = sprite.rectangle.forTile(tile_x, tile_y) orelse continue;
                drawSprite(&tile_pixels, rectangle, sprite.texture, sprite.texels_per_pixel_x, sprite.texels_per_pixel_y);
            },
            .draw_textured_rectangle => {
                const size = @sizeOf(Internal.DrawTexturedRectangleCommand);
                assert(command_data.len >= header.offset);
                assert(command_data.len - header.offset >= size);
                const trect: *const Internal.DrawTexturedRectangleCommand = @ptrCast(@alignCast(command_data[header.offset..][0..size]));
                const rectangle = trect.rectangle.forTile(tile_x, tile_y) orelse continue;
                drawTexturedRectangle(&tile_pixels, rectangle, trect.texture, trect.texels_per_pixel_x, trect.texels_per_pixel_y, trect.tint);
            },
        }
    }

    // Tile rows and framebuffer rows have different strides.
    for (y_min..y_max, 0..) |destination_y, source_y| {
        const source_start = source_y * render_tile_size;
        const destination_start = destination_y * @as(usize, back_buffer.width) + x_min;
        @memcpy(
            destination_pixels[destination_start..][0..copy_width],
            tile_pixels[source_start..][0..copy_width],
        );
    }
}

pub fn endDrawing(self: *Self, arena: std.mem.Allocator, command_buffer: *const Renderer.CommandBuffer) void {
    self.prepareCommands(command_buffer);

    if (self.prepared_commands.headers.len == 1 and self.prepared_commands.headers[0].tag == .clear_screen) {
        const trace = profile.begin(.renderer_clear);
        defer profile.end(trace);
        const cc = readClearCommand(self.prepared_commands.headers[0], self.prepared_commands.data);
        @memset(self.back_buffer.pixels(), cc.color);
        return;
    }

    const rows = @divFloor((self.back_buffer.height + render_tile_size - 1), render_tile_size);
    const cols = @divFloor((self.back_buffer.width + render_tile_size - 1), render_tile_size);
    const bins = self.prepared_commands.bin(cols, rows, arena) catch @panic("Frame allocator exhausted while binning commands");

    for (0..rows) |row| {
        for (0..cols) |col| {
            const tile = row * cols + col;
            const commands = bins.headers[bins.offsets[tile]..bins.offsets[tile + 1]];
            renderTile(self.back_buffer, .{ .x = col, .y = row }, commands, self.prepared_commands.data);
        }
    }
}

pub fn getTexture(self: *const Self, texture: Renderer.Texture) Bitmap {
    const index: u32 = @backingInt(texture);
    if (index >= self.head) return self.textures[0];
    return self.textures[index];
}

pub fn getTextureOrNull(self: *const Self, texture: Renderer.Texture) ?Bitmap {
    const index: u32 = @backingInt(texture);
    if (index >= self.head) return null;
    return self.textures[index];
}

pub fn allocTexture(
    self: *Self,
    gpa: std.mem.Allocator,
    width: u16,
    height: u16,
) error{ TextureFull, OutOfMemory }!Renderer.Texture {
    if (self.head >= self.textures.len) {
        std.log.err("Texture slots full", .{});
        return error.TextureFull;
    }
    const t: *Bitmap = &self.textures[self.head];
    t.pixels = try gpa.alloc(u32, @as(u64, width) * height);
    defer self.head += 1;
    t.width = width;
    t.height = height;
    return @fromBackingInt(self.head);
}

pub fn createTextureCopy(self: *Self, gpa: std.mem.Allocator, texture: Bitmap) Renderer.Texture {
    if (self.head >= self.textures.len) {
        std.log.err("Texture slots full", .{});
        return .missing_texture;
    }
    const t: *Bitmap = &self.textures[self.head];
    assert(@as(u64, texture.width) * texture.height <= texture.pixels.len);
    t.pixels = gpa.dupe(u32, texture.pixels) catch {
        std.log.err("Failed to allocate memory for texture", .{});
        return .missing_texture;
    };
    defer self.head += 1;
    t.width = texture.width;
    t.height = texture.height;
    return @fromBackingInt(self.head);
}

pub fn loadAndCreateTexture(
    self: *Self,
    io: std.Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    file_path: []const u8,
) Renderer.Texture {
    if (self.head >= self.textures.len) {
        std.log.err("Texture slots full", .{});
        return .missing_texture;
    }

    const texture: *Bitmap = &self.textures[self.head];
    texture.* = loadTexture(io, gpa, arena, file_path) orelse return .missing_texture;
    defer self.head += 1;
    return @fromBackingInt(@intCast(self.head));
}

pub fn loadTexture(
    io: std.Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    file_path: []const u8,
) ?Bitmap {
    const file = std.Io.Dir.cwd().openFile(io, file_path, .{}) catch {
        std.log.err("Failed to open texture: {s}", .{file_path});
        return null;
    };
    defer file.close(io);
    var diagnostic: ?[]const u8 = null;
    const image = png.fromFile(
        file,
        io,
        arena,
        gpa,
        &diagnostic,
        .{ .flip_vertical_on_load = false, .requested_channels = 4 },
    ) catch {
        if (diagnostic) |d| {
            std.log.err("Failed to load texture png: {s}", .{d});
        }
        return null;
    };
    return Bitmap.prepareFromPNG(image);
}

fn packClear(r: f32, g: f32, b: f32) u32 {
    const red: u8 = @truncate(@as(u32, @intFromFloat(@round(r * 255.0))));
    const green: u8 = @truncate(@as(u32, @intFromFloat(@round(g * 255.0))));
    const blue: u8 = @truncate(@as(u32, @intFromFloat(@round(b * 255.0))));
    return (@as(u32, red) << 16) | (@as(u32, green) << 8) | blue;
}

fn readClearCommand(header: PreparedCommandBuffer.Header, command_data: []align(PreparedCommandBuffer.data_alignment) const u8) *const Internal.ClearCommand {
    assert(header.tag == .clear_screen);
    const size = @sizeOf(Internal.ClearCommand);
    assert(command_data.len >= header.offset);
    assert(command_data.len - header.offset >= size);
    return @ptrCast(@alignCast(command_data[header.offset..][0..size]));
}

fn clipped(width: u16, height: u16, left: f32, top: f32, right: f32, bottom: f32) ?AABB {
    @setFloatMode(.optimized);
    // Keep offscreen coordinates in floating point until the intersection
    // bounds them to the framebuffer; finite inputs can be larger than i64.
    const bounds: AABB = .{
        .min_x = @max(left, 0),
        .min_y = @max(top, 0),
        .max_x = @min(right, @as(f32, @floatFromInt(width))),
        .max_y = @min(bottom, @as(f32, @floatFromInt(height))),
    };
    if (bounds.max_x <= bounds.min_x or bounds.max_y <= bounds.min_y) return null;
    return bounds;
}

/// Unrotated sprite geometry needs no stored basis or bounds-rounding mode.
const PreparedSprite = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    bounds: AABB,

    fn fromRectangle(rectangle: PreparedRectangle) PreparedSprite {
        assert(rectangle.right_x == 1 and rectangle.right_y == 0);
        return .{
            .x = rectangle.x,
            .y = rectangle.y,
            .width = rectangle.width,
            .height = rectangle.height,
            .bounds = rectangle.bounds,
        };
    }

    fn forTile(self: PreparedSprite, tile_x: f32, tile_y: f32) ?PreparedSprite {
        var sprite = self;
        sprite.x -= tile_x;
        sprite.y -= tile_y;
        sprite.bounds = clipped(
            render_tile_size,
            render_tile_size,
            self.bounds.min_x - tile_x,
            self.bounds.min_y - tile_y,
            self.bounds.max_x - tile_x,
            self.bounds.max_y - tile_y,
        ) orelse return null;
        return sprite;
    }
};

/// Rectangle geometry in framebuffer pixels, clipped to the preparation target.
const PreparedRectangle = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    right_x: f32,
    right_y: f32,

    bounds: AABB,
    bounds_rounding: BoundsRounding,

    const BoundsRounding = enum { pixel_centres, outward };
    const Coverage = enum { outside, full, partial };
    const LocalPosition = struct { x: f32, y: f32 };

    /// Convert transformed geometry into clipped pixel bounds. The camera's
    /// translation/scale (and, for a rotated view, basis rotation) happens first.
    fn init(buffer: FrameBuffer, geometry: Renderer.RectangleGeometry, rounding: BoundsRounding) ?PreparedRectangle {
        // World geometry was validated when recorded. Only conversion overflow
        // needs checking here, before clipping or converting bounds to integers.
        // Match construction's rounding headroom for the scaled corner arithmetic.
        const coordinate_bound = @abs(geometry.origin_x) + @abs(geometry.origin_y) +
            @abs(geometry.width) + @abs(geometry.height);
        if (!std.math.isFinite(coordinate_bound * 2.0)) @panic("Rectangle exceeds screen coordinate range");
        if (geometry.width <= 0 or geometry.height <= 0) return null;
        assert(rounding != .pixel_centres or (geometry.right_x == 1 and geometry.right_y == 0));
        const raw = geometry.bounds();
        // At zero rotation, solve x <= i + 0.5 < x + width once at the bounds.
        // Otherwise include candidate pixels and reject uncovered centres below.
        const left = if (rounding == .pixel_centres) @ceil(raw.min_x - 0.5) else @floor(raw.min_x);
        const top = if (rounding == .pixel_centres) @ceil(raw.min_y - 0.5) else @floor(raw.min_y);
        const right = if (rounding == .pixel_centres) @ceil(raw.max_x - 0.5) else @ceil(raw.max_x);
        const bottom = if (rounding == .pixel_centres) @ceil(raw.max_y - 0.5) else @ceil(raw.max_y);
        return .{
            .x = geometry.origin_x,
            .y = geometry.origin_y,
            .width = geometry.width,
            .height = geometry.height,
            .right_x = geometry.right_x,
            .right_y = geometry.right_y,
            .bounds = clipped(buffer.width, buffer.height, left, top, right, bottom) orelse return null,
            .bounds_rounding = rounding,
        };
    }

    fn forTile(self: PreparedRectangle, tile_x: f32, tile_y: f32) ?PreparedRectangle {
        var rectangle = self;
        rectangle.x -= tile_x;
        rectangle.y -= tile_y;
        // Clip only the raster bounds; preserve geometry size and orientation for sampling.
        rectangle.bounds = clipped(
            render_tile_size,
            render_tile_size,
            self.bounds.min_x - tile_x,
            self.bounds.min_y - tile_y,
            self.bounds.max_x - tile_x,
            self.bounds.max_y - tile_y,
        ) orelse return null;
        return rectangle;
    }

    fn localPosition(self: PreparedRectangle, pixel_x: f32, pixel_y: f32) LocalPosition {
        @setFloatMode(.optimized);
        const translated_x = pixel_x - self.x;
        const translated_y = pixel_y - self.y;
        return .{
            .x = translated_x * self.right_x + translated_y * self.right_y,
            .y = translated_x * -self.right_y + translated_y * self.right_x,
        };
    }

    /// Classify the clipped raster region's sample centres, not its pixel edges.
    /// A separating rectangle-local axis proves rejection; four outside corners
    /// alone do not, since the region can contain or cross the rectangle.
    fn classifyCoverage(self: PreparedRectangle) Coverage {
        assert(self.bounds.min_x < self.bounds.max_x);
        assert(self.bounds.min_y < self.bounds.max_y);
        const left = self.bounds.min_x + 0.5;
        const top = self.bounds.min_y + 0.5;
        const right = self.bounds.max_x - 0.5;
        const bottom = self.bounds.max_y - 0.5;
        const a = self.localPosition(left, top);
        const b = self.localPosition(right, top);
        const c = self.localPosition(left, bottom);
        const d = self.localPosition(right, bottom);
        const min_x = @min(a.x, b.x, c.x, d.x);
        const min_y = @min(a.y, b.y, c.y, d.y);
        const max_x = @max(a.x, b.x, c.x, d.x);
        const max_y = @max(a.y, b.y, c.y, d.y);

        if (max_x < 0 or min_x >= self.width) return .outside;
        if (max_y < 0 or min_y >= self.height) return .outside;
        // Keep samples exactly on an edge on the per-pixel coverage path.
        if (min_x > 0 and max_x < self.width and min_y > 0 and max_y < self.height) return .full;
        return .partial;
    }

    fn coveredPosition(self: PreparedRectangle, pixel_x: f32, pixel_y: f32) ?LocalPosition {
        const local = self.localPosition(pixel_x, pixel_y);

        // Test half-open geometry before scaling to texels. For a 31-pixel
        // texture drawn 7 pixels wide, f32 can round 7 * (31 / 7) below 31
        // and incorrectly admit the ending edge if coverage is tested afterward.
        if (local.x < 0 or local.x >= self.width) return null;
        if (local.y < 0 or local.y >= self.height) return null;
        return local;
    }
};

fn fillSolidRows(pixels: *align(tile_alignment) Tile, bounds: AABB, packed_color: u32) void {
    const x_min: usize = @intFromFloat(bounds.min_x);
    const y_min: usize = @intFromFloat(bounds.min_y);
    const x_max: usize = @intFromFloat(bounds.max_x);
    const y_max: usize = @intFromFloat(bounds.max_y);
    for (y_min..y_max) |y| {
        const offset = y * render_tile_size;
        @memset(pixels[offset + x_min .. offset + x_max], packed_color);
    }
}

// TODO(adi): Maybe have nearest-neighbour sampling and bilinear sampling as options?
/// Rasterize prepared geometry with bilinear filtering and optional tint.
fn drawTexturedRectangle(
    pixels: *align(tile_alignment) Tile,
    rectangle: PreparedRectangle,
    texture: Bitmap,
    texels_per_pixel_x: f32,
    texels_per_pixel_y: f32,
    tint: LinearColor,
) void {
    @setFloatMode(.optimized);
    const trace = profile.begin(.renderer_draw_textured_rectangle);
    defer profile.end(trace);
    assert(rectangle.width > 0);
    assert(rectangle.height > 0);
    if (texture.width == 0 or texture.height == 0) return;

    switch (rectangle.classifyCoverage()) {
        .outside => return,
        .full => drawTexturedRectanglePixels(true, pixels, rectangle, texture, texels_per_pixel_x, texels_per_pixel_y, tint),
        .partial => drawTexturedRectanglePixels(false, pixels, rectangle, texture, texels_per_pixel_x, texels_per_pixel_y, tint),
    }
}

fn drawTexturedRectanglePixels(
    comptime fully_covered: bool,
    pixels: *align(tile_alignment) Tile,
    rectangle: PreparedRectangle,
    texture: Bitmap,
    texels_per_pixel_x: f32,
    texels_per_pixel_y: f32,
    tint: LinearColor,
) void {
    @setFloatMode(.optimized);

    const bounds = rectangle.bounds;
    const x_min: usize = @intFromFloat(bounds.min_x);
    const y_min: usize = @intFromFloat(bounds.min_y);
    const x_max: usize = @intFromFloat(bounds.max_x);
    const y_max: usize = @intFromFloat(bounds.max_y);

    const texture_width: f32 = @floatFromInt(texture.width);
    const texture_height: f32 = @floatFromInt(texture.height);

    for (y_min..y_max) |j| {
        const pixel_y = @as(f32, @floatFromInt(j)) + 0.5;
        for (x_min..x_max) |i| {
            const pixel_x = @as(f32, @floatFromInt(i)) + 0.5;
            const local = if (fully_covered)
                rectangle.localPosition(pixel_x, pixel_y)
            else
                rectangle.coveredPosition(pixel_x, pixel_y) orelse continue;

            // Scale directly to texels: for a native-size 127-pixel texture,
            // (87.5 / 127) * 127 can drift whereas 87.5 * (127 / 127) does not.
            // Subtract 0.5 so integer coordinates address texel centres.
            const texel_x = local.x * texels_per_pixel_x - 0.5;
            const texel_y = local.y * texels_per_pixel_y - 0.5;

            const raw_x0: f32 = @floor(texel_x);
            const raw_y0: f32 = @floor(texel_y);
            const raw_x1 = raw_x0 + 1;
            const raw_y1 = raw_y0 + 1;

            // Distance to center of pixel being sampled. texel_* is the pixel centre in texture space.
            const dx: f32 = texel_x - raw_x0;
            const dy: f32 = texel_y - raw_y0;

            const x0: usize = @intFromFloat(std.math.clamp(raw_x0, 0.0, texture_width - 1));
            const y0: usize = @intFromFloat(std.math.clamp(raw_y0, 0.0, texture_height - 1));
            const x1: usize = @intFromFloat(std.math.clamp(raw_x1, 0.0, texture_width - 1));
            const y1: usize = @intFromFloat(std.math.clamp(raw_y1, 0.0, texture_height - 1));

            // Convention: • denotes the pixel being sampled.
            // A ───── B
            // │       │
            // │   •   │
            // │       │
            // C ───── D
            const pixel_a: [4]u8 = @bitCast(texture.pixels[y0 * texture.width + x0]);
            const pixel_b: [4]u8 = @bitCast(texture.pixels[y0 * texture.width + x1]);
            const pixel_c: [4]u8 = @bitCast(texture.pixels[y1 * texture.width + x0]);
            const pixel_d: [4]u8 = @bitCast(texture.pixels[y1 * texture.width + x1]);

            var pixel_a_b: f32 = @floatFromInt(pixel_a[0]);
            var pixel_a_g: f32 = @floatFromInt(pixel_a[1]);
            var pixel_a_r: f32 = @floatFromInt(pixel_a[2]);
            const pixel_a_a: f32 = @as(f32, @floatFromInt(pixel_a[3])) * (1.0 / 255.0);

            var pixel_b_b: f32 = @floatFromInt(pixel_b[0]);
            var pixel_b_g: f32 = @floatFromInt(pixel_b[1]);
            var pixel_b_r: f32 = @floatFromInt(pixel_b[2]);
            const pixel_b_a: f32 = @as(f32, @floatFromInt(pixel_b[3])) * (1.0 / 255.0);

            var pixel_c_b: f32 = @floatFromInt(pixel_c[0]);
            var pixel_c_g: f32 = @floatFromInt(pixel_c[1]);
            var pixel_c_r: f32 = @floatFromInt(pixel_c[2]);
            const pixel_c_a: f32 = @as(f32, @floatFromInt(pixel_c[3])) * (1.0 / 255.0);

            var pixel_d_b: f32 = @floatFromInt(pixel_d[0]);
            var pixel_d_g: f32 = @floatFromInt(pixel_d[1]);
            var pixel_d_r: f32 = @floatFromInt(pixel_d[2]);
            const pixel_d_a: f32 = @as(f32, @floatFromInt(pixel_d[3])) * (1.0 / 255.0);

            // Gamma-2 decode in byte-squared units; the RGB /255 and final *255
            // cancel. Bitmap RGB was premultiplied before encoding.
            pixel_a_b = pixel_a_b * pixel_a_b;
            pixel_a_g = pixel_a_g * pixel_a_g;
            pixel_a_r = pixel_a_r * pixel_a_r;

            pixel_b_b = pixel_b_b * pixel_b_b;
            pixel_b_g = pixel_b_g * pixel_b_g;
            pixel_b_r = pixel_b_r * pixel_b_r;

            pixel_c_b = pixel_c_b * pixel_c_b;
            pixel_c_g = pixel_c_g * pixel_c_g;
            pixel_c_r = pixel_c_r * pixel_c_r;

            pixel_d_b = pixel_d_b * pixel_d_b;
            pixel_d_g = pixel_d_g * pixel_d_g;
            pixel_d_r = pixel_d_r * pixel_d_r;

            const top_r = std.math.lerp(pixel_a_r, pixel_b_r, dx);
            const top_g = std.math.lerp(pixel_a_g, pixel_b_g, dx);
            const top_b = std.math.lerp(pixel_a_b, pixel_b_b, dx);
            const top_a = std.math.lerp(pixel_a_a, pixel_b_a, dx);

            const bottom_r = std.math.lerp(pixel_c_r, pixel_d_r, dx);
            const bottom_g = std.math.lerp(pixel_c_g, pixel_d_g, dx);
            const bottom_b = std.math.lerp(pixel_c_b, pixel_d_b, dx);
            const bottom_a = std.math.lerp(pixel_c_a, pixel_d_a, dx);

            const source_r = std.math.lerp(top_r, bottom_r, dy) * tint.r;
            const source_g = std.math.lerp(top_g, bottom_g, dy) * tint.g;
            const source_b = std.math.lerp(top_b, bottom_b, dy) * tint.b;
            const source_a = std.math.lerp(top_a, bottom_a, dy) * tint.a;

            if (source_a == 0) continue;
            const index = j * render_tile_size + i;
            const destination_u8: [4]u8 = @bitCast(pixels[index]);

            var destination_b: f32 = @floatFromInt(destination_u8[0]);
            var destination_g: f32 = @floatFromInt(destination_u8[1]);
            var destination_r: f32 = @floatFromInt(destination_u8[2]);

            destination_r = destination_r * destination_r;
            destination_g = destination_g * destination_g;
            destination_b = destination_b * destination_b;

            var blended_r = source_r + destination_r * (1.0 - source_a);
            var blended_g = source_g + destination_g * (1.0 - source_a);
            var blended_b = source_b + destination_b * (1.0 - source_a);

            blended_r = @sqrt(blended_r);
            blended_g = @sqrt(blended_g);
            blended_b = @sqrt(blended_b);

            const final = [_]u8{
                @truncate(@as(u32, @intFromFloat(@round(blended_b)))),
                @truncate(@as(u32, @intFromFloat(@round(blended_g)))),
                @truncate(@as(u32, @intFromFloat(@round(blended_r)))),
                255,
            };

            pixels[index] = @bitCast(final);
        }
    }
}

/// Rasterize an untinted texture using prepared, unrotated geometry.
/// Retains bilinear filtering, premultiplied alpha and gamma-2 conversion.
fn drawSprite(
    pixels: *align(tile_alignment) Tile,
    rectangle: PreparedSprite,
    texture: Bitmap,
    texels_per_pixel_x: f32,
    texels_per_pixel_y: f32,
) void {
    @setFloatMode(.optimized);
    const trace = profile.begin(.renderer_draw_sprite);
    defer profile.end(trace);
    assert(rectangle.width > 0);
    assert(rectangle.height > 0);
    if (texture.width == 0) return;
    if (texture.height == 0) return;
    const bounds = rectangle.bounds;
    const x_min: usize = @intFromFloat(bounds.min_x);
    const y_min: usize = @intFromFloat(bounds.min_y);
    const x_max: usize = @intFromFloat(bounds.max_x);
    const y_max: usize = @intFromFloat(bounds.max_y);
    const texture_width: f32 = @floatFromInt(texture.width);
    const texture_height: f32 = @floatFromInt(texture.height);

    // At most one tile's columns; no chunking or frame allocation.
    var cached_x0: [render_tile_size]usize = undefined;
    var cached_x1: [render_tile_size]usize = undefined;
    var cached_dx: [render_tile_size]f32 = undefined;
    var covered_x: [render_tile_size]bool = undefined;
    const column_count = x_max - x_min;
    assert(column_count <= render_tile_size);

    for (0..column_count) |column| {
        const pixel_x = @as(f32, @floatFromInt(x_min + column)) + 0.5;
        const local_x = pixel_x - rectangle.x;

        covered_x[column] = false;
        if (local_x < 0) continue;
        if (local_x >= rectangle.width) continue;
        covered_x[column] = true;

        const texel_x = local_x * texels_per_pixel_x - 0.5;
        const raw_x0 = @floor(texel_x);
        const raw_x1 = raw_x0 + 1;
        cached_x0[column] = @intFromFloat(std.math.clamp(raw_x0, 0.0, texture_width - 1));
        cached_x1[column] = @intFromFloat(std.math.clamp(raw_x1, 0.0, texture_width - 1));
        cached_dx[column] = texel_x - raw_x0;
    }

    for (y_min..y_max) |j| {
        const pixel_y = @as(f32, @floatFromInt(j)) + 0.5;
        const local_y = pixel_y - rectangle.y;
        if (local_y < 0) continue;
        if (local_y >= rectangle.height) continue;

        const texel_y = local_y * texels_per_pixel_y - 0.5;
        const raw_y0 = @floor(texel_y);
        const raw_y1 = raw_y0 + 1;
        const y0: usize = @intFromFloat(std.math.clamp(raw_y0, 0.0, texture_height - 1));
        const y1: usize = @intFromFloat(std.math.clamp(raw_y1, 0.0, texture_height - 1));
        const dy = texel_y - raw_y0;
        const row0 = y0 * texture.width;
        const row1 = y1 * texture.width;
        const destination_row = j * render_tile_size + x_min;

        for (0..column_count) |column| {
            if (!covered_x[column]) continue;
            const x0 = cached_x0[column];
            const x1 = cached_x1[column];
            const dx = cached_dx[column];
            const index = destination_row + column;
            const texel_a = texture.pixels[row0 + x0];
            const texel_b = texture.pixels[row0 + x1];
            const texel_c = texture.pixels[row1 + x0];
            const texel_d = texture.pixels[row1 + x1];
            if ((texel_a | texel_b | texel_c | texel_d) >> 24 == 0) continue;
            // Uniform opaque regions need neither filtering nor blending.
            if (texel_a >> 24 == 255) {
                if (texel_a == texel_b and texel_a == texel_c and texel_a == texel_d) {
                    pixels[index] = texel_a;
                    continue;
                }
            }

            const pixel_a: [4]u8 = @bitCast(texel_a);
            const pixel_b: [4]u8 = @bitCast(texel_b);
            const pixel_c: [4]u8 = @bitCast(texel_c);
            const pixel_d: [4]u8 = @bitCast(texel_d);

            var pixel_a_b: f32 = @floatFromInt(pixel_a[0]);
            var pixel_a_g: f32 = @floatFromInt(pixel_a[1]);
            var pixel_a_r: f32 = @floatFromInt(pixel_a[2]);
            const pixel_a_a: f32 = @as(f32, @floatFromInt(pixel_a[3])) * (1.0 / 255.0);

            var pixel_b_b: f32 = @floatFromInt(pixel_b[0]);
            var pixel_b_g: f32 = @floatFromInt(pixel_b[1]);
            var pixel_b_r: f32 = @floatFromInt(pixel_b[2]);
            const pixel_b_a: f32 = @as(f32, @floatFromInt(pixel_b[3])) * (1.0 / 255.0);

            var pixel_c_b: f32 = @floatFromInt(pixel_c[0]);
            var pixel_c_g: f32 = @floatFromInt(pixel_c[1]);
            var pixel_c_r: f32 = @floatFromInt(pixel_c[2]);
            const pixel_c_a: f32 = @as(f32, @floatFromInt(pixel_c[3])) * (1.0 / 255.0);

            var pixel_d_b: f32 = @floatFromInt(pixel_d[0]);
            var pixel_d_g: f32 = @floatFromInt(pixel_d[1]);
            var pixel_d_r: f32 = @floatFromInt(pixel_d[2]);
            const pixel_d_a: f32 = @as(f32, @floatFromInt(pixel_d[3])) * (1.0 / 255.0);

            // Gamma-2 decode in byte-squared units; the RGB /255 and final *255
            // cancel. Bitmap RGB was premultiplied before encoding.
            pixel_a_b = pixel_a_b * pixel_a_b;
            pixel_a_g = pixel_a_g * pixel_a_g;
            pixel_a_r = pixel_a_r * pixel_a_r;

            pixel_b_b = pixel_b_b * pixel_b_b;
            pixel_b_g = pixel_b_g * pixel_b_g;
            pixel_b_r = pixel_b_r * pixel_b_r;

            pixel_c_b = pixel_c_b * pixel_c_b;
            pixel_c_g = pixel_c_g * pixel_c_g;
            pixel_c_r = pixel_c_r * pixel_c_r;

            pixel_d_b = pixel_d_b * pixel_d_b;
            pixel_d_g = pixel_d_g * pixel_d_g;
            pixel_d_r = pixel_d_r * pixel_d_r;

            const top_r = std.math.lerp(pixel_a_r, pixel_b_r, dx);
            const top_g = std.math.lerp(pixel_a_g, pixel_b_g, dx);
            const top_b = std.math.lerp(pixel_a_b, pixel_b_b, dx);
            const top_a = std.math.lerp(pixel_a_a, pixel_b_a, dx);

            const bottom_r = std.math.lerp(pixel_c_r, pixel_d_r, dx);
            const bottom_g = std.math.lerp(pixel_c_g, pixel_d_g, dx);
            const bottom_b = std.math.lerp(pixel_c_b, pixel_d_b, dx);
            const bottom_a = std.math.lerp(pixel_c_a, pixel_d_a, dx);

            const source_r = std.math.lerp(top_r, bottom_r, dy);
            const source_g = std.math.lerp(top_g, bottom_g, dy);
            const source_b = std.math.lerp(top_b, bottom_b, dy);
            const source_a = std.math.lerp(top_a, bottom_a, dy);

            if (source_a == 0) continue;
            var blended_r = source_r;
            var blended_g = source_g;
            var blended_b = source_b;
            if (source_a != 1) {
                const destination_u8: [4]u8 = @bitCast(pixels[index]);
                var destination_b: f32 = @floatFromInt(destination_u8[0]);
                var destination_g: f32 = @floatFromInt(destination_u8[1]);
                var destination_r: f32 = @floatFromInt(destination_u8[2]);

                destination_r = destination_r * destination_r;
                destination_g = destination_g * destination_g;
                destination_b = destination_b * destination_b;

                blended_r += destination_r * (1.0 - source_a);
                blended_g += destination_g * (1.0 - source_a);
                blended_b += destination_b * (1.0 - source_a);
            }

            blended_r = @sqrt(blended_r);
            blended_g = @sqrt(blended_g);
            blended_b = @sqrt(blended_b);

            const final = [_]u8{
                @truncate(@as(u32, @intFromFloat(@round(blended_b)))),
                @truncate(@as(u32, @intFromFloat(@round(blended_g)))),
                @truncate(@as(u32, @intFromFloat(@round(blended_r)))),
                255,
            };

            pixels[index] = @bitCast(final);
        }
    }
}

/// Rasterize a solid color using prepared geometry and coverage bounds.
fn drawRectangle(
    pixels: *align(tile_alignment) Tile,
    rectangle: PreparedRectangle,
    color: PreparedSolidColor,
) void {
    @setFloatMode(.optimized);
    const trace = profile.begin(.renderer_draw_rectangle);
    defer profile.end(trace);
    assert(rectangle.width > 0);
    assert(rectangle.height > 0);

    const coverage = if (rectangle.bounds_rounding == .pixel_centres) .full else rectangle.classifyCoverage();
    switch (coverage) {
        .outside => return,
        .full => if (color.linear.a == 1)
            fillSolidRows(pixels, rectangle.bounds, color.opaque_pixel)
        else
            drawRectangleWide(true, false, pixels, rectangle, color),
        .partial => if (color.linear.a == 1)
            drawRectangleWide(false, true, pixels, rectangle, color)
        else
            drawRectangleWide(false, false, pixels, rectangle, color),
    }
}

const rectangle_lanes = 16;
const LaneF32 = @Vector(rectangle_lanes, f32);
const LaneU32 = @Vector(rectangle_lanes, u32);
const LaneShift = @Vector(rectangle_lanes, u5);
const LaneMask = @Vector(rectangle_lanes, bool);
const lane_index = std.simd.iota(u32, rectangle_lanes);
const lane_centers: LaneF32 = @as(LaneF32, @floatFromInt(lane_index)) + @as(LaneF32, @splat(0.5));

comptime {
    // A chunk slid back to the end of a row still fits inside that row.
    assert(render_tile_size >= rectangle_lanes);
}

// NOTE(adi): Things I did in case i forget:
// 1. the comptime paths were tested to be faster in general because it allows LLVM to do better register management
//     based on reading some of the disassembly. IDK why llvm does that, it is above my pay grade.
// 2. we start with x_min and take lane strides steps untill we get to the last stride which probably is less than lanes
//    and we just slide back till we have lane count and we just mask out the parts that have already been drawn.
fn drawRectangleWide(
    comptime fully_covered: bool,
    comptime opaque_source: bool,
    pixels: *align(tile_alignment) Tile,
    rectangle: PreparedRectangle,
    color: PreparedSolidColor,
) void {
    @setFloatMode(.optimized);
    comptime assert(!(fully_covered and opaque_source));

    const bounds = rectangle.bounds;
    const x_min: usize = @intFromFloat(bounds.min_x);
    const y_min: usize = @intFromFloat(bounds.min_y);
    const x_max: usize = @intFromFloat(bounds.max_x);
    const y_max: usize = @intFromFloat(bounds.max_y);
    assert(x_min < x_max and x_max <= render_tile_size);
    assert(y_min < y_max and y_max <= render_tile_size);

    // Scale the premultiplied source once; destination RGB stays in byte units.
    const source_r: LaneF32 = @splat(color.linear.r * (255.0 * 255.0));
    const source_g: LaneF32 = @splat(color.linear.g * (255.0 * 255.0));
    const source_b: LaneF32 = @splat(color.linear.b * (255.0 * 255.0));

    const x_high: LaneU32 = @splat(@intCast(x_max));
    const zero: LaneF32 = @splat(0);
    const origin_x: LaneF32 = @splat(rectangle.x);
    const width: LaneF32 = @splat(rectangle.width);
    const height: LaneF32 = @splat(rectangle.height);
    const right_x: LaneF32 = @splat(rectangle.right_x);
    const right_y: LaneF32 = @splat(rectangle.right_y);

    const negative_right_y: LaneF32 = @splat(-rectangle.right_y);
    const inverse_alpha: LaneF32 = @splat(1.0 - color.linear.a);
    const opaque_pixel: LaneU32 = @splat(color.opaque_pixel);
    const alpha_bits: LaneU32 = @splat(0xff00_0000);
    const channel: LaneU32 = @splat(0xff);
    const shift_g: LaneShift = @splat(8);
    const shift_r: LaneShift = @splat(16);

    for (y_min..y_max) |y| {
        const row: *align(@alignOf(u32)) [render_tile_size]u32 = pixels[y * render_tile_size ..][0..render_tile_size];
        const pixel_y = @as(f32, @floatFromInt(y)) + 0.5;
        const translated_y: LaneF32 = @splat(pixel_y - rectangle.y);

        var x = x_min;
        const row_local_x = translated_y * right_y;
        const row_local_y = translated_y * right_x;
        while (x + rectangle_lanes <= x_max) : (x += rectangle_lanes) {
            var mask: LaneMask = @splat(true);
            if (!fully_covered) {
                const pixel_x = @as(LaneF32, @splat(@as(f32, @floatFromInt(x)))) + lane_centers;
                const translated_x = pixel_x - origin_x;
                const local_x = translated_x * right_x + row_local_x;
                const local_y = translated_x * negative_right_y + row_local_y;
                const outside = (local_x < zero) | (local_x >= width) |
                    (local_y < zero) | (local_y >= height);
                mask = ~outside;
                if (!@reduce(.Or, mask)) continue;
            }

            const destination: LaneU32 = row[x..][0..rectangle_lanes].*;
            var result = opaque_pixel;
            if (!opaque_source) {
                var destination_b: LaneF32 = @floatFromInt(destination & channel);
                var destination_g: LaneF32 = @floatFromInt((destination >> shift_g) & channel);
                var destination_r: LaneF32 = @floatFromInt((destination >> shift_r) & channel);

                destination_r = destination_r * destination_r;
                destination_g = destination_g * destination_g;
                destination_b = destination_b * destination_b;

                const blended_r = @sqrt(source_r + destination_r * inverse_alpha);
                const blended_g = @sqrt(source_g + destination_g * inverse_alpha);
                const blended_b = @sqrt(source_b + destination_b * inverse_alpha);

                const final_r: LaneU32 = @intFromFloat(@round(blended_r));
                const final_g: LaneU32 = @intFromFloat(@round(blended_g));
                const final_b: LaneU32 = @intFromFloat(@round(blended_b));
                result = alpha_bits | (final_r << shift_r) | (final_g << shift_g) | final_b;
            }
            row[x..][0..rectangle_lanes].* = if (fully_covered) result else @select(u32, mask, result, destination);
        }
        // At most one short chunk remains. Keep the lower bound when sliding it
        // back into the row so previously blended pixels are not blended twice.
        if (x < x_max) {
            const start = @min(x, render_tile_size - rectangle_lanes);
            const lane_x = @as(LaneU32, @splat(@intCast(start))) + lane_index;
            var mask: LaneMask = (lane_x >= @as(LaneU32, @splat(@intCast(x)))) & (lane_x < x_high);
            if (!fully_covered) {
                const pixel_x = @as(LaneF32, @splat(@as(f32, @floatFromInt(start)))) + lane_centers;
                const translated_x = pixel_x - origin_x;
                const local_x = translated_x * right_x + row_local_x;
                const local_y = translated_x * negative_right_y + row_local_y;
                const outside = (local_x < zero) | (local_x >= width) |
                    (local_y < zero) | (local_y >= height);
                mask &= ~outside;
                if (!@reduce(.Or, mask)) continue;
            }

            const destination: LaneU32 = row[start..][0..rectangle_lanes].*;
            var result = opaque_pixel;
            if (!opaque_source) {
                var destination_b: LaneF32 = @floatFromInt(destination & channel);
                var destination_g: LaneF32 = @floatFromInt((destination >> shift_g) & channel);
                var destination_r: LaneF32 = @floatFromInt((destination >> shift_r) & channel);

                destination_r = destination_r * destination_r;
                destination_g = destination_g * destination_g;
                destination_b = destination_b * destination_b;

                const blended_r = @sqrt(source_r + destination_r * inverse_alpha);
                const blended_g = @sqrt(source_g + destination_g * inverse_alpha);
                const blended_b = @sqrt(source_b + destination_b * inverse_alpha);

                const final_r: LaneU32 = @intFromFloat(@round(blended_r));
                const final_g: LaneU32 = @intFromFloat(@round(blended_g));
                const final_b: LaneU32 = @intFromFloat(@round(blended_b));
                result = alpha_bits | (final_r << shift_r) | (final_g << shift_g) | final_b;
            }
            row[start..][0..rectangle_lanes].* = @select(u32, mask, result, destination);
        }
    }
}

const SubpixelPoint = struct {
    x: i64,
    y: i64,

    const subpixel_scale: i64 = 256;
    const max_pixel_coordinate: f32 = 2_097_152;

    fn init(x: f32, y: f32) ?SubpixelPoint {
        if (@abs(x) > max_pixel_coordinate) return null;
        if (@abs(y) > max_pixel_coordinate) return null;

        // Coordinates fit +/-2^29 subpixels. Differences fit +/-2^30,
        // leaving room for both products, their difference, and edge bias in i64.
        const scale: f32 = @floatFromInt(subpixel_scale);
        return .{
            .x = @intFromFloat(@round(x * scale)),
            .y = @intFromFloat(@round(y * scale)),
        };
    }
};

fn triangleEdgeBias(dx: i64, dy: i64) i64 {
    // With Y down and positive-inside edges, upward and rightward-horizontal
    // edges own their boundary samples. Subtract one for all other edges.
    if (dy < 0) return 0;
    if (dy == 0) {
        if (dx > 0) return 0;
    }
    return -1;
}

/// Draw at pixel centers with top-left ownership on a 1/256-pixel grid.
/// Non-finite vertices or coordinates outside +/-2,097,152 pixels are ignored.
pub fn drawTriangle(
    self: *Self,
    a_x: f32,
    a_y: f32,
    b_x: f32,
    b_y: f32,
    c_x: f32,
    c_y: f32,
    color_srgb: Color,
) void {
    const back_buffer = &self.back_buffer;
    const subpixel_scale = SubpixelPoint.subpixel_scale;
    const a = SubpixelPoint.init(a_x, a_y) orelse return;
    const b = SubpixelPoint.init(b_x, b_y) orelse return;
    const c = SubpixelPoint.init(c_x, c_y) orelse return;

    const signed_double_area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);

    if (signed_double_area == 0) return;

    // Framebuffer Y increases downward, so positive area is clockwise.
    const is_clockwise = signed_double_area > 0;
    const is_front_facing = switch (self.front_face_winding_order) {
        .clockwise => is_clockwise,
        .anticlockwise => !is_clockwise,
    };
    switch (self.cull_mode) {
        .none => {},
        .front => {
            if (is_front_facing) return;
        },
        .back => {
            if (!is_front_facing) return;
        },
    }

    // Bound the snapped geometry, then clip before converting to unsigned indices.
    const left = @max(
        @divFloor(@min(a.x, b.x, c.x), subpixel_scale),
        0,
    );
    const right = @min(
        @divFloor(@max(a.x, b.x, c.x) + subpixel_scale - 1, subpixel_scale),
        @as(i64, back_buffer.width),
    );
    const top = @max(@divFloor(@min(a.y, b.y, c.y), subpixel_scale), 0);
    const bottom = @min(
        @divFloor(@max(a.y, b.y, c.y) + subpixel_scale - 1, subpixel_scale),
        @as(i64, back_buffer.height),
    );
    if (right <= left) return;
    if (bottom <= top) return;

    // Keep the inside test positive for either surviving winding.
    const edge_sign: i64 = if (is_clockwise) 1 else -1;
    const @"a->b_x" = (b.x - a.x) * edge_sign;
    const @"a->b_y" = (b.y - a.y) * edge_sign;
    const @"b->c_x" = (c.x - b.x) * edge_sign;
    const @"b->c_y" = (c.y - b.y) * edge_sign;
    const @"c->a_x" = (a.x - c.x) * edge_sign;
    const @"c->a_y" = (a.y - c.y) * edge_sign;

    const ab_bias = triangleEdgeBias(@"a->b_x", @"a->b_y");
    const bc_bias = triangleEdgeBias(@"b->c_x", @"b->c_y");
    const ca_bias = triangleEdgeBias(@"c->a_x", @"c->a_y");
    const ab_step_right = -@"a->b_y" * subpixel_scale;
    const bc_step_right = -@"b->c_y" * subpixel_scale;
    const ca_step_right = -@"c->a_y" * subpixel_scale;
    const ab_step_down = @"a->b_x" * subpixel_scale;
    const bc_step_down = @"b->c_x" * subpixel_scale;
    const ca_step_down = @"c->a_x" * subpixel_scale;

    const source_r = color_srgb.r * color_srgb.r * color_srgb.a;
    const source_g = color_srgb.g * color_srgb.g * color_srgb.a;
    const source_b = color_srgb.b * color_srgb.b * color_srgb.a;
    const source_a = color_srgb.a;

    const sample_x = left * subpixel_scale + subpixel_scale / 2;
    const sample_y = top * subpixel_scale + subpixel_scale / 2;
    var ab_check = @"a->b_x" * (sample_y - a.y) - @"a->b_y" * (sample_x - a.x) + ab_bias;
    var bc_check = @"b->c_x" * (sample_y - b.y) - @"b->c_y" * (sample_x - b.x) + bc_bias;
    var ca_check = @"c->a_x" * (sample_y - c.y) - @"c->a_y" * (sample_x - c.x) + ca_bias;

    const min_x: usize = @intCast(left);
    const min_y: usize = @intCast(top);
    const max_x: usize = @intCast(right);
    const max_y: usize = @intCast(bottom);

    const pixels = back_buffer.pixels();
    for (min_y..max_y) |row| {
        var ab_check_row = ab_check;
        var bc_check_row = bc_check;
        var ca_check_row = ca_check;
        for (min_x..max_x) |col| {
            draw_pixel: {
                if (ab_check_row < 0) break :draw_pixel;
                if (bc_check_row < 0) break :draw_pixel;
                if (ca_check_row < 0) break :draw_pixel;
                const index = row * @as(usize, back_buffer.width) + col;
                const destination_u8: [4]u8 = @bitCast(pixels[index]);

                var destination_b: f32 = @as(f32, @floatFromInt(destination_u8[0])) / 255.0;
                var destination_g: f32 = @as(f32, @floatFromInt(destination_u8[1])) / 255.0;
                var destination_r: f32 = @as(f32, @floatFromInt(destination_u8[2])) / 255.0;

                destination_r = destination_r * destination_r;
                destination_g = destination_g * destination_g;
                destination_b = destination_b * destination_b;

                var blended_r = source_r + destination_r * (1.0 - source_a);
                var blended_g = source_g + destination_g * (1.0 - source_a);
                var blended_b = source_b + destination_b * (1.0 - source_a);

                blended_r = @sqrt(blended_r);
                blended_g = @sqrt(blended_g);
                blended_b = @sqrt(blended_b);

                const final = [_]u8{
                    @truncate(@as(u32, @intFromFloat(@round(blended_b * 255.0)))),
                    @truncate(@as(u32, @intFromFloat(@round(blended_g * 255.0)))),
                    @truncate(@as(u32, @intFromFloat(@round(blended_r * 255.0)))),
                    255,
                };

                pixels[index] = @bitCast(final);
            }
            ab_check_row += ab_step_right;
            bc_check_row += bc_step_right;
            ca_check_row += ca_step_right;
        }
        ab_check += ab_step_down;
        bc_check += bc_step_down;
        ca_check += ca_step_down;
    }
}

test "clear-only frames require no frame allocation" {
    var renderer: Self = undefined;
    try renderer.init(std.testing.allocator, .{ .width = 65, .height = 67, .missing_texture_color = .magenta });
    defer renderer.deinit(std.testing.allocator);
    var storage: [0]u8 = .{};
    var frame_allocator = std.heap.FixedBufferAllocator.init(&storage);
    _ = renderer.beginDrawing(.{ .r = 0.1, .g = 0.4, .b = 0.8, .a = 1 }, .{ .meters_per_pixel = 1, .camera_x = 0, .camera_y = 0 });
    renderer.endDrawing(frame_allocator.allocator(), &renderer.command_buffer);
    for (renderer.back_buffer.pixels()) |pixel| try std.testing.expectEqual(@as(u32, 0x001a66cc), pixel);
}

test "clear-only tile jobs preserve other tiles and clip the bottom right edge" {
    var renderer: Self = undefined;
    try renderer.init(std.testing.allocator, .{ .width = 130, .height = 67, .missing_texture_color = .magenta });
    defer renderer.deinit(std.testing.allocator);
    _ = renderer.beginDrawing(.black, .{ .meters_per_pixel = 1, .camera_x = 0, .camera_y = 0 });
    renderer.command_buffer.pushClear(.{ .r = 0.1, .g = 0.4, .b = 0.8 });
    // Use a nonzero payload offset, then force the normal playback path too.
    renderer.prepareCommands(&renderer.command_buffer);
    const header = renderer.prepared_commands.headers[1];
    const headers = [_]PreparedCommandBuffer.Header{ header, header };
    for ([_]usize{ 1, 2 }) |count| {
        @memset(renderer.back_buffer.pixels(), 0x12345678);
        renderTile(renderer.back_buffer, .{ .x = 2, .y = 1 }, headers[0..count], renderer.prepared_commands.data);
        for (renderer.back_buffer.pixels(), 0..) |pixel, index| {
            const expected: u32 = if (index % 130 >= 128 and index / 130 >= 64) 0x001a66cc else 0x12345678;
            try std.testing.expectEqual(expected, pixel);
        }
    }
}

test "rectangle coverage classifies clipped pixel centres conservatively" {
    const buffer: FrameBuffer = .{ .width = 64, .height = 64, .data = undefined };
    const Case = struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
        angle: f32,
        bounds: AABB,
        expected: PreparedRectangle.Coverage,
    };
    const cases = [_]Case{
        // A rotated diamond: its AABB includes an outside corner and its interior.
        .{ .x = 32, .y = 0, .width = 45, .height = 45, .angle = std.math.pi / 4.0, .bounds = .{ .min_x = 0, .min_y = 0, .max_x = 8, .max_y = 8 }, .expected = .outside },
        .{ .x = 32, .y = 0, .width = 45, .height = 45, .angle = std.math.pi / 4.0, .bounds = .{ .min_x = 24, .min_y = 24, .max_x = 40, .max_y = 40 }, .expected = .full },
        .{ .x = 32, .y = 0, .width = 45, .height = 45, .angle = std.math.pi / 4.0, .bounds = .{ .min_x = 0, .min_y = 0, .max_x = 64, .max_y = 64 }, .expected = .partial },
        // All four corners are outside, but the region contains the entire shape.
        .{ .x = 32, .y = 24, .width = 10, .height = 10, .angle = std.math.pi / 4.0, .bounds = .{ .min_x = 0, .min_y = 0, .max_x = 64, .max_y = 64 }, .expected = .partial },
        // Sample centres on a half-open ending edge cannot enter the full path.
        .{ .x = 0, .y = 0, .width = 7.5, .height = 8, .angle = 0, .bounds = .{ .min_x = 0, .min_y = 0, .max_x = 8, .max_y = 8 }, .expected = .partial },
        .{ .x = 0, .y = 0, .width = 8, .height = 8, .angle = 0, .bounds = .{ .min_x = 0, .min_y = 0, .max_x = 8, .max_y = 8 }, .expected = .full },
        // Near-edge cancellation deliberately falls back to per-pixel coverage.
        .{ .x = -1e20, .y = -1e20, .width = 2e20, .height = 2e20, .angle = std.math.pi / 4.0, .bounds = .{ .min_x = 0, .min_y = 0, .max_x = 64, .max_y = 64 }, .expected = .partial },
    };
    for (cases) |case| {
        var rectangle = PreparedRectangle.init(buffer, Renderer.RectangleGeometry.init(case.x, case.y, case.width, case.height, 0, 0, case.angle), .outward).?;
        rectangle.bounds = case.bounds;
        try std.testing.expectEqual(case.expected, rectangle.classifyCoverage());
    }
}

test "classified rectangle kernels match per-pixel coverage across rotated tile regions" {
    var actual: Tile align(tile_alignment) = undefined;
    var expected: Tile align(tile_alignment) = undefined;
    const screen: FrameBuffer = .{ .width = 130, .height = 67, .data = undefined };
    var texels = [_]u32{ 0x00000000, 0x80b40000, 0xff00ff00, 0xffffffff, 0xff204080, 0x80404040 };
    const texture: Bitmap = .{ .width = 3, .height = 2, .pixels = &texels };
    const Case = struct { x: f32, y: f32, width: f32, height: f32, angle: f32 };
    const cases = [_]Case{
        .{ .x = 64, .y = 32, .width = 300, .height = 300, .angle = 0.4 },
        .{ .x = 64, .y = 32, .width = 70, .height = 70, .angle = std.math.pi / 4.0 },
        .{ .x = 63.5, .y = 63.5, .width = 125, .height = 0.75, .angle = -0.7 },
        .{ .x = 64.5, .y = 64.5, .width = 7, .height = 7, .angle = 0 },
        .{ .x = 64, .y = 32, .width = 65, .height = 66, .angle = std.math.pi / 2.0 },
        .{ .x = -1e20, .y = -1e20, .width = 2e20, .height = 2e20, .angle = std.math.pi / 4.0 },
    };
    var classifications: [3]usize = @splat(0);
    for (cases) |case| {
        const prepared = PreparedRectangle.init(screen, Renderer.RectangleGeometry.init(case.x, case.y, case.width, case.height, 0.5, 0.5, case.angle), .outward) orelse continue;
        const texels_per_pixel_x = @as(f32, @floatFromInt(texture.width)) / prepared.width;
        const texels_per_pixel_y = @as(f32, @floatFromInt(texture.height)) / prepared.height;
        for (0..2) |row| {
            for (0..3) |col| {
                const rectangle = prepared.forTile(@floatFromInt(col * 64), @floatFromInt(row * 64)) orelse continue;
                classifications[@backingInt(rectangle.classifyCoverage())] += 1;
                // Fixed gamma-2 blend results over 0xff183a71, independent of
                // the rasterizer; the per-pixel check remains the coverage oracle.
                for (
                    [_]Color{ .white, .{ .r = 0.8, .g = 0.3, .b = 0.1, .a = 0.5 } },
                    [_]u32{ 0xffffffff, 0xff914452 },
                ) |color, blended| {
                    @memset(&actual, 0xff183a71);
                    @memset(&expected, 0xff183a71);
                    drawRectangle(&actual, rectangle, PreparedSolidColor.init(color));
                    for (&expected, 0..) |*pixel, index| {
                        const x = @as(f32, @floatFromInt(index % render_tile_size)) + 0.5;
                        const y = @as(f32, @floatFromInt(index / render_tile_size)) + 0.5;
                        if (x < rectangle.bounds.min_x or x >= rectangle.bounds.max_x) continue;
                        if (y < rectangle.bounds.min_y or y >= rectangle.bounds.max_y) continue;
                        if (rectangle.coveredPosition(x, y) != null) pixel.* = blended;
                    }
                    try std.testing.expectEqualSlices(u32, &expected, &actual);
                }
                for ([_]?Color{ null, .{ .r = 0.7, .g = 0.3, .b = 0.9, .a = 0.5 } }) |tint| {
                    @memset(&actual, 0xff183a71);
                    @memset(&expected, 0xff183a71);
                    drawTexturedRectangle(&actual, rectangle, texture, texels_per_pixel_x, texels_per_pixel_y, LinearColor.init(tint orelse .white));
                    drawTexturedRectanglePixels(false, &expected, rectangle, texture, texels_per_pixel_x, texels_per_pixel_y, LinearColor.init(tint orelse .white));
                    try std.testing.expectEqualSlices(u32, &expected, &actual);
                }
            }
        }
    }
    for (classifications) |count| try std.testing.expect(count > 0);
}

test "solid blends preserve byte-squared rounding at full and partial row tails" {
    const screen: FrameBuffer = .{ .width = 64, .height = 64, .data = undefined };
    const background: u32 = 0xfffeeffe;
    // Before quantization, red/blue are 251.49997 and green is 238.49997.
    // Normalizing the destination by 255 pushes them across the half-byte edge.
    var color: Color = .{ .r = 8.0 / 255.0, .g = 212.0 / 255.0, .b = 8.0 / 255.0, .a = 5.0 / 255.0 };
    std.mem.doNotOptimizeAway(&color);
    const Case = struct {
        x: f32,
        width: f32,
        height: f32,
        rounding: PreparedRectangle.BoundsRounding,
        first_x: usize,
        end_x: usize,
        end_y: usize,
    };
    const cases = [_]Case{
        .{ .x = 0, .width = 64, .height = 4, .rounding = .pixel_centres, .first_x = 0, .end_x = 64, .end_y = 4 },
        .{ .x = 1, .width = 63, .height = 4, .rounding = .pixel_centres, .first_x = 1, .end_x = 64, .end_y = 4 },
        .{ .x = 1, .width = 62.5, .height = 3.5, .rounding = .outward, .first_x = 1, .end_x = 63, .end_y = 3 },
        .{ .x = 63, .width = 1, .height = 4, .rounding = .pixel_centres, .first_x = 63, .end_x = 64, .end_y = 4 },
    };
    for (cases) |case| {
        var pixels: Tile align(tile_alignment) = @splat(background);
        const rectangle = PreparedRectangle.init(screen, Renderer.RectangleGeometry.init(case.x, 0, case.width, case.height, 0, 0, 0), case.rounding).?;
        drawRectangle(&pixels, rectangle, PreparedSolidColor.init(color));
        for (pixels, 0..) |pixel, index| {
            const x = index % render_tile_size;
            const y = index / render_tile_size;
            const expected: u32 = if (x >= case.first_x and x < case.end_x and y < case.end_y) 0xfffbeefb else background;
            try std.testing.expectEqual(expected, pixel);
        }
    }
}

test "partial solid rows preserve coverage across lane widths and shifted tails" {
    const screen: FrameBuffer = .{ .width = 64, .height = 64, .data = undefined };
    const background: u32 = 0xff183a71;
    // The geometry starts on pixel centres and ends on excluded pixel centres.
    // Outward bounds include that ending edge, forcing partial coverage even
    // when the horizontal span contains complete vector chunks.
    for (0..render_tile_size) |start| {
        for ([_]usize{ 1, 15, 16, 17, 31, 32, 33, 47, 48, 49, 63, 64 }) |width| {
            const rectangle = PreparedRectangle.init(screen, Renderer.RectangleGeometry.init(
                @as(f32, @floatFromInt(start)) + 0.5,
                1.5,
                @floatFromInt(width),
                3,
                0,
                0,
                0,
            ), .outward).?;
            try std.testing.expectEqual(PreparedRectangle.Coverage.partial, rectangle.classifyCoverage());
            for (
                [_]Color{ .white, .{ .r = 0.8, .g = 0.3, .b = 0.1, .a = 0.5 } },
                [_]u32{ 0xffffffff, 0xff914452 },
            ) |color, blended| {
                var pixels: Tile align(tile_alignment) = @splat(background);
                drawRectangle(&pixels, rectangle, PreparedSolidColor.init(color));
                for (pixels, 0..) |pixel, index| {
                    const x = index % render_tile_size;
                    const y = index / render_tile_size;
                    const covered = x >= start and x < start + width and y >= 1 and y < 4;
                    try std.testing.expectEqual(if (covered) blended else background, pixel);
                }
            }
        }
    }
}

test "recorded tile ranges produce compact bins in submission order" {
    var renderer: Self = undefined;
    try renderer.init(std.testing.allocator, .{ .width = 130, .height = 67, .missing_texture_color = .magenta });
    defer renderer.deinit(std.testing.allocator);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = renderer.beginDrawing(.black, .{ .meters_per_pixel = 1, .camera_x = 65, .camera_y = 33.5 });
    const draws = [_]struct {
        pivot_world_x: f32,
        pivot_world_y: f32,
        width: f32,
        height: f32,
        texture: ?Renderer.Texture = null,
        tint_srgb: ?Color = null,
    }{
        .{ .pivot_world_x = 0, .pivot_world_y = 0, .width = 64, .height = 64 },
        .{ .pivot_world_x = 64, .pivot_world_y = 64, .width = 66, .height = 3 },
        .{ .pivot_world_x = 64, .pivot_world_y = 0, .width = 64, .height = 64, .texture = .missing_texture },
        .{ .pivot_world_x = 0, .pivot_world_y = 0, .width = 64, .height = 64, .texture = .missing_texture, .tint_srgb = .white },
        .{ .pivot_world_x = 63, .pivot_world_y = 63, .width = 2, .height = 2 },
        .{ .pivot_world_x = 130, .pivot_world_y = 0, .width = 10, .height = 10 },
    };
    for (draws) |draw| {
        renderer.command_buffer.pushRect(draw.pivot_world_x, draw.pivot_world_y, draw.width, draw.height, .{
            .pivot_fraction_x = 0,
            .pivot_fraction_y = 0,
            .texture = draw.texture,
            .tint_srgb = draw.tint_srgb,
        });
    }
    renderer.command_buffer.pushView(.{ .meters_per_pixel = 1, .camera_x = 0, .camera_y = 0 });
    renderer.prepareCommands(&renderer.command_buffer);
    const expected_bounds = [_]TileBounds{
        .{ .min_x = 0, .min_y = 0, .max_x = 3, .max_y = 2 },
        .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 },
        .{ .min_x = 1, .min_y = 1, .max_x = 3, .max_y = 2 },
        .{ .min_x = 1, .min_y = 0, .max_x = 2, .max_y = 1 },
        .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 },
        .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 2 },
    };
    try std.testing.expectEqual(expected_bounds.len, renderer.prepared_commands.headers.len);
    try std.testing.expectEqualSlices(TileBounds, &expected_bounds, renderer.prepared_commands.tile_bounds);
    const bins = try renderer.prepared_commands.bin(3, 2, arena.allocator());
    try std.testing.expectEqualSlices(usize, &.{ 0, 4, 7, 8, 10, 13, 15 }, bins.offsets);
    const expected_commands = [_]usize{ 0, 1, 4, 5, 0, 3, 5, 0, 0, 5, 0, 2, 5, 0, 2 };
    try std.testing.expectEqual(expected_commands.len, bins.headers.len);
    for (bins.headers, expected_commands) |header, command_index| {
        try std.testing.expectEqualDeep(renderer.prepared_commands.headers[command_index], header);
    }

    _ = renderer.beginDrawing(.white, .{ .meters_per_pixel = 1, .camera_x = 65, .camera_y = 33.5 });
    renderer.prepareCommands(&renderer.command_buffer);
    const next = try renderer.prepared_commands.bin(3, 2, arena.allocator());
    try std.testing.expectEqual(@as(usize, 1), renderer.prepared_commands.tile_bounds.len);
    try std.testing.expectEqual(@as(usize, 6), next.headers.len);
    for (next.headers) |header| try std.testing.expectEqualDeep(renderer.prepared_commands.headers[0], header);
}

test "dense bins retain every command at capacity and empty bins need no references" {
    var renderer: Self = undefined;
    try renderer.init(std.testing.allocator, .{ .width = 65, .height = 65, .missing_texture_color = .magenta });
    defer renderer.deinit(std.testing.allocator);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const empty = try renderer.prepared_commands.bin(2, 2, arena.allocator());
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0, 0, 0 }, empty.offsets);
    try std.testing.expectEqual(@as(usize, 0), empty.headers.len);
    _ = renderer.beginDrawing(.black, .{ .meters_per_pixel = 1, .camera_x = 0, .camera_y = 0 });
    for (1..MAX_COMMANDS) |_| renderer.command_buffer.pushClear(.{ .r = 0, .g = 0, .b = 0 });
    renderer.prepareCommands(&renderer.command_buffer);
    const bins = try renderer.prepared_commands.bin(2, 2, arena.allocator());
    try std.testing.expectEqualSlices(usize, &.{ 0, 4096, 8192, 12288, 16384 }, bins.offsets);
    for (0..4) |tile| {
        for (bins.headers[bins.offsets[tile]..bins.offsets[tile + 1]], 0..) |header, expected| {
            try std.testing.expectEqualDeep(renderer.prepared_commands.headers[expected], header);
        }
    }
}

test "tile scratch does not consume the frame allocator" {
    var renderer: Self = undefined;
    try renderer.init(std.testing.allocator, .{ .width = 65, .height = 65, .missing_texture_color = .magenta });
    defer renderer.deinit(std.testing.allocator);
    // Enough for four compact bins; deliberately too small for a 16 KiB tile.
    var storage: [512]u8 align(@alignOf(usize)) = undefined;
    var frame_allocator = std.heap.FixedBufferAllocator.init(&storage);
    _ = renderer.beginDrawing(.black, .{ .meters_per_pixel = 1, .camera_x = 0, .camera_y = 0 });
    renderer.command_buffer.pushRect(0, 0, 65, 65, .{ .tint_srgb = .white });
    renderer.endDrawing(frame_allocator.allocator(), &renderer.command_buffer);
    for (renderer.back_buffer.pixels()) |pixel| try std.testing.expectEqual(@as(u32, 0xffffffff), pixel);
}

test "tile playback uses copied headers independently of the recording array" {
    var renderer: Self = undefined;
    try renderer.init(std.testing.allocator, .{ .width = 64, .height = 64, .missing_texture_color = .magenta });
    defer renderer.deinit(std.testing.allocator);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = renderer.beginDrawing(.black, .{ .meters_per_pixel = 1, .camera_x = 0, .camera_y = 0 });
    renderer.command_buffer.pushRect(0, 0, 64, 64, .{ .tint_srgb = .white });
    renderer.prepareCommands(&renderer.command_buffer);
    const bins = try renderer.prepared_commands.bin(1, 1, arena.allocator());
    // The bin owns its header copies; payload bytes retain their frame lifetime.
    @memset(renderer.prepared_commands.headers, .{ .tag = .clear_screen, .offset = std.math.maxInt(u32) });
    renderTile(renderer.back_buffer, .{ .x = 0, .y = 0 }, bins.headers, renderer.prepared_commands.data);
    for (renderer.back_buffer.pixels()) |pixel| try std.testing.expectEqual(@as(u32, 0xffffffff), pixel);
}

test "tiled playback preserves alpha order clear barriers and partial edge tiles" {
    var renderer: Self = undefined;
    try renderer.init(std.testing.allocator, .{ .width = 130, .height = 67, .missing_texture_color = .magenta });
    defer renderer.deinit(std.testing.allocator);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = renderer.beginDrawing(.white, .{ .meters_per_pixel = 1, .camera_x = 65, .camera_y = 33.5 });
    renderer.command_buffer.pushRect(0, 0, 260, 134, .{ .tint_srgb = .magenta });
    renderer.command_buffer.pushClear(.{ .r = 0, .g = 0, .b = 0 });
    renderer.command_buffer.pushRect(63, 63, 65, 4, .{ .pivot_fraction_x = 0, .pivot_fraction_y = 0, .tint_srgb = .{ .r = 1, .g = 0, .b = 0, .a = 1 } });
    renderer.command_buffer.pushRect(64, 64, 66, 3, .{ .pivot_fraction_x = 0, .pivot_fraction_y = 0, .tint_srgb = .{ .r = 0, .g = 0, .b = 1, .a = 0.5 } });
    renderer.endDrawing(arena.allocator(), &renderer.command_buffer);
    for (renderer.back_buffer.pixels(), 0..) |pixel, index| {
        const x = index % 130;
        const y = index / 130;
        const red = x >= 63 and x < 128 and y >= 63;
        const blue = x >= 64 and y >= 64;
        const expected: u32 = if (blue) (if (red) 0xffb400b4 else 0xff0000b4) else (if (red) 0xffff0000 else 0);
        try std.testing.expectEqual(expected, pixel);
    }

    // Independent tile jobs may finish in any order, including edge tiles first.
    const bins = try renderer.prepared_commands.bin(3, 2, arena.allocator());
    @memset(renderer.back_buffer.pixels(), 0x12345678);
    var completed: [6]bool = @splat(false);
    for ([_]usize{ 5, 0, 3, 2, 1, 4 }) |tile| {
        renderTile(renderer.back_buffer, .{ .x = tile % 3, .y = tile / 3 }, bins.headers[bins.offsets[tile]..bins.offsets[tile + 1]], renderer.prepared_commands.data);
        completed[tile] = true;
        for (renderer.back_buffer.pixels(), 0..) |pixel, index| {
            const x = index % 130;
            const y = index / 130;
            const red = x >= 63 and x < 128 and y >= 63;
            const blue = x >= 64 and y >= 64;
            const rendered: u32 = if (blue) (if (red) 0xffb400b4 else 0xff0000b4) else (if (red) 0xffff0000 else 0);
            const expected: u32 = if (completed[(y / 64) * 3 + x / 64]) rendered else 0x12345678;
            try std.testing.expectEqual(expected, pixel);
        }
    }

    _ = renderer.beginDrawing(.black, .{ .meters_per_pixel = 1, .camera_x = 65, .camera_y = 33.5 });
    renderer.endDrawing(arena.allocator(), &renderer.command_buffer);
    for (renderer.back_buffer.pixels()) |pixel| try std.testing.expectEqual(@as(u32, 0), pixel);
}

test "submitted sprites preserve texel positions across partial tile boundaries" {
    var renderer: Self = undefined;
    try renderer.init(std.testing.allocator, .{ .width = 65, .height = 65, .missing_texture_color = .magenta });
    defer renderer.deinit(std.testing.allocator);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const texture = try renderer.allocTexture(std.testing.allocator, 3, 2);
    const texels = [_]u32{ 0xffff0000, 0xff00ff00, 0xff0000ff, 0xff204080, 0xff000000, 0xffffffff };
    @memcpy(renderer.getTexture(texture).pixels, &texels);
    for ([_]?Color{ null, .white }) |tint| {
        _ = renderer.beginDrawing(.black, .{ .meters_per_pixel = 1, .camera_x = 32.5, .camera_y = 32.5 });
        renderer.command_buffer.pushRect(63, 63, 3, 2, .{ .pivot_fraction_x = 0, .pivot_fraction_y = 0, .texture = texture, .tint_srgb = tint });
        renderer.endDrawing(arena.allocator(), &renderer.command_buffer);
        for (renderer.back_buffer.pixels(), 0..) |pixel, index| {
            const x = index % 65;
            const y = index / 65;
            const expected: u32 = if (x >= 63 and y >= 63) texels[(y - 63) * 3 + x - 63] else 0;
            try std.testing.expectEqual(expected, pixel);
        }
    }
}

test "native size texture preserves pixel channels and row stride" {
    var texels = [_]u32{ 0xffff0000, 0xff00ff00, 0xff0000ff, 0xff204080, 0xff000000, 0xffffffff };
    var pixels: Tile align(tile_alignment) = @splat(0);
    const buffer: FrameBuffer = .{ .width = 3, .height = 2, .data = undefined };
    const rectangle = PreparedRectangle.init(buffer, Renderer.RectangleGeometry.init(0, 0, 3, 2, 0, 0, 0), .outward).?;
    const texture: Bitmap = .{ .width = 3, .height = 2, .pixels = &texels };
    drawTexturedRectangle(&pixels, rectangle, texture, 1, 1, LinearColor.init(.white));
    for (pixels, 0..) |pixel, index| {
        const x = index % render_tile_size;
        const y = index / render_tile_size;
        const expected: u32 = if (x < 3 and y < 2) texels[y * 3 + x] else 0;
        try std.testing.expectEqual(expected, pixel);
    }
}

test "bilinear texture filtering averages linear colors and clamps edge texels" {
    var texels = [_]u32{ 0xffff0000, 0xff00ff00, 0xff0000ff, 0xffffffff };
    const texture: Bitmap = .{ .width = 2, .height = 2, .pixels = &texels };
    var pixels: Tile align(tile_alignment) = @splat(0);
    const buffer: FrameBuffer = .{ .width = 4, .height = 4, .data = undefined };
    // The centre averages all four texels: each linear RGB channel is 0.5.
    const small_rectangle = PreparedRectangle.init(buffer, Renderer.RectangleGeometry.init(0, 0, 1, 1, 0, 0, 0), .outward).?;
    drawTexturedRectangle(&pixels, small_rectangle, texture, 2, 2, LinearColor.init(.white));
    try std.testing.expectEqual(@as(u32, 0xffb4b4b4), pixels[0]);

    const large_rectangle = PreparedRectangle.init(buffer, Renderer.RectangleGeometry.init(0, 0, 4, 4, 0, 0, 0), .outward).?;
    drawTexturedRectangle(&pixels, large_rectangle, texture, 0.5, 0.5, LinearColor.init(.white));
    try std.testing.expectEqual(@as(u32, 0xffff0000), pixels[0]);
    try std.testing.expectEqual(@as(u32, 0xff00ff00), pixels[3]);
    try std.testing.expectEqual(@as(u32, 0xff0000ff), pixels[3 * render_tile_size]);
    try std.testing.expectEqual(@as(u32, 0xffffffff), pixels[3 * render_tile_size + 3]);
}

test "offscreen rectangles clip without overwriting the framebuffer boundary" {
    const Case = struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
        angle_radians: f32 = 0,
        left: usize = 0,
        top: usize = 0,
        right: usize = 0,
        bottom: usize = 0,
    };
    const cases = [_]Case{
        .{ .x = 0, .y = -3, .width = 10, .height = 2 },
        .{ .x = -3, .y = 0, .width = 2, .height = 10 },
        .{ .x = -3, .y = 0, .width = 10, .height = 2, .right = 7, .bottom = 2 },
        .{ .x = 0, .y = -3, .width = 2, .height = 10, .right = 2, .bottom = 7 },
        .{ .x = -1, .y = -1, .width = 20, .height = 20, .right = 16, .bottom = 16 },
        .{
            .x = 14,
            .y = 14,
            .width = 4,
            .height = 4,
            .left = 14,
            .top = 14,
            .right = 16,
            .bottom = 16,
        },
        .{ .x = 16, .y = 0, .width = 2, .height = 10 },
        .{ .x = 0, .y = 16, .width = 10, .height = 2 },
        .{ .x = -2, .y = 0, .width = 2, .height = 10 },
        .{ .x = 0, .y = -2, .width = 10, .height = 2 },
        .{ .x = 4, .y = 4, .width = 0, .height = 4 },
        .{ .x = 4, .y = 4, .width = 4, .height = -1 },
        .{ .x = 1.5, .y = 1.5, .width = 2, .height = 2, .left = 1, .top = 1, .right = 3, .bottom = 3 },
        .{ .x = 1.75, .y = 1.75, .width = 2, .height = 2, .left = 2, .top = 2, .right = 4, .bottom = 4 },
        .{ .x = 5, .y = 2, .width = 2, .height = 3, .angle_radians = std.math.pi / 2.0, .left = 2, .top = 2, .right = 5, .bottom = 4 },
        .{ .x = 1, .y = 2, .width = 2, .height = 3, .angle_radians = std.math.pi / 2.0, .top = 2, .right = 1, .bottom = 4 },
        // Each operand fits i32, but their sum does not. Offscreen geometry must
        // remain a no-op rather than overflow before clipping.
        .{ .x = 1073741824, .y = 1073741824, .width = 1073741824, .height = 1073741824 },
        // Finite f32 bounds can exceed i64. Clip before converting to integers.
        .{ .x = 1e20, .y = 0, .width = 4, .height = 4 },
        .{ .x = -1e20, .y = 0, .width = 4, .height = 4 },
        .{ .x = 0, .y = 1e20, .width = 4, .height = 4 },
        .{ .x = 0, .y = -1e20, .width = 4, .height = 4 },
        .{ .x = 1e20, .y = 0, .width = 4, .height = 4, .angle_radians = std.math.pi / 4.0 },
        // Large intersecting rectangles must still draw their visible portion.
        .{ .x = 4, .y = 2, .width = 1e20, .height = 3, .left = 4, .top = 2, .right = 16, .bottom = 5 },
        .{ .x = 2, .y = 4, .width = 3, .height = 1e20, .left = 2, .top = 4, .right = 5, .bottom = 16 },
        .{ .x = -1e20, .y = -1e20, .width = 2e20, .height = 2e20, .right = 16, .bottom = 16 },
        .{ .x = 0, .y = -1e20, .width = 2e20, .height = 2e20, .angle_radians = std.math.pi / 4.0, .right = 16, .bottom = 16 },
    };

    for (cases) |case| {
        // The trailing pixels detect writes past the framebuffer in fast builds too.
        var pixels: [render_tile_size * render_tile_size + 16]u32 align(tile_alignment) = @splat(0);
        @memset(pixels[render_tile_size * render_tile_size ..], 0x12345678);
        const buffer: FrameBuffer = .{ .width = 16, .height = 16, .data = undefined };

        const rounding: PreparedRectangle.BoundsRounding = if (case.angle_radians == 0) .pixel_centres else .outward;
        if (PreparedRectangle.init(buffer, Renderer.RectangleGeometry.init(case.x, case.y, case.width, case.height, 0, 0, case.angle_radians), rounding)) |rectangle| {
            drawRectangle(pixels[0 .. render_tile_size * render_tile_size], rectangle, PreparedSolidColor.init(.white));
        }

        for (pixels[0 .. render_tile_size * render_tile_size], 0..) |pixel, index| {
            const x = index % render_tile_size;
            const y = index / render_tile_size;
            const expected: u32 = if (x >= case.left and x < case.right and
                y >= case.top and y < case.bottom) 0xffffffff else 0;
            try std.testing.expectEqual(expected, pixel);
        }
        for (pixels[render_tile_size * render_tile_size ..]) |pixel| try std.testing.expectEqual(@as(u32, 0x12345678), pixel);
    }
}

test "textured rectangles clip and exclude ending edges irrespective of texture size" {
    const Case = struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
        angle_radians: f32 = 0,
        texture_width: usize,
        texture_height: usize,
        left: usize = 0,
        top: usize = 0,
        right: usize,
        bottom: usize,
    };
    const cases = [_]Case{
        // Pixel centres lie on both edges: include the start, exclude the end.
        // In f32, (31 / 7) * 7 can round below 31 and admit the ending edge.
        .{ .x = 0.5, .y = 0, .width = 7, .height = 1, .texture_width = 31, .texture_height = 1, .right = 7, .bottom = 1 },
        .{ .x = 0, .y = 0.5, .width = 1, .height = 7, .texture_width = 1, .texture_height = 31, .right = 1, .bottom = 7 },
        .{ .x = 1.5, .y = 1.5, .width = 7, .height = 7, .texture_width = 31, .texture_height = 31, .left = 1, .top = 1, .right = 8, .bottom = 8 },
        // A different scale also exercises the boundary with optimized math.
        .{ .x = 0.5, .y = 0, .width = 41, .height = 1, .texture_width = 1, .texture_height = 1, .right = 41, .bottom = 1 },
        .{ .x = 0, .y = 0.5, .width = 1, .height = 41, .texture_width = 1, .texture_height = 1, .right = 1, .bottom = 41 },
        // Clipping preserves the original local coordinates and ending edges.
        .{ .x = -3.5, .y = -3.5, .width = 7, .height = 7, .texture_width = 31, .texture_height = 31, .right = 3, .bottom = 3 },
        // Centres strictly inside the rectangle must remain covered.
        .{ .x = 1, .y = 1, .width = 7, .height = 7, .texture_width = 31, .texture_height = 31, .left = 1, .top = 1, .right = 8, .bottom = 8 },
        .{ .x = 1.75, .y = 1.75, .width = 7, .height = 7, .texture_width = 31, .texture_height = 31, .left = 2, .top = 2, .right = 9, .bottom = 9 },
        // Preparation rejects empty or negative destination sizes.
        .{ .x = 0, .y = 0, .width = 0, .height = 7, .texture_width = 1, .texture_height = 1, .right = 0, .bottom = 0 },
        .{ .x = 0, .y = 0, .width = 7, .height = 0, .texture_width = 1, .texture_height = 1, .right = 0, .bottom = 0 },
        .{ .x = 0, .y = 0, .width = -1, .height = 7, .texture_width = 1, .texture_height = 1, .right = 0, .bottom = 0 },
        .{ .x = 0, .y = 0, .width = 7, .height = -1, .texture_width = 1, .texture_height = 1, .right = 0, .bottom = 0 },
        // Empty textures remain a no-op when coverage is checked in local space.
        .{ .x = 0, .y = 0, .width = 7, .height = 7, .texture_width = 0, .texture_height = 1, .right = 0, .bottom = 0 },
        .{ .x = 0, .y = 0, .width = 7, .height = 7, .texture_width = 1, .texture_height = 0, .right = 0, .bottom = 0 },
        // Finite bounds outside i64 must be clipped before integer conversion.
        .{ .x = 1e20, .y = 0, .width = 4, .height = 4, .texture_width = 1, .texture_height = 1, .right = 0, .bottom = 0 },
        .{ .x = -1e20, .y = 0, .width = 4, .height = 4, .texture_width = 1, .texture_height = 1, .right = 0, .bottom = 0 },
        .{ .x = 0, .y = 1e20, .width = 4, .height = 4, .texture_width = 1, .texture_height = 1, .right = 0, .bottom = 0 },
        .{ .x = 0, .y = -1e20, .width = 4, .height = 4, .texture_width = 1, .texture_height = 1, .right = 0, .bottom = 0 },
        .{ .x = 1e20, .y = 0, .width = 4, .height = 4, .angle_radians = std.math.pi / 4.0, .texture_width = 1, .texture_height = 1, .right = 0, .bottom = 0 },
        // Intersecting rectangles retain their visible portion, including rotation.
        .{ .x = 4, .y = 2, .width = 1e20, .height = 3, .texture_width = 1, .texture_height = 1, .left = 4, .top = 2, .right = 48, .bottom = 5 },
        .{ .x = 2, .y = 4, .width = 3, .height = 1e20, .texture_width = 1, .texture_height = 1, .left = 2, .top = 4, .right = 5, .bottom = 48 },
        .{ .x = -1e20, .y = -1e20, .width = 2e20, .height = 2e20, .texture_width = 1, .texture_height = 1, .right = 48, .bottom = 48 },
        .{ .x = 0, .y = -1e20, .width = 2e20, .height = 2e20, .angle_radians = std.math.pi / 4.0, .texture_width = 1, .texture_height = 1, .right = 48, .bottom = 48 },
    };
    var texels: [31 * 31]u32 = @splat(0xffffffff);

    for (cases) |case| {
        for ([_]bool{ false, true }) |direct_tile| {
            if (direct_tile) {
                if (case.angle_radians != 0) continue;
            }
            var pixels: [render_tile_size * render_tile_size + 16]u32 align(tile_alignment) = @splat(0);
            @memset(pixels[render_tile_size * render_tile_size ..], 0x12345678);
            const buffer: FrameBuffer = .{ .width = 48, .height = 48, .data = undefined };
            const texture: Bitmap = .{
                .width = @intCast(case.texture_width),
                .height = @intCast(case.texture_height),
                .pixels = texels[0 .. case.texture_width * case.texture_height],
            };

            if (PreparedRectangle.init(buffer, Renderer.RectangleGeometry.init(case.x, case.y, case.width, case.height, 0, 0, case.angle_radians), .outward)) |rectangle| {
                const texels_per_pixel_x = @as(f32, @floatFromInt(texture.width)) / rectangle.width;
                const texels_per_pixel_y = @as(f32, @floatFromInt(texture.height)) / rectangle.height;
                if (direct_tile) {
                    drawSprite(pixels[0 .. render_tile_size * render_tile_size], PreparedSprite.fromRectangle(rectangle), texture, texels_per_pixel_x, texels_per_pixel_y);
                } else {
                    drawTexturedRectangle(pixels[0 .. render_tile_size * render_tile_size], rectangle, texture, texels_per_pixel_x, texels_per_pixel_y, LinearColor.init(.white));
                }
            }

            for (pixels[0 .. render_tile_size * render_tile_size], 0..) |pixel, index| {
                const x = index % render_tile_size;
                const y = index / render_tile_size;
                const expected: u32 = if (x >= case.left and x < case.right and
                    y >= case.top and y < case.bottom) 0xffffffff else 0;
                try std.testing.expectEqual(expected, pixel);
            }
            for (pixels[render_tile_size * render_tile_size ..]) |pixel| try std.testing.expectEqual(@as(u32, 0x12345678), pixel);
        }
    }
}

test "opaque rotated rectangles overwrite only covered pixels" {
    const buffer: FrameBuffer = .{ .width = 64, .height = 64, .data = undefined };
    const color: Color = .{ .r = 0.1, .g = 0.4, .b = 0.8, .a = 1 };
    const expected_color = color.toARGB();
    for ([_]f32{ 0.2, -0.7, std.math.pi / 4.0 }) |angle| {
        const rectangle = PreparedRectangle.init(buffer, Renderer.RectangleGeometry.init(32, 32, 60, 3, 0.5, 0.5, angle), .outward).?;
        try std.testing.expectEqual(PreparedRectangle.Coverage.partial, rectangle.classifyCoverage());
        for ([_]u32{ 0x12345678, 0xffabcdef }) |background| {
            var pixels: Tile align(tile_alignment) = @splat(background);
            drawRectangle(&pixels, rectangle, PreparedSolidColor.init(color));
            var covered: usize = 0;
            for (pixels, 0..) |pixel, index| {
                const x = @as(f32, @floatFromInt(index % render_tile_size)) + 0.5;
                const y = @as(f32, @floatFromInt(index / render_tile_size)) + 0.5;
                const inside = rectangle.coveredPosition(x, y) != null;
                if (inside) covered += 1;
                try std.testing.expectEqual(if (inside) expected_color else background, pixel);
            }
            try std.testing.expect(covered > 0 and covered < pixels.len);
        }
    }
}

test "rotated rectangles blend only covered pixel centres" {
    var pixels: Tile align(tile_alignment) = @splat(0xff0000ff);
    const buffer: FrameBuffer = .{ .width = 8, .height = 8, .data = undefined };
    const rectangle = PreparedRectangle.init(buffer, Renderer.RectangleGeometry.init(4, 1.25, 3, 3, 0, 0, std.math.pi / 4.0), .outward).?;
    drawRectangle(&pixels, rectangle, PreparedSolidColor.init(.{ .r = 1, .g = 0, .b = 0, .a = 0.5 }));

    // A 45-degree square forms a diamond. These pixel centres are strictly
    // inside it; the other pixels in its bounding box must remain blue.
    const coverage = [_][]const u8{
        "........",
        "........",
        "...##...",
        "..####..",
        "...##...",
        "........",
        "........",
        "........",
    };
    for (pixels, 0..) |pixel, index| {
        const x = index % render_tile_size;
        const y = index / render_tile_size;
        const expected: u32 = if (x < 8 and y < 8 and coverage[y][x] == '#') 0xffb400b4 else 0xff0000ff;
        try std.testing.expectEqual(expected, pixel);
    }
}
